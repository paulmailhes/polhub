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
        /// « Colin attend la fin de ton call ».
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
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, isOn, runner != nil, !isAnswering else { return }
        asking = true
        Task { await begin(question) }
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
        cut("Arrêté : ton call commence.")
        guard isOn else { return }
        status = .waitingCall
        watchCall()
    }

    public func macWillSleep() {
        cut("Arrêté : le Mac s'endort.")
    }

    // MARK: - Pieces

    private func begin(_ question: String) async {
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
        draft = ""
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
        case .step(let step):
            guard answer != nil else { return }
            status = .working(Self.phrase(for: step.tool))
        case .answered(let turn):
            guard var row = answer else { return }
            row.text = turn.text
            row.state = turn.interrupted ? .interrupted : .done
            row.costUSD = turn.costUSD
            row.drafts = newDrafts().subtracting(draftsBefore).sorted()
            try? store.update(row)
            answer = nil
            streaming = ""
            lastAnswerAt = now()
            status = isOn ? .idle : .off
        case .failed(let failure):
            if var row = answer {
                row.text = streaming
                row.state = .failed
                try? store.update(row)
            }
            answer = nil
            streaming = ""
            status = .broken(Self.sentence(failure, calendar: calendar))
        }
    }

    /// Claude Code goes now; an answer under way keeps what came, and why it stopped.
    private func cut(_ note: String) {
        epoch += 1
        guard let runner else { return }
        Task { await runner.stop() }
        if case .working = status { status = isOn ? .idle : .off }
        if status == .starting || status == .settling { status = isOn ? .idle : .off }
        guard var row = answer else { return }
        row.text = streaming.isEmpty ? note : streaming + "\n\n" + note
        row.state = .interrupted
        try? store.update(row)
        answer = nil
        streaming = ""
    }

    private func switched() {
        if isOn {
            if status == .off { status = .idle }
        } else if status != .off {
            cut("Arrêté : Colin est à l'arrêt.")
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

    /// « Annuler » on a change of Colin's: what he wrote is put back, what changed since stays.
    public func undo(_ line: ProjectChangeLine) {
        guard outcomes[line.id] == nil, line.undoneAt == nil else { return }
        outcomes[line.id] = (try? changeStore.undo(line, at: now())) ?? .changedSince
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
            let parts = calendar.dateComponents([.hour, .minute], from: resetsAt)
            return String(format: "Limite atteinte · reprend à %02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
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
