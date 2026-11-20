import Foundation
import Persistence
import Testing
@testable import Inspiration

/// The posts of the LinkedIn pages followed, collected by hub (16/11), without account nor cookie: the company
/// page for the ten latest, the embed page of each new one, up to five still images, the refusals said plainly.
@Suite struct BrandingCollectionTests {
    let now = Date(timeIntervalSince1970: 1_794_830_400)

    struct Pages {
        let studio: InspirationSourceRow
        let atelier: InspirationSourceRow
    }

    /// Two pages followed; a post already in hub; the studio's page, its embeds and images served; the
    /// atelier's page behind LinkedIn's login wall.
    func setUp(_ world: CollectWorld) throws -> Pages {
        let studio = try world.store.saveSource(InspirationSourceRow(name: "Studio Exemple", link: CollectFixtures.studioPage, color: "#e8b923", createdAt: now))
        let atelier = try world.store.saveSource(InspirationSourceRow(name: "Atelier Nord", link: CollectFixtures.atelierPage, createdAt: now))
        try world.store.upsert(InspirationItemRow(kind: .branding, key: CollectFixtures.knownUrn, title: "Déjà là", date: now, createdAt: now))
        let http = world.http
        http.page(CollectFixtures.studioPage, fixture: "linkedin-entreprise.html")
        http.page(CollectFixtures.embed(CollectFixtures.cafeUrn), fixture: "linkedin-embed.html")
        http.page(CollectFixtures.embed(CollectFixtures.marqueUrn), html: "Introuvable", status: 404)
        // The first image is an animation: its first frame red, the next blue.
        http.image(CollectFixtures.media("D4E22AQExemple10", "feedshare-shrink_2048_1536", "embed10"),
                   TestImages.gif(width: 2000, height: 1500, frames: [.red, .blue, .blue, .blue]), contentType: "image/gif")
        http.image(CollectFixtures.media("D4E22AQExemple11", "feedshare-shrink_2048_1536", "embed11"), TestImages.jpeg(width: 2048, height: 1536))
        http.image(CollectFixtures.media("D4E22AQExemple12", "feedshare-shrink_1280", "embed12"), TestImages.jpeg(width: 1280, height: 960))
        http.image(CollectFixtures.media("D4E22AQExemple13", "feedshare-shrink_2048_1536", "embed13"), TestImages.png(width: 1200, height: 1200))
        http.image(CollectFixtures.media("D4E22AQExemple14", "feedshare-shrink_2048_1536", "embed14"), TestImages.jpeg(width: 800, height: 600))
        http.image(CollectFixtures.media("D4E22AQExemple15", "feedshare-shrink_2048_1536", "embed15"), TestImages.jpeg(width: 800, height: 600))
        http.image(CollectFixtures.media("D4E22AQExemple31", "feedshare-shrink_800", "carte31"), TestImages.jpeg(width: 800, height: 800))
        http.page(CollectFixtures.atelierPage, fixture: "linkedin-mur.html", finalURL: "https://www.linkedin.com/authwall?trk=bf&trkInfo=x")
        return Pages(studio: studio, atelier: atelier)
    }

