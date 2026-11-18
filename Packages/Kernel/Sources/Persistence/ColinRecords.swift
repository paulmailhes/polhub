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

/// A message of Colin's one thread (base v17, 18/11): Paul's, or Colin's answer. An answer is written when it begins
/// and again when it ends.
public struct ColinMessageRow: Codable, FetchableRecord, PersistableRecord, Equatable, Identifiable, Sendable {
    public static let databaseTableName = "colin_message"

    public enum Author: String, Codable, Sendable { case paul, colin }

    public enum State: String, Codable, Sendable {
        case done
        /// Colin is writing it.
        case answering
        /// Stopped before its end: by Paul, a call, the Mac's sleep, Colin turned off.
        case interrupted
        /// Claude Code failed.
        case failed
    }

    public var id: String
    public var author: Author
    public var text: String
    public var state: State
    public var createdAt: Date
    /// An answer: what it cost, in what the API would have charged.
    public var costUSD: Double?
    /// The drafts that appeared while Colin answered, by identifier.
    public var drafts: [String]

    public init(id: String = UUID().uuidString.lowercased(), author: Author, text: String, state: State = .done, createdAt: Date,
                costUSD: Double? = nil, drafts: [String] = []) {
        self.id = id
        self.author = author
        self.text = text
        self.state = state
        self.createdAt = createdAt
        self.costUSD = costUSD
        self.drafts = drafts
    }
}

/// One action of Colin's in an answer (the Accueil's pass, 18/11): a tool he called, its arguments as short texts, how
/// it went, and where it came in the answer (the characters written before it). Never what the tool gave back.
public struct ColinStep: Codable, Equatable, Identifiable, Sendable {
    public enum State: String, Codable, Sendable {
        case running, done, failed
    }

    public var id: String
    /// The tool's short name (« mails », « projet »).
    public var tool: String
    public var arguments: [String: String]
    public var state: State
    public var position: Int

    public init(id: String, tool: String, arguments: [String: String] = [:], state: State = .running, position: Int = 0) {
        self.id = id
        self.tool = tool
        self.arguments = arguments
        self.state = state
        self.position = position
    }
}

/// « Ce que Colin sait » (base v17): one text, which Paul alone changes.
struct ColinKnowledgeRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "colin_knowledge"
    var id: Int = 1
    var text: String
    var updatedAt: Date
}
