import Foundation
import GRDB
import Testing
@testable import Persistence

/// « Inspiration » (16/11): the sites, the branding and the mock-ups, and the LinkedIn pages they come from.
@Suite struct InspirationStoreTests {
    let now = Date(timeIntervalSince1970: 1_794_822_000)   // 16/11/2026

    func store() throws -> InspirationStore { InspirationStore(try AppDatabase.inMemory()) }

    func site(_ key: String, title: String = "Exemple", daysAgo: Double = 0) -> InspirationItemRow {
        InspirationItemRow(kind: .website, key: key, title: title, url: key, date: now.addingTimeInterval(-daysAgo * 86_400), createdAt: now)
    }

    func post(_ urn: String, title: String = "Café Nord", images: [String] = [], sources: [String] = ["Galerie Exemple"]) -> InspirationItemRow {
        InspirationItemRow(kind: .branding, key: urn, title: title, text: "Identité visuelle d'un café.",
                           url: "https://www.linkedin.com/feed/update/urn:li:activity:\(urn)/", date: now, sources: sources,
                           studio: "Atelier Nord", images: images, createdAt: now)
    }

    @Test func theNewestComeFirstAndEachKindKeepsItsOwn() throws {
        let store = try store()
        try store.upsert(site("https://ancien.exemple.fr", title: "Ancien", daysAgo: 3), at: now)
        try store.upsert(site("https://recent.exemple.fr", title: "Récent", daysAgo: 1), at: now)
        try store.upsert(post("7300000000000000001"), at: now)
        #expect(try store.items(kind: .website).map(\.title) == ["Récent", "Ancien"])
        #expect(try store.items(kind: .branding).map(\.title) == ["Café Nord"])
        #expect(try store.items(kind: .mockup).isEmpty)
    }

    /// The JSON columns come back as they went in, and stay readable from `sqlite3`.
    @Test func everyFieldComesBackAsItWentIn() throws {
        let store = try store()
        var item = post("7300000000000000002", images: ["7300000000000000002-1.jpg", "7300000000000000002-2.jpg"])
        item.links = ["https://exemple.fr/projet"]
        item.categories = ["secteur": ["restaurant"], "style": ["chaleureux", "artisanal"]]
        item.fonts = ["Garamond Exemple"]
        item.client = "café de quartier à Lyon"
        item.extra = InspirationExtra(hashtags: ["branding", "cafe"], hiddenImages: 3)
        item.importedFrom = "database/Branding/2026-07-04 Café Nord.md"
        try store.upsert(item, at: now)
        let back = try #require(try store.item(id: item.id))
        #expect(back == item)
        let raw = try store.database.writer.read { try Row.fetchOne($0, sql: "SELECT categories, images, extra FROM inspiration_item")! }
        #expect((raw["categories"] as String).contains(#""secteur":["restaurant"]"#))
        #expect((raw["images"] as String) == #"["7300000000000000002-1.jpg","7300000000000000002-2.jpg"]"#)
        #expect((raw["extra"] as String).contains(#""hiddenImages":3"#))
    }

    /// The same post seen again: the richer images list stays, the sources add up, nothing is duplicated.
    @Test func anUpsertMergesTheSameKey() throws {
        let store = try store()
        let first = post("7300000000000000003", images: ["a-1.jpg", "a-2.jpg", "a-3.jpg"], sources: ["Galerie Exemple"])
        #expect(try store.upsert(first, at: now).outcome == .added)
        var again = post("7300000000000000003", images: ["a-1.jpg"], sources: ["Revue Exemple"])
        again.text = "Court."
        let result = try store.upsert(again, at: now.addingTimeInterval(60))
        #expect(result.outcome == .updated)
        let items = try store.items(kind: .branding)
        #expect(items.count == 1)
        #expect(items[0].id == first.id)
        #expect(items[0].images == ["a-1.jpg", "a-2.jpg", "a-3.jpg"])
        #expect(items[0].sources == ["Galerie Exemple", "Revue Exemple"])
        // The longer text stays.
        #expect(items[0].text == "Identité visuelle d'un café.")
        #expect(items[0].updatedAt == now.addingTimeInterval(60) && items[0].createdAt == now)
        // The same again: nothing changes, not even the date of the last change.
        #expect(try store.upsert(again, at: now.addingTimeInterval(120)).outcome == .unchanged)
        #expect(try store.item(id: first.id)?.updatedAt == now.addingTimeInterval(60))
    }

