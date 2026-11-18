import Agenda
import Colin
import Combine
import Foundation
import GRDB
import Persistence
import PolhubDesign

/// What the Accueil knows (18/11): « À valider » and « Le point », made by rules alone and kept up to date out of the
/// display. The base is read away from the main thread, once for a burst of changes, and only for writings a line
/// can say; between two readings the lines follow the clock from what was read. What the mails already hold in
/// memory (their rules, the drafts) is taken from them, never read twice. No model, nothing leaves the Mac.
@MainActor
public final class ColinLibrary: ObservableObject {
    /// « À valider », in order: the drafts ready, the answers awaited, the silent clients, the meetings to file.
    @Published public private(set) var review: [ReviewRules.Line] = []
    /// « Le point »: four sentences at most, as they stood when Paul came back.
    @Published public private(set) var briefing: [String] = []
    /// When « Le point » was prepared: at a return of Paul's, or when Polhub opened.
    @Published public private(set) var briefingAt: Date?

    private let agenda: AgendaLibrary
    private let mails: MailLibrary?
    private let defaults: UserDefaults
    private let now: () -> Date
    /// The calendar given, else the app's own, made again at each use: it follows a change of time zone.
    private let givenCalendar: Calendar?
    private var calendar: Calendar { givenCalendar ?? CalendarView.calendar }
    private let settle: Duration

