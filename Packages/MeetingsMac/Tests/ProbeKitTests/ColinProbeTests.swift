import Colin
import Foundation
import Observability
import Testing
@testable import ProbeKit

/// A Claude Code that is not there: its events are written by hand, and it remembers what it was told.
final class FakeSession: ClaudeSession, @unchecked Sendable {
    let events: AsyncStream<ClaudeEvent>
    let pid: Int32 = 4242
    private let continuation: AsyncStream<ClaudeEvent>.Continuation
    private let lock = NSLock()
    private var ended = false
    private var _sent: [String] = []
    private var _stopped = false
    private let onSend: @Sendable (String, Int) -> [ClaudeEvent]
    private let onInterrupt: @Sendable (String) -> [ClaudeEvent]
    private let onClose: @Sendable () -> [ClaudeEvent]
    private let onStop: @Sendable () -> [ClaudeEvent]
    private let endsWhenClosed: Bool
    private let errors: String
    private let stopCode: Int32
    private let stopDelay: Double

    var sent: [String] { lock.withLock { _sent } }
    var stopped: Bool { lock.withLock { _stopped } }
    /// Its process is gone.
    var isOver: Bool { lock.withLock { ended } }

    /// - Parameters:
    ///   - code: the launch answers `first` and ends with this code at once. `nil`: it stays open (a conversation,
    ///     or a Claude Code that never answers).
    ///   - errors: the end of its error output, told as it leaves.
    ///   - stopCode: the code it leaves with once stopped; `stopDelay`: how long it takes to leave.
    ///   - onClose, onStop: what it still writes when its input closes, and when it is stopped.
    init(_ first: [ClaudeEvent] = [], code: Int32? = nil, endsWhenClosed: Bool = true, errors: String = "",
         stopCode: Int32 = 130, stopDelay: Double = 0,
         onSend: @escaping @Sendable (String, Int) -> [ClaudeEvent] = { _, _ in [] },
         onInterrupt: @escaping @Sendable (String) -> [ClaudeEvent] = { _ in [] },
         onClose: @escaping @Sendable () -> [ClaudeEvent] = { [] },
         onStop: @escaping @Sendable () -> [ClaudeEvent] = { [] }) {
        (events, continuation) = AsyncStream.makeStream()
        self.onSend = onSend
        self.onInterrupt = onInterrupt
        self.onClose = onClose
        self.onStop = onStop
        self.endsWhenClosed = endsWhenClosed
        self.errors = errors
        self.stopCode = stopCode
        self.stopDelay = stopDelay
        for event in first { continuation.yield(event) }
        if let code { end(code) }
    }

    func send(_ text: String) {
        let count = lock.withLock { _sent.append(text); return _sent.count }
        for event in onSend(text, count) { continuation.yield(event) }
    }

    func interrupt(_ requestID: String) {
        for event in onInterrupt(requestID) { continuation.yield(event) }
    }

    func closeInput() {
        for event in onClose() { continuation.yield(event) }
        if endsWhenClosed { end(0) }
    }

    func stop() {
        let first = lock.withLock { if _stopped { return false }; _stopped = true; return true }
        guard first else { return }
        for event in onStop() { continuation.yield(event) }
        if stopDelay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + stopDelay) { [self] in end(stopCode) }
        } else {
            end(stopCode)
        }
    }

    private func end(_ code: Int32) {
        let first = lock.withLock { if ended { return false }; ended = true; return true }
        guard first else { return }
        continuation.yield(.exited(code: code, errors: errors))
        continuation.finish()
    }
}

/// Answers each launch from the command it receives, and keeps the commands in order.
final class FakeLauncher: ClaudeLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [ClaudeCommand] = []
    private var sessions: [FakeSession] = []
    private var folders: [URL] = []
    private var files: [Bool] = []
    private let failing: Set<Int>
    private let respond: @Sendable (ClaudeCommand, Int) -> FakeSession
    /// Called as each launch is asked, with its rank, before it starts or fails.
    var onStart: (@Sendable (Int) -> Void)?

    /// `failing`: the launches, by their rank, that cannot start at all.
    init(failing: Set<Int> = [], _ respond: @escaping @Sendable (ClaudeCommand, Int) -> FakeSession) {
        self.failing = failing
        self.respond = respond
    }

    var started: [ClaudeCommand] { lock.withLock { commands } }
    var all: [FakeSession] { lock.withLock { sessions } }
    var directories: [URL] { lock.withLock { folders } }
    /// For each launch: was a file of instructions waiting in its folder?
    var instructions: [Bool] { lock.withLock { files } }

    func start(_ command: ClaudeCommand, binary: URL, directory: URL) throws -> any ClaudeSession {
        let waiting = FileManager.default.fileExists(atPath: directory.appending(path: "CLAUDE.md").path(percentEncoded: false))
        let index = lock.withLock { folders.append(directory); files.append(waiting); return commands.count }
        onStart?(index)
        if failing.contains(index) {
            lock.withLock { commands.append(command) }
            throw CocoaError(.fileNoSuchFile)
        }
        let session = respond(command, index)
        lock.withLock { commands.append(command); sessions.append(session) }
        return session
    }
}

/// Counts the calls of a closure that several tasks may make.
final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func next() -> Int { lock.withLock { count += 1; return count } }
}

@Suite struct ColinProbeTests {
    static let secret = "RÉPONSE-À-NE-PAS-GARDER"
    static let home = URL(fileURLWithPath: "/Users/essai-de-sonde")
    let binary = URL(fileURLWithPath: "/Users/essai-de-sonde/.local/bin/claude")
    let helper = URL(fileURLWithPath: "/Applications/Essai.app/Contents/Helpers/polhub")

    // MARK: - A Claude Code where everything answers well

    static let loaded = ClaudeInit(version: "2.1.304", model: "claude-haiku-4-5", permissionMode: "dontAsk", apiKeySource: "none",
                                   builtinPlugins: 3, agents: ["claude", "Explore"])
    static let withServer = ClaudeInit(version: "2.1.304", model: "claude-opus-4-8", permissionMode: "dontAsk", apiKeySource: "none",
                                       tools: ["mcp__hub__projets", "mcp__hub__journal"], servers: ["hub": "connected"], builtinPlugins: 3)
    static let limit = ClaudeRateLimit(status: "allowed", type: "five_hour", fiveHour: 0.42, sevenDay: 0.11)
    static func done(_ cost: Double = 0.0002) -> ClaudeEvent {
        .result(ClaudeResult(subtype: "success", durationMs: 900, numTurns: 1, costUSD: cost, inputTokens: 900, outputTokens: 3, text: "ok " + secret))
    }

    static func ping() -> FakeSession { FakeSession([.initialized(loaded), .textDelta("ok"), .rateLimit(limit), done()], code: 0) }

    static func notConnected() -> FakeSession {
        FakeSession([.result(ClaudeResult(subtype: "success", isError: true, apiErrorStatus: 401, text: "Invalid API key · Please run /login"))], code: 1)
    }

    static func tools(denied: [String]) -> FakeSession {
        FakeSession([.initialized(withServer), .assistant(text: secret, tools: ["mcp__hub__projets"]), .toolResult(isError: false),
                     .assistant(text: "", tools: ["mcp__hub__journal"]), .toolResult(isError: true),
                     .result(ClaudeResult(subtype: "success", numTurns: 3, costUSD: 0.001, inputTokens: 2_000, outputTokens: 40, denied: denied, text: "fini"))], code: 0)
    }

    /// - Parameters:
    ///   - second: what the second message gets (a tool call and its answer when nothing is said).
    ///   - first: what it says it loaded; `interrupted`: how the interrupted turn ends; `extra`: lines written with
    ///     the first answer; `onClose`: what it still writes once its input is closed.
    static func conversation(initFirst: Bool = true, endsWhenClosed: Bool = true, second: [ClaudeEvent]? = nil,
                             first: ClaudeInit = withServer, interrupted: String = "error_during_execution", extra: [ClaudeEvent] = [],
                             onClose: @escaping @Sendable () -> [ClaudeEvent] = { [] }) -> FakeSession {
        FakeSession(initFirst ? [.initialized(first)] : [], endsWhenClosed: endsWhenClosed, onSend: { _, turn in
            let late: [ClaudeEvent] = !initFirst && turn == 1 ? [.initialized(first)] : []
            switch turn {
            case 2: return second ?? [.textDelta("Deux"), .assistant(text: secret, tools: ["mcp__hub__projets"]), .toolResult(isError: false), done(0.03)]
            case 3: return [.textDelta("1"), .other("stream_event/message_delta"), .other("un_message_inconnu")]
            default: return late + (turn == 1 ? extra : []) + [.textDelta("Bon"), .assistant(text: secret, tools: []), done(Double(turn) * 0.01)]
            }
        }, onInterrupt: { id in
            // As Claude Code does: its answer, its own mark of the interruption, then the turn's end in error.
            [.controlResponse(requestID: id, success: true), .other("user/interruption"),
             .result(ClaudeResult(subtype: interrupted, isError: true, costUSD: 0.04))]
        }, onClose: onClose)
    }

    /// Says nothing more after `first`, until it is stopped. Then, as the real Claude Code stopped during a turn
    /// (measured on 17/11): its own mark of the interruption, the turn's end in error, and it leaves with code 0.
    static func silent(_ first: [ClaudeEvent] = [], stopDelay: Double = 0) -> FakeSession {
        FakeSession(first, endsWhenClosed: false, stopCode: 0, stopDelay: stopDelay, onStop: {
            [.other("user/interruption"), .result(ClaudeResult(subtype: "error_during_execution", isError: true, costUSD: 0.001))]
        })
    }

