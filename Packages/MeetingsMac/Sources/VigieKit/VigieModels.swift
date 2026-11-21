import Foundation

/// What Vigie's engine says (21/11): the part of its API v2 that hub's « Vue d'ensemble » shows. Every field the
/// engine may leave out is optional here: an engine a version ahead or behind is still read.
public struct VigieOverview: Decodable, Equatable, Sendable {
    /// What waits for Paul, the most recent first.
    public var toReview: [VigieReview]
    public var conversations: [VigieConversation]
    public var accounts: [VigieAccount]
    /// The engine's general settings: Auto-accept, the questions, the safeguards.
    public var settings: VigieSettings?
    /// The engine's short sentences to show (an account's folder repaired…).
    public var notices: [String]
    /// What finished: a request, a workflow, a page published.
    public var reports: [VigieReport]

    public init(toReview: [VigieReview] = [], conversations: [VigieConversation] = [], accounts: [VigieAccount] = [],
                settings: VigieSettings? = nil, notices: [String] = [], reports: [VigieReport] = []) {
        self.toReview = toReview
        self.conversations = conversations
        self.accounts = accounts
        self.settings = settings
        self.notices = notices
        self.reports = reports
    }

    enum CodingKeys: String, CodingKey {
        case toReview, conversations, accounts, settings, engine, reports
    }

    enum EngineKeys: String, CodingKey {
        case notices
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Codex is left out of hub (Paul, 20/11): its conversations, its accounts and what they ask.
        conversations = (Self.each(values, .conversations) as [VigieConversation]).filter { !$0.isCodex }
        accounts = (Self.each(values, .accounts) as [VigieAccount]).filter { !$0.isCodex }
        let codex = Set((try? values.decodeIfPresent([Lenient<VigieConversation>].self, forKey: .conversations))??
            .compactMap(\.value).filter(\.isCodex).map(\.id) ?? [])
        toReview = (Self.each(values, .toReview) as [VigieReview]).filter { review in
            !review.isCodex && !(review.conversationID.map(codex.contains) ?? false)
        }
        settings = try? values.decodeIfPresent(VigieSettings.self, forKey: .settings)
        let engine = try? values.nestedContainer(keyedBy: EngineKeys.self, forKey: .engine)
        notices = ((try? engine?.decodeIfPresent([Lenient<VigieNotice>].self, forKey: .notices)) ?? [])?.compactMap(\.value?.text) ?? []
        reports = (Self.each(values, .reports) as [VigieReport]).filter { !($0.conversationID.map(codex.contains) ?? false) }
    }

    /// A conversation's short name, for a notification: its title, else its project.
    public func conversationName(_ id: String?, fallback: String?) -> String {
        let conversation = id.flatMap { id in conversations.first { $0.id == id } }
        let title = conversation?.title.isEmpty == false ? conversation?.title : fallback
        return title ?? conversation?.project ?? "Une conversation"
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

    /// What waits for Paul's decision now, as Vigie's red count (21/11): a sensitive action that waits, a question or a
    /// plan that waits, a conversation that waits in VS Code. The soonest refusal first, then the longest wait.
    public var decisions: [VigieReview] {
        // At equal times, the engine's order: a sort that keeps it.
        let waiting = toReview.filter(\.isDecision).enumerated()
        let timed = waiting.filter { $0.element.expiresAt != nil }
            .sorted { ($0.element.expiresAt ?? .distantFuture, $0.offset) < ($1.element.expiresAt ?? .distantFuture, $1.offset) }
        let untimed = waiting.filter { $0.element.expiresAt == nil }
            .sorted { ($0.element.at ?? .distantFuture, $0.offset) < ($1.element.at ?? .distantFuture, $1.offset) }
        return (timed + untimed).map(\.element)
    }

    /// The questions Vigie answered for Paul, to read again.
    public var toRead: [VigieReview] { toReview.filter { $0.kind == .question } }

    /// What is only to see: a refusal to do oneself, a limit reached, an account to connect again, a notice.
    public var toSee: [VigieReview] { toReview.filter { !$0.isDecision && $0.kind != .question } }
}

/// Something that finished: a request (`missionDone`), a workflow (`workflowDone`), a page published (`artifact`).
public struct VigieReport: Decodable, Equatable, Sendable {
    public var id: String?
    public var kind: String
    public var conversationID: String?
    public var conversationTitle: String?
    public var title: String?
    public var detail: String?
    /// The real request, without « continue ».
    public var prompt: String?
    /// The report ends with this question.
    public var question: String?
    /// What Claude leaves to Paul (« À toi : … »).
    public var toYou: String?
    public var duration: TimeInterval?
    /// A workflow: done, failed, killed.
    public var status: String?
    public var agentsFailed: Int?
    public var at: Date?

