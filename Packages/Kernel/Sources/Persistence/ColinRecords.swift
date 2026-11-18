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
    /// The key of the thread, or the identifier of the event.
    public var subject: String
    public var reason: Reason
    public var projectID: UUID?
    public var createdAt: Date

    public init(kind: String, subject: String, reason: Reason, projectID: UUID? = nil, createdAt: Date) {
        self.id = Self.key(kind: kind, subject: subject)
        self.kind = kind
        self.subject = subject
        self.reason = reason
        self.projectID = projectID
        self.createdAt = createdAt
    }

    public static func key(kind: String, subject: String) -> String { "\(kind):\(subject)" }
}
