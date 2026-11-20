import Colin
import Combine
import Foundation
import GRDB
import Persistence
import PolhubDesign

/// Colin's one thread (18/11): Paul's questions and Colin's answers, kept in the base, and what the app imposes on
/// Colin. During a call or a transcription the bar waits; a call that begins, the Mac's sleep and the switch stop
/// an answer under way; in the minutes after a wake a question waits before Claude Code is launched. Created once by
/// the app, it outlives the Accueil: what Paul types in the bar is kept here.
@MainActor
public final class ColinThread: ObservableObject {
    public enum Status: Equatable, Sendable {
        case off
        /// « Colin attend la fin de ta visio ».
        case waitingCall
        /// The Mac woke a moment ago: the question waits.
        case settling
        case idle
        case starting
        /// What Colin is doing, said by his last tool.
        case working(String)
        /// Why he cannot answer.
        case broken(String)
    }

    @Published public private(set) var messages: [ColinMessageRow] = []
    /// What Colin changed on the projects, the last fortnight (step 3, 18/11), and what an agent changed on a card,
    /// each with « Annuler ».
    @Published public private(set) var changes: [ProjectChangeLine] = []
    /// What Colin is doing in the answer under way, in order (the Accueil's pass, 18/11).
    @Published public private(set) var liveSteps: [ColinStep] = []
    /// The answer under way as the screen shows it: whole words, at a steady pace (`StreamPacer`).
    @Published public private(set) var visible = ""
    private var pacer = StreamPacer()
    private var pacing: Task<Void, Never>?
    /// What « Annuler » did, by line.
    @Published public private(set) var outcomes: [String: UndoOutcome] = [:]
    @Published public private(set) var status: Status = .off
    /// The answer as it is written.
    @Published public private(set) var streaming = ""
    /// The text of the bar.
    @Published public var draft = ""
    /// « Ce que Colin sait ».
    @Published public private(set) var knowledge = ""

    private let store: ColinStore
    private let runner: ColinRunner?
    private let review: @MainActor () -> [String]
    private let defaults: UserDefaults
    private let now: () -> Date
    private let calendar: Calendar
    private let isBusy: @MainActor () async -> Bool
    private let sinceWake: () -> TimeInterval?
    private let settleAfterWake: TimeInterval
    private let busyPace: Duration
    private let newDrafts: @MainActor () -> Set<String>
    private var observation: AnyDatabaseCancellable?
    private var changesObservation: AnyDatabaseCancellable?
    private let changeStore: ProjectChanges
    private let database: AppDatabase
    /// What each step was about, once said (a thread's subject and project are read once).
    private var subjects: [String: StepSubject] = [:]
    private var rules: (read: Date, rules: MailFilingRules)?
    /// Colin's changes are shown this far back.
    static let changesShown: TimeInterval = 14 * 86_400
    private var cancellables: Set<AnyCancellable> = []
    private var limit = 100
    /// The answer under way, and the drafts there were before it.
    private var answer: ColinMessageRow?
    private var draftsBefore: Set<String> = []
    /// A question on its way (the call checked, the wake waited).
    private var asking = false
    private var lastAnswerAt: Date?
    private var watcher: Task<Void, Never>?
    /// Counts what stopped Colin (a call, the Mac's sleep, the switch): a question waiting since before does not leave.
    private var epoch = 0
    /// « Ce que Colin sait » as Paul types it, kept a second after his last keystroke.
    private var pendingKnowledge: String?
    private var knowledgeSave: Task<Void, Never>?

