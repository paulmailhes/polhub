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
    private let endsWhenClosed: Bool

    var sent: [String] { lock.withLock { _sent } }
    var stopped: Bool { lock.withLock { _stopped } }

    /// `code`: the launch answers `first` and ends with this code at once. `nil`: it stays open (a conversation, or
    /// a Claude Code that never answers).
    init(_ first: [ClaudeEvent] = [], code: Int32? = nil, endsWhenClosed: Bool = true,
         onSend: @escaping @Sendable (String, Int) -> [ClaudeEvent] = { _, _ in [] },
         onInterrupt: @escaping @Sendable (String) -> [ClaudeEvent] = { _ in [] }) {
        (events, continuation) = AsyncStream.makeStream()
        self.onSend = onSend
        self.onInterrupt = onInterrupt
        self.endsWhenClosed = endsWhenClosed
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
        if endsWhenClosed { end(0) }
    }

    func stop() {
        lock.withLock { _stopped = true }
        end(130)
    }

    private func end(_ code: Int32) {
        let first = lock.withLock { if ended { return false }; ended = true; return true }
        guard first else { return }
        continuation.yield(.exited(code: code, errors: ""))
        continuation.finish()
    }
}

/// Answers each launch from the command it receives, and keeps the commands in order.
final class FakeLauncher: ClaudeLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [ClaudeCommand] = []
    private var sessions: [FakeSession] = []
    private let respond: @Sendable (ClaudeCommand, Int) -> FakeSession

    init(_ respond: @escaping @Sendable (ClaudeCommand, Int) -> FakeSession) { self.respond = respond }

    var started: [ClaudeCommand] { lock.withLock { commands } }
    var all: [FakeSession] { lock.withLock { sessions } }

    func start(_ command: ClaudeCommand, binary: URL, directory: URL) throws -> any ClaudeSession {
        let index = lock.withLock { commands.count }
        let session = respond(command, index)
        lock.withLock { commands.append(command); sessions.append(session) }
        return session
    }
}

@Suite struct ColinProbeTests {
    static let secret = "RÉPONSE-À-NE-PAS-GARDER"
    static let home = URL(fileURLWithPath: "/Users/essai-de-sonde")
    let binary = URL(fileURLWithPath: "/Users/essai-de-sonde/.local/bin/claude")
    let helper = URL(fileURLWithPath: "/Applications/Essai.app/Contents/Helpers/polhub")

    // MARK: - A Claude Code where everything answers well

    static let loaded = ClaudeInit(version: "2.1.304", model: "claude-haiku-4-5", permissionMode: "dontAsk", apiKeySource: "none")
    static let withServer = ClaudeInit(version: "2.1.304", model: "claude-opus-4-8", permissionMode: "dontAsk", apiKeySource: "none",
                                       tools: ["mcp__polhub__projets", "mcp__polhub__journal"], servers: ["polhub": "connected"])
    static let limit = ClaudeRateLimit(status: "allowed", type: "five_hour", fiveHour: 0.42, sevenDay: 0.11)
    static func done(_ cost: Double = 0.0002) -> ClaudeEvent {
        .result(ClaudeResult(subtype: "success", durationMs: 900, numTurns: 1, costUSD: cost, inputTokens: 900, outputTokens: 3, text: "ok " + secret))
    }

    static func ping() -> FakeSession { FakeSession([.initialized(loaded), .rateLimit(limit), done()], code: 0) }

    static func notConnected() -> FakeSession {
        FakeSession([.result(ClaudeResult(subtype: "success", isError: true, apiErrorStatus: 401, text: "Invalid API key · Please run /login"))], code: 1)
    }

    static func tools(denied: [String]) -> FakeSession {
        FakeSession([.initialized(withServer), .assistant(text: secret, tools: ["mcp__polhub__projets"]), .toolResult(isError: false),
                     .assistant(text: "", tools: ["mcp__polhub__journal"]), .toolResult(isError: true),
                     .result(ClaudeResult(subtype: "success", numTurns: 3, costUSD: 0.001, inputTokens: 2_000, outputTokens: 40, denied: denied, text: "fini"))], code: 0)
    }

    static func conversation(initFirst: Bool = true) -> FakeSession {
        FakeSession(initFirst ? [.initialized(withServer)] : [], onSend: { _, turn in
            let late: [ClaudeEvent] = !initFirst && turn == 1 ? [.initialized(withServer)] : []
            switch turn {
            case 2: return [.textDelta("Deux"), .assistant(text: secret, tools: ["mcp__polhub__projets"]), .toolResult(isError: false), done(0.03)]
            case 3: return [.textDelta("1"), .other("stream_event/message_delta"), .other("un_message_inconnu")]
            default: return late + [.textDelta("Bon"), .assistant(text: secret, tools: []), done(Double(turn) * 0.01)]
            }
        }, onInterrupt: { id in
            [.controlResponse(requestID: id, success: true), .result(ClaudeResult(subtype: "error_during_execution", isError: true, costUSD: 0.04))]
        })
    }

