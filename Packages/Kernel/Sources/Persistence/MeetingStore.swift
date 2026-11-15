import Domain
import Foundation
import GRDB

/// Every read and write of the base goes through here.
public struct MeetingStore: Sendable {
    public let database: AppDatabase
    private var writer: any DatabaseWriter { database.writer }

    public init(_ database: AppDatabase) {
        self.database = database
    }

    private static func key(_ id: UUID) -> String { id.uuidString.lowercased() }

    /// Every column but the project: `setProject` alone files a meeting, so the coordinator's copy of a
    /// meeting being recorded never undoes a filing (review of the projects module, Important 3).
    public func save(_ row: MeetingRow) throws {
        try writer.write { db in
            if try row.exists(db) {
                let columns = try db.columns(in: MeetingRow.databaseTableName).map(\.name).filter { $0 != "projectID" }
                try row.update(db, columns: columns)
            } else {
                try row.insert(db)
            }
        }
    }

    // MARK: - Summaries and imported meetings (base v4)

    public func setSummary(meetingID: UUID, summary: String?) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE meeting SET summary = ? WHERE id = ?", arguments: [summary, Self.key(meetingID)])
        }
    }

    public func summary(meetingID: UUID) throws -> String? {
        try writer.read { try String.fetchOne($0, sql: "SELECT summary FROM meeting WHERE id = ?", arguments: [Self.key(meetingID)]) }
    }

    /// A meeting of the vault: created, or updated when its note was imported before.
    public func saveImported(_ row: MeetingRow, importedFrom: String, googleEventID: String?, summary: String?) throws {
        try writer.write { db in
            if try row.exists(db) { try row.update(db) } else { try row.insert(db) }
            try db.execute(sql: "UPDATE meeting SET importedFrom = ?, googleEventID = ?, summary = ? WHERE id = ?",
                           arguments: [importedFrom, googleEventID, summary, Self.key(row.id)])
        }
    }

    public func setGoogleEventID(meetingID: UUID, eventID: String?) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE meeting SET googleEventID = ? WHERE id = ?", arguments: [eventID, Self.key(meetingID)])
        }
    }

    public func googleEventID(meetingID: UUID) throws -> String? {
        try writer.read { try String.fetchOne($0, sql: "SELECT googleEventID FROM meeting WHERE id = ?", arguments: [Self.key(meetingID)]) }
    }

    public func importedMeeting(from note: String) throws -> MeetingRow? {
        try writer.read { try MeetingRow.fetchOne($0, sql: "SELECT * FROM meeting WHERE importedFrom = ?", arguments: [note]) }
    }

    public func meeting(googleEventID: String) throws -> MeetingRow? {
        try writer.read { try MeetingRow.fetchOne($0, sql: "SELECT * FROM meeting WHERE googleEventID = ? AND deletedAt IS NULL", arguments: [googleEventID]) }
    }

    /// A better title, from the calendar, for a meeting whose title came from the tab.
    public func setTitle(meetingID: UUID, title: String) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE meeting SET title = ? WHERE id = ?", arguments: [title, Self.key(meetingID)])
        }
    }

    public func meeting(id: UUID) throws -> MeetingRow? {
        try writer.read { try MeetingRow.filter(Column("id") == Self.key(id)).fetchOne($0) }
    }

    /// Meetings the app may still be recording, or must close after a crash.
    public func unfinished() throws -> [MeetingRow] {
        try writer.read { db in
            try MeetingRow
                .filter([MeetingStatus.pending, .recording, .presumedEnded].map(\.rawValue).contains(Column("status")))
                .filter(Column("deletedAt") == nil)
                .order(Column("startedAt"))
                .fetchAll(db)
        }
    }

    public func recent(limit: Int) throws -> [MeetingRow] {
        try writer.read { try Self.recentRequest(limit: limit).fetchAll($0) }
    }

    private static func recentRequest(limit: Int) -> QueryInterfaceRequest<MeetingRow> {
        MeetingRow
            .filter(Column("deletedAt") == nil)
            .order(Column("startedAt").desc)
            .limit(limit)
    }

    public func softDelete(id: UUID, at date: Date) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE meeting SET deletedAt = ?, updatedAt = ? WHERE id = ?",
                arguments: [date, date, Self.key(id)]
            )
        }
    }

    public func addJournal(_ entry: JournalEntry) throws {
        try writer.write { try entry.insert($0) }
    }

    public func journal(limit: Int) throws -> [JournalEntry] {
        try writer.read { try JournalEntry.order(Column("createdAt").desc).limit(limit).fetchAll($0) }
    }

    /// A meeting of that Meet code started in that span, whatever became of it (ended, declined at the prompt,
    /// in the Trash): the notifications' « non enregistrée » is then wrong (14/11).
    public func anyMeeting(code: String, from: Date, to: Date) throws -> Bool {
        try writer.read { db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM meeting WHERE meetCode = ? AND startedAt >= ? AND startedAt <= ?)",
                              arguments: [code, from, to]) ?? false
        }
    }

    public func neverCodes() throws -> Set<String> {
        try writer.read { try String.fetchSet($0, sql: "SELECT code FROM never_link") }
    }

    public func addNeverCode(_ code: String, at date: Date) throws {
        try writer.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO never_link (code, createdAt) VALUES (?, ?)", arguments: [code, date])
        }
    }

    public func addMemorySample(_ sample: MemorySample) throws {
        var sample = sample
        try writer.write { try sample.insert($0) }
    }

    public func memorySampleCount() throws -> Int {
        try writer.read { try MemorySample.fetchCount($0) }
    }

    /// Calls `onChange` on the main queue with the latest journal entries, now and after every change.
    public func observeJournal(limit: Int, onChange: @escaping @MainActor @Sendable ([JournalEntry]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { try JournalEntry.order(Column("createdAt").desc).limit(limit).fetchAll($0) }
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { entries in
                MainActor.assumeIsolated { onChange(entries) }
            })
    }

    /// The summaries of the latest meetings, each reduced by `digest` (its first lines, for the list: 15/11), on
    /// the main queue, now and after every change. Read apart: the summary stays outside `MeetingRow`.
    public func observeSummaries(limit: Int, digest: @escaping @Sendable (String) -> String?,
                                 onChange: @escaping @MainActor @Sendable ([UUID: String]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { db in
                var digests: [UUID: String] = [:]
                let rows = try Row.fetchAll(db, sql: """
                    SELECT id, summary FROM meeting WHERE deletedAt IS NULL AND summary IS NOT NULL AND summary != ''
                    ORDER BY startedAt DESC LIMIT ?
                    """, arguments: [limit])
                for row in rows {
                    guard let id = UUID(uuidString: row["id"]), let text = digest(row["summary"]) else { continue }
                    digests[id] = text
                }
                return digests
            }
            .removeDuplicates()
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { digests in
                MainActor.assumeIsolated { onChange(digests) }
            })
    }

    /// Calls `onChange` on the main queue with the latest meetings, now and after every change.
    public func observeRecent(limit: Int, onChange: @escaping @MainActor @Sendable ([MeetingRow]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { try Self.recentRequest(limit: limit).fetchAll($0) }
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { rows in
                MainActor.assumeIsolated { onChange(rows) }
            })
    }
}
