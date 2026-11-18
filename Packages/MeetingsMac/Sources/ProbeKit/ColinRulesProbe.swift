import Colin
import Foundation
import Observability
import Persistence

/// The rules of « À valider », counted on the mails of the base (18/11), before the Accueil shows them: how many
/// lines « attend ta réponse » and « ne répond plus » would give today, and how many they would have given two weeks
/// ago — with what followed: did Paul answer, did the client, did Paul write again? Numbers only: no subject, no
/// address, no name. No model, nothing leaves the Mac, and nothing is written in the base.
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

    /// The numbers of the count, and nothing else.
    public static func count(mails: MailStore, events: [CalendarEventRow], now: Date, thresholds: ReviewRules.Thresholds) throws -> [ColinMeasure] {
        let clock = ContinuousClock()
        var started = clock.now
        let threads = try mails.allThreads()
        let rules = try mails.filingRules()
        let window = Double(thresholds.maxAgeDays + 1) * 86_400
        // The copies of one conversation in several of Paul's boxes: its turn is read over all of them.
        let conversations = try mails.conversations(since: now.addingTimeInterval(-window))

        // Two weeks ago: each thread with the turn and the last sender it had then, and the people Paul had written
        // to by then. What cannot be known as of then stays as it is today: the cases of the threads, and what Paul
        // threw away since. The agenda of then is not known either: the silences of then are counted without it.
        let then = now.addingTimeInterval(-lookBack)
        let turns = try mails.turns(asOf: then)
        let senders = try mails.lastSenders(asOf: then)
        var rulesThen = rules
        rulesThen.correspondents = try mails.correspondents(asOf: then)
        let conversationsThen = try mails.conversations(since: then.addingTimeInterval(-window))
        let before = threads.map { thread in
            var copy = thread
            copy.lastReceivedAt = turns[thread.id]?.lastReceivedAt
            copy.lastSentAt = turns[thread.id]?.lastSentAt
            copy.lastSender = senders[thread.id]
            copy.paulWrote = turns[thread.id]?.lastSentAt != nil
            return copy
        }

        // What happened since, by conversation: an answer may have left from another of Paul's boxes.
        func conversation(_ thread: String) -> String { conversations[thread] ?? conversationsThen[thread] ?? thread }
        var sentSince: Set<String> = [], receivedSince: Set<String> = []
        for thread in threads {
            if let sent = thread.lastSentAt, sent > then { sentSince.insert(conversation(thread.id)) }
            if let received = thread.lastReceivedAt, received > then { receivedSince.insert(conversation(thread.id)) }
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
        let byKey = Dictionary(threads.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // « Attend ta réponse ».
        func replies(_ rows: [MailThreadRow], _ rules: MailFilingRules, _ copies: [String: String], at date: Date,
                     _ thresholds: ReviewRules.Thresholds) -> [ReviewRules.Line] {
            ReviewRules.replies(rows, rules: rules, conversations: copies, dismissed: [], now: date, thresholds: thresholds)
        }
        let awaited = replies(threads, rules, conversations, at: now, thresholds)
        let awaitedThen = replies(before, rulesThen, conversationsThen, at: then, thresholds)
        // On a healthy base every thread shown has a turn: one without betrays a count that failed after the migration.
        let withTurn = threads.filter { $0.lastReceivedAt != nil || $0.lastSentAt != nil }.count
        var numbers: [String: Double] = [
            "fils": Double(threads.count), "avecTour": Double(withTurn), "sansTour": Double(threads.count - withTurn),
            "aujourdhui": Double(awaited.count), "dansUnProjet": Double(awaited.filter { $0.projectID != nil }.count),
            "de3a7Jours": aged(awaited, 0...7), "de8a14Jours": aged(awaited, 8...14), "de15a45Jours": aged(awaited, 15...10_000),
            "ilYA14Jours": Double(awaitedThen.count), "suiviesDUneReponse": followed(awaitedThen, by: sentSince),
            // How many threads have a copy in another box, and how many of today's lines are of those.
            "copies": Double(conversations.count), "lignesAvecCopie": Double(awaited.filter { $0.threadKey.map { conversations[$0] != nil } ?? false }.count),
            // Lines that look like a calendar's own mails, by the first words of their subject (read, never written).
            "invitations": Double(awaited.filter { line in
                guard let subject = line.threadKey.flatMap({ byKey[$0]?.subject.lowercased() }) else { return false }
                return calendarWords.contains(where: subject.hasPrefix)
            }.count),
        ]
        // What other thresholds would give today.
        for days in [2, 5, 7] { numbers["seuil\(days)Jours"] = Double(replies(threads, rules, conversations, at: now, with { $0.replyDays = days }).count) }
        numbers["ms"] = milliseconds(clock.now - started)
        let first = ColinMeasure(step: "regles-reponses", ok: awaited.count <= expectedReplies && withTurn == threads.count, numbers: numbers)

        // « Ne répond plus ». Who Paul wrote to, in the threads where he wrote last: they say the project of a thread
        // nobody else wrote in.
        started = clock.now
        func wroteLast(_ thread: MailThreadRow) -> Bool { (thread.lastSentAt ?? .distantPast) > (thread.lastReceivedAt ?? .distantPast) }
        let candidates = Array(Set((threads.filter(wroteLast) + before.filter(wroteLast)).map(\.id)))
        var recipients: [String: [MailAddress]] = [:]
        for index in stride(from: 0, to: candidates.count, by: 400) {
            recipients.merge(try mails.sentRecipients(threadKeys: Array(candidates[index..<min(index + 400, candidates.count)]))) { first, _ in first }
        }
        func silences(_ rows: [MailThreadRow], _ rules: MailFilingRules, _ copies: [String: String], _ events: [CalendarEventRow], at date: Date,
                      _ thresholds: ReviewRules.Thresholds) -> [ReviewRules.Line] {
            ReviewRules.silent(rows, rules: rules, conversations: copies, recipients: recipients, events: events, dismissed: [], now: date, thresholds: thresholds)
        }
        let quiet = silences(threads, rules, conversations, events, at: now, thresholds)
        let quietThen = silences(before, rulesThen, conversationsThen, [], at: then, thresholds)
        numbers = [
            "aujourdhui": Double(quiet.count), "de7a14Jours": aged(quiet, 0...14), "de15a45Jours": aged(quiet, 15...10_000),
            "ilYA14Jours": Double(quietThen.count), "suivisDUneReponse": followed(quietThen, by: receivedSince),
            // Paul wrote again and nobody answered: a chase. When the client answered, it is counted above only.
            "suivisDUneRelance": followed(quietThen, by: sentSince, butNot: receivedSince),
            // Today's silences in a thread nobody but Paul wrote in.
            "commencesParPaul": Double(quiet.filter { $0.threadKey.flatMap { byKey[$0] }?.lastReceivedAt == nil }.count),
        ]
        for days in [5, 10, 14] {
            numbers["seuil\(days)Jours"] = Double(silences(threads, rules, conversations, events, at: now, with { $0.silentDays = days }).count)
        }
        numbers["ms"] = milliseconds(clock.now - started)
        return [first, ColinMeasure(step: "regles-muets", ok: quiet.count <= expectedSilences, numbers: numbers)]
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let value = Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
        return (value * 10).rounded() / 10
    }
}