    /// The threads of the last weeks, as the base's observation gave them.
    private var threads: [MailThreadRow] = []
    private var threadsRead = false
    /// What the last readings of the base gave: of the mails, of the rest (events, projects, lines set aside). Each is
    /// read again once something a line can say was written since.
    private var mailInputs: MailInputs?
    private var baseInputs: BaseInputs?
    private var staleMails = true
    private var staleBase = true
    private var readingCost: Duration = .zero
    /// « Le point » to prepare: since when, and the time it carries. Kept after it is prepared, until the copies of
    /// the mailboxes and of the calendars were read again (or ten minutes): what they bring then enters it.
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
        givenCalendar = calendar
        self.settle = settle
        let database = agenda.database
        // What is written in the base asks for a reading, a burst of writings for one; and only what a line can say:
        // Paul's notes in a project, a mail read or archived, a calendar that writes the same events again ask nothing.
        observations.append(ColinStore(database).observeDismissals { [weak self] _ in self?.changed(mails: false) })
        agenda.$shown.map(Self.said).removeDuplicates().dropFirst().sink { [weak self] _ in self?.changed(mails: false) }.store(in: &cancellables)
        agenda.$projects.map(Self.said).removeDuplicates().dropFirst().sink { [weak self] _ in self?.changed(mails: false) }.store(in: &cancellables)
        if let mails {
            let since = now().addingTimeInterval(-Self.window)
            observations.append(mails.store.observeTurns(since: since) { [weak self] rows in
                guard let self else { return }
                let same = self.threadsRead && Self.said(rows) == Self.said(self.threads)
                self.threads = rows
                self.threadsRead = true
                if !same { self.changed(mails: true) }
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
        refresh()
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
        // At the priority of the reading it waits for: a reading never climbs above the app's own work.
        pending = Task(priority: .utility) { [weak self] in
            var more = true
            while more, !Task.isCancelled {
                guard let wait = self?.wait else { return }
                try? await Task.sleep(for: wait)
                guard let self else { return }
                self.again = false
                await self.compute()
                more = self.again
            }
            self?.pending = nil
        }
    }

    /// How long the next computation waits: the others of its burst; longer when it reads the base again after a
    /// reading that took long.
    private var wait: Duration {
        staleMails || staleBase ? Self.pause(settle: settle, reading: readingCost) : settle
    }

    /// How long a computation that reads the base waits before it begins: the others of its burst, and five times
    /// what the last reading took (never more than a sixth of the time in readings), up to five seconds: a reading
    /// that took long, whatever the reason, never holds the next ones for long.
    nonisolated static func pause(settle: Duration, reading: Duration) -> Duration {
        min(max(settle, reading * 5), max(settle, .seconds(5)))
    }

    /// Something a line can say was written in the base: the next computation reads it again. `mails`: the threads
    /// changed (their copies in other mailboxes and their recipients are read again); else the rest.
    private func changed(mails: Bool) {
        if mails { staleMails = true } else { staleBase = true }
        refresh()
    }

    private func compute() async {
        // With the mails, the first computation waits for their threads and their rules: nothing is said of a base
        // half read.
        guard mails.map({ $0.rulesRead && threadsRead }) ?? true else { return }
        computations += 1
        let number = computations
        let date = now()
        // « Le point » already prepared: once the copies were read again since Paul's return, or after ten minutes,
        // it is closed and no longer moves.
        if let point = wanted, briefingAt == point.at, readAgain(since: point.at) || date.timeIntervalSince(point.at) >= Self.pointSettles {
            wanted = nil
        }
        let asked = wanted
        let readsMails = mails != nil && (staleMails || mailInputs == nil), readsBase = staleBase || baseInputs == nil
        if readsMails { staleMails = false }
        if readsBase { staleBase = false }
        if readsMails || readsBase { readings += 1 }
        let hiddenDrafts = Set((mails?.scheduled.keys).map(Array.init) ?? []).union([mails?.sending?.draftID].compactMap { $0 })
        let job = Job(database: agenda.database, threads: threads, rules: mails?.rules ?? .empty, drafts: mails?.drafts ?? [], withMails: mails != nil,
                      knownMails: readsMails ? nil : mailInputs ?? MailInputs(), knownBase: readsBase ? nil : baseInputs, hiddenDrafts: hiddenDrafts,
                      hiddenAccounts: mails?.hidden ?? [], thresholds: Self.thresholds(defaults), now: date, calendar: calendar,
                      point: asked.map { Job.Point(since: $0.since) })
        // The time a reading takes, a Mac's sleep apart: a Mac that slept has not been reading.
        let clock = SuspendingClock(), began = clock.now
        let outcome = await Task.detached(priority: .utility) { job.run() }.value
        guard let outcome else {
            // The base could not be read: what shows stays, and the next request reads again.
            if readsMails { staleMails = true }
            if readsBase { staleBase = true }
            return
        }
        if readsMails || readsBase { readingCost = clock.now - began }
        mailInputs = outcome.mails
        baseInputs = outcome.base
        lastMessages = outcome.lastMessages
        // A line Paul set aside while this was computed stays out; a later computation knows what he did.
        let lines = outcome.lines.filter { (removed[$0.id] ?? 0) < number }
        removed = removed.filter { $0.value >= number }
        if lines != review { review = lines }
        // « Le point », unless Paul came back again meanwhile: the next computation prepares that one.
        if let point = outcome.point, let asked, wanted?.at == asked.at {
            if point != briefing { briefing = point }
            if briefingAt != asked.at { briefingAt = asked.at }
        }
    }

    /// Everything Polhub copies was read again since `date`: the mailboxes it follows and the calendars. What came
    /// while Paul was away is then in the base.
    private func readAgain(since date: Date) -> Bool {
        let calendars = agenda.accounts.allSatisfy { ($0.lastSyncAt ?? .distantPast) >= date }
        let mailboxes = mails.map { mails in mails.accounts.allSatisfy { (mails.cursors[$0.email]?.lastSyncAt ?? .distantPast) >= date } } ?? true
        return calendars && mailboxes
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

    /// « Pas besoin », « Plus tard », « Anne a répondu ailleurs »: the line leaves at once, and the base keeps why,
    /// with the last message Paul had before him. A draft is not set aside: it leaves when sent, deleted or programmed.
    public func dismiss(_ line: ReviewRules.Line, reason: ColinDismissalRow.Reason) {
        guard line.kind != .draft, let subject = line.threadKey ?? line.eventID else { return }
        let row = ColinDismissalRow(kind: line.kind.rawValue, subject: subject, reason: reason, projectID: line.projectID, createdAt: now(),
                                    lastMessageAt: lastMessages[line.id])
        guard (try? ColinStore(agenda.database).dismiss(row)) != nil else { return }
        remove(line)
    }

    /// « Ranger »: the meeting goes in a project, or in none (« Aucun »); either way it is no longer offered.
    public func file(_ line: ReviewRules.Line, projectID: UUID?) async {
        guard line.kind == .unfiled, let id = line.eventID, let event = try? CalendarStore(agenda.database).event(id: id) else { return }
        // The line leaves before the filing is awaited: its writing comes first in it, before any computation.
        remove(line)
        await agenda.setProject(event, projectID: projectID)
        changed(mails: false)
    }

    /// The line leaves now; the next computation reads the base again, whatever asked for it.
    private func remove(_ line: ReviewRules.Line) {
        removed[line.id] = computations
        if review.contains(where: { $0.id == line.id }) { review.removeAll { $0.id == line.id } }
        changed(mails: false)
    }

    // MARK: - Pieces

    /// How far back the mails are read: the oldest thread the rules still say, and a day.
    nonisolated static let window = Double(ReviewRules.Thresholds().maxAgeDays + 1) * 86_400
    private static let absencesKept = 100
    private static let absenceFloor: TimeInterval = 30 * 60
    /// A point just prepared stays open this long at most.
    private static let pointSettles: TimeInterval = 10 * 60

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

    /// What the rules read of a thread: who wrote, when, and what files it. Not whether it is read, in the inbox,
    /// nor its extract.
    private nonisolated static func said(_ threads: [MailThreadRow]) -> [MailThreadRow] {
        threads.map { thread in
            var copy = thread
            copy.snippet = ""
            copy.lastMessageAt = .distantPast
            copy.messageCount = 0
            copy.unread = false
            copy.inInbox = false
            copy.hasAttachment = false
            return copy
        }
    }

    /// What a line or the point says of an event: its day, its title, its project, its meeting, Paul's answer. Not
    /// when the calendar last wrote it.
    private nonisolated static func said(_ events: [CalendarEventRow]) -> [CalendarEventRow] {
        events.map { event in
            var copy = event
            copy.updatedAt = .distantPast
            copy.htmlLink = nil
            copy.location = nil
            return copy
        }
    }

    /// What the point says of a project: its name, its status, its due date, its place. Not its notes.
    private nonisolated static func said(_ projects: [ProjectRow]) -> [String] {
        projects.map { project in
            [project.id.uuidString, project.name, project.status.rawValue, project.dueDate.map { String($0.timeIntervalSince1970) } ?? "",
             String(project.kanbanOrder), project.deletedAt == nil ? "" : "x"].joined(separator: "\u{1F}")
        }
    }

    /// What a reading of the mails gives.
    struct MailInputs: Sendable {
        var threads: [MailThreadRow] = []
        /// The copies of one conversation in several of Paul's mailboxes.
        var conversations: [String: String] = [:]
        /// Who Paul wrote to, in the threads where he wrote last.
        var recipients: [String: [MailAddress]] = [:]
    }

    /// What a reading of the rest of the base gives.
    struct BaseInputs: Sendable {
        /// One row per event, from two weeks ago on.
        var events: [CalendarEventRow] = []
        var projects: [ProjectRow] = []
        var dismissed: [ColinDismissalRow] = []
    }

    /// One computation, away from the main thread: what is not known is read in the base, then the rules say the lines.
    struct Job: Sendable {
        struct Point: Sendable {
            var since: Date?
        }

        struct Outcome: Sendable {
            var mails: MailInputs
            var base: BaseInputs
            var lines: [ReviewRules.Line]
            var lastMessages: [String: Date]
            var point: [String]?
        }

        var database: AppDatabase
        var threads: [MailThreadRow]
        var rules: MailFilingRules
        var drafts: [MailDraftRow]
        var withMails: Bool
        var knownMails: MailInputs?
        var knownBase: BaseInputs?
        var hiddenDrafts: Set<String>
        var hiddenAccounts: Set<String>
        var thresholds: ReviewRules.Thresholds
        var now: Date
        var calendar: Calendar
        var point: Point?

        func run() -> Outcome? {
            guard let mails = knownMails ?? (try? readMails()), let base = knownBase ?? (try? readBase()) else { return nil }
            let said = lines(mails, base)
            return Outcome(mails: mails, base: base, lines: said.lines, lastMessages: said.lastMessages,
                           point: point.map { sentences(mails, base, since: $0.since) })
        }

        private func readBase() throws -> BaseInputs {
            var inputs = BaseInputs()
            let agenda = CalendarStore(database)
            let oldest = now.addingTimeInterval(-Double(ReviewRules.unfiledDays + 1) * 86_400)
            inputs.events = EventCopies.merge(try agenda.events(from: oldest, to: .distantFuture), accounts: try agenda.accounts())
            inputs.projects = try ProjectStore(database).projects()
            inputs.dismissed = try ColinStore(database).dismissals()
            return inputs
        }

        private func readMails() throws -> MailInputs {
            var inputs = MailInputs()
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
        private func lines(_ mails: MailInputs, _ base: BaseInputs) -> (lines: [ReviewRules.Line], lastMessages: [String: Date]) {
            let unfiled = ReviewRules.unfiled(base.events, dismissed: base.dismissed, now: now, calendar: calendar)
            guard withMails else { return (ReviewRules.ordered([unfiled]), [:]) }
            // The copies in a mailbox shown come first: a conversation is said from the box Paul looks at.
            let threads = mails.threads.filter { !hiddenAccounts.contains($0.account) } + mails.threads.filter { hiddenAccounts.contains($0.account) }
            let drafts = ReviewRules.drafts(self.drafts, hidden: hiddenDrafts, threads: threads, rules: rules)
            let boxes = Dictionary(threads.map { ($0.id, $0.account) }, uniquingKeysWith: { first, _ in first })
            func shown(_ line: ReviewRules.Line) -> Bool {
                line.threadKey.flatMap { boxes[$0] }.map { !hiddenAccounts.contains($0) } ?? true
            }
            let replies = ReviewRules.replies(threads, rules: rules, conversations: mails.conversations, dismissed: base.dismissed, now: now,
                                              thresholds: thresholds, calendar: calendar).filter(shown)
            let silent = ReviewRules.silent(threads, rules: rules, conversations: mails.conversations, recipients: mails.recipients,
                                            events: base.events, dismissed: base.dismissed, now: now, thresholds: thresholds, calendar: calendar).filter(shown)
            // The last message of each conversation, whoever wrote it.
            var last: [String: Date] = [:]
            for thread in threads {
                guard let date = [thread.lastReceivedAt, thread.lastSentAt].compactMap({ $0 }).max() else { continue }
                let conversation = mails.conversations[thread.id] ?? thread.id
                last[conversation] = max(last[conversation] ?? .distantPast, date)
            }
            var lastMessages: [String: Date] = [:]
            for line in replies + silent {
                guard let key = line.threadKey else { continue }
                lastMessages[line.id] = last[mails.conversations[key] ?? key]
            }
            return (ReviewRules.ordered([drafts, replies, silent, unfiled]), lastMessages)
        }

        /// « Le point ». A client's mail delivered to two of Paul's mailboxes counts once.
        private func sentences(_ mails: MailInputs, _ base: BaseInputs, since: Date?) -> [String] {
            var clients = 0
            if withMails, let since {
                let threads = Briefing.clientMails(mails.threads.filter { !hiddenAccounts.contains($0.account) }, rules: rules, since: since)
                clients = Set(threads.map { mails.conversations[$0.id] ?? $0.id }).count
            }
            return Briefing.lines(week: Briefing.week(base.events, now: now, calendar: calendar), due: Briefing.due(base.projects, now: now, calendar: calendar),
                                  yours: Briefing.yours(base.projects), clientMails: clients, since: since, now: now, calendar: calendar)
        }
    }
}
