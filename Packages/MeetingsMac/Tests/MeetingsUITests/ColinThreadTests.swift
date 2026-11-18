import Colin
import Domain
import Foundation
import Persistence
import PolhubDesign
import Testing
@testable import MeetingsUI

/// Colin's thread (18/11): Paul's questions and Colin's answers kept in the base, and what the app imposes on Colin
/// (a call, the Mac's sleep, the switch, the minutes after a wake). Claude Code is a script; every text is invented.
@MainActor
@Suite struct ColinThreadTests {
    nonisolated static let good = ClaudeInit(model: "claude-opus-5-5", permissionMode: "dontAsk", apiKeySource: "none", tools: ColinTool.allowed,
                                 servers: ["polhub": "connected"])

    /// Warm-up, then the answer « Trois projets. » to each question; or `answer` for each.
    nonisolated static func session(_ answer: (@Sendable (String, Int) -> [ClaudeEvent])? = nil, warmUp: [ClaudeEvent]? = nil) -> FakeSession {
        FakeSession(onSend: { text, rank in
            if rank == 1 { return warmUp ?? [.initialized(good), .result(ClaudeResult(costUSD: 0.01, text: "prêt"))] }
            return answer?(text, rank) ?? [.initialized(good), .textDelta("Trois projets."),
                                            .result(ClaudeResult(costUSD: 0.01 + 0.02 * Double(rank - 1), text: "Trois projets."))]
        })
    }