    /// Every launch answers; `override` changes one of them.
    static func healthy(_ override: @escaping @Sendable (ClaudeCommand, Int) -> FakeSession? = { _, _ in nil }) -> FakeLauncher {
        FakeLauncher { command, index in
            if let session = override(command, index) { return session }
            if command.configDirectory?.lastPathComponent == "compte-vide" { return notConnected() }
            guard let prompt = command.prompt else { return conversation() }
            if prompt.hasPrefix("Appelle l'outil projets") { return tools(denied: ["mcp__polhub__journal"]) }
            if prompt == "Réponds seulement : ok" { return ping() }
            return FakeSession([.initialized(loaded), done(0.05)], code: 0)
        }
    }

    static let answers: ColinProbe.Tool = { _, arguments, _ in
        if arguments == ["--version"] { return (0, "2.1.304 (Claude Code)\n") }
        if arguments.first == "auth" { return (0, #"{"loggedIn":true,"authMethod":"claude.ai","email":"quelquun@exemple.fr"}"#) }
        return (0, "  0:01.50 204800\n")
    }

    func probe(_ launcher: FakeLauncher, binary: URL?, helper: URL?, pings: Int = 3, timeout: Double = 5, tool: @escaping ColinProbe.Tool = answers) -> ColinProbe {
        ColinProbe(launcher: launcher, binary: binary, helper: helper, home: Self.home, environment: ["HOME": Self.home.path, "PATH": "/usr/bin:/bin"],
                   pings: pings, pause: 0, timeout: timeout, initWait: 0.5, interruptDelay: 0, tool: tool)
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
                                         "scene", "scene", "scene", "panne", "invisible", "limites", "bilan"], "\(measures.map(\.step))")
        let failed = measures.filter { !$0.ok }
        #expect(failed.isEmpty, "\(failed)")
        #expect(step("binaire", measures)?.labels == ["sorte": "officiel", "version": "2.1.304"])
        #expect(step("compte", measures)?.numbers["connecte"] == 1)
        #expect(step("compte", measures)?.labels["methode"] == "claude.ai")
        #expect(step("connexion", measures)?.labels["cle"] == "none")
        #expect(step("connexion", measures)?.numbers["coutUSD"] == 0.0002)
        #expect(step("connexion", measures)?.numbers["entree"] == 900)
        #expect(step("isolation", measures)?.numbers == ["outils": 0, "serveurs": 0, "plugins": 0, "skills": 0, "commandes": 0])
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
        #expect(measures.filter { $0.step == "scene" }.compactMap { $0.labels["nom"] } == ["fiche-mail", "brouillon", "compte-rendu"])
        #expect(step("panne", measures)?.labels["categorie"] == "pas-connecte")
        #expect(step("limites", measures)?.numbers["cinqHeuresAvant"] == 42)
        #expect(step("limites", measures)?.numbers["semaineApres"] == 11)
        #expect(step("bilan", measures)?.labels["fin"] == "complete")
        #expect(step("bilan", measures)?.numbers["echecs"] == 0)
        #expect(ColinProbe.verdict(in: directory) == true)
        // 3 pings, the tools, the conversation, 3 scenes, the empty account.
        #expect(launcher.started.count == 9)
        #expect(launcher.all.allSatisfy { !$0.stopped })
    }

    @Test func theConversationSaysItsFourMessagesAndInterruptsTheThird() async throws {
        let launcher = Self.healthy()
        _ = try await run(probe(launcher, binary: binary, helper: helper))
        let index = try #require(launcher.started.firstIndex { $0.prompt == nil })
        #expect(launcher.all[index].sent.count == 4)
        #expect(launcher.started[index].model == "opus")
        #expect(launcher.started[index].allowedTools == ["mcp__polhub__projets"])
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
    }

    @Test func aToolOutsideTheProfileMustBeDenied() async throws {
        let denied = try await run(probe(Self.healthy(), binary: binary, helper: helper)).measures
        #expect(step("outils", denied)?.ok == true)
        #expect(step("outils", denied)?.labels["refuses"] == "mcp__polhub__journal")
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
    }

    @Test func aSilentClaudeIsKilledAfterTheDelay() async throws {
        let launcher = FakeLauncher { _, _ in FakeSession(endsWhenClosed: false) }
        let began = Date()
        let measures = try await run(probe(launcher, binary: binary, helper: helper, timeout: 0.2)).measures
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
        while launcher.started.count < 2 { try await Task.sleep(for: .milliseconds(20)) }
        task.cancel()
        let measures = try await task.value
        #expect(launcher.all[1].stopped)
        #expect(launcher.started.count == 2)
        #expect(step("bilan", measures)?.labels["fin"] == "interrompue")
        #expect(step("bilan", measures)?.ok == false)
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
        #expect(ProbeID.colin.title == "Colin : Claude Code depuis Polhub")
        #expect(await ProbeRegistry.make(.colin) != nil)
    }

    @Test func theTextsAreLongEnoughToMeasure() {
        #expect(ColinProbeTexts.call.split(separator: " ").count > 1_500)
        #expect(ColinProbeTexts.mail.contains("jeudi 26 novembre"))
        #expect(ColinProbeTexts.turns.count == 4)
    }
}
