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
/// a time, each one gone before the next begins. A Claude that is not connected, has reached its limit, does not
/// answer, cannot start or loaded more than what was asked stops the probe at whatever launch it shows: nothing is
/// tried after it.
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
    fileprivate let folderName: String?

    /// - Parameters:
    ///   - helper: Polhub's command line, the server of the tools; `nil`: the tools are not measured.
    ///   - pings: how many launches in a row, the first included.
    ///   - pause: seconds between two of them.
    ///   - timeout: seconds a launch, or a turn of the conversation, may take before it is killed.
    ///   - initWait: seconds the conversation waits for Claude Code's first line before speaking.
    ///   - interruptDelay: seconds after the first word of the third answer before it is interrupted.
    ///   - busySessions: how many conversations of Claude Code are at work, for the account's folder given.
    ///   - folderName: the name of the run's own folder among the temporary ones; `nil`: a new name at each run.
    public init(launcher: any ClaudeLaunching = LiveClaudeLauncher(), binary: URL? = ClaudeBinary.find(), helper: URL?,
                home: URL = FileManager.default.homeDirectoryForCurrentUser, environment: [String: String] = ProcessInfo.processInfo.environment,
                pings: Int = 20, pause: Double = 1, timeout: Double = 60, initWait: Double = 2, interruptDelay: Double = 0.4,
                tool: @escaping Tool = { await ClaudeTool.run($0, arguments: $1, environment: $2, timeout: 15) },
                busySessions: @escaping @Sendable (URL) -> Int? = { ColinProbe.busySessions(in: $0) }, folderName: String? = nil) {
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
        self.folderName = folderName
    }

    /// `request.variant`: the folder of the Claude account; empty, absent, or Claude Code's own folder: its own account.
    public func run(_ request: ProbeRequest, trace: TraceWriter, directory: URL) async {
        Self.runs.begin()
        defer { Self.runs.end() }
        var run = Run(probe: self, account: ClaudeCommand.account(folder: request.variant, home: home), trace: trace, directory: directory)
        await run.go()
    }

    static let runs = Runs()

    /// The app is going and has stopped every Claude Code: the runs under way are given this long to end their own
    /// way (a last line in their trace, their folder removed). It returns as soon as none is left.
    public static func waitUntilDone(within seconds: Double) {
        runs.wait(within: seconds)
    }

    /// The runs under way, counted from whatever thread.
    final class Runs: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func begin() { lock.withLock { count += 1 } }
        func end() { lock.withLock { count -= 1 } }

        func wait(within seconds: Double) {
            let deadline = Date().addingTimeInterval(seconds)
            while lock.withLock({ count }) > 0, Date() < deadline { usleep(20_000) }
        }
    }

    /// `<directory>/bilan.json`; `nil`: no report (the probe was stopped before its end).
    public static func verdict(in directory: URL) -> Bool? {
        report(in: directory)?["ok"] as? Bool
    }

    /// Why the probe stopped early, when it knows: « introuvable », « pas-connecte », « limite-atteinte »,
    /// « sans-reponse », « lancement-impossible », « isolation » (Claude Code loaded more than what was asked),
    /// « isolation-inconnue » (nothing says what it loaded), « erreur ».
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

