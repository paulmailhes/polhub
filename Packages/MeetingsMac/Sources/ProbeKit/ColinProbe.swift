import Colin
import Domain
import Foundation
import Observability
import Persistence

/// One line of the probe's trace: a step, whether it went as expected, numbers and technical labels (a version, a
/// model, a tool's name). Never the text of an answer, never a path, never an address.
public struct ColinMeasure: Codable, Sendable, Equatable {
    public var step: String
    public var ok: Bool
    public var numbers: [String: Double]
    public var labels: [String: String]

    public init(step: String, ok: Bool, numbers: [String: Double] = [:], labels: [String: String] = [:]) {
        self.step = step
        self.ok = ok
        self.numbers = numbers
        self.labels = labels
    }
}

/// Step 0 of Colin (17/11): does the Claude Code of this Mac answer from Polhub as an API would? The connection, what
/// loads, the tools, a conversation with an interruption, the failures, the cost. Invented texts only, one process at
/// a time. A Claude that is not connected, does not answer or cannot start stops the probe at whatever launch it
/// shows: nothing is tried after it.
public struct ColinProbe: Probe {
    public typealias Tool = @Sendable (URL, [String], [String: String]) async -> (code: Int32, output: String)?

    fileprivate let launcher: any ClaudeLaunching
    fileprivate let binary: URL?
    fileprivate let helper: URL?
    fileprivate let home: URL
    fileprivate let environment: [String: String]
    fileprivate let pings: Int
    fileprivate let pause: Double
    fileprivate let timeout: Double
    fileprivate let initWait: Double
    fileprivate let interruptDelay: Double
    fileprivate let tool: Tool
    fileprivate let busySessions: @Sendable (URL) -> Int?

    /// - Parameters:
    ///   - helper: Polhub's command line, the server of the tools; `nil`: the tools are not measured.
    ///   - pings: how many launches in a row, the first included.
    ///   - pause: seconds between two of them.
    ///   - timeout: seconds a launch, or a turn of the conversation, may take before it is killed.
    ///   - initWait: seconds the conversation waits for Claude Code's first line before speaking.
    ///   - interruptDelay: seconds after the first word of the third answer before it is interrupted.
    ///   - busySessions: how many conversations of Claude Code are at work, for the account's folder given.
    public init(launcher: any ClaudeLaunching = LiveClaudeLauncher(), binary: URL? = ClaudeBinary.find(), helper: URL?,
                home: URL = FileManager.default.homeDirectoryForCurrentUser, environment: [String: String] = ProcessInfo.processInfo.environment,
                pings: Int = 20, pause: Double = 1, timeout: Double = 60, initWait: Double = 2, interruptDelay: Double = 0.4,
                tool: @escaping Tool = { await ClaudeTool.run($0, arguments: $1, environment: $2, timeout: 15) },
                busySessions: @escaping @Sendable (URL) -> Int? = { ColinProbe.busySessions(in: $0) }) {
        self.launcher = launcher
        self.binary = binary
        self.helper = helper
        self.home = home
        self.environment = environment
        self.pings = pings
        self.pause = pause
        self.timeout = timeout
        self.initWait = initWait
        self.interruptDelay = interruptDelay
        self.tool = tool
        self.busySessions = busySessions
    }

    /// `request.variant`: the folder of the Claude account; empty, absent, or Claude Code's own folder: its own account.
    public func run(_ request: ProbeRequest, trace: TraceWriter, directory: URL) async {
        var run = Run(probe: self, account: ClaudeCommand.account(folder: request.variant, home: home), trace: trace, directory: directory)
        await run.go()
    }

    /// `<directory>/bilan.json`; `nil`: no report (the probe was stopped before its end).
    public static func verdict(in directory: URL) -> Bool? {
        report(in: directory)?["ok"] as? Bool
    }

    /// Why the probe stopped early, when it knows: « introuvable », « pas-connecte », « sans-reponse »,
    /// « lancement-impossible ».
    public static func reason(in directory: URL) -> String? {
        report(in: directory)?["raison"] as? String
    }

