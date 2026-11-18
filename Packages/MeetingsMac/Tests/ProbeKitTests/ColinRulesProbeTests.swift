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

    func received(_ id: String, thread: String, from: String, daysAgo: Double, subject: String, box: String = me, identifier: String? = nil,
                  labels: [String] = ["INBOX", "CATEGORY_PERSONAL"]) -> MailMessageRow {
        MailMessageRow(account: box, messageID: id, threadID: thread, date: ago(daysAgo), sender: MailAddress(name: "Quelqu'un Exemple", email: from),
                       to: [MailAddress(email: box)], subject: subject, snippet: "extrait secret", labels: labels, rfcMessageID: identifier)
    }

    func sent(_ id: String, thread: String, to: String, daysAgo: Double, subject: String, box: String = me) -> MailMessageRow {
        MailMessageRow(account: box, messageID: id, threadID: thread, date: ago(daysAgo), sender: MailAddress(name: "Moi", email: box),
                       to: [MailAddress(email: to)], subject: subject, snippet: "extrait secret", labels: ["SENT"])
    }

    func key(_ thread: String, box: String = me) -> String { MailThreadRow.key(account: box, threadID: thread) }

    func count(_ mails: MailStore, events: [CalendarEventRow] = []) throws -> (replies: ColinMeasure, silent: ColinMeasure) {
        let measures = try ColinRulesProbe.count(mails: mails, events: events, now: now, thresholds: thresholds)
        return (try #require(step("regles-reponses", measures)), try #require(step("regles-muets", measures)))
    }

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
        #expect(replies.numbers["avecTour"] == 3 && replies.numbers["sansTour"] == 0)
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

    @Test func twoWeeksAgoIsJudgedAsItStoodThen() throws {
        let (_, mails, _) = try base()
        try mails.apply(account: Self.me, upserts: [
            // A stranger wrote 20 days ago; Paul first answered him 12 days ago. Two weeks ago he was still a stranger:
            // the rule said nothing then.
            received("x1", thread: "x", from: "nouveau@exemple.org", daysAgo: 20, subject: "Bonjour"),
            sent("x2", thread: "x", to: "nouveau@exemple.org", daysAgo: 12, subject: "Bonjour"),
            // Paul had written to Marc long ago.
            sent("s", thread: "ancien", to: Self.marc, daysAgo: 90, subject: "Avant"),
            // Received 15 days ago, unanswered: one day old two weeks ago (no line then), a line today.
            received("y1", thread: "y", from: Self.marc, daysAgo: 15, subject: "Récent"),
            // Received 50 days ago, unanswered: a line two weeks ago, too old today.
            received("z1", thread: "z", from: Self.marc, daysAgo: 50, subject: "Vieux"),
            // The last to write two weeks ago was Marc; since then a stranger wrote in the same thread.
            received("w1", thread: "w", from: Self.marc, daysAgo: 19, subject: "Suite"),
            received("w2", thread: "w", from: "inconnu@exemple.org", daysAgo: 2, subject: "Suite"),
        ])
        let (replies, _) = try count(mails)
        #expect(replies.numbers["ilYA14Jours"] == 2)
        #expect(replies.numbers["suiviesDUneReponse"] == 0)
        #expect(replies.numbers["aujourdhui"] == 1)
        #expect(replies.numbers["de15a45Jours"] == 1)
    }

    @Test func anAnswerFromAnotherBoxFollowsTheLine() throws {
        // Marc wrote to both of Paul's addresses 18 days ago; Paul answered from the second box 10 days ago. The two
        // threads are copies of one conversation, known by the mail's identifier.
        let (database, mails, _) = try base()
        let second = "moi@atelier.exemple"
        try CalendarStore(database).addAccount(email: second, at: ago(400))
        try mails.apply(account: Self.me, upserts: [
            sent("s", thread: "ancien", to: Self.marc, daysAgo: 90, subject: "Avant"),
            received("a1", thread: "a", from: Self.marc, daysAgo: 18, subject: "Devis", identifier: "<devis-1@exemple.net>"),
        ])
        try mails.apply(account: second, upserts: [
            received("b1", thread: "b", from: Self.marc, daysAgo: 18, subject: "Devis", box: second, identifier: "<devis-1@exemple.net>"),
            sent("b2", thread: "b", to: Self.marc, daysAgo: 10, subject: "Re: Devis", box: second),
        ])
        let (replies, _) = try count(mails)
        // One conversation: one line two weeks ago, answered since; nothing waits today, in either box.
        #expect(replies.numbers["ilYA14Jours"] == 1)
        #expect(replies.numbers["suiviesDUneReponse"] == 1)
        #expect(replies.numbers["aujourdhui"] == 0)
        #expect(replies.numbers["copies"] == 2)
    }

    @Test func theLinesAreSortedByAgeAndByProject() throws {
        let (database, mails, project) = try base()
        let claire = try ContactStore(database).upsert(email: Self.claire, name: "Claire Morel", company: nil, at: ago(100))
        try ContactStore(database).link(contactID: claire.id, projectID: project, origin: .paul, at: ago(100))
        try mails.apply(account: Self.me, upserts: [
            sent("s1", thread: "ancien", to: Self.marc, daysAgo: 90, subject: "Avant"),
            sent("s2", thread: "ancien2", to: Self.claire, daysAgo: 90, subject: "Avant aussi"),
            received("a1", thread: "a", from: Self.marc, daysAgo: 20, subject: "Vingt jours"),
            received("b1", thread: "b", from: Self.claire, daysAgo: 5, subject: "Dans un projet"),
            // An invitation sent by someone Paul wrote to: counted, and counted apart.
            received("c1", thread: "c", from: Self.marc, daysAgo: 4, subject: "Invitation : Point jeudi"),
        ])
        let (replies, silent) = try count(mails)
        #expect(replies.numbers["aujourdhui"] == 3)
        #expect(replies.numbers["de3a7Jours"] == 2 && replies.numbers["de15a45Jours"] == 1)
        #expect(replies.numbers["dansUnProjet"] == 1)
        #expect(replies.numbers["invitations"] == 1)
        // Paul's old mail to Claire, which she never answered, is a silence of her project even though nobody else
        // wrote in that thread; too old today, it was one two weeks ago... beyond the ceiling too: nothing.
        #expect(silent.numbers["aujourdhui"] == 0 && silent.numbers["commencesParPaul"] == 0)
    }

    @Test func aMailPaulStartedIsCountedAmongTheSilences() throws {
        let (database, mails, project) = try base()
        let claire = try ContactStore(database).upsert(email: Self.claire, name: "Claire Morel", company: nil, at: ago(100))
        try ContactStore(database).link(contactID: claire.id, projectID: project, origin: .paul, at: ago(100))
        try mails.apply(account: Self.me, upserts: [sent("s1", thread: "a", to: Self.claire, daysAgo: 9, subject: "Devis")])
        let (_, silent) = try count(mails)
        #expect(silent.numbers["aujourdhui"] == 1)
        #expect(silent.numbers["commencesParPaul"] == 1)
    }

    @Test func sixSilencesAreMoreThanTheDesignExpects() throws {
        let (_, mails, project) = try base()
        var messages: [MailMessageRow] = []
        for index in 0..<6 {
            messages.append(received("r\(index)", thread: "t\(index)", from: Self.claire, daysAgo: 30, subject: "Sujet \(index)"))
            messages.append(sent("s\(index)", thread: "t\(index)", to: Self.claire, daysAgo: 8 + Double(index), subject: "Sujet \(index)"))
        }
        try mails.apply(account: Self.me, upserts: messages)
        for index in 0..<6 { try mails.file(threadKey: key("t\(index)"), as: .project(project), at: ago(50)) }
        let (replies, silent) = try count(mails)
        #expect(silent.numbers["aujourdhui"] == 6)
        #expect(!silent.ok)
        #expect(silent.numbers["de7a14Jours"] == 6 && silent.numbers["de15a45Jours"] == 0)
        #expect(replies.ok)
    }

    @Test func aChaseIsNotAnAnswer() throws {
        // Silent two weeks ago in both threads. In the first the client answered, then Paul replied: an answer, not a
        // chase. In the second Paul wrote again and nobody answered: a chase.
        let (_, mails, project) = try base()
        try mails.apply(account: Self.me, upserts: [
            sent("a1", thread: "a", to: Self.claire, daysAgo: 30, subject: "Plans"),
            received("a2", thread: "a", from: Self.claire, daysAgo: 10, subject: "Plans"),
            sent("a3", thread: "a", to: Self.claire, daysAgo: 9, subject: "Plans"),
            sent("b1", thread: "b", to: Self.claire, daysAgo: 30, subject: "Devis"),
            sent("b2", thread: "b", to: Self.claire, daysAgo: 3, subject: "Devis"),
        ])
        for thread in ["a", "b"] { try mails.file(threadKey: key(thread), as: .project(project), at: ago(50)) }
        let (_, silent) = try count(mails)
        #expect(silent.numbers["ilYA14Jours"] == 2)
        #expect(silent.numbers["suivisDUneReponse"] == 1)
        #expect(silent.numbers["suivisDUneRelance"] == 1)
    }

    @Test func threadsWithoutATurnAreSaidAndAreNotFine() throws {
        // A base whose turns could not be counted after the migration: threads, and none with a turn.
        let (database, mails, _) = try base()
        try mails.apply(account: Self.me, upserts: [
            sent("s", thread: "ancien", to: Self.marc, daysAgo: 90, subject: "Avant"),
            received("a1", thread: "a", from: Self.marc, daysAgo: 4, subject: "Maquette"),
        ])
        try database.writer.write { try $0.execute(sql: "UPDATE mail_thread SET lastReceivedAt = NULL, lastSentAt = NULL") }
        let (replies, _) = try count(mails)
        #expect(replies.numbers["fils"] == 2 && replies.numbers["avecTour"] == 0 && replies.numbers["sansTour"] == 2)
        #expect(replies.numbers["aujourdhui"] == 0)
        #expect(!replies.ok)
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
        // Numbers under names fixed in advance, and no label at all: nothing of the base can ride along.
        struct Line: Decodable { let kind: String; let data: ColinMeasure }
        let measures = try text.split(separator: "\n").map { try JSONDecoder().decode(Line.self, from: Data($0.utf8)).data }
        #expect(measures.map(\.step) == ["regles-reponses", "regles-muets"])
        let known: Set<String> = ["fils", "avecTour", "sansTour", "aujourdhui", "dansUnProjet", "de3a7Jours", "de8a14Jours", "de15a45Jours", "ilYA14Jours",
                                  "suiviesDUneReponse", "seuil2Jours", "seuil5Jours", "seuil7Jours", "copies", "lignesAvecCopie", "invitations", "ms",
                                  "de7a14Jours", "suivisDUneReponse", "suivisDUneRelance", "seuil10Jours", "seuil14Jours", "commencesParPaul"]
        for measure in measures {
            #expect(measure.labels.isEmpty, "\(measure.step)")
            #expect(Set(measure.numbers.keys).isSubset(of: known), "\(measure.step) : \(Set(measure.numbers.keys).subtracting(known))")
        }
        #expect(ColinRulesProbe.completed(in: directory))
        // Only the trace: nothing else is written beside it.
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) == ["trace.jsonl"])
    }

    @Test func aBaseThatCannotBeReadIsSaidAndNothingElse() async throws {
        // An error's own words may carry a path, or a whole row of the base: none of them is written.
        struct Shut: Error, CustomStringConvertible {
            var description: String { "/Users/essai-de-sonde/Polhub.sqlite : row: [subject:\"Maquette confidentielle\"]" }
        }
        let directory = FileManager.default.temporaryDirectory.appending(path: "colin-regles-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let trace = try TraceWriter(fileURL: directory.appending(path: "trace.jsonl"))
        await ColinRulesProbe(database: { throw Shut() }).run(ProbeRequest(probe: .colinRules), trace: trace, directory: directory)
        await trace.close()
        struct Line: Decodable { let kind: String; let data: ColinMeasure }
        let text = try String(contentsOf: directory.appending(path: "trace.jsonl"), encoding: .utf8)
        let measures = try text.split(separator: "\n").map { try JSONDecoder().decode(Line.self, from: Data($0.utf8)).data }
        #expect(measures == [ColinMeasure(step: "regles-reponses", ok: false, labels: ["raison": "base illisible", "etape": "ouverture"])])
        #expect(!text.contains("essai-de-sonde") && !text.contains("confidentielle"))
        #expect(!ColinRulesProbe.completed(in: directory))
    }

    @Test func theCountOpensTheBaseToReadAndWritesNothing() async throws {
        // As the app runs it: on the file of the base, which the app holds open, and without a single writing.
        let folder = FileManager.default.temporaryDirectory.appending(path: "colin-regles-base-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "Polhub.sqlite").path(percentEncoded: false)
        let app = try AppDatabase(path: path)
        try CalendarStore(app).addAccount(email: Self.me, at: ago(400))
        try MailStore(app).apply(account: Self.me, upserts: [
            sent("s", thread: "ancien", to: Self.marc, daysAgo: 90, subject: "Avant"),
            received("a1", thread: "a", from: Self.marc, daysAgo: 4, subject: "Maquette"),
        ])
        let changes = try await app.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM mail_thread") }
        let directory = folder.appending(path: "mesure", directoryHint: .isDirectory)
        let trace = try TraceWriter(fileURL: directory.appending(path: "trace.jsonl"))
        let fixed = now
        await ColinRulesProbe(path: path, now: { fixed }).run(ProbeRequest(probe: .colinRules), trace: trace, directory: directory)
        await trace.close()
        #expect(ColinRulesProbe.completed(in: directory))
        let text = try String(contentsOf: directory.appending(path: "trace.jsonl"), encoding: .utf8)
        #expect(text.contains(#""aujourdhui":1"#))
        // The base the probe opens refuses any writing.
        #expect(throws: (any Error).self) {
            try AppDatabase.readOnly(path: path).writer.write { try $0.execute(sql: "DELETE FROM mail_thread") }
        }
        #expect(try MailStore(app).allThreads().count == 2)
        let after = try await app.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM mail_thread") }
        #expect(after == changes)
    }

    @Test func theProbeIsInTheRegistryAndInTheWindow() async {
        #expect(ProbeID.colinRules.rawValue == "colin-regles")
        #expect(ProbeID.colinRules.title == "Colin : les règles sur tes mails")
        #expect(ProbeID.listed.contains(.colinRules))
        #expect(await ProbeRegistry.make(.colinRules) != nil)
        #expect(LaunchArguments.parse(["Polhub", "--probe", "colin-regles"])?.probe == .colinRules)
    }
}
