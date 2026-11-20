import Foundation
import FoundationModels
import Persistence
import Testing
@testable import Inspiration

/// A model as the tagger tests see it: canned answers, every request kept.
final class FakeTaggingModel: InspirationTaggingModel, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [Result<TaggingAnswer, TaggingModelError>]
    private var log: [TaggingRequest] = []
    let isAvailable: Bool

    init(available: Bool = true, answers: [Result<TaggingAnswer, TaggingModelError>] = []) {
        self.isAvailable = available
        self.answers = answers
    }

    var requests: [TaggingRequest] { lock.withLock { log } }

    func answer(_ request: TaggingRequest) async throws -> TaggingAnswer {
        let next: Result<TaggingAnswer, TaggingModelError> = lock.withLock {
            log.append(request)
            return answers.isEmpty ? .failure(.other("plus de réponse")) : answers.removeFirst()
        }
        return try next.get()
    }
}

/// A model that takes its time: each answer waits its delay, in order.
final class SlowTaggingModel: InspirationTaggingModel, @unchecked Sendable {
    private let lock = NSLock()
    private var delays: [Duration]
    let answer: TaggingAnswer
    let isAvailable = true

    init(delays: [Duration], answer: TaggingAnswer) {
        self.delays = delays
        self.answer = answer
    }

    func answer(_ request: TaggingRequest) async throws -> TaggingAnswer {
        let delay = lock.withLock { delays.isEmpty ? .zero : delays.removeFirst() }
        try await Task.sleep(for: delay)
        return answer
    }
}

/// The categories put by Apple's model (16/11), as `ia_locale.py` did: the text only, the vocabulary's tags only,
/// never on Paul's choice, nothing when the model is away.
@Suite struct TaggerTests {
    let now = Date(timeIntervalSince1970: 1_794_830_400)

    static let postText = """
        Café Lumière by Atelier Nord
        Une identité chaleureuse pour un café de quartier à Lyon : logo dessiné à la main, palette ocre et crème, enseigne \
        peinte, tasses, sacs et menus imprimés en Garamond Exemple. L'atelier a aussi dessiné le site et les affiches de \
        l'ouverture, avec une signalétique simple et des pictogrammes ronds.
        """

    func post(_ store: InspirationStore, text: String = TaggerTests.postText, byPaul: Bool = false,
              categories: [String: [String]] = [:]) throws -> InspirationItemRow {
        try store.upsert(InspirationItemRow(kind: .branding, key: UUID().uuidString, title: "Café Lumière", text: text, date: now,
                                            sources: ["Studio Exemple"], studio: "Atelier Nord", categories: categories,
                                            categoriesByPaul: byPaul, createdAt: now)).item
    }

    static let goodAnswer = TaggingAnswer(
        categories: ["secteur": ["restaurant"], "style": ["artisanal", "chaleureux-inconnu"], "typo": [], "support": ["signalétique", "packaging"]],
        fonts: ["Garamond Exemple", "serif", "Helvetica Inventée"], client: "café de quartier à Lyon.")

    /// An answer that drags on is given up at the time limit (16/11: Apple's model looped up to six minutes on a
    /// post): the item is passed, the next one is tagged.
    @Test func aSlowAnswerIsGivenUp() async throws {
        let database = try AppDatabase.inMemory()
        let store = InspirationStore(database)
        let slow = try post(store)
        let model = SlowTaggingModel(delays: [.seconds(30), .zero], answer: Self.goodAnswer)
        let tagger = InspirationTagger(database: database, model: model, answerTimeout: .milliseconds(200))
        let started = Date()
        #expect(await tagger.tag(id: slow.id, now: now) == .failed("L'IA d'Apple a mis trop de temps."))
        #expect(Date().timeIntervalSince(started) < 5)
        let next = try post(store)
        #expect(await tagger.tag(id: next.id, now: now) == .tagged(["secteur": ["restaurant"], "style": ["artisanal"], "support": ["signalétique", "packaging"]]))
    }

    @Test func aPostIsTaggedWithinTheVocabulary() async throws {
        let database = try AppDatabase.inMemory()
        let store = InspirationStore(database)
        let item = try post(store)
        let model = FakeTaggingModel(answers: [.success(Self.goodAnswer)])
        let outcome = await InspirationTagger(database: database, model: model).tag(id: item.id, now: now)
        // An unknown tag dropped, a font not in the text and a generic one dropped, the client tidied.
        let expected: [String: [String]] = ["secteur": ["restaurant"], "style": ["artisanal"], "support": ["signalétique", "packaging"]]
        #expect(outcome == .tagged(expected))
        let tagged = try #require(try store.item(id: item.id))
        #expect(tagged.categories == expected && !tagged.categoriesByPaul)
        #expect(tagged.fonts == ["Garamond Exemple"] && tagged.client == "café de quartier à Lyon")
        // The text read: the vault's header, then the post; the vocabulary's request after it.
        let request = try #require(model.requests.first)
        #expect(request.prompt.hasPrefix("Brand: Café Lumière\nStudio: Atelier Nord\n\nCafé Lumière by Atelier Nord\nUne identité chaleureuse"))
        #expect(request.prompt.hasSuffix(try #require(InspirationVocabulary.bundled(.branding).prompt?.suffix)))
        #expect(request.instructions.hasPrefix("You classify branding case studies") && !request.isLastAttempt)
        #expect(request.instructions.contains("  restaurant: restaurant, bar, café"))
        #expect(model.requests.count == 1)
    }

