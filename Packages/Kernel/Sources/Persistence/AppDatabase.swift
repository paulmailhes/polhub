import Foundation
import GRDB

public enum AppDatabaseError: Error, LocalizedError, Equatable {
    /// The base holds migrations this version of the app does not know.
    case newerBase

    public var errorDescription: String? {
        switch self {
        case .newerBase: "La base vient d'une version plus récente de Polhub : installe la dernière version pour l'ouvrir."
        }
    }
}

/// The app's SQLite base. Readable from outside (`sqlite3`, Claude Code): text identifiers, ISO dates.
/// Tables are created when a step needs them; step 1 needs the four of migration `v1`.
public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(path: String) throws {
        let folder = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let existed = FileManager.default.fileExists(atPath: path)
        // WAL: the command line and Claude Code read while the app writes, and never make it fail.
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        writer = try DatabasePool(path: path, configuration: configuration)
        if existed {
            try Self.protect(writer, backups: folder.appending(path: "Sauvegardes", directoryHint: .isDirectory), now: Date())
        }
        try Self.migrator.migrate(writer)
    }

    /// Before any migration of a base that already holds Paul's data (review of 15/11): a base left by a newer
    /// Polhub is refused, never read with the wrong meanings; a base about to change gets a copy first, named
    /// after the first migration it is about to get.
    static func protect(_ writer: any DatabaseWriter, backups: URL, now: Date,
                        copy: (any DatabaseWriter, String) throws -> Void = { writer, path in try writer.backup(to: DatabaseQueue(path: path)) }) throws {
        let migrator = Self.migrator
        let (superseded, applied) = try writer.read { db in
            (try migrator.hasBeenSuperseded(db), try migrator.appliedIdentifiers(db))
        }
        if superseded { throw AppDatabaseError.newerBase }
        guard let pending = migrator.migrations.first(where: { !applied.contains($0) }), !applied.isEmpty else { return }
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let target = backups.appending(path: backupName(before: pending, on: now))
        // A copy of the same day is already the base before this migration: it stays.
        guard !FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) else { return }
        // Written under another name, then renamed: a copy that failed on the way (a full disk, Polhub stopped)
        // never passes for the copy at the next opening (correctifs, 15/11).
        let partial = backups.appending(path: target.lastPathComponent + ".partiel")
        let manager = FileManager.default
        func removePartial() {
            for suffix in ["", "-journal", "-wal", "-shm"] {
                try? manager.removeItem(atPath: partial.path(percentEncoded: false) + suffix)
            }
        }
        removePartial()
        do {
            try copy(writer, partial.path(percentEncoded: false))
            try manager.moveItem(at: partial, to: target)
        } catch {
            removePartial()
            throw error
        }
    }

    /// `Polhub-avant-v12-20261115.sqlite`.
    public static func backupName(before migration: String, on date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return "Polhub-avant-\(migration)-\(formatter.string(from: date)).sqlite"
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
        // Contacts, calendars, the vault's old meetings (13/11).
        migrator.registerMigration("v4") { db in
            try db.create(table: "contact") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("email", .text)
                t.column("company", .text)
                t.column("phone", .text)
                t.column("notes", .text).notNull()
                t.column("importedFrom", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }
            try db.create(index: "contact_on_email", on: "contact", columns: ["email"], unique: true, condition: Column("email") != nil)
            try db.create(table: "contact_project") { t in
                t.column("contactID", .text).notNull().indexed().references("contact", onDelete: .cascade)
                t.column("projectID", .text).notNull().indexed().references("project", onDelete: .cascade)
                t.column("origin", .text).notNull()
                t.column("excluded", .boolean).notNull()
                t.column("createdAt", .datetime).notNull()
                t.primaryKey(["contactID", "projectID"])
            }
            try db.create(table: "meeting_participant") { t in
                t.column("meetingID", .text).notNull().indexed().references("meeting", onDelete: .cascade)
                t.column("contactID", .text).notNull().indexed().references("contact", onDelete: .cascade)
                t.primaryKey(["meetingID", "contactID"])
            }
            try db.create(table: "google_account") { t in
                t.primaryKey("email", .text)
                t.column("addedAt", .datetime).notNull()
                t.column("lastSyncAt", .datetime)
                t.column("syncToken", .text)
                t.column("lastError", .text)
            }
            try db.create(table: "calendar_event") { t in
                t.primaryKey("id", .text)
                t.column("account", .text).notNull()
                t.column("eventID", .text).notNull()
                t.column("recurringEventID", .text).indexed()
                t.column("title", .text).notNull()
                t.column("startAt", .datetime).notNull().indexed()
                t.column("endAt", .datetime).notNull()
                t.column("allDay", .boolean).notNull()
                t.column("meetCode", .text).indexed()
                t.column("location", .text)
                t.column("htmlLink", .text)
                t.column("organizer", .text)
                t.column("attendees", .text).notNull()
                t.column("projectID", .text).indexed().references("project", onDelete: .setNull)
                t.column("projectOrigin", .text)
                t.column("meetingID", .text).indexed().references("meeting", onDelete: .setNull)
                t.column("updatedAt", .datetime).notNull()
            }
            // Outside `MeetingRow`: the recorder's copy of a meeting never touches them.
            try db.alter(table: "meeting") { t in
                t.add(column: "summary", .text)
                t.add(column: "googleEventID", .text)
                t.add(column: "importedFrom", .text)
            }
        }
        // The color Paul gives each Google account (14/11).
        migrator.registerMigration("v5") { db in
            try db.alter(table: "google_account") { t in
                t.add(column: "color", .text)
            }
        }
        // The meetings' summaries, made on the Mac (14/11).
        migrator.registerMigration("v6") { db in
            try db.create(table: "summary_job") { t in
                t.primaryKey("meetingID", .text).references("meeting", onDelete: .cascade)
                t.column("state", .text).notNull()
                t.column("attempts", .integer).notNull()
                t.column("error", .text)
                t.column("sourceTranscribedAt", .datetime)
                t.column("updatedAt", .datetime).notNull()
            }
        }
        // What each Google account granted (calendar, mails), kept between launches (14/11).
        migrator.registerMigration("v7") { db in
            try db.alter(table: "google_account") { t in
                t.add(column: "grantedScopes", .text)
            }
        }
        // The mails, step « Lire » (14/11): a copy of the mailboxes that follows Gmail. Everything goes with its
        // account. The HTML and the attachments live in files beside the base, never here.
        migrator.registerMigration("v8") { db in
            try db.create(table: "mail_thread") { t in
                t.primaryKey("id", .text)
                t.column("account", .text).notNull().indexed().references("google_account", onDelete: .cascade)
                t.column("threadID", .text).notNull()
                t.column("subject", .text).notNull()
                t.column("snippet", .text).notNull()
                t.column("senders", .text).notNull()
                t.column("lastMessageAt", .datetime).notNull().indexed()
                t.column("messageCount", .integer).notNull()
                t.column("unread", .boolean).notNull()
                t.column("inInbox", .boolean).notNull()
                t.column("hidden", .boolean).notNull()
                t.column("hasAttachment", .boolean).notNull()
                t.column("category", .text)
                t.column("lastSender", .text)
                t.column("paulWrote", .boolean).notNull()
            }
            try db.create(table: "mail_message") { t in
                t.primaryKey("id", .text)
                t.column("account", .text).notNull().indexed()
                t.column("messageID", .text).notNull()
                t.column("threadKey", .text).notNull().indexed().references("mail_thread", onDelete: .cascade)
                t.column("date", .datetime).notNull()
                t.column("sender", .text)
                t.column("to", .text).notNull()
                t.column("cc", .text).notNull()
                t.column("subject", .text).notNull()
                t.column("snippet", .text).notNull()
                t.column("labels", .text).notNull()
                t.column("rfcMessageID", .text)
                t.column("authenticated", .boolean).notNull()
                t.column("listUnsubscribe", .text)
                t.column("listUnsubscribePost", .text)
                t.column("hasBody", .boolean).notNull()
                t.column("bodyIsHTML", .boolean).notNull()
                t.column("attachments", .text).notNull()
            }
            try db.create(table: "mail_cursor") { t in
                t.primaryKey("account", .text).references("google_account", onDelete: .cascade)
                t.column("historyID", .text)
                t.column("total", .integer).notNull()
                t.column("done", .integer).notNull()
                t.column("finishedAt", .datetime)
                t.column("lastSyncAt", .datetime)
                t.column("lastError", .text)
            }
            // Paul's gestures on their way to Gmail. Never a send: a send is never a row.
            try db.create(table: "mail_outbox") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("account", .text).notNull().indexed().references("google_account", onDelete: .cascade)
                t.column("threadKey", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("messageIDs", .text).notNull()
                t.column("attempts", .integer).notNull()
                t.column("error", .text)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "mail_sender") { t in
                t.primaryKey("address", .text)
                t.column("principal", .boolean).notNull()
                t.column("images", .boolean).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }
        // The mails, step « Écrire » (14/11): the drafts, the signature of each mailbox, three tabs.
        migrator.registerMigration("v9") { db in
            try db.alter(table: "mail_sender") { t in
                t.add(column: "tab", .text)
            }
            try db.execute(sql: "UPDATE mail_sender SET tab = 'personnes' WHERE principal = 1")
            try db.alter(table: "mail_cursor") { t in
                t.add(column: "senderName", .text)
                t.add(column: "signature", .text)
            }
            try db.create(table: "mail_draft") { t in
                t.primaryKey("id", .text)
                t.column("account", .text).notNull().indexed().references("google_account", onDelete: .cascade)
                t.column("mode", .text).notNull()
                t.column("threadKey", .text).indexed()
                t.column("replyToKey", .text)
                t.column("to", .text).notNull()
                t.column("cc", .text).notNull()
                t.column("bcc", .text).notNull()
                t.column("subject", .text).notNull()
                t.column("body", .text).notNull()
                t.column("quoteHTML", .text)
                t.column("quoteText", .text)
                t.column("inReplyTo", .text)
                t.column("references", .text)
                t.column("signature", .boolean).notNull()
                t.column("files", .text).notNull()
                t.column("gmailDraftID", .text)
                t.column("gmailMessageID", .text)
                t.column("origin", .text).notNull()
                t.column("pushedAt", .datetime)
                t.column("lastError", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }
        // 14/11: a draft whose Gmail copy went its own way; step « Ranger »: the case of a thread, Paul's
        // choices kept per thread and per sender.
        migrator.registerMigration("v10") { db in
            try db.alter(table: "mail_draft") { t in
                t.add(column: "conflict", .text)
            }
            try db.alter(table: "mail_sender") { t in
                t.add(column: "filing", .text)
            }
            try db.create(table: "mail_filing") { t in
                t.primaryKey("threadKey", .text)
                t.column("value", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }
        // Step « Agents » (14/11): what an agent drops, in a table of its own. Text only, no Gmail id, nothing
        // that sends: the app makes a draft of it, and only Paul's click sends.
        migrator.registerMigration("v11") { db in
            try db.create(table: "mail_agent_draft") { t in
                t.primaryKey("id", .text)
                t.column("mode", .text).notNull()
                t.column("account", .text)
                t.column("threadKey", .text)
                t.column("to", .text).notNull()
                t.column("cc", .text).notNull()
                t.column("subject", .text).notNull()
                t.column("body", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }
        // 15/11 (Paul): four statuses. On raw rows, never ProjectRow: the enum no longer knows the old values.
        migrator.registerMigration("v12") { db in
            try ProjectStatusMigration.run(db)
        }
        // « Inspiration » (16/11): the sites, the branding and the mock-ups of the vault, and the LinkedIn pages
        // followed. Lists and families are JSON text; the images are files beside the base.
        migrator.registerMigration("v13") { db in
            try db.create(table: "inspiration_item") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull()
                t.column("key", .text).notNull()
                t.column("title", .text).notNull()
                t.column("text", .text).notNull()
                t.column("url", .text)
                t.column("links", .text).notNull()
                t.column("date", .datetime).notNull()
                t.column("sources", .text).notNull()
                t.column("studio", .text)
                t.column("categories", .text).notNull()
                t.column("categoriesByPaul", .boolean).notNull()
                t.column("fonts", .text).notNull()
                t.column("client", .text)
                t.column("images", .text).notNull()
                t.column("extra", .text).notNull()
                t.column("importedFrom", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }
            try db.create(index: "inspiration_item_on_kind_date", on: "inspiration_item", columns: ["kind", "date"])
            try db.create(index: "inspiration_item_on_kind_key", on: "inspiration_item", columns: ["kind", "key"], unique: true)
            try db.create(table: "inspiration_source") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("link", .text).notNull().unique()
                t.column("color", .text)
                t.column("lastReadAt", .datetime)
                t.column("lastError", .text)
                t.column("createdAt", .datetime).notNull()
                // « Ne plus la suivre »: the page is remembered, so that an import does not follow it again.
                t.column("removedAt", .datetime)
            }
        }
        return migrator
    }
}

/// The seven statuses of the vault become four, in one pass: « priorité 2 » changes meaning, so a chain of
/// UPDATEs would merge everything (review of 15/11). The cards of each new column are numbered again, the
/// old columns one after the other; a project in the bin changes status and keeps its place.
enum ProjectStatusMigration {
    /// Old raw value → new raw value, and the rank of the old column inside the new one.
    static let mapping: [String: (status: String, group: Int)] = [
        "priorité 1": ("priorité 1", 0), "priorité 2": ("priorité 1", 1), "idée": ("priorité 1", 2),
        "priorité 3": ("priorité 2", 0),
        "en attente": ("en pause", 0), "": ("en pause", 1),
        "terminé": ("terminé", 0),
    ]

    private struct Card {
        let id: String
        let name: String
        let status: String
        let group: Int
        let order: Double
        let deleted: Bool
    }

    static func run(_ db: Database) throws {
        let cards = try Row.fetchAll(db, sql: "SELECT id, name, status, kanbanOrder, deletedAt FROM project").map { row in
            let old = ((row["status"] as String?) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // Anything else (a status typed by hand in the vault) waits « en pause », after the others.
            let target = mapping[old] ?? ("en pause", 2)
            return Card(id: row["id"], name: row["name"], status: target.status, group: target.group,
                        order: row["kanbanOrder"], deleted: !(row["deletedAt"] as DatabaseValue).isNull)
        }
        for card in cards where card.deleted {
            try db.execute(sql: "UPDATE project SET status = ? WHERE id = ?", arguments: [card.status, card.id])
        }
        for column in Dictionary(grouping: cards.filter { !$0.deleted }, by: \.status).values {
            let sorted = column.sorted { a, b in
                if a.group != b.group { return a.group < b.group }
                if a.order != b.order { return a.order < b.order }
                return a.name < b.name
            }
            for (rank, card) in sorted.enumerated() {
                try db.execute(sql: "UPDATE project SET status = ?, kanbanOrder = ? WHERE id = ?",
                               arguments: [card.status, Double(rank), card.id])
            }
        }
    }
}
