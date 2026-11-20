import Foundation
import Persistence
import Testing

/// 20/11 : la Dictée garde ce que Paul a dit (l'historique) et sa mémoire (ses mots, ses corrections).
@Suite struct DictationStoreTests {
    func store() throws -> DictationStore { DictationStore(try AppDatabase.inMemory()) }

    @Test func theHistoryKeepsTheNewestFirst() throws {
        let store = try store()
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        try store.add(DictationRow(text: "Premier.", raw: "premier", app: "Mail", seconds: 1.2, createdAt: start))
        try store.add(DictationRow(text: "Second.", raw: "second", app: "Code", seconds: 2, createdAt: start.addingTimeInterval(60)))
        #expect(try store.recent(limit: 10).map(\.text) == ["Second.", "Premier."])
        #expect(try store.last()?.app == "Code")
        try store.delete(try #require(try store.last()).id)
        #expect(try store.recent(limit: 10).map(\.text) == ["Premier."])
    }

    /// 20/11 au soir : la recherche, le texte réécrit, un fichier transcrit, l'historique effacé après un délai.
    @Test func theHistoryIsSearchedRewrittenAndForgotten() throws {
        let store = try store()
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let old = DictationRow(text: "Le devis 100% prêt.", raw: "le devis", app: "Mail", seconds: 3, createdAt: start)
        try store.add(old)
        try store.add(DictationRow(text: "Un mémo vocal.", raw: "un memo", app: nil, seconds: 62, createdAt: start.addingTimeInterval(86_400),
                                   file: "memo-client.m4a"))
        #expect(try store.search("DEVIS", limit: 10).map(\.text) == ["Le devis 100% prêt."])
        #expect(try store.search("100%", limit: 10).count == 1)
        #expect(try store.search("_", limit: 10).isEmpty)
        #expect(try store.search("client", limit: 10).map(\.file) == ["memo-client.m4a"])
        #expect(try store.search("  ", limit: 10).count == 2)
        try store.setText(old.id, text: "Le devis est prêt.", raw: "le devis est pret")
        #expect(try store.search("est prêt", limit: 10).map(\.id) == [old.id])
        #expect(try store.deleteOlder(than: start.addingTimeInterval(3_600)) == [old.id])
        #expect(try store.ids().count == 1 && store.recent(limit: 10).first?.file == "memo-client.m4a")
    }

    @Test func theMemoryKeepsEachWordAndEachCorrectionOnce() throws {
        let store = try store()
        try store.addWord("Vigie", at: Date())
        try store.addWord("  vigie ", at: Date())
        #expect(try store.words().map(\.word) == ["Vigie"])
        try store.setReplacement(heard: "mythe", written: "Meet", at: Date())
        try store.setReplacement(heard: "Mythe", written: "Google Meet", at: Date())
        #expect(try store.replacements().map { "\($0.heard)→\($0.written)" } == ["Mythe→Google Meet"])
        try store.removeWord("VIGIE")
        try store.removeReplacement("MYTHE")
        #expect(try store.words().isEmpty && store.replacements().isEmpty)
    }

    @Test func theFirstCorrectionsArePutOnlyOnce() throws {
        let store = try store()
        try store.seed([("mythe", "Meet"), ("Paul Hub", "hub")], at: Date())
        try store.removeReplacement("mythe")
        try store.seed([("mythe", "Meet"), ("Paul Hub", "hub")], at: Date())
        #expect(try store.replacements().map(\.heard) == ["Paul Hub"])
    }
}