private struct Outcome: Sendable {
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
    /// Stopped by the probe's delay.
    var timedOut = false
    var couldNotStart = false
    /// Stopped because the probe itself was.
    var cancelled = false

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

/// A part from 0 to 1 → a percentage with one decimal.
private func percent(_ part: Double?) -> Double? {
    part.map { ($0 * 1_000).rounded() / 10 }
}

private let wordCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_[]")

/// A word of Claude Code's own (a version, a model, a mode, the name of a tool), kept only when it looks like one:
/// short, made of letters, digits and « . - _ [ ] ». Anything else (a path, an address, a sentence) is « autre »:
/// the trace is meant to be shown, and holds nothing of the user's.
private func word(_ text: String?) -> String {
    guard let text, !text.isEmpty else { return "" }
    return text.count <= 64 && text.allSatisfy(wordCharacters.contains) ? text : "autre"
}

/// The name of a line: « type » or « type/subtype », each one a technical word; anything else is « autre ».
private func lineName(_ name: String) -> String {
    let parts = name.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
    return parts.allSatisfy { !$0.isEmpty && word($0) == $0 } ? name : "autre"
}

/// The partial messages and Claude Code's own notices are expected; any other line nobody asked for is counted and
/// named: it may be a message of another session. A hook that runs is one of the user's settings at work: never
/// expected. The mark of an interruption is expected only where the probe itself interrupted or stopped Claude Code.
private func isExpected(_ name: String) -> Bool {
    if name.hasPrefix(hookLines) { return false }
    return name.hasPrefix("stream_event/") || name.hasPrefix("system/") || name == "keep_alive"
}

/// « system/hook_started », « system/hook_response »…: what Claude Code writes when a hook runs.
private let hookLines = "system/hook"

private let interruptionMark = "user/interruption"

/// What Claude Code says when the account is not connected: the same words as Colin's engine.
private func saysNotConnected(_ text: String) -> Bool { ColinFailure.saysNotConnected(text) }

// MARK: - The run

private struct Run {
    enum End: String { case complete, arretee, interrompue }

    typealias Texts = ColinProbeTexts
    static let allowed = "mcp__polhub__projets"
    /// What the first launch may read, in tokens. Measured on 17/11 with Claude Code 2.1.304: 620 to 660 with
    /// nothing of the user's. It catches what is large (long instructions of the account, a memory); a file
    /// shorter than the margin would pass, and only the word of the planted file proves the folder's own.
    static let contextCeiling = 1_000.0

    let probe: ColinProbe
    let account: URL?
    let trace: TraceWriter
    let directory: URL
    /// The name of the run's own folder. Claude Code would name a conversation's folder after it.
    let token: String
    /// The run's own folder, among the temporary ones: everything it makes lives there and goes with it at the
    /// end, and nothing else is touched. Its path says nothing of the user: Claude Code tells the model where it
    /// runs (measured on 17/11), and gives the base's path to the server of the tools.
    let root: URL
    /// The folder was made by this run: only then is it removed.
    var ownsRoot = false
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
        token = probe.folderName ?? "colin-sonde-" + UUID().uuidString.prefix(8).lowercased()
        root = FileManager.default.temporaryDirectory.appending(path: token, directoryHint: .isDirectory)
        began = clock.now
    }

    private var toolEnvironment: [String: String] {
        ClaudeCommand(model: "", systemPrompt: "", configDirectory: account).environment(from: probe.environment)
    }

    private var ping: ClaudeCommand {
        ClaudeCommand(model: "haiku", systemPrompt: Texts.system, prompt: Texts.ping, maxTurns: 1, configDirectory: account)
    }

    /// Where the launches run.
    private var work: URL { root.appending(path: "travail", directoryHint: .isDirectory) }
    private var base: URL { root.appending(path: "base", directoryHint: .isDirectory) }
    private var emptyAccount: URL { root.appending(path: "compte-vide", directoryHint: .isDirectory) }

    mutating func go() async {
        let end = await steps()
        await close(end)
        // Nothing of the run stays but its trace and its report.
        if ownsRoot { try? FileManager.default.removeItem(at: root) }
    }