    public init(id: String? = nil, kind: String, conversationID: String? = nil, conversationTitle: String? = nil, title: String? = nil,
                detail: String? = nil, prompt: String? = nil, question: String? = nil, toYou: String? = nil, duration: TimeInterval? = nil,
                status: String? = nil, agentsFailed: Int? = nil, at: Date? = nil) {
        self.id = id
        self.kind = kind
        self.conversationID = conversationID
        self.conversationTitle = conversationTitle
        self.title = title
        self.detail = detail
        self.prompt = prompt
        self.question = question
        self.toYou = toYou
        self.duration = duration
        self.status = status
        self.agentsFailed = agentsFailed
        self.at = at
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, conversationId, conversationTitle, title, detail, prompt, question, toYou, durationMs, status, agentsFailed, ts
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try? values.decodeIfPresent(String.self, forKey: .id)
        kind = (try? values.decodeIfPresent(String.self, forKey: .kind)) ?? ""
        conversationID = try? values.decodeIfPresent(String.self, forKey: .conversationId)
        conversationTitle = try? values.decodeIfPresent(String.self, forKey: .conversationTitle)
        title = try? values.decodeIfPresent(String.self, forKey: .title)
        detail = try? values.decodeIfPresent(String.self, forKey: .detail)
        prompt = try? values.decodeIfPresent(String.self, forKey: .prompt)
        question = try? values.decodeIfPresent(String.self, forKey: .question)
        toYou = try? values.decodeIfPresent(String.self, forKey: .toYou)
        duration = (try? values.decodeIfPresent(Double.self, forKey: .durationMs)).map { $0 / 1_000 }
        status = try? values.decodeIfPresent(String.self, forKey: .status)
        agentsFailed = try? values.decodeIfPresent(Int.self, forKey: .agentsFailed)
        at = VigieDate.read(values, .ts)
    }
}

/// A sentence of the engine: a text, or an object with one.
struct VigieNotice: Decodable {
    let text: String

    enum Keys: String, CodingKey {
        case text, message, title
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
            self.text = text
            return
        }
        let values = try decoder.container(keyedBy: Keys.self)
        guard let text = (try? values.decode(String.self, forKey: .text)) ?? (try? values.decode(String.self, forKey: .message))
            ?? (try? values.decode(String.self, forKey: .title)), !text.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "avis vide"))
        }
        self.text = text
    }
}

/// The engine's general settings (`overview.settings`).
public struct VigieSettings: Decodable, Equatable, Sendable {
    public struct Safeguards: Decodable, Equatable, Sendable {
        public struct Rule: Decodable, Equatable, Sendable, Identifiable {
            public var id: String
            public var label: String
            public var disabled: Bool

            public init(id: String, label: String, disabled: Bool = false) {
                self.id = id
                self.label = label
                self.disabled = disabled
            }

            enum CodingKeys: String, CodingKey {
                case id, label, disabled
            }

            public init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                id = try values.decode(String.self, forKey: .id)
                label = (try? values.decodeIfPresent(String.self, forKey: .label)) ?? id
                disabled = (try? values.decodeIfPresent(Bool.self, forKey: .disabled)) ?? false
            }
        }