    /// Paul's categories are never overwritten by an import or by the AI; the rest still fills in.
    @Test func paulsCategoriesAreNeverOverwritten() throws {
        let store = try store()
        var item = site("https://exemple.fr")
        item.categories = ["secteur": ["agence"]]
        try store.upsert(item, at: now)
        try store.setCategories(id: item.id, ["secteur": ["culture"], "style": ["minimal"], "typo": []], at: now)
        let edited = try #require(try store.item(id: item.id))
        #expect(edited.categoriesByPaul && edited.categories == ["secteur": ["culture"], "style": ["minimal"]])
        var incoming = site("https://exemple.fr")
        incoming.categories = ["secteur": ["tech"]]
        incoming.fonts = ["Police IA"]
        incoming.text = "Une description plus longue que rien du tout."
        try store.upsert(incoming, at: now)
        let back = try #require(try store.item(id: item.id))
        #expect(back.categories == ["secteur": ["culture"], "style": ["minimal"]] && back.categoriesByPaul)
        #expect(back.fonts.isEmpty)
        #expect(back.text == "Une description plus longue que rien du tout.")
        // The tagger's door: nothing for an item Paul corrected.
        #expect(try store.applyTagging(id: item.id, categories: ["secteur": ["tech"]], fonts: [], client: "IA", at: now) == false)
        #expect(try store.item(id: item.id)?.categories == ["secteur": ["culture"], "style": ["minimal"]])
    }

    /// The categories an import brings from a note Paul tagged by hand (`ia_manuel`) are his as well.
    @Test func importedHandTagsWinOverTheAI() throws {
        let store = try store()
        var ai = site("https://exemple.fr")
        ai.categories = ["secteur": ["tech"]]
        try store.upsert(ai, at: now)
        var hand = site("https://exemple.fr")
        hand.categories = ["secteur": ["agence"]]
        hand.categoriesByPaul = true
        try store.upsert(hand, at: now)
        let back = try #require(try store.items(kind: .website).first)
        #expect(back.categories == ["secteur": ["agence"]] && back.categoriesByPaul)
        // And an empty incoming list never erases what is there.
        try store.upsert(site("https://exemple.fr"), at: now)
        #expect(try store.items(kind: .website).first?.categories == ["secteur": ["agence"]])
    }

    @Test func theTaggerFillsAnItemPaulLeftAlone() throws {
        let store = try store()
        let item = site("https://exemple.fr")
        try store.upsert(item, at: now)
        #expect(try store.applyTagging(id: item.id, categories: ["secteur": ["agence"], "techno": []], fonts: ["Söhne Exemple"], client: "studio de design", at: now))
        let back = try #require(try store.item(id: item.id))
        #expect(back.categories == ["secteur": ["agence"]] && !back.categoriesByPaul)
        #expect(back.fonts == ["Söhne Exemple"] && back.client == "studio de design")
    }

    /// A deleted item leaves the lists, is never brought back by an import or a collection, and « Annuler »
    /// restores it.
    @Test func aDeletedItemIsNeverResurrected() throws {
        let store = try store()
        let item = site("https://exemple.fr")
        try store.upsert(item, at: now)
        try store.moveToTrash(id: item.id, at: now)
        #expect(try store.items(kind: .website).isEmpty)
        #expect(try store.knownKeys(kind: .website) == ["https://exemple.fr"])
        // The import still sees it, to leave it where it is.
        #expect(try store.allItems(kind: .website).map(\.id) == [item.id])
        let result = try store.upsert(site("https://exemple.fr", title: "Revenu"), at: now)
        #expect(result.item.deletedAt != nil)
        #expect(try store.items(kind: .website).isEmpty)
        try store.restore(id: item.id, at: now)
        #expect(try store.items(kind: .website).map(\.id) == [item.id])
    }

    /// A duplicate merged into another item keeps its key as an alias: seen again, it lands on that item.
    @Test func anAliasLeadsToTheItemItWasMergedInto() throws {
        let store = try store()
        var kept = post("7300000000000000010", images: ["k-1.jpg", "k-2.jpg"])
        kept.extra.aliases = ["7300000000000000011"]
        try store.upsert(kept, at: now)
        #expect(try store.knownKeys(kind: .branding) == ["7300000000000000010", "7300000000000000011"])
        let result = try store.upsert(post("7300000000000000011", images: ["d-1.jpg"], sources: ["Revue Exemple"]), at: now)
        #expect(result.item.id == kept.id && result.item.key == "7300000000000000010")
        #expect(try store.items(kind: .branding).count == 1)
        #expect(try store.item(kind: .branding, key: "7300000000000000011")?.id == kept.id)
        #expect(result.item.sources == ["Galerie Exemple", "Revue Exemple"])
    }

    /// An item whose own key and one of its aliases are both rows lands on its own row, never on the alias's
    /// (review of 16/11: the lowest key came first, and the item's own row was never updated).
    @Test func anItemLandsOnItsOwnRowBeforeAnAlias() throws {
        let store = try store()
        try store.upsert(post("7400000000000000001", title: "Premier"), at: now)
        try store.upsert(post("7500000000000000002", title: "Second"), at: now)
        var incoming = post("7500000000000000002", title: "Second complété", images: ["7500000000000000002-1.jpg"])
        incoming.extra.aliases = ["7400000000000000001"]
        let result = try store.upsert(incoming, at: now)
        #expect(result.item.key == "7500000000000000002")
        #expect(try store.item(kind: .branding, key: "7400000000000000001")?.title == "Premier")
        #expect(try store.item(kind: .branding, key: "7500000000000000002")?.title == "Second complété")
    }

