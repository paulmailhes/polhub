import Foundation
import Persistence

/// « À valider » on the Accueil (18/11): what waits for Paul's click, said by rules alone. No model, nothing read
/// outside the base, nothing that leaves the Mac. Each function takes rows and gives the lines to show.
public enum ReviewRules {
    public struct Thresholds: Equatable, Sendable {
        /// « Attend ta réponse »: the last message received is this old, in days.
        public var replyDays: Int
        /// « Ne répond plus »: Paul's last message is this old, in days.
        public var silentDays: Int
        /// Older than this, a thread is no longer said: it is history.
        public var maxAgeDays: Int

        public init(replyDays: Int = 3, silentDays: Int = 7, maxAgeDays: Int = 45) {
            self.replyDays = replyDays
            self.silentDays = silentDays
            self.maxAgeDays = maxAgeDays
        }
    }

    public enum Kind: String, Sendable {
        /// « Brouillon prêt pour Claire ».
        case draft
        /// « Marc attend ta réponse ».
        case reply
        /// « Anne ne répond plus ».
        case silent
        /// « Réunion à ranger ».
        case unfiled
    }

    public struct Line: Equatable, Identifiable, Sendable {
        /// `<kind>:<subject>`: also the key under which Paul sets the line aside.
        public var id: String
        public var kind: Kind
        /// « Claire », or the title of the event; empty for a draft without a recipient.
        public var person: String
        /// What the line is about: the project's name; for a draft without one, the subject of its mail.
        public var detail: String?
        public var days: Int?
        public var threadKey: String?
        public var draftID: String?
        public var eventID: String?
        public var projectID: UUID?

        public init(id: String, kind: Kind, person: String, detail: String? = nil, days: Int? = nil, threadKey: String? = nil,
                    draftID: String? = nil, eventID: String? = nil, projectID: UUID? = nil) {
            self.id = id
            self.kind = kind
            self.person = person
            self.detail = detail
            self.days = days
            self.threadKey = threadKey
            self.draftID = draftID
            self.eventID = eventID
            self.projectID = projectID
        }
    }

    /// A meeting without a project is offered for this long.
    public static let unfiledDays = 14
    private static let day: TimeInterval = 86_400

    // MARK: - « Brouillon prêt »

