import Foundation
import GRDB

/// The app's SQLite base. Readable from outside (`sqlite3`, Claude Code): text identifiers, ISO dates.
/// Tables are created when a step needs them; step 1 needs the four of migration `v1`.
public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(path: String) throws {
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true
        )
        // WAL: the command line and Claude Code read while the app writes, and never make it fail.
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        writer = try DatabasePool(path: path, configuration: configuration)
        try Self.migrator.migrate(writer)
    }

    private init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// For the command line and Claude Code: never writes, never migrates, waits up to 5 s for the app's
    /// writes. The base must already be at the app's version.
    public static func readOnly(path: String) throws -> AppDatabase {
        var configuration = Configuration()
        configuration.readonly = true
        configuration.busyMode = .timeout(5)
        return AppDatabase(unmigrated: try DatabasePool(path: path, configuration: configuration))
    }

    /// For `polhub mcp`, whose project tools write (13/11): reads and writes, waits up to 5 s for the app,
    /// and never migrates — only the app does. The base must already be at the app's version.
    public static func forTools(path: String) throws -> AppDatabase {
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        return AppDatabase(unmigrated: try DatabasePool(path: path, configuration: configuration))
    }

    /// For the command line's reading: read-only when the app runs; when it is closed, SQLite has removed
    /// the base's `-shm` and a read-only opening fails, so the base opens for writing — never migrated,
    /// and nothing is written (13/11).
    public static func forReading(path: String) throws -> AppDatabase {
        if let base = try? readOnly(path: path), (try? base.writer.read { try $0.tableExists("meeting") }) != nil {
            return base
        }
        return try forTools(path: path)
    }

    /// Whether the base has the project tables (migration `v3`).
    public func hasProjects() throws -> Bool {
        try writer.read { try $0.tableExists("project") && $0.tableExists("project_journal") }
    }

    /// Another process (`polhub mcp`) wrote in the base: the app's observations fetch again.
    public func notifyExternalChanges() throws {
        try writer.write { try $0.notifyChanges(in: .fullDatabase) }
    }

    /// Whether the base has the tables of step 2: a base left by an older app does not.
    public func isAtStep2() throws -> Bool {
        try writer.read { try $0.tableExists("job") && $0.tableExists("utterance") }
    }

    private init(unmigrated writer: any DatabaseWriter) {
        self.writer = writer
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(writer: DatabaseQueue())
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "meeting") { t in
                t.primaryKey("id", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
                t.column("status", .text).notNull()
                t.column("source", .text).notNull()
                t.column("candidateKey", .text).notNull()
                t.column("tabID", .text)
                t.column("meetCode", .text)
                t.column("authUser", .text)
                t.column("tabTitle", .text)
                t.column("title", .text).notNull()
                t.column("startedAt", .datetime).notNull().indexed()
                t.column("presumedEndAt", .datetime)
                t.column("endedAt", .datetime)
                t.column("endReason", .text)
                t.column("healthJSON", .text)
                t.column("transcribedAt", .datetime)
                t.column("audioPurgedAt", .datetime)
            }
            try db.create(table: "journal_entry") { t in
                t.primaryKey("id", .text)
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("kind", .text).notNull()
                t.column("message", .text).notNull()
                t.column("meetingID", .text)
            }
            try db.create(table: "memory_sample") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("at", .datetime).notNull()
                t.column("pressure", .text).notNull()
                for column in ["freeBytes", "activeBytes", "inactiveBytes", "wiredBytes", "compressedBytes", "swapUsedBytes"] {
                    t.column(column, .integer).notNull()
                }
            }
            try db.create(table: "never_link") { t in
                t.primaryKey("code", .text)
                t.column("createdAt", .datetime).notNull()
            }
        }
        // Step 2: the work queue, the dialogue lines and their full-text index.
        migrator.registerMigration("v2") { db in
            try db.create(table: "job") { t in
                t.primaryKey("id", .text)
                t.column("meetingID", .text).notNull().indexed().references("meeting", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("state", .text).notNull()
                t.column("language", .text)
                t.column("attempts", .integer).notNull()
                t.column("error", .text)
                t.column("progress", .double).notNull()
                t.column("doubtful", .boolean).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("startedAt", .datetime)
                t.column("finishedAt", .datetime)
            }
            try db.create(table: "utterance") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("meetingID", .text).notNull().references("meeting", onDelete: .cascade)
                t.column("speaker", .text).notNull()
                t.column("startMs", .integer).notNull()
                t.column("endMs", .integer).notNull()
                t.column("text", .text).notNull()
                t.column("doubtful", .boolean).notNull()
            }
            try db.create(index: "utterance_on_meeting_start", on: "utterance", columns: ["meetingID", "startMs"])
            try db.create(virtualTable: "utterance_ft", using: FTS5()) { t in
                t.synchronize(withTable: "utterance")
                t.tokenizer = .unicode61(diacritics: .remove)
                t.column("text")
            }
        }
        // Projects and kanban: the projects, their actions and journal, and the project of a meeting.
        migrator.registerMigration("v3") { db in
            try db.create(table: "project") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("status", .text).notNull().indexed()
                t.column("client", .text)
                t.column("dueDate", .datetime)
                t.column("todo", .text)
                t.column("icon", .text)
                t.column("color", .text)
                t.column("contacts", .text).notNull()
                t.column("createdOn", .datetime)
                t.column("codeFolder", .text)
                t.column("github", .text)
                t.column("notion", .text)
                t.column("lastActivity", .datetime)
                t.column("lastMeetingImported", .datetime)
                t.column("noteModifiedAt", .datetime)
                t.column("lastEditedAt", .datetime)
                t.column("notes", .text).notNull()
                t.column("kanbanOrder", .double).notNull()
                t.column("importedFrom", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }
            try db.create(table: "action") { t in
                t.primaryKey("id", .text)
                t.column("projectID", .text).indexed().references("project", onDelete: .setNull)
                t.column("meetingID", .text).indexed().references("meeting", onDelete: .cascade)
                t.column("text", .text).notNull()
                t.column("done", .boolean).notNull()
                t.column("addedOn", .datetime)
                t.column("dueDate", .datetime)
                t.column("owner", .text)
                t.column("position", .double).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "project_journal") { t in
                t.primaryKey("id", .text)
                t.column("projectID", .text).notNull().indexed().references("project", onDelete: .cascade)
                t.column("date", .datetime).notNull()
                t.column("title", .text).notNull()
                t.column("body", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.alter(table: "meeting") { t in
                t.add(column: "projectID", .text).references("project", onDelete: .setNull)
            }
        }
        return migrator
    }
}
