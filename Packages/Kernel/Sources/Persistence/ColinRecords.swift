import Foundation
import GRDB

/// A line of the Accueil that Paul set aside (base v16, 18/11): which one, why, and when. One row by line; setting
/// it aside again replaces the row.
public struct ColinDismissalRow: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "colin_dismissal"
    public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy { .lowercaseString }

    public enum Reason: String, Codable, Sendable {
        /// « Pas besoin ».
        case notNeeded
        /// « Plus tard »: the line comes back the next day.
        case later
        /// « Elle a répondu ailleurs ».
        case answeredElsewhere
    }

    /// `<kind>:<subject>`.
    public var id: String
    /// « reply », « silent », « unfiled ».
    public var kind: String
    /// What the line is about: a person's address for « reply », a project's identifier in small letters for
    /// « silent », an event's identifier for « unfiled ».
    public var subject: String
    public var reason: Reason
    public var projectID: UUID?
    public var createdAt: Date
    /// The date of the last message Paul had before him when he set the line aside: a message that reached Gmail
    /// before his click and Polhub after it is newer than what he saw, and brings the line back.
    public var lastMessageAt: Date?
    /// How many times in a row this line was set aside as « Elle a répondu ailleurs ».
    public var times: Int

    public init(kind: String, subject: String, reason: Reason, projectID: UUID? = nil, createdAt: Date, lastMessageAt: Date? = nil, times: Int = 1) {
        self.id = Self.key(kind: kind, subject: subject)
        self.kind = kind
        self.subject = subject
        self.reason = reason
        self.projectID = projectID
        self.createdAt = createdAt
        self.lastMessageAt = lastMessageAt
        self.times = times
    }

    public static func key(kind: String, subject: String) -> String { "\(kind):\(subject)" }
}