    @Test func theNewPostsOfEachPageAreAdded() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        let pages = try setUp(world)
        let runLog = CollectWorld.runLog()
        let run = await world.collector(runLog: runLog).collectBranding(now: now)
        #expect(run.added.map(\.key) == [CollectFixtures.cafeUrn, CollectFixtures.marqueUrn])
        #expect(run.statuses.map(\.name) == ["Atelier Nord", "Studio Exemple"])
        #expect(run.statuses.map { $0.text(now: now) } == [
            "LinkedIn demande une connexion : réessai au prochain tour",
            "Lu à \(WebsiteCollectionTests.time(now)), 2 nouveaux posts",
        ])
        #expect(runLog.lastRun(.branding) == now)

        // The post from its embed page: the whole text, the title and studio of its first line, the hashtags.
        let cafe = try #require(try world.store.item(kind: .branding, key: CollectFixtures.cafeUrn))
        #expect(cafe.title == "Café Lumière" && cafe.studio == "Atelier Nord")
        #expect(cafe.text.hasPrefix("Café Lumière by Atelier Nord\nUne identité chaleureuse pour un café de quartier à Lyon"))
        #expect(cafe.text.hasSuffix("exemple.fr/cafe-lumiere · Atelier Nord"))
        #expect(cafe.extra.hashtags == ["branding", "identite", "café"])
        #expect(cafe.url == "https://www.linkedin.com/feed/update/urn:li:activity:\(CollectFixtures.cafeUrn)/")
        #expect(cafe.date == InspirationKeys.publicationDate(urn: CollectFixtures.cafeUrn))
        #expect(cafe.sources == ["Studio Exemple"])
        // The links of the text: never LinkedIn's chrome, nor the page that posted it.
        #expect(cafe.links == ["https://exemple.fr/cafe-lumiere", "https://www.linkedin.com/company/atelier-nord/"])
        #expect(cafe.categories.isEmpty && !cafe.categoriesByPaul)

        // Five images at most; the first still image first (the GIF's blank start never makes the cover); the GIF
        // kept as its first frame only, read no further than that frame.
        #expect(cafe.images == (1...5).map { InspirationImageName.branding(urn: CollectFixtures.cafeUrn, index: $0) })
        let cover = try #require(TestImages.Probe(world.imageURL(.branding, cafe.images[0])))
        #expect(cover.width == 1600 && cover.height == 1200 && cover.type == "public.jpeg")
        let animation = try #require(TestImages.Probe(world.imageURL(.branding, cafe.images[1])))
        let pixel = animation.pixel(x: 10, y: 10)
        #expect(animation.width == 1600 && pixel.red > 200 && pixel.blue < 60)
        #expect(world.http.stoppedAt(CollectFixtures.media("D4E22AQExemple10", "feedshare-shrink_2048_1536", "embed10")) != nil)
        #expect(!world.http.requested.contains(CollectFixtures.media("D4E22AQExemple15", "feedshare-shrink_2048_1536", "embed15")))
        #expect(!world.imageFiles(.branding).contains { $0.hasPrefix(".") })

        // Its embed page refused (404): the company page's card is enough.
        let marque = try #require(try world.store.item(kind: .branding, key: CollectFixtures.marqueUrn))
        #expect(marque.title == "Marque Exemple" && marque.studio == "Studio Exemple")
        #expect(marque.text == "Marque Exemple by Studio Exemple\nUne identité pour une maison d'édition indépendante — logo, couvertures, papeterie et signalétique de la librairie.")
        #expect(marque.images == [InspirationImageName.branding(urn: CollectFixtures.marqueUrn, index: 1)])

        // The post already there is neither fetched nor touched.
        #expect(!world.http.requested.contains(CollectFixtures.embed(CollectFixtures.knownUrn)))
        #expect(try world.store.item(kind: .branding, key: CollectFixtures.knownUrn)?.title == "Déjà là")

        // Each page's reading kept in the base: when, and why it failed.
        let sources = try world.store.sources()
        #expect(sources.first { $0.id == pages.studio.id }?.lastReadAt == now)
        #expect(sources.first { $0.id == pages.studio.id }?.lastError == nil)
        #expect(sources.first { $0.id == pages.atelier.id }?.lastError == "LinkedIn demande une connexion : réessai au prochain tour")
    }

    /// One request at a time, a pause before each LinkedIn page but the first; the images (LinkedIn's media
    /// server) come right after their post.
    @Test func linkedInIsAskedSlowlyAndInOrder() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        _ = try setUp(world)
        _ = await world.collector().collectBranding(now: now)
        let linkedInPages = world.http.requested.filter { $0.hasPrefix("https://www.linkedin.com/") }
        #expect(linkedInPages == [CollectFixtures.atelierPage, CollectFixtures.studioPage, CollectFixtures.embed(CollectFixtures.cafeUrn),
                                  CollectFixtures.embed(CollectFixtures.marqueUrn)])
        #expect(world.pauses.all == [.seconds(2), .seconds(2), .seconds(2)])
        let requested = world.http.requested
        let cafeEmbed = try #require(requested.firstIndex(of: CollectFixtures.embed(CollectFixtures.cafeUrn)))
        let marqueEmbed = try #require(requested.firstIndex(of: CollectFixtures.embed(CollectFixtures.marqueUrn)))
        #expect(requested[(cafeEmbed + 1)..<marqueEmbed].allSatisfy { $0.hasPrefix("https://media.licdn.com/") })
    }

    @Test func aSecondRunAddsNothing() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        _ = try setUp(world)
        let collector = world.collector()
        _ = await collector.collectBranding(now: now)
        let before = world.http.requested.count
        let again = await collector.collectBranding(now: now.addingTimeInterval(3600))
        #expect(again.added.isEmpty && again.updated == 0)
        // Only the two company pages.
        #expect(world.http.requested.count == before + 2)
        #expect(again.statuses.last?.text(now: now) == "Lu à \(WebsiteCollectionTests.time(now.addingTimeInterval(3600))), aucun nouveau post")
        #expect(try world.store.items(kind: .branding).count == 3)
    }

    /// 999 and 429 skip the page until the next run; the other pages are read.
    @Test func linkedInsRefusalsSkipThePage() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        let pages = try setUp(world)
        world.http.page(CollectFixtures.atelierPage, html: "", status: 999)
        let collector = world.collector()
        let refused = await collector.collectBranding(now: now)
        #expect(refused.statuses.first?.text(now: now) == "LinkedIn refuse la lecture pour l'instant : réessai au prochain tour")
        #expect(refused.added.count == 2)
        world.http.page(CollectFixtures.atelierPage, html: "", status: 429)
        let slow = await collector.collectBranding(now: now)
        #expect(slow.statuses.first?.problem == "LinkedIn demande de ralentir : réessai au prochain tour")
        world.http.page(CollectFixtures.atelierPage, html: "", status: 404)
        let gone = await collector.collectBranding(now: now)
        #expect(gone.statuses.first?.problem == "Page introuvable : vérifie son lien")
        #expect(try world.store.sources().first { $0.id == pages.atelier.id }?.lastError == "Page introuvable : vérifie son lien")
        // The statuses Réglages reads: the last of each page.
        let statuses = await collector.statuses()
        #expect(statuses.map(\.name) == ["Atelier Nord", "Studio Exemple"])
        #expect(statuses.first?.isProblem == true && statuses.last?.isProblem == false)
    }

    /// An embed page refused (999): LinkedIn is not asked again for that page this time; the posts come from the
    /// company page's cards.
    @Test func aRefusedEmbedFallsBackOnTheCards() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        _ = try setUp(world)
        world.http.page(CollectFixtures.embed(CollectFixtures.cafeUrn), html: "", status: 999)
        world.http.image(CollectFixtures.media("D4E22AQExemple11", "feedshare-shrink_800", "carte11"), TestImages.jpeg(width: 800, height: 600))
        world.http.image(CollectFixtures.media("D4E22AQExemple12", "feedshare-shrink_800", "carte12"), TestImages.jpeg(width: 800, height: 600))
        let run = await world.collector().collectBranding(now: now)
        #expect(run.added.count == 2)
        #expect(!world.http.requested.contains(CollectFixtures.embed(CollectFixtures.marqueUrn)))
        let cafe = try #require(run.added.first)
        #expect(cafe.text == "Café Lumière by Atelier Nord\nUne identité chaleureuse pour un café de quartier.\nexemple.fr/cafe-lumiere")
        #expect(cafe.extra.hashtags == ["branding", "identite"] && cafe.images.count == 2)
        #expect(cafe.links == ["https://exemple.fr/cafe-lumiere"])
    }

    /// The same project posted by a second page: one item, both pages on it, the second id kept as an alias so
    /// it is never fetched again.
    @Test func theSameProjectFromTwoPagesIsOneItem() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        _ = try setUp(world)
        let collector = world.collector()
        _ = await collector.collectBranding(now: now)
        let repost = "7528100153191634567"
        world.http.page(CollectFixtures.atelierPage, html: """
            <html><body><ul>
            <li><article class="main-feed-activity-card" data-activity-urn="urn:li:activity:\(repost)">
            <p data-test-id="main-feed-activity-card__commentary">Café Lumière by Atelier Nord
            Notre nouvelle identité pour un café de quartier.</p>
            <img data-delayed-url="https://media.licdn.com/dms/image/v2/D4E22AQRepost1/feedshare-shrink_800/feedshare-shrink_800/0/1?e=1&amp;t=r">
            </article></li></ul></body></html>
            """)
        let run = await collector.collectBranding(now: now.addingTimeInterval(3600))
        #expect(run.added.isEmpty && run.updated == 1)
        let cafe = try #require(try world.store.item(kind: .branding, key: CollectFixtures.cafeUrn))
        #expect(cafe.sources == ["Studio Exemple", "Atelier Nord"])
        #expect(cafe.extra.aliases == [repost] && cafe.images.count == 5)
        #expect(try world.store.knownKeys(kind: .branding).contains(repost))
        #expect(!world.http.requested.contains { $0.contains("D4E22AQRepost1") })
        #expect(try world.store.items(kind: .branding).count == 3)
    }

    /// A post Paul deleted is never brought back, whichever page posts it again.
    @Test func aDeletedPostStaysDeleted() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        _ = try setUp(world)
        let collector = world.collector()
        let first = await collector.collectBranding(now: now)
        let cafe = try #require(first.added.first)
        try world.store.moveToTrash(id: cafe.id, at: now)
        let again = await collector.collectBranding(now: now.addingTimeInterval(3600))
        #expect(again.added.isEmpty)
        #expect(try world.store.item(id: cafe.id)?.deletedAt != nil)
    }

    /// An image too heavy is left aside; the others stay.
    @Test func aTooHeavyImageIsLeftAside() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        _ = try setUp(world)
        world.http.image(CollectFixtures.media("D4E22AQExemple11", "feedshare-shrink_2048_1536", "embed11"), Data(repeating: 7, count: 3_000_000))
        let run = await world.collector(configuration: .init(maxImageBytes: 2_000_000, linkedInPause: .zero)).collectBranding(now: now)
        let cafe = try #require(run.added.first)
        // 10 (GIF), 12, 13, 14, 15: the sixth candidate takes the heavy one's place; no still image first, so
        // 12 leads.
        #expect(cafe.images.count == 5)
        #expect(world.http.requested.contains(CollectFixtures.media("D4E22AQExemple15", "feedshare-shrink_2048_1536", "embed15")))
        #expect(world.pauses.count == 0)
    }

    /// The line drops while a new post's images come down (the Wi-Fi goes, the Mac falls asleep): the post is not
    /// kept for good with two images out of five; once the line is back, the next pass brings it whole (audit of 19/11).
    @Test func imagesCutByADroppedLineComeAtTheNextPass() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        _ = try setUp(world)
        // The café post's first two images come, then nothing comes until the line is back.
        let line = DroppingLine(world.http, imagesBeforeDrop: 2)
        let collector = world.collector(http: line)
        // Two passes as the app runs them (`InspirationAutomation.work`): the collection, then the images still missing.
        let cut = await collector.collectBranding(now: now)
        _ = await collector.completeImages(now: now)
        #expect(cut.statuses.last?.text(now: now) == "Pas de connexion à Internet : réessai au prochain tour")
        line.reconnect()
        let later = now.addingTimeInterval(6 * 3600)
        _ = await collector.collectBranding(now: later)
        _ = await collector.completeImages(now: later)
        let cafe = try #require(try world.store.item(kind: .branding, key: CollectFixtures.cafeUrn))
        #expect(cafe.images == (1...5).map { InspirationImageName.branding(urn: CollectFixtures.cafeUrn, index: $0) })
        // No half-written file left beside.
        #expect(!world.imageFiles(.branding).contains { $0.hasPrefix(".") })
    }

    /// Two collections never overlap: the second asked while the first runs does nothing.
    @Test func twoRunsNeverOverlap() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        _ = try setUp(world)
        world.http.delay = .milliseconds(30)
        let collector = world.collector()
        async let first = collector.collectBranding(now: now)
        async let second = collector.collectBranding(now: now)
        let runs = await [first, second]
        #expect(runs.filter(\.skipped).count == 1)
        #expect(try world.store.items(kind: .branding).count == 3)
    }

    /// Stopped midway (the app quits): nothing said as a failure, the run not counted.
    @Test func aStoppedRunSaysNothing() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        _ = try setUp(world)
        world.http.delay = .milliseconds(300)
        let runLog = CollectWorld.runLog()
        let collector = world.collector(runLog: runLog)
        let task = Task { await collector.collectBranding(now: now) }
        try await Task.sleep(for: .milliseconds(60))
        task.cancel()
        let run = await task.value
        #expect(run.statuses.isEmpty && run.added.isEmpty)
        #expect(runLog.lastRun(.branding) == nil)
        #expect(try world.store.sources().allSatisfy { $0.lastReadAt == nil && $0.lastError == nil })
    }

    /// Posts found on a page but that cannot be read (LinkedIn changed its page: no text, no image, on the cards
    /// nor on the embeds) are said as a problem, never « aucun nouveau post », and their embed pages are not asked
    /// again at the next run (review of 16/11).
    @Test func unreadablePostsAreSaidAndNotAskedAgain() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        _ = try world.store.saveSource(InspirationSourceRow(name: "Atelier Nord", link: CollectFixtures.atelierPage, createdAt: now))
        let first = "7529000000000000001", second = "7529000000000000002"
        world.http.page(CollectFixtures.atelierPage, html: """
            <html><body><ul>
            <li><article data-activity-urn="urn:li:activity:\(first)"><p class="nouvelle-classe">Une identité</p></article></li>
            <li><article data-activity-urn="urn:li:activity:\(second)"><p class="nouvelle-classe">Une autre</p></article></li>
            </ul></body></html>
            """)
        for urn in [first, second] {
            world.http.page(CollectFixtures.embed(urn), html: "<html><body><p class=\"autre-classe\">Texte</p></body></html>")
        }
        let collector = world.collector()
        let run = await collector.collectBranding(now: now)
        #expect(run.added.isEmpty)
        #expect(run.statuses.first?.problem == "Posts illisibles : LinkedIn a peut-être changé sa page")
        let before = world.http.requested.count
        let again = await collector.collectBranding(now: now.addingTimeInterval(3600))
        // Only the company page; still said.
        #expect(world.http.requested.count == before + 1)
        #expect(again.statuses.first?.problem == "Posts illisibles : LinkedIn a peut-être changé sa page")
    }

    /// One post without words nor image (a video) among readable ones: not a problem, and not asked again either.
    @Test func aPostWithoutWordsIsSkippedQuietlyOnce() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        _ = try setUp(world)
        let video = "7529000000000000003"
        let list = "<ul class=\"updates__list\">"
        let page = CollectFixtures.html("linkedin-entreprise.html").replacingOccurrences(
            of: list, with: list + "<li><article data-activity-urn=\"urn:li:activity:\(video)\"><video></video></article></li>")
        world.http.page(CollectFixtures.studioPage, html: page)
        world.http.page(CollectFixtures.embed(video), html: "<html><body><video></video></body></html>")
        let collector = world.collector()
        let run = await collector.collectBranding(now: now)
        #expect(run.added.count == 2 && run.statuses.last?.isProblem == false)
        _ = await collector.collectBranding(now: now.addingTimeInterval(3600))
        #expect(world.http.requested.filter { $0 == CollectFixtures.embed(video) }.count == 1)
    }

    /// Without any page followed, nothing is asked.
    @Test func withoutPagesNothingIsAsked() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        let run = await world.collector().collectBranding(now: now)
        #expect(run.statuses.isEmpty && run.added.isEmpty && world.http.requested.isEmpty)
    }
}