    /// Too few tags or no client: asked once more with the reminder, without randomness; the second answer kept
    /// when it has any tag.
    @Test func aWeakAnswerIsAskedAgainOnce() async throws {
        let database = try AppDatabase.inMemory()
        let store = InspirationStore(database)
        let item = try post(store)
        let weak = TaggingAnswer(categories: ["secteur": ["restaurant"]], client: "")
        let better = TaggingAnswer(categories: ["secteur": ["restaurant"], "style": ["artisanal"]], client: "café")
        let model = FakeTaggingModel(answers: [.success(weak), .success(better)])
        let outcome = await InspirationTagger(database: database, model: model).tag(id: item.id, now: now)
        #expect(outcome == .tagged(["secteur": ["restaurant"], "style": ["artisanal"]]))
        #expect(model.requests.count == 2)
        let reminder = try #require(InspirationVocabulary.bundled(.branding).prompt?.reminder)
        #expect(model.requests[1].isLastAttempt && model.requests[1].instructions.hasSuffix(reminder))
        // Nothing usable twice: nothing written.
        let empty = try post(store)
        let nothing = FakeTaggingModel(answers: [.success(TaggingAnswer(categories: ["secteur": ["inconnu"]])), .success(TaggingAnswer(categories: [:]))])
        let failed = await InspirationTagger(database: database, model: nothing).tag(id: empty.id, now: now)
        #expect(failed == .failed("Aucune catégorie utilisable dans la réponse."))
        #expect(try store.item(id: empty.id)?.categories.isEmpty == true)
    }

    @Test func paulsCategoriesAreNeverTouched() async throws {
        let database = try AppDatabase.inMemory()
        let store = InspirationStore(database)
        let item = try post(store, byPaul: true, categories: ["secteur": ["culture"]])
        let model = FakeTaggingModel(answers: [.success(Self.goodAnswer)])
        let tagger = InspirationTagger(database: database, model: model)
        #expect(await tagger.tag(id: item.id, now: now) == .byPaul)
        #expect(await tagger.tagPending(now: now) == 0)
        #expect(model.requests.isEmpty)
        #expect(try store.item(id: item.id)?.categories == ["secteur": ["culture"]])
    }

    /// Fewer words than the vocabulary asks (40 for a post, 8 for a site, header aside): no call.
    @Test func aShortTextIsNotSubmitted() async throws {
        let database = try AppDatabase.inMemory()
        let store = InspirationStore(database)
        let item = try post(store, text: "Nouvelle identité pour un café. #branding")
        let model = FakeTaggingModel(answers: [.success(Self.goodAnswer)])
        #expect(await InspirationTagger(database: database, model: model).tag(id: item.id, now: now) == .tooShort)
        #expect(model.requests.isEmpty)
    }

    /// Without Apple Intelligence: nothing, quietly.
    @Test func withoutTheModelNothingHappens() async throws {
        let database = try AppDatabase.inMemory()
        let store = InspirationStore(database)
        let item = try post(store)
        let away = FakeTaggingModel(available: false, answers: [.success(Self.goodAnswer)])
        let tagger = InspirationTagger(database: database, model: away)
        #expect(await tagger.tag(id: item.id, now: now) == .unavailable)
        #expect(await tagger.tagPending(now: now) == 0)
        #expect(away.requests.isEmpty)
        let busy = FakeTaggingModel(answers: [.failure(.unavailable)])
        #expect(await InspirationTagger(database: database, model: busy).tag(id: item.id, now: now) == .unavailable)
        #expect(try store.item(id: item.id)?.categories.isEmpty == true)
    }

    @Test func mockupsAreNotTagged() async throws {
        let database = try AppDatabase.inMemory()
        let store = InspirationStore(database)
        let mockup = try store.upsert(InspirationItemRow(kind: .mockup, key: "Affiche", title: "Affiche", text: String(repeating: "mot ", count: 50),
                                                         date: now, createdAt: now)).item
        let model = FakeTaggingModel(answers: [.success(Self.goodAnswer)])
        #expect(await InspirationTagger(database: database, model: model).tag(id: mockup.id, now: now) == .notTaggable)
        #expect(model.requests.isEmpty)
    }

