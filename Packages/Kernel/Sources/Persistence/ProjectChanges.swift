import Domain
import Foundation
import GRDB

/// Who changed a project (step 3 of Colin, 18/11): Paul in the app, Colin (the agent of the Accueil), or an agent —
/// a session's `polhub mcp`, of now or of before the journal.
public enum ChangeAuthor: String, Codable, Sendable, CaseIterable {
    case paul, colin, agent
}

/// What each write of a project says of itself, in the base, for the time of its transaction: who writes, the batch
/// it belongs to (one gesture, one tool call, one rule), why, and the event it answers (a rule's: never twice).
public struct ChangeStamp: Equatable, Sendable {
    public var author: ChangeAuthor
    public var batch: String?
    public var reason: String?
    public var source: String?

    public init(author: ChangeAuthor, batch: String? = nil, reason: String? = nil, source: String? = nil) {
        self.author = author
        self.batch = batch
        self.reason = reason
        self.source = source
    }
}

/// What changed. The project's status, deadline and task are kept whoever changes them (a rule must not undo what Paul
/// did today); the rest only when it is not Paul's doing.
public enum ProjectChangeField: String, Codable, Sendable, CaseIterable {
    case status, dueDate, todo, client, notes
    case actionAdded, actionDone, actionText, actionRemoved
    case journalAdded
    /// A project created by an agent, Colin among them (19/11): its name after, its column in the detail.
    case created
}

/// One change, written by the base's own triggers.
public struct ProjectChangeRow: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "project_change"
    public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy { .lowercaseString }

    public var id: Int64?
    public var projectID: UUID
    public var field: ProjectChangeField
    /// The action or the journal entry changed.
    public var subject: String?
    public var before: String?
    public var after: String?
    /// For a status, where the card was (`order`, and the card that came `next`); for a removed action, its row.
    public var detail: String?
    public var who: ChangeAuthor
    public var batch: String?
    public var reason: String?
    public var source: String?
    public var at: Date
    public var undoneAt: Date?

    public init(id: Int64?, projectID: UUID, field: ProjectChangeField, subject: String?, before: String?, after: String?, detail: String?,
                who: ChangeAuthor, batch: String?, reason: String?, source: String?, at: Date, undoneAt: Date?) {
        self.id = id
        self.projectID = projectID
        self.field = field
        self.subject = subject
        self.before = before
        self.after = after
        self.detail = detail
        self.who = who
        self.batch = batch
        self.reason = reason
        self.source = source
        self.at = at
        self.undoneAt = undoneAt
    }
}

/// The journal of the changes (base v18). The triggers call nothing but SQLite itself: a helper of before runs them
/// in its own writes, and a function it does not know would make them fail.
enum ProjectChangeSchema {
    static let now = "strftime('%Y-%m-%d %H:%M:%f','now')"
    static let who = "coalesce((SELECT who FROM change_stamp WHERE id = 1), 'agent')"
    static let at = "coalesce((SELECT at FROM change_stamp WHERE id = 1), \(now))"
    static func stamp(_ column: String) -> String { "(SELECT \(column) FROM change_stamp WHERE id = 1)" }

    /// The columns every trigger writes, and the stamp's values that follow the change's own.
    static let columns = "projectID, field, subject, before, after, detail, who, batch, reason, source, at"
    static var signed: String { "\(who), \(stamp("batch")), \(stamp("reason")), \(stamp("source")), \(at)" }

    static var tables: [String] {
        [
            """
            CREATE TABLE change_stamp (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                who TEXT NOT NULL,
                batch TEXT,
                reason TEXT,
                source TEXT,
                at DATETIME
            )
            """,
            """
            CREATE TABLE project_change (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                projectID TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
                field TEXT NOT NULL,
                subject TEXT,
                before TEXT,
                after TEXT,
                detail TEXT,
                who TEXT NOT NULL,
                batch TEXT,
                reason TEXT,
                source TEXT,
                at DATETIME NOT NULL DEFAULT (\(now)),
                undoneAt DATETIME
            )
            """,
            "CREATE INDEX project_change_on_project ON project_change(projectID, at)",
            "CREATE INDEX project_change_on_batch ON project_change(batch)",
            "CREATE INDEX project_change_on_source ON project_change(source)",
            "CREATE INDEX project_change_on_at ON project_change(at)",
        ]
    }

