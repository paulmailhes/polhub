import Domain
import Foundation
import GRDB

/// One meeting. Its files live in `AppPaths.meetingFolder(id)`.
public struct MeetingRow: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "meeting"
    /// Text, not a 16-byte blob: the base stays readable with `sqlite3`.
    public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy { .lowercaseString }

    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var status: MeetingStatus
    public var source: MeetingSource
    /// The detector's key: `<tabID>/<code>`, `mic` or `manual`.
    public var candidateKey: String
    public var tabID: String?
    public var meetCode: String?
    public var authUser: String?
    public var tabTitle: String?
    public var title: String
    /// When the pop-up appeared: the pre-recording belongs to the meeting.
    public var startedAt: Date
    public var presumedEndAt: Date?
    public var endedAt: Date?
    public var endReason: EndReason?
    public var healthJSON: String?
    public var transcribedAt: Date?
    public var audioPurgedAt: Date?
    /// The project the meeting is filed in, if any.
    public var projectID: UUID?

    public init(
        id: UUID = UUID(), createdAt: Date, updatedAt: Date? = nil, status: MeetingStatus, source: MeetingSource,
        candidateKey: String, tabID: String? = nil, meetCode: String? = nil, authUser: String? = nil,
        tabTitle: String? = nil, title: String, startedAt: Date, deletedAt: Date? = nil,
        presumedEndAt: Date? = nil, endedAt: Date? = nil, endReason: EndReason? = nil, healthJSON: String? = nil,
        transcribedAt: Date? = nil, audioPurgedAt: Date? = nil, projectID: UUID? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
        self.status = status
        self.source = source
        self.candidateKey = candidateKey
        self.tabID = tabID
        self.meetCode = meetCode
        self.authUser = authUser
        self.tabTitle = tabTitle
        self.title = title
        self.startedAt = startedAt
        self.presumedEndAt = presumedEndAt
        self.endedAt = endedAt
        self.endReason = endReason
        self.healthJSON = healthJSON
        self.transcribedAt = transcribedAt
        self.audioPurgedAt = audioPurgedAt
        self.projectID = projectID
    }
}

/// A line of the window's Journal: a missed meeting, an alert, a piece of information.
public struct JournalEntry: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "journal_entry"
    /// Text, not a 16-byte blob: the base stays readable with `sqlite3`.
    public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy { .lowercaseString }

    public var id: UUID
    public var createdAt: Date
    public var kind: JournalKind
    public var message: String
    public var meetingID: UUID?

    public init(id: UUID = UUID(), createdAt: Date, kind: JournalKind, message: String, meetingID: UUID? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.message = message
        self.meetingID = meetingID
    }
}

/// The Mac's memory every five minutes, kept for step 3 (can the summary model fit?).
public struct MemorySample: Codable, Equatable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "memory_sample"

    public var id: Int64?
    public var at: Date
    public var pressure: String
    public var freeBytes: Int64
    public var activeBytes: Int64
    public var inactiveBytes: Int64
    public var wiredBytes: Int64
    public var compressedBytes: Int64
    public var swapUsedBytes: Int64

    public init(
        id: Int64? = nil, at: Date, pressure: String, freeBytes: Int64, activeBytes: Int64, inactiveBytes: Int64,
        wiredBytes: Int64, compressedBytes: Int64, swapUsedBytes: Int64
    ) {
        self.id = id
        self.at = at
        self.pressure = pressure
        self.freeBytes = freeBytes
        self.activeBytes = activeBytes
        self.inactiveBytes = inactiveBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.swapUsedBytes = swapUsedBytes
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
