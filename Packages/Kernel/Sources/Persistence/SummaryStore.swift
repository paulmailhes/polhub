import Domain
import Foundation
import GRDB

public enum SummaryState: String, Codable, Sendable {
    case queued, running, done, failed
}

/// How a meeting's summary went: one row per meeting (14/11).
public struct SummaryJobRow: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "summary_job"
    public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy { .lowercaseString }

    public var meetingID: UUID
    public var state: SummaryState
    public var attempts: Int
    public var error: String?
    /// The transcription it was made from: a newer one asks for a new summary.
    public var sourceTranscribedAt: Date?
    public var updatedAt: Date

    public init(meetingID: UUID, state: SummaryState, attempts: Int = 0, error: String? = nil, sourceTranscribedAt: Date? = nil, updatedAt: Date) {
        self.meetingID = meetingID
        self.state = state
        self.attempts = attempts
        self.error = error
        self.sourceTranscribedAt = sourceTranscribedAt
        self.updatedAt = updatedAt
    }
}

/// The summaries' queue in the base: what waits, what runs, what was written.
public struct SummaryStore: Sendable {
    public static let automaticAttempts = 2

    public let database: AppDatabase
    private var writer: any DatabaseWriter { database.writer }

    public init(_ database: AppDatabase) {
        self.database = database
    }

    private static func key(_ id: UUID) -> String { id.uuidString.lowercased() }

    /// The newest transcribed meeting that has words and no summary of its current transcription: never
    /// an imported one, nor one in the Trash, nor one that failed twice, nor one that already has a summary
    /// from elsewhere (the vault's, merged at the history import: review of 14/11) unless Paul asks.
    public func nextPending() throws -> UUID? {
        try writer.read { db in
            try String.fetchOne(db, sql: """
                SELECT meeting.id FROM meeting LEFT JOIN summary_job AS job ON job.meetingID = meeting.id
                WHERE meeting.deletedAt IS NULL AND meeting.source != 'imported' AND meeting.transcribedAt IS NOT NULL
                  AND EXISTS (SELECT 1 FROM utterance WHERE utterance.meetingID = meeting.id)
                  AND ((job.meetingID IS NULL AND meeting.summary IS NULL) OR job.state = 'queued'
                       OR (job.state IN ('done', 'failed') AND job.sourceTranscribedAt < meeting.transcribedAt))
                ORDER BY meeting.startedAt DESC LIMIT 1
                """)
        }.flatMap(UUID.init(uuidString:))
    }

    public func job(meetingID: UUID) throws -> SummaryJobRow? {
        try writer.read { try SummaryJobRow.fetchOne($0, key: ["meetingID": Self.key(meetingID)]) }
    }

    /// The summary starts from the meeting's current transcription.
    public func start(meetingID: UUID, at date: Date) throws {
        try writer.write { db in
            let transcribed = try Date.fetchOne(db, sql: "SELECT transcribedAt FROM meeting WHERE id = ?", arguments: [Self.key(meetingID)])
            var job = try SummaryJobRow.fetchOne(db, key: ["meetingID": Self.key(meetingID)]) ?? SummaryJobRow(meetingID: meetingID, state: .queued, updatedAt: date)
            if job.sourceTranscribedAt != transcribed, job.state != .queued { job.attempts = 0 }
            job.state = .running
            job.error = nil
            job.sourceTranscribedAt = transcribed
            job.updatedAt = date
            try job.save(db)
        }
    }

    /// The summary is written: its text on the meeting, its actions on the meeting (not in a project: Paul
    /// adds the ones he wants).
    public func finish(meetingID: UUID, summary: String?, actions: [ActionRow], at date: Date) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE meeting SET summary = ? WHERE id = ?", arguments: [summary, Self.key(meetingID)])
            // An action found again keeps its row (ticked, put in a project, its place); the untouched ones that are
            // gone leave; the new ones come in (review of 14/11).
            let existing = try ActionRow.filter(Column("meetingID") == Self.key(meetingID)).fetchAll(db)
            let fresh = Set(actions.map { Self.fold($0.text) })
            for row in existing where row.projectID == nil && !row.done && !fresh.contains(Self.fold(row.text)) {
                _ = try row.delete(db)
            }
            let known = Set(existing.map { Self.fold($0.text) })
            var position = (existing.map(\.position).max() ?? -1) + 1
            for var action in actions where !known.contains(Self.fold(action.text)) {
                action.meetingID = meetingID
                action.projectID = nil
                action.position = position
                position += 1
                try action.insert(db)
            }
            try update(db, meetingID, at: date) { $0.state = .done; $0.error = nil }
        }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR")).trimmingCharacters(in: .whitespacesAndNewlines)
    }


    /// A failure counts; after the second one, the summary waits for Paul's « Refaire ».
    public func fail(meetingID: UUID, error: String, at date: Date) throws {
        try writer.write { db in
            try update(db, meetingID, at: date) { job in
                job.attempts += 1
                job.error = error
                job.state = job.attempts >= Self.automaticAttempts ? .failed : .queued
            }
        }
    }

    /// Stopped by a meeting: back to the queue, without counting as a failure.
    public func stopped(meetingID: UUID, at date: Date) throws {
        try writer.write { db in try update(db, meetingID, at: date) { $0.state = .queued } }
    }

    /// « Refaire le compte rendu ».
    public func redo(meetingID: UUID, at date: Date) throws {
        try writer.write { db in
            var job = try SummaryJobRow.fetchOne(db, key: ["meetingID": Self.key(meetingID)]) ?? SummaryJobRow(meetingID: meetingID, state: .queued, updatedAt: date)
            job.state = .queued
            job.attempts = 0
            job.error = nil
            job.updatedAt = date
            try job.save(db)
        }
    }

    /// At launch: what was running goes back to the queue. Returns how many.
    @discardableResult
    public func resetRunning(at date: Date) throws -> Int {
        try writer.write { db in
            try SummaryJobRow.filter(Column("state") == SummaryState.running.rawValue)
                .updateAll(db, Column("state").set(to: SummaryState.queued.rawValue), Column("updatedAt").set(to: date))
        }
    }

    public func observeJob(meetingID: UUID, onChange: @escaping @MainActor @Sendable (SummaryJobRow?) -> Void) -> AnyDatabaseCancellable {
        let key = Self.key(meetingID)
        return ValueObservation
            .tracking { try SummaryJobRow.fetchOne($0, key: ["meetingID": key]) }
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { job in
                MainActor.assumeIsolated { onChange(job) }
            })
    }

    private func update(_ db: Database, _ meetingID: UUID, at date: Date, _ change: (inout SummaryJobRow) -> Void) throws {
        var job = try SummaryJobRow.fetchOne(db, key: ["meetingID": Self.key(meetingID)]) ?? SummaryJobRow(meetingID: meetingID, state: .queued, updatedAt: date)
        change(&job)
        job.updatedAt = date
        try job.save(db)
    }
}
