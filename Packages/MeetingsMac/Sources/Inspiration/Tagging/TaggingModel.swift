import Foundation
import FoundationModels

/// What the tagger asks a model: the vocabulary's instructions, the item's text, the families as fixed choices.
public struct TaggingRequest: Sendable {
    public let vocabulary: InspirationVocabulary
    /// The system instructions (`InspirationVocabulary.instructions`, plus the reminder on the last attempt).
    public let instructions: String
    /// The item's text followed by the vocabulary's closing request (`suffixe`).
    public let prompt: String
    /// The second and last attempt: no randomness.
    public let isLastAttempt: Bool

    public init(vocabulary: InspirationVocabulary, instructions: String, prompt: String, isLastAttempt: Bool) {
        self.vocabulary = vocabulary
        self.instructions = instructions
        self.prompt = prompt
        self.isLastAttempt = isLastAttempt
    }
}

/// The model's answer, before the vocabulary's rules sort it.
public struct TaggingAnswer: Sendable, Equatable {
    /// Family → tags, as answered.
    public var categories: [String: [String]]
    /// `police`: the typefaces the text names.
    public var fonts: [String]
    /// What the client is, in a few French words.
    public var client: String

    public init(categories: [String: [String]], fonts: [String] = [], client: String = "") {
        self.categories = categories
        self.fonts = fonts
        self.client = client
    }
}

/// A model that tags a text: Apple's on the Mac, or a fake in the tests.
public protocol InspirationTaggingModel: Sendable {
    /// Whether it can answer now (Apple Intelligence on, the model downloaded).
    var isAvailable: Bool { get }
    func answer(_ request: TaggingRequest) async throws -> TaggingAnswer
}

/// The tagger's failures, sorted for the caller.
public enum TaggingModelError: Error, Equatable, Sendable {
    /// Unavailable for now (not downloaded, busy, too many requests): try another time, quietly.
    case unavailable
    /// The model declined this text: not asked again until the next launch.
    case refused
    /// The text did not fit.
    case tooLong
    case other(String)
}

/// Apple's model, built into macOS (`FoundationModels`, as the meetings' summaries): it runs in a system
/// service, nothing leaves the Mac. Guided generation: each family's answer can only be a tag of its list, at most
/// its maximum; the fonts and the client are free text.
public struct AppleTaggingModel: InspirationTaggingModel {
    public init() {}

    public var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    public func answer(_ request: TaggingRequest) async throws -> TaggingAnswer {
        let schema = try Self.schema(for: request.vocabulary)
        let session = LanguageModelSession(instructions: request.instructions)
        let options = GenerationOptions(temperature: request.isLastAttempt ? 0 : 0.1)
        do {
            // The instructions already list every tag with its meaning: the schema constrains the answer without
            // being written out again in the prompt (the window is small).
            let response = try await session.respond(to: request.prompt, schema: schema, includeSchemaInPrompt: false, options: options)
            return try Self.decode(response.content, vocabulary: request.vocabulary)
        } catch _ where Task.isCancelled {
            throw CancellationError()
        } catch let error as TaggingModelError {
            throw error
        } catch {
            throw Self.mapped(error)
        }
    }

    /// One property per family (an array of that family's tags, at most its maximum), then `police` (four names
    /// at most) and `client`, in the order of `ia_locale.py`'s JSON schema.
    public static func schema(for vocabulary: InspirationVocabulary) throws -> GenerationSchema {
        var properties: [DynamicGenerationSchema.Property] = vocabulary.families.map { family in
            let tag = DynamicGenerationSchema(name: "\(family.name)Tag", anyOf: family.tags.map(\.value))
            return DynamicGenerationSchema.Property(
                name: family.name, description: family.prompt,
                schema: DynamicGenerationSchema(arrayOf: tag, minimumElements: 0, maximumElements: max(1, family.maximum)))
        }
        properties.append(DynamicGenerationSchema.Property(
            name: "police", description: vocabulary.prompt?.fonts,
            schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self), minimumElements: 0, maximumElements: 4)))
        properties.append(DynamicGenerationSchema.Property(
            name: "client", description: vocabulary.prompt?.client, schema: DynamicGenerationSchema(type: String.self)))
        let root = DynamicGenerationSchema(name: "Categories", properties: properties)
        return try GenerationSchema(root: root, dependencies: [])
    }

    static func decode(_ content: GeneratedContent, vocabulary: InspirationVocabulary) throws -> TaggingAnswer {
        var categories: [String: [String]] = [:]
        for family in vocabulary.families {
            categories[family.name] = (try? content.value([String].self, forProperty: family.name)) ?? []
        }
        let fonts = (try? content.value([String].self, forProperty: "police")) ?? []
        let client = (try? content.value(String.self, forProperty: "client")) ?? ""
        return TaggingAnswer(categories: categories, fonts: fonts, client: client)
    }

    /// The model's errors, sorted (the same reading as the summaries': macOS 27 names them anew, the older names are
    /// kept).
    static func mapped(_ error: any Error) -> TaggingModelError {
        if let error = error as? LanguageModelError {
            switch error {
            case .contextSizeExceeded: return .tooLong
            case .guardrailViolation, .refusal: return .refused
            case .rateLimited: return .unavailable
            default: return .other(error.localizedDescription)
            }
        }
        if let error = error as? LanguageModelSession.Error, error == .concurrentRequests { return .unavailable }
        if error is SystemLanguageModel.Error { return .unavailable }
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize: return .tooLong
            case .guardrailViolation, .refusal: return .refused
            case .rateLimited, .concurrentRequests, .assetsUnavailable: return .unavailable
            default: return .other(error.localizedDescription)
            }
        }
        return .other(error.localizedDescription)
    }
}
