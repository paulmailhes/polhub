import Domain
import Foundation
import GRDB

/// One project, imported from the vault or created in the app.
public struct ProjectRow: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "project"
    public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy { .lowercaseString }

    public var id: UUID
    public var name: String
    public var status: ProjectStatus
    public var client: String?
    public var dueDate: Date?
    /// The next thing to do, one line (`todo` in the vault).
    public var todo: String?
    public var icon: String?
    public var color: String?
    public var contacts: [String]
    public var createdOn: Date?
    public var codeFolder: String?
    public var github: String?
    public var notion: String?
    public var lastActivity: Date?
    /// The last meeting seen in Obsidian, frozen at the import.
    public var lastMeetingImported: Date?
    /// When the note was last changed in the vault, at the import: a sign of life.
    public var noteModifiedAt: Date?
    /// When Paul last changed the project in the app.
    public var lastEditedAt: Date?
    public var notes: String
    public var kanbanOrder: Double
    /// The note it came from, relative to the vault.
    public var importedFrom: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(), name: String, status: ProjectStatus, client: String? = nil, dueDate: Date? = nil, todo: String? = nil,
        icon: String? = nil, color: String? = nil, contacts: [String] = [], createdOn: Date? = nil, codeFolder: String? = nil,
        github: String? = nil, notion: String? = nil, lastActivity: Date? = nil, lastMeetingImported: Date? = nil,
        noteModifiedAt: Date? = nil, lastEditedAt: Date? = nil, notes: String = "", kanbanOrder: Double = 0,
        importedFrom: String? = nil, createdAt: Date, updatedAt: Date? = nil, deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.client = client
        self.dueDate = dueDate
        self.todo = todo
        self.icon = icon
        self.color = color
        self.contacts = contacts
        self.createdOn = createdOn
        self.codeFolder = codeFolder
        self.github = github
        self.notion = notion
        self.lastActivity = lastActivity
        self.lastMeetingImported = lastMeetingImported
        self.noteModifiedAt = noteModifiedAt
        self.lastEditedAt = lastEditedAt
        self.notes = notes
        self.kanbanOrder = kanbanOrder
        self.importedFrom = importedFrom
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }
}

/// One action: of a project, and later of a meeting's summary (design of 12/11: « les actions sont des
/// lignes : porteur, échéance, projet, état »).
public struct ActionRow: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "action"
    public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy { .lowercaseString }

    public var id: UUID
    public var projectID: UUID?
    public var meetingID: UUID?
    public var text: String
    public var done: Bool
    /// The date after « · » in the vault: when the action was written down.
    public var addedOn: Date?
    public var dueDate: Date?
    public var owner: String?
    public var position: Double
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(), projectID: UUID? = nil, meetingID: UUID? = nil, text: String, done: Bool = false, addedOn: Date? = nil,
        dueDate: Date? = nil, owner: String? = nil, position: Double, createdAt: Date, updatedAt: Date? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.meetingID = meetingID
        self.text = text
        self.done = done
        self.addedOn = addedOn
        self.dueDate = dueDate
        self.owner = owner
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

/// One entry of a project's journal: what was done.
public struct ProjectJournalRow: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "project_journal"
    public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy { .lowercaseString }

    public var id: UUID
    public var projectID: UUID
    public var date: Date
    public var title: String
    public var body: String
    public var createdAt: Date

    public init(id: UUID = UUID(), projectID: UUID, date: Date, title: String, body: String, createdAt: Date) {
        self.id = id
        self.projectID = projectID
        self.date = date
        self.title = title
        self.body = body
        self.createdAt = createdAt
    }
}
