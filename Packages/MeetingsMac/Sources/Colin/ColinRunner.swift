import Domain
import Foundation

/// Where Colin's Claude Code runs (18/11): the binary, Polhub's tools server and its base, the account (`nil`: Claude
/// Code's own), and an empty working folder whose path names no one (the model is told it).
public struct ColinSetup: Sendable {
    public var binary: URL
    public var helper: URL
    public var base: URL
    public var account: URL?
    public var work: URL

    public init(binary: URL, helper: URL, base: URL, account: URL?, work: URL) {
        self.binary = binary
        self.helper = helper
        self.base = base
        self.account = account
        self.work = work
    }
}

/// One answer of Colin's.
public struct ColinTurn: Equatable, Sendable {
    public var text: String
    /// What this turn added to the process's cost (Claude Code counts it from the start of its process).
    public var costUSD: Double?
    /// Stopped by the stop arrow: the text is what came.
    public var interrupted: Bool
    /// The server's lock refused a draft: the next question starts on a fresh context.
    public var locked: Bool
    /// The tools used, in order.
    public var tools: [String]

    public init(text: String, costUSD: Double?, interrupted: Bool, locked: Bool, tools: [String]) {
        self.text = text
        self.costUSD = costUSD
        self.interrupted = interrupted
        self.locked = locked
        self.tools = tools
    }
}