    /// The items without categories, the newest first, at most `limit`; one the model refused is not asked again.
    @Test func thePendingItemsAreTagged() async throws {
        let database = try AppDatabase.inMemory()
        let store = InspirationStore(database)
        let refused = try post(store)
        _ = try post(store, categories: ["secteur": ["culture"]])
        _ = try post(store, text: "Trop court.")
        let site = try store.upsert(InspirationItemRow(
            kind: .website, key: "https://lumiere.exemple.fr", title: "Lumière Exemple — Studio d'éclairage",
            text: "Un studio d'éclairage qui dessine la lumière des lieux culturels : effets WebGL et typographie éditoriale.",
            url: "https://lumiere.exemple.fr/", date: now.addingTimeInterval(60), createdAt: now)).item
        #expect(InspirationTagger.needsTagging(site) && InspirationTagger.needsTagging(refused))
        let model = FakeTaggingModel(answers: [
            .success(TaggingAnswer(categories: ["secteur": ["agence"], "style": ["éditorial"], "techno": ["shaders"], "support": ["vitrine"]], client: "studio d'éclairage")),
            .failure(.refused),
        ])
        let tagger = InspirationTagger(database: database, model: model)
        #expect(await tagger.tagPending(now: now) == 1)
        let tagged = try #require(try store.item(id: site.id))
        #expect(tagged.categories["techno"] == ["shaders"] && tagged.client == "studio d'éclairage")
        #expect(model.requests.first?.prompt.hasPrefix("Title: Lumière Exemple — Studio d'éclairage\nSite: https://lumiere.exemple.fr/\n\n") == true)
        // The refused post is not asked again this launch.
        #expect(await tagger.tagPending(now: now) == 0)
        #expect(model.requests.count == 2)
    }

    /// The tags no vocabulary knows (kept from the vault) stay beside the model's.
    @Test func unknownTagsStay() async throws {
        let database = try AppDatabase.inMemory()
        let store = InspirationStore(database)
        let item = try post(store, categories: ["autres": ["fait-main"]])
        #expect(InspirationTagger.needsTagging(item))
        let model = FakeTaggingModel(answers: [.success(Self.goodAnswer)])
        _ = await InspirationTagger(database: database, model: model).tag(id: item.id, now: now)
        #expect(try store.item(id: item.id)?.categories["autres"] == ["fait-main"])
    }

    /// The vocabulary's bounds: « autre » only alone, a family at most its maximum, the total trimmed in the
    /// vocabulary's order.
    @Test func theRulesKeepTheBounds() throws {
        let branding = try InspirationVocabulary.bundled(.branding)
        let answer = TaggingAnswer(categories: [
            "secteur": ["autre", "restaurant", "boisson", "alimentation"],
            "style": ["minimal", "moderne", "rétro", "ludique"],
            "typo": ["empattement", "script"],
            "support": ["logo", "packaging", "signalétique", "affiche", "site"],
        ], fonts: [], client: String(repeating: "très ", count: 12) + "long")
        let result = TaggingRules.validate(answer, vocabulary: branding, text: "")
        #expect(result.categories["secteur"] == ["restaurant", "boisson"])
        #expect(result.total == 8)
        // Trimmed from `support` first (the vocabulary's `rognage`), down to one.
        #expect(result.categories["support"] == ["logo"] && result.categories["style"] == ["minimal", "moderne", "rétro"])
        #expect(result.categories["typo"] == ["empattement", "script"])
        #expect(result.client?.split(separator: " ").count == 10)
        #expect(result.problems.isEmpty)
    }

    /// The schema the model answers in: one property per family whose answers are that family's tags only.
    @Test func theSchemaFollowsTheVocabulary() throws {
        for kind in [InspirationKind.website, .branding] {
            let vocabulary = try InspirationVocabulary.bundled(kind)
            let schema = try AppleTaggingModel.schema(for: vocabulary)
            let description = String(describing: schema)
            for family in vocabulary.families {
                #expect(description.contains(family.name), "\(kind) \(family.name)")
            }
            #expect(description.contains("police") && description.contains("client"))
        }
    }
}

/// The real model on this Mac, on an invented post: run by hand (`HUB_MODELE_APPLE=1`) to measure, never by
/// `make check`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["HUB_MODELE_APPLE"] != nil))
struct AppleTaggerMeasureTests {
    @Test func theRealModelTagsAnInventedPost() async throws {
        let database = try AppDatabase.inMemory()
        let store = InspirationStore(database)
        let item = try store.upsert(InspirationItemRow(kind: .branding, key: "1", title: "Café Lumière", text: TaggerTests.postText,
                                                       date: Date(), studio: "Atelier Nord", createdAt: Date())).item
        let vocabulary = try InspirationVocabulary.bundled(.branding)
        let model = SystemLanguageModel.default
        let instructions = try await model.tokenCount(for: Instructions(vocabulary.instructions ?? ""))
        let schema = try await model.tokenCount(for: AppleTaggingModel.schema(for: vocabulary))
        let start = Date()
        let outcome = await InspirationTagger(database: database).tag(id: item.id)
        let seconds = Date().timeIntervalSince(start)
        let tagged = try store.item(id: item.id)
        print("MESURE tagger: \(String(format: "%.1f", seconds)) s ; fenêtre \(model.contextSize) jetons ; consignes \(instructions) ; schéma \(schema)")
        print("MESURE résultat: \(outcome) ; polices \(tagged?.fonts ?? []) ; client \(tagged?.client ?? "-")")
        if case .tagged = outcome {} else { Issue.record("pas de catégories : \(outcome)") }
    }
}
