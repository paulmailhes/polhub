import Agenda
import Colin
import Combine
import Foundation
import GRDB
import Persistence
import PolhubDesign

/// What the Accueil knows (18/11): « À valider » and « Le point », made by rules alone and kept up to date out of the
/// display. The base is read away from the main thread, once for a burst of changes; between two readings the lines
/// follow the clock from what was read. What the mails already hold in memory (their rules, the drafts) is taken
/// from them, never read twice. No model, nothing leaves the Mac.
@MainActor
public final class ColinLibrary: ObservableObject {
    /// « À valider », in order: the drafts ready, the answers awaited, the silent clients, the meetings to file.
    @Published public private(set) var review: [ReviewRules.Line] = []
    /// « Le point »: four sentences at most, as they stood at `briefingAt`.
    @Published public private(set) var briefing: [String] = []
    /// When « Le point » was prepared: at a return of Paul's, or when Polhub opened.
    @Published public private(set) var briefingAt: Date?

    private let agenda: AgendaLibrary
    private let mails: MailLibrary?
    private let defaults: UserDefaults
    private let now: () -> Date
    private let calendar: Calendar
    private let settle: Duration

    /// The threads of the last weeks, as the base's observation gave them.
    private var threads: [MailThreadRow] = []
    private var threadsRead = false
    /// What the last reading of the base gave; `stale` once something was written since.
    private var inputs: Inputs?
    private var stale = true
    private var readingCost: Duration = .zero
    /// « Le point » to prepare at the next computation: since when, and the time it will carry.
    private var wanted: (since: Date?, at: Date)?
    private var pending: Task<Void, Never>?
    private var again = false
    /// The last message of each line's conversation, as Paul has it before him: kept with a line he sets aside.
    private var lastMessages: [String: Date] = [:]
    /// The lines Paul set aside or filed by hand, with the number of the last computation begun before: a
    /// computation that began before his gesture never brings them back.
    private var removed: [String: Int] = [:]
    private var observations: [AnyDatabaseCancellable] = []
    private var cancellables: Set<AnyCancellable> = []
    private var timer: Task<Void, Never>?

    /// How many times the lines were computed, and how many times the base was read for it: for the tests.
    private(set) var computations = 0
    private(set) var readings = 0
    /// Nothing left to compute.
    var isIdle: Bool { pending == nil }