    /// Paul's typing in the project's page writes at every key: a minute of it is one change. The change takes the
    /// last write's source (base v20): a date from the next call merged after one of Paul's stays the call's.
    static var typing: [String] {
        ["dueDate", "todo"].map { field in
            let recent = """
                SELECT id FROM project_change
                WHERE projectID = NEW.id AND field = '\(field)' AND who = 'paul' AND undoneAt IS NULL
                  AND at >= strftime('%Y-%m-%d %H:%M:%f', \(at), '-60 seconds')
                ORDER BY id DESC LIMIT 1
                """
            return """
                CREATE TRIGGER project_change_\(field) AFTER UPDATE OF \(field) ON project
                WHEN OLD.\(field) IS NOT NEW.\(field) AND NEW.deletedAt IS NULL
                BEGIN
                    UPDATE project_change SET after = NEW.\(field), at = \(at), source = \(stamp("source"))
                    WHERE \(who) = 'paul' AND id = (\(recent));
                    INSERT INTO project_change (\(columns))
                    SELECT NEW.id, '\(field)', NULL, OLD.\(field), NEW.\(field), NULL, \(signed)
                    WHERE NOT (\(who) = 'paul' AND EXISTS (\(recent)));
                END
                """
        }
    }

    static var triggers: [String] {
        var all: [String] = []
        // The project's row: GRDB writes it whole, so each field is compared. A card in the trash changes nothing.
        all.append("""
            CREATE TRIGGER project_change_status AFTER UPDATE OF status ON project
            WHEN OLD.status IS NOT NEW.status AND NEW.deletedAt IS NULL
            BEGIN
                INSERT INTO project_change (\(columns))
                VALUES (NEW.id, 'status', NULL, OLD.status, NEW.status,
                        json_object('order', OLD.kanbanOrder, 'next', (
                            SELECT card.id FROM project card
                            WHERE card.status = OLD.status AND card.deletedAt IS NULL AND card.id <> NEW.id
                              AND (card.kanbanOrder > OLD.kanbanOrder OR (card.kanbanOrder = OLD.kanbanOrder AND card.name > NEW.name))
                            ORDER BY card.kanbanOrder, card.name LIMIT 1)),
                        \(signed));
            END
            """)
        all += typing

        for field in ["client", "notes"] {
            all.append("""
                CREATE TRIGGER project_change_\(field) AFTER UPDATE OF \(field) ON project
                WHEN OLD.\(field) IS NOT NEW.\(field) AND NEW.deletedAt IS NULL AND \(who) <> 'paul'
                BEGIN
                    INSERT INTO project_change (\(columns))
                    VALUES (NEW.id, '\(field)', NULL, OLD.\(field), NEW.\(field), NULL, \(signed));
                END
                """)
        }
        // When Paul last changed the project: an agent's write, even a helper of before that sets it, leaves it.
        all.append("""
            CREATE TRIGGER project_keeps_pauls_edit AFTER UPDATE OF lastEditedAt ON project
            WHEN OLD.lastEditedAt IS NOT NEW.lastEditedAt AND \(who) <> 'paul'
            BEGIN
                UPDATE project SET lastEditedAt = OLD.lastEditedAt WHERE id = NEW.id;
            END
            """)
        // The actions of a project, those of a meeting Paul put in it included (final review, 18/11); a meeting's summary
        // writes its own in no project.
        let ownAction = "NEW.projectID IS NOT NULL AND \(who) <> 'paul'"
        all.append("""
            CREATE TRIGGER action_change_added AFTER INSERT ON action
            WHEN \(ownAction)
            BEGIN
                INSERT INTO project_change (\(columns)) VALUES (NEW.projectID, 'actionAdded', NEW.id, NULL, NEW.text, NULL, \(signed));
            END
            """)
        all.append("""
            CREATE TRIGGER action_change_text AFTER UPDATE OF text ON action
            WHEN OLD.text IS NOT NEW.text AND \(ownAction)
            BEGIN
                INSERT INTO project_change (\(columns)) VALUES (NEW.projectID, 'actionText', NEW.id, OLD.text, NEW.text, NULL, \(signed));
            END
            """)
        all.append("""
            CREATE TRIGGER action_change_done AFTER UPDATE OF done ON action
            WHEN OLD.done IS NOT NEW.done AND \(ownAction)
            BEGIN
                INSERT INTO project_change (\(columns))
                VALUES (NEW.projectID, 'actionDone', NEW.id, CAST(OLD.done AS TEXT), CAST(NEW.done AS TEXT), json_object('text', NEW.text), \(signed));
            END
            """)
        all.append("""
            CREATE TRIGGER action_change_removed AFTER DELETE ON action
            WHEN OLD.projectID IS NOT NULL AND \(who) <> 'paul'
            BEGIN
                INSERT INTO project_change (\(columns))
                VALUES (OLD.projectID, 'actionRemoved', OLD.id, OLD.text, NULL,
                        json_object('id', OLD.id, 'projectID', OLD.projectID, 'meetingID', OLD.meetingID, 'text', OLD.text, 'done', OLD.done, 'addedOn', OLD.addedOn,
                                    'dueDate', OLD.dueDate, 'owner', OLD.owner, 'position', OLD.position, 'createdAt', OLD.createdAt,
                                    'updatedAt', OLD.updatedAt),
                        \(signed));
            END
            """)
        all.append("""
            CREATE TRIGGER journal_change_added AFTER INSERT ON project_journal
            WHEN \(who) <> 'paul'
            BEGIN
                INSERT INTO project_change (\(columns)) VALUES (NEW.projectID, 'journalAdded', NEW.id, NULL, NEW.title, NULL, \(signed));
            END
            """)
        return all
    }
}