    @Test func theItemsAreObserved() async throws {
        let store = try store()
        final class Box: @unchecked Sendable { var titles: [String] = [] }
        let box = Box()
        let observation = store.observeItems(kind: .website) { box.titles = $0.map(\.title) }
        try store.upsert(site("https://exemple.fr", title: "Observé"), at: now)
        for _ in 0..<100 where box.titles.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(box.titles == ["Observé"])
        observation.cancel()
    }

    /// A change of one kind wakes only that kind's page: Branding's posts never make Websites read and draw again
    /// (review of 16/11: every write read the three lists again, on the writer).
    @Test func aChangeOfOneKindIsNotToldToTheOthers() async throws {
        let store = try store()
        final class Box: @unchecked Sendable {
            var calls = 0
            var titles: [String] = []
        }
        let box = Box()
        let observation = store.observeItems(kind: .website) { rows in
            box.calls += 1
            box.titles = rows.map(\.title)
        }
        for _ in 0..<100 where box.calls == 0 { try await Task.sleep(for: .milliseconds(20)) }
        for index in 1...5 { try store.upsert(post("730000000000000010\(index)"), at: now) }
        try store.upsert(site("https://exemple.fr", title: "Observé"), at: now)
        for _ in 0..<100 where box.titles.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(box.titles == ["Observé"])
        #expect(box.calls == 2)
        observation.cancel()
    }

    // MARK: - LinkedIn pages

    @Test func aPageIsKeptOnceByItsLink() throws {
        let store = try store()
        let page = InspirationSourceRow(name: "Galerie Exemple", link: "https://www.linkedin.com/company/galerie-exemple/", color: "#e8b923", createdAt: now)
        try store.saveSource(page)
        // The same link under another id: the page is updated, not doubled.
        try store.saveSource(InspirationSourceRow(name: "Galerie Exemple (bis)", link: "https://www.linkedin.com/company/galerie-exemple/", createdAt: now))
        let pages = try store.sources()
        #expect(pages.count == 1 && pages[0].id == page.id && pages[0].name == "Galerie Exemple (bis)")
        try store.markSourceRead(id: page.id, at: now, error: "LinkedIn demande une connexion")
        #expect(try store.sources().first?.lastError == "LinkedIn demande une connexion" && store.sources().first?.lastReadAt == now)
        try store.deleteSource(id: page.id)
        #expect(try store.sources().isEmpty)
    }

    /// A page Paul no longer follows is remembered, so that an import does not follow it again; followed again by
    /// hand, the same row comes back (review of 16/11).
    @Test func aPageNoLongerFollowedIsRemembered() throws {
        let store = try store()
        let page = InspirationSourceRow(name: "Galerie Exemple", link: "https://www.linkedin.com/company/galerie-exemple/", createdAt: now)
        try store.saveSource(page)
        try store.deleteSource(id: page.id, at: now)
        #expect(try store.sources().isEmpty)
        #expect(try store.sources(includingRemoved: true).map(\.link) == [page.link])
        #expect(try store.sources(includingRemoved: true).first?.removedAt == now)
        try store.saveSource(InspirationSourceRow(name: "Galerie Exemple", link: page.link, color: "#e8b923", createdAt: now))
        let back = try store.sources()
        #expect(back.map(\.id) == [page.id] && back.first?.removedAt == nil && back.first?.color == "#e8b923")
    }

    @Test func aPagesLinkIsWrittenOneWay() {
        #expect(InspirationSourceRow.normalizedLink("https://fr.linkedin.com/company/Galerie-Exemple/posts/?trk=x") == "https://www.linkedin.com/company/galerie-exemple/")
        #expect(InspirationSourceRow.normalizedLink("http://linkedin.com/company/revue-exemple") == "https://www.linkedin.com/company/revue-exemple/")
        #expect(InspirationSourceRow.normalizedLink("  https://www.linkedin.com/company/revue-exemple/  ") == "https://www.linkedin.com/company/revue-exemple/")
    }

    @Test func theSourcesAreObserved() async throws {
        let store = try store()
        final class Box: @unchecked Sendable { var names: [String] = [] }
        let box = Box()
        let observation = store.observeSources { box.names = $0.map(\.name) }
        try store.saveSource(InspirationSourceRow(name: "Revue Exemple", link: "https://www.linkedin.com/company/revue-exemple/", createdAt: now))
        for _ in 0..<100 where box.names.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(box.names == ["Revue Exemple"])
        observation.cancel()
    }
}