    private static func report(in directory: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: directory.appending(path: "bilan.json")) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// The command line embedded in the app, when it is there.
    public static func embeddedHelper(bundle: Bundle = .main) -> URL? {
        let url = bundle.bundleURL.appending(path: "Contents/Helpers/polhub")
        return FileManager.default.isExecutableFile(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    /// How many conversations of Claude Code are at work: the files of its sessions that say « busy ». Their number
    /// only; it tells whether the account's use moved because of the probe or because of them.
    public static func busySessions(in root: URL) -> Int? {
        let folder = root.appending(path: "sessions", directoryHint: .isDirectory)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) else { return nil }
        return names.filter { $0.hasSuffix(".json") }.reduce(0) { count, name in
            guard let data = try? Data(contentsOf: folder.appending(path: name)), data.count < 262_144,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return count }
            return count + (object["status"] as? String == "busy" ? 1 : 0)
        }
    }
}

// MARK: - One launch that answers once

private struct Outcome {
    var initial: ClaudeInit?
    var initMs: Double?
    var firstWordMs: Double?
    var result: ClaudeResult?
    var totalMs = 0.0
    var code: Int32?
    var errors = ""
    var tools: [String] = []
    var limits: [ClaudeRateLimit] = []
    var unexpected: [String] = []
    var timedOut = false
    var couldNotStart = false

    var succeeded: Bool { result.map { $0.subtype == "success" && !$0.isError } ?? false }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    var isRaised: Bool { lock.withLock { raised } }
    func raise() { lock.withLock { raised = true } }
}

private func milliseconds(_ duration: Duration) -> Double {
    let value = Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    return (value * 10).rounded() / 10
}

/// The partial messages, Claude Code's own notices and its mark of an interruption are expected; any other line
/// nobody asked for is counted and named: it may be a message of another session.
private func isExpected(_ name: String) -> Bool {
    name.hasPrefix("stream_event/") || name.hasPrefix("system/") || name == "keep_alive" || name == "user/interruption"
}

/// What Claude Code says when the account is not connected.
private func saysNotConnected(_ text: String) -> Bool {
    let said = text.lowercased()
    return ["log in", "login", "authenticat", "api key"].contains(where: said.contains)
}

// MARK: - The run

private struct Run {
    enum End: String { case complete, arretee, interrompue }

    typealias Texts = ColinProbeTexts
    static let allowed = "mcp__polhub__projets"

    let probe: ColinProbe
    let account: URL?
    let trace: TraceWriter
    let directory: URL
    /// The name of the launches' working folder: Claude Code would name a conversation's folder after it.
    let token: String
    let work: URL
    let clock = ContinuousClock()
    let began: ContinuousClock.Instant
    var measures: [ColinMeasure] = []
    var limits: [ClaudeRateLimit] = []
    var unexpected: [String] = []
    var cost = 0.0
    /// Why the probe stopped before its end, when it knows.
    var reason: String?

    init(probe: ColinProbe, account: URL?, trace: TraceWriter, directory: URL) {
        self.probe = probe
        self.account = account
        self.trace = trace
        self.directory = directory
        token = "colin-sonde-" + UUID().uuidString.prefix(8).lowercased()
        work = directory.appending(path: token, directoryHint: .isDirectory)
        began = clock.now
    }

    private var toolEnvironment: [String: String] {
        ClaudeCommand(model: "", systemPrompt: "", configDirectory: account).environment(from: probe.environment)
    }

    private var ping: ClaudeCommand {
        ClaudeCommand(model: "haiku", systemPrompt: Texts.system, prompt: Texts.ping, maxTurns: 1, configDirectory: account)
    }

    private var base: URL { directory.appending(path: "base", directoryHint: .isDirectory) }
    private var emptyAccount: URL { directory.appending(path: "compte-vide", directoryHint: .isDirectory) }

    mutating func go() async {
        let end = await steps()
        await close(end)
        // Nothing of the run stays but its trace and its report.
        for folder in [work, base, emptyAccount] { try? FileManager.default.removeItem(at: folder) }
    }

    private mutating func note(_ step: String, ok: Bool, _ numbers: [String: Double] = [:], _ labels: [String: String] = [:]) async {
        let measure = ColinMeasure(step: step, ok: ok, numbers: numbers, labels: labels)
        measures.append(measure)
        try? await trace.write(kind: "colin", measure)
    }

