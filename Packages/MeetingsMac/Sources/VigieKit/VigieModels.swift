import Foundation

/// What Vigie's engine says (21/11): the part of its API v2 that hub's « Vue d'ensemble » shows. Every field the
/// engine may leave out is optional here: an engine a version ahead or behind is still read.
public struct VigieOverview: Decodable, Equatable, Sendable {
    /// What waits for Paul, the most recent first.
    public var toReview: [VigieReview]
    public var conversations: [VigieConversation]
    public var accounts: [VigieAccount]

    public init(toReview: [VigieReview] = [], conversations: [VigieConversation] = [], accounts: [VigieAccount] = []) {
        self.toReview = toReview
        self.conversations = conversations
        self.accounts = accounts
    }

    enum CodingKeys: String, CodingKey {
        case toReview, conversations, accounts
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        toReview = Self.each(values, .toReview)
        conversations = Self.each(values, .conversations)
        accounts = Self.each(values, .accounts)
    }

    /// The elements that can be read: one the engine writes in a way hub does not know is left out, the rest stays.
    static func each<Element: Decodable>(_ values: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [Element] {
        ((try? values.decodeIfPresent([Lenient<Element>].self, forKey: key)) ?? [])?.compactMap(\.value) ?? []
    }

    /// The label of an account, for a conversation's line.
    public func accountLabel(_ id: String?) -> String? {
        guard let id else { return nil }
        return accounts.first { $0.id == id }?.label
    }
}

/// An element that may fail to decode without failing the list it is in.
struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// Something that waits for Paul, or that he should see.
public struct VigieReview: Decodable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        /// A question Vigie answered for Paul, not read again yet.
        case question
        /// A sensitive action: waiting for his decision, or refused.
        case blocked
        /// A question or a plan that waits for him.
        case waiting
        case limit
        case notice
        case other
    }

    public var id: String
    public var kind: Kind
    public var conversationID: String?
    public var conversationTitle: String?
    public var title: String
    public var detail: String?
    public var at: Date?
    /// A sensitive action: « waiting » while the conversation still waits for the decision.
    public var state: String?
    /// The wait's identifier, while it lasts: what a decision answers.
    public var pendingID: String?
    public var expiresAt: Date?
    public var rule: String?
    /// The action's exact text.
    public var command: String?
    /// A sudo command: to run oneself in Terminal.
    public var needsPassword: Bool
    /// The question answered for Paul, with what was chosen.
    public var question: VigieQuestion?

    public init(id: String, kind: Kind, conversationID: String? = nil, conversationTitle: String? = nil, title: String, detail: String? = nil,
                at: Date? = nil, state: String? = nil, pendingID: String? = nil, expiresAt: Date? = nil, rule: String? = nil,
                command: String? = nil, needsPassword: Bool = false, question: VigieQuestion? = nil) {
        self.id = id
        self.kind = kind
        self.conversationID = conversationID
        self.conversationTitle = conversationTitle
        self.title = title
        self.detail = detail
        self.at = at
        self.state = state
        self.pendingID = pendingID
        self.expiresAt = expiresAt
        self.rule = rule
        self.command = command
        self.needsPassword = needsPassword
        self.question = question
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, conversationId, conversationTitle, title, detail, ts, state, pendingId, expiresAt, rule, command, needsPassword, question
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        kind = (try? values.decode(String.self, forKey: .kind)).flatMap(Kind.init(rawValue:)) ?? .other
        conversationID = try? values.decodeIfPresent(String.self, forKey: .conversationId)
        conversationTitle = try? values.decodeIfPresent(String.self, forKey: .conversationTitle)
        title = (try? values.decodeIfPresent(String.self, forKey: .title)) ?? ""
        detail = try? values.decodeIfPresent(String.self, forKey: .detail)
        at = VigieDate.read(values, .ts)
        state = try? values.decodeIfPresent(String.self, forKey: .state)
        // The engine writes it as text; a number is read too.
        pendingID = (try? values.decodeIfPresent(String.self, forKey: .pendingId)) ?? (try? values.decodeIfPresent(Int.self, forKey: .pendingId)).map(String.init)
        expiresAt = VigieDate.read(values, .expiresAt)
        rule = try? values.decodeIfPresent(String.self, forKey: .rule)
        command = try? values.decodeIfPresent(String.self, forKey: .command)
        needsPassword = (try? values.decodeIfPresent(Bool.self, forKey: .needsPassword)) ?? false
        question = try? values.decodeIfPresent(VigieQuestion.self, forKey: .question)
    }

    /// A sensitive action the conversation still waits on: « Autoriser » or « Refuser » answers it.
    public var isPendingDecision: Bool {
        kind == .blocked && state == "waiting" && pendingID != nil
    }

    /// Something to decide or to answer: what the count of « T'attendent » holds. A notice is only to see.
    public var needsPaul: Bool {
        switch kind {
        case .question, .waiting: true
        case .blocked: state == "waiting"
        case .limit, .notice, .other: false
        }
    }
}