    /// The drafts an agent prepared, the most recent first. `hidden`: the programmed ones and the one on its way out,
    /// which no longer wait for Paul. Each says its project: the one of the thread it answers (among `threads`); for
    /// a new mail, the one project of the people it is written to; without a project, the subject of the mail.
    public static func drafts(_ drafts: [MailDraftRow], hidden: Set<String>, threads: [MailThreadRow] = [], rules: MailFilingRules = .empty) -> [Line] {
        let known = Dictionary(threads.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return drafts.filter { $0.origin == .agent && !hidden.contains($0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { draft in
                let project: UUID?
                if let thread = draft.threadKey.flatMap({ known[$0] }) {
                    project = rules.filing(of: thread)?.filing.projectID
                } else {
                    project = self.project(of: draft.to + draft.cc, rules: rules)
                }
                let subject = draft.subject.trimmingCharacters(in: .whitespacesAndNewlines)
                return Line(id: id(.draft, draft.id), kind: .draft, person: draft.to.first.map { short($0.display) } ?? "",
                            detail: name(of: project, rules: rules) ?? (subject.isEmpty ? nil : subject), threadKey: draft.threadKey, draftID: draft.id,
                            projectID: project)
            }
    }

    // MARK: - « Attend ta réponse »

    /// The conversations whose last message came from someone Paul already wrote to, three days ago or more, and
    /// that he has not answered. `conversations`: the copies of one conversation in several of his mailboxes
    /// (`MailStore.conversations`): its turn is read over all of them, so a copy left behind in another box never
    /// waits. The oldest first.
    public static func replies(_ threads: [MailThreadRow], rules: MailFilingRules, conversations: [String: String] = [:],
                               dismissed: [ColinDismissalRow], now: Date, thresholds: Thresholds, calendar: Calendar = .current) -> [Line] {
        let aside = rows(dismissed, of: .reply)
        var lines: [Line] = []
        for copies in grouped(threads, conversations) {
            let received = copies.compactMap(\.lastReceivedAt).max(), sent = copies.compactMap(\.lastSentAt).max()
            guard let received, received > (sent ?? .distantPast) else { continue }
            let days = age(of: received, now: now)
            guard days >= thresholds.replyDays, days <= thresholds.maxAgeDays else { continue }
            // The first copy that waits: one that holds a message received after Paul's last answer. In the order the
            // threads were given (the mailboxes Paul shows first), not the box whose copy happens to be dated last.
            guard let thread = copies.first(where: { ($0.lastReceivedAt ?? .distantPast) > (sent ?? .distantPast) }),
                  rules.tab(of: thread) == .personnes, thread.lastSender.map({ rules.correspondents.contains($0.lowercased()) }) == true else { continue }
            guard !copies.contains(where: { isAside(aside[$0.id], lastMessage: received, now: now, calendar: calendar) }) else { continue }
            let project = rules.filing(of: thread)?.filing.projectID
            lines.append(Line(id: id(.reply, thread.id), kind: .reply, person: sender(of: thread, rules: rules), detail: name(of: project, rules: rules),
                              days: days, threadKey: thread.id, projectID: project))
        }
        return lines.sorted { ($0.days ?? 0) > ($1.days ?? 0) }
    }

    // MARK: - « Ne répond plus »

    /// The conversations of a project where Paul wrote last, seven days ago or more, with no coming event of that
    /// project. `recipients`: who Paul wrote to in each thread; in a thread nobody else wrote in, they say the
    /// project. The oldest first.
    public static func silent(_ threads: [MailThreadRow], rules: MailFilingRules, conversations: [String: String] = [:],
                              recipients: [String: [MailAddress]], events: [CalendarEventRow], dismissed: [ColinDismissalRow], now: Date,
                              thresholds: Thresholds, calendar: Calendar = .current) -> [Line] {
        let aside = rows(dismissed, of: .silent)
        // « Elle a répondu ailleurs », said twice of one project (of two threads, or twice of the same): Colin no
        // longer says it of this project.
        var elsewhere: [UUID: Int] = [:]
        for row in aside.values where row.reason == .answeredElsewhere {
            if let project = row.projectID { elsewhere[project, default: 0] += max(row.times, 1) }
        }
        let quiet = Set(elsewhere.filter { $0.value >= 2 }.keys)
        let coming = Set(events.filter { $0.startAt > now }.compactMap(\.projectID))
        var lines: [Line] = []
        for copies in grouped(threads, conversations) {
            let received = copies.compactMap(\.lastReceivedAt).max(), sent = copies.compactMap(\.lastSentAt).max()
            guard let sent, sent > (received ?? .distantPast) else { continue }
            let days = age(of: sent, now: now)
            guard days >= thresholds.silentDays, days <= thresholds.maxAgeDays else { continue }
            // The first of the copies that sits in a project.
            guard let (thread, project) = copies.lazy.compactMap({ thread in
                self.project(of: thread, rules: rules, recipients: recipients[thread.id] ?? []).map { (thread, $0) }
            }).first else { continue }
            guard !quiet.contains(project), !coming.contains(project) else { continue }
            guard !copies.contains(where: { isAside(aside[$0.id], lastMessage: sent, now: now, calendar: calendar) }) else { continue }
            lines.append(Line(id: id(.silent, thread.id), kind: .silent, person: silentPerson(of: thread, rules: rules, recipients: recipients[thread.id] ?? []),
                              detail: name(of: project, rules: rules), days: days, threadKey: thread.id, projectID: project))
        }
        return lines.sorted { ($0.days ?? 0) > ($1.days ?? 0) }
    }

    // MARK: - « Réunion à ranger »

    /// The meetings of the last two weeks that sit in no project, and that Paul did not file under « Aucun ». One
    /// line by meeting, even when its event is in two of his calendars. The most recent first.
    public static func unfiled(_ events: [CalendarEventRow], dismissed: [ColinDismissalRow] = [], now: Date, calendar: Calendar = .current) -> [Line] {
        let aside = rows(dismissed, of: .unfiled)
        let oldest = now.addingTimeInterval(-Double(unfiledDays) * day)
        var seen: Set<UUID> = []
        return events
            .filter { $0.projectID == nil && $0.meetingID != nil && $0.projectOrigin != .paul && $0.startAt <= now && $0.startAt >= oldest }
            // An event has no later message: set aside, it stays aside (« Plus tard »: until the next day).
            .filter { !isAside(aside[$0.id], lastMessage: .distantPast, now: now, calendar: calendar) }
            .sorted { $0.startAt > $1.startAt }
            .filter { event in event.meetingID.map { seen.insert($0).inserted } ?? true }
            .map { Line(id: id(.unfiled, $0.id), kind: .unfiled, person: $0.title, eventID: $0.id) }
    }

    // MARK: - Together

    /// Everything in order, whatever order the lists come in: the drafts, the replies awaited, the silences, the
    /// meetings. Inside each kind, the order its own function gave.
    public static func ordered(_ lines: [[Line]]) -> [Line] {
        let rank: [Kind: Int] = [.draft: 0, .reply: 1, .silent: 2, .unfiled: 3]
        return lines.flatMap { $0 }.enumerated()
            .sorted { (rank[$0.element.kind] ?? 9, $0.offset) < (rank[$1.element.kind] ?? 9, $1.offset) }
            .map(\.element)
    }

    /// « Claire Morel » → « Claire », « Morel, Claire » too. Whatever does not plainly begin with a first name stays
    /// whole, rather than be cut at the wrong word: an address, a single word, a title (« Dr. Claire Morel »), a
    /// name in capitals (« MOREL Claire », « EDF Entreprises »), a first word that is no word.
    public static func short(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "'\"«»“”‘’")))
        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 2, !trimmed.contains("@") else { return trimmed }
        let first = words[0], second = words[1]
        if first.hasSuffix(","), first.count > 2 { return second }
        let letters = first.filter(\.isLetter)
        let isTitle = first.hasSuffix(".") || titles.contains(first.lowercased())
        let shouted = letters.count > 1 && first == first.uppercased()
        guard letters.count >= 2, letters.count == first.filter({ $0 != "-" }).count, !isTitle, !shouted else { return trimmed }
        return first
    }