    /// Holds the task of a run, for a launcher that must stop it.
    final class Running: @unchecked Sendable {
        private let lock = NSLock()
        private var task: Task<[ColinMeasure], any Error>?
        func hold(_ task: Task<[ColinMeasure], any Error>) { lock.withLock { self.task = task } }
        func cancel() {
            for _ in 0..<200 where lock.withLock({ task }) == nil { usleep(5_000) }
            lock.withLock { task }?.cancel()
        }
    }

    /// Every launch answers; `override` changes one of them.
    static func healthy(failing: Set<Int> = [], _ override: @escaping @Sendable (ClaudeCommand, Int) -> FakeSession? = { _, _ in nil }) -> FakeLauncher {
        FakeLauncher(failing: failing) { command, index in
            if let session = override(command, index) { return session }
            if command.configDirectory?.lastPathComponent == "compte-vide" { return notConnected() }
            guard let prompt = command.prompt else { return conversation() }
            if prompt.hasPrefix("Appelle l'outil projets") { return tools(denied: ["mcp__hub__journal"]) }
            // The first launch asks for the word of the folder's instructions; the others only « ok ».
            if prompt == "Réponds seulement : ok" || prompt == ColinProbeTexts.memoryRequest { return ping() }
            return FakeSession([.initialized(loaded), done(0.05)], code: 0)
        }
    }

