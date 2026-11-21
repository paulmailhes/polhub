import Foundation

/// A conversation of Claude Code in detail (`GET /api/v2/conversation/:id`, 21/11, the migration's « page d'une
/// conversation »): what it does now, Paul's request, its last messages, its plan, its agents, its tests, its files, the
/// decisions Vigie took for it, its pages published. Every part may be missing: an engine a version ahead or behind is
/// still read. The engine keeps no detail past 48 hours (404).
public struct VigieConversationDetail: Decodable, Equatable, Sendable {
    public var summary: VigieConversation
    /// Its auto-accept, and whether it is set for this conversation only (`nil`: as the general setting).
    public var autoAccept: Bool
    public var autoAcceptOverride: Bool?
    public var branch: String?
    /// The request under way: Paul's words, what Claude says of it, and its counts.
    public var current: Current?
    public var messages: [Message]
    public var now: Now?
    public var chapters: [Chapter]
    public var accepted: [Decision]
    public var agents: [Agent]
    public var workflows: [Workflow]
    public var artifacts: [Artifact]
    public var files: [File]
    public var tests: [TestRun]
    /// « Fini, mais pas vérifié »: what the engine checked after the last change of code.
    public var checks: Checks?

    public struct Current: Decodable, Equatable, Sendable {
        public var prompt: String?
        public var brief: String?
        public var text: String?
        public var start: Date?
        public var agents: Int
        public var files: Int
        public var testsOk: Int
        public var testsFailed: Int
        public var commits: Int

        enum CodingKeys: String, CodingKey {
            case prompt, brief, text, start, agents, files, testsOk, testsFailed, commits
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            prompt = try? values.decodeIfPresent(String.self, forKey: .prompt)
            brief = try? values.decodeIfPresent(String.self, forKey: .brief)
            text = try? values.decodeIfPresent(String.self, forKey: .text)
            start = VigieDate.read(values, .start)
            agents = (try? values.decodeIfPresent(Int.self, forKey: .agents)) ?? 0
            files = (try? values.decodeIfPresent(Int.self, forKey: .files)) ?? 0
            testsOk = (try? values.decodeIfPresent(Int.self, forKey: .testsOk)) ?? 0
            testsFailed = (try? values.decodeIfPresent(Int.self, forKey: .testsFailed)) ?? 0
            commits = (try? values.decodeIfPresent(Int.self, forKey: .commits)) ?? 0
        }
    }

    public struct Message: Decodable, Equatable, Sendable {
        public var text: String
        public var brief: String?
        /// What Claude asks Paul, and what it leaves him.
        public var ask: String?
        public var toYou: String?
        public var at: Date?

        enum CodingKeys: String, CodingKey {
            case text, brief, ask, toYou, ts
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            text = (try? values.decodeIfPresent(String.self, forKey: .text)) ?? ""
            brief = try? values.decodeIfPresent(String.self, forKey: .brief)
            ask = try? values.decodeIfPresent(String.self, forKey: .ask)
            toYou = try? values.decodeIfPresent(String.self, forKey: .toYou)
            at = VigieDate.read(values, .ts)
        }
    }

    public struct Now: Decodable, Equatable, Sendable {
        public struct Step: Decodable, Equatable, Sendable {
            public var id: String?
            public var text: String
            /// done, doing, todo.
            public var status: String

            enum CodingKeys: String, CodingKey {
                case id, text, status
            }

            public init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                id = try? values.decodeIfPresent(String.self, forKey: .id)
                text = (try? values.decodeIfPresent(String.self, forKey: .text)) ?? ""
                status = (try? values.decodeIfPresent(String.self, forKey: .status)) ?? "todo"
            }
        }

        public struct Plan: Decodable, Equatable, Sendable {
            public var title: String?
            public var steps: [Step]
            public var done: Int
            public var total: Int
            public var current: String?

            enum CodingKeys: String, CodingKey {
                case title, steps, done, total, current
            }