public struct VigieQuestion: Decodable, Equatable, Sendable {
    public struct Item: Decodable, Equatable, Sendable {
        public var question: String
        public var chosen: String?

        public init(question: String, chosen: String? = nil) {
            self.question = question
            self.chosen = chosen
        }

        enum CodingKeys: String, CodingKey {
            case question, chosen
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            question = (try? values.decodeIfPresent(String.self, forKey: .question)) ?? ""
            chosen = try? values.decodeIfPresent(String.self, forKey: .chosen)
        }
    }

    public var id: String
    public var items: [Item]

    public init(id: String, items: [Item]) {
        self.id = id
        self.items = items
    }

    enum CodingKeys: String, CodingKey {
        case id, items
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        items = (try? values.decodeIfPresent([Item].self, forKey: .items)) ?? []
    }
}

/// A conversation of Claude Code, as Vigie sees it.
public struct VigieConversation: Decodable, Equatable, Sendable, Identifiable {
    public enum Status: String, Sendable {
        case working, idle, waiting, blocked, closed, other
    }

    public struct Progress: Decodable, Equatable, Sendable {
        public var done: Int
        public var total: Int

        public init(done: Int, total: Int) {
            self.done = done
            self.total = total
        }
    }

    public var id: String
    public var title: String
    public var project: String?
    public var status: Status
    public var running: Bool
    public var accountID: String?
    public var lastActivity: Date?
    /// How many things of « à regarder » are this conversation's.
    public var needsYou: Int
    /// One line: the task under way, else the start of the last report.
    public var headline: String?
    public var agentsRunning: Int
    public var progress: Progress?

    public init(id: String, title: String, project: String? = nil, status: Status = .idle, running: Bool = false, accountID: String? = nil,
                lastActivity: Date? = nil, needsYou: Int = 0, headline: String? = nil, agentsRunning: Int = 0, progress: Progress? = nil) {
        self.id = id
        self.title = title
        self.project = project
        self.status = status
        self.running = running
        self.accountID = accountID
        self.lastActivity = lastActivity
        self.needsYou = needsYou
        self.headline = headline
        self.agentsRunning = agentsRunning
        self.progress = progress
    }

    enum CodingKeys: String, CodingKey {
        case id, title, project, status, running, accountId, lastActivity, needsYou, headline, agentsRunning, progress
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = (try? values.decodeIfPresent(String.self, forKey: .title)) ?? ""
        project = try? values.decodeIfPresent(String.self, forKey: .project)
        status = (try? values.decode(String.self, forKey: .status)).flatMap(Status.init(rawValue:)) ?? .other
        running = (try? values.decodeIfPresent(Bool.self, forKey: .running)) ?? false
        accountID = try? values.decodeIfPresent(String.self, forKey: .accountId)
        lastActivity = VigieDate.read(values, .lastActivity)
        needsYou = (try? values.decodeIfPresent(Int.self, forKey: .needsYou)) ?? 0
        headline = try? values.decodeIfPresent(String.self, forKey: .headline)
        agentsRunning = (try? values.decodeIfPresent(Int.self, forKey: .agentsRunning)) ?? 0
        progress = try? values.decodeIfPresent(Progress.self, forKey: .progress)
    }
}

/// A Claude account, as far as a conversation's line needs it.
public struct VigieAccount: Decodable, Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }

    enum CodingKeys: String, CodingKey {
        case id, label
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        label = (try? values.decodeIfPresent(String.self, forKey: .label)) ?? id
    }
}

/// The engine's dates: ISO 8601 in UTC, with or without the milliseconds.
enum VigieDate {
    static func read<Key: CodingKey>(_ values: KeyedDecodingContainer<Key>, _ key: Key) -> Date? {
        guard let text = try? values.decodeIfPresent(String.self, forKey: key) else { return nil }
        return parse(text)
    }

    static func parse(_ text: String) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = precise.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }
}
