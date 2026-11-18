import Colin
import Domain
import Foundation
import Observability
import Persistence
import Testing
@testable import ProbeKit

/// The rules of « À valider », counted on the mails of the base (18/11): today, and as they stood two weeks ago.
/// Numbers only. Every name, address and subject here is invented.
@Suite struct ColinRulesProbeTests {
    static let me = "moi@exemple.fr", marc = "marc@exemple.net", claire = "claire@cabinet.exemple"
    /// Wednesday 18/11/2026, 10:00 in Paris.
    let now = Date(timeIntervalSince1970: 1_794_992_400)
    let thresholds = ReviewRules.Thresholds()

    func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    /// A base with one mailbox and one project.
    func base() throws -> (database: AppDatabase, mails: MailStore, project: UUID) {
        let database = try AppDatabase.inMemory()
        try CalendarStore(database).addAccount(email: Self.me, at: ago(400))
        let project = try ProjectStore(database).addProject(name: "Cabinet Martin", status: .priorite2, at: ago(100))
        return (database, MailStore(database), project.id)
    }

    func received(_ id: String, thread: String, from: String, daysAgo: Double, subject: String) -> MailMessageRow {
        MailMessageRow(account: Self.me, messageID: id, threadID: thread, date: ago(daysAgo), sender: MailAddress(name: "Quelqu'un Exemple", email: from),
                       to: [MailAddress(email: Self.me)], subject: subject, snippet: "extrait secret", labels: ["INBOX", "CATEGORY_PERSONAL"])
    }

    func sent(_ id: String, thread: String, to: String, daysAgo: Double, subject: String) -> MailMessageRow {
        MailMessageRow(account: Self.me, messageID: id, threadID: thread, date: ago(daysAgo), sender: MailAddress(name: "Moi", email: Self.me),
                       to: [MailAddress(email: to)], subject: subject, snippet: "extrait secret", labels: ["SENT"])
    }

    func key(_ thread: String) -> String { MailThreadRow.key(account: Self.me, threadID: thread) }

    func step(_ name: String, _ measures: [ColinMeasure]) -> ColinMeasure? { measures.first { $0.step == name } }

    @Test func theCountsOfTodayAndOfTwoWeeksAgo() throws {
        let (_, mails, _) = try base()
        try mails.apply(account: Self.me, upserts: [
            // Paul wrote to Marc long ago; Marc wrote four days ago: it waits today.
            sent("a1", thread: "a", to: Self.marc, daysAgo: 60, subject: "Maquette"),
            received("a2", thread: "a", from: Self.marc, daysAgo: 4, subject: "Maquette"),
            // Marc wrote eighteen days ago; Paul answered ten days ago: it waited two weeks ago, and he answered since.
            received("b1", thread: "b", from: Self.marc, daysAgo: 18, subject: "Devis"),
            sent("b2", thread: "b", to: Self.marc, daysAgo: 10, subject: "Devis"),
            // Someone Paul never wrote to: never counted.
            received("c1", thread: "c", from: "inconnu@exemple.org", daysAgo: 5, subject: "Bonjour"),
        ])
        let measures = try ColinRulesProbe.count(mails: mails, events: [], now: now, thresholds: thresholds)
        #expect(measures.map(\.step) == ["regles-reponses", "regles-muets"])
        let replies = try #require(step("regles-reponses", measures))
        #expect(replies.ok)
        #expect(replies.numbers["fils"] == 3)
        #expect(replies.numbers["avecTour"] == 3)
        #expect(replies.numbers["aujourdhui"] == 1)
        #expect(replies.numbers["dansUnProjet"] == 0)
        #expect(replies.numbers["de3a7Jours"] == 1 && replies.numbers["de8a14Jours"] == 0 && replies.numbers["de15a45Jours"] == 0)
        #expect(replies.numbers["ilYA14Jours"] == 1)
        #expect(replies.numbers["suiviesDUneReponse"] == 1)
        // What other thresholds would give today: after 2 days, the same thread; after 5 or 7, none.
        #expect(replies.numbers["seuil2Jours"] == 1 && replies.numbers["seuil5Jours"] == 0 && replies.numbers["seuil7Jours"] == 0)
        #expect(replies.numbers["ms"] != nil)
        #expect(replies.labels.isEmpty)
    }