            public init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                title = try? values.decodeIfPresent(String.self, forKey: .title)
                steps = ((try? values.decodeIfPresent([Lenient<Step>].self, forKey: .steps)) ?? [])?.compactMap(\.value) ?? []
                done = (try? values.decodeIfPresent(Int.self, forKey: .done)) ?? steps.filter { $0.status == "done" }.count
                total = (try? values.decodeIfPresent(Int.self, forKey: .total)) ?? steps.count
                current = try? values.decodeIfPresent(String.self, forKey: .current)
            }
        }

        /// Claude's last report, short.
        public var text: String?
        public var tasks: [Step]
        public var plan: Plan?

        enum CodingKeys: String, CodingKey {
            case text, tasks, plan
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            text = try? values.decodeIfPresent(String.self, forKey: .text)
            tasks = ((try? values.decodeIfPresent([Lenient<Step>].self, forKey: .tasks)) ?? [])?.compactMap(\.value) ?? []
            plan = try? values.decodeIfPresent(Plan.self, forKey: .plan)
        }
    }

    /// One of Paul's real requests, and what it gave.
    public struct Chapter: Decodable, Equatable, Sendable {
        public var prompt: String
        public var outcome: String?
        public var start: Date?
        public var duration: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case prompt, outcome, start, durationMs
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            prompt = (try? values.decodeIfPresent(String.self, forKey: .prompt)) ?? ""
            outcome = try? values.decodeIfPresent(String.self, forKey: .outcome)
            start = VigieDate.read(values, .start)
            duration = (try? values.decodeIfPresent(Double.self, forKey: .durationMs)).map { $0 / 1_000 }
        }
    }

    /// A decision of Vigie for this conversation: accepted alone, by Paul, held, refused.
    public struct Decision: Decodable, Equatable, Sendable {
        public var at: Date?
        public var kind: String
        public var title: String
        public var detail: String?
        /// auto, you, blocked, waiting, denied.
        public var decision: String
        public var agent: String?

        enum CodingKeys: String, CodingKey {
            case ts, kind, title, detail, decision, agent
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            at = VigieDate.read(values, .ts)
            kind = (try? values.decodeIfPresent(String.self, forKey: .kind)) ?? "other"
            title = (try? values.decodeIfPresent(String.self, forKey: .title)) ?? ""
            detail = try? values.decodeIfPresent(String.self, forKey: .detail)
            decision = (try? values.decodeIfPresent(String.self, forKey: .decision)) ?? "auto"
            agent = try? values.decodeIfPresent(String.self, forKey: .agent)
        }
    }

    public struct Agent: Decodable, Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var workflow: String?
        public var phase: String?
        public var lastAction: String?
        public var duration: TimeInterval?
        /// running, done, failed, killed, idle.
        public var status: String

        enum CodingKeys: String, CodingKey {
            case id, title, workflow, phase, lastAction, durationMs, status
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? values.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
            title = (try? values.decodeIfPresent(String.self, forKey: .title)) ?? "agent"
            workflow = try? values.decodeIfPresent(String.self, forKey: .workflow)
            phase = try? values.decodeIfPresent(String.self, forKey: .phase)
            lastAction = try? values.decodeIfPresent(String.self, forKey: .lastAction)
            duration = (try? values.decodeIfPresent(Double.self, forKey: .durationMs)).map { $0 / 1_000 }
            status = (try? values.decodeIfPresent(String.self, forKey: .status)) ?? "running"
        }
    }

    public struct Workflow: Decodable, Equatable, Sendable {
        public var name: String
        public var summary: String?
        public var status: String
        public var agents: Int

        enum CodingKeys: String, CodingKey {
            case name, summary, status, agents
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            name = (try? values.decodeIfPresent(String.self, forKey: .name)) ?? "workflow"
            summary = try? values.decodeIfPresent(String.self, forKey: .summary)
            status = (try? values.decodeIfPresent(String.self, forKey: .status)) ?? "running"
            agents = (try? values.decodeIfPresent(Int.self, forKey: .agents)) ?? 0
        }
    }

    public struct Artifact: Decodable, Equatable, Sendable {
        public var title: String
        public var url: String?
        public var description: String?
    }

    public struct File: Decodable, Equatable, Sendable {
        public var path: String
        public var name: String
        public var created: Bool
        public var writes: Int
        public var at: Date?
        public var by: String?
        /// project, elsewhere, scratch.
        public var location: String?

        enum CodingKeys: String, CodingKey {
            case path, name, created, writes, ts, by, location
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            path = (try? values.decodeIfPresent(String.self, forKey: .path)) ?? ""
            name = (try? values.decodeIfPresent(String.self, forKey: .name)) ?? (path as NSString).lastPathComponent
            created = (try? values.decodeIfPresent(Bool.self, forKey: .created)) ?? false
            writes = (try? values.decodeIfPresent(Int.self, forKey: .writes)) ?? 1
            at = VigieDate.read(values, .ts)
            by = try? values.decodeIfPresent(String.self, forKey: .by)
            location = try? values.decodeIfPresent(String.self, forKey: .location)
        }
    }

    public struct TestRun: Decodable, Equatable, Sendable {
        public var title: String
        /// nil while it runs.
        public var ok: Bool?
        public var passed: Int?
        public var failed: Int?
        public var at: Date?
        /// A red step wanted: shown neutral.
        public var expectedFail: Bool

        enum CodingKeys: String, CodingKey {
            case title, ok, passed, failed, ts, expectedFail
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            title = (try? values.decodeIfPresent(String.self, forKey: .title)) ?? "Tests"
            ok = try? values.decodeIfPresent(Bool.self, forKey: .ok)
            passed = try? values.decodeIfPresent(Int.self, forKey: .passed)
            failed = try? values.decodeIfPresent(Int.self, forKey: .failed)
            at = VigieDate.read(values, .ts)
            expectedFail = (try? values.decodeIfPresent(Bool.self, forKey: .expectedFail)) ?? false
        }
    }

    public struct Checks: Decodable, Equatable, Sendable {
        /// verified, unverified…
        public var verdict: String?
        public var label: String?
        public var notes: [String]
        public var uncommitted: Int?

        enum CodingKeys: String, CodingKey {
            case verdict, label, notes, uncommitted
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            verdict = try? values.decodeIfPresent(String.self, forKey: .verdict)
            label = try? values.decodeIfPresent(String.self, forKey: .label)
            notes = (try? values.decodeIfPresent([String].self, forKey: .notes)) ?? []
            uncommitted = try? values.decodeIfPresent(Int.self, forKey: .uncommitted)
        }
    }

    enum CodingKeys: String, CodingKey {
        case summary, current, messages, now, chapters, accepted, agents, workflows, artifacts, files, tests
    }

    enum SummaryKeys: String, CodingKey {
        case autoAccept, autoAcceptOverride, branch, checks
    }

    enum AgentKeys: String, CodingKey {
        case running, done
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        summary = try values.decode(VigieConversation.self, forKey: .summary)
        let extra = try values.nestedContainer(keyedBy: SummaryKeys.self, forKey: .summary)
        autoAccept = (try? extra.decodeIfPresent(Bool.self, forKey: .autoAccept)) ?? true
        autoAcceptOverride = try? extra.decodeIfPresent(Bool.self, forKey: .autoAcceptOverride)
        branch = try? extra.decodeIfPresent(String.self, forKey: .branch)
        checks = try? extra.decodeIfPresent(Checks.self, forKey: .checks)
        current = try? values.decodeIfPresent(Current.self, forKey: .current)
        messages = Self.list(values, .messages)
        now = try? values.decodeIfPresent(Now.self, forKey: .now)
        chapters = Self.list(values, .chapters)
        accepted = Self.list(values, .accepted)
        let agentLists = try? values.nestedContainer(keyedBy: AgentKeys.self, forKey: .agents)
        let running = ((try? agentLists?.decodeIfPresent([Lenient<Agent>].self, forKey: .running)) ?? [])?.compactMap(\.value) ?? []
        let done = ((try? agentLists?.decodeIfPresent([Lenient<Agent>].self, forKey: .done)) ?? [])?.compactMap(\.value) ?? []
        agents = running + done
        workflows = Self.list(values, .workflows)
        artifacts = Self.list(values, .artifacts)
        files = Self.list(values, .files)
        tests = Self.list(values, .tests)
    }

    static func list<Element: Decodable>(_ values: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [Element] {
        ((try? values.decodeIfPresent([Lenient<Element>].self, forKey: key)) ?? [])?.compactMap(\.value) ?? []
    }

    /// The agents at work now.
    public var running: [Agent] { agents.filter { $0.status == "running" } }
    /// The tests that failed lately, a red step wanted left out.
    public var failing: [TestRun] { tests.filter { $0.ok == false && !$0.expectedFail } }
    /// Paul's request under way: the current one, else the latest chapter's.
    public var request: String? { current?.prompt ?? chapters.first?.prompt }
}
