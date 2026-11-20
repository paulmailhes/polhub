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