    /// The run's folders, made by it and by nobody else: a path that already stands is refused, never adopted.
    /// A file of instructions waits in the launches' folder, on purpose: closed on itself, Claude Code does not
    /// read it, and the first launch asks for its word.
    private mutating func prepare() -> Bool {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: false)
            ownsRoot = true
            for folder in [work, base, emptyAccount] { try manager.createDirectory(at: folder, withIntermediateDirectories: false) }
            try Data(Texts.memoryFile.utf8).write(to: work.appending(path: "CLAUDE.md"))
            return true
        } catch {
            return false
        }
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
        if await mustStop() { return .interrompue }
        await note("binaire", ok: true, ["trouve": 1], ["sorte": ClaudeBinary.kind(of: binary, home: probe.home), "version": Self.version(version?.output)])

        let root = account ?? probe.home.appending(path: ".claude", directoryHint: .isDirectory)
        let busyBefore = probe.busySessions(root)

        let before = await connected(binary)
        if await mustStop() { return .interrompue }
        await note("compte", ok: before.connected == true, before.connected.map { ["connecte": $0 ? 1 : 0] } ?? [:], before.labels)
        // An account that says it is not connected: nothing is launched at all.
        if before.connected == false {
            reason = "pas-connecte"
            return .arretee
        }

        guard prepare() else {
            await note("dossier", ok: false)
            reason = "lancement-impossible"
            return .arretee
        }
        // The connection, and what Claude Code loaded. The first launch asks for the word of the instructions left
        // in its folder, which a Claude closed on itself does not know.
        var asking = ping
        asking.prompt = Texts.memoryRequest
        let first = await launch(asking, binary)
        if Task.isCancelled { return .interrompue }
        let start = first.initial
        var connection: [String: Double] = [
            "initMs": first.initMs ?? -1, "totalMs": first.totalMs, "coutUSD": first.result?.costUSD ?? 0,
            "entree": Double(first.result?.inputTokens ?? 0), "sortie": Double(first.result?.outputTokens ?? 0),
        ]
        connection["premierMotMs"] = first.firstWordMs
        await note("connexion", ok: first.succeeded && first.totalMs < 10_000, connection,
                   ["cle": word(start?.apiKeySource), "modele": word(start?.model), "mode": word(start?.permissionMode), "version": word(start?.version)])
        guard first.succeeded else {
            // Not connected, at its limit, no answer, or an error of its own: said once, and nothing is launched again.
            let failure = Self.failure(first)
            await note("panne", ok: failure.ok, failure.numbers, failure.labels)
            reason = Self.breakdown(first) ?? "erreur"
            return .arretee
        }
        // Nothing of the user's may have come along. Claude Code's own plugins and agents always do, and its socket
        // for the other sessions may be open: they are told, and are no fault. A list that Claude Code no longer
        // gives proves nothing: it is a fault too. Its first line never tells the instructions it read (measured on
        // 17/11): those show by the word of the file, and by the size of what the launch read.
        let loaded: [String: Double] = [
            "outils": Double(start?.tools.count ?? -1), "serveurs": Double(start?.servers.count ?? -1), "plugins": Double(start?.plugins ?? -1),
            "skills": Double(start?.skills ?? -1), "commandes": Double(start?.slashCommands ?? -1),
            "memoires": Double(start?.memoryPaths ?? -1), "dossiers": Double(start?.directories ?? -1),
        ]
        let told: [String: Double] = [
            "pluginsIntegres": Double(start?.builtinPlugins ?? 0), "agents": Double(start?.agents.count ?? 0), "messagerie": start?.messaging == true ? 1 : 0,
        ]
        let read = first.result?.text.contains(Texts.memoryWord) ?? false
        let context = Double(first.result?.inputTokens ?? 0)
        // A hook that ran during the launch: the user's settings were read after all.
        let hooks = first.unexpected.filter { $0.hasPrefix(hookLines) }.count
        let seen: [String: Double] = ["hooks": Double(hooks), "consigneLue": read ? 1 : 0, "contexte": context]
        let missing = start?.missing ?? []
        // « It loaded more » and « nothing says what it loaded » are two things to read, and two reasons.
        let leaked = loaded.values.contains { $0 > 0 } || hooks > 0 || read || context > Self.contextCeiling
        let unknown = loaded.values.contains { $0 < 0 } || !missing.isEmpty || context < 1
        await note("isolation", ok: !leaked && !unknown, loaded.merging(told) { first, _ in first }.merging(seen) { first, _ in first },
                   missing.isEmpty ? [:] : ["champsAbsents": missing.map { word($0) }.joined(separator: ",")])
        // Either way, this Claude Code is given nothing more.
        guard !leaked, !unknown else {
            reason = leaked ? "isolation" : "isolation-inconnue"
            return .arretee
        }

        // Launches in a row: does the account stay connected?
        var times = [first.totalMs]
        var launched = 1
        var failed: Outcome?
        for _ in 1..<max(probe.pings, 1) {
            if probe.pause > 0 { try? await Task.sleep(for: .seconds(probe.pause)) }
            if await mustStop() { return .interrompue }
            let outcome = await launch(ping, binary)
            if Task.isCancelled { return .interrompue }
            launched += 1
            guard outcome.succeeded else {
                failed = outcome
                break
            }
            times.append(outcome.totalMs)
        }
        // A Claude Code that broke down is not started again, not even to ask whether it is still connected.
        let broken = failed.flatMap(Self.breakdown) != nil
        var after: (connected: Bool?, labels: [String: String]) = (nil, [:])
        if !broken {
            after = await connected(binary)
            if await mustStop() { return .interrompue }
        }
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
                let store = ProjectStore(try AppDatabase(path: file.path(percentEncoded: false)))
                let project = try store.addProject(name: "Projet d'essai", status: .priorite2, at: Date())
                let config = ClaudeCommand.mcpConfig(helper: helper, base: file)
                server = config
                let outcome = await launch(ClaudeCommand(model: "haiku", systemPrompt: Texts.system, prompt: Texts.tools, mcpConfig: config,
                                                         allowedTools: [Self.allowed], maxTurns: 6, configDirectory: account), binary)
                if Task.isCancelled { return .interrompue }
                let written = (try? store.journal(projectID: project.id).count) ?? -1
                let denied = outcome.result?.denied ?? []
                await note("outils", ok: outcome.tools.contains(Self.allowed) && !denied.isEmpty && written == 0, [
                    "serveurs": Double(outcome.initial?.servers.values.filter { $0 == "connected" }.count ?? 0),
                    "outilsVus": Double(outcome.initial?.tools.count ?? 0), "appels": Double(outcome.tools.count),
                    "refus": Double(denied.count), "journalEcrit": Double(written), "ms": outcome.totalMs,
                ], ["refuses": denied.prefix(5).map { word($0) }.joined(separator: ",")])
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
            if Task.isCancelled { return .interrompue }
            await note("premier-mot", ok: outcome.succeeded, Self.spent(outcome), ["nom": voice.name, "modele": word(outcome.initial?.model)])
            if await broke(outcome) { return .arretee }
            if await mustStop() { return .interrompue }
        }

        // What a scene costs.
        let scenes = [("fiche-mail", "haiku", Texts.mailRequest), ("brouillon", "opus", Texts.threadRequest), ("compte-rendu", "opus", Texts.callRequest)]
        for (name, model, request) in scenes {
            let outcome = await launch(ClaudeCommand(model: model, systemPrompt: Texts.system, prompt: request, maxTurns: 1, configDirectory: account), binary)
            if Task.isCancelled { return .interrompue }
            await note("scene", ok: outcome.succeeded, Self.spent(outcome), ["nom": name])
            if await broke(outcome) { return .arretee }
            if await mustStop() { return .interrompue }
        }

        // An account that is not connected, on purpose (an empty folder): how does it show? Not a new try: another
        // account. It must say so itself, and quickly: a silence is no signal.
        var lost = ping
        lost.configDirectory = emptyAccount
        let unconnected = await launch(lost, binary)
        if Task.isCancelled { return .interrompue }
        let failure = Self.failure(unconnected)
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
        if let first = windows.first, let last = windows.last {
            used["cinqHeuresAvant"] = percent(first.fiveHour)
            used["cinqHeuresApres"] = percent(last.fiveHour)
            used["semaineAvant"] = percent(first.sevenDay)
            used["semaineApres"] = percent(last.sevenDay)
        }
        used["conversationsAuTravailAvant"] = busyBefore.map(Double.init)
        used["conversationsAuTravailApres"] = probe.busySessions(root).map(Double.init)
        await note("limites", ok: !windows.isEmpty, used, windows.last.map { ["etat": word($0.status)] } ?? [:])
        return .complete
    }

    private mutating func close(_ end: End) async {
        let failed = measures.filter { !$0.ok }.count
        let ok = end == .complete && failed == 0
        var labels = ["fin": end.rawValue]
        if !unexpected.isEmpty { labels["inattendus"] = Set(unexpected).sorted().prefix(5).joined(separator: ",") }
        if let reason { labels["raison"] = reason }
        var numbers: [String: Double] = [
            "etapes": Double(measures.count), "echecs": Double(failed), "coutTotalUSD": cost, "inattendus": Double(unexpected.count),
            "dureeS": (milliseconds(clock.now - began) / 100).rounded() / 10,
        ]
        // Where the account stands, at whatever end: a probe stopped by a limit says where it was.
        if let state = limits.last(where: { !$0.status.isEmpty })?.status { labels["limites"] = word(state) }
        numbers["cinqHeures"] = percent(limits.last { $0.fiveHour != nil }?.fiveHour)
        numbers["semaine"] = percent(limits.last { $0.sevenDay != nil }?.sevenDay)
        await note("bilan", ok: ok, numbers, labels)
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
              let object = Self.object(in: answer.output) else {
            return (nil, ["raison": "sans réponse lisible"])
        }
        var labels: [String: String] = [:]
        if let method = object["authMethod"] as? String { labels["methode"] = word(method) }
        if let plan = object["subscriptionType"] as? String { labels["abonnement"] = word(plan) }
        guard let logged = object["loggedIn"] as? Bool else {
            // An answer of another shape: the names of its fields say which, never their values.
            labels["cles"] = Set(object.keys.map { $0.isEmpty ? "autre" : word($0) }).sorted().prefix(8).joined(separator: ",")
            return (nil, labels)
        }
        return (logged, labels)
    }

    /// The object of an output that may begin with a notice: from its first « { » to its last « } ».
    private static func object(in output: String) -> [String: Any]? {
        guard let open = output.firstIndex(of: "{"), let close = output.lastIndex(of: "}"), open < close else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(output[open...close].utf8)) as? [String: Any]
    }

    private mutating func launch(_ command: ClaudeCommand, _ binary: URL) async -> Outcome {
        let outcome = await Self.collect(command, binary: binary, directory: work, probe: probe)
        limits += outcome.limits
        unexpected += outcome.unexpected
        cost += outcome.result?.costUSD ?? 0
        return outcome
    }

    /// A Claude that is not connected, is at its limit, does not answer or cannot start: said once, and the probe
    /// stops there.
    private mutating func broke(_ outcome: Outcome) async -> Bool {
        guard let cause = Self.breakdown(outcome) else { return false }
        let failure = Self.failure(outcome)
        await note("panne", ok: failure.ok, failure.numbers, failure.labels)
        reason = cause
        return true
    }

    /// One launch, read to its end; stopped after the probe's delay, or when the probe is stopped. It returns only
    /// once the process is gone: nothing of it is left running behind the probe.
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
        let late = Flag(), stopped = Flag()
        // The delay does not run while the Mac sleeps: a launch is not killed for the night it spent.
        let watchdog = Task { [timeout = probe.timeout] in
            try? await Task.sleep(for: .seconds(timeout), clock: .suspending)
            if Task.isCancelled { return }
            late.raise()
            stopped.raise()
            session.stop()
        }
        // Read in a task of its own: when the probe is stopped, the reading goes on until the process says it ended.
        let reader = Task { () -> Outcome in
            var outcome = Outcome()
            for await event in session.events {
                switch event {
                case .initialized(let initial):
                    outcome.initial = initial
                    outcome.initMs = milliseconds(clock.now - start)
                case .textDelta:
                    if outcome.firstWordMs == nil { outcome.firstWordMs = milliseconds(clock.now - start) }
                case .assistant(_, let tools, _):
                    outcome.tools += tools
                case .rateLimit(let limit):
                    outcome.limits.append(limit)
                case .result(let result):
                    // Stopped, Claude Code ends its turn in error before it leaves (measured on 17/11): the end of
                    // an interrupted turn, not an answer. A success written as the probe stopped it is one.
                    if stopped.isRaised, result.isError || result.subtype != "success" { break }
                    outcome.result = result
                    outcome.totalMs = milliseconds(clock.now - start)
                case .other(let name):
                    // Nobody interrupts a launch that answers once, unless the probe just stopped it.
                    if name == interruptionMark, stopped.isRaised { break }
                    if !isExpected(name) { outcome.unexpected.append(lineName(name)) }
                case .exited(let code, let errors):
                    outcome.code = code
                    outcome.errors = errors
                default:
                    break
                }
            }
            return outcome
        }
        var outcome = await withTaskCancellationHandler {
            await reader.value
        } onCancel: {
            stopped.raise()
            session.stop()
        }
        watchdog.cancel()
        outcome.timedOut = late.isRaised
        outcome.cancelled = Task.isCancelled
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
        // The answer came, and the process had to be stopped all the same.
        if outcome.timedOut, outcome.result != nil { numbers["sortieForcee"] = 1 }
        return numbers
    }

    /// What stops the probe: « lancement-impossible », « limite-atteinte », « pas-connecte », « sans-reponse ».
    /// `nil`: the launch went through, the probe itself was stopped, or the launch failed for a reason of its own
    /// (the model, a turn too many), which stops nothing.
    private static func breakdown(_ outcome: Outcome) -> String? {
        if outcome.succeeded { return nil }
        if outcome.couldNotStart { return "lancement-impossible" }
        if outcome.cancelled { return nil }
        if outcome.limits.contains(where: { $0.status == "rejected" }) || outcome.result?.apiErrorStatus == 429 { return "limite-atteinte" }
        if outcome.result?.apiErrorStatus == 401 || saysNotConnected((outcome.result?.text ?? "") + " " + outcome.errors) { return "pas-connecte" }
        // It answered, by an error of its own.
        guard outcome.result == nil else { return nil }
        // No answer at all: stopped for its silence, or gone by itself: before its first line, it never really
        // started.
        if outcome.timedOut { return "sans-reponse" }
        return outcome.initial == nil ? "lancement-impossible" : "sans-reponse"
    }

    /// How a launch that failed shows: its code, whether a result came, and what it looks like. `ok`: Claude Code
    /// said so itself, in time (a result in error, or a code); a silence or a launch that cannot start is no signal.
    private static func failure(_ outcome: Outcome) -> (ok: Bool, numbers: [String: Double], labels: [String: String]) {
        let isError = outcome.result?.isError ?? false
        let clear = !outcome.timedOut && !outcome.couldNotStart && (isError || (outcome.code ?? 0) != 0)
        return (clear, [
            "code": Double(outcome.code ?? -1), "resultat": outcome.result == nil ? 0 : 1, "erreur": isError ? 1 : 0,
            "statutAPI": Double(outcome.result?.apiErrorStatus ?? 0), "ms": outcome.totalMs,
        ], ["sousType": word(outcome.result?.subtype), "categorie": breakdown(outcome) ?? "autre"])
    }

    /// The conversation; returns why the probe must stop, when it broke down.
    private mutating func converse(_ binary: URL, server: String?) async -> String? {
        let command = ClaudeCommand(model: "opus", systemPrompt: Texts.system, mcpConfig: server,
                                    allowedTools: server == nil ? [] : [Self.allowed], configDirectory: account)
        let session: any ClaudeSession
        do {
            session = try probe.launcher.start(command, binary: binary, directory: work)
        } catch {
            // The probe was stopped at that very moment (the app is going, and launches nothing more): no breakdown.
            if Task.isCancelled { return nil }
            await note("conversation", ok: false, [:], ["raison": "lancement impossible"])
            await note("panne", ok: false, [:], ["categorie": "lancement-impossible", "sousType": ""])
            return "lancement-impossible"
        }
        let tool = probe.tool
        // Raised when the probe stops the process, by its delay or with the probe itself: what Claude Code writes
        // after that is the end of an interrupted turn.
        let stopped = Flag()
        let conversation = Conversation(session: session, turns: Texts.turns, timeout: probe.timeout, initWait: probe.initWait,
                                        interruptDelay: probe.interruptDelay, stopped: stopped) {
            guard let answer = await tool(URL(fileURLWithPath: "/bin/ps"), ["-o", "time=,rss=", "-p", String(session.pid)], [:]) else { return nil }
            return Conversation.usage(answer.output)
        }
        await conversation.begin()
        // Read in a task of its own: stopped, the probe still waits here until the process is gone.
        let reader = Task {
            for await event in session.events { await conversation.handle(event) }
        }
        await withTaskCancellationHandler {
            await reader.value
        } onCancel: {
            stopped.raise()
            session.stop()
        }
        let summary = await conversation.summary()
        limits += summary.limits
        unexpected += summary.unexpected
        cost += summary.cost
        // Stopped with the probe: half a conversation is not a measure.
        if Task.isCancelled { return nil }
        await note("conversation", ok: summary.ok, summary.numbers, summary.labels)
        guard let breakdown = summary.breakdown else { return nil }
        // As for a launch: only what Claude Code said itself is a clear signal.
        await note("panne", ok: breakdown == "pas-connecte" || breakdown == "limite-atteinte", ["tour": Double(summary.turn)],
                   ["categorie": breakdown, "sousType": ""])
        return breakdown
    }
}