    /// A Claude Code that starts answering and never ends.
    nonisolated static let hanging: @Sendable (String, Int) -> [ClaudeEvent] = { _, _ in [.initialized(good), .assistant(text: "", tools: ["mcp__polhub__mails"], calls: [ClaudeToolCall(id: "t1", name: "mcp__polhub__mails", arguments: [:])]), .textDelta("Trois ")] }

    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var on = false
        var value: Bool { get { lock.withLock { on } } set { lock.withLock { on = newValue } } }
    }

    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var ids: Set<String> = []
        var value: Set<String> { get { lock.withLock { ids } } set { lock.withLock { ids = newValue } } }
    }

    struct World {
        let thread: ColinThread
        let database: AppDatabase
        let launcher: FakeLauncher
        let defaults: UserDefaults
    }

    /// Wednesday 18/11/2026, 10:00 in Paris.
    nonisolated static let now = Date(timeIntervalSince1970: 1_794_992_400)

    func world(_ launcher: FakeLauncher, on: Bool = true, busy: Flag = Flag(), sinceWake: TimeInterval? = 3_600, drafts: Box = Box(),
               review: [String] = [], database: AppDatabase? = nil) throws -> World {
        let database = try database ?? AppDatabase.inMemory()
        let defaults = try #require(UserDefaults(suiteName: "colin-fil-\(UUID().uuidString)"))
        defaults.set(on, forKey: Preferences.Key.colinOn)
        let work = FileManager.default.temporaryDirectory.appending(path: "colin-travail-\(UUID().uuidString)", directoryHint: .isDirectory)
        let setup = ColinSetup(binary: URL(fileURLWithPath: "/usr/bin/true"), helper: URL(fileURLWithPath: "/Applications/Polhub.app/Contents/Helpers/polhub"),
                               base: URL(fileURLWithPath: "/tmp/essai/Polhub.sqlite"), account: nil, work: work)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let thread = ColinThread(database: database, runner: ColinRunner(launcher: launcher, setup: { setup }), review: { review }, defaults: defaults,
                                 now: { Self.now }, calendar: calendar, isBusy: { busy.value }, sinceWake: { sinceWake }, settleAfterWake: 300,
                                 busyPace: .milliseconds(30), newDrafts: { drafts.value })
        return World(thread: thread, database: database, launcher: launcher, defaults: defaults)
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }

    func ask(_ thread: ColinThread, _ text: String) {
        thread.draft = text
        thread.send()
    }

    // MARK: - Colin's changes (step 3, 18/11)

    @Test func colinsChangesShowInTheThreadAndAreUndone() async throws {
        let world = try world(FakeLauncher { _, _ in Self.session() })
        let projects = ProjectStore(world.database)
        let martin = try projects.addProject(name: "Cabinet Martin", status: .priorite2, at: Self.now.addingTimeInterval(-86_400))
        let edit = KanbanEdit(projectID: martin.id, status: .priorite1, todo: "En attente retour de Claire", dueDate: nil, journal: nil,
                              reason: "Après ton mail à Claire, 9:50", source: "mail:m-1")
        try projects.edit(edit, by: .colin, at: Self.now.addingTimeInterval(-60))
        try await waitUntil { world.thread.changes.count == 1 }
        let line = try #require(world.thread.changes.first)
        #expect(line.who == .colin && line.reason == "Après ton mail à Claire, 9:50")
        world.thread.undo(line)
        #expect(world.thread.outcomes[line.id] == .undone)
        try await waitUntil { world.thread.changes.first?.undoneAt != nil }
        #expect(try projects.project(id: martin.id)?.status == .priorite2)
        #expect(try projects.project(id: martin.id)?.todo == nil)
    }

    /// Final review (18/11): what an agent changes on a card (its status, deadline, task, client, notes, an action
    /// removed) shows in the thread too, signed, with « Annuler »; what it only adds (an action, a journal entry) is
    /// counted by « Le point ».
    @Test func anAgentsChangeOfACardShowsInTheThread() async throws {
        let world = try world(FakeLauncher { _, _ in Self.session() })
        let projects = ProjectStore(world.database)
        let martin = try projects.addProject(name: "Cabinet Martin", status: .priorite2, at: Self.now.addingTimeInterval(-86_400))
        let agent = projects.signed(.agent)
        try agent.addJournal(ProjectJournalRow(projectID: martin.id, date: Self.now, title: "Maquette posée", body: "", createdAt: Self.now.addingTimeInterval(-400)))
        let current = try #require(try projects.project(id: martin.id))
        var other = current
        other.todo = "Relire la maquette"
        try projects.signed(.agent).saveChanges(from: current, to: other, at: Self.now.addingTimeInterval(-300))
        try await waitUntil { world.thread.changes.count == 1 }
        #expect(world.thread.changes.first?.who == .agent)
        #expect(world.thread.changes.first?.rows.map(\.field) == [.todo])
    }

    @Test func aQuestionIsKeptThenAnswered() async throws {
        let world = try world(FakeLauncher { _, _ in Self.session() })
        ask(world.thread, "Où on en est ?")
        try await waitUntil { world.thread.messages.last?.state == .done && world.thread.messages.count == 2 }
        #expect(world.thread.messages.map(\.author) == [.paul, .colin])
        #expect(world.thread.messages.map(\.text) == ["Où on en est ?", "Trois projets."])
        #expect(world.thread.messages.last?.costUSD.map { abs($0 - 0.03) < 1e-9 } == true)
        #expect(world.thread.draft.isEmpty && world.thread.status == .idle && world.thread.streaming.isEmpty)
    }

    @Test func theFirstQuestionCarriesThePrimer() async throws {
        let database = try AppDatabase.inMemory()
        try ColinStore(database).saveKnowledge("Écrire court.", at: Self.now)
        let world = try world(FakeLauncher { _, _ in Self.session() }, review: ["Brouillon prêt pour Claire · Cabinet Martin"], database: database)
        ask(world.thread, "Où on en est ?")
        try await waitUntil { world.thread.messages.count == 2 && world.thread.messages.last?.state == .done }
        ask(world.thread, "Et demain ?")
        try await waitUntil { world.thread.messages.count == 4 && world.thread.messages.last?.state == .done }
        let sent = try #require(world.launcher.all.first).sent
        #expect(sent.count == 3)
        #expect(sent[1].hasPrefix("Le contexte de Polhub") && sent[1].contains("Écrire court.") && sent[1].contains("Brouillon prêt pour Claire"))
        #expect(sent[1].hasSuffix("\n\nOù on en est ?") && sent[2] == "Et demain ?")
    }

    @Test func aCallStopsTheTurnAndKillsClaude() async throws {
        let busy = Flag()
        let world = try world(FakeLauncher { _, _ in Self.session(Self.hanging) }, busy: busy)
        ask(world.thread, "Où on en est ?")
        try await waitUntil { world.thread.streaming == "Trois " }
        #expect(world.thread.status == .working("Colin lit tes mails…"))
        busy.value = true
        world.thread.meetingBegan()
        try await waitUntil { world.launcher.all.first?.stopped == true && world.thread.messages.last?.state == .interrupted }
        #expect(world.thread.messages.last?.text == "Trois \n\nArrêté : ton call commence.")
        #expect(world.thread.status == .waitingCall && !world.thread.isAnswering)
        busy.value = false
        try await waitUntil { world.thread.status == .idle }
    }

    @Test func duringACallTheBarWaits() async throws {
        let busy = Flag()
        busy.value = true
        let world = try world(FakeLauncher { _, _ in Self.session() }, busy: busy)
        ask(world.thread, "Où on en est ?")
        try await waitUntil { world.thread.status == .waitingCall }
        #expect(world.launcher.started.isEmpty && world.thread.messages.isEmpty)
        #expect(world.thread.draft == "Où on en est ?")
        busy.value = false
        try await waitUntil { world.thread.status == .idle }
    }

    @Test func turningColinOffKillsAndSaysSo() async throws {
        let world = try world(FakeLauncher { _, _ in Self.session(Self.hanging) })
        ask(world.thread, "Où on en est ?")
        try await waitUntil { world.thread.streaming == "Trois " }
        world.thread.turnOff()
        try await waitUntil { world.launcher.all.first?.stopped == true && world.thread.messages.last?.state == .interrupted }
        #expect(!Preferences(defaults: world.defaults).colinOn && world.thread.status == .off)
        // Off, a question goes nowhere.
        ask(world.thread, "Encore ?")
        try await Task.sleep(for: .milliseconds(50))
        #expect(world.launcher.started.count == 1 && world.thread.messages.count == 2)
        world.thread.turnOn()
        #expect(Preferences(defaults: world.defaults).colinOn && world.thread.status == .idle)
    }

    @Test func sleepStops() async throws {
        let world = try world(FakeLauncher { _, _ in Self.session(Self.hanging) })
        ask(world.thread, "Où on en est ?")
        try await waitUntil { world.thread.streaming == "Trois " }
        world.thread.macWillSleep()
        try await waitUntil { world.launcher.all.first?.stopped == true && world.thread.messages.last?.state == .interrupted }
        #expect(world.thread.messages.last?.text == "Trois \n\nArrêté : le Mac s'endort.")
    }

    @Test func fiveMinutesAfterWakeTheQuestionWaitsThenGoes() async throws {
        let world = try world(FakeLauncher { _, _ in Self.session() }, sinceWake: 299.5)
        ask(world.thread, "Où on en est ?")
        try await waitUntil { world.thread.status == .settling && world.thread.messages.map(\.text) == ["Où on en est ?"] }
        #expect(world.launcher.started.isEmpty)
        try await waitUntil { world.thread.messages.count == 2 && world.thread.messages.last?.state == .done }
    }

    /// A call, the Mac's sleep or the switch during the wait after a wake: the question does not leave.
    @Test func aCallDuringTheWakeWaitStopsTheQuestion() async throws {
        for gesture in ["call", "sleep", "off"] {
            let busy = Flag()
            let world = try world(FakeLauncher { _, _ in Self.session() }, busy: busy, sinceWake: 299.7)
            ask(world.thread, "Où on en est ?")
            try await waitUntil { world.thread.status == .settling }
            switch gesture {
            case "call": busy.value = true; world.thread.meetingBegan()
            case "sleep": world.thread.macWillSleep()
            default: world.thread.turnOff()
            }
            try await Task.sleep(for: .milliseconds(600))
            #expect(world.launcher.started.isEmpty, "\(gesture)")
            #expect(!world.thread.isAnswering, "\(gesture)")
        }
    }

    @Test func afterSleepNothingSaysColinWorks() async throws {
        let world = try world(FakeLauncher { _, _ in Self.session(Self.hanging) })
        ask(world.thread, "Où on en est ?")
        try await waitUntil { world.thread.streaming == "Trois " }
        world.thread.macWillSleep()
        try await waitUntil { world.thread.messages.last?.state == .interrupted }
        #expect(world.thread.status == .idle)
    }

    /// Off, Colin stays off when a call begins and ends: « Allumer Colin » stays in the bar's place.
    @Test func aCallWithColinOffLeavesHimOff() async throws {
        let busy = Flag()
        let world = try world(FakeLauncher { _, _ in Self.session() }, on: false, busy: busy)
        busy.value = true
        world.thread.meetingBegan()
        #expect(world.thread.status == .off)
        busy.value = false
        try await Task.sleep(for: .milliseconds(100))
        #expect(world.thread.status == .off && !world.thread.isOn)
    }

    /// What Paul types in « Ce que Colin sait » is kept a second later, or at once when he leaves the page.
    @Test func whatColinKnowsIsKeptWhenPaulLeaves() async throws {
        let world = try world(FakeLauncher { _, _ in Self.session() })
        world.thread.editKnowledge("Écrire court.")
        #expect(try ColinStore(world.database).knowledge() == "")
        world.thread.flushKnowledge()
        #expect(try ColinStore(world.database).knowledge() == "Écrire court.")
        world.thread.editKnowledge("Écrire court, à mon ton.")
        try await waitUntil { (try? ColinStore(world.database).knowledge()) == "Écrire court, à mon ton." }
    }

    @Test func aLineIsKeptOnce() throws {
        let world = try world(FakeLauncher { _, _ in Self.session() })
        try world.thread.keep("Marc préfère WhatsApp.")
        try world.thread.keep("Marc préfère WhatsApp.")
        #expect(try ColinStore(world.database).knowledge() == "Marc préfère WhatsApp.")
        #expect(world.thread.knows("Marc préfère WhatsApp."))
    }

    @Test func notConnectedIsSaidOnce() async throws {
        let world = try world(FakeLauncher { _, _ in
            Self.session(warmUp: [.initialized(Self.good), .result(ClaudeResult(isError: true, text: "Not logged in · Please run /login"))])
        })
        ask(world.thread, "Où on en est ?")
        try await waitUntil { world.thread.status == .broken("Claude Code n'est pas connecté sur ton compte.") && world.thread.messages.last?.state == .failed }
        #expect(!world.thread.isAnswering)
        try await Task.sleep(for: .milliseconds(100))
        #expect(world.launcher.started.count == 1)
    }

    @Test func theDraftsOfTheTurnAreKept() async throws {
        let drafts = Box()
        drafts.value = ["ancien"]
        let world = try world(FakeLauncher { _, _ in
            Self.session { _, rank in
                drafts.value = ["ancien", "nouveau"]
                return [.initialized(Self.good), .result(ClaudeResult(costUSD: 0.05, text: "Brouillon prêt pour Claire."))]
            }
        }, drafts: drafts)
        ask(world.thread, "Prépare la réponse à Claire")
        try await waitUntil { world.thread.messages.last?.state == .done && world.thread.messages.count == 2 }
        #expect(world.thread.messages.last?.drafts == ["nouveau"])
        #expect(world.thread.answeredRecently)
    }

    @Test func keepAppendsALineToWhatColinKnows() throws {
        let world = try world(FakeLauncher { _, _ in Self.session() })
        try world.thread.keep("Marc préfère WhatsApp.")
        #expect(try ColinStore(world.database).knowledge() == "Marc préfère WhatsApp.")
        try world.thread.keep("Claire répond le matin.")
        #expect(try ColinStore(world.database).knowledge() == "Marc préfère WhatsApp.\nClaire répond le matin.")
        #expect(world.thread.knowledge == "Marc préfère WhatsApp.\nClaire répond le matin.")
    }

    @Test func aLaunchAfterACrashClosesTheUnfinishedAnswer() async throws {
        let database = try AppDatabase.inMemory()
        try ColinStore(database).add(ColinMessageRow(author: .colin, text: "À moi", state: .answering, createdAt: Self.now))
        let world = try world(FakeLauncher { _, _ in Self.session() }, database: database)
        try await waitUntil { world.thread.messages.count == 1 }
        #expect(world.thread.messages.first?.state == .interrupted)
    }

    @Test func theWorkingPhraseFollowsTheTool() {
        #expect(ColinThread.phrase(for: nil) == "Colin réfléchit…")
        #expect(ColinThread.phrase(for: "mcp__polhub__projets") == "Colin regarde tes projets…")
        #expect(ColinThread.phrase(for: "mcp__polhub__contexte") == "Colin regarde tes projets…")
        #expect(ColinThread.phrase(for: "mcp__polhub__mail") == "Colin lit tes mails…")
        #expect(ColinThread.phrase(for: "mcp__polhub__reunion") == "Colin lit tes réunions…")
        #expect(ColinThread.phrase(for: "mcp__polhub__projet") == "Colin met à jour le projet…")
        #expect(ColinThread.phrase(for: "mcp__polhub__fait") == "Colin met à jour le projet…")
        #expect(ColinThread.phrase(for: "mcp__polhub__agenda") == "Colin regarde ton agenda…")
        #expect(ColinThread.phrase(for: "mcp__polhub__brouillon") == "Colin écrit le brouillon…")
    }

    @Test func eachFailureIsSaidPlainly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let reset = Date(timeIntervalSince1970: 1_795_015_200)   // 18/11/2026, 16:20 in Paris
        #expect(ColinThread.sentence(.limit(resetsAt: reset), calendar: calendar) == "Limite atteinte · reprend à 16:20")
        #expect(ColinThread.sentence(.limit(resetsAt: nil), calendar: calendar) == "Limite atteinte.")
        #expect(ColinThread.sentence(.missing, calendar: calendar) == "Claude Code est introuvable sur ce Mac.")
        #expect(ColinThread.sentence(.isolation("outils"), calendar: calendar) == "Claude Code a chargé plus que ce que Polhub lui demande : Colin s'est arrêté.")
    }
}
