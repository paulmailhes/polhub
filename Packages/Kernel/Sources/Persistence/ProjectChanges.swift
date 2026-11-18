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
        // Paul's typing in the project's page writes at every key: a minute of it is one change.
        for field in ["dueDate", "todo"] {
            let recent = """
                SELECT id FROM project_change
                WHERE projectID = NEW.id AND field = '\(field)' AND who = 'paul' AND undoneAt IS NULL
                  AND at >= strftime('%Y-%m-%d %H:%M:%f', \(at), '-60 seconds')
                ORDER BY id DESC LIMIT 1
                """
            all.append("""
                CREATE TRIGGER project_change_\(field) AFTER UPDATE OF \(field) ON project
                WHEN OLD.\(field) IS NOT NEW.\(field) AND NEW.deletedAt IS NULL
                BEGIN
                    UPDATE project_change SET after = NEW.\(field), at = \(at)
                    WHERE \(who) = 'paul' AND id = (\(recent));
                    INSERT INTO project_change (\(columns))
                    SELECT NEW.id, '\(field)', NULL, OLD.\(field), NEW.\(field), NULL, \(signed)
                    WHERE NOT (\(who) = 'paul' AND EXISTS (\(recent)));
                END
                """)
        }
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
        // The actions of a project, not those of a meeting's summary, made on the Mac and replaced whole.
        let ownAction = "NEW.meetingID IS NULL AND NEW.projectID IS NOT NULL AND \(who) <> 'paul'"
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
            WHEN OLD.meetingID IS NULL AND OLD.projectID IS NOT NULL AND \(who) <> 'paul'
            BEGIN
                INSERT INTO project_change (\(columns))
                VALUES (OLD.projectID, 'actionRemoved', OLD.id, OLD.text, NULL,
                        json_object('id', OLD.id, 'projectID', OLD.projectID, 'text', OLD.text, 'done', OLD.done, 'addedOn', OLD.addedOn,
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