extension ProjectChangeSchema {
    /// A project an agent creates (base v21, 19/11): one change, undone by putting it in the trash. Paul's own are not
    /// journaled.
    static let created = """
        CREATE TRIGGER project_change_created AFTER INSERT ON project
        WHEN NEW.deletedAt IS NULL AND \(who) <> 'paul'
        BEGIN
            INSERT INTO project_change (\(columns)) VALUES (NEW.id, 'created', NULL, NULL, NEW.name, NEW.status, \(signed));
        END
        """
}

/// What a rule changes in a project (step 3 of Colin, 18/11): only what is given; `source` is the event it answers
/// (`mail:…`, `event:…`), never answered twice; `reason` is what the Accueil says under the change.
public struct KanbanEdit: Equatable, Sendable {
    public var projectID: UUID
    public var status: ProjectStatus?
    public var todo: String?
    public var dueDate: Date?
    public var journal: String?
    public var reason: String
    public var source: String

    public init(projectID: UUID, status: ProjectStatus?, todo: String?, dueDate: Date?, journal: String?, reason: String, source: String) {
        self.projectID = projectID
        self.status = status
        self.todo = todo
        self.dueDate = dueDate
        self.journal = journal
        self.reason = reason
        self.source = source
    }
}

/// A field of a project, for the rules: what Paul changed himself is left alone.
public struct ProjectFieldKey: Hashable, Sendable {
    public var projectID: UUID
    public var field: ProjectChangeField

    public init(projectID: UUID, field: ProjectChangeField) {
        self.projectID = projectID
        self.field = field
    }
}

/// One change as Paul reads it: a batch (one gesture of an agent, one tool call, one rule), or, for a helper of before
/// that writes none, its writes on a project a few seconds apart.
public struct ProjectChangeLine: Identifiable, Equatable, Sendable {
    public var id: String
    public var projectID: UUID
    public var projectName: String
    public var who: ChangeAuthor
    /// When it was made: its last write.
    public var at: Date
    public var reason: String?
    public var rows: [ProjectChangeRow]
    /// Undone by Paul.
    public var undoneAt: Date?

    public init(id: String, projectID: UUID, projectName: String, who: ChangeAuthor, at: Date, reason: String?, rows: [ProjectChangeRow],
                undoneAt: Date?) {
        self.id = id
        self.projectID = projectID
        self.projectName = projectName
        self.who = who
        self.at = at
        self.reason = reason
        self.rows = rows
        self.undoneAt = undoneAt
    }
}

