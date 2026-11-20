import Foundation
import Persistence
import Testing
@testable import Inspiration

/// Awwwards' site of the day, collected by hub (16/11), and a site added by hand: the og tags, the image made
/// light (else Awwwards' thumbnail), the address as the only key.
@Suite struct WebsiteCollectionTests {
    let now = Date(timeIntervalSince1970: 1_794_816_000) // 16/11/2026

    func served(_ world: CollectWorld, site: String = "site-lumiere.html") {
        world.http.page(AwwwardsHome.address.absoluteString, fixture: "awwwards-accueil.html")
        world.http.page(CollectFixtures.lumiere, fixture: site)
        world.http.image(CollectFixtures.lumiereImage, TestImages.jpeg(width: 2400, height: 1260))
        world.http.image(CollectFixtures.awwwardsThumbnail, TestImages.png(width: 1600, height: 1200, color: .red))
    }

    @Test func theSiteOfTheDayIsAdded() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        served(world)
        let runLog = CollectWorld.runLog()
        let run = await world.collector(runLog: runLog).collectWebsites(now: now)
        #expect(run.added.count == 1 && !run.skipped)
        let site = try #require(try world.store.item(kind: .website, key: "https://lumiere.exemple.fr"))
        #expect(site.title == "Lumière Exemple — Studio d'éclairage")
        #expect(site.text.hasPrefix("Un studio d'éclairage qui dessine la lumière"))
        #expect(site.url == CollectFixtures.lumiere)
        #expect(site.links == ["https://www.awwwards.com/sites/lumiere-exemple"])
        #expect(site.date == now && site.categories.isEmpty && !site.categoriesByPaul)
        // The site's own image, made light, named as the import names it.
        #expect(site.images == [InspirationImageName.website(key: "https://lumiere.exemple.fr")])
        let probe = try #require(TestImages.Probe(world.imageURL(.website, site.images[0])))
        #expect(probe.width == 1600 && probe.height == 840 && probe.type == "public.jpeg")
        #expect(!world.http.requested.contains(CollectFixtures.awwwardsThumbnail))
        // Its state, in plain words, and the run kept.
        #expect(run.statuses.map { $0.text(now: now) } == ["Lu à \(Self.time(now)), 1 nouveau site"])
        #expect(runLog.lastRun(.websites) == now)
        #expect(runLog.awwwards?.outcome == .read(newItems: 1))
    }

    /// A site imported with its image known only by its address (a Web Clipper note) gets it at the next pass;
    /// each address is asked once, whether it came or not (review of 16/11: those cards stayed grey for good).
    @Test func anImportedSiteGetsItsRemoteImage() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        var galerie = InspirationItemRow(kind: .website, key: "https://galerie.exemple.fr", title: "Galerie", url: "https://galerie.exemple.fr/",
                                         date: now, createdAt: now)
        galerie.extra.imageURL = "https://galerie.exemple.fr/og.jpg"
        var lost = InspirationItemRow(kind: .website, key: "https://perdu.exemple.fr", title: "Perdu", url: "https://perdu.exemple.fr/",
                                      date: now, createdAt: now)
        lost.extra.imageURL = "https://perdu.exemple.fr/og.jpg"
        var local = InspirationItemRow(kind: .website, key: "https://local.exemple.fr", title: "Local", date: now, createdAt: now)
        local.extra.imageURL = "http://localhost:3000/og.jpg"
        for item in [galerie, lost, local] { try world.store.upsert(item, at: now) }
        world.http.image("https://galerie.exemple.fr/og.jpg", TestImages.jpeg(width: 2400, height: 1260))
        let collector = world.collector()
        #expect(await collector.completeImages(now: now) == 1)
        let back = try #require(try world.store.item(kind: .website, key: "https://galerie.exemple.fr"))
        #expect(back.images == [InspirationImageName.website(key: "https://galerie.exemple.fr")])
        #expect(back.images.first.flatMap { TestImages.Probe(world.imageURL(.website, $0)) }?.width == 1600)
        #expect(!world.http.requested.contains { $0.contains("localhost") })
        let before = world.http.requested.count
        #expect(await collector.completeImages(now: now) == 0)
        #expect(world.http.requested.count == before)
    }

    /// Seen again (the next slot, a deleted site, a merged duplicate), nothing is added nor fetched beyond the
    /// home page.
    @Test func aKnownSiteIsNotAddedAgain() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        served(world)
        let collector = world.collector()
        _ = await collector.collectWebsites(now: now)
        let site = try #require(try world.store.item(kind: .website, key: "https://lumiere.exemple.fr"))
        try world.store.moveToTrash(id: site.id, at: now)
        let before = world.http.requested.count
        let again = await collector.collectWebsites(now: now.addingTimeInterval(7200))
        #expect(again.added.isEmpty)
        #expect(world.http.requested.count == before + 1)
        #expect(again.statuses.first?.text(now: now) == "Lu à \(Self.time(now.addingTimeInterval(7200))), rien de nouveau")
        #expect(try world.store.items(kind: .website).isEmpty)
    }

    /// No og:image, or one on `localhost`: Awwwards' thumbnail stands in, and the local address is never asked.
    @Test func awwwardsThumbnailStandsInForAMissingImage() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        served(world, site: "site-sans-image.html")
        let run = await world.collector().collectWebsites(now: now)
        let site = try #require(run.added.first)
        #expect(site.title == "Atelier Exemple | Portfolio")
        #expect(site.text == "Le portfolio d'un atelier de design graphique et de signalétique, à Nantes.")
        #expect(site.images.count == 1)
        let probe = try #require(TestImages.Probe(world.imageURL(.website, site.images[0])))
        #expect(probe.width == 1600 && probe.height == 1200)
        #expect(world.http.requested.contains(CollectFixtures.awwwardsThumbnail))
        #expect(!world.http.requested.contains { $0.contains("localhost") })
    }

    /// The site's image is not one (a page, an SVG): the thumbnail again.
    @Test func anImageThatIsNotOneIsReplaced() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        served(world)
        world.http.image(CollectFixtures.lumiereImage, Data("<html>404</html>".utf8), contentType: "text/html")
        let run = await world.collector().collectWebsites(now: now)
        let site = try #require(run.added.first)
        let probe = try #require(TestImages.Probe(world.imageURL(.website, site.images[0])))
        #expect(probe.width == 1600 && probe.height == 1200)
        // No half-written file left beside.
        #expect(world.imageFiles(.website) == [site.images[0]])
    }

    /// The line drops as the site's image comes down: the site of the day is not kept grey for good; once the line
    /// is back, the next pass brings it with its image (audit of 19/11).
    @Test func anImageCutByADroppedLineComesAtTheNextPass() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        served(world)
        // The pages come, then the line drops at the first image.
        let line = DroppingLine(world.http, imagesBeforeDrop: 0)
        let runLog = CollectWorld.runLog()
        let collector = world.collector(http: line, runLog: runLog)
        // Two passes as the app runs them (`InspirationAutomation.work`): the collection, then the images still missing.
        let cut = await collector.collectWebsites(now: now)
        _ = await collector.completeImages(now: now)
        // Said offline, and not counted as a run: the next check tries again.
        #expect(cut.wasOffline && runLog.lastRun(.websites) == nil)
        line.reconnect()
        let later = now.addingTimeInterval(300)
        _ = await collector.collectWebsites(now: later)
        _ = await collector.completeImages(now: later)
        let site = try #require(try world.store.item(kind: .website, key: "https://lumiere.exemple.fr"))
        #expect(site.images == [InspirationImageName.website(key: "https://lumiere.exemple.fr")])
    }

    /// The site does not answer: the item stays, named after its host, with Awwwards' thumbnail.
    @Test func aSiteThatDoesNotAnswerIsStillKept() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        served(world)
        world.http.page(CollectFixtures.lumiere, html: "Interdit", status: 403)
        let run = await world.collector().collectWebsites(now: now)
        let site = try #require(run.added.first)
        #expect(site.title == "lumiere.exemple.fr" && site.text.isEmpty && site.images.count == 1)
    }

    @Test func awwwardsProblemsAreSaidPlainly() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        world.http.page(AwwwardsHome.address.absoluteString, html: "<html><body>Maintenance</body></html>")
        let runLog = CollectWorld.runLog()
        let collector = world.collector(runLog: runLog)
        let changed = await collector.collectWebsites(now: now)
        #expect(changed.statuses.first?.text(now: now) == "Le site du jour est introuvable sur la page d'Awwwards : réessai au prochain tour")
        #expect(runLog.lastRun(.websites) == now)
        world.http.page(AwwwardsHome.address.absoluteString, html: "", status: 503)
        let down = await collector.collectWebsites(now: now)
        #expect(down.statuses.first?.text(now: now) == "Awwwards n'a pas répondu (erreur 503) : réessai au prochain tour")
        #expect(await collector.statuses().first?.problem == "Awwwards n'a pas répondu (erreur 503) : réessai au prochain tour")
        // Offline: said, and not counted as a run (the next check tries again).
        world.http.fail(AwwwardsHome.address.absoluteString, URLError(.notConnectedToInternet))
        let offline = await collector.collectWebsites(now: now.addingTimeInterval(600))
        #expect(offline.wasOffline && offline.statuses.first?.text(now: now) == "Pas de connexion à Internet : réessai au prochain tour")
        #expect(runLog.lastRun(.websites) == now)
        #expect(runLog.awwwards?.problem == "Pas de connexion à Internet : réessai au prochain tour")
    }

    // MARK: - By hand

    @Test func aSiteIsAddedByItsAddress() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        served(world)
        let url = try #require(InspirationCollector.siteURL(from: " lumiere.exemple.fr/?ref=awwwards "))
        #expect(url.absoluteString == "https://lumiere.exemple.fr/?ref=awwwards")
        let site = try await world.collector().addSite(url: url, now: now)
        #expect(site.key == "https://lumiere.exemple.fr" && site.title == "Lumière Exemple — Studio d'éclairage" && site.images.count == 1)
        #expect(site.links.isEmpty)
        // Twice: the same item, nothing fetched again.
        let before = world.http.requested.count
        let again = try await world.collector().addSite(url: URL(string: "http://www.lumiere.exemple.fr/")!, now: now)
        #expect(again.id == site.id && world.http.requested.count == before)
        #expect(try world.store.items(kind: .website).count == 1)
    }

    /// Paul adds a site he had deleted: it comes back.
    @Test func addingADeletedSiteBringsItBack() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        served(world)
        let collector = world.collector()
        let site = try await collector.addSite(url: URL(string: CollectFixtures.lumiere)!, now: now)
        try world.store.moveToTrash(id: site.id, at: now)
        let back = try await collector.addSite(url: URL(string: CollectFixtures.lumiere)!, now: now)
        #expect(back.id == site.id && back.deletedAt == nil)
        #expect(try world.store.items(kind: .website).map(\.id) == [site.id])
    }

    @Test func onlyPublicAddressesAreAdded() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        for text in ["localhost:3000", "http://192.168.1.10/", "file:///Users/exemple/site.html", "pas une adresse", "", "intranet"] {
            #expect(InspirationCollector.siteURL(from: text) == nil, "\(text)")
        }
        await #expect(throws: InspirationAddError.notAWebAddress) {
            try await world.collector().addSite(url: URL(string: "http://10.0.0.2/")!, now: now)
        }
        #expect(world.http.requested.isEmpty)
        world.http.fail("https://hors-ligne.exemple.fr", URLError(.notConnectedToInternet))
        await #expect(throws: InspirationAddError.offline) {
            try await world.collector().addSite(url: URL(string: "https://hors-ligne.exemple.fr")!, now: now)
        }
        #expect(try world.store.items(kind: .website).isEmpty)
    }

    /// Paul adds a site as the line drops at its image: said offline rather than kept without it; once the line is
    /// back, the same address brings it whole (audit of 19/11).
    @Test func aSiteAddedAsTheLineDropsIsSaidOffline() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        served(world)
        let line = DroppingLine(world.http, imagesBeforeDrop: 0)
        let collector = world.collector(http: line)
        await #expect(throws: InspirationAddError.offline) {
            try await collector.addSite(url: URL(string: CollectFixtures.lumiere)!, now: now)
        }
        #expect(try world.store.items(kind: .website).isEmpty)
        line.reconnect()
        let site = try await collector.addSite(url: URL(string: CollectFixtures.lumiere)!, now: now)
        #expect(site.images == [InspirationImageName.website(key: "https://lumiere.exemple.fr")])
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
