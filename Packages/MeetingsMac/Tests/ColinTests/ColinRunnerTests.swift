import Domain
import Persistence
import Foundation
import Testing
@testable import Colin

/// The engine of Colin's bar (18/11): one warm Claude Code, checked at each `init`, which answers Paul's questions
/// and says what each turn cost. Every text here is invented.
@Suite struct ColinRunnerTests {
    static let good = ColinInitCheckTests.good
    static let primer = "AMORCE : ce que Colin sait, les derniers échanges."

    /// The warm-up's answer, then `answer` for each question (its rank among the messages sent, from 2).
    static func session(_ answer: @escaping @Sendable (String, Int) -> [ClaudeEvent] = Self.answer, warmUp: [ClaudeEvent]? = nil,
                        onInterrupt: @escaping @Sendable (String) -> [ClaudeEvent] = { _ in [] }) -> FakeSession {
        FakeSession(onSend: { text, rank in
            rank == 1 ? (warmUp ?? [.initialized(good), .result(ClaudeResult(costUSD: 0.01, text: "prêt"))]) : answer(text, rank)
        }, onInterrupt: onInterrupt)
    }

    /// Each question costs 0.02 more than the one before, as Claude Code counts its cost: from the process's start.
    static func answer(_ text: String, _ rank: Int) -> [ClaudeEvent] {
        [.initialized(good), .textDelta("Trois "), .toolStarted(id: "t1", name: "mcp__polhub__mail"),
         .assistant(text: "", tools: ["mcp__polhub__mail"], calls: [ClaudeToolCall(id: "t1", name: "mcp__polhub__mail", arguments: ["quel": "fil-1"])]),
         .toolResult(isError: false, text: "", outcomes: [ClaudeToolOutcome(id: "t1", isError: false)]),
         .textDelta("projets."), .result(ClaudeResult(durationMs: 900, costUSD: 0.01 + 0.02 * Double(rank - 1), text: "Trois projets."))]
    }

    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [ColinRunner.Event] = []
        var events: [ColinRunner.Event] { lock.withLock { seen } }
        func add(_ event: ColinRunner.Event) { lock.withLock { seen.append(event) } }
        var answers: [ColinTurn] { events.compactMap { if case .answered(let turn) = $0 { turn } else { nil } } }
        var failures: [ColinFailure] { events.compactMap { if case .failed(let failure) = $0 { failure } else { nil } } }
    }

    func runner(_ launcher: FakeLauncher, idle: Duration = .seconds(600), turnLimit: Duration = .seconds(30)) -> (ColinRunner, Recorder) {
        let work = FileManager.default.temporaryDirectory.appending(path: "colin-travail-\(UUID().uuidString)", directoryHint: .isDirectory)
        let setup = ColinSetup(binary: URL(fileURLWithPath: "/usr/bin/true"), helper: URL(fileURLWithPath: "/Applications/Polhub.app/Contents/Helpers/polhub"),
                               base: URL(fileURLWithPath: "/tmp/essai/Polhub.sqlite"), account: nil, work: work)
        let runner = ColinRunner(launcher: launcher, setup: { setup }, idle: idle, turnLimit: turnLimit)
        let recorder = Recorder()
        Task { for await event in runner.events { recorder.add(event) } }
        return (runner, recorder)
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }

    @Test func aQuestionStreamsThenAnswers() async throws {
        let launcher = FakeLauncher { _, _ in Self.session() }
        let (runner, seen) = runner(launcher)
        await runner.ask("Où on en est ?", primer: Self.primer)
        try await waitUntil { !seen.answers.isEmpty }
        // The Accueil's pass (18/11): each action as a step — begun where the text stood, its arguments, its end — and
        // the turn says its steps and how long it worked.
        let started = ColinStep(id: "t1", tool: "mail", arguments: [:], state: .running, position: 6)
        var called = started
        called.arguments = ["quel": "fil-1"]
        var done = called
        done.state = .done
        #expect(seen.events == [.starting, .ready, .delta("Trois "), .step(started), .step(called), .step(done), .delta("projets."),
                                .answered(ColinTurn(text: "Trois projets.", costUSD: 0.03, interrupted: false, locked: false, tools: ["mcp__polhub__mail"],
                                                    steps: [done], durationMs: 900))])
    }

    @Test func thePrimerGoesWithTheFirstQuestionOnly() async throws {
        let launcher = FakeLauncher { _, _ in Self.session() }
        let (runner, seen) = runner(launcher)
        #expect(await runner.fresh)
        await runner.ask("Où on en est ?", primer: Self.primer)
        try await waitUntil { seen.answers.count == 1 }
        #expect(await !runner.fresh)
        await runner.ask("Et demain ?", primer: Self.primer)
        try await waitUntil { seen.answers.count == 2 }
        let sent = try #require(launcher.all.first).sent
        #expect(sent == [ColinTexts.warmUp, "\(Self.primer)\n\nOù on en est ?", "Et demain ?"])
    }

    @Test func theTurnCostIsWhatThisTurnAdded() async throws {
        let launcher = FakeLauncher { _, _ in Self.session() }
        let (runner, seen) = runner(launcher)
        await runner.ask("Un", primer: "")
        try await waitUntil { seen.answers.count == 1 }
        await runner.ask("Deux", primer: "")
        try await waitUntil { seen.answers.count == 2 }
        // The first answer carries the warm-up's cost too.
        let costs = seen.answers.compactMap(\.costUSD)
        #expect(costs.count == 2 && abs(costs[0] - 0.03) < 1e-9 && abs(costs[1] - 0.02) < 1e-9)
    }

    @Test func whatColinKnowsNeverTravelsInTheArguments() async throws {
        let launcher = FakeLauncher { _, _ in Self.session() }
        let (runner, seen) = runner(launcher)
        await runner.ask("Où on en est ?", primer: "Ce que Colin sait : un secret de Paul")
        try await waitUntil { !seen.answers.isEmpty }
        let command = try #require(launcher.started.first)
        #expect(command.model == "opus" && command.prompt == nil && command.systemPrompt == ColinTexts.system)
        #expect(command.allowedTools == ColinTool.allowed && command.configDirectory == nil)
        #expect(command.mcpConfig?.contains("--colin") == true)
        #expect(!command.arguments.joined(separator: " ").contains("secret"))
        #expect(!ColinTexts.system.contains("Paul"))
    }

    @Test func aWrongInitSendsNothingOfPaul() async throws {
        var changed = Self.good
        changed.tools.append("mcp__polhub__journal")
        let wrong = changed
        let launcher = FakeLauncher { _, _ in Self.session(warmUp: [.initialized(wrong), .result(ClaudeResult(text: "prêt"))]) }
        let (runner, seen) = runner(launcher)
        await runner.ask("Un secret de Paul", primer: Self.primer)
        try await waitUntil { !seen.failures.isEmpty }
        #expect(seen.failures == [.isolation("outils")])
        let session = try #require(launcher.all.first)
        try await waitUntil { session.stopped }
        #expect(session.sent == [ColinTexts.warmUp])
        #expect(await runner.fresh)
    }

    @Test func everyInitIsChecked() async throws {
        var changed = Self.good
        changed.plugins = 1
        let wrong = changed
        let launcher = FakeLauncher { _, _ in
            Self.session { text, rank in rank == 2 ? Self.answer(text, rank) : [.initialized(wrong), .textDelta("Je ")] }
        }
        let (runner, seen) = runner(launcher)
        await runner.ask("Un", primer: "")
        try await waitUntil { seen.answers.count == 1 }
        await runner.ask("Deux", primer: "")
        try await waitUntil { !seen.failures.isEmpty }
        #expect(seen.failures == [.isolation("plugins")])
        #expect(launcher.all.first?.stopped == true)
    }

    @Test func aHookStopsItToo() async throws {
        let launcher = FakeLauncher { _, _ in Self.session(warmUp: [.other("system/hook_started"), .initialized(Self.good), .result(ClaudeResult(text: "prêt"))]) }
        let (runner, seen) = runner(launcher)
        await runner.warm()
        try await waitUntil { !seen.failures.isEmpty }
        #expect(seen.failures == [.isolation("hooks")])
    }

    @Test func aLockRefusalMakesTheNextQuestionFresh() async throws {
        let launcher = FakeLauncher { _, _ in
            Self.session { _, rank in
                rank == 2 ? [.initialized(Self.good), .assistant(text: "", tools: ["mcp__polhub__brouillon"]),
                             .toolResult(isError: true, text: "\(ColinTool.lockMark) : après ce qu'il a lu…"),
                             .result(ClaudeResult(costUSD: 0.03, text: "Je ne peux pas l'écrire ici."))]
                    : Self.answer("", rank)
            }
        }
        let (runner, seen) = runner(launcher)
        await runner.ask("Écris à Claire", primer: Self.primer)
        try await waitUntil { seen.answers.count == 1 }
        #expect(seen.answers.first?.locked == true)
        try await waitUntil { launcher.all.first?.stopped == true }
        #expect(await runner.fresh)
        await runner.ask("Réessaie", primer: Self.primer)
        try await waitUntil { seen.answers.count == 2 }
        #expect(launcher.all.count == 2)
        #expect(launcher.all.last?.sent == [ColinTexts.warmUp, "\(Self.primer)\n\nRéessaie"])
    }

    @Test func tenQuietMinutesCloseTheProcess() async throws {
        let launcher = FakeLauncher { _, _ in Self.session() }
        let (runner, seen) = runner(launcher, idle: .milliseconds(100))
        await runner.ask("Un", primer: "")
        try await waitUntil { seen.answers.count == 1 }
        try await waitUntil { launcher.all.first?.isOver == true }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await runner.fresh)
        #expect(seen.failures.isEmpty)
        #expect(launcher.all.first?.stopped == false)
    }

    @Test func notConnectedStopsWithoutRetry() async throws {
        let launcher = FakeLauncher { _, _ in
            Self.session(warmUp: [.initialized(Self.good), .result(ClaudeResult(isError: true, text: "Not logged in · Please run /login"))])
        }
        let (runner, seen) = runner(launcher)
        await runner.ask("Un", primer: "")
        try await waitUntil { !seen.failures.isEmpty }
        #expect(seen.failures == [.notConnected])
        try await Task.sleep(for: .milliseconds(150))
        #expect(launcher.started.count == 1 && seen.failures.count == 1)
    }

    @Test func aLimitSaysWhenItResets() async throws {
        let reset = Date(timeIntervalSince1970: 1_795_000_000)
        let launcher = FakeLauncher { _, _ in
            Self.session { _, _ in
                [.initialized(Self.good), .rateLimit(ClaudeRateLimit(status: "rejected", resetsAt: reset)),
                 .result(ClaudeResult(isError: true, apiErrorStatus: 429, text: "limite"))]
            }
        }
        let (runner, seen) = runner(launcher)
        await runner.ask("Un", primer: "")
        try await waitUntil { !seen.failures.isEmpty }
        #expect(seen.failures == [.limit(resetsAt: reset)])
    }

    @Test func theStopArrowEndsTheTurnOnly() async throws {
        let launcher = FakeLauncher { _, _ in
            Self.session({ _, _ in [.initialized(Self.good), .textDelta("Trois ")] }, onInterrupt: { id in
                [.controlResponse(requestID: id, success: true), .other("user/interruption"),
                 .result(ClaudeResult(subtype: "error_during_execution", isError: true, costUSD: 0.02))]
            })
        }
        let (runner, seen) = runner(launcher)
        await runner.ask("Un", primer: "")
        try await waitUntil { seen.events.contains(.delta("Trois ")) }
        await runner.interrupt()
        try await waitUntil { seen.answers.count == 1 }
        #expect(seen.answers.first?.interrupted == true && seen.answers.first?.text == "Trois ")
        #expect(seen.failures.isEmpty)
        #expect(launcher.all.first?.stopped == false)
        #expect(await !runner.fresh)
    }

    /// A turn stopped while a tool runs: nothing stays « en cours »; stopped by Paul is not a failure.
    @Test func aTurnEndsItsSteps() async throws {
        let launcher = FakeLauncher { _, _ in
            Self.session({ _, _ in [.initialized(Self.good), .textDelta("Je "), .toolStarted(id: "t9", name: "mcp__polhub__mails")] }, onInterrupt: { id in
                [.controlResponse(requestID: id, success: true), .other("user/interruption"),
                 .result(ClaudeResult(subtype: "error_during_execution", isError: true, costUSD: 0.02))]
            })
        }
        let (runner, seen) = runner(launcher)
        await runner.ask("Un", primer: "")
        try await waitUntil { seen.events.contains { if case .step = $0 { true } else { false } } }
        await runner.interrupt()
        try await waitUntil { seen.answers.count == 1 }
        #expect(seen.answers.first?.steps.map(\.state) == [.done])
        #expect(seen.answers.first?.durationMs == nil)
    }

    @Test func stopKillsAtOnce() async throws {
        let launcher = FakeLauncher { _, _ in Self.session { _, _ in [.initialized(Self.good), .textDelta("Trois ")] } }
        let (runner, seen) = runner(launcher)
        await runner.ask("Un", primer: "")
        try await waitUntil { seen.events.contains(.delta("Trois ")) }
        await runner.stop()
        #expect(launcher.all.first?.stopped == true)
        #expect(await runner.fresh)
        try await waitUntil { launcher.all.first?.isOver == true }
        try await Task.sleep(for: .milliseconds(50))
        #expect(seen.failures.isEmpty && seen.answers.isEmpty)
    }

    @Test func aSilentTurnFailsAfterItsLimit() async throws {
        let launcher = FakeLauncher { _, _ in Self.session { _, _ in [] } }
        let (runner, seen) = runner(launcher, turnLimit: .milliseconds(150))
        await runner.ask("Un", primer: "")
        try await waitUntil { !seen.failures.isEmpty }
        #expect(seen.failures == [.noAnswer])
        #expect(launcher.all.first?.stopped == true)
    }

    @Test func aLaunchThatCannotStartSaysSo() async throws {
        let launcher = FakeLauncher(failing: [0]) { _, _ in Self.session() }
        let (runner, seen) = runner(launcher)
        await runner.ask("Un", primer: "")
        try await waitUntil { !seen.failures.isEmpty }
        #expect(seen.failures == [.launch])
    }
}
