import Foundation
import Persistence

/// The categories of a site or a branding post, put by Apple's model on the Mac (16/11), as the vault's
/// `ia_locale.py` did with a local model: the text only (never the images), the answer limited to the
/// vocabulary's tags, the families' bounds kept, the fonts checked against the text. Never on an item whose
/// categories Paul chose; a text too short to say anything is not submitted; without Apple Intelligence, nothing
/// happens and nothing is said. Mock-ups are not tagged (their types are Paul's).
public actor InspirationTagger {
    public enum Outcome: Sendable, Equatable {
        /// Written: the categories now on the item.
        case tagged([String: [String]])
        /// Paul chose its categories: left alone.
        case byPaul
        /// Fewer words than the vocabulary asks for.
        case tooShort
        /// A mock-up, or a vocabulary without the tagger's prompt.
        case notTaggable
        /// The model cannot answer now: nothing done, nothing said.
        case unavailable
        case notFound
        case cancelled
        /// The model's answer could not be used, in plain words.
        case failed(String)
    }

    /// Longer texts are cut: the model's window is small, and the start of a post says what it is.
    public static let maxCharacters = 2_500

    let store: InspirationStore
    let paths: AppPaths?
    let model: any InspirationTaggingModel
    private var vocabularies: [InspirationKind: InspirationVocabulary] = [:]
    /// The items the model declined or could not tag since the launch: not asked again.
    private var declined: Set<UUID> = []

    /// `paths`: where Polhub's copy of the vocabularies is; without it, the bundled ones.
    /// `answerTimeout`: what one answer of the model may take (16/11: it looped up to six minutes on a post, the Mac
    /// working for nothing meanwhile); past it, the item is passed until the next launch.
    public init(database: AppDatabase, paths: AppPaths? = nil, model: any InspirationTaggingModel = AppleTaggingModel(),
                answerTimeout: Duration = .seconds(45)) {
        self.store = InspirationStore(database)
        self.paths = paths
        self.model = model
        self.answerTimeout = answerTimeout
    }

    let answerTimeout: Duration

    /// The model's answer, or `tooSlow` past the time limit (the answer under way is cancelled).
    private func answer(_ request: TaggingRequest) async throws -> TaggingAnswer {
        let model = model, timeout = answerTimeout
        return try await withThrowingTaskGroup(of: TaggingAnswer.self) { group in
            group.addTask { try await model.answer(request) }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw TaggingModelError.tooSlow
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CancellationError() }
            return first
        }
    }

    /// Whether the model can answer now.
    public var isAvailable: Bool { model.isAvailable }

    /// An item the tagger would take: a site or a post, not deleted, without categories, not Paul's.
    public static func needsTagging(_ item: InspirationItemRow) -> Bool {
        item.kind != .mockup && item.deletedAt == nil && !item.categoriesByPaul
            && item.categories.filter({ $0.key != InspirationVocabulary.otherFamily && !$0.value.isEmpty }).isEmpty
    }

    /// The vocabulary of a kind, read once.
    func vocabulary(_ kind: InspirationKind) -> InspirationVocabulary {
        if let known = vocabularies[kind] { return known }
        let loaded = InspirationVocabulary.load(kind, paths: paths)
        vocabularies[kind] = loaded
        return loaded
    }

    /// Tags one item, whatever categories it has (unless Paul chose them).
    @discardableResult
    public func tag(id: UUID, now: Date = Date()) async -> Outcome {
        guard let item = try? store.item(id: id), item.deletedAt == nil else { return .notFound }
        guard !item.categoriesByPaul else { return .byPaul }
        guard item.kind != .mockup else { return .notTaggable }
        let vocabulary = vocabulary(item.kind)
        guard let instructions = vocabulary.instructions, let prompt = vocabulary.prompt, !vocabulary.families.isEmpty else { return .notTaggable }
        let text = Self.text(of: item, vocabulary: vocabulary)
        guard !vocabulary.isTooShort(text) else { return .tooShort }
        guard model.isAvailable else { return .unavailable }
        let submitted = String(text.prefix(Self.maxCharacters)) + "\n\n" + prompt.suffix
        var kept: TaggingRules.Result?
        for attempt in 1...2 {
            let last = attempt == 2
            let request = TaggingRequest(vocabulary: vocabulary, instructions: last ? instructions + "\n\n" + prompt.reminder : instructions,
                                         prompt: submitted, isLastAttempt: last)
            let answer: TaggingAnswer
            do {
                answer = try await self.answer(request)
            } catch is CancellationError {
                return .cancelled
            } catch TaggingModelError.unavailable {
                return .unavailable
            } catch TaggingModelError.tooSlow {
                declined.insert(id)
                // « l'IA d'Apple », never « le modèle » (lot 10, 20/11).
                return .failed("L'IA d'Apple a mis trop de temps.")
            } catch TaggingModelError.refused {
                declined.insert(id)
                return .failed("L'IA d'Apple a refusé ce texte.")
            } catch TaggingModelError.tooLong {
                declined.insert(id)
                return .failed("Le texte est trop long pour l'IA d'Apple.")
            } catch {
                declined.insert(id)
                return .failed("L'IA d'Apple n'a pas répondu.")
            }
            let result = TaggingRules.validate(answer, vocabulary: vocabulary, text: text)
            // Too few tags, or no client: asked once more, with the reminder.
            if result.problems.isEmpty || last {
                kept = result
                break
            }
        }
        guard let kept, kept.total > 0 else {
            declined.insert(id)
            return .failed("Aucune catégorie utilisable dans la réponse.")
        }
        // The tags no vocabulary knows (kept from the vault) stay; a font or a client the answer misses stays too.
        var categories = kept.categories
        if let others = item.categories[InspirationVocabulary.otherFamily], !others.isEmpty { categories[InspirationVocabulary.otherFamily] = others }
        let fonts = kept.fonts.isEmpty ? item.fonts : kept.fonts
        guard (try? store.applyTagging(id: id, categories: categories, fonts: fonts, client: kept.client ?? item.client, at: now)) == true else {
            return (try? store.item(id: id))?.categoriesByPaul == true ? .byPaul : .notFound
        }
        return .tagged(InspirationMerge.cleaned(categories))
    }

    /// Tags the items that need it (`needsTagging`), the newest first, at most `limit`; skips those the model
    /// declined since the launch. Stops at once when the model is unavailable or the task is cancelled. Returns how
    /// many were tagged.
    @discardableResult
    public func tagPending(kinds: [InspirationKind] = [.website, .branding], limit: Int = 25, now: Date = Date()) async -> Int {
        guard model.isAvailable else { return 0 }
        var tagged = 0
        var tried = 0
        for kind in kinds where kind != .mockup {
            let pending = ((try? store.items(kind: kind)) ?? []).filter { Self.needsTagging($0) && !declined.contains($0.id) }
            for item in pending {
                guard tried < limit, !Task.isCancelled else { return tagged }
                switch await tag(id: item.id, now: now) {
                case .tagged:
                    tagged += 1
                    tried += 1
                case .unavailable, .cancelled:
                    return tagged
                case .failed:
                    tried += 1
                case .tooShort, .byPaul, .notTaggable, .notFound:
                    continue
                }
            }
        }
        return tagged
    }

    /// The text the model reads, built as the vault built it: the header (« Brand: … / Studio: … », « Title: … /
    /// Site: … »), then the item's words.
    static func text(of item: InspirationItemRow, vocabulary: InspirationVocabulary) -> String {
        var fields: [String: String] = [
            "titre": item.title, "title": item.title, "file.name": item.title,
            "studio": item.studio ?? "", "site": item.url ?? item.key, "url": item.url ?? item.key,
            "source": item.sources.first ?? "", "client": item.client ?? "",
        ]
        fields = fields.filter { !$0.value.isEmpty }
        return vocabulary.taggingText(fields: fields, body: item.text)
    }
}

