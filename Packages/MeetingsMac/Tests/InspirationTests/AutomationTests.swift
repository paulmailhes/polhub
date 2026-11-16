import Foundation
import Persistence
import Testing
@testable import Inspiration

/// What the app runs of « Inspiration » (16/11): the collections due at each look at the clock, then the categories
/// of what came in; nothing when the conditions say no (a meeting, the setting off, the development build); a pass
/// stopped midway records nothing; Paul's gestures said in plain words.
@Suite struct AutomationTests {
    /// 16/11/2026, 10:30 UTC: the 10 h slot of the sites and the 9 h slot of the branding have passed.
    let now = Date(timeIntervalSince1970: 1_794_825_000)

    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static let siteAnswer = TaggingAnswer(categories: ["secteur": ["agence"], "style": ["éditorial"], "support": ["vitrine"]],
                                          client: "studio d'éclairage")

    /// Who was asked, and the conditions of the pass (changed by the tests).
    final class Gates: @unchecked Sendable {
        private let lock = NSLock()
        private var collect = true
        private var tag = true
        private var ai = true

        func set(collect: Bool? = nil, tag: Bool? = nil, ai: Bool? = nil) {
            lock.withLock {
                if let collect { self.collect = collect }
                if let tag { self.tag = tag }
                if let ai { self.ai = ai }
            }
        }

        var conditions: InspirationAutomation.Conditions {
            InspirationAutomation.Conditions(mayCollect: { self.lock.withLock { self.collect } },
                                             mayTag: { self.lock.withLock { self.tag } },
                                             aiCategories: { self.lock.withLock { self.ai } })
        }
    }

    func served(_ world: CollectWorld) {
        world.http.page(AwwwardsHome.address.absoluteString, fixture: "awwwards-accueil.html")
        world.http.page(CollectFixtures.lumiere, fixture: "site-lumiere.html")
        world.http.image(CollectFixtures.lumiereImage, TestImages.jpeg(width: 1200, height: 630))
    }

    func automation(_ world: CollectWorld, runLog: CollectionRunLog, model: FakeTaggingModel, gates: Gates) -> InspirationAutomation {
        InspirationAutomation(collector: world.collector(runLog: runLog), tagger: InspirationTagger(database: world.database, model: model),
                              runLog: runLog, schedule: CollectionSchedule(calendar: Self.utc), conditions: gates.conditions)
    }

    @Test func aLookAtTheClockRunsWhatIsDueThenTagsWhatCameIn() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        served(world)
        let runLog = CollectWorld.runLog()
        let model = FakeTaggingModel(answers: [.success(Self.siteAnswer)])
        let automation = automation(world, runLog: runLog, model: model, gates: Gates())
        await automation.tick(now: now)
        let site = try #require(try world.store.item(kind: .website, key: "https://lumiere.exemple.fr"))
        #expect(site.categories == ["secteur": ["agence"], "style": ["éditorial"], "support": ["vitrine"]] && !site.categoriesByPaul)
        #expect(runLog.lastRun(.websites) == now && runLog.lastRun(.branding) == now)
        #expect(model.requests.count == 1)
        #expect(await !automation.isRunning)

        // Ten minutes later, nothing is due: Awwwards is not asked again, nor the model.
        let asked = world.http.requested.count
        await automation.tick(now: now.addingTimeInterval(600))
        #expect(world.http.requested.count == asked && model.requests.count == 1)
    }

    /// A meeting under way, the setting off, the development build: no request, no model; the slots stay due.
    @Test func nothingRunsWhenTheConditionsSayNo() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        served(world)
        try world.store.upsert(InspirationItemRow(kind: .website, key: "https://ancien.exemple.fr", title: "Ancien",
                                                  text: "Un site ancien sans aucune catégorie encore, avec assez de mots pour le modèle.",
                                                  date: now, createdAt: now))
        let runLog = CollectWorld.runLog()
        let model = FakeTaggingModel(answers: [.success(Self.siteAnswer)])
        let gates = Gates()
        gates.set(collect: false, tag: false)
        let automation = automation(world, runLog: runLog, model: model, gates: gates)
        await automation.tick(now: now)
        #expect(world.http.requested.isEmpty && model.requests.isEmpty)
        #expect(runLog.lastRuns.isEmpty)

        // The AI off: the model is never asked, even when it may run.
        gates.set(tag: true, ai: false)
        await automation.tick(now: now)
        #expect(model.requests.isEmpty)
        // On again: the item left without categories is tagged at the next look.
        gates.set(ai: true)
        await automation.tick(now: now)
        #expect(model.requests.count == 1)
        #expect(try world.store.item(kind: .website, key: "https://ancien.exemple.fr")?.categories.isEmpty == false)
    }

    /// A meeting starts during a pass: it stops at once, nothing is recorded, and the slot is still due.
    @Test func aPassStoppedMidwayRecordsNothing() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        served(world)
        world.http.delay = .seconds(5)
        let runLog = CollectWorld.runLog()
        let model = FakeTaggingModel(answers: [.success(Self.siteAnswer)])
        let automation = automation(world, runLog: runLog, model: model, gates: Gates())
        let pass = Task { await automation.tick(now: now) }
        for _ in 0..<200 where world.http.requested.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        // A second look while the first runs does nothing.
        await automation.tick(now: now)
        #expect(world.http.requested.count == 1)
        await automation.stop()
        await pass.value
        #expect(runLog.lastRun(.websites) == nil && model.requests.isEmpty)
        #expect(try world.store.items(kind: .website).isEmpty)
        #expect(await !automation.isRunning)
        #expect(CollectionSchedule(calendar: Self.utc).due(lastRuns: runLog.lastRuns, now: now).contains(.websites))
    }

    /// A site added by hand is tagged at once when the AI is on; « Proposer des catégories » says what stops it.
    @Test func paulsGesturesAreTaggedOrSaid() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        served(world)
        let runLog = CollectWorld.runLog()
        let model = FakeTaggingModel(answers: [.success(Self.siteAnswer)])
        let gates = Gates()
        // The model runs for Paul's gestures even when the background may not (a meeting).
        gates.set(tag: false)
        let automation = automation(world, runLog: runLog, model: model, gates: gates)
        let id = try await automation.addSite(url: try #require(URL(string: CollectFixtures.lumiere)))
        for _ in 0..<200 where (try? world.store.item(id: id))?.categories.isEmpty != false { try await Task.sleep(for: .milliseconds(10)) }
        #expect(try world.store.item(id: id)?.categories["secteur"] == ["agence"])

        try world.store.setCategories(id: id, ["style": ["minimal"]], at: now)
        await #expect(throws: InspirationTagError.byPaul) { try await automation.tag(id: id) }
        gates.set(ai: false)
        await #expect(throws: InspirationTagError.turnedOff) { try await automation.tag(id: id) }
        #expect(InspirationTagError.turnedOff.localizedDescription == "Les catégories par l'IA d'Apple sont coupées dans Réglages › Inspiration.")
        #expect(model.requests.count == 1)
    }
}
