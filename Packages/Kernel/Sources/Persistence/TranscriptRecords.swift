import Domain
import Foundation
import GRDB

/// One piece of work on a meeting, kept in the base so that it survives a restart.
public struct JobRow: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "job"
    public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy { .lowercaseString }

    public var id: UUID
    public var meetingID: UUID
    public var kind: JobKind
    public var state: JobState
    /// `fr`, `en`, or `nil` for the engine's own detection.
    public var language: String?
    public var attempts: Int
    public var error: String?
    /// From 0 to 1, while it runs.
    public var progress: Double
    /// The checks found passages the engine may have invented: shown with « à vérifier ».
    public var doubtful: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?

    public init(
        id: UUID = UUID(), meetingID: UUID, kind: JobKind = .transcription, state: JobState = .queued, language: String?,
        attempts: Int = 0, error: String? = nil, progress: Double = 0, doubtful: Bool = false, createdAt: Date,
        updatedAt: Date? = nil, startedAt: Date? = nil, finishedAt: Date? = nil
    ) {
        self.id = id
        self.meetingID = meetingID
        self.kind = kind
        self.state = state
        self.language = language
        self.attempts = attempts
        self.error = error
        self.progress = progress
        self.doubtful = doubtful
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

/// One line of the dialogue: « Moi » or « Les autres », times from the start of the meeting.
public struct UtteranceRow: Codable, Equatable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "utterance"
    public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy { .lowercaseString }

    public var id: Int64?
    public var meetingID: UUID
    public var speaker: Speaker
    public var startMs: Int
    public var endMs: Int
    public var text: String
    public var doubtful: Bool

    public init(id: Int64? = nil, meetingID: UUID, speaker: Speaker, startMs: Int, endMs: Int, text: String, doubtful: Bool) {
        self.id = id
        self.meetingID = meetingID
        self.speaker = speaker
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
        self.doubtful = doubtful
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// A line found by the search, with the meeting it belongs to.
public struct SearchHit: Equatable, Sendable {
    public let meetingID: UUID
    public let title: String
    public let startedAt: Date
    public let startMs: Int
    public let speaker: Speaker
    /// The line with the words found between « and ».
    public let excerpt: String

    public init(meetingID: UUID, title: String, startedAt: Date, startMs: Int, speaker: Speaker, excerpt: String) {
        self.meetingID = meetingID
        self.title = title
        self.startedAt = startedAt
        self.startMs = startMs
        self.speaker = speaker
        self.excerpt = excerpt
    }
}