/// What « Annuler » did: everything put back, a part (what changed since stays), or nothing (all of it changed since).
/// What « Reporter » or « Livré » changed, to put it back (0.36.0).
public struct DueUndo: Equatable, Sendable {
    public var projectID: UUID
    public var before: Date?
    public var after: Date?
    /// The journal line « Livré le … » it added.
    public var journalID: UUID?
    /// The mark a date from the next call left on a day that did not move (0.37.0).
    public var markID: Int64?

    public init(projectID: UUID, before: Date?, after: Date?, journalID: UUID?, markID: Int64? = nil) {
        self.projectID = projectID
        self.before = before
        self.after = after
        self.journalID = journalID
        self.markID = markID
    }
}

public enum UndoOutcome: Equatable, Sendable {
    case undone
    case partly(kept: Int)
    case changedSince
}

/// The journal of the changes, read and undone (step 3 of Colin, 18/11).
public struct ProjectChanges: Sendable {
    public let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    /// Writes of a helper of before, on one project, this close: one line.
    static let sameLine: TimeInterval = 5

    /// Whether the base keeps the journal (v18).
    public func isReady() throws -> Bool {
        try database.writer.read { try $0.tableExists("change_stamp") && $0.tableExists("project_change") }
    }

    /// The changes made since `since` by those `authors`, the oldest first.
    public func lines(since: Date, authors: Set<ChangeAuthor>) throws -> [ProjectChangeLine] {
        try database.writer.read { try Self.lines($0, since: since, authors: authors) }
    }

    /// The same, now and after every change, on the main queue.
    public func observeLines(since: Date, authors: Set<ChangeAuthor>,
                             onChange: @escaping @MainActor @Sendable ([ProjectChangeLine]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { try Self.lines($0, since: since, authors: authors) }
            .removeDuplicates()
            .start(in: database.writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { lines in
                MainActor.assumeIsolated { onChange(lines) }
            })
    }

    static func lines(_ db: Database, since: Date, authors: Set<ChangeAuthor>) throws -> [ProjectChangeLine] {
        guard !authors.isEmpty, try db.tableExists("project_change") else { return [] }
        let marks = authors.map { _ in "?" }.joined(separator: ", ")
        let rows = try ProjectChangeRow.fetchAll(db, sql: "SELECT * FROM project_change WHERE at >= ? AND who IN (\(marks)) ORDER BY id",
                                                 arguments: StatementArguments([since] + authors.map(\.rawValue).sorted())!)
        let ids = Set(rows.map(\.projectID))
        var names: [UUID: String] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT id, name FROM project") {
            guard let id = UUID(uuidString: row["id"]), ids.contains(id) else { continue }
            names[id] = row["name"]
        }
        return group(rows, names: names)
    }

    /// Rows into lines: a batch is a line; rows with no batch join the line before them when it has none either, is
    /// of the same project and author, and was written at most `sameLine` seconds earlier. A row that came back to
    /// where it began says nothing; a line of nothing is not one.
    public static func group(_ rows: [ProjectChangeRow], names: [UUID: String]) -> [ProjectChangeLine] {
        var lines: [ProjectChangeLine] = []
        var byBatch: [String: Int] = [:]
        for row in rows where row.before != row.after {
            if let batch = row.batch, let index = byBatch[batch] {
                lines[index].rows.append(row)
                lines[index].at = max(lines[index].at, row.at)
                continue
            }
            if row.batch == nil, let last = lines.indices.last, lines[last].rows.last?.batch == nil, lines[last].projectID == row.projectID,
               lines[last].who == row.who, row.at.timeIntervalSince(lines[last].at) <= sameLine {
                lines[last].rows.append(row)
                lines[last].at = max(lines[last].at, row.at)
                continue
            }
            if let batch = row.batch { byBatch[batch] = lines.count }
            lines.append(ProjectChangeLine(id: "c\(row.id ?? 0)", projectID: row.projectID, projectName: names[row.projectID] ?? "",
                                           who: row.who, at: row.at, reason: row.reason, rows: [row], undoneAt: nil))
        }
        for index in lines.indices {
            let undone = lines[index].rows.map(\.undoneAt)
            lines[index].undoneAt = undone.contains(nil) ? nil : undone.compactMap { $0 }.max()
        }
        return lines
    }

