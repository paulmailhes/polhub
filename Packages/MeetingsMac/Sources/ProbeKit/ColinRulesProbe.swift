import Colin
import Foundation
import Observability
import Persistence

/// The rules of « À valider », counted on the mails of the base (18/11), before the Accueil shows them: how many
/// lines « attend ta réponse » and « ne répond plus » would give today, and how many they would have given two weeks
/// ago — with what followed: did Paul answer, did the client, did Paul write again? And how many of those lines are
/// for a mail he took out of his inbox without answering. Counted a first time (0.31.2), the rules spoke ten times
/// too much: they read thread by thread, and Paul answers in a new mail. So the count also says what would be left
/// if the exchange with the person were read instead, and plays the rules again on seven past weeks. Numbers only:
/// no subject, no address, no name. No model, nothing leaves the Mac, and nothing is written in the base.
public struct ColinRulesProbe: Probe {
    private let database: @Sendable () throws -> AppDatabase
    private let now: @Sendable () -> Date

    public init(database: @escaping @Sendable () throws -> AppDatabase, now: @escaping @Sendable () -> Date = { Date() }) {
        self.database = database
        self.now = now
    }

    /// On the file of the app's base, opened to read only: the app has already brought it up to date, and the count
    /// writes nothing in it.
    public init(path: String, now: @escaping @Sendable () -> Date = { Date() }) {
        self.init(database: { try AppDatabase.readOnly(path: path) }, now: now)
    }

    public func run(_ request: ProbeRequest, trace: TraceWriter, directory: URL) async {
        // Where it stands, in a word fixed in advance: an error's own words may carry a path or a row of the base,
        // and are never written.
        var stage = "ouverture"
        do {
            let base = try database()
            stage = "agenda"
            let events = try CalendarStore(base).allEvents()
            stage = "calcul"
            for measure in try Self.count(mails: MailStore(base), events: events, now: now(), thresholds: ReviewRules.Thresholds()) {
                try? await trace.write(kind: "colin", measure)
            }
        } catch {
            try? await trace.write(kind: "colin", ColinMeasure(step: "regles-reponses", ok: false, labels: ["raison": "base illisible", "etape": stage]))
        }
    }

