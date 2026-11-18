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
        /// « Attend ta réponse », read by person: a message older than this no longer waits. Counted on Paul's own
        /// mails, what he has not answered in two weeks he never answers.
        public var replyMaxDays: Int

        public init(replyDays: Int = 3, silentDays: Int = 7, maxAgeDays: Int = 45, replyMaxDays: Int = 14) {
            self.replyDays = replyDays
            self.silentDays = silentDays
            self.maxAgeDays = maxAgeDays
            self.replyMaxDays = replyMaxDays
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
        /// The last message Paul has before him when the line shows: kept with the line when he sets it aside, which
        /// then hides until a newer one.
        public var lastMessageAt: Date?

        public init(id: String, kind: Kind, person: String, detail: String? = nil, days: Int? = nil, threadKey: String? = nil,
                    draftID: String? = nil, eventID: String? = nil, projectID: UUID? = nil, lastMessageAt: Date? = nil) {
            self.id = id
            self.kind = kind
            self.person = person
            self.detail = detail
            self.days = days
            self.threadKey = threadKey
            self.draftID = draftID
            self.eventID = eventID
            self.projectID = projectID
            self.lastMessageAt = lastMessageAt
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

    // MARK: - Read by person and by project

    /// « Attend ta réponse », read by person and no longer by thread (18/11). Counted on Paul's own mails, the thread
    /// alone speaks ten times too much: he answers a client in a new mail, or in a meeting. A person waits when:
    /// - a thread ends on a message of theirs, three days old or more and two weeks at most (`replies`);
    /// - Paul wrote nothing to them since, in whatever thread of whatever mailbox (`exchanges`);
    /// - that message is neither a calendar's own nor an automatic one, and they are no colleague of his;
    /// - no draft to them was begun or touched since their message (`drafts`: all of them, Paul's own and an agent's;
    ///   `gmailDrafts`: those begun in Gmail, on the phone or the web);
    /// - no meeting with them was held since, nor comes within a week (`events`).
    /// One line by person, on their oldest thread that waits, set aside by person; the oldest first. Never said from
    /// a mailbox Paul hid (`hiddenAccounts`), though what he wrote from it counts.
    public static func repliesByPerson(_ threads: [MailThreadRow], rules: MailFilingRules, conversations: [String: String] = [:], exchanges: Exchanges,
                                       drafts: [MailDraftRow] = [], gmailDrafts: [MailMessageRow] = [], events: [CalendarEventRow] = [],
                                       hiddenAccounts: Set<String> = [],
                                       dismissed: [ColinDismissalRow], now: Date,
                                       thresholds: Thresholds, calendar: Calendar = .current) -> [Line] {
        var window = thresholds
        window.maxAgeDays = thresholds.replyMaxDays
        let byKey = Dictionary(threads.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let aside = rows(dismissed, of: .reply)
        let colleagues = ownDomains(rules)
        // Who a draft is written to, and when it was last touched: a draft older than the message answers nothing.
        var writing: [String: Date] = [:]
        let begun = drafts.map { ($0.to + $0.cc, $0.updatedAt) } + gmailDrafts.map { ($0.to + $0.cc, $0.date) }
        for (people, date) in begun {
            for person in people { writing[person.email.lowercased()] = max(writing[person.email.lowercased()] ?? .distantPast, date) }
        }
        var byPerson: [String: (line: Line, last: Date)] = [:]
        var order: [String] = []
        for line in replies(threads, rules: rules, conversations: conversations, dismissed: [], now: now, thresholds: window, calendar: calendar) {
            guard let key = line.threadKey, let thread = byKey[key], let address = thread.lastSender?.lowercased(),
                  let received = thread.lastReceivedAt, !hiddenAccounts.contains(thread.account) else { continue }
            if let domain = PublicMailDomains.domain(of: address), colleagues.contains(domain) { continue }
            guard !exchanges.wrote(to: address, after: received, until: now) else { continue }
            if let last = exchanges.lastReceived(in: key, asOf: now), last.calendar || last.automatic { continue }
            guard (writing[address] ?? .distantPast) <= received, !met(address, since: received, events: events, now: now) else { continue }
            if let known = byPerson[address] {
                // Their oldest thread that waits says the line; their latest message says until when it is set aside.
                byPerson[address] = (line: (line.days ?? 0) > (known.line.days ?? 0) ? line : known.line, last: max(known.last, received))
            } else {
                order.append(address)
                byPerson[address] = (line, received)
            }
        }
        return order.compactMap { address -> Line? in
            guard let found = byPerson[address], !isAside(aside[address], lastMessage: found.last, now: now, calendar: calendar) else { return nil }
            var line = found.line
            line.id = id(.reply, address)
            // What Paul has before him: their latest message in whatever thread, even one too young yet to be said.
            // Set aside, the line stays aside until they write after it.
            line.lastMessageAt = max(found.last, exchanges.lastHeard(from: address, asOf: now) ?? found.last)
            return line
        }
        .sorted { ($0.days ?? 0, $1.id) > ($1.days ?? 0, $0.id) }
    }

    /// « Ne répond plus », read by project and no longer by thread (18/11): his clients answer in new threads. A
    /// project is silent when Paul's last mail in it is seven days old or more, and since then:
    /// - nobody wrote to him in a thread of the project, nor any of the people he wrote to (his colleagues apart), in
    ///   whatever thread; an absent mailbox's answer and a calendar's mail are nobody's;
    /// - he wrote nothing more in the project (a later mail of his starts the wait again);
    /// - no meeting of the project was held, and none is to come.
    /// One line by project, set aside by project; never for a finished one (`finished`), nor said from a mailbox
    /// Paul hid (`hiddenAccounts`). The oldest first.
    public static func silentByProject(_ threads: [MailThreadRow], rules: MailFilingRules, conversations: [String: String] = [:],
                                       recipients: [String: [MailAddress]], exchanges: Exchanges, events: [CalendarEventRow], finished: Set<UUID> = [],
                                       hiddenAccounts: Set<String> = [], dismissed: [ColinDismissalRow], now: Date, thresholds: Thresholds,
                                       calendar: Calendar = .current) -> [Line] {
        // An absent mailbox's answer, a calendar's mail after Paul's: nobody answered him. The thread is read as if
        // they had not come.
        let threads = threads.map { thread -> MailThreadRow in
            guard let received = thread.lastReceivedAt, received > (thread.lastSentAt ?? .distantPast),
                  let last = exchanges.lastReceived(in: thread.id), last.automatic || last.calendar else { return thread }
            var read = thread
            read.lastReceivedAt = exchanges.lastWritten(in: thread.id).map(\.date)
            return read
        }
        let byKey = Dictionary(threads.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let aside = rows(dismissed, of: .silent)
        let colleagues = ownDomains(rules)
        // « A répondu ailleurs », said twice of one project: Colin no longer says it of this project.
        var elsewhere: [UUID: Int] = [:]
        for row in aside.values where row.reason == .answeredElsewhere {
            if let project = row.projectID { elsewhere[project, default: 0] += max(row.times, 1) }
        }
        let quiet = Set(elsewhere.filter { $0.value >= 2 }.keys)
        // The threads where Paul wrote last, without the events nor what he set aside: both are read by project.
        var latest: [UUID: (line: Line, sent: Date)] = [:]
        for line in silent(threads, rules: rules, conversations: conversations, recipients: recipients, events: [], dismissed: [], now: now,
                           thresholds: thresholds, calendar: calendar) {
            guard let project = line.projectID, let key = line.threadKey, let thread = byKey[key], let sent = thread.lastSentAt,
                  !hiddenAccounts.contains(thread.account) else { continue }
            if let known = latest[project], known.sent >= sent { continue }
            latest[project] = (line, sent)
        }
        var lines: [Line] = []
        for (project, found) in latest {
            guard !finished.contains(project), !quiet.contains(project) else { continue }
            // Paul wrote again in the project since, or someone wrote in it: the exchange goes on in another thread.
            guard !exchanges.wrote(in: project, after: found.sent, until: now), !exchanges.heard(in: project, after: found.sent, until: now) else { continue }
            // The people Paul wrote to, his colleagues apart: they write to him every day, about everything.
            let people = (exchanges.lastSent(in: found.line.threadKey ?? "", asOf: now)?.recipients ?? []).filter { person in
                !rules.mine.contains(person) && !(PublicMailDomains.domain(of: person).map(colleagues.contains) ?? false)
            }
            guard !people.contains(where: { exchanges.heard(from: $0, after: found.sent, until: now) }) else { continue }
            // A meeting of the project, held since or to come: they speak.
            guard !events.contains(where: { $0.projectID == project && !$0.allDay && $0.startAt > found.sent }) else { continue }
            let subject = project.uuidString.lowercased()
            guard !isAside(aside[subject], lastMessage: found.sent, now: now, calendar: calendar) else { continue }
            var line = found.line
            line.id = id(.silent, subject)
            line.lastMessageAt = found.sent
            lines.append(line)
        }
        return lines.sorted { ($0.days ?? 0, $1.id) > ($1.days ?? 0, $0.id) }
    }

    /// The project of each thread that has one, as the silences read it (a thread only Paul wrote in takes the one
    /// project of the people he wrote to): what says « in a thread of the project » to `Exchanges`.
    public static func projects(of threads: [MailThreadRow], rules: MailFilingRules, recipients: [String: [MailAddress]]) -> [String: UUID] {
        var found: [String: UUID] = [:]
        for thread in threads {
            if let project = project(of: thread, rules: rules, recipients: recipients[thread.id] ?? []) { found[thread.id] = project }
        }
        return found
    }

    /// The part of a line's name after its kind: what it is set aside under (a person's address, a project, an event).
    public static func subject(of line: Line) -> String {
        String(line.id.dropFirst(line.kind.rawValue.count + 1))
    }

    /// Paul's own domains, those of everyone apart: who writes from one of them is a colleague, with whom he speaks
    /// elsewhere.
    private static func ownDomains(_ rules: MailFilingRules) -> Set<String> {
        Set(rules.mine.compactMap { PublicMailDomains.domain(of: $0) }).subtracting(PublicMailDomains.all)
    }

    /// A meeting with this person, held since `date` or to come within a week: neither a whole day, nor one Paul
    /// declined.
    private static func met(_ address: String, since date: Date, events: [CalendarEventRow], now: Date) -> Bool {
        let soon = now.addingTimeInterval(7 * day)
        return events.contains { event in
            guard !event.allDay, event.startAt > date, event.startAt <= soon, event.attendees.first(where: \.isSelf)?.response != "declined" else { return false }
            return event.attendees.contains { !$0.isSelf && $0.email.lowercased() == address }
        }
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
