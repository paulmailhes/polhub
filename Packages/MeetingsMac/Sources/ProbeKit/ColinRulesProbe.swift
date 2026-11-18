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

    public func run(_ request: ProbeRequest, trace: TraceWriter, directory: URL) async {
        do {
            let base = try database()
            let events = try CalendarStore(base).allEvents()
            for measure in try Self.count(mails: MailStore(base), events: events, now: now(), thresholds: ReviewRules.Thresholds()) {
                try? await trace.write(kind: "colin", measure)
            }
        } catch {
            // Why is never written: an error's own words may carry a path.
            try? await trace.write(kind: "colin", ColinMeasure(step: "regles-reponses", ok: false, labels: ["raison": "base illisible"]))
        }
    }

    /// What the design expects at most: eight replies awaited, five silences.
    static let expectedReplies = 8, expectedSilences = 5
    /// How far back the second count looks.
    static let lookBack: TimeInterval = 14 * 86_400

    /// The numbers of the count, and nothing else.
    public static func count(mails: MailStore, events: [CalendarEventRow], now: Date, thresholds: ReviewRules.Thresholds) throws -> [ColinMeasure] {
        let clock = ContinuousClock()
        var started = clock.now
        let threads = try mails.allThreads()
        let rules = try mails.filingRules()
        // The threads as they stood two weeks ago: the same rows, with the turn they had then.
        let then = now.addingTimeInterval(-lookBack)
        let turns = try mails.turns(asOf: then)
        let before = threads.map { thread in
            var copy = thread
            copy.lastReceivedAt = turns[thread.id]?.lastReceivedAt
            copy.lastSentAt = turns[thread.id]?.lastSentAt
            return copy
        }
        // What happened since, by subject: a reply may have left from another of Paul's boxes.
        var sentSince: Set<String> = [], receivedSince: Set<String> = []
        for thread in threads {
            if let sent = thread.lastSentAt, sent > then { sentSince.insert(thread.subject) }
            if let received = thread.lastReceivedAt, received > then { receivedSince.insert(thread.subject) }
        }
        let subjects = Dictionary(threads.map { ($0.id, $0.subject) }, uniquingKeysWith: { first, _ in first })
        func followed(_ lines: [ReviewRules.Line], by subjectsSince: Set<String>) -> Int {
            lines.filter { line in line.threadKey.flatMap { subjects[$0] }.map(subjectsSince.contains) ?? false }.count
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
        func replies(_ rows: [MailThreadRow], at date: Date, _ thresholds: ReviewRules.Thresholds) -> [ReviewRules.Line] {
            ReviewRules.replies(rows, rules: rules, dismissed: [], now: date, thresholds: thresholds)
        }
        let awaited = replies(threads, at: now, thresholds)
        let awaitedThen = replies(before, at: then, thresholds)
        var numbers: [String: Double] = [
            "fils": Double(threads.count),
            // A base whose turns could not be counted at the migration shows here: threads, and none with a turn.
            "avecTour": Double(threads.filter { $0.lastReceivedAt != nil || $0.lastSentAt != nil }.count),
            "aujourdhui": Double(awaited.count), "dansUnProjet": Double(awaited.filter { $0.projectID != nil }.count),
            "de3a7Jours": aged(awaited, 0...7), "de8a14Jours": aged(awaited, 8...14), "de15a45Jours": aged(awaited, 15...10_000),
            "ilYA14Jours": Double(awaitedThen.count), "suiviesDUneReponse": Double(followed(awaitedThen, by: sentSince)),
        ]
        // What other thresholds would give today.
        for days in [2, 5, 7] { numbers["seuil\(days)Jours"] = Double(replies(threads, at: now, with { $0.replyDays = days }).count) }
        numbers["ms"] = milliseconds(clock.now - started)
        let first = ColinMeasure(step: "regles-reponses", ok: awaited.count <= expectedReplies, numbers: numbers)

        // « Ne répond plus ». The people's names are not needed to count.
        started = clock.now
        func silences(_ rows: [MailThreadRow], at date: Date, _ thresholds: ReviewRules.Thresholds) -> [ReviewRules.Line] {
            ReviewRules.silent(rows, rules: rules, recipients: [:], events: events, dismissed: [], now: date, thresholds: thresholds)
        }
        let quiet = silences(threads, at: now, thresholds)
        let quietThen = silences(before, at: then, thresholds)
        numbers = [
            "aujourdhui": Double(quiet.count), "de7a14Jours": aged(quiet, 0...14), "de15a45Jours": aged(quiet, 15...10_000),
            "ilYA14Jours": Double(quietThen.count), "suivisDUneReponse": Double(followed(quietThen, by: receivedSince)),
            "suivisDUneRelance": Double(followed(quietThen, by: sentSince)),
        ]
        for days in [5, 10, 14] { numbers["seuil\(days)Jours"] = Double(silences(threads, at: now, with { $0.silentDays = days }).count) }
        numbers["ms"] = milliseconds(clock.now - started)
        return [first, ColinMeasure(step: "regles-muets", ok: quiet.count <= expectedSilences, numbers: numbers)]
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let value = Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
        return (value * 10).rounded() / 10
    }
}