/// The engine of Colin's bar (18/11): one Claude Code at a time, launched on demand, warmed by a message that holds
/// nothing of the user's, checked at each `init` (stopped at the least difference), kept ten quiet minutes, then
/// closed. A context is one process: a question after a lock refusal, a failure or the quiet minutes starts a new one,
/// with the primer.
public actor ColinRunner {
    public enum Event: Equatable, Sendable {
        case starting
        case ready
        case delta(String)
        case tool(String)
        case answered(ColinTurn)
        case failed(ColinFailure)
    }

    private enum Phase { case off, warming, ready, answering, closing }

    private let launcher: any ClaudeLaunching
    private let setup: @Sendable () -> ColinSetup?
    private let idle: Duration
    private let turnLimit: Duration
    private let continuation: AsyncStream<Event>.Continuation
    public nonisolated let events: AsyncStream<Event>

    private var session: (any ClaudeSession)?
    /// Which process the events read belong to: those of a process already left are not heard.
    private var generation = 0
    private var phase = Phase.off
    /// The process received its first question, and the primer with it.
    private var primed = false
    /// A question asked while the process warms up.
    private var pending: String?
    private var initialized = false
    private var lastCost = 0.0
    private var rate: ClaudeRateLimit?
    private var turnText = ""
    private var turnTools: [String] = []
    private var locked = false
    private var interrupted = false
    /// The quiet minutes, or the turn's limit.
    private var timer: Task<Void, Never>?

    public init(launcher: any ClaudeLaunching, setup: @escaping @Sendable () -> ColinSetup?, idle: Duration = .seconds(600),
                turnLimit: Duration = .seconds(180)) {
        self.launcher = launcher
        self.setup = setup
        self.idle = idle
        self.turnLimit = turnLimit
        (events, continuation) = AsyncStream.makeStream()
    }

    /// The next question starts a context: it carries the primer.
    public var fresh: Bool { session == nil || !primed }

    /// Launches and warms the process, if none runs.
    public func warm() {
        guard session == nil else { return }
        guard let setup = setup() else {
            pending = nil
            continuation.yield(.failed(.missing))
            return
        }
        try? FileManager.default.createDirectory(at: setup.work, withIntermediateDirectories: true)
        let command = ClaudeCommand(model: "opus", systemPrompt: ColinTexts.system,
                                    mcpConfig: ClaudeCommand.mcpConfig(helper: setup.helper, base: setup.base, colin: true),
                                    allowedTools: ColinTool.allowed, configDirectory: setup.account)
        generation += 1
        let mine = generation
        continuation.yield(.starting)
        let started: any ClaudeSession
        do {
            started = try launcher.start(command, binary: setup.binary, directory: setup.work)
        } catch {
            reset()
            continuation.yield(.failed(.launch))
            return
        }
        session = started
        (phase, primed, initialized, lastCost, rate) = (.warming, false, false, 0, nil)
        Task { [weak self] in
            for await event in started.events { await self?.handle(event, from: mine) }
        }
        started.send(ColinTexts.warmUp)
        arm(turnLimit, mine) { await $0.silent(mine) }
    }

    /// A question of Paul's. `primer` goes before it when it starts a context.
    public func ask(_ question: String, primer: String) {
        let text = (session != nil && primed) || primer.isEmpty ? question : "\(primer)\n\n\(question)"
        switch phase {
        case .off, .closing:
            if phase == .closing { reset() }
            pending = text
            warm()
        case .warming:
            pending = text
        case .ready:
            send(text)
        case .answering:
            return
        }
    }

    /// The stop arrow: the turn ends with what came; the process stays.
    public func interrupt() {
        guard phase == .answering, let session else { return }
        interrupted = true
        session.interrupt(UUID().uuidString.lowercased())
    }

    /// Kills the process now: Colin turned off, a call that begins, the Mac's sleep.
    public func stop() {
        guard let session else { return }
        reset()
        session.stop()
    }

    // MARK: - Pieces

    private func send(_ text: String) {
        guard let session else { return }
        timer?.cancel()
        (phase, primed, turnText, turnTools, locked, interrupted) = (.answering, true, "", [], false, false)
        session.send(text)
        let mine = generation
        arm(turnLimit, mine) { await $0.silent(mine) }
    }

    private func handle(_ event: ClaudeEvent, from mine: Int) {
        guard mine == generation, session != nil else { return }
        switch event {
        case .initialized(let launch):
            if let problem = ColinInitCheck.problem(launch, tools: Set(ColinTool.allowed)) { return fail(.isolation(problem)) }
            initialized = true
        case .other(let name):
            if name.hasPrefix("system/hook") { fail(.isolation("hooks")) }
        case .textDelta(let text):
            guard phase == .answering else { return }
            turnText += text
            continuation.yield(.delta(text))
        case .assistant(_, let tools):
            guard phase == .answering else { return }
            for tool in tools {
                turnTools.append(tool)
                continuation.yield(.tool(tool))
            }
        case .toolResult(let isError, let text):
            if isError, text.contains(ColinTool.lockMark) { locked = true }
        case .rateLimit(let limit):
            rate = limit
        case .result(let result):
            finish(result)
        case .controlResponse:
            break
        case .exited(_, let errors):
            let under = phase == .warming || phase == .answering
            let known = initialized
            reset()
            // Gone by itself while it worked: why it says, else its silence.
            if under { continuation.yield(.failed(ColinFailure.of(result: nil, rateLimit: rate, errors: errors, initialized: known) ?? .noAnswer)) }
        }
    }

    private func finish(_ result: ClaudeResult) {
        timer?.cancel()
        switch phase {
        case .warming:
            if result.isError { return fail(ColinFailure.of(result: result, rateLimit: rate, errors: "", initialized: initialized) ?? .noAnswer) }
            guard initialized else { return fail(.isolation("init")) }
            phase = .ready
            continuation.yield(.ready)
            if let pending {
                self.pending = nil
                send(pending)
            } else {
                armIdle()
            }
        case .answering:
            let cost = max(0, result.costUSD - lastCost)
            lastCost = max(lastCost, result.costUSD)
            if result.isError, !interrupted {
                return fail(ColinFailure.of(result: result, rateLimit: rate, errors: "", initialized: initialized) ?? .noAnswer)
            }
            let text = interrupted || result.text.isEmpty ? turnText : result.text
            continuation.yield(.answered(ColinTurn(text: text, costUSD: cost, interrupted: interrupted, locked: locked, tools: turnTools)))
            phase = .ready
            if locked { stop() } else { armIdle() }
        default:
            break
        }
    }

    /// Stopped for a reason that will go on: the process goes, the reason is said, nothing is tried again.
    private func fail(_ failure: ColinFailure) {
        guard let session else { return }
        reset()
        session.stop()
        continuation.yield(.failed(failure))
    }

    /// A turn, or the warm-up, silent past its limit.
    private func silent(_ mine: Int) {
        guard mine == generation, phase == .warming || phase == .answering else { return }
        fail(.noAnswer)
    }

    private func armIdle() {
        let mine = generation
        arm(idle, mine) { runner in await runner.close(mine) }
    }

    /// Ten quiet minutes: the process finishes and leaves; the next question starts a context.
    private func close(_ mine: Int) {
        guard mine == generation, phase == .ready, let session else { return }
        phase = .closing
        session.closeInput()
    }

    /// A Mac asleep does not count: the delay is read on a clock that stops with it.
    private func arm(_ delay: Duration, _ mine: Int, _ action: @escaping @Sendable (ColinRunner) async -> Void) {
        timer?.cancel()
        timer = Task { [weak self] in
            guard (try? await Task.sleep(for: delay, tolerance: nil, clock: .suspending)) != nil, let self else { return }
            await action(self)
        }
    }

    private func reset() {
        timer?.cancel()
        timer = nil
        session = nil
        generation += 1
        phase = .off
        primed = false
        pending = nil
    }
}