        public var enabled: Bool
        /// Minutes before an action left waiting is refused.
        public var waitMinutes: Int
        public var rules: [Rule]

        public init(enabled: Bool = true, waitMinutes: Int = 10, rules: [Rule] = []) {
            self.enabled = enabled
            self.waitMinutes = waitMinutes
            self.rules = rules
        }

        enum CodingKeys: String, CodingKey {
            case enabled, waitMin, rules
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            enabled = (try? values.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
            waitMinutes = (try? values.decodeIfPresent(Int.self, forKey: .waitMin)) ?? 10
            rules = ((try? values.decodeIfPresent([Lenient<Rule>].self, forKey: .rules)) ?? [])?.compactMap(\.value) ?? []
        }
    }

    public var autoAccept: Bool
    /// « Quand je ne suis pas là, Claude choisit l'option recommandée ».
    public var questionsAuto: Bool
    public var questionWaitMinutes: Int
    /// The account's MCP in new conversations: « on » or « off ».
    public var connectorsDefault: String?
    /// The engine installs Vigie's new versions by itself — and with them the app Vigie.
    public var autoUpdate: Bool?
    /// Chrome windows left behind by the agents are stopped by themselves.
    public var stopForgotten: Bool?
    public var safeguards: Safeguards

    public init(autoAccept: Bool = true, questionsAuto: Bool = false, questionWaitMinutes: Int = 20, connectorsDefault: String? = nil,
                autoUpdate: Bool? = nil, stopForgotten: Bool? = nil, safeguards: Safeguards = Safeguards()) {
        self.autoAccept = autoAccept
        self.questionsAuto = questionsAuto
        self.questionWaitMinutes = questionWaitMinutes
        self.connectorsDefault = connectorsDefault
        self.autoUpdate = autoUpdate
        self.stopForgotten = stopForgotten
        self.safeguards = safeguards
    }

    enum CodingKeys: String, CodingKey {
        case autoAccept, questionsAuto, questionWaitMin, connectorsDefault, autoUpdate, stopForgotten
        case safeguards = "guard"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        autoAccept = (try? values.decodeIfPresent(Bool.self, forKey: .autoAccept)) ?? true
        questionsAuto = (try? values.decodeIfPresent(Bool.self, forKey: .questionsAuto)) ?? false
        questionWaitMinutes = (try? values.decodeIfPresent(Int.self, forKey: .questionWaitMin)) ?? 20
        connectorsDefault = try? values.decodeIfPresent(String.self, forKey: .connectorsDefault)
        autoUpdate = try? values.decodeIfPresent(Bool.self, forKey: .autoUpdate)
        stopForgotten = try? values.decodeIfPresent(Bool.self, forKey: .stopForgotten)
        safeguards = (try? values.decodeIfPresent(Safeguards.self, forKey: .safeguards)) ?? Safeguards()
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
    /// A question that waits for Paul: its choices, to answer from hub (with `pendingID`).
    public var questions: [VigieQuestion.Item]
    /// Where the action runs, and which agent asked for it.
    public var cwd: String?
    public var byAgent: String?
    /// A refusal: why (« delai », « jamais », « sous-agent », « echec »).
    public var reason: String?
    /// A limit reached: on which account, which window, and when it starts again.
    public var accountID: String?
    public var scope: String?
    public var resetsAt: Date?