/// The vocabulary's rules applied to an answer (`ia_locale.py`'s `valider`): a tag outside its family's list is
/// dropped, « autre » only alone, each family at most its maximum, the total trimmed in the vocabulary's order;
/// a font kept only when the text names it and it is not a generic word; the client folded to ten words.
public enum TaggingRules {
    public struct Result: Sendable, Equatable {
        public var categories: [String: [String]]
        public var fonts: [String]
        public var client: String?
        /// Why the answer is weak: too few tags, no client.
        public var problems: [String]
        /// What was dropped, for the record.
        public var dropped: [String]

        public var total: Int { categories.values.reduce(0) { $0 + $1.count } }
    }

    static let genericFonts: Set<String> = ["sans", "sans serif", "sans-serif", "serif", "custom", "typeface", "typography",
                                            "font", "bold", "regular", "italic", "display", "script", "mono", "monospace"]
    static let clientMaxWords = 10

    public static func validate(_ answer: TaggingAnswer, vocabulary: InspirationVocabulary, text: String) -> Result {
        var categories: [String: [String]] = [:]
        var dropped: [String] = []
        var problems: [String] = []
        for family in vocabulary.families {
            var kept: [String] = []
            for raw in answer.categories[family.name] ?? [] {
                let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !tag.isEmpty else { continue }
                if family.contains(tag) {
                    if !kept.contains(tag) { kept.append(tag) }
                } else {
                    dropped.append("\(family.name):\(tag)")
                }
            }
            if kept.contains("autre"), kept.count > 1 { kept.removeAll { $0 == "autre" } }
            categories[family.name] = Array(kept.prefix(max(0, family.maximum)))
        }
        var total = categories.values.reduce(0) { $0 + $1.count }
        let order = vocabulary.trimOrder.isEmpty ? vocabulary.families.map(\.name).reversed() : vocabulary.trimOrder
        while total > vocabulary.maximumTotal, vocabulary.maximumTotal > 0 {
            guard let family = order.first(where: { (categories[$0]?.count ?? 0) > 1 }) else { break }
            categories[family]?.removeLast()
            total -= 1
        }
        if total < vocabulary.minimumTotal { problems.append("\(total) catégorie(s) seulement") }
        let lowered = text.lowercased()
        var fonts: [String] = []
        for raw in answer.fonts {
            let font = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"")).trimmingCharacters(in: .whitespaces)
            guard !font.isEmpty, !genericFonts.contains(font.lowercased()) else { continue }
            guard lowered.contains(font.lowercased()) else {
                dropped.append("police:\(font) (absente du texte)")
                continue
            }
            if !fonts.contains(font) { fonts.append(font) }
        }
        var client = answer.client.split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        if client.isEmpty {
            problems.append("client vide")
        } else if client.split(separator: " ").count > clientMaxWords {
            dropped.append("client trop long, coupé : \(client)")
            client = client.split(separator: " ").prefix(clientMaxWords).joined(separator: " ")
        }
        return Result(categories: InspirationMerge.cleaned(categories), fonts: fonts, client: client.isEmpty ? nil : client,
                      problems: problems, dropped: dropped)
    }
}
