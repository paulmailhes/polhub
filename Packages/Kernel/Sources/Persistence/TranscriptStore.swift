import Domain
import Foundation
import GRDB

/// The work queue and the dialogue lines of step 2.
public struct TranscriptStore: Sendable {
    public let database: AppDatabase
    private var writer: any DatabaseWriter { database.writer }

    public init(_ database: AppDatabase) {
        self.database = database
    }

    private static func key(_ id: UUID) -> String { id.uuidString.lowercased() }

    // MARK: - Jobs

    /// Queues a transcription. An unfinished job of the same meeting is replaced: only one runs per meeting.
    @discardableResult
    public func enqueue(meetingID: UUID, language: String?, at date: Date) throws -> JobRow {
        try writer.write { db in
            try JobRow
                .filter(Column("meetingID") == Self.key(meetingID))
                .filter([JobState.queued.rawValue, JobState.running.rawValue, JobState.failed.rawValue].contains(Column("state")))
                .deleteAll(db)
            let job = JobRow(meetingID: meetingID, language: language, createdAt: date)
            try job.insert(db)
            return job
        }
    }

    /// The oldest queued job of a meeting that is not in the Trash.
    public func nextQueued() throws -> JobRow? {
        try writer.read { db in
            try JobRow.fetchOne(db, sql: """
                SELECT job.* FROM job JOIN meeting ON meeting.id = job.meetingID
                WHERE job.state = ? AND meeting.deletedAt IS NULL
                ORDER BY job.createdAt LIMIT 1
                """, arguments: [JobState.queued.rawValue])
        }
    }

    public func save(_ job: JobRow) throws {
        try writer.write { try job.save($0) }
    }

    /// Every job of a meeting, newest first.
    public func jobs(for meetingID: UUID) throws -> [JobRow] {
        try writer.read { db in
            try JobRow.filter(Column("meetingID") == Self.key(meetingID)).order(Column("createdAt").desc).fetchAll(db)
        }
    }

    /// The newest job of a meeting.
    public func job(for meetingID: UUID) throws -> JobRow? {
        try jobs(for: meetingID).first
    }

    /// The newest job of each of these meetings.
    public func latestJobs() throws -> [UUID: JobRow] {
        let all = try writer.read { try JobRow.order(Column("createdAt")).fetchAll($0) }
        return Dictionary(all.map { ($0.meetingID, $0) }, uniquingKeysWith: { _, newer in newer })
    }

    /// After a crash or a stop: what was running goes back to the queue. Returns how many.
    @discardableResult
    public func resetRunning(at date: Date) throws -> Int {
        try writer.write { db in
            try JobRow.filter(Column("state") == JobState.running.rawValue)
                .updateAll(db, Column("state").set(to: JobState.queued.rawValue), Column("updatedAt").set(to: date))
        }
    }

    /// Ended or interrupted meetings, not deleted, not transcribed, with no job yet.
    public func meetingsAwaitingTranscription() throws -> [MeetingRow] {
        try writer.read { db in
            try MeetingRow.fetchAll(db, sql: """
                SELECT meeting.* FROM meeting
                WHERE status IN (?, ?) AND deletedAt IS NULL AND transcribedAt IS NULL
                  AND NOT EXISTS (SELECT 1 FROM job WHERE job.meetingID = meeting.id)
                ORDER BY startedAt
                """, arguments: [MeetingStatus.ended.rawValue, MeetingStatus.interrupted.rawValue])
        }
    }

    /// Calls `onChange` on the main queue with the newest job of the meeting, now and after every change.
    public func observeJob(meetingID: UUID, onChange: @escaping @MainActor @Sendable (JobRow?) -> Void) -> AnyDatabaseCancellable {
        let key = Self.key(meetingID)
        return ValueObservation
            .tracking { try JobRow.filter(Column("meetingID") == key).order(Column("createdAt").desc).fetchOne($0) }
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { job in
                MainActor.assumeIsolated { onChange(job) }
            })
    }

    /// Calls `onChange` on the main queue with the newest job of every meeting, now and after every change.
    public func observeLatestJobs(onChange: @escaping @MainActor @Sendable ([UUID: JobRow]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { try JobRow.order(Column("createdAt")).fetchAll($0) }
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { jobs in
                let latest = Dictionary(jobs.map { ($0.meetingID, $0) }, uniquingKeysWith: { _, newer in newer })
                MainActor.assumeIsolated { onChange(latest) }
            })
    }

    // MARK: - Lines

    /// Replaces the whole dialogue of a meeting, in one transaction.
    public func replaceUtterances(meetingID: UUID, _ lines: [UtteranceRow]) throws {
        try writer.write { db in
            try UtteranceRow.filter(Column("meetingID") == Self.key(meetingID)).deleteAll(db)
            for var line in lines {
                line.id = nil
                try line.insert(db)
            }
        }
    }

    public func utterances(meetingID: UUID) throws -> [UtteranceRow] {
        try writer.read { db in
            try UtteranceRow.filter(Column("meetingID") == Self.key(meetingID)).order(Column("startMs")).fetchAll(db)
        }
    }

    /// Calls `onChange` on the main queue with the dialogue of the meeting, now and after every change.
    public func observeUtterances(meetingID: UUID, onChange: @escaping @MainActor @Sendable ([UtteranceRow]) -> Void) -> AnyDatabaseCancellable {
        let key = Self.key(meetingID)
        return ValueObservation
            .tracking { try UtteranceRow.filter(Column("meetingID") == key).order(Column("startMs")).fetchAll($0) }
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { lines in
                MainActor.assumeIsolated { onChange(lines) }
            })
    }

    // MARK: - Search

    /// Lines whose words start with every word of `text`, accents and case ignored, newest meetings first.
    public func search(_ text: String, limit: Int) throws -> [SearchHit] {
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: text) else { return [] }
        return try writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT utterance.meetingID, utterance.startMs, utterance.speaker, meeting.title, meeting.startedAt,
                       snippet(utterance_ft, 0, '«', '»', '…', 12) AS excerpt
                FROM utterance_ft
                JOIN utterance ON utterance.id = utterance_ft.rowid
                JOIN meeting ON meeting.id = utterance.meetingID
                WHERE utterance_ft MATCH ? AND meeting.deletedAt IS NULL
                ORDER BY meeting.startedAt DESC, utterance.startMs
                LIMIT ?
                """, arguments: [pattern, limit]).compactMap { row in
                guard let id = UUID(uuidString: row["meetingID"]), let speaker = Speaker(rawValue: row["speaker"]) else { return nil }
                return SearchHit(
                    meetingID: id, title: row["title"], startedAt: row["startedAt"], startMs: row["startMs"],
                    speaker: speaker, excerpt: row["excerpt"]
                )
            }
        }
    }
}
