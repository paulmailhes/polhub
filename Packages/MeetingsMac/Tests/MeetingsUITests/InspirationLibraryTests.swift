import AppKit
import Foundation
import Inspiration
import Persistence
import PolhubDesign
import Testing
@testable import MeetingsUI

/// The library of « Inspiration » (16/11): it follows the base page by page, filters and searches, keeps Paul's
/// categories, deletes with « Annuler », keeps the LinkedIn pages, asks the collection.
@MainActor @Suite struct InspirationLibraryTests {
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }

    /// Each page has its items, newest first, from the base; a new one shows without asking.
    @Test func eachPageFollowsTheBase() async throws {
        let world = try InspirationTestWorld()
        defer { world.clean() }
        try world.website("Ancien", url: "https://ancien.exemple.fr", on: InspirationTestWorld.day(10, 1))
        try world.website("Récent", url: "https://recent.exemple.fr", on: InspirationTestWorld.day(11, 10))
        try world.mockup("Affiche", folder: "Affiche", on: InspirationTestWorld.day(9, 1), types: ["affiche"])
        let library = world.library()
        try await waitUntil { library.loaded.count == 3 }
        #expect(library.items(.website).map(\.title) == ["Récent", "Ancien"])
        #expect(library.shown(.website).map(\.title) == ["Récent", "Ancien"])
        #expect(library.items(.branding).isEmpty && library.items(.mockup).count == 1)
        try world.website("Nouveau", url: "https://nouveau.exemple.fr", on: InspirationTestWorld.day(11, 16))
        try await waitUntil { library.items(.website).count == 3 }
        #expect(library.shown(.website).first?.title == "Nouveau")
    }

    /// The search and the filters belong to each page; « Tout afficher » clears both.
    @Test func eachPageKeepsItsSearchAndItsFilters() async throws {
        let world = try InspirationTestWorld()
        defer { world.clean() }
        try world.website("Maison Lumière", url: "https://maison.exemple.fr", on: InspirationTestWorld.day(11, 2), categories: ["style": ["minimal"]])
        try world.website("Atelier Nord", url: "https://atelier.exemple.fr", on: InspirationTestWorld.day(11, 1), categories: ["style": ["brutaliste"]])
        try world.branding("Café Nord", urn: "7390000000000000001", on: InspirationTestWorld.day(11, 3), studio: nil, sources: ["Studio Exemple"])
        let library = world.library()
        try await waitUntil { library.loaded.count == 3 }
        library.setFilter("minimal", family: "style", for: .website)
        #expect(library.shown(.website).map(\.title) == ["Maison Lumière"])
        #expect(library.chips(.website).first { $0.family == "style" }?.selected == "minimal")
        #expect(library.shown(.branding).count == 1)
        library.setFilter(nil, family: "style", for: .website)
        library.setQuery("nord", for: .website)
        #expect(library.shown(.website).map(\.title) == ["Atelier Nord"] && library.hasFilters(.website))
        #expect(library.query(.branding).isEmpty)
        library.setFilter("Studio Exemple", family: "source", for: .branding)
        library.clearFilters(.website)
        #expect(library.shown(.website).count == 2 && !library.hasFilters(.website))
        #expect(library.filter(.branding, family: "source") == "Studio Exemple")
    }

    /// Paul's categories are his from then on: the base marks them, and a later write of the item never changes them.
    @Test func paulsCategoriesStayHis() async throws {
        let world = try InspirationTestWorld()
        defer { world.clean() }
        let item = try world.website("Maison", url: "https://maison.exemple.fr", on: InspirationTestWorld.day(11, 2), categories: ["style": ["minimal"]])
        let library = world.library()
        try await waitUntil { library.loaded.contains(.website) }
        library.toggleCategory(item, family: "style", value: "luxe")
        try await waitUntil { library.item(item.id)?.categories["style"] == ["minimal", "luxe"] }
        #expect(library.item(item.id)?.categoriesByPaul == true)
        var again = item
        again.categories = ["style": ["brutaliste"]]
        try world.store.upsert(again)
        #expect(try world.store.item(id: item.id)?.categories["style"] == ["minimal", "luxe"])
    }

    /// « Supprimer » takes the item off its page; « Annuler » brings it back as it was.
    @Test func supprimerCanBeUndone() async throws {
        let world = try InspirationTestWorld()
        defer { world.clean() }
        let item = try world.branding("Café Nord", urn: "7390000000000000001", on: InspirationTestWorld.day(11, 3), studio: "Studio Exemple",
                                      sources: ["Studio Exemple"], images: [1])
        let library = world.library()
        try await waitUntil { library.items(.branding).count == 1 }
        library.moveToTrash(item)
        #expect(library.undoable?.text == "« Café Nord » supprimé")
        try await waitUntil { library.items(.branding).isEmpty }
        #expect(library.item(item.id) == nil)
        library.undo()
        try await waitUntil { library.items(.branding).count == 1 }
        #expect(library.undoable == nil && library.item(item.id)?.images == item.images)
    }

    /// The LinkedIn pages: added, changed, removed; their link written one way; a link that is not a company page,
    /// or one already followed, is refused in plain words.
    @Test func theLinkedInPagesAreKeptOneLinkEach() async throws {
        let world = try InspirationTestWorld()
        defer { world.clean() }
        let library = world.library()
        #expect(library.saveSource(name: "Studio Exemple", link: "linkedin.com/company/Studio-Exemple/posts/?feedView=all", color: "#e8b923") == nil)
        try await waitUntil { library.sources.count == 1 }
        let source = try #require(library.sources.first)
        #expect(source.link == "https://www.linkedin.com/company/studio-exemple/" && source.color == "#E8B923")
        #expect(library.saveSource(name: "Copie", link: "https://www.linkedin.com/company/studio-exemple/", color: nil) == "« Studio Exemple » suit déjà cette page.")
        #expect(library.saveSource(name: "Profil", link: "https://www.linkedin.com/in/quelqu-un/", color: nil)?.contains("pas une page LinkedIn") == true)
        #expect(library.saveSource(name: "  ", link: "https://www.linkedin.com/company/autre/", color: nil) == "Donne un nom à la page.")
        #expect(library.saveSource(id: source.id, name: "Studio Exemple Paris", link: source.link, color: "pas une couleur") == nil)
        try await waitUntil { library.sources.first?.name == "Studio Exemple Paris" }
        #expect(library.sources.count == 1 && library.sources.first?.color == nil)
        library.deleteSource(try #require(library.sources.first))
        try await waitUntil { library.sources.isEmpty }
    }

    /// Until the app wires the collection, every addition says « Pas encore branché. »; once wired, the closures run.
    @Test func theCollectionGoesThroughTheServices() async throws {
        let world = try InspirationTestWorld()
        defer { world.clean() }
        let library = world.library()
        await #expect(throws: InspirationServicesError.notConnected) { try await library.addSite("exemple.fr") }
        await #expect(throws: InspirationAddError.notAWebAddress) { try await library.addSite("pas une adresse") }
        await #expect(throws: InspirationAddError.notAWebAddress) { try await library.addSite("192.168.1.10") }
        await library.collectNow()
        #expect(library.message == "Pas encore branché.")
        library.message = nil

        let id = UUID()
        let asked = Asked()
        library.services = InspirationServices(
            addSite: { url in await asked.add(url.absoluteString); return id },
            addMockup: { folder in await asked.add(folder.lastPathComponent); return id },
            collectNow: { await asked.add("collecte") },
            status: { [InspirationStatusLine(id: "awwwards", name: "Awwwards", added: 1)] },
            tag: { item in await asked.add(item.uuidString) })
        #expect(try await library.addSite("exemple.fr/projets") == id)
        #expect(try await library.addMockup(folder: URL(fileURLWithPath: "/tmp/Affiche", isDirectory: true)) == id)
        await library.collectNow()
        #expect(library.message == nil && library.status(for: "awwwards")?.added == 1)
        #expect(await asked.all == ["https://exemple.fr/projets", "Affiche", "collecte"])
    }

    actor Asked {
        var all: [String] = []
        func add(_ text: String) { all.append(text) }
    }

    /// The collection's readings, as Réglages shows them: Awwwards under « awwwards », a page under its link, a
    /// page no longer followed left out; the count of a reading restored from the base is not known.
    @Test func theCollectionsReadingsBecomeStatusLines() throws {
        let date = InspirationTestWorld.day(11, 16)
        let page = InspirationSourceRow(name: "Studio Exemple", link: "https://www.linkedin.com/company/studio-exemple/", createdAt: date)
        let lines = InspirationStatusLine.lines([
            CollectionStatus(source: .awwwards, name: "Awwwards", date: date, outcome: .read(newItems: 1)),
            CollectionStatus(source: .linkedIn(page.id), name: "Studio Exemple", date: date, outcome: .loginWall),
            CollectionStatus(source: .linkedIn(UUID()), name: "Plus suivie", date: date, outcome: .read(newItems: 2)),
        ], sources: [page])
        #expect(lines == [
            InspirationStatusLine(id: "awwwards", name: "Awwwards", lastRun: date, problem: nil, added: 1),
            InspirationStatusLine(id: page.link, name: "Studio Exemple", lastRun: date,
                                  problem: "LinkedIn demande une connexion : réessai au prochain tour", added: nil),
        ])
        let restored = try #require(CollectionStatus(page: InspirationSourceRow(name: "Atelier Nord", link: "https://www.linkedin.com/company/atelier-nord/",
                                                                                 lastReadAt: date, createdAt: date)))
        #expect(InspirationStatusLine.lines([restored], sources: [])
            .isEmpty)
    }

    /// A card never decodes the whole image: a thumbnail at the pixels it fills, made once, then from memory.
    @Test func aCardDecodesOnlyTheThumbnailItShows() async throws {
        let world = try InspirationTestWorld()
        defer { world.clean() }
        let name = try world.draw("grande.jpg", kind: .website, seed: 3, size: CGSize(width: 1_600, height: 1_000))
        let url = world.paths.inspirationImages(.website).appending(path: name)
        let thumbnails = InspirationThumbnails(memory: 64 << 20)
        let card = try #require(await thumbnails.image(url, pixels: CGSize(width: 520, height: 390), mode: .fill))
        // The box goes up to 640 × 512 pixels; filling it from a 16:10 image takes 512 pixels of height.
        #expect(card.width == 820 && (512...513).contains(card.height))
        #expect(thumbnails.cached(url, pixels: CGSize(width: 530, height: 400), mode: .fill) === card)
        let fit = try #require(await thumbnails.image(url, pixels: CGSize(width: 520, height: 390), mode: .fit))
        #expect(fit.width == 640 && fit.height == 400)
        // Never larger than the image itself.
        let large = try #require(await thumbnails.image(url, pixels: CGSize(width: 4_000, height: 4_000), mode: .fill))
        #expect(large.width == 1_600 && large.height == 1_000)
        #expect(await thumbnails.image(world.root.appending(path: "absente.jpg"), pixels: CGSize(width: 100, height: 100), mode: .fill) == nil)
        #expect(InspirationThumbnails.longSide(image: CGSize(width: 1_200, height: 630), box: CGSize(width: 640, height: 480), mode: .fill) == 915)
        #expect(InspirationThumbnails.pixelSize(url) == CGSize(width: 1_600, height: 1_000))
    }

    /// The thumbnails kept in memory: a few screens of cards (64 Mo, about forty), let go when Paul leaves
    /// « Inspiration » (review of 16/11: 256 Mo stayed all day in an app that never quits).
    @Test func theThumbnailsKeepLittleMemoryAndGoWhenInspirationCloses() async throws {
        #expect(InspirationThumbnails.memory == 64 << 20)
        let world = try InspirationTestWorld()
        defer { world.clean() }
        let name = try world.draw("carte.jpg", kind: .website, seed: 4, size: CGSize(width: 1_200, height: 900))
        let url = world.paths.inspirationImages(.website).appending(path: name)
        let thumbnails = InspirationThumbnails()
        _ = try #require(await thumbnails.image(url, pixels: CGSize(width: 256, height: 192), mode: .fill))
        #expect(thumbnails.cached(url, pixels: CGSize(width: 256, height: 192), mode: .fill) != nil)
        thumbnails.purge()
        #expect(thumbnails.cached(url, pixels: CGSize(width: 256, height: 192), mode: .fill) == nil)
    }

    /// Past the memory set aside, the thumbnail shown least recently goes first; one shown again stays.
    @Test func theLeastRecentlyShownThumbnailGoesFirst() async throws {
        let world = try InspirationTestWorld()
        defer { world.clean() }
        let box = CGSize(width: 256, height: 192)
        var urls: [URL] = []
        for (index, file) in ["a.jpg", "b.jpg", "c.jpg"].enumerated() {
            let name = try world.draw(file, kind: .website, seed: index + 5, size: CGSize(width: 1_200, height: 900))
            urls.append(world.paths.inspirationImages(.website).appending(path: name))
        }
        let one = try #require(await InspirationThumbnails().image(urls[0], pixels: box, mode: .fill))
        // Room for two.
        let thumbnails = InspirationThumbnails(memory: one.bytesPerRow * one.height * 2 + 1)
        for url in urls.prefix(2) { _ = await thumbnails.image(url, pixels: box, mode: .fill) }
        #expect(thumbnails.cached(urls[0], pixels: box, mode: .fill) != nil)
        _ = await thumbnails.image(urls[2], pixels: box, mode: .fill)
        #expect(thumbnails.cached(urls[0], pixels: box, mode: .fill) != nil)
        #expect(thumbnails.cached(urls[1], pixels: box, mode: .fill) == nil)
        #expect(thumbnails.cached(urls[2], pixels: box, mode: .fill) != nil)
    }
}