    public init(id: String, kind: Kind, conversationID: String? = nil, conversationTitle: String? = nil, title: String, detail: String? = nil,
                at: Date? = nil, state: String? = nil, pendingID: String? = nil, expiresAt: Date? = nil, rule: String? = nil,
                command: String? = nil, needsPassword: Bool = false, question: VigieQuestion? = nil, questions: [VigieQuestion.Item] = [],
                cwd: String? = nil, byAgent: String? = nil, reason: String? = nil, accountID: String? = nil, scope: String? = nil,
                resetsAt: Date? = nil) {
        self.questions = questions
        self.cwd = cwd
        self.byAgent = byAgent
        self.reason = reason
        self.accountID = accountID
        self.scope = scope
        self.resetsAt = resetsAt
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
        case questions, cwd, byAgent, reason, accountId, scope, resetsAt
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
        questions = ((try? values.decodeIfPresent([Lenient<VigieQuestion.Item>].self, forKey: .questions)) ?? [])?.compactMap(\.value) ?? []
        cwd = try? values.decodeIfPresent(String.self, forKey: .cwd)
        byAgent = try? values.decodeIfPresent(String.self, forKey: .byAgent)
        reason = try? values.decodeIfPresent(String.self, forKey: .reason)
        accountID = try? values.decodeIfPresent(String.self, forKey: .accountId)
        scope = try? values.decodeIfPresent(String.self, forKey: .scope)
        resetsAt = VigieDate.read(values, .resetsAt)
    }

    /// A sensitive action the conversation still waits on: « Autoriser » or « Refuser » answers it.
    public var isPendingDecision: Bool {
        kind == .blocked && state == "waiting" && pendingID != nil
    }

    /// What Vigie counts in red, « à décider »: a sensitive action that waits (`g:`), a question or a plan that waits
    /// (`w:`), a conversation that waits in VS Code (`c:`).
    public var isDecision: Bool {
        isPendingDecision || (kind == .waiting && (id.hasPrefix("w:") || id.hasPrefix("c:")))
    }

    /// Something to decide or to answer, or a question answered for Paul to read again; a notice is only to see.
    public var needsPaul: Bool {
        isDecision || kind == .question
    }

    /// A question that waits, with its choices: « Répondre » answers it from hub.
    public var canAnswer: Bool {
        id.hasPrefix("w:") && pendingID != nil && !questions.isEmpty
    }

    /// Codex's own (a hook to accept, an action held for it): left out of hub.
    public var isCodex: Bool {
        id == "codex-hook" || id.hasPrefix("v:")
    }

    /// A plan to approve (`ExitPlanMode`): the engine says it by its title only (`docs/api-v2.md`, `w:`; « Plan à
    /// valider » before 7/11/2026). It is approved in VS Code.
    public var isPlan: Bool {
        Self.planTitles.contains(title)
    }

    static let planTitles: Set<String> = ["Plan à approuver", "Plan à valider"]

    /// A command masked by the engine (a key in it): never copied.
    public var commandIsMasked: Bool {
        command?.contains("••••") ?? false
    }
}

public struct VigieQuestion: Decodable, Equatable, Sendable {
    public struct Option: Decodable, Equatable, Sendable, Hashable {
        public var label: String
        public var description: String?

        public init(label: String, description: String? = nil) {
            self.label = label
            self.description = description
        }
    }

    public struct Item: Decodable, Equatable, Sendable {
        public var question: String
        public var header: String?
        public var multiSelect: Bool
        public var options: [Option]
        /// What was chosen: one option, or several for a question with several answers.
        public var chosen: [String]

        public init(question: String, header: String? = nil, multiSelect: Bool = false, options: [Option] = [], chosen: [String] = []) {
            self.question = question
            self.header = header
            self.multiSelect = multiSelect
            self.options = options
            self.chosen = chosen
        }

        enum CodingKeys: String, CodingKey {
            case question, header, multiSelect, options, chosen
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            question = (try? values.decodeIfPresent(String.self, forKey: .question)) ?? ""
            header = try? values.decodeIfPresent(String.self, forKey: .header)
            multiSelect = (try? values.decodeIfPresent(Bool.self, forKey: .multiSelect)) ?? false
            options = ((try? values.decodeIfPresent([Lenient<Option>].self, forKey: .options)) ?? [])?.compactMap(\.value) ?? []
            // One text, or a list: the engine writes a list for several answers.
            if let one = try? values.decodeIfPresent(String.self, forKey: .chosen) {
                chosen = one.isEmpty ? [] : [one]
            } else {
                chosen = (try? values.decodeIfPresent([String].self, forKey: .chosen)) ?? []
            }
        }