    /// What Paul changed himself since `since`, of what a rule may change.
    public func paulTouches(since: Date) throws -> Set<ProjectFieldKey> {
        try database.writer.read { db in
            guard try db.tableExists("project_change") else { return [] }
            let rows = try Row.fetchAll(db, sql: """
                SELECT DISTINCT projectID, field FROM project_change
                WHERE who = 'paul' AND at >= ? AND before IS NOT after
                """, arguments: [since])
            return Set(rows.compactMap { row in
                guard let id = UUID(uuidString: row["projectID"]), let field = ProjectChangeField(rawValue: row["field"]) else { return nil }
                return ProjectFieldKey(projectID: id, field: field)
            })
        }
    }

    /// The projects whose deadline Paul set himself (0.37.0): his last change of it that changed something, without a
    /// meeting as its source. A date Colin took from a meeting, or Paul from the next call (« Livré, prochaine
    /// échéance »), is that call — even onto the day already set, which leaves a mark of its own; a date never journaled
    /// is no one's. « Livré » then « Annuler » says nothing.
    public func paulDeadlines() throws -> Set<UUID> {
        try database.writer.read { try Self.paulDeadlines($0) }
    }

    /// The same, now and after every change, on the main queue.
    public func observePaulDeadlines(onChange: @escaping @MainActor @Sendable (Set<UUID>) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { try Self.paulDeadlines($0) }
            .removeDuplicates()
            .start(in: database.writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { deadlines in
                MainActor.assumeIsolated { onChange(deadlines) }
            })
    }

    static func paulDeadlines(_ db: Database) throws -> Set<UUID> {
        guard try db.tableExists("project_change") else { return [] }
        let ids = try String.fetchAll(db, sql: """
            SELECT projectID FROM project_change
            WHERE id IN (SELECT MAX(id) FROM project_change
                         WHERE field = 'dueDate' AND (before IS NOT after OR source LIKE 'event:%') GROUP BY projectID)
              AND who = 'paul' AND (source IS NULL OR source NOT LIKE 'event:%')
            """)
        return Set(ids.compactMap { UUID(uuidString: $0) })
    }

    /// The events a rule already answered since `since`, undone or not.
    public func sources(since: Date) throws -> Set<String> {
        try database.writer.read { db in
            guard try db.tableExists("project_change") else { return [] }
            return Set(try String.fetchAll(db, sql: "SELECT DISTINCT source FROM project_change WHERE source IS NOT NULL AND at >= ?",
                                           arguments: [since]))
        }
    }

    /// « Annuler »: in one transaction of Paul's, each change of the line, the last first, is put back if what it wrote
    /// is still there; what changed since stays. The line is marked undone either way.
    public func undo(_ line: ProjectChangeLine, at date: Date) throws -> UndoOutcome {
        let store = ProjectStore(database).signed(.paul)
        return try store.write(at: date) { db in
            let ids = line.rows.compactMap(\.id)
            guard !ids.isEmpty else { return .undone }
            let marks = ids.map { _ in "?" }.joined(separator: ", ")
            let rows = try ProjectChangeRow.fetchAll(db, sql: "SELECT * FROM project_change WHERE id IN (\(marks)) AND undoneAt IS NULL ORDER BY id DESC",
                                                     arguments: StatementArguments(ids)!)
            guard !rows.isEmpty else { return .undone }
            var kept = 0
            for row in rows where try !Self.putBack(row, db, at: date) { kept += 1 }
            try db.execute(sql: "UPDATE project_change SET undoneAt = ? WHERE id IN (\(marks))", arguments: StatementArguments([date] + ids)!)
            return kept == 0 ? .undone : kept == rows.count ? .changedSince : .partly(kept: kept)
        }
    }

