import Domain
import Foundation
import GRDB

/// A person Paul works with: from the vault, from his calendars' guests, or added in the app.
public struct ContactRow: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "contact"
    public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy { .lowercaseString }

    public var id: UUID
    public var name: String
    /// Lowercased; at most one contact per address.
    public var email: String?
    public var company: String?
    public var phone: String?
    public var notes: String
    /// The vault note it came from.
    public var importedFrom: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID = UUID(), name: String, email: String? = nil, company: String? = nil, phone: String? = nil, notes: String = "",
                importedFrom: String? = nil, createdAt: Date, updatedAt: Date? = nil, deletedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.email = email?.lowercased()
        self.company = company
        self.phone = phone
        self.notes = notes
        self.importedFrom = importedFrom
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }

    /// « Camille Martin » → « CM ».
    public var initials: String {
        let words = name.replacing(#/\s*\(.*?\)/#, with: "").split(separator: " ").filter { $0.count > 1 }
        return words.prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
    }
}

/// Where a link between a contact and a project comes from.
public enum LinkOrigin: String, Codable, Sendable {
    /// The vault's contact note.
    case coffre
    /// A calendar event filed in the project, the contact being a guest.
    case agenda
    /// Paul, in the app.
    case paul
}

public struct ContactProjectRow: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "contact_project"
    public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy { .lowercaseString }

    public var contactID: UUID
    public var projectID: UUID
    public var origin: LinkOrigin
    /// Paul removed it: the automatic links never bring it back.
    public var excluded: Bool
    public var createdAt: Date

    public init(contactID: UUID, projectID: UUID, origin: LinkOrigin, excluded: Bool = false, createdAt: Date) {
        self.contactID = contactID
        self.projectID = projectID
        self.origin = origin
        self.excluded = excluded
        self.createdAt = createdAt
    }
}

/// A guest of a calendar event, as Google gives it.
public struct Attendee: Codable, Equatable, Hashable, Sendable {
    public var email: String
    public var name: String?
    /// accepted, declined, tentative, needsAction.
    public var response: String?
    /// The calendar's owner: Paul.
    public var isSelf: Bool
    public var isOrganizer: Bool
    /// A meeting room.
    public var isResource: Bool

    public init(email: String, name: String? = nil, response: String? = nil, isSelf: Bool = false, isOrganizer: Bool = false,
                isResource: Bool = false) {
        self.email = email.lowercased()
        self.name = name
        self.response = response
        self.isSelf = isSelf
        self.isOrganizer = isOrganizer
        self.isResource = isResource
    }
}

/// Why an event is in a project: the first rule that answered (see the plan of 13/11).
public enum EventProjectOrigin: String, Codable, Sendable {
    case paul, reunion, serie, invites, titre
}

/// An event of the primary calendar of one of Paul's Google accounts.
public struct CalendarEventRow: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "calendar_event"
    public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy { .lowercaseString }

    /// `account|eventID`.
    public var id: String
    public var account: String
    public var eventID: String
    public var recurringEventID: String?
    public var title: String
    public var startAt: Date
    public var endAt: Date
    public var allDay: Bool
    public var meetCode: String?
    public var location: String?
    public var htmlLink: String?
    public var organizer: String?
    public var attendees: [Attendee]
    public var projectID: UUID?
    public var projectOrigin: EventProjectOrigin?
    public var meetingID: UUID?
    public var updatedAt: Date

    public init(account: String, eventID: String, recurringEventID: String? = nil, title: String, startAt: Date, endAt: Date,
                allDay: Bool = false, meetCode: String? = nil, location: String? = nil, htmlLink: String? = nil, organizer: String? = nil,
                attendees: [Attendee] = [], projectID: UUID? = nil, projectOrigin: EventProjectOrigin? = nil, meetingID: UUID? = nil,
                updatedAt: Date) {
        self.id = Self.key(account: account, eventID: eventID)
        self.account = account.lowercased()
        self.eventID = eventID
        self.recurringEventID = recurringEventID
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.allDay = allDay
        self.meetCode = meetCode
        self.location = location
        self.htmlLink = htmlLink
        self.organizer = organizer
        self.attendees = attendees
        self.projectID = projectID
        self.projectOrigin = projectOrigin
        self.meetingID = meetingID
        self.updatedAt = updatedAt
    }

    public static func key(account: String, eventID: String) -> String { "\(account.lowercased())|\(eventID)" }

    /// The guests who are neither Paul nor a room.
    public var guests: [Attendee] { attendees.filter { !$0.isSelf && !$0.isResource } }
}

/// One of Paul's Google accounts; its token lives in the Keychain, never here.
public struct GoogleAccountRow: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "google_account"

    public var email: String
    public var addedAt: Date
    public var lastSyncAt: Date?
    /// Google's token for the next incremental sync of the primary calendar.
    public var syncToken: String?
    public var lastError: String?
    /// `#RRGGBB` chosen by Paul; `nil` takes the default (see `AccountStyle`).
    public var color: String?
    /// What the account granted at its last token, space-separated as Google gives it; `nil` before.
    public var grantedScopes: String?

    public var id: String { email }

    public init(email: String, addedAt: Date, lastSyncAt: Date? = nil, syncToken: String? = nil, lastError: String? = nil,
                color: String? = nil, grantedScopes: String? = nil) {
        self.email = email.lowercased()
        self.addedAt = addedAt
        self.lastSyncAt = lastSyncAt
        self.syncToken = syncToken
        self.lastError = lastError
        self.color = color
        self.grantedScopes = grantedScopes
    }
}