        /// What was chosen, in words.
        public var chosenText: String? {
            chosen.isEmpty ? nil : chosen.joined(separator: ", ")
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
    /// The tool it runs in: « codex » is left out.
    public var agent: String?
    public var cwd: String?
    /// « S'emballe »: an unusual consumption, a test that fails in a loop, an agent that repeats itself.
    public var alert: Alert?

    public struct Alert: Decodable, Equatable, Sendable {
        public var kind: String?
        public var since: Date?
        public var reason: String?

        public init(kind: String? = nil, since: Date? = nil, reason: String? = nil) {
            self.kind = kind
            self.since = since
            self.reason = reason
        }

        enum CodingKeys: String, CodingKey {
            case kind, since, reason
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            kind = try? values.decodeIfPresent(String.self, forKey: .kind)
            since = VigieDate.read(values, .since)
            reason = try? values.decodeIfPresent(String.self, forKey: .reason)
        }
    }

    public var isCodex: Bool { agent == "codex" }

    public init(id: String, title: String, project: String? = nil, status: Status = .idle, running: Bool = false, accountID: String? = nil,
                lastActivity: Date? = nil, needsYou: Int = 0, headline: String? = nil, agentsRunning: Int = 0, progress: Progress? = nil,
                agent: String? = nil, cwd: String? = nil) {
        self.agent = agent
        self.cwd = cwd
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
        case id, title, project, status, running, accountId, lastActivity, needsYou, headline, agentsRunning, progress, agent, cwd, alert
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
        agent = try? values.decodeIfPresent(String.self, forKey: .agent)
        cwd = try? values.decodeIfPresent(String.self, forKey: .cwd)
        alert = try? values.decodeIfPresent(Alert.self, forKey: .alert)
    }
}

/// A Claude account, as far as a conversation's line needs it.
public struct VigieAccount: Decodable, Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    /// « codex » for Codex's account, left out.
    public var kind: String?
    /// Its 5-hour session and its week; nil when the reading is old (the engine never gives a stale one).
    public var session: Window?
    public var week: Window?
    /// The week of one model (« Fable »), from real sessions only.
    public var weekModel: Window?
    public var weekModelLabel: String?
    /// How old the reading is.
    public var observedAt: Date?
    public var email: String?
    /// Connected with another address than the one planned for it.
    public var wrongAccount: Bool
    public var connected: Bool
    /// What the vault saw of its connection: ok, restored, restoring, lost, dead, logged-out, unknown.
    public var loginState: String?
    /// The account of new conversations.
    public var isDefault: Bool
    /// Other accounts of Vigie connected to the same account of claude.ai.
    public var sameAs: [String]

    public struct Window: Decodable, Equatable, Sendable {
        public var percent: Double
        public var resetsAt: Date?
        /// The week will be full before it starts again, at this time.
        public var fullAt: Date?

        public init(percent: Double, resetsAt: Date? = nil, fullAt: Date? = nil) {
            self.percent = percent
            self.resetsAt = resetsAt
            self.fullAt = fullAt
        }

        enum CodingKeys: String, CodingKey {
            case pct, resetsAt, fullAt
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            percent = try values.decode(Double.self, forKey: .pct)
            resetsAt = VigieDate.read(values, .resetsAt)
            fullAt = VigieDate.read(values, .fullAt)
        }
    }

    public var isCodex: Bool { kind == "codex" }