    /// One change put back; `false` when what it wrote changed since.
    private static func putBack(_ row: ProjectChangeRow, _ db: Database, at date: Date) throws -> Bool {
        let project = ProjectStore.key(row.projectID)
        switch row.field {
        case .status:
            let current = try String.fetchOne(db, sql: "SELECT status FROM project WHERE id = ? AND deletedAt IS NULL", arguments: [project])
            guard current == row.after, let before = row.before.flatMap(ProjectStatus.init(rawValue:)) else { return false }
            try ProjectStore.place(db, row.projectID, to: before, before: try neighbour(of: row, in: before, db), at: date, edited: true)
            return true
        case .dueDate, .todo, .client, .notes:
            let column = row.field.rawValue
            let current = try String.fetchOne(db, sql: "SELECT \(column) FROM project WHERE id = ?", arguments: [project])
            guard current == row.after else { return false }
            try db.execute(sql: "UPDATE project SET \(column) = ?, updatedAt = ?, lastEditedAt = ? WHERE id = ?",
                           arguments: [row.before, date, date, project])
            return true
        case .actionAdded:
            guard let action = try Row.fetchOne(db, sql: "SELECT text, done FROM action WHERE id = ?", arguments: [row.subject]) else { return true }
            guard action["text"] == row.after, action["done"] == false else { return false }
            try db.execute(sql: "DELETE FROM action WHERE id = ?", arguments: [row.subject])
            return true
        case .actionDone, .actionText:
            let column = row.field == .actionDone ? "done" : "text"
            guard let current = try String.fetchOne(db, sql: "SELECT CAST(\(column) AS TEXT) FROM action WHERE id = ?", arguments: [row.subject]),
                  current == row.after else { return false }
            let value: DatabaseValueConvertible? = row.field == .actionDone ? (row.before == "1") : row.before
            try db.execute(sql: "UPDATE action SET \(column) = ?, updatedAt = ? WHERE id = ?", arguments: [value, date, row.subject])
            return true
        case .actionRemoved:
            guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM action WHERE id = ?)", arguments: [row.subject]) == false else { return true }
            guard let detail = row.detail else { return false }
            try db.execute(sql: """
                INSERT INTO action (id, projectID, meetingID, text, done, addedOn, dueDate, owner, position, createdAt, updatedAt)
                SELECT json_extract(:d, '$.id'), json_extract(:d, '$.projectID'),
                       (SELECT id FROM meeting WHERE id = json_extract(:d, '$.meetingID')), json_extract(:d, '$.text'), json_extract(:d, '$.done'),
                       json_extract(:d, '$.addedOn'), json_extract(:d, '$.dueDate'), json_extract(:d, '$.owner'), json_extract(:d, '$.position'),
                       json_extract(:d, '$.createdAt'), json_extract(:d, '$.updatedAt')
                WHERE EXISTS(SELECT 1 FROM project WHERE id = json_extract(:d, '$.projectID'))
                """, arguments: ["d": detail])
            return db.changesCount > 0
        case .journalAdded:
            try db.execute(sql: "DELETE FROM project_journal WHERE id = ?", arguments: [row.subject])
            return true
        case .created:
            // In the trash, where Paul can still find it.
            try db.execute(sql: "UPDATE project SET deletedAt = ?, updatedAt = ? WHERE id = ? AND deletedAt IS NULL", arguments: [date, date, project])
            return true
        }
    }

    /// The card a project goes back before, in its old column: the one that came after it, if it is still there;
    /// else the first one its old place came before; else none (the bottom).
    private static func neighbour(of row: ProjectChangeRow, in status: ProjectStatus, _ db: Database) throws -> UUID? {
        let detail = row.detail.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] } ?? [:]
        if let next = detail["next"] as? String,
           try String.fetchOne(db, sql: "SELECT status FROM project WHERE id = ? AND deletedAt IS NULL", arguments: [next]) == status.rawValue {
            return UUID(uuidString: next)
        }
        guard let order = (detail["order"] as? NSNumber)?.doubleValue else { return nil }
        let after = try String.fetchOne(db, sql: """
            SELECT id FROM project WHERE status = ? AND deletedAt IS NULL AND id <> ? AND kanbanOrder > ? ORDER BY kanbanOrder, name LIMIT 1
            """, arguments: [status.rawValue, ProjectStore.key(row.projectID), order])
        return after.flatMap(UUID.init(uuidString:))
    }
}