    static let answers: ColinProbe.Tool = { _, arguments, _ in
        if arguments == ["--version"] { return (0, "2.1.304 (Claude Code)\n") }
        if arguments.first == "auth" { return (0, #"{"loggedIn":true,"authMethod":"claude.ai","email":"quelquun@exemple.fr"}"#) }
        return (0, "  0:01.50 204800\n")
    }

    func probe(_ launcher: FakeLauncher, binary: URL?, helper: URL?, pings: Int = 3, pause: Double = 0, timeout: Double = 5,
               tool: @escaping ColinProbe.Tool = answers, folderName: String? = nil) -> ColinProbe {
        ColinProbe(launcher: launcher, binary: binary, helper: helper, home: Self.home, environment: ["HOME": Self.home.path, "PATH": "/usr/bin:/bin"],
                   pings: pings, pause: pause, timeout: timeout, initWait: 0.5, interruptDelay: 0, tool: tool, busySessions: { _ in 2 },
                   folderName: folderName)
    }

    func folder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "sonde-colin-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    struct Line: Decodable { let kind: String; let data: ColinMeasure }

    func measures(in directory: URL) throws -> [ColinMeasure] {
        let text = try String(contentsOf: directory.appending(path: "trace.jsonl"), encoding: .utf8)
        return try text.split(separator: "\n").map { try JSONDecoder().decode(Line.self, from: Data($0.utf8)) }.filter { $0.kind == "colin" }.map(\.data)
    }

    func run(_ probe: ColinProbe, variant: String? = nil, in directory: URL? = nil) async throws -> (directory: URL, measures: [ColinMeasure]) {
        let directory = directory ?? folder()
        let trace = try TraceWriter(fileURL: directory.appending(path: "trace.jsonl"))
        await probe.run(ProbeRequest(probe: .colin, variant: variant), trace: trace, directory: directory)
        await trace.close()
        return (directory, try measures(in: directory))
    }

    func step(_ name: String, _ measures: [ColinMeasure]) -> ColinMeasure? { measures.first { $0.step == name } }

    // MARK: - Tests

    @Test func aHealthyClaudeGivesAGreenReport() async throws {
        let launcher = Self.healthy()
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper))
        #expect(measures.map(\.step) == ["binaire", "compte", "connexion", "isolation", "connexions", "outils", "conversation",
                                         "premier-mot", "premier-mot", "premier-mot", "premier-mot",
                                         "scene", "scene", "scene", "panne", "invisible", "limites", "bilan"], "\(measures.map(\.step))")
        let failed = measures.filter { !$0.ok }
        #expect(failed.isEmpty, "\(failed)")
        #expect(step("binaire", measures)?.labels == ["sorte": "officiel", "version": "2.1.304"])
        #expect(step("compte", measures)?.numbers["connecte"] == 1)
        #expect(step("compte", measures)?.labels["methode"] == "claude.ai")
        #expect(step("connexion", measures)?.labels["cle"] == "none")
        #expect(step("connexion", measures)?.numbers["coutUSD"] == 0.0002)
        #expect(step("connexion", measures)?.numbers["entree"] == 900)
        #expect(step("connexion", measures)?.numbers["premierMotMs"] != nil)
        // Claude Code's own plugins and agents are told, and are no fault.
        #expect(step("isolation", measures)?.numbers == ["outils": 0, "serveurs": 0, "plugins": 0, "pluginsIntegres": 3, "skills": 0, "commandes": 0,
                                                         "memoires": 0, "dossiers": 0, "agents": 2, "messagerie": 0, "hooks": 0, "consigneLue": 0, "contexte": 900])
        #expect(step("isolation", measures)?.labels == [:])
        // A file of instructions waited in the folder of every launch, and the first one asked for its word.
        #expect(launcher.started.first?.prompt == ColinProbeTexts.memoryRequest)
        #expect(launcher.instructions.count == 13 && launcher.instructions.allSatisfy { $0 })
        #expect(step("connexions", measures)?.numbers["lancements"] == 3)
        #expect(step("connexions", measures)?.numbers["reussis"] == 3)
        #expect(step("connexions", measures)?.numbers["connecteApres"] == 1)
        let conversation = try #require(step("conversation", measures))
        #expect(conversation.numbers["initAvantMessage"] == 1)
        #expect(conversation.numbers["interruptionRecue"] == 1)
        #expect(conversation.numbers["appels2"] == 1)
        #expect(conversation.numbers["inattendus"] == 1)
        #expect(conversation.numbers["cout4"] == 0.04)
        #expect(conversation.numbers["cpuS"] == 1.5)
        #expect(conversation.numbers["memoireMo"] == 200)
        #expect(conversation.numbers["code"] == 0)
        #expect(conversation.labels["finInterrompue"] == "error_during_execution")
        #expect(conversation.labels["modele"] == "claude-opus-4-8")
        #expect(conversation.numbers["inits"] == 1)
        #expect(measures.filter { $0.step == "premier-mot" }.compactMap { $0.labels["nom"] } == ["opus", "opus-low", "sonnet", "haiku"])
        #expect(measures.filter { $0.step == "scene" }.compactMap { $0.labels["nom"] } == ["fiche-mail", "brouillon", "compte-rendu"])
        #expect(step("panne", measures)?.labels["categorie"] == "pas-connecte")
        #expect(step("limites", measures)?.numbers["cinqHeuresAvant"] == 42)
        #expect(step("limites", measures)?.numbers["semaineApres"] == 11)
        #expect(step("limites", measures)?.numbers["conversationsAuTravailAvant"] == 2)
        #expect(step("limites", measures)?.numbers["conversationsAuTravailApres"] == 2)
        #expect(step("bilan", measures)?.labels["fin"] == "complete")
        #expect(step("bilan", measures)?.numbers["echecs"] == 0)
        // The one line nobody expected, in the conversation, is counted for the whole run and named.
        #expect(step("bilan", measures)?.numbers["inattendus"] == 1)
        #expect(step("bilan", measures)?.labels["inattendus"] == "un_message_inconnu")
        #expect(ColinProbe.verdict(in: directory) == true)
        #expect(ColinProbe.reason(in: directory) == nil)
        // Nothing of the run stays but its trace and its report.
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted() == ["bilan.json", "trace.jsonl"])
        // 3 pings, the tools, the conversation, 4 first words, 3 scenes, the empty account.
        #expect(launcher.started.count == 13)
        #expect(launcher.all.allSatisfy { !$0.stopped })
        let low = launcher.started.first { $0.effort == "low" }
        #expect(low?.model == "opus" && low?.prompt == "Dis bonjour en une phrase.")
    }

    @Test func anIsolationThatLeaksStopsTheProbe() async throws {
        // A plugin of the user, a memory file: Claude Code loaded more than what was asked. Nothing more is sent to it.
        let leaking = ClaudeInit(version: "2.1.304", model: "claude-haiku-4-5", permissionMode: "dontAsk", apiKeySource: "none",
                                 plugins: 1, builtinPlugins: 3, memoryPaths: 1)
        let launcher = Self.healthy { _, index in index == 0 ? FakeSession([.initialized(leaking), Self.done()], code: 0) : nil }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper))
        #expect(step("isolation", measures)?.ok == false)
        #expect(step("isolation", measures)?.numbers["plugins"] == 1)
        #expect(step("isolation", measures)?.numbers["memoires"] == 1)
        #expect(launcher.started.count == 1)
        #expect(Array(measures.map(\.step).suffix(2)) == ["isolation", "bilan"])
        #expect(ColinProbe.reason(in: directory) == "isolation")
    }

    @Test func anInitWithoutItsListsFailsTheIsolation() async throws {
        // A Claude Code that no longer says what it loaded: « nothing loaded » is not checked, and is not said.
        let silent = ClaudeInit(version: "9.9.9", model: "claude-haiku-4-5", permissionMode: "dontAsk", apiKeySource: "none", missing: ["plugins", "skills"])
        let launcher = Self.healthy { _, index in index == 0 ? FakeSession([.initialized(silent), Self.done()], code: 0) : nil }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper))
        #expect(step("isolation", measures)?.ok == false)
        #expect(step("isolation", measures)?.labels["champsAbsents"] == "plugins,skills")
        #expect(launcher.started.count == 1)
        // Not « it loaded more »: nothing says what it loaded.
        #expect(ColinProbe.reason(in: directory) == "isolation-inconnue")
    }

    @Test func aClaudeThatReadTheFoldersInstructionsIsNotIsolated() async throws {
        // It answers the word of the file: the file was read, whatever its first line says of what it loaded.
        let knows = FakeSession([.initialized(Self.loaded),
                                 .result(ClaudeResult(subtype: "success", inputTokens: 900, text: "Le mot est \(ColinProbeTexts.memoryWord)."))], code: 0)
        let launcher = Self.healthy { _, index in index == 0 ? knows : nil }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper))
        #expect(step("isolation", measures)?.ok == false)
        #expect(step("isolation", measures)?.numbers["consigneLue"] == 1)
        #expect(launcher.started.count == 1)
        #expect(ColinProbe.reason(in: directory) == "isolation")
        // The answer itself is never kept, not even this invented word.
        let trace = try String(contentsOf: directory.appending(path: "trace.jsonl"), encoding: .utf8)
        #expect(!trace.contains(ColinProbeTexts.memoryWord))
    }

    @Test func aFirstLaunchThatReadTooMuchIsNotIsolated() async throws {
        // More was read than the few sentences given: instructions of the user's, a memory. A size that is not
        // told proves nothing either.
        for (tokens, reason) in [(2_400, "isolation"), (0, "isolation-inconnue")] {
            let heavy = FakeSession([.initialized(Self.loaded), .result(ClaudeResult(subtype: "success", inputTokens: tokens, text: "inconnu"))], code: 0)
            let launcher = Self.healthy { _, index in index == 0 ? heavy : nil }
            let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper))
            #expect(step("isolation", measures)?.ok == false, "\(tokens)")
            #expect(step("isolation", measures)?.numbers["contexte"] == Double(tokens), "\(tokens)")
            #expect(launcher.started.count == 1, "\(tokens)")
            #expect(ColinProbe.reason(in: directory) == reason, "\(tokens)")
        }
    }

    @Test func aHookThatRanIsNotIsolated() async throws {
        // A hook of the user's ran in the launch: Claude Code read his settings, whatever its first line says.
        let hooked = FakeSession([.initialized(Self.loaded), .other("system/hook_started"), .other("system/hook_response"), Self.done()], code: 0)
        let launcher = Self.healthy { _, index in index == 0 ? hooked : nil }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper))
        #expect(step("isolation", measures)?.ok == false)
        #expect(step("isolation", measures)?.numbers["hooks"] == 2)
        #expect(launcher.started.count == 1)
        #expect(ColinProbe.reason(in: directory) == "isolation")
        #expect(step("bilan", measures)?.labels["inattendus"] == "system/hook_response,system/hook_started")
    }

    @Test func aHookInALaterLaunchIsCountedAndNamed() async throws {
        // Claude Code's own notices are expected; a hook is not one of them, in whatever launch.
        let launcher = Self.healthy { command, _ in
            command.prompt == "Dis bonjour en une phrase." && command.model == "sonnet"
                ? FakeSession([.initialized(Self.loaded), .other("system/status"), .other("system/hook_started"), Self.done()], code: 0) : nil
        }
        let measures = try await run(probe(launcher, binary: binary, helper: helper)).measures
        #expect(step("bilan", measures)?.numbers["inattendus"] == 2)
        #expect(step("bilan", measures)?.labels["inattendus"] == "system/hook_started,un_message_inconnu")
    }

    @Test func theConversationSaysItsFourMessagesAndInterruptsTheThird() async throws {
        let launcher = Self.healthy()
        _ = try await run(probe(launcher, binary: binary, helper: helper))
        let index = try #require(launcher.started.firstIndex { $0.prompt == nil })
        #expect(launcher.all[index].sent.count == 4)
        #expect(launcher.started[index].model == "opus")
        #expect(launcher.started[index].allowedTools == ["mcp__hub__projets"])
        #expect(launcher.started[index].mcpConfig?.contains("/Applications/Essai.app/Contents/Helpers/polhub") == true)
    }

    @Test func aClaudeThatIsNotConnectedStopsTheProbeAtOnce() async throws {
        let launcher = FakeLauncher { _, _ in Self.notConnected() }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper))
        #expect(launcher.started.count == 1)
        #expect(measures.map(\.step) == ["binaire", "compte", "connexion", "panne", "bilan"], "\(measures.map(\.step))")
        #expect(step("connexion", measures)?.ok == false)
        #expect(step("panne", measures)?.labels["categorie"] == "pas-connecte")
        #expect(step("panne", measures)?.numbers["statutAPI"] == 401)
        #expect(step("bilan", measures)?.ok == false)
        #expect(step("bilan", measures)?.labels["fin"] == "arretee")
        #expect(ColinProbe.verdict(in: directory) == false)
        #expect(ColinProbe.reason(in: directory) == "pas-connecte")
    }

    // MARK: - A breakdown at any launch stops the probe

    @Test func aClaudeThatDisconnectsMidwayStopsTheProbe() async throws {
        // The third launch in a row says « not connected »: nothing is launched after it.
        let launcher = Self.healthy { _, index in index == 2 ? Self.notConnected() : nil }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper, pings: 5))
        #expect(launcher.started.count == 3)
        #expect(measures.map(\.step) == ["binaire", "compte", "connexion", "isolation", "connexions", "panne", "bilan"], "\(measures.map(\.step))")
        #expect(step("connexions", measures)?.numbers["lancements"] == 3)
        #expect(step("connexions", measures)?.numbers["reussis"] == 2)
        #expect(step("panne", measures)?.labels["categorie"] == "pas-connecte")
        #expect(step("bilan", measures)?.labels["fin"] == "arretee")
        #expect(ColinProbe.reason(in: directory) == "pas-connecte")
    }

    @Test func aClaudeThatGoesSilentMidwayStopsTheProbe() async throws {
        let launcher = Self.healthy { _, index in index == 2 ? FakeSession(endsWhenClosed: false) : nil }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper, pings: 5, timeout: 0.5))
        #expect(launcher.started.count == 3)
        #expect(launcher.all[2].stopped)
        #expect(step("panne", measures)?.labels["categorie"] == "sans-reponse")
        #expect(measures.last?.labels["fin"] == "arretee")
        #expect(ColinProbe.reason(in: directory) == "sans-reponse")
    }

    @Test func anAccountNoLongerConnectedAfterTheLaunchesStopsTheProbe() async throws {
        let calls = Calls()
        let tool: ColinProbe.Tool = { url, arguments, environment in
            if arguments.first == "auth" { return (0, calls.next() == 1 ? #"{"loggedIn":true}"# : #"{"loggedIn":false}"#) }
            return await Self.answers(url, arguments, environment)
        }
        let launcher = Self.healthy()
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper, tool: tool))
        #expect(launcher.started.count == 3)
        #expect(step("connexions", measures)?.numbers["connecteApres"] == 0)
        #expect(Array(measures.map(\.step).suffix(2)) == ["connexions", "bilan"])
        #expect(ColinProbe.reason(in: directory) == "pas-connecte")
    }

    @Test func anAccountNotConnectedLaunchesNothing() async throws {
        let tool: ColinProbe.Tool = { url, arguments, environment in
            if arguments.first == "auth" { return (0, #"{"loggedIn":false,"authMethod":"none"}"#) }
            return await Self.answers(url, arguments, environment)
        }
        let launcher = Self.healthy()
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper, tool: tool))
        #expect(launcher.started.isEmpty)
        #expect(measures.map(\.step) == ["binaire", "compte", "bilan"])
        #expect(ColinProbe.reason(in: directory) == "pas-connecte")
    }

    @Test func aLaterLaunchThatBreaksStopsTheProbeToo() async throws {
        // The launch of the tools is the fourth: not connected there, and neither the conversation nor the scenes run.
        let launcher = Self.healthy { command, _ in command.prompt?.hasPrefix("Appelle l'outil projets") == true ? Self.notConnected() : nil }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper))
        #expect(launcher.started.count == 4)
        #expect(Array(measures.map(\.step).suffix(3)) == ["outils", "panne", "bilan"])
        #expect(ColinProbe.reason(in: directory) == "pas-connecte")
    }

    @Test func aClaudeThatCannotStartIsToldSo() async throws {
        let launcher = FakeLauncher(failing: [0]) { _, _ in Self.ping() }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper))
        #expect(launcher.started.count == 1)
        #expect(step("connexion", measures)?.ok == false)
        #expect(step("panne", measures)?.labels["categorie"] == "lancement-impossible")
        #expect(ColinProbe.reason(in: directory) == "lancement-impossible")
    }

    @Test func aTurnThatNeverAnswersIsKilled() async throws {
        // The second message of the conversation gets no answer: the process is stopped, and the probe with it.
        let launcher = Self.healthy { command, _ in command.prompt == nil ? Self.conversation(endsWhenClosed: false, second: []) : nil }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper, timeout: 0.5))
        let index = try #require(launcher.started.firstIndex { $0.prompt == nil })
        #expect(launcher.all[index].stopped)
        #expect(launcher.all[index].sent.count == 2)
        #expect(step("conversation", measures)?.ok == false)
        #expect(step("conversation", measures)?.labels["delai"] == "tour 2")
        #expect(Array(measures.map(\.step).suffix(3)) == ["conversation", "panne", "bilan"])
        #expect(ColinProbe.reason(in: directory) == "sans-reponse")
    }

    @Test func aTurnInErrorEndsTheConversation() async throws {
        let refused: [ClaudeEvent] = [.result(ClaudeResult(subtype: "success", isError: true, apiErrorStatus: 401, text: "Please run /login"))]
        let launcher = Self.healthy { command, _ in command.prompt == nil ? Self.conversation(second: refused) : nil }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper))
        let index = try #require(launcher.started.firstIndex { $0.prompt == nil })
        // No third message after a turn in error, and no launch after the conversation.
        #expect(launcher.all[index].sent.count == 2)
        #expect(launcher.started.count == 5)
        #expect(step("conversation", measures)?.ok == false)
        #expect(measures.last?.labels["fin"] == "arretee")
        #expect(ColinProbe.reason(in: directory) == "pas-connecte")
    }

    @Test func aConversationCancelledMidwayStopsItsProcess() async throws {
        // The first message never gets its answer; the probe is stopped meanwhile.
        let silent = FakeSession([.initialized(Self.withServer)], endsWhenClosed: false)
        let launcher = Self.healthy { command, _ in command.prompt == nil ? silent : nil }
        let directory = folder()
        let probe = probe(launcher, binary: binary, helper: helper, timeout: 30)
        let task = Task { try await run(probe, in: directory).measures }
        for _ in 0..<500 where silent.sent.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        task.cancel()
        let measures = try await task.value
        #expect(silent.stopped)
        #expect(measures.last?.labels["fin"] == "interrompue")
        #expect(ColinProbe.verdict(in: directory) == nil)
    }

    @Test func aMessageNobodySentIsCountedInAnyLaunch() async throws {
        // A line of the user's kind that the probe did not write, in a launch that answers once: it could come from
        // another session, and is counted for the whole run.
        let launcher = Self.healthy { command, _ in
            command.prompt == "Dis bonjour en une phrase." && command.model == "sonnet"
                ? FakeSession([.initialized(Self.loaded), .other("user"), Self.done()], code: 0) : nil
        }
        let measures = try await run(probe(launcher, binary: binary, helper: helper)).measures
        #expect(step("bilan", measures)?.numbers["inattendus"] == 2)
        #expect(step("bilan", measures)?.labels["inattendus"] == "un_message_inconnu,user")
    }

    @Test func aVersionThatDoesNotLookLikeOneIsNotKept() async throws {
        let tool: ColinProbe.Tool = { url, arguments, environment in
            if arguments == ["--version"] { return (0, "/Users/essai-de-sonde/bizarre: commande inconnue\n") }
            return await Self.answers(url, arguments, environment)
        }
        let measures = try await run(probe(Self.healthy(), binary: binary, helper: helper, tool: tool)).measures
        #expect(step("binaire", measures)?.labels["version"] == "")
    }

    // MARK: - Every launch, and every way to break

    @Test func aFirstWordLaunchThatBreaksStopsTheProbe() async throws {
        // The second of the four first words (Opus at a low effort) says « not connected ».
        let launcher = Self.healthy { command, _ in command.effort == "low" ? Self.notConnected() : nil }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper))
        #expect(launcher.started.count == 7)
        #expect(Array(measures.map(\.step).suffix(4)) == ["premier-mot", "premier-mot", "panne", "bilan"])
        #expect(ColinProbe.reason(in: directory) == "pas-connecte")
    }

    @Test func aSceneThatGoesSilentStopsTheProbe() async throws {
        let launcher = Self.healthy { command, _ in
            command.prompt?.hasPrefix("Voici la transcription") == true ? FakeSession(endsWhenClosed: false) : nil
        }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper, timeout: 0.5))
        #expect(launcher.started.count == 12)
        #expect(Array(measures.map(\.step).suffix(3)) == ["scene", "panne", "bilan"])
        #expect(step("panne", measures)?.labels["categorie"] == "sans-reponse")
        #expect(ColinProbe.reason(in: directory) == "sans-reponse")
    }

    @Test func aSceneThatCannotStartStopsTheProbe() async throws {
        // The eleventh launch is the second scene.
        let launcher = Self.healthy(failing: [10])
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper))
        #expect(launcher.started.count == 11)
        #expect(Array(measures.map(\.step).suffix(2)) == ["panne", "bilan"])
        #expect(ColinProbe.reason(in: directory) == "lancement-impossible")
    }

    @Test func aConversationThatCannotStartStopsTheProbe() async throws {
        // Three launches in a row, the tools, then the conversation: the fifth.
        let launcher = Self.healthy(failing: [4])
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper))
        #expect(launcher.started.count == 5)
        #expect(Array(measures.map(\.step).suffix(3)) == ["conversation", "panne", "bilan"])
        #expect(ColinProbe.reason(in: directory) == "lancement-impossible")
    }

    @Test func aLaunchInARowThatBreaksIsNotFollowedByAnotherLookAtTheAccount() async throws {
        let calls = Calls()
        let tool: ColinProbe.Tool = { url, arguments, environment in
            if arguments.first == "auth" { _ = calls.next() }
            return await Self.answers(url, arguments, environment)
        }
        let launcher = Self.healthy(failing: [1])
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper, tool: tool))
        #expect(launcher.started.count == 2)
        // The account was looked at once, before the launches: Claude Code is not started again after the breakdown.
        #expect(calls.next() == 2)
        #expect(step("connexions", measures)?.numbers["connecteApres"] == -1)
        #expect(ColinProbe.reason(in: directory) == "lancement-impossible")
    }

    @Test func aClaudeThatDiesWithoutAnAnswerIsABreakdown() async throws {
        // Gone before saying anything (a code 127, a crash): it could not start. Gone after its first line: no answer.
        let first = FakeLauncher { _, _ in FakeSession([], code: 127) }
        let (one, firstMeasures) = try await run(probe(first, binary: binary, helper: helper))
        #expect(first.started.count == 1)
        #expect(step("panne", firstMeasures)?.labels["categorie"] == "lancement-impossible")
        #expect(ColinProbe.reason(in: one) == "lancement-impossible")

        let third = Self.healthy { _, index in index == 2 ? FakeSession([.initialized(Self.loaded)], code: 1) : nil }
        let (two, _) = try await run(probe(third, binary: binary, helper: helper, pings: 5))
        #expect(third.started.count == 3)
        #expect(ColinProbe.reason(in: two) == "sans-reponse")
    }

    @Test func anAccountAtItsLimitIsNamed() async throws {
        let refused: [ClaudeEvent] = [.initialized(Self.loaded), .rateLimit(ClaudeRateLimit(status: "rejected", type: "seven_day", sevenDay: 1)),
                                      .result(ClaudeResult(subtype: "success", isError: true, apiErrorStatus: 429, text: "limite"))]
        let launcher = Self.healthy { _, index in index == 1 ? FakeSession(refused, code: 1) : nil }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper))
        #expect(launcher.started.count == 2)
        #expect(step("panne", measures)?.labels["categorie"] == "limite-atteinte")
        #expect(ColinProbe.reason(in: directory) == "limite-atteinte")
        // Where the account stands is said at whatever end.
        #expect(step("bilan", measures)?.labels["limites"] == "rejected")
        #expect(step("bilan", measures)?.numbers["semaine"] == 100)
    }

    @Test func aFirstLaunchInErrorSaysSo() async throws {
        let launcher = FakeLauncher { _, _ in
            FakeSession([.initialized(Self.loaded), .result(ClaudeResult(subtype: "error_during_execution", isError: true, text: "boum"))], code: 1)
        }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper))
        #expect(launcher.started.count == 1)
        #expect(step("panne", measures)?.labels["categorie"] == "autre")
        #expect(ColinProbe.reason(in: directory) == "erreur")
    }

    @Test func aLaunchThatAnsweredButWasSlowToLeaveIsNoBreakdown() async throws {
        // The answer came; the process only took its time to end, and was stopped. Not « no answer ».
        let slow = FakeSession([.initialized(Self.loaded), Self.done()], endsWhenClosed: false)
        let launcher = Self.healthy { command, _ in command.effort == "low" ? slow : nil }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper, timeout: 0.5))
        #expect(slow.stopped)
        #expect(step("bilan", measures)?.labels["fin"] == "complete")
        #expect(ColinProbe.reason(in: directory) == nil)
    }

    @Test func aConversationWhoseProcessDiesIsABreakdown() async throws {
        let launcher = Self.healthy { command, _ in command.prompt == nil ? FakeSession([.initialized(Self.withServer)], code: 1) : nil }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper))
        #expect(launcher.started.count == 5)
        #expect(Array(measures.map(\.step).suffix(3)) == ["conversation", "panne", "bilan"])
        #expect(ColinProbe.reason(in: directory) == "sans-reponse")
    }

    @Test func theEmptyAccountThatStaysSilentIsNotAGoodFailure() async throws {
        let launcher = Self.healthy { command, _ in
            command.configDirectory?.lastPathComponent == "compte-vide" ? FakeSession(endsWhenClosed: false) : nil
        }
        let measures = try await run(probe(launcher, binary: binary, helper: helper, timeout: 0.5)).measures
        #expect(measures.last { $0.step == "panne" }?.ok == false)
        #expect(step("bilan", measures)?.ok == false)
        #expect(step("bilan", measures)?.labels["fin"] == "complete")
    }

    @Test func theMarkOfAnInterruptionIsExpectedOnlyWhereTheProbeInterrupts() async throws {
        // In a launch that answers once, nobody interrupts: the mark there was not asked for.
        let launcher = Self.healthy { command, _ in
            command.prompt == "Dis bonjour en une phrase." && command.model == "sonnet"
                ? FakeSession([.initialized(Self.loaded), .other("user/interruption"), Self.done()], code: 0) : nil
        }
        let measures = try await run(probe(launcher, binary: binary, helper: helper)).measures
        #expect(step("bilan", measures)?.numbers["inattendus"] == 2)
    }

    // MARK: - Stopped by the probe: by its delay, or with the probe itself

    @Test func aClaudeStoppedForItsSilenceGaveNoAnswerWhateverItWritesAsItLeaves() async throws {
        // Stopped, the real Claude Code ends its turn in error before it leaves: the end of an interrupted turn,
        // not an answer. A silence stays a silence, at the first launch as at any other.
        let first = FakeLauncher { _, _ in Self.silent() }
        let (one, firstMeasures) = try await run(probe(first, binary: binary, helper: helper, timeout: 0.5))
        #expect(first.started.count == 1)
        #expect(step("panne", firstMeasures)?.labels["categorie"] == "sans-reponse")
        #expect(step("panne", firstMeasures)?.numbers["resultat"] == 0)
        #expect(ColinProbe.reason(in: one) == "sans-reponse")
        // Its own mark of the interruption, after the probe's own stop, is no stranger's line.
        #expect(step("bilan", firstMeasures)?.numbers["inattendus"] == 0)

        let third = Self.healthy { _, index in index == 2 ? Self.silent() : nil }
        let (two, _) = try await run(probe(third, binary: binary, helper: helper, pings: 5, timeout: 0.5))
        #expect(third.started.count == 3)
        #expect(ColinProbe.reason(in: two) == "sans-reponse")

        let scene = Self.healthy { command, _ in command.prompt?.hasPrefix("Voici la transcription") == true ? Self.silent() : nil }
        let (three, sceneMeasures) = try await run(probe(scene, binary: binary, helper: helper, timeout: 0.5))
        #expect(scene.started.count == 12)
        #expect(Array(sceneMeasures.map(\.step).suffix(3)) == ["scene", "panne", "bilan"])
        #expect(sceneMeasures.last { $0.step == "scene" }?.numbers["sortieForcee"] == nil)
        #expect(ColinProbe.reason(in: three) == "sans-reponse")
    }

    @Test func anAnswerThatCameJustAsTheDelayEndedIsStillAnAnswer() async throws {
        // The answer was written as the probe decided to stop: a success is a success. Only the end in error of an
        // interrupted turn is no answer.
        let late = FakeSession(endsWhenClosed: false, stopCode: 0, onStop: { [Self.done(0.05)] })
        let launcher = Self.healthy { command, _ in command.effort == "low" ? late : nil }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper, timeout: 0.5))
        #expect(late.stopped)
        let words = measures.filter { $0.step == "premier-mot" }
        #expect(words.map(\.ok) == [true, true, true, true])
        #expect(words[1].numbers["sortieForcee"] == 1)
        #expect(step("bilan", measures)?.labels["fin"] == "complete")
        #expect(ColinProbe.reason(in: directory) == nil)
    }

    @Test func aTurnSilentAfterALimitRefusedNamesTheLimit() async throws {
        // The account says its limit is reached, then nothing: stopped for its silence, and the limit is why.
        let rejected = ClaudeEvent.rateLimit(ClaudeRateLimit(status: "rejected", type: "five_hour", fiveHour: 1))
        let limited = FakeSession([.initialized(Self.withServer)], endsWhenClosed: false, stopCode: 0, onSend: { _, turn in
            turn == 1 ? [.textDelta("Bon"), Self.done(0.01)] : [rejected]
        }, onStop: { [.other("user/interruption"), .result(ClaudeResult(subtype: "error_during_execution", isError: true))] })
        let launcher = Self.healthy { command, _ in command.prompt == nil ? limited : nil }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper, timeout: 0.5))
        #expect(limited.stopped)
        #expect(step("conversation", measures)?.labels["delai"] == "tour 2")
        #expect(measures.last { $0.step == "panne" }?.labels["categorie"] == "limite-atteinte")
        #expect(ColinProbe.reason(in: directory) == "limite-atteinte")
    }

    @Test func theRunsFolderIsItsOwnAndNobodyElses() async throws {
        // A folder that already stands where the run would make its own is refused, never adopted, and never removed.
        let manager = FileManager.default
        let name = "colin-sonde-essai-\(UUID().uuidString.prefix(8).lowercased())"
        let standing = manager.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)
        try manager.createDirectory(at: standing, withIntermediateDirectories: true)
        try Data("déjà là".utf8).write(to: standing.appending(path: "voisin.txt"))
        defer { try? manager.removeItem(at: standing) }
        let launcher = Self.healthy()
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper, folderName: name))
        #expect(measures.map(\.step) == ["binaire", "compte", "dossier", "bilan"])
        #expect(launcher.started.isEmpty)
        #expect(ColinProbe.reason(in: directory) == "lancement-impossible")
        #expect(try manager.contentsOfDirectory(atPath: standing.path(percentEncoded: false)) == ["voisin.txt"])

        // On a free name, the run makes its folder, works in it, and leaves nothing of it.
        let free = "colin-sonde-essai-\(UUID().uuidString.prefix(8).lowercased())"
        let made = manager.temporaryDirectory.appending(path: free, directoryHint: .isDirectory)
        let second = Self.healthy()
        let (_, green) = try await run(probe(second, binary: binary, helper: helper, folderName: free))
        #expect(step("bilan", green)?.labels["fin"] == "complete")
        #expect(second.directories.allSatisfy { $0.path(percentEncoded: false).contains("/\(free)/travail") })
        #expect(!manager.fileExists(atPath: made.path(percentEncoded: false)))
    }

    @Test func aStoppedLaunchIsWaitedForUntilItsProcessIsGone() async throws {
        // Asked to stop, the real Claude Code needs most of a second to leave: the probe does not return before.
        let slow = Self.silent(stopDelay: 0.3)
        let launcher = Self.healthy { _, index in index == 1 ? slow : nil }
        let once = probe(launcher, binary: binary, helper: helper, timeout: 30)
        let task = Task { try await run(once).measures }
        for _ in 0..<500 where launcher.started.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        task.cancel()
        _ = try await task.value
        #expect(slow.stopped)
        #expect(slow.isOver)

        let talking = Self.silent([.initialized(Self.withServer)], stopDelay: 0.3)
        let second = Self.healthy { command, _ in command.prompt == nil ? talking : nil }
        let other = probe(second, binary: binary, helper: helper, timeout: 30)
        let conversation = Task { try await run(other).measures }
        for _ in 0..<500 where talking.sent.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        conversation.cancel()
        _ = try await conversation.value
        #expect(talking.stopped)
        #expect(talking.isOver)
    }

    /// Runs the probe, stops it while the launch chosen by `silent` is under way, and gives what was noted.
    func stopped(during silent: @escaping @Sendable (ClaudeCommand, Int) -> Bool) async throws -> (directory: URL, measures: [ColinMeasure]) {
        let waiting = Calls()
        let launcher = Self.healthy { command, index in
            guard silent(command, index) else { return nil }
            _ = waiting.next()
            return Self.silent()
        }
        let directory = folder()
        let once = probe(launcher, binary: binary, helper: helper, timeout: 30)
        let task = Task { try await run(once, in: directory).measures }
        for _ in 0..<1_000 where waiting.value == 0 { try await Task.sleep(for: .milliseconds(10)) }
        task.cancel()
        return (directory, try await task.value)
    }

    @Test func aProbeStoppedDuringALaunchNotesNothingOfThatLaunch() async throws {
        // Half a launch is not a measure, and a probe stopped by hand has no verdict.
        let first = try await stopped { _, index in index == 0 }
        #expect(first.measures.map(\.step) == ["binaire", "compte", "bilan"])

        let tools = try await stopped { command, _ in command.prompt?.hasPrefix("Appelle l'outil projets") == true }
        #expect(!tools.measures.contains { $0.step == "outils" })

        let word = try await stopped { command, _ in command.effort == "low" }
        #expect(word.measures.filter { $0.step == "premier-mot" }.count == 1)

        let scene = try await stopped { command, _ in command.prompt?.hasPrefix("Voici la transcription") == true }
        #expect(scene.measures.filter { $0.step == "scene" }.count == 2)

        let empty = try await stopped { command, _ in command.configDirectory?.lastPathComponent == "compte-vide" }
        #expect(!empty.measures.contains { $0.step == "panne" })

        for run in [first, tools, word, scene, empty] {
            #expect(run.measures.last?.labels["fin"] == "interrompue")
            #expect(ColinProbe.verdict(in: run.directory) == nil)
        }
    }

    @Test func aProbeStoppedAsItsConversationFailsToStartWritesNoReport() async throws {
        // The app is going: the probe is stopped, and the engine refuses the next launch. Not a breakdown of
        // Claude Code.
        let running = Running()
        let launcher = Self.healthy(failing: [4])
        launcher.onStart = { index in if index == 4 { running.cancel() } }
        let directory = folder()
        let once = probe(launcher, binary: binary, helper: helper)
        let task = Task { try await run(once, in: directory).measures }
        running.hold(task)
        let measures = try await task.value
        #expect(!measures.contains { $0.step == "conversation" || $0.step == "panne" })
        #expect(measures.last?.labels["fin"] == "interrompue")
        #expect(ColinProbe.verdict(in: directory) == nil)
    }

    @Test func theMarkWrittenWhenTheProbeItselfIsStoppedIsNoStrangersLine() async throws {
        // Stopped during a turn of the conversation, Claude Code writes its own mark of the interruption: the
        // probe asked for it.
        let talking = Self.silent([.initialized(Self.withServer)])
        let launcher = Self.healthy { command, _ in command.prompt == nil ? talking : nil }
        let once = probe(launcher, binary: binary, helper: helper, timeout: 30)
        let task = Task { try await run(once).measures }
        for _ in 0..<500 where talking.sent.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        task.cancel()
        let measures = try await task.value
        #expect(step("bilan", measures)?.labels["fin"] == "interrompue")
        #expect(step("bilan", measures)?.numbers["inattendus"] == 0)
    }

    // MARK: - The end of the conversation

    @Test func aConversationThatDoesNotLeaveOnceClosedIsStoppedAndOnlyNoted() async throws {
        // Every turn answered; the input closes, and the process stays: stopped after the delay, and no breakdown.
        let stays = Self.conversation(endsWhenClosed: false)
        let launcher = Self.healthy { command, _ in command.prompt == nil ? stays : nil }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper, timeout: 0.5))
        #expect(stays.stopped)
        #expect(step("conversation", measures)?.labels["delai"] == "fermeture")
        #expect(step("conversation", measures)?.ok == true)
        #expect(step("bilan", measures)?.labels["fin"] == "complete")
        #expect(ColinProbe.reason(in: directory) == nil)
    }

    @Test func aResultThatComesOnceTheInputIsClosedChangesNothing() async throws {
        let late = Self.conversation(onClose: { [.result(ClaudeResult(subtype: "success", isError: true, apiErrorStatus: 401, text: "Please run /login"))] })
        let launcher = Self.healthy { command, _ in command.prompt == nil ? late : nil }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper))
        #expect(step("conversation", measures)?.ok == true)
        #expect(step("conversation", measures)?.numbers["tour4Reussi"] == 1)
        #expect(step("conversation", measures)?.labels["arret"] == nil)
        #expect(step("bilan", measures)?.labels["fin"] == "complete")
        #expect(ColinProbe.verdict(in: directory) == true)
    }

    // MARK: - An error of its own goes on; each sign of a breakdown stops

    @Test func aLaterLaunchInErrorOfItsOwnOnlyMarksItsStep() async throws {
        // A turn too many, a model that refuses: an error of that launch, not a Claude Code that broke down.
        let launcher = Self.healthy { command, _ in
            command.effort == "low"
                ? FakeSession([.initialized(Self.loaded), .result(ClaudeResult(subtype: "error_max_turns", isError: true, text: "trop de tours"))], code: 1) : nil
        }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper))
        #expect(launcher.started.count == 13)
        #expect(measures.filter { $0.step == "premier-mot" }.map(\.ok) == [true, false, true, true])
        #expect(measures.filter { $0.step == "panne" }.count == 1)
        #expect(step("bilan", measures)?.labels["fin"] == "complete")
        #expect(ColinProbe.verdict(in: directory) == false)
        #expect(ColinProbe.reason(in: directory) == nil)
    }

    @Test func aTurnInErrorOfItsOwnEndsTheConversationAndTheProbeGoesOn() async throws {
        let failing: [ClaudeEvent] = [.result(ClaudeResult(subtype: "success", isError: true, apiErrorStatus: 500, text: "surcharge"))]
        let launcher = Self.healthy { command, _ in command.prompt == nil ? Self.conversation(second: failing) : nil }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper))
        #expect(step("conversation", measures)?.ok == false)
        #expect(step("conversation", measures)?.labels["arret"] == "tour 2")
        #expect(launcher.started.count == 13)
        #expect(measures.filter { $0.step == "panne" }.count == 1)
        #expect(step("bilan", measures)?.labels["fin"] == "complete")
        #expect(ColinProbe.reason(in: directory) == nil)
    }

    @Test func eachSignOfABreakdownIsEnoughAlone() async throws {
        func refused(_ status: Int?, _ text: String, limit: String? = nil) -> FakeSession {
            var events: [ClaudeEvent] = [.initialized(Self.loaded)]
            if let limit { events.append(.rateLimit(ClaudeRateLimit(status: limit, type: "five_hour", fiveHour: 1))) }
            events.append(.result(ClaudeResult(subtype: "success", isError: true, apiErrorStatus: status, text: text)))
            return FakeSession(events, code: 1)
        }
        let cases: [(name: String, session: FakeSession, reason: String)] = [
            ("les mots seuls", refused(nil, "Please run /login"), "pas-connecte"),
            ("le statut 401 seul", refused(401, "refusé"), "pas-connecte"),
            ("la sortie d'erreur seule", FakeSession([.initialized(Self.loaded)], code: 1, errors: "Invalid API key"), "pas-connecte"),
            ("la limite seule", refused(nil, "non", limit: "rejected"), "limite-atteinte"),
            ("le statut 429 seul", refused(429, "non"), "limite-atteinte"),
            ("la limite avec un 401", refused(401, "Please run /login", limit: "rejected"), "limite-atteinte"),
        ]
        for item in cases {
            let launcher = Self.healthy { _, index in index == 1 ? item.session : nil }
            let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper))
            #expect(launcher.started.count == 2, "\(item.name)")
            #expect(step("panne", measures)?.labels["categorie"] == item.reason, "\(item.name)")
            #expect(ColinProbe.reason(in: directory) == item.reason, "\(item.name)")
        }
    }

    @Test func theConversationNamesEachBreakdown() async throws {
        let limited = ClaudeEvent.result(ClaudeResult(subtype: "success", isError: true, apiErrorStatus: 429, text: "non"))
        let cases: [(name: String, session: FakeSession, reason: String)] = [
            ("un tour refusé pour la limite", Self.conversation(second: [limited]), "limite-atteinte"),
            ("parti avant sa première ligne", FakeSession([], code: 1), "lancement-impossible"),
            ("parti en disant qu'il n'est pas connecté", FakeSession([.initialized(Self.withServer)], code: 1, errors: "Please run /login"), "pas-connecte"),
            ("parti après une limite refusée", FakeSession([.rateLimit(ClaudeRateLimit(status: "rejected", type: "seven_day", sevenDay: 1))], code: 1), "limite-atteinte"),
            ("refusé avant le premier message", FakeSession([.result(ClaudeResult(subtype: "success", isError: true, apiErrorStatus: 401, text: "x"))], code: 1), "pas-connecte"),
        ]
        for item in cases {
            let launcher = Self.healthy { command, _ in command.prompt == nil ? item.session : nil }
            let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper))
            #expect(launcher.started.count == 5, "\(item.name)")
            #expect(Array(measures.map(\.step).suffix(3)) == ["conversation", "panne", "bilan"], "\(item.name)")
            #expect(measures.last { $0.step == "panne" }?.labels["categorie"] == item.reason, "\(item.name)")
            #expect(ColinProbe.reason(in: directory) == item.reason, "\(item.name)")
        }
    }

    // MARK: - The edges of the isolation

    @Test func eachThingOfTheUsersFailsTheIsolationAlone() async throws {
        let leaks: [(name: String, initial: ClaudeInit)] = [
            ("un outil", ClaudeInit(tools: ["Bash"], builtinPlugins: 3)),
            ("un serveur", ClaudeInit(servers: ["le-sien": "connected"], builtinPlugins: 3)),
            ("un plugin", ClaudeInit(plugins: 1, builtinPlugins: 3)),
            ("un skill", ClaudeInit(builtinPlugins: 3, skills: 1)),
            ("une commande", ClaudeInit(builtinPlugins: 3, slashCommands: 1)),
            ("une mémoire", ClaudeInit(builtinPlugins: 3, memoryPaths: 1)),
            ("un dossier en plus", ClaudeInit(builtinPlugins: 3, directories: 1)),
        ]
        for leak in leaks {
            let launcher = Self.healthy { _, index in index == 0 ? FakeSession([.initialized(leak.initial), Self.done()], code: 0) : nil }
            let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper))
            #expect(step("isolation", measures)?.ok == false, "\(leak.name)")
            #expect(launcher.started.count == 1, "\(leak.name)")
            #expect(ColinProbe.reason(in: directory) == "isolation", "\(leak.name)")
        }
    }

    @Test func theFirstLaunchMayReadAThousandTokensAndNoMore() async throws {
        func first(_ tokens: Int) -> FakeSession {
            FakeSession([.initialized(Self.loaded), .result(ClaudeResult(subtype: "success", inputTokens: tokens, text: "inconnu"))], code: 0)
        }
        let under = first(1_000), over = first(1_001)
        let fits = Self.healthy { _, index in index == 0 ? under : nil }
        let measures = try await run(probe(fits, binary: binary, helper: helper)).measures
        #expect(step("isolation", measures)?.ok == true)
        let heavy = Self.healthy { _, index in index == 0 ? over : nil }
        let (directory, tooMuch) = try await run(probe(heavy, binary: binary, helper: helper))
        #expect(step("isolation", tooMuch)?.ok == false)
        #expect(ColinProbe.reason(in: directory) == "isolation")
    }

    @Test func aClaudeThatDoesNotSayWhatItLoadedCannotBeJudged() async throws {
        // An answer, and no first line at all: nothing proves what loaded. « Cannot tell », not « loaded more ».
        let mute = FakeSession([Self.done()], code: 0)
        let launcher = Self.healthy { _, index in index == 0 ? mute : nil }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper))
        #expect(step("isolation", measures)?.ok == false)
        #expect(step("isolation", measures)?.numbers["outils"] == -1)
        #expect(launcher.started.count == 1)
        #expect(ColinProbe.reason(in: directory) == "isolation-inconnue")
    }

    // MARK: - What a trace, a report and the cleaning may hold

    @Test func nothingThatLooksLikeAPathOrAnAddressReachesTheTrace() async throws {
        // Claude Code's own words are kept only when they look like technical words: every label that copies one
        // is given a path, an address or an account's number here.
        let path = "/Users/essai-de-sonde/quelque/part", address = "quelquun@exemple.fr", arn = "arn:aws:bedrock:eu-west-1:123456789012:model/x"
        let odd = ClaudeInit(version: path, model: arn, permissionMode: path, apiKeySource: address, builtinPlugins: 3)
        let oddServer = ClaudeInit(version: path, model: arn, permissionMode: path, apiKeySource: address,
                                   tools: ["mcp__hub__projets", "mcp__hub__journal"], servers: ["hub": "connected"], builtinPlugins: 3)
        let launcher = Self.healthy { command, index in
            if command.configDirectory?.lastPathComponent == "compte-vide" {
                return FakeSession([.result(ClaudeResult(subtype: path, isError: true, text: "Please run /login"))], code: 1)
            }
            guard let prompt = command.prompt else {
                return Self.conversation(first: oddServer, interrupted: path, extra: [.other(path), .other(address)])
            }
            if prompt.hasPrefix("Appelle l'outil projets") {
                return FakeSession([.initialized(oddServer), .assistant(text: "", tools: ["mcp__hub__projets"]),
                                    .result(ClaudeResult(subtype: "success", denied: [path, address]))], code: 0)
            }
            if index == 0 || prompt == "Réponds seulement : ok" {
                return FakeSession([.initialized(odd), .other(path), .rateLimit(ClaudeRateLimit(status: address, type: path, sevenDay: 0.2)), Self.done()], code: 0)
            }
            if prompt == "Dis bonjour en une phrase." { return FakeSession([.initialized(odd), Self.done(0.05)], code: 0) }
            return nil
        }
        let tool: ColinProbe.Tool = { url, arguments, environment in
            if arguments.first == "auth" { return (0, #"{"loggedIn":true,"authMethod":"\#(address)","subscriptionType":"\#(path)"}"#) }
            return await Self.answers(url, arguments, environment)
        }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper, tool: tool))
        let trace = try String(contentsOf: directory.appending(path: "trace.jsonl"), encoding: .utf8)
        for word in ["essai-de-sonde", "exemple.fr", "123456789012", "quelque/part"] { #expect(!trace.contains(word), "\(word)") }
        // The run went to its end, and each of these words was written « autre ».
        #expect(step("bilan", measures)?.labels["fin"] == "complete")
        #expect(step("compte", measures)?.labels == ["methode": "autre", "abonnement": "autre"])
        #expect(step("connexion", measures)?.labels == ["cle": "autre", "modele": "autre", "mode": "autre", "version": "autre"])
        #expect(step("outils", measures)?.labels["refuses"] == "autre,autre")
        #expect(step("conversation", measures)?.labels["modele"] == "autre")
        #expect(step("conversation", measures)?.labels["finInterrompue"] == "autre")
        #expect(step("conversation", measures)?.labels["inattendus"] == "autre,un_message_inconnu")
        let words = measures.filter { $0.step == "premier-mot" }
        #expect(words.count == 4 && words.allSatisfy { $0.labels["modele"] == "autre" })
        #expect(measures.last { $0.step == "panne" }?.labels["sousType"] == "autre")
        #expect(step("limites", measures)?.labels["etat"] == "autre")
        #expect(step("bilan", measures)?.labels["limites"] == "autre")
        #expect(step("bilan", measures)?.labels["inattendus"] == "autre,un_message_inconnu")
    }

    @Test func noWordOfAnAnswerNorOfAnErrorReachesTheTraceNorTheReport() async throws {
        // The words as they come, the text of an error, the end of the error output: none is kept.
        let secret = Self.secret, path = "/Users/essai-de-sonde/secret"
        let launcher = Self.healthy { command, _ in
            if command.prompt == "Réponds seulement : ok" {
                return FakeSession([.initialized(Self.loaded), .textDelta(secret), .assistant(text: secret + path, tools: []), Self.done()], code: 0)
            }
            if command.prompt == "Dis bonjour en une phrase.", command.model == "sonnet" {
                return FakeSession([.initialized(Self.loaded), .textDelta(secret),
                                    .result(ClaudeResult(subtype: "error_during_execution", isError: true, text: secret + " " + path))],
                                   code: 1, errors: secret + " " + path)
            }
            return nil
        }
        let (directory, measures) = try await run(probe(launcher, binary: binary, helper: helper))
        #expect(step("bilan", measures)?.labels["fin"] == "complete")
        for file in ["trace.jsonl", "bilan.json"] {
            let text = try String(contentsOf: directory.appending(path: file), encoding: .utf8)
            #expect(!text.contains(secret) && !text.contains("essai-de-sonde"), "\(file)")
        }
    }

    @Test func anAnswerOfAnotherShapeTellsOnlyTheNamesOfItsFields() async throws {
        let tool: ColinProbe.Tool = { url, arguments, environment in
            if arguments.first == "auth" { return (0, #"Avis : une mise à jour existe.\n{"connecte":"oui","compte":"quelquun@exemple.fr","/Users/essai-de-sonde":1}"#) }
            return await Self.answers(url, arguments, environment)
        }
        let (directory, measures) = try await run(probe(Self.healthy(), binary: binary, helper: helper, tool: tool))
        #expect(step("compte", measures)?.ok == false)
        #expect(step("compte", measures)?.labels["cles"] == "autre,compte,connecte")
        let trace = try String(contentsOf: directory.appending(path: "trace.jsonl"), encoding: .utf8)
        #expect(!trace.contains("exemple.fr") && !trace.contains("essai-de-sonde"))
    }

    @Test func theReportHoldsOnlyItsVerdictAndItsReason() async throws {
        let healthy = try await run(probe(Self.healthy(), binary: binary, helper: helper)).directory
        let stopped = try await run(probe(FakeLauncher { _, _ in Self.notConnected() }, binary: binary, helper: helper)).directory
        for directory in [healthy, stopped] {
            let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appending(path: "bilan.json"))) as? [String: Any])
            #expect(Set(object.keys).isSubset(of: ["ok", "raison"]))
        }
    }

    @Test func theBusyConversationsAreCountedFromTheirFiles() throws {
        let root = folder()
        let sessions = root.appending(path: "sessions", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try Data(#"{"status":"busy","cwd":"/quelque/part"}"#.utf8).write(to: sessions.appending(path: "1.json"))
        try Data(#"{"status":"busy"}"#.utf8).write(to: sessions.appending(path: "2.json"))
        try Data(#"{"status":"idle"}"#.utf8).write(to: sessions.appending(path: "3.json"))
        try Data("pas du JSON".utf8).write(to: sessions.appending(path: "4.json"))
        try Data(#"{"status":"busy"}"#.utf8).write(to: sessions.appending(path: "5.key"))
        #expect(ColinProbe.busySessions(in: root) == 2)
        #expect(ColinProbe.busySessions(in: folder()) == nil)
    }

    @Test func theCleaningLeavesTheAccountAndItsNeighboursAlone() async throws {
        let manager = FileManager.default
        let account = folder()
        try manager.createDirectory(at: account, withIntermediateDirectories: true)
        try Data("un fichier du compte".utf8).write(to: account.appending(path: "garde.txt"))
        try manager.createDirectory(at: account.appending(path: "projects/un-projet", directoryHint: .isDirectory), withIntermediateDirectories: true)
        try manager.createDirectory(at: account.appending(path: "sessions", directoryHint: .isDirectory), withIntermediateDirectories: true)
        try Data(#"{"status":"idle"}"#.utf8).write(to: account.appending(path: "sessions/1.json"))
        let directory = folder()
        try manager.createDirectory(at: directory.appending(path: "base", directoryHint: .isDirectory), withIntermediateDirectories: true)
        try Data("un voisin".utf8).write(to: directory.appending(path: "voisin.txt"))
        let launcher = Self.healthy()
        _ = try await run(probe(launcher, binary: binary, helper: helper), variant: account.path(percentEncoded: false), in: directory)
        for kept in ["garde.txt", "projects/un-projet", "sessions/1.json"] {
            #expect(manager.fileExists(atPath: account.appending(path: kept).path(percentEncoded: false)), "\(kept)")
        }
        #expect(try manager.contentsOfDirectory(atPath: account.path(percentEncoded: false)).sorted() == ["garde.txt", "projects", "sessions"])
        // Everything the run makes lives among the temporary folders: a path with no name of the user.
        let temporary = manager.temporaryDirectory.resolvingSymlinksInPath().path(percentEncoded: false)
        #expect(launcher.directories.allSatisfy { $0.resolvingSymlinksInPath().path(percentEncoded: false).hasPrefix(temporary) })
        let bases = launcher.started.compactMap(\.mcpConfig)
        #expect(!bases.isEmpty && bases.allSatisfy { !$0.contains(directory.lastPathComponent) && $0.contains("colin-sonde-") })
        let empty = launcher.started.compactMap(\.configDirectory).filter { $0.lastPathComponent == "compte-vide" }
        #expect(empty.count == 1 && empty.allSatisfy { !$0.path(percentEncoded: false).contains(directory.lastPathComponent) })
        // A folder that was there before, even named like one of the probe's own, stays.
        #expect(try manager.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted() == ["base", "bilan.json", "trace.jsonl", "voisin.txt"])
        // The launches ran in a folder of their own, outside the measure's: its path, with the user's name, is not
        // what the tools would tell Claude.
        #expect(!launcher.directories.isEmpty)
        #expect(launcher.directories.allSatisfy { !$0.path(percentEncoded: false).hasPrefix(directory.path(percentEncoded: false)) })
        #expect(launcher.directories.allSatisfy { !manager.fileExists(atPath: $0.path(percentEncoded: false)) })
        // The chosen account never reaches the trace.
        let trace = try String(contentsOf: directory.appending(path: "trace.jsonl"), encoding: .utf8)
        #expect(!trace.contains(account.lastPathComponent))
    }

    @Test func aToolOutsideTheProfileMustBeDenied() async throws {
        let denied = try await run(probe(Self.healthy(), binary: binary, helper: helper)).measures
        #expect(step("outils", denied)?.ok == true)
        #expect(step("outils", denied)?.labels["refuses"] == "mcp__hub__journal")
        #expect(step("outils", denied)?.numbers["refus"] == 1)
        #expect(step("outils", denied)?.numbers["serveurs"] == 1)
        #expect(step("outils", denied)?.numbers["journalEcrit"] == 0)

        let open = Self.healthy { command, _ in command.prompt?.hasPrefix("Appelle l'outil projets") == true ? Self.tools(denied: []) : nil }
        let allowed = try await run(probe(open, binary: binary, helper: helper)).measures
        #expect(step("outils", allowed)?.ok == false)
        #expect(step("bilan", allowed)?.ok == false)
    }

    @Test func withoutTheHelperTheToolsStepSaysWhy() async throws {
        let launcher = Self.healthy()
        let measures = try await run(probe(launcher, binary: binary, helper: nil)).measures
        #expect(step("outils", measures)?.ok == false)
        #expect(step("outils", measures)?.labels["raison"] == "programme des outils introuvable")
        // The conversation still runs, with no server.
        let conversation = try #require(launcher.started.first { $0.prompt == nil })
        #expect(conversation.mcpConfig == nil && conversation.allowedTools.isEmpty)
        #expect(step("conversation", measures) != nil)
    }

    @Test func withoutABinaryTheProbeSaysSoAndLaunchesNothing() async throws {
        let launcher = Self.healthy()
        let (directory, measures) = try await run(probe(launcher, binary: nil, helper: helper))
        #expect(launcher.started.isEmpty)
        #expect(measures.map(\.step) == ["binaire", "bilan"])
        #expect(step("binaire", measures)?.ok == false)
        #expect(ColinProbe.verdict(in: directory) == false)
        #expect(ColinProbe.reason(in: directory) == "introuvable")
    }

    @Test func aSilentClaudeIsKilledAfterTheDelay() async throws {
        let launcher = FakeLauncher { _, _ in FakeSession(endsWhenClosed: false) }
        let began = Date()
        let measures = try await run(probe(launcher, binary: binary, helper: helper, timeout: 0.5)).measures
        #expect(Date().timeIntervalSince(began) < 5)
        #expect(launcher.started.count == 1)
        #expect(launcher.all.first?.stopped == true)
        #expect(step("connexion", measures)?.ok == false)
        #expect(step("panne", measures)?.labels["categorie"] == "sans-reponse")
        #expect(step("bilan", measures)?.labels["fin"] == "arretee")
    }

    @Test func aCancelledProbeStopsItsProcessAndSaysSo() async throws {
        // The second ping never answers; the probe is stopped meanwhile.
        let launcher = Self.healthy { _, index in index == 1 ? FakeSession(endsWhenClosed: false) : nil }
        let directory = folder()
        let probe = probe(launcher, binary: binary, helper: helper, timeout: 30)
        let task = Task { try await run(probe, in: directory).measures }
        for _ in 0..<500 where launcher.started.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        task.cancel()
        let measures = try await task.value
        #expect(launcher.all[1].stopped)
        #expect(launcher.started.count == 2)
        #expect(step("bilan", measures)?.labels["fin"] == "interrompue")
        #expect(step("bilan", measures)?.ok == false)
        #expect(ColinProbe.verdict(in: directory) == nil)
    }

    @Test func aProbeStoppedDuringThePauseBetweenTwoLaunchesStopsAtOnce() async throws {
        let launcher = Self.healthy()
        let directory = folder()
        let probe = probe(launcher, binary: binary, helper: helper, pings: 5, pause: 30)
        let task = Task { try await run(probe, in: directory).measures }
        for _ in 0..<500 where launcher.started.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(100))
        let began = Date()
        task.cancel()
        let measures = try await task.value
        #expect(Date().timeIntervalSince(began) < 3)
        #expect(launcher.started.count == 1)
        #expect(step("bilan", measures)?.labels["fin"] == "interrompue")
    }

    @Test func aProbeStoppedWhileAToolIsSlowLaunchesNothing() async throws {
        // `claude --version` hangs; the probe is stopped meanwhile: nothing is noted of it, and nothing is launched.
        let asked = Calls()
        let tool: ColinProbe.Tool = { url, arguments, environment in
            if arguments == ["--version"] {
                _ = asked.next()
                try? await Task.sleep(for: .seconds(30))
                return nil
            }
            return await Self.answers(url, arguments, environment)
        }
        let launcher = Self.healthy()
        let directory = folder()
        let probe = probe(launcher, binary: binary, helper: helper, tool: tool)
        let task = Task { try await run(probe, in: directory).measures }
        for _ in 0..<500 where asked.value == 0 { try await Task.sleep(for: .milliseconds(10)) }
        let began = Date()
        task.cancel()
        let measures = try await task.value
        #expect(Date().timeIntervalSince(began) < 3)
        #expect(launcher.started.isEmpty)
        #expect(measures.map(\.step) == ["bilan"])
        #expect(step("bilan", measures)?.labels["fin"] == "interrompue")
        #expect(ColinProbe.verdict(in: directory) == nil)
    }

    @Test func theTraceCarriesNoTextOfAnAnswer() async throws {
        let (directory, _) = try await run(probe(Self.healthy(), binary: binary, helper: helper))
        let trace = try String(contentsOf: directory.appending(path: "trace.jsonl"), encoding: .utf8)
        #expect(!trace.contains(Self.secret))
        #expect(!trace.contains("essai-de-sonde"))
        #expect(!trace.contains("exemple.fr"))
        #expect(!trace.contains(directory.lastPathComponent))
    }

    @Test func theAccountFolderOfTheRequestIsUsed() async throws {
        let chosen = Self.healthy()
        _ = try await run(probe(chosen, binary: binary, helper: helper), variant: "/tmp/compte-essai")
        let folders = chosen.started.map { $0.configDirectory?.path(percentEncoded: false) }
        #expect(folders.filter { $0?.hasSuffix("compte-vide/") == true || $0?.hasSuffix("compte-vide") == true }.count == 1)
        #expect(folders.filter { $0 == "/tmp/compte-essai/" || $0 == "/tmp/compte-essai" }.count == chosen.started.count - 1)

        let own = Self.healthy()
        _ = try await run(probe(own, binary: binary, helper: helper), variant: "")
        #expect(own.started.filter { $0.configDirectory == nil }.count == own.started.count - 1)
    }

    @Test func claudeCodesOwnFolderIsItsOwnAccount() async throws {
        // Chosen by hand, Claude Code's own folder must not become a variable: it would name another account.
        let launcher = Self.healthy()
        _ = try await run(probe(launcher, binary: binary, helper: helper), variant: "/Users/essai-de-sonde/.claude")
        #expect(launcher.started.filter { $0.configDirectory == nil }.count == launcher.started.count - 1)
    }

    @Test func anInitThatComesAfterTheFirstMessageIsNoted() async throws {
        let launcher = Self.healthy { command, _ in command.prompt == nil ? Self.conversation(initFirst: false) : nil }
        let measures = try await run(probe(launcher, binary: binary, helper: helper)).measures
        #expect(step("conversation", measures)?.numbers["initAvantMessage"] == 0)
        #expect(step("conversation", measures)?.numbers["tour4Reussi"] == 1)
    }

    @Test func theProbeIsInTheRegistryWithItsTitle() async {
        #expect(ProbeID.colin.rawValue == "colin")
        #expect(ProbeID.colin.title == "Colin : Claude Code depuis hub")
        #expect(await ProbeRegistry.make(.colin) != nil)
    }

    @Test func theTextsAreLongEnoughToMeasure() {
        #expect(ColinProbeTexts.call.split(separator: " ").count > 1_500)
        #expect(ColinProbeTexts.mail.contains("jeudi 26 novembre"))
        #expect(ColinProbeTexts.turns.count == 4)
    }
}

@Suite struct ColinProbeRunsTests {
    /// What blocks is run on a thread of its own, away from the tests' own.
    func blocking(_ work: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            Thread.detachNewThread {
                work()
                done.resume()
            }
        }
    }

    @Test func theAppThatGoesWaitsForTheRunsUnderWayAndNoLonger() async {
        let runs = ColinProbe.Runs()
        // No run: nothing to wait for.
        var began = Date()
        await blocking { runs.wait(within: 5) }
        #expect(Date().timeIntervalSince(began) < 3)
        // A run that ends its own way, 300 ms later: waited for, and no longer.
        runs.begin()
        began = Date()
        Thread.detachNewThread {
            usleep(300_000)
            runs.end()
        }
        await blocking { runs.wait(within: 5) }
        let waited = Date().timeIntervalSince(began)
        #expect(waited > 0.29 && waited < 4)
        // A run that never ends does not hold the app beyond the delay given.
        runs.begin()
        began = Date()
        await blocking { runs.wait(within: 0.3) }
        let held = Date().timeIntervalSince(began)
        #expect(held > 0.29 && held < 3)
    }
}