    /// `runner`: `nil` shows the thread and asks nothing (captures, tests of the screens). `isBusy`: a call recorded
    /// or transcribed. `sinceWake`: the seconds since the Mac started or woke. `newDrafts`: the drafts the agents
    /// prepared, by identifier.
    public init(database: AppDatabase, runner: ColinRunner?, review: @escaping @MainActor () -> [String] = { [] }, defaults: UserDefaults = .standard,
                now: @escaping () -> Date = Date.init, calendar: Calendar = .current, isBusy: @escaping @MainActor () async -> Bool = { false },
                sinceWake: @escaping () -> TimeInterval? = { nil }, settleAfterWake: TimeInterval = 300, busyPace: Duration = .seconds(15),
                newDrafts: @escaping @MainActor () -> Set<String> = { [] }) {
        store = ColinStore(database)
        changeStore = ProjectChanges(database)
        self.database = database
        self.runner = runner
        self.review = review
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        self.isBusy = isBusy
        self.sinceWake = sinceWake
        self.settleAfterWake = settleAfterWake
        self.busyPace = busyPace
        self.newDrafts = newDrafts
        try? store.closeUnfinished()
        knowledge = (try? store.knowledge()) ?? ""
        status = isOn ? .idle : .off
        observe()
        if let runner {
            Task { [weak self] in
                for await event in runner.events { self?.received(event) }
            }
        }
        // The switch, from Réglages as from the Accueil.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: defaults).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.switched() }.store(in: &cancellables)
    }

    public var isOn: Bool { Preferences(defaults: defaults).colinOn }

    /// A question asked or an answer under way: an update of the app waits.
    public var isAnswering: Bool { answer != nil || asking }

    /// A draft that appears now was asked in the bar: it does not ring.
    public var answeredRecently: Bool {
        isAnswering || lastAnswerAt.map { now().timeIntervalSince($0) < 30 } ?? false
    }

    // MARK: - Paul's gestures

    public func send() {
        submit(draft, clearing: true)
    }