    private static let titles: Set<String> = ["m", "mr", "mme", "mlle", "mrs", "ms", "me", "dr", "pr", "prof", "maître", "maitre", "docteur", "monsieur", "madame"]

    // MARK: - Pieces

    private static func id(_ kind: Kind, _ subject: String) -> String {
        ColinDismissalRow.key(kind: kind.rawValue, subject: subject)
    }

    /// What Paul set aside for this kind of line, by subject.
    private static func rows(_ dismissed: [ColinDismissalRow], of kind: Kind) -> [String: ColinDismissalRow] {
        Dictionary(dismissed.filter { $0.kind == kind.rawValue }.map { ($0.subject, $0) }, uniquingKeysWith: { $1 })
    }

    /// The threads shown, gathered by conversation: the copies named by `conversations` together, any other thread
    /// alone. In the order the first of each came.
    private static func grouped(_ threads: [MailThreadRow], _ conversations: [String: String]) -> [[MailThreadRow]] {
        var groups: [String: [MailThreadRow]] = [:]
        var order: [String] = []
        for thread in threads where !thread.hidden {
            let key = conversations[thread.id] ?? thread.id
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(thread)
        }
        return order.compactMap { groups[$0] }
    }

    /// The project of a thread: the case the mails give it; in a thread nobody but Paul wrote in, the one project
    /// of the people he wrote to. A thread he filed outside any project stays there.
    private static func project(of thread: MailThreadRow, rules: MailFilingRules, recipients: [MailAddress]) -> UUID? {
        if let filing = rules.filing(of: thread) { return filing.filing.projectID }
        guard !thread.senders.contains(where: { !rules.mine.contains($0.email.lowercased()) }) else { return nil }
        return project(of: recipients, rules: rules)
    }

    /// The one project of these people: the contacts of a project, those Paul took out of it apart. None when they
    /// are of several projects, or of none.
    private static func project(of people: [MailAddress], rules: MailFilingRules) -> UUID? {
        var found: Set<UUID> = []
        for person in people {
            let address = person.email.lowercased()
            guard !rules.mine.contains(address) else { continue }
            found.formUnion((rules.contactProjects[address] ?? []).subtracting(rules.excludedProjects[address] ?? []))
        }
        return found.count == 1 ? found.first.flatMap { id in rules.projects.contains { $0.id == id } ? id : nil } : nil
    }

    /// Who is silent: the one Paul answered, when someone wrote; else the first he wrote to.
    private static func silentPerson(of thread: MailThreadRow, rules: MailFilingRules, recipients: [MailAddress]) -> String {
        if thread.lastSender != nil { return sender(of: thread, rules: rules) }
        return recipients.first { !rules.mine.contains($0.email.lowercased()) }.map { short($0.display) } ?? ""
    }

    /// Whole days gone since `date`.
    private static func age(of date: Date, now: Date) -> Int {
        Int((now.timeIntervalSince(date) / day).rounded(.down))
    }

    /// « Pas besoin » and « Elle a répondu ailleurs » hide the line until a message newer than what Paul had
    /// before him (for a row that did not keep it: newer than his click); « Plus tard » until the next day.
    private static func isAside(_ row: ColinDismissalRow?, lastMessage: Date, now: Date, calendar: Calendar) -> Bool {
        guard let row else { return false }
        switch row.reason {
        case .notNeeded, .answeredElsewhere:
            return lastMessage <= (row.lastMessageAt ?? row.createdAt)
        case .later:
            let start = calendar.startOfDay(for: row.createdAt)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(day)
            return now < tomorrow
        }
    }

    /// Who wrote last: the name a header gave, else the one Paul's own mails gave, else the address.
    private static func sender(of thread: MailThreadRow, rules: MailFilingRules) -> String {
        guard let address = thread.lastSender?.lowercased() else { return "" }
        let named = thread.senders.first { $0.email.lowercased() == address }?.name ?? rules.correspondentStats[address]?.name
        return short(named ?? address)
    }

    private static func name(of project: UUID?, rules: MailFilingRules) -> String? {
        project.flatMap { id in rules.projects.first { $0.id == id }?.name }
    }
}