    @Test func aSilentClientWhoAnsweredSinceIsCounted() throws {
        let (_, mails, project) = try base()
        try mails.apply(account: Self.me, upserts: [
            // Paul wrote 25 days ago: silent two weeks ago. Claire answered five days ago.
            received("a1", thread: "a", from: Self.claire, daysAgo: 40, subject: "Plans"),
            sent("a2", thread: "a", to: Self.claire, daysAgo: 25, subject: "Plans"),
            received("a3", thread: "a", from: Self.claire, daysAgo: 5, subject: "Plans"),
            // Paul wrote 30 days ago: silent two weeks ago. He wrote again three days ago.
            sent("b1", thread: "b", to: Self.claire, daysAgo: 30, subject: "Devis"),
            sent("b2", thread: "b", to: Self.claire, daysAgo: 3, subject: "Devis"),
            // Paul wrote nine days ago, and nothing since: silent today.
            received("c1", thread: "c", from: Self.claire, daysAgo: 12, subject: "Logo"),
            sent("c2", thread: "c", to: Self.claire, daysAgo: 9, subject: "Logo"),
            // The same silence outside any project is never counted.
            sent("d1", thread: "d", to: Self.marc, daysAgo: 9, subject: "Autre"),
        ])
        for thread in ["a", "b", "c"] { try mails.file(threadKey: key(thread), as: .project(project), at: ago(50)) }
        let measures = try ColinRulesProbe.count(mails: mails, events: [], now: now, thresholds: thresholds)
        let silent = try #require(step("regles-muets", measures))
        #expect(silent.ok)
        #expect(silent.numbers["aujourdhui"] == 1)
        #expect(silent.numbers["de7a14Jours"] == 1 && silent.numbers["de15a45Jours"] == 0)
        #expect(silent.numbers["ilYA14Jours"] == 2)
        #expect(silent.numbers["suivisDUneReponse"] == 1)
        #expect(silent.numbers["suivisDUneRelance"] == 1)
        #expect(silent.numbers["seuil5Jours"] == 1 && silent.numbers["seuil10Jours"] == 0 && silent.numbers["seuil14Jours"] == 0)
        // A coming event of the project hides today's silence, as on the Accueil.
        let coming = CalendarEventRow(account: Self.me, eventID: "e1", title: "Point", startAt: now.addingTimeInterval(86_400), endAt: now.addingTimeInterval(90_000),
                                      projectID: project, updatedAt: now)
        let hidden = try ColinRulesProbe.count(mails: mails, events: [coming], now: now, thresholds: thresholds)
        #expect(step("regles-muets", hidden)?.numbers["aujourdhui"] == 0)
    }

    @Test func moreLinesThanTheDesignExpectsIsSaid() throws {
        // Nine threads wait: more than the eight the design expects.
        let (_, mails, _) = try base()
        var messages = [sent("s", thread: "ancien", to: Self.marc, daysAgo: 60, subject: "Avant")]
        for index in 0..<9 { messages.append(received("m\(index)", thread: "t\(index)", from: Self.marc, daysAgo: 4 + Double(index), subject: "Sujet \(index)")) }
        try mails.apply(account: Self.me, upserts: messages)
        let replies = try #require(step("regles-reponses", try ColinRulesProbe.count(mails: mails, events: [], now: now, thresholds: thresholds)))
        #expect(replies.numbers["aujourdhui"] == 9)
        #expect(!replies.ok)
        #expect(replies.numbers["de3a7Jours"] == 4 && replies.numbers["de8a14Jours"] == 5)
    }

    @Test func theTraceCarriesNoSubjectNorAddress() async throws {
        let (database, mails, project) = try base()
        try mails.apply(account: Self.me, upserts: [
            sent("a1", thread: "a", to: Self.marc, daysAgo: 60, subject: "Maquette confidentielle"),
            received("a2", thread: "a", from: Self.marc, daysAgo: 4, subject: "Maquette confidentielle"),
            received("b1", thread: "b", from: Self.claire, daysAgo: 12, subject: "Logo confidentiel"),
            sent("b2", thread: "b", to: Self.claire, daysAgo: 9, subject: "Logo confidentiel"),
        ])
        try mails.file(threadKey: key("b"), as: .project(project), at: ago(50))
        let directory = FileManager.default.temporaryDirectory.appending(path: "colin-regles-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let trace = try TraceWriter(fileURL: directory.appending(path: "trace.jsonl"))
        let fixed = now
        await ColinRulesProbe(database: { database }, now: { fixed }).run(ProbeRequest(probe: .colinRules), trace: trace, directory: directory)
        await trace.close()
        let text = try String(contentsOf: directory.appending(path: "trace.jsonl"), encoding: .utf8)
        #expect(text.contains("regles-reponses") && text.contains("regles-muets"))
        for word in ["exemple", "confidenti", "Maquette", "Logo", "Cabinet", "Martin", "Quelqu", "secret", "marc", "claire"] {
            #expect(!text.contains(word), "\(word)")
        }
        // Only the trace: nothing else is written beside it.
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) == ["trace.jsonl"])
    }

    @Test func aBaseThatCannotBeReadIsSaidAndNothingElse() async throws {
        struct Shut: Error {}
        let directory = FileManager.default.temporaryDirectory.appending(path: "colin-regles-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let trace = try TraceWriter(fileURL: directory.appending(path: "trace.jsonl"))
        await ColinRulesProbe(database: { throw Shut() }).run(ProbeRequest(probe: .colinRules), trace: trace, directory: directory)
        await trace.close()
        let text = try String(contentsOf: directory.appending(path: "trace.jsonl"), encoding: .utf8)
        #expect(text.contains(#""raison":"base illisible""#) && text.contains(#""ok":false"#))
    }

    @Test func theProbeIsInTheRegistryAndInTheWindow() async {
        #expect(ProbeID.colinRules.rawValue == "colin-regles")
        #expect(ProbeID.colinRules.title == "Colin : les règles sur tes mails")
        #expect(ProbeID.listed.contains(.colinRules))
        #expect(await ProbeRegistry.make(.colinRules) != nil)
        #expect(LaunchArguments.parse(["Polhub", "--probe", "colin-regles"])?.probe == .colinRules)
    }
}