    /// A question to Colin; `clearing`: it came from the bar, which empties.
    private func submit(_ text: String, clearing: Bool) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, isOn, runner != nil, !isAnswering else { return }
        asking = true
        Task { await begin(question, clearing: clearing) }
    }

    /// The stop arrow: the answer ends with what came.
    public func stop() {
        guard answer != nil, let runner else { return }
        Task { await runner.interrupt() }
    }

    public func turnOn() {
        defaults.set(true, forKey: Preferences.Key.colinOn)
        switched()
    }

    public func turnOff() {
        defaults.set(false, forKey: Preferences.Key.colinOn)
        switched()
    }

    /// The bar has the focus: Claude Code gets ready while Paul types.
    public func focused() {
        guard isOn, !isAnswering, let runner else { return }
        if let since = sinceWake(), since < settleAfterWake { return }
        Task {
            guard await !isBusy() else { return }
            await runner.warm()
        }
    }

    /// « Garder »: the line joins what Colin knows, once.
    public func keep(_ line: String) throws {
        flushKnowledge()
        guard !knows(line) else { return }
        let current = knowledge.trimmingCharacters(in: .whitespacesAndNewlines)
        try saveKnowledge(current.isEmpty ? line : current + "\n" + line)
    }

    /// Whether this line is already in what Colin knows.
    public func knows(_ line: String) -> Bool {
        let wanted = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return knowledge.components(separatedBy: "\n").contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == wanted }
    }

    /// Réglages › Colin, as Paul types: kept a second after his last keystroke.
    public func editKnowledge(_ text: String) {
        pendingKnowledge = text
        knowledgeSave?.cancel()
        knowledgeSave = Task { [weak self] in
            guard (try? await Task.sleep(for: .seconds(1))) != nil else { return }
            self?.flushKnowledge()
        }
    }

    /// What Paul typed and is not kept yet, kept now: he leaves the page.
    public func flushKnowledge() {
        knowledgeSave?.cancel()
        knowledgeSave = nil
        guard let text = pendingKnowledge else { return }
        pendingKnowledge = nil
        try? saveKnowledge(text)
    }

    /// Réglages › Colin: « Ce que Colin sait », as Paul writes it.
    public func saveKnowledge(_ text: String) throws {
        try store.saveKnowledge(text, at: now())
        knowledge = text
    }

    /// Colin's answers this week (from Monday), and what they cost.
    public func week() -> (count: Int, costUSD: Double) {
        var monday = calendar
        monday.firstWeekday = 2
        let start = monday.dateInterval(of: .weekOfYear, for: now())?.start ?? now().addingTimeInterval(-7 * 86_400)
        return (try? store.answers(since: start)) ?? (0, 0)
    }

    /// The messages before those shown.
    public func loadEarlier() {
        limit += 100
        observe()
    }

    // MARK: - What the app tells

    public func meetingBegan() {
        cut(.call)
        guard isOn else { return }
        status = .waitingCall
        watchCall()
    }

    public func macWillSleep() {
        cut(.sleep)
    }

    // MARK: - Pieces

    private func begin(_ question: String, clearing: Bool) async {
        defer { asking = false }
        if await isBusy() {
            status = .waitingCall
            watchCall()
            return
        }
        guard isOn, let runner else { return }
        // Before the question joins the thread: it is said once, after the primer.
        let primer = ColinPrimer.text(knowledge: (try? store.knowledge()) ?? "", exchanges: (try? store.exchanges(last: 16)) ?? [], review: review(),
                                      now: now(), calendar: calendar)
        // The bar empties once the question is asked — not during a call, where it waits in the bar.
        if clearing { draft = "" }
        let asked = ColinMessageRow(author: .paul, text: question, createdAt: now())
        try? store.add(asked)
        if let since = sinceWake(), since < settleAfterWake {
            status = .settling
            let before = epoch
            try? await Task.sleep(for: .seconds(settleAfterWake - since))
            // A call, the Mac's sleep or the switch meanwhile: the question stays, unanswered.
            guard isOn, epoch == before else { return }
            if await isBusy() {
                status = .waitingCall
                watchCall()
                return
            }
        }
        let row = ColinMessageRow(author: .colin, text: "", state: .answering, createdAt: asked.createdAt.addingTimeInterval(0.001))
        try? store.add(row)
        answer = row
        draftsBefore = newDrafts()
        streaming = ""
        liveSteps = []
        endPacing()
        status = .working(Self.phrase(for: nil))
        await runner.ask(question, primer: primer)
    }

    private func received(_ event: ColinRunner.Event) {
        switch event {
        case .starting:
            if answer != nil, streaming.isEmpty { status = .working(Self.phrase(for: nil)) }
        case .ready:
            break
        case .delta(let text):
            guard answer != nil else { return }
            streaming += text
            pacer.push(text)
            pace()
        case .step(let step):
            guard answer != nil else { return }
            if let index = liveSteps.firstIndex(where: { $0.id == step.id }) {
                liveSteps[index] = step
            } else {
                // An action begins: the text before it is whole, its last word too (final review, 18/11).
                visible = pacer.flush()
                liveSteps.append(step)
            }
            status = .working(Self.phrase(for: step.tool))
        case .answered(let turn):
            guard var row = answer else { return }
            row.text = turn.text
            row.state = turn.interrupted ? .interrupted : .done
            row.costUSD = turn.costUSD
            row.drafts = newDrafts().subtracting(draftsBefore).sorted()
            row.steps = turn.steps
            row.durationMs = turn.durationMs
            try? store.update(row)
            shown(row)
            answer = nil
            streaming = ""
            liveSteps = []
            endPacing()
            lastAnswerAt = now()
            status = isOn ? .idle : .off
        case .failed(let failure):
            if var row = answer {
                row.text = streaming
                row.state = .failed
                row.steps = Self.ended(liveSteps, failed: true)
                try? store.update(row)
                shown(row)
            }
            answer = nil
            streaming = ""
            liveSteps = []
            endPacing()
            status = .broken(Self.sentence(failure, calendar: calendar))
        }
    }

    /// Claude Code goes now; an answer under way keeps what came, and why it stopped, in the words the base keeps.
    private func cut(_ stop: ColinStop) {
        epoch += 1
        guard let runner else { return }
        Task { await runner.stop() }
        if case .working = status { status = isOn ? .idle : .off }
        if status == .starting || status == .settling { status = isOn ? .idle : .off }
        guard var row = answer else { return }
        row.text = streaming.isEmpty ? stop.stored : streaming + "\n\n" + stop.stored
        row.state = .interrupted
        row.steps = Self.ended(liveSteps)
        liveSteps = []
        try? store.update(row)
        shown(row)
        answer = nil
        streaming = ""
        endPacing()
    }

    private func switched() {
        if isOn {
            if status == .off { status = .idle }
        } else if status != .off {
            cut(.off)
            status = .off
        }
    }

    /// While a call or its transcription lasts, the bar waits; looked at again every few seconds.
    private func watchCall() {
        guard watcher == nil else { return }
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: busyPace)
                if await !isBusy() { break }
            }
            guard let self else { return }
            if status == .waitingCall { status = isOn ? .idle : .off }
            watcher = nil
        }
    }

    private func observe() {
        observation = store.observeMessages(limit: limit) { [weak self] rows in self?.messages = rows }
        if changesObservation == nil {
            changesObservation = changeStore.observeLines(since: now().addingTimeInterval(-Self.changesShown), authors: [.colin, .agent]) { [weak self] lines in
                self?.changes = Self.shown(lines)
            }
        }
    }

    /// What the thread shows (final review, 18/11): all of Colin's changes; of an agent's, those that change a card —
    /// its status, deadline, task, client, notes, an action removed. What an agent only adds (an action, a line in the
    /// journal) is counted by « Le point », behind « Voir ».
    nonisolated static func shown(_ lines: [ProjectChangeLine]) -> [ProjectChangeLine] {
        let card: Set<ProjectChangeField> = [.status, .dueDate, .todo, .client, .notes, .actionRemoved]
        return lines.filter { $0.who == .colin || $0.rows.contains { card.contains($0.field) } }
    }

    /// What a step was about, as Polhub's own base says it (the Accueil's pass, 18/11): a thread by its subject and
    /// its person, and its project; else the project named. Never what the tool gave back.
    public func subject(_ step: ColinStep) -> StepSubject {
        if let known = subjects[step.id] { return known }
        var said = StepSubject(title: nil, project: step.arguments["projet"])
        if step.tool == "mail", let which = step.arguments["quel"], let thread = try? MailStore(database).thread(matching: which) {
            let person = thread.senders.last.map { ReviewRules.short($0.name ?? $0.email) }
            said.title = [thread.subject.isEmpty ? nil : thread.subject, person].compactMap { $0 }.joined(separator: " · ")
            if rules.map({ now().timeIntervalSince($0.read) > 300 }) ?? true, let read = try? MailStore(database).filingRules() { rules = (now(), read) }
            if let project = rules?.rules.filing(of: thread)?.filing.projectID { said.project = (try? ProjectStore(database).project(id: project))?.name }
        }
        // Kept once its arguments are known.
        if !step.arguments.isEmpty { subjects[step.id] = said }
        return said
    }

    /// « Réessayer » (the Accueil's pass, 18/11): the question of an answer that stopped or failed, asked again at the
    /// end of the thread. An answer that ended is not asked again: it may have written something.
    public func retry(_ answer: ColinMessageRow) {
        guard answer.author == .colin, answer.state == .interrupted || answer.state == .failed, !isAnswering,
              let question = messages.last(where: { $0.author == .paul && $0.createdAt < answer.createdAt }) else { return }
        // What Paul is typing stays in the bar.
        submit(question.text, clearing: false)
    }

    /// Three suggestions above the bar (the Accueil's pass, 18/11), from the day, until Paul asks Colin something today:
    /// who waits for his answer, where a project to deliver stands, what to start tomorrow.
    public func suggestions(review: [ReviewRules.Line], due: [String]) -> [String] {
        let today = calendar.startOfDay(for: now())
        guard !messages.contains(where: { $0.author == .paul && $0.createdAt >= today }) else { return [] }
        var said: [String] = []
        if review.contains(where: { $0.kind == .reply }) { said.append("Qui attend ma réponse ?") }
        if let project = due.first { said.append("Où on en est sur \(project) ?") }
        said.append("Sur quoi je me lance demain ?")
        return said
    }

    /// A suggestion, or a figure of « Le point »: its question in the bar, not sent.
    public func fill(_ text: String) {
        draft = text
    }

    /// « Annuler » on a change of Colin's: what he wrote is put back, what changed since stays.
    public func undo(_ line: ProjectChangeLine) {
        guard outcomes[line.id] == nil, line.undoneAt == nil else { return }
        outcomes[line.id] = (try? changeStore.undo(line, at: now())) ?? .changedSince
    }

    /// The answer kept is the answer shown, at once: the base's observation brings it a little later, and meanwhile
    /// the row would still be « being written » with nothing to write (final review, 18/11).
    private func shown(_ row: ColinMessageRow) {
        if let index = messages.firstIndex(where: { $0.id == row.id }) { messages[index] = row }
    }

    /// The words that came go out at about thirty paces a second, while some are waiting.
    private func pace() {
        guard pacing == nil else { return }
        pacing = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard let self, self.answer != nil else { break }
                let before = self.pacer.shown.count
                let shown = self.pacer.tick()
                if shown != self.visible { self.visible = shown }
                // Nothing more to give now (all shown, or a word not finished): the next words start it again.
                if shown.count == before { break }
            }
            self?.pacing = nil
        }
    }

    private func endPacing() {
        pacing?.cancel()
        pacing = nil
        pacer = StreamPacer()
        visible = ""
    }

    /// Steps of an answer that ended early: none stays « under way » — stopped (by Paul, a call, the sleep), they end;
    /// failed (Claude Code), they failed.
    nonisolated static func ended(_ steps: [ColinStep], failed: Bool = false) -> [ColinStep] {
        steps.map { step in
            var step = step
            if step.state == .running { step.state = failed ? .failed : .done }
            return step
        }
    }

    // MARK: - Words

    /// What Colin is doing, by his last tool.
    public static func phrase(for tool: String?) -> String {
        switch tool.map({ $0.replacingOccurrences(of: "mcp__polhub__", with: "") }) {
        case "projets", "contexte", "actions": "Colin regarde tes projets…"
        case "mails", "mail": "Colin lit tes mails…"
        case "reunions", "reunion", "chercher": "Colin lit tes réunions…"
        case "agenda", "contacts": "Colin regarde ton agenda…"
        case "brouillon": "Colin écrit le brouillon…"
        case "projet", "action", "fait", "journal": "Colin met à jour le projet…"
        default: "Colin réfléchit…"
        }
    }

    public static func sentence(_ failure: ColinFailure, calendar: Calendar) -> String {
        switch failure {
        case .missing: return "Claude Code est introuvable sur ce Mac."
        case .notConnected: return "Claude Code n'est pas connecté sur ton compte."
        case .limit(let resetsAt):
            guard let resetsAt else { return "Limite atteinte." }
            // « reprend à 9:05 », the hour by `Words.time` (lot 10, 20/11: never « 09:05 »).
            return "Limite atteinte · reprend à " + Words.time(resetsAt, calendar: calendar)
        case .launch: return "Claude Code n'a pas pu se lancer."
        case .noAnswer: return "Claude Code n'a pas répondu."
        case .isolation: return "Claude Code a chargé plus que ce que Polhub lui demande : Colin s'est arrêté."
        }
    }

    /// The lines of « À valider » as the Accueil says them, for the primer.
    public static func sentences(of lines: [ReviewRules.Line]) -> [String] {
        lines.map { line in ([ReviewText.title(line)] + [ReviewText.detail(line)].compactMap { $0 }).joined(separator: " · ") }
    }
}