    public init(id: String, label: String, kind: String? = nil, session: Window? = nil, week: Window? = nil, weekModel: Window? = nil,
                weekModelLabel: String? = nil, observedAt: Date? = nil, email: String? = nil, wrongAccount: Bool = false, connected: Bool = true,
                loginState: String? = nil, isDefault: Bool = false, sameAs: [String] = []) {
        self.id = id
        self.label = label
        self.kind = kind
        self.session = session
        self.week = week
        self.weekModel = weekModel
        self.weekModelLabel = weekModelLabel
        self.observedAt = observedAt
        self.email = email
        self.wrongAccount = wrongAccount
        self.connected = connected
        self.loginState = loginState
        self.isDefault = isDefault
        self.sameAs = sameAs
    }

    enum CodingKeys: String, CodingKey {
        case id, label, kind, usage, email, wrongAccount, connected, login, isDefault, sameAs
    }

    enum UsageKeys: String, CodingKey {
        case session, week, weekModel, observedAt
    }

    enum LoginKeys: String, CodingKey {
        case state
    }

    enum ModelKeys: String, CodingKey {
        case label
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        label = (try? values.decodeIfPresent(String.self, forKey: .label)) ?? id
        kind = try? values.decodeIfPresent(String.self, forKey: .kind)
        let usage = try? values.nestedContainer(keyedBy: UsageKeys.self, forKey: .usage)
        session = try? usage?.decodeIfPresent(Window.self, forKey: .session)
        week = try? usage?.decodeIfPresent(Window.self, forKey: .week)
        weekModel = try? usage?.decodeIfPresent(Window.self, forKey: .weekModel)
        weekModelLabel = (try? usage?.nestedContainer(keyedBy: ModelKeys.self, forKey: .weekModel))
            .flatMap { try? $0.decodeIfPresent(String.self, forKey: .label) }
        observedAt = usage.flatMap { VigieDate.read($0, .observedAt) }
        email = try? values.decodeIfPresent(String.self, forKey: .email)
        wrongAccount = (try? values.decodeIfPresent(Bool.self, forKey: .wrongAccount)) ?? false
        connected = (try? values.decodeIfPresent(Bool.self, forKey: .connected)) ?? true
        loginState = (try? values.nestedContainer(keyedBy: LoginKeys.self, forKey: .login)).flatMap { try? $0.decodeIfPresent(String.self, forKey: .state) }
        isDefault = (try? values.decodeIfPresent(Bool.self, forKey: .isDefault)) ?? false
        sameAs = (try? values.decodeIfPresent([String].self, forKey: .sameAs)) ?? []
    }

    /// To connect again: its connection is lost, refused, or it is not connected.
    public var needsConnecting: Bool {
        !connected || ["lost", "dead", "logged-out"].contains(loginState ?? "")
    }
}

/// The accounts' page (`GET /api/v2/accounts`): every Claude account, the one of new conversations, and VS Code's
/// launcher that runs each conversation on its account.
public struct VigieAccounts: Decodable, Equatable, Sendable {
    public var accounts: [VigieAccount]
    public var defaultForNew: String?
    /// VS Code runs its conversations through Vigie's launcher: without it, a conversation's account is not kept.
    public var launcherActive: Bool

    public init(accounts: [VigieAccount] = [], defaultForNew: String? = nil, launcherActive: Bool = true) {
        self.accounts = accounts
        self.defaultForNew = defaultForNew
        self.launcherActive = launcherActive
    }

    enum CodingKeys: String, CodingKey {
        case accounts, defaultForNew, wrapper
    }

    enum WrapperKeys: String, CodingKey {
        case active
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        accounts = (((try? values.decodeIfPresent([Lenient<VigieAccount>].self, forKey: .accounts)) ?? [])?.compactMap(\.value) ?? [])
            .filter { !$0.isCodex }
        defaultForNew = try? values.decodeIfPresent(String.self, forKey: .defaultForNew)
        launcherActive = (try? values.nestedContainer(keyedBy: WrapperKeys.self, forKey: .wrapper))
            .flatMap { try? $0.decodeIfPresent(Bool.self, forKey: .active) } ?? true
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