    /// Stopped by hand, by a meeting that begins, or because the trace can no longer be written.
    private func mustStop() async -> Bool {
        if Task.isCancelled { return true }
        return await trace.failure != nil
    }

    private mutating func steps() async -> End {
        guard let binary = probe.binary else {
            await note("binaire", ok: false, ["trouve": 0])
            reason = "introuvable"
            return .arretee
        }
        let version = await probe.tool(binary, ["--version"], toolEnvironment)
        await note("binaire", ok: true, ["trouve": 1], ["sorte": ClaudeBinary.kind(of: binary, home: probe.home), "version": Self.version(version?.output)])

        let root = account ?? probe.home.appending(path: ".claude", directoryHint: .isDirectory)
        let busyBefore = probe.busySessions(root)

        let before = await connected(binary)
        await note("compte", ok: before.connected == true, before.connected.map { ["connecte": $0 ? 1 : 0] } ?? [:], before.labels)
        if await mustStop() { return .interrompue }
        // An account that says it is not connected: nothing is launched at all.
        if before.connected == false {
            reason = "pas-connecte"
            return .arretee
        }

        // The connection, and what Claude Code loaded.
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let first = await launch(ping, binary)
        let start = first.initial
        var connection: [String: Double] = [
            "initMs": first.initMs ?? -1, "totalMs": first.totalMs, "coutUSD": first.result?.costUSD ?? 0,
            "entree": Double(first.result?.inputTokens ?? 0), "sortie": Double(first.result?.outputTokens ?? 0),
        ]
        connection["premierMotMs"] = first.firstWordMs
        await note("connexion", ok: first.succeeded && first.totalMs < 10_000, connection,
                   ["cle": start?.apiKeySource ?? "", "modele": start?.model ?? "", "mode": start?.permissionMode ?? "", "version": start?.version ?? ""])
        if Task.isCancelled { return .interrompue }
        guard first.succeeded else {
            // Not connected, no answer, or anything else: said once, and nothing is launched again.
            let failure = Self.failure(first)
            await note("panne", ok: failure.ok, failure.numbers, failure.labels)
            reason = Self.breakdown(first)
            return .arretee
        }
        // Nothing of the user's may have come along. Claude Code's own plugins and agents always do, and its socket
        // for the other sessions may be open: they are told, and are no fault.
        let loaded: [String: Double] = [
            "outils": Double(start?.tools.count ?? -1), "serveurs": Double(start?.servers.count ?? -1), "plugins": Double(start?.plugins ?? -1),
            "skills": Double(start?.skills ?? -1), "commandes": Double(start?.slashCommands ?? -1),
            "memoires": Double(start?.memoryPaths ?? -1), "dossiers": Double(start?.directories ?? -1),
        ]
        let told: [String: Double] = [
            "pluginsIntegres": Double(start?.builtinPlugins ?? 0), "agents": Double(start?.agents.count ?? 0), "messagerie": start?.messaging == true ? 1 : 0,
        ]
        await note("isolation", ok: loaded.values.allSatisfy { $0 == 0 }, loaded.merging(told) { first, _ in first })

        // Launches in a row: does the account stay connected?
        var times = [first.totalMs]
        var launched = 1
        var failed: Outcome?
        for _ in 1..<max(probe.pings, 1) {
            if probe.pause > 0 { try? await Task.sleep(for: .seconds(probe.pause)) }
            if await mustStop() { return .interrompue }
            let outcome = await launch(ping, binary)
            launched += 1
            if Task.isCancelled { return .interrompue }
            guard outcome.succeeded else {
                failed = outcome
                break
            }
            times.append(outcome.totalMs)
        }
        let after = await connected(binary)
        await note("connexions", ok: times.count == launched && after.connected == true, [
            "lancements": Double(launched), "reussis": Double(times.count),
            "msMoyen": (times.reduce(0, +) / Double(times.count) * 10).rounded() / 10, "msMax": times.max() ?? 0,
            "connecteApres": after.connected.map { $0 ? 1 : 0 } ?? -1,
        ])
        if let failed, await broke(failed) { return .arretee }
        if after.connected == false {
            reason = "pas-connecte"
            return .arretee
        }
        if await mustStop() { return .interrompue }

        // The tools: one allowed, which runs; one outside the profile, which must be refused.
        var server: String?
        if let helper = probe.helper {
            let file = base.appending(path: "Polhub.sqlite")
            do {
                try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
                let store = ProjectStore(try AppDatabase(path: file.path(percentEncoded: false)))
                let project = try store.addProject(name: "Projet d'essai", status: .priorite2, at: Date())
                let config = ClaudeCommand.mcpConfig(helper: helper, base: file)
                server = config
                let outcome = await launch(ClaudeCommand(model: "haiku", systemPrompt: Texts.system, prompt: Texts.tools, mcpConfig: config,
                                                         allowedTools: [Self.allowed], maxTurns: 6, configDirectory: account), binary)
                let written = (try? store.journal(projectID: project.id).count) ?? -1
                let denied = outcome.result?.denied ?? []
                await note("outils", ok: outcome.tools.contains(Self.allowed) && !denied.isEmpty && written == 0, [
                    "serveurs": Double(outcome.initial?.servers.values.filter { $0 == "connected" }.count ?? 0),
                    "outilsVus": Double(outcome.initial?.tools.count ?? 0), "appels": Double(outcome.tools.count),
                    "refus": Double(denied.count), "journalEcrit": Double(written), "ms": outcome.totalMs,
                ], ["refuses": denied.joined(separator: ",")])
                if await broke(outcome) { return .arretee }
            } catch {
                await note("outils", ok: false, [:], ["raison": "base d'essai impossible"])
            }
        } else {
            await note("outils", ok: false, [:], ["raison": "programme des outils introuvable"])
        }
        if await mustStop() { return .interrompue }

        if let cause = await converse(binary, server: server) {
            reason = cause
            return .arretee
        }
        if await mustStop() { return .interrompue }

        // The first word of the same short answer, by model and by effort: what a person waits for in a conversation.
        let voices: [(name: String, model: String, effort: String?)] = [("opus", "opus", nil), ("opus-low", "opus", "low"), ("sonnet", "sonnet", nil), ("haiku", "haiku", nil)]
        for voice in voices {
            let outcome = await launch(ClaudeCommand(model: voice.model, systemPrompt: Texts.system, prompt: Texts.turns[0], maxTurns: 1,
                                                     configDirectory: account, effort: voice.effort), binary)
            await note("premier-mot", ok: outcome.succeeded, Self.spent(outcome), ["nom": voice.name, "modele": outcome.initial?.model ?? ""])
            if await broke(outcome) { return .arretee }
            if await mustStop() { return .interrompue }
        }

        // What a scene costs.
        let scenes = [("fiche-mail", "haiku", Texts.mailRequest), ("brouillon", "opus", Texts.threadRequest), ("compte-rendu", "opus", Texts.callRequest)]
        for (name, model, request) in scenes {
            let outcome = await launch(ClaudeCommand(model: model, systemPrompt: Texts.system, prompt: request, maxTurns: 1, configDirectory: account), binary)
            await note("scene", ok: outcome.succeeded, Self.spent(outcome), ["nom": name])
            if await broke(outcome) { return .arretee }
            if await mustStop() { return .interrompue }
        }

        // An account that is not connected, on purpose (an empty folder): how does it show? Not a new try: another account.
        try? FileManager.default.createDirectory(at: emptyAccount, withIntermediateDirectories: true)
        var lost = ping
        lost.configDirectory = emptyAccount
        let failure = Self.failure(await launch(lost, binary))
        await note("panne", ok: failure.ok, failure.numbers, failure.labels)
        if await mustStop() { return .interrompue }

        // Nothing kept of Colin among the conversations of the account.
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.appending(path: "projects").path(percentEncoded: false))) ?? []
        let kept = names.filter { $0.contains(token) }.count
        await note("invisible", ok: kept == 0, ["dossiersDeConversation": Double(kept)])

        // Where the account stands in its windows, before and after; and whether other conversations were at work,
        // which would have moved it too.
        let windows = limits.filter { $0.fiveHour != nil || $0.sevenDay != nil }
        var used: [String: Double] = [:]
        func percent(_ part: Double?) -> Double? { part.map { ($0 * 1_000).rounded() / 10 } }
        if let first = windows.first, let last = windows.last {
            used["cinqHeuresAvant"] = percent(first.fiveHour)
            used["cinqHeuresApres"] = percent(last.fiveHour)
            used["semaineAvant"] = percent(first.sevenDay)
            used["semaineApres"] = percent(last.sevenDay)
        }
        used["conversationsAuTravailAvant"] = busyBefore.map(Double.init)
        used["conversationsAuTravailApres"] = probe.busySessions(root).map(Double.init)
        await note("limites", ok: !windows.isEmpty, used, windows.last.map { ["etat": $0.status] } ?? [:])
        return .complete
    }

    private mutating func close(_ end: End) async {
        let failed = measures.filter { !$0.ok }.count
        let ok = end == .complete && failed == 0
        var labels = ["fin": end.rawValue]
        if !unexpected.isEmpty { labels["inattendus"] = Set(unexpected).sorted().prefix(5).joined(separator: ",") }
        if let reason { labels["raison"] = reason }
        await note("bilan", ok: ok, [
            "etapes": Double(measures.count), "echecs": Double(failed), "coutTotalUSD": cost, "inattendus": Double(unexpected.count),
            "dureeS": (milliseconds(clock.now - began) / 100).rounded() / 10,
        ], labels)
        guard end != .interrompue else { return }
        var report: [String: Any] = ["ok": ok]
        if let reason { report["raison"] = reason }
        try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]).write(to: directory.appending(path: "bilan.json"))
    }

    // MARK: Pieces

    /// « 2.1.304 (Claude Code) » → « 2.1.304 »; anything that does not look like a version is not kept.
    private static func version(_ output: String?) -> String {
        guard let word = output?.split(whereSeparator: \.isWhitespace).first.map(String.init),
              word.wholeMatch(of: /\d+\.\d+\.\d+/) != nil else { return "" }
        return word
    }

    /// `claude auth status --json`: is the account connected? Only that, and how: never who.
    private func connected(_ binary: URL) async -> (connected: Bool?, labels: [String: String]) {
        guard let answer = await probe.tool(binary, ["auth", "status", "--json"], toolEnvironment),
              let object = try? JSONSerialization.jsonObject(with: Data(answer.output.utf8)) as? [String: Any] else {
            return (nil, ["raison": "sans réponse lisible"])
        }
        var labels: [String: String] = [:]
        if let method = object["authMethod"] as? String { labels["methode"] = method }
        if let plan = object["subscriptionType"] as? String { labels["abonnement"] = plan }
        guard let logged = object["loggedIn"] as? Bool else {
            // An answer of another shape: the names of its fields say which, never their values.
            labels["cles"] = object.keys.sorted().joined(separator: ",")
            return (nil, labels)
        }
        return (logged, labels)
    }

    private mutating func launch(_ command: ClaudeCommand, _ binary: URL) async -> Outcome {
        let outcome = await Self.collect(command, binary: binary, directory: work, probe: probe)
        limits += outcome.limits
        unexpected += outcome.unexpected
        cost += outcome.result?.costUSD ?? 0
        return outcome
    }

    /// A Claude that is not connected, does not answer or cannot start: said once, and the probe stops there.
    private mutating func broke(_ outcome: Outcome) async -> Bool {
        guard let cause = Self.breakdown(outcome) else { return false }
        let failure = Self.failure(outcome)
        await note("panne", ok: failure.ok, failure.numbers, failure.labels)
        reason = cause
        return true
    }

    /// One launch, read to its end; killed after the probe's delay, or when the probe is stopped.
    private static func collect(_ command: ClaudeCommand, binary: URL, directory: URL, probe: ColinProbe) async -> Outcome {
        let clock = ContinuousClock()
        let start = clock.now
        let session: any ClaudeSession
        do {
            session = try probe.launcher.start(command, binary: binary, directory: directory)
        } catch {
            var outcome = Outcome()
            outcome.couldNotStart = true
            return outcome
        }
        let late = Flag()
        let watchdog = Task { [timeout = probe.timeout] in
            try? await Task.sleep(for: .seconds(timeout))
            if Task.isCancelled { return }
            late.raise()
            session.stop()
        }
        var outcome: Outcome = await withTaskCancellationHandler {
            var outcome = Outcome()
            for await event in session.events {
                switch event {
                case .initialized(let initial):
                    outcome.initial = initial
                    outcome.initMs = milliseconds(clock.now - start)
                case .textDelta:
                    if outcome.firstWordMs == nil { outcome.firstWordMs = milliseconds(clock.now - start) }
                case .assistant(_, let tools):
                    outcome.tools += tools
                case .rateLimit(let limit):
                    outcome.limits.append(limit)
                case .result(let result):
                    outcome.result = result
                    outcome.totalMs = milliseconds(clock.now - start)
                case .other(let name):
                    if !isExpected(name) { outcome.unexpected.append(name) }
                case .exited(let code, let errors):
                    outcome.code = code
                    outcome.errors = errors
                default:
                    break
                }
            }
            return outcome
        } onCancel: {
            session.stop()
        }
        watchdog.cancel()
        outcome.timedOut = late.isRaised
        if outcome.result == nil { outcome.totalMs = milliseconds(clock.now - start) }
        return outcome
    }

    /// The time, the cost and the size of one answer.
    private static func spent(_ outcome: Outcome) -> [String: Double] {
        var numbers: [String: Double] = [
            "ms": outcome.totalMs, "coutUSD": outcome.result?.costUSD ?? 0,
            "entree": Double(outcome.result?.inputTokens ?? 0), "sortie": Double(outcome.result?.outputTokens ?? 0),
        ]
        numbers["premierMotMs"] = outcome.firstWordMs
        return numbers
    }

    /// What stops the probe: « lancement-impossible », « sans-reponse », « pas-connecte ». `nil`: the launch went
    /// through, or failed for a reason of its own (the model, a turn too many), which stops nothing.
    private static func breakdown(_ outcome: Outcome) -> String? {
        if outcome.couldNotStart { return "lancement-impossible" }
        if outcome.timedOut { return "sans-reponse" }
        guard !outcome.succeeded else { return nil }
        return saysNotConnected((outcome.result?.text ?? "") + " " + outcome.errors) ? "pas-connecte" : nil
    }

    /// How a launch that failed shows: its code, whether a result came, and what it looks like.
    private static func failure(_ outcome: Outcome) -> (ok: Bool, numbers: [String: Double], labels: [String: String]) {
        let isError = outcome.result?.isError ?? false
        let recognizable = isError || outcome.timedOut || outcome.couldNotStart || (outcome.code ?? 0) != 0
        return (recognizable, [
            "code": Double(outcome.code ?? -1), "resultat": outcome.result == nil ? 0 : 1, "erreur": isError ? 1 : 0,
            "statutAPI": Double(outcome.result?.apiErrorStatus ?? 0), "ms": outcome.totalMs,
        ], ["sousType": outcome.result?.subtype ?? "", "categorie": breakdown(outcome) ?? "autre"])
    }

    /// The conversation; returns why the probe must stop, when it broke down.
    private mutating func converse(_ binary: URL, server: String?) async -> String? {
        let command = ClaudeCommand(model: "opus", systemPrompt: Texts.system, mcpConfig: server,
                                    allowedTools: server == nil ? [] : [Self.allowed], configDirectory: account)
        let session: any ClaudeSession
        do {
            session = try probe.launcher.start(command, binary: binary, directory: work)
        } catch {
            await note("conversation", ok: false, [:], ["raison": "lancement impossible"])
            await note("panne", ok: true, [:], ["categorie": "lancement-impossible", "sousType": ""])
            return "lancement-impossible"
        }
        let tool = probe.tool
        let conversation = Conversation(session: session, turns: Texts.turns, timeout: probe.timeout, initWait: probe.initWait,
                                        interruptDelay: probe.interruptDelay) {
            guard let answer = await tool(URL(fileURLWithPath: "/bin/ps"), ["-o", "time=,rss=", "-p", String(session.pid)], [:]) else { return nil }
            return Conversation.usage(answer.output)
        }
        await conversation.begin()
        await withTaskCancellationHandler {
            for await event in session.events { await conversation.handle(event) }
        } onCancel: {
            session.stop()
        }
        let summary = await conversation.summary()
        limits += summary.limits
        unexpected += summary.unexpected
        cost += summary.cost
        await note("conversation", ok: summary.ok, summary.numbers, summary.labels)
        guard let breakdown = summary.breakdown, !Task.isCancelled else { return nil }
        await note("panne", ok: true, ["tour": Double(summary.turn)], ["categorie": breakdown, "sousType": ""])
        return breakdown
    }
}