    /// `calendar`: the app's own when none is given (weeks begin on Monday, as in Calendrier). `settle`: how long a
    /// change waits for the others of its burst. `every`: how often the thresholds are looked at again, without
    /// reading the base.
    public init(agenda: AgendaLibrary, mails: MailLibrary?, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
                calendar: Calendar? = nil, settle: Duration = .milliseconds(300), every: Duration = .seconds(60)) {
        self.agenda = agenda
        self.mails = mails
        self.defaults = defaults
        self.now = now
        self.calendar = calendar ?? CalendarView.calendar
        self.settle = settle
        let database = agenda.database
        // What is written in the base: each change asks for a reading, and a burst of them for one.
        observations.append(ColinStore(database).observeDismissals { [weak self] _ in self?.changed() })
        agenda.$shown.dropFirst().sink { [weak self] _ in self?.changed() }.store(in: &cancellables)
        agenda.$projects.dropFirst().sink { [weak self] _ in self?.changed() }.store(in: &cancellables)
        if let mails {
            let since = now().addingTimeInterval(-Self.window)
            observations.append(mails.store.observeTurns(since: since) { [weak self] rows in
                guard let self else { return }
                self.threads = rows
                self.threadsRead = true
                self.changed()
            })
            // What the mails hold in memory: nothing to read again. Of the drafts, only what a line says counts:
            // Paul typing in one changes nothing here.
            mails.$drafts.map(Self.said).removeDuplicates().dropFirst().sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
            mails.$rules.dropFirst().sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
            // The mails programmed, the one leaving, the mailboxes Paul hid.
            mails.$scheduled.dropFirst().sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
            mails.$sending.dropFirst().sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
            mails.$hidden.dropFirst().sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
        }
        // Réglages › Colin: a threshold Paul changes shows at once.
        var thresholds = Self.thresholds(defaults)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: defaults).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                let read = Self.thresholds(defaults)
                guard read != thresholds else { return }
                thresholds = read
                self?.refresh()
            }
            .store(in: &cancellables)
        // The thresholds pass with the minutes, whatever is written.
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: every)
                self?.refresh()
            }
        }
        changed()
    }

    deinit {
        timer?.cancel()
        pending?.cancel()
    }

    // MARK: - Computing

    /// Asks for the lines again. Several requests close to one another make one computation.
    public func refresh() {
        guard pending == nil else {
            again = true
            return
        }
        pending = Task { [weak self] in
            var more = true
            while more, !Task.isCancelled {
                // A reading that took long is not begun again at once: never more than a sixth of the time.
                let wait = max(self?.settle ?? .zero, (self?.readingCost ?? .zero) * 5)
                try? await Task.sleep(for: wait)
                guard let self else { return }
                self.again = false
                await self.compute()
                more = self.again
            }
            self?.pending = nil
        }
    }

    /// Something was written in the base: the next computation reads it again.
    private func changed() {
        stale = true
        refresh()
    }

    private func compute() async {
        // With the mails, the first computation waits for their threads and their rules: nothing is said of a base
        // half read.
        guard mails.map({ $0.rulesRead && threadsRead }) ?? true else { return }
        computations += 1
        let number = computations
        let reads = stale || inputs == nil
        if reads {
            stale = false
            readings += 1
        }
        let hiddenDrafts = Set((mails?.scheduled.keys).map(Array.init) ?? []).union([mails?.sending?.draftID].compactMap { $0 })
        let asked = wanted
        let job = Job(database: agenda.database, threads: threads, rules: mails?.rules ?? .empty, drafts: mails?.drafts ?? [], withMails: mails != nil,
                      known: reads ? nil : inputs, hiddenDrafts: hiddenDrafts, hiddenAccounts: mails?.hidden ?? [], thresholds: Self.thresholds(defaults),
                      now: now(), calendar: calendar, point: asked.map { Job.Point(since: $0.since) })
        let clock = ContinuousClock(), began = clock.now
        let outcome = await Task.detached(priority: .utility) { job.run() }.value
        guard let outcome else {
            // The base could not be read: what shows stays, and the next request reads again.
            stale = true
            return
        }
        if reads { readingCost = clock.now - began }
        inputs = outcome.inputs
        lastMessages = outcome.lastMessages
        // A line Paul set aside while this was computed stays out; a later computation knows what he did.
        let lines = outcome.lines.filter { (removed[$0.id] ?? 0) < number }
        removed = removed.filter { $0.value >= number }
        if lines != review { review = lines }
        // « Le point », unless Paul came back again meanwhile: the next computation prepares that one.
        if let point = outcome.point, let asked, wanted?.at == asked.at {
            if point != briefing { briefing = point }
            briefingAt = asked.at
            wanted = nil
        }
    }

    // MARK: - Paul is there

    /// The Accueil shows, or Polhub comes back in front on the Accueil. « Le point » is prepared when Paul is back
    /// (the first time of a day, or three hours later), and when Polhub has none yet since it opened.
    public func seen() {
        let date = now()
        let before = presence
        let passage = Presence.seen(before, at: date, calendar: calendar)
        var state = passage.state
        // How long he was away, from half an hour up, a return or not: what will set the threshold of a return.
        if let last = before.lastSeen, date.timeIntervalSince(last) >= Self.absenceFloor {
            let all = ((defaults.array(forKey: Preferences.Key.colinAbsences) as? [Int]) ?? []) + [Int(date.timeIntervalSince(last) / 60)]
            defaults.set(Array(all.suffix(Self.absencesKept)), forKey: Preferences.Key.colinAbsences)
        }
        if passage.returned || (briefingAt == nil && wanted == nil) {
            wanted = (since: state.since, at: date)
            state.preparedAt = date
        }
        presence = state
        refresh()
    }

    /// When the Accueil was last before Paul: three dates in the preferences, nothing else.
    private var presence: Presence.State {
        get { defaults.data(forKey: Preferences.Key.colinPresence).flatMap { try? JSONDecoder().decode(Presence.State.self, from: $0) } ?? Presence.State() }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Preferences.Key.colinPresence)
        }
    }

    // MARK: - Paul's gestures

    /// « Pas besoin », « Plus tard », « Elle a répondu ailleurs »: the line leaves at once, and the base keeps why,
    /// with the last message Paul had before him. A draft is not set aside: it leaves when sent, deleted or programmed.
    public func dismiss(_ line: ReviewRules.Line, reason: ColinDismissalRow.Reason) {
        guard line.kind != .draft, let subject = line.threadKey ?? line.eventID else { return }
        let row = ColinDismissalRow(kind: line.kind.rawValue, subject: subject, reason: reason, projectID: line.projectID, createdAt: now(),
                                    lastMessageAt: lastMessages[line.id])
        guard (try? ColinStore(agenda.database).dismiss(row)) != nil else { return }
        remove(line)
        changed()
    }

    /// « Ranger »: the meeting goes in a project, or in none (« Aucun »); either way it is no longer offered.
    public func file(_ line: ReviewRules.Line, projectID: UUID?) async {
        guard line.kind == .unfiled, let id = line.eventID, let event = try? CalendarStore(agenda.database).event(id: id) else { return }
        remove(line)
        await agenda.setProject(event, projectID: projectID)
        changed()
    }

    private func remove(_ line: ReviewRules.Line) {
        removed[line.id] = computations
        review.removeAll { $0.id == line.id }
    }

    // MARK: - Pieces

    /// How far back the mails are read: the oldest thread the rules still say, and a day.
    nonisolated static let window = Double(ReviewRules.Thresholds().maxAgeDays + 1) * 86_400
    private static let absencesKept = 100
    private static let absenceFloor: TimeInterval = 30 * 60

    /// The thresholds of Réglages › Colin, read again at each computation.
    private static func thresholds(_ defaults: UserDefaults) -> ReviewRules.Thresholds {
        let settings = Preferences(defaults: defaults)
        return ReviewRules.Thresholds(replyDays: settings.colinReplyDays, silentDays: settings.colinSilentDays)
    }

    /// What a line says of the drafts an agent prepared: which, for whom (the people say the project), under which
    /// thread, on what subject. Never its text.
    private nonisolated static func said(_ drafts: [MailDraftRow]) -> [String] {
        drafts.filter { $0.origin == .agent }.map { draft in
            let people = (draft.to + draft.cc).map(\.email).joined(separator: ",")
            return [draft.id, draft.to.first?.display ?? "", people, draft.threadKey ?? "", draft.subject].joined(separator: "\u{1F}")
        }
    }

    /// What one reading of the base gives.
    struct Inputs: Sendable {
        var threads: [MailThreadRow] = []
        /// The copies of one conversation in several of Paul's mailboxes.
        var conversations: [String: String] = [:]
        /// Who Paul wrote to, in the threads where he wrote last.
        var recipients: [String: [MailAddress]] = [:]
        /// One row per event, from two weeks ago on.
        var events: [CalendarEventRow] = []
        var projects: [ProjectRow] = []
        var dismissed: [ColinDismissalRow] = []
    }

    /// One computation, away from the main thread: the base is read when `known` is nil, then the rules say the lines.
    struct Job: Sendable {
        struct Point: Sendable {
            var since: Date?
        }

        struct Outcome: Sendable {
            var inputs: Inputs
            var lines: [ReviewRules.Line]
            var lastMessages: [String: Date]
            var point: [String]?
        }

        var database: AppDatabase
        var threads: [MailThreadRow]
        var rules: MailFilingRules
        var drafts: [MailDraftRow]
        var withMails: Bool
        var known: Inputs?
        var hiddenDrafts: Set<String>
        var hiddenAccounts: Set<String>
        var thresholds: ReviewRules.Thresholds
        var now: Date
        var calendar: Calendar
        var point: Point?

        func run() -> Outcome? {
            guard let inputs = known ?? (try? read()) else { return nil }
            let said = lines(inputs)
            return Outcome(inputs: inputs, lines: said.lines, lastMessages: said.lastMessages, point: point.map { sentences(inputs, since: $0.since) })
        }

        private func read() throws -> Inputs {
            var inputs = Inputs()
            let agenda = CalendarStore(database)
            let oldest = now.addingTimeInterval(-Double(ReviewRules.unfiledDays + 1) * 86_400)
            inputs.events = EventCopies.merge(try agenda.events(from: oldest, to: .distantFuture), accounts: try agenda.accounts())
            inputs.projects = try ProjectStore(database).projects()
            inputs.dismissed = try ColinStore(database).dismissals()
            guard withMails else { return inputs }
            let mails = MailStore(database)
            inputs.threads = threads
            inputs.conversations = try mails.conversations(since: now.addingTimeInterval(-ColinLibrary.window))
            let wroteLast = threads.filter { ($0.lastSentAt ?? .distantPast) > ($0.lastReceivedAt ?? .distantPast) }.map(\.id)
            for index in stride(from: 0, to: wroteLast.count, by: 400) {
                inputs.recipients.merge(try mails.sentRecipients(threadKeys: Array(wroteLast[index..<min(index + 400, wroteLast.count)]))) { first, _ in first }
            }
            return inputs
        }

        /// « À valider ». The mailboxes Paul hid from his mails are not signaled, but what he answered from them
        /// counts; an agent's draft waits for him whatever its mailbox.
        private func lines(_ inputs: Inputs) -> (lines: [ReviewRules.Line], lastMessages: [String: Date]) {
            let unfiled = ReviewRules.unfiled(inputs.events, dismissed: inputs.dismissed, now: now, calendar: calendar)
            guard withMails else { return (ReviewRules.ordered([unfiled]), [:]) }
            // The copies in a mailbox shown come first: a conversation is said from the box Paul looks at.
            let threads = inputs.threads.filter { !hiddenAccounts.contains($0.account) } + inputs.threads.filter { hiddenAccounts.contains($0.account) }
            let drafts = ReviewRules.drafts(self.drafts, hidden: hiddenDrafts, threads: threads, rules: rules)
            let boxes = Dictionary(threads.map { ($0.id, $0.account) }, uniquingKeysWith: { first, _ in first })
            func shown(_ line: ReviewRules.Line) -> Bool {
                line.threadKey.flatMap { boxes[$0] }.map { !hiddenAccounts.contains($0) } ?? true
            }
            let replies = ReviewRules.replies(threads, rules: rules, conversations: inputs.conversations, dismissed: inputs.dismissed, now: now,
                                              thresholds: thresholds, calendar: calendar).filter(shown)
            let silent = ReviewRules.silent(threads, rules: rules, conversations: inputs.conversations, recipients: inputs.recipients,
                                            events: inputs.events, dismissed: inputs.dismissed, now: now, thresholds: thresholds, calendar: calendar).filter(shown)
            // The last message of each conversation, whoever wrote it.
            var last: [String: Date] = [:]
            for thread in threads {
                guard let date = [thread.lastReceivedAt, thread.lastSentAt].compactMap({ $0 }).max() else { continue }
                let conversation = inputs.conversations[thread.id] ?? thread.id
                last[conversation] = max(last[conversation] ?? .distantPast, date)
            }
            var lastMessages: [String: Date] = [:]
            for line in replies + silent {
                guard let key = line.threadKey else { continue }
                lastMessages[line.id] = last[inputs.conversations[key] ?? key]
            }
            return (ReviewRules.ordered([drafts, replies, silent, unfiled]), lastMessages)
        }

        /// « Le point ». A client's mail delivered to two of Paul's mailboxes counts once.
        private func sentences(_ inputs: Inputs, since: Date?) -> [String] {
            var clients = 0
            if withMails, let since {
                let threads = Briefing.clientMails(inputs.threads.filter { !hiddenAccounts.contains($0.account) }, rules: rules, since: since)
                clients = Set(threads.map { inputs.conversations[$0.id] ?? $0.id }).count
            }
            return Briefing.lines(week: Briefing.week(inputs.events, now: now, calendar: calendar), due: Briefing.due(inputs.projects, now: now, calendar: calendar),
                                  yours: Briefing.yours(inputs.projects), clientMails: clients, since: since, now: now, calendar: calendar)
        }
    }
}