// MARK: - The conversation

/// Four messages in one process: the first word and the whole answer are timed, the third answer is interrupted, and
/// the fourth shows that the conversation outlives it. A turn in error, one that never answers, or a process that
/// goes before its input is closed ends it.
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
    /// The probe stopped the process, by a delay of the conversation or with the probe itself.
    private let stopped: Flag
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
    private var sawInit = false
    private var interruptedAt: ContinuousClock.Instant?
    private var closedAt: ContinuousClock.Instant?
    private var starter: Task<Void, Never>?
    private var interrupter: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var over = false
    /// The account said its limit is reached.
    private var refused = false
    /// Claude Code is about to write its mark of an interruption: the probe just interrupted its turn.
    private var awaitingMark = false
    /// Why the probe must stop, once known.
    private var cause: String?

    init(session: any ClaudeSession, turns: [String], timeout: Double, initWait: Double, interruptDelay: Double, stopped: Flag,
         sample: @escaping Sample) {
        self.stopped = stopped
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
            sawInit = true
            // Claude Code 2.1.304 says it again at each turn (measured on 17/11): the first one is the one timed.
            numbers["inits", default: 0] += 1
            if numbers["initMs"] == nil {
                numbers["initMs"] = milliseconds(clock.now - started)
                labels["modele"] = word(initial.model)
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
        case .assistant(_, let tools, _):
            if turn == 2 { numbers["appels2", default: 0] += Double(tools.count) }
        case .controlResponse(let requestID, let success) where requestID == Self.interruptID:
            numbers["interruptionRecue"] = success ? 1 : 0
        case .rateLimit(let limit):
            limits.append(limit)
            if limit.status == "rejected" { refused = true }
        case .result(let result):
            // Once the input is closed, no answer is waited for; and what Claude Code writes after the probe stopped
            // it is the end of an interrupted turn. Neither is an answer.
            guard closedAt == nil, !stopped.isRaised else { return }
            let succeeded = result.subtype == "success" && !result.isError
            guard (1...turns.count).contains(turn), let turnStart else {
                // Before any message: nobody asked. In error, it says why Claude Code will not answer.
                if !succeeded {
                    blame(result)
                    end()
                }
                return
            }
            numbers["tour\(turn)Ms"] = milliseconds(clock.now - turnStart)
            numbers["cout\(turn)"] = result.costUSD
            costs.append(result.costUSD)
            if turn == 3 {
                labels["finInterrompue"] = word(result.subtype)
                if let interruptedAt { numbers["interruptionMs"] = milliseconds(clock.now - interruptedAt) }
            }
            if turn == turns.count { numbers["tour\(turn)Reussi"] = succeeded ? 1 : 0 }
            // The interrupted turn ends in error on purpose. Any other turn in error ends the conversation: nothing
            // more is said to a Claude that fails.
            if !succeeded, !(turn == 3 && interruptedAt != nil) {
                labels["arret"] = "tour \(turn)"
                blame(result)
                end()
                return
            }
            await next()
        case .other(let name):
            // Claude Code's own mark: expected once right after the probe's interruption, and after the probe
            // stopped the process; nowhere else.
            if name == interruptionMark {
                if awaitingMark {
                    awaitingMark = false
                    return
                }
                if stopped.isRaised { return }
            }
            guard !isExpected(name) else { return }
            numbers["inattendus", default: 0] += 1
            unknown.append(lineName(name))
        case .exited(let code, let errors):
            over = true
            watchdog?.cancel()
            numbers["code"] = Double(code)
            if let closedAt {
                numbers["sortieMs"] = milliseconds(clock.now - closedAt)
            } else if cause == nil {
                // Gone before the probe closed its input: it died. After a limit refused, that is why; before its
                // first line, it never really started.
                cause = refused ? "limite-atteinte"
                    : (saysNotConnected(errors) ? "pas-connecte" : (sawInit ? "sans-reponse" : "lancement-impossible"))
            }
        default:
            break
        }
    }

    /// An answer in error that tells why Claude Code will go on failing: its limit, or its connection. Any other
    /// error is the turn's own, and names nothing.
    private func blame(_ result: ClaudeResult) {
        guard cause == nil else { return }
        if refused || result.apiErrorStatus == 429 {
            cause = "limite-atteinte"
        } else if result.apiErrorStatus == 401 || saysNotConnected(result.text) {
            cause = "pas-connecte"
        }
    }

    /// The next message; after the last one, the weight of the process is read and its input is closed.
    private func next() async {
        guard !over, closedAt == nil else { return }
        watchdog?.cancel()
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

    /// Nothing more is said: the input closes, and the process has `timeout` seconds to end. Once only: a second
    /// call must not disarm the delay of the first.
    private func end() {
        guard !over, closedAt == nil else { return }
        watchdog?.cancel()
        closedAt = clock.now
        session.closeInput()
        arm(turns.count + 1)
    }

    /// The delay does not run while the Mac sleeps.
    private func arm(_ armed: Int) {
        watchdog = Task { [timeout] in
            try? await Task.sleep(for: .seconds(timeout), clock: .suspending)
            if Task.isCancelled { return }
            self.late(armed)
        }
    }

    /// A turn that never answered: the process is stopped, and the probe will stop with it. A process slow to end
    /// after its input closed is stopped too, and only noted.
    private func late(_ armed: Int) {
        guard !over, armed > turns.count ? closedAt != nil : (turn == armed && closedAt == nil) else { return }
        if armed <= turns.count {
            labels["delai"] = "tour \(armed)"
            // Silent after the account said its limit is reached: the limit is why.
            if cause == nil { cause = refused ? "limite-atteinte" : "sans-reponse" }
        } else {
            labels["delai"] = "fermeture"
        }
        stopped.raise()
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
        awaitingMark = true
        session.interrupt(Self.interruptID)
    }

    /// What was measured, once the process is gone; nothing of the conversation's own stays behind.
    func summary() -> Summary {
        starter?.cancel()
        interrupter?.cancel()
        watchdog?.cancel()
        if !unknown.isEmpty { labels["inattendus"] = Set(unknown).sorted().prefix(5).joined(separator: ",") }
        let ok = (numbers["premierMot1Ms"] ?? .infinity) < 4_000 && numbers["interruptionRecue"] == 1 && numbers["tour\(turns.count)Reussi"] == 1
        return (ok, numbers, labels, limits, unknown, costs.max() ?? 0, turn, cause)
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