// MARK: - The conversation

/// Four messages in one process: the first word and the whole answer are timed, the third answer is interrupted, and
/// the fourth shows that the conversation outlives it. A turn in error, or one that never answers, ends it.
private actor Conversation {
    typealias Sample = @Sendable () async -> (cpu: Double, memory: Double)?
    typealias Summary = (ok: Bool, numbers: [String: Double], labels: [String: String], limits: [ClaudeRateLimit], unexpected: [String],
                         cost: Double, turn: Int, breakdown: String?)
    static let interruptID = "sonde-interruption"

    private let session: any ClaudeSession
    private let turns: [String]
    private let timeout: Double
    private let initWait: Double
    private let interruptDelay: Double
    private let sample: Sample
    private let clock = ContinuousClock()
    private let started: ContinuousClock.Instant
    private var numbers: [String: Double] = ["appels2": 0, "interruptionRecue": 0, "inattendus": 0]
    private var labels: [String: String] = [:]
    private var limits: [ClaudeRateLimit] = []
    private var unknown: [String] = []
    private var costs: [Double] = []
    private var turn = 0
    private var turnStart: ContinuousClock.Instant?
    private var sawWord = false
    private var interruptedAt: ContinuousClock.Instant?
    private var closedAt: ContinuousClock.Instant?
    private var starter: Task<Void, Never>?
    private var interrupter: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var over = false
    private var timedOut = false
    private var notConnected = false

    init(session: any ClaudeSession, turns: [String], timeout: Double, initWait: Double, interruptDelay: Double, sample: @escaping Sample) {
        self.session = session
        self.turns = turns
        self.timeout = timeout
        self.initWait = initWait
        self.interruptDelay = interruptDelay
        self.sample = sample
        started = clock.now
    }

    /// Claude Code is given `initWait` seconds to say what it loaded; then the first message goes anyway.
    func begin() {
        starter = Task { [initWait] in
            try? await Task.sleep(for: .seconds(initWait))
            if Task.isCancelled { return }
            await self.spokeFirst()
        }
    }

    private func spokeFirst() async {
        guard turn == 0, !over else { return }
        numbers["initAvantMessage"] = 0
        await next()
    }

    func handle(_ event: ClaudeEvent) async {
        switch event {
        case .initialized(let initial):
            // Claude Code 2.1.304 says it again at each turn (measured on 17/11): the first one is the one timed.
            numbers["inits", default: 0] += 1
            if numbers["initMs"] == nil {
                numbers["initMs"] = milliseconds(clock.now - started)
                labels["modele"] = initial.model
            }
            if turn == 0 {
                numbers["initAvantMessage"] = 1
                await next()
            }
        case .textDelta:
            guard !sawWord, let turnStart else { return }
            sawWord = true
            numbers["premierMot\(turn)Ms"] = milliseconds(clock.now - turnStart)
            if turn == 3 { interruptSoon() }
        case .assistant(_, let tools):
            if turn == 2 { numbers["appels2", default: 0] += Double(tools.count) }
        case .controlResponse(let requestID, let success) where requestID == Self.interruptID:
            numbers["interruptionRecue"] = success ? 1 : 0
        case .rateLimit(let limit):
            limits.append(limit)
        case .result(let result):
            guard (1...turns.count).contains(turn), let turnStart else { return }
            numbers["tour\(turn)Ms"] = milliseconds(clock.now - turnStart)
            numbers["cout\(turn)"] = result.costUSD
            costs.append(result.costUSD)
            let succeeded = result.subtype == "success" && !result.isError
            if turn == 3 {
                labels["finInterrompue"] = result.subtype
                if let interruptedAt { numbers["interruptionMs"] = milliseconds(clock.now - interruptedAt) }
            }
            if turn == turns.count { numbers["tour\(turn)Reussi"] = succeeded ? 1 : 0 }
            // The interrupted turn ends in error on purpose. Any other turn in error ends the conversation: nothing
            // more is said to a Claude that fails.
            if !succeeded, !(turn == 3 && interruptedAt != nil) {
                labels["arret"] = "tour \(turn)"
                if saysNotConnected(result.text) { notConnected = true }
                end()
                return
            }
            await next()
        case .other(let name):
            guard !isExpected(name) else { return }
            numbers["inattendus", default: 0] += 1
            unknown.append(name)
        case .exited(let code, _):
            over = true
            watchdog?.cancel()
            numbers["code"] = Double(code)
            if let closedAt { numbers["sortieMs"] = milliseconds(clock.now - closedAt) }
        default:
            break
        }
    }

    /// The next message; after the last one, the weight of the process is read and its input is closed.
    private func next() async {
        watchdog?.cancel()
        guard !over else { return }
        turn += 1
        guard turn <= turns.count else {
            if let usage = await sample() {
                numbers["cpuS"] = usage.cpu
                numbers["memoireMo"] = usage.memory
            }
            end()
            return
        }
        sawWord = false
        turnStart = clock.now
        session.send(turns[turn - 1])
        arm(turn)
    }

    /// Nothing more is said: the input closes, and the process has `timeout` seconds to end.
    private func end() {
        watchdog?.cancel()
        guard !over, closedAt == nil else { return }
        closedAt = clock.now
        session.closeInput()
        arm(turns.count + 1)
    }

    private func arm(_ armed: Int) {
        watchdog = Task { [timeout] in
            try? await Task.sleep(for: .seconds(timeout))
            if Task.isCancelled { return }
            self.late(armed)
        }
    }

    /// A turn that never answered: the process is stopped, and the probe will stop with it. A process slow to end
    /// after its input closed is stopped too, and only noted.
    private func late(_ armed: Int) {
        guard !over, armed > turns.count ? closedAt != nil : turn == armed else { return }
        if armed <= turns.count {
            labels["delai"] = "tour \(armed)"
            timedOut = true
        } else {
            labels["delai"] = "fermeture"
        }
        session.stop()
    }

    private func interruptSoon() {
        interrupter = Task { [interruptDelay] in
            if interruptDelay > 0 { try? await Task.sleep(for: .seconds(interruptDelay)) }
            if Task.isCancelled { return }
            self.interruptNow()
        }
    }

    private func interruptNow() {
        guard turn == 3, interruptedAt == nil, !over else { return }
        interruptedAt = clock.now
        session.interrupt(Self.interruptID)
    }

    /// What was measured, once the process is gone; nothing of the conversation's own stays behind.
    func summary() -> Summary {
        starter?.cancel()
        interrupter?.cancel()
        watchdog?.cancel()
        if !unknown.isEmpty { labels["inattendus"] = Set(unknown).sorted().prefix(5).joined(separator: ",") }
        let ok = (numbers["premierMot1Ms"] ?? .infinity) < 4_000 && numbers["interruptionRecue"] == 1 && numbers["tour\(turns.count)Reussi"] == 1
        let breakdown = timedOut ? "sans-reponse" : (notConnected ? "pas-connecte" : nil)
        return (ok, numbers, labels, limits, unknown, costs.max() ?? 0, turn, breakdown)
    }

    /// `ps -o time=,rss=` → the seconds of processor used, the megabytes held. « 0:01.50 204800 » → 1.5 s, 200 Mo.
    static func usage(_ output: String) -> (cpu: Double, memory: Double)? {
        let fields = output.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 2, let kilobytes = Double(fields[1]) else { return nil }
        let seconds = fields[0].split(separator: ":").reversed().enumerated().reduce(0.0) { total, part in
            total + (Double(part.element) ?? 0) * pow(60, Double(part.offset))
        }
        return ((seconds * 100).rounded() / 100, (kilobytes / 1_024 * 10).rounded() / 10)
    }
}