    /// Whether the count kept in this folder went to its end: its two steps are in its trace.
    public static func completed(in directory: URL) -> Bool {
        guard let text = try? String(contentsOf: directory.appending(path: "trace.jsonl"), encoding: .utf8) else { return false }
        return text.contains(#""step":"regles-reponses""#) && text.contains(#""step":"regles-muets""#) && !text.contains(#""raison":"base illisible""#)
    }

    /// What the design expects at most: eight replies awaited, five silences.
    static let expectedReplies = 8, expectedSilences = 5
    /// How far back the second count looks.
    static let lookBack: TimeInterval = 14 * 86_400
    /// How a calendar's own mails begin: an invitation, an answer to one. Someone Paul wrote to sends them too, and
    /// nobody expects an answer to them.
    static let calendarWords = ["invitation", "updated invitation", "accepté", "accepted", "refusé", "declined", "provisoire", "tentative",
                                "annulé", "canceled", "cancelled", "proposition de nouvel horaire", "new event", "nouvel événement"]

    private static let aDay: TimeInterval = 86_400
    /// The rules are played again on past days: every week, from two weeks ago (what followed in the two weeks after
    /// is then known) to eight.
    static let replayWeeks = 2...8
    /// What followed a line is looked at for this long.
    static let followUp: TimeInterval = 14 * 86_400

    /// The rules as they stood on a day.
    private struct Day {
        var date: Date
        var threads: [MailThreadRow]
        var byKey: [String: MailThreadRow]
        var rules: MailFilingRules
        var copies: [String: String]
    }

    /// What the exchange with its sender says of a line « attend ta réponse », on its day.
    private struct Reply {
        /// Paul wrote to the sender since, in whatever thread: answered elsewhere.
        var answered = false
        /// Paul wrote in a thread of the same project since.
        var projectAnswered = false
        /// The last message received is a calendar's own.
        var calendar = false
        /// It was written to other people too.
        var several = false
        /// The sender is of one of Paul's own domains.
        var colleague = false
        var inInbox = false
        var days = 0
        /// Paul wrote to the sender in the two weeks after that day.
        var followed = false
    }

    /// What the exchange with the people Paul wrote to says of a line « ne répond plus », on its day.
    private struct Silence {
        /// One of them wrote to Paul since, in whatever thread.
        var heard = false
        /// Someone wrote in a thread of the same project since.
        var projectHeard = false
        var days = 0
        /// One of them wrote to Paul in the two weeks after that day; Paul wrote to one of them again.
        var heardAfter = false
        var chasedAfter = false
    }

    /// The numbers of the count, and nothing else.
    public static func count(mails: MailStore, events: [CalendarEventRow], now: Date, thresholds: ReviewRules.Thresholds) throws -> [ColinMeasure] {
        let clock = ContinuousClock()
        var started = clock.now
        let threads = try mails.allThreads()
        let rules = try mails.filingRules()
        let window = Double(thresholds.maxAgeDays + 1) * aDay
        func index(_ rows: [MailThreadRow]) -> [String: MailThreadRow] {
            Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }

        // A past day: each thread with the turn and the last sender it had then, and the people Paul had written to
        // by then. What cannot be known as of then stays as it is today: the cases of the threads, their labels, and
        // what Paul threw away since. The agenda of then is not known either: its silences are counted without it.
        func state(on date: Date) throws -> Day {
            let turns = try mails.turns(asOf: date)
            let senders = try mails.lastSenders(asOf: date)
            var rulesThen = rules
            rulesThen.correspondents = try mails.correspondents(asOf: date)
            let rows = threads.map { thread in
                var copy = thread
                copy.lastReceivedAt = turns[thread.id]?.lastReceivedAt
                copy.lastSentAt = turns[thread.id]?.lastSentAt
                copy.lastSender = senders[thread.id]
                copy.paulWrote = turns[thread.id]?.lastSentAt != nil
                return copy
            }
            return Day(date: date, threads: rows, byKey: index(rows), rules: rulesThen, copies: try mails.conversations(since: date.addingTimeInterval(-window)))
        }
        // The copies of one conversation in several of Paul's boxes: its turn is read over all of them.
        let today = Day(date: now, threads: threads, byKey: index(threads), rules: rules, copies: try mails.conversations(since: now.addingTimeInterval(-window)))
        let past = try replayWeeks.map { try state(on: now.addingTimeInterval(-Double($0) * 7 * aDay)) }
        // Two weeks ago: the first of the past days.
        let then = past[0]

        // Who wrote to whom, in whatever thread: Paul answers in a new mail more often than in the thread.
        let messages = try mails.exchanges(since: (past.last?.date ?? now).addingTimeInterval(-window))
        var projects: [String: UUID] = [:]
        for thread in threads {
            if let project = rules.filing(of: thread)?.filing.projectID { projects[thread.id] = project }
        }
        let exchanges = Exchanges(messages, projects: projects)
        let ownDomains = Set(rules.mine.compactMap { PublicMailDomains.domain(of: $0) }).subtracting(PublicMailDomains.all)

        // What happened since two weeks ago, by conversation and in the thread itself.
        func conversation(_ thread: String) -> String { today.copies[thread] ?? then.copies[thread] ?? thread }
        var sentSince: Set<String> = [], receivedSince: Set<String> = []
        for thread in threads {
            if let sent = thread.lastSentAt, sent > then.date { sentSince.insert(conversation(thread.id)) }
            if let received = thread.lastReceivedAt, received > then.date { receivedSince.insert(conversation(thread.id)) }
        }
        func followed(_ lines: [ReviewRules.Line], by since: Set<String>, butNot other: Set<String> = []) -> Double {
            Double(lines.filter { line in
                guard let key = line.threadKey.map(conversation) else { return false }
                return since.contains(key) && !other.contains(key)
            }.count)
        }
        func aged(_ lines: [ReviewRules.Line], _ range: ClosedRange<Int>) -> Double {
            Double(lines.filter { range.contains($0.days ?? -1) }.count)
        }
        func with(_ change: (inout ReviewRules.Thresholds) -> Void) -> ReviewRules.Thresholds {
            var other = thresholds
            change(&other)
            return other
        }

        // « Attend ta réponse ».
        func replies(_ day: Day, _ thresholds: ReviewRules.Thresholds) -> [ReviewRules.Line] {
            ReviewRules.replies(day.threads, rules: day.rules, conversations: day.copies, dismissed: [], now: day.date, thresholds: thresholds)
        }
        func reply(_ line: ReviewRules.Line, on day: Day) -> Reply? {
            guard let key = line.threadKey, let thread = day.byKey[key], let sender = thread.lastSender?.lowercased(),
                  let received = thread.lastReceivedAt else { return nil }
            let last = exchanges.lastReceived(in: key, asOf: day.date)
            var facts = Reply()
            facts.answered = exchanges.wrote(to: sender, after: received, until: day.date)
            facts.projectAnswered = line.projectID.map { exchanges.wrote(in: $0, after: received, until: day.date) } ?? false
            facts.calendar = last?.calendar ?? false
            facts.several = (last?.recipients ?? []).contains { !rules.mine.contains($0) }
            facts.colleague = PublicMailDomains.domain(of: sender).map { ownDomains.contains($0) } ?? false
            facts.inInbox = thread.inInbox
            facts.days = line.days ?? 0
            facts.followed = exchanges.wrote(to: sender, after: day.date, until: day.date.addingTimeInterval(followUp))
            return facts
        }
        let awaited = replies(today, thresholds)
        let awaitedThen = replies(then, thresholds)
        let answers = awaited.compactMap { reply($0, on: today) }
        func kept(_ keep: (Reply) -> Bool) -> Double { Double(answers.filter(keep).count) }
        // On a healthy base every thread shown has a turn: one without betrays a count that failed after the migration.
        let withTurn = threads.filter { $0.lastReceivedAt != nil || $0.lastSentAt != nil }.count
        var numbers: [String: Double] = [
            "fils": Double(threads.count), "avecTour": Double(withTurn), "sansTour": Double(threads.count - withTurn),
            "aujourdhui": Double(awaited.count), "dansUnProjet": Double(awaited.filter { $0.projectID != nil }.count),
            "de3a7Jours": aged(awaited, 0...7), "de8a14Jours": aged(awaited, 8...14), "de15a45Jours": aged(awaited, 15...10_000),
            "ilYA14Jours": Double(awaitedThen.count), "suiviesDUneReponse": followed(awaitedThen, by: sentSince),
            // How many threads have a copy in another box, and how many of today's lines are of those.
            "copies": Double(today.copies.count), "lignesAvecCopie": Double(awaited.filter { $0.threadKey.map { today.copies[$0] != nil } ?? false }.count),
            // What Paul left in his inbox, and what he has not read: a line for a mail he archived without answering
            // may be one he already classed. Among the lines of two weeks ago he never answered, those out of the
            // inbox today.
            "dansLaBoite": Double(awaited.filter { $0.threadKey.flatMap { today.byKey[$0] }?.inInbox == true }.count),
            "nonLus": Double(awaited.filter { $0.threadKey.flatMap { today.byKey[$0] }?.unread == true }.count),
            "sansSuiteHorsBoite": Double(awaitedThen.filter { line in
                guard let key = line.threadKey, !sentSince.contains(conversation(key)) else { return false }
                return today.byKey[key]?.inInbox == false
            }.count),
            // Lines that look like a calendar's own mails, by the first words of their subject (read, never written).
            "invitations": Double(awaited.filter { line in
                guard let subject = line.threadKey.flatMap({ today.byKey[$0]?.subject.lowercased() }) else { return false }
                return calendarWords.contains(where: subject.hasPrefix)
            }.count),
            // Read by person and no longer by thread: the lines whose sender Paul wrote to since, in whatever thread;
            // those of a project he wrote in since; the calendar's own mails, by what they carry; those written to
            // several people; those of a colleague.
            "ecritDepuis": kept { $0.answered }, "projetEcritDepuis": kept { $0.projectAnswered }, "agenda": kept { $0.calendar },
            "aPlusieurs": kept { $0.several }, "collegues": kept { $0.colleague },
            // What would be left of today's lines, filter after filter.
            "resteParPersonne": kept { !$0.answered },
            "resteSansAgenda": kept { !$0.answered && !$0.calendar },
            "reste14Jours": kept { !$0.answered && !$0.calendar && $0.days <= 14 },
            "reste14JoursDansLaBoite": kept { !$0.answered && !$0.calendar && $0.days <= 14 && $0.inInbox },
            "resteDansLaBoite": kept { !$0.answered && !$0.calendar && $0.inInbox },
            "resteHorsCollegues": kept { !$0.answered && !$0.calendar && !$0.colleague },
            "resteParProjet": kept { !$0.answered && !$0.projectAnswered && !$0.calendar },
        ]
        // What other thresholds would give today.
        for days in [2, 5, 7] { numbers["seuil\(days)Jours"] = Double(replies(today, with { $0.replyDays = days }).count) }
        // The rule played again on the past days: the lines it would have shown, week after week (a line that stays
        // counts each week), and those Paul then wrote to the sender of, in the two weeks after.
        for day in past {
            for facts in replies(day, thresholds).compactMap({ reply($0, on: day) }) {
                let shown: [(String, Bool)] = [("passe", true), ("passeParPersonne", !facts.answered),
                                               ("passeSansAgenda", !facts.answered && !facts.calendar),
                                               ("passe14Jours", !facts.answered && !facts.calendar && facts.days <= 14),
                                               ("passeParProjet", !facts.answered && !facts.projectAnswered && !facts.calendar)]
                for (key, yes) in shown where yes {
                    numbers[key, default: 0] += 1
                    if facts.followed { numbers[key + "Suivies", default: 0] += 1 }
                }
            }
        }
        numbers["ms"] = milliseconds(clock.now - started)
        let first = ColinMeasure(step: "regles-reponses", ok: awaited.count <= expectedReplies && withTurn == threads.count, numbers: numbers)

        // « Ne répond plus ». Who Paul wrote to, in the threads where he wrote last on one of the days: they say the
        // project of a thread nobody else wrote in.
        started = clock.now
        var candidates: Set<String> = []
        for day in [today] + past {
            for thread in day.threads {
                guard let sent = thread.lastSentAt, sent > (thread.lastReceivedAt ?? .distantPast), sent > day.date.addingTimeInterval(-window) else { continue }
                candidates.insert(thread.id)
            }
        }
        let keys = Array(candidates)
        var recipients: [String: [MailAddress]] = [:]
        for index in stride(from: 0, to: keys.count, by: 400) {
            recipients.merge(try mails.sentRecipients(threadKeys: Array(keys[index..<min(index + 400, keys.count)]))) { first, _ in first }
        }
        func silences(_ day: Day, _ events: [CalendarEventRow], _ thresholds: ReviewRules.Thresholds) -> [ReviewRules.Line] {
            ReviewRules.silent(day.threads, rules: day.rules, conversations: day.copies, recipients: recipients, events: events, dismissed: [],
                               now: day.date, thresholds: thresholds)
        }
        func silence(_ line: ReviewRules.Line, on day: Day) -> Silence? {
            guard let key = line.threadKey, let sent = day.byKey[key]?.lastSentAt else { return nil }
            // The people of Paul's last message in the thread, as it stood that day.
            let people = (exchanges.lastSent(in: key, asOf: day.date)?.recipients ?? []).filter { !rules.mine.contains($0) }
            let until = day.date.addingTimeInterval(followUp)
            var facts = Silence()
            facts.heard = people.contains { exchanges.heard(from: $0, after: sent, until: day.date) }
            facts.projectHeard = line.projectID.map { exchanges.heard(in: $0, after: sent, until: day.date) } ?? false
            facts.days = line.days ?? 0
            facts.heardAfter = people.contains { exchanges.heard(from: $0, after: day.date, until: until) }
            facts.chasedAfter = people.contains { exchanges.wrote(to: $0, after: day.date, until: until) }
            return facts
        }
        let quiet = silences(today, events, thresholds)
        let quietThen = silences(then, [], thresholds)
        let quietFacts = quiet.compactMap { silence($0, on: today) }
        func left(_ keep: (Silence) -> Bool) -> Double { Double(quietFacts.filter(keep).count) }
        numbers = [
            "aujourdhui": Double(quiet.count), "de7a14Jours": aged(quiet, 0...14), "de15a45Jours": aged(quiet, 15...10_000),
            "ilYA14Jours": Double(quietThen.count), "suivisDUneReponse": followed(quietThen, by: receivedSince),
            // Paul wrote again and nobody answered: a chase. When the client answered, it is counted above only.
            "suivisDUneRelance": followed(quietThen, by: sentSince, butNot: receivedSince),
            // Today's silences in a thread nobody but Paul wrote in.
            "commencesParPaul": Double(quiet.filter { $0.threadKey.flatMap { today.byKey[$0] }?.lastReceivedAt == nil }.count),
            // Read by person: the lines where someone Paul wrote to has written since, in whatever thread; those of
            // a project that has written since; and what would be left.
            "ontEcritDepuis": left { $0.heard }, "projetAEcritDepuis": left { $0.projectHeard },
            "resteParPersonne": left { !$0.heard }, "resteParProjet": left { !$0.heard && !$0.projectHeard },
            "resteParPersonne14Jours": left { !$0.heard && $0.days <= 14 },
        ]
        for days in [5, 10, 14] { numbers["seuil\(days)Jours"] = Double(silences(today, events, with { $0.silentDays = days }).count) }
        // Played again on the past days: the lines shown, those followed by a word of the client in the two weeks
        // after, those followed by a word of Paul.
        for day in past {
            for facts in silences(day, [], thresholds).compactMap({ silence($0, on: day) }) {
                let shown: [(String, Bool)] = [("passe", true), ("passeParPersonne", !facts.heard), ("passeParProjet", !facts.heard && !facts.projectHeard)]
                for (key, yes) in shown where yes {
                    numbers[key, default: 0] += 1
                    if facts.heardAfter { numbers[key + "SuiviesReponse", default: 0] += 1 }
                    if facts.chasedAfter { numbers[key + "SuiviesRelance", default: 0] += 1 }
                }
            }
        }
        numbers["ms"] = milliseconds(clock.now - started)
        return [first, ColinMeasure(step: "regles-muets", ok: quiet.count <= expectedSilences, numbers: numbers)]
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let value = Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
        return (value * 10).rounded() / 10
    }
}
