import Foundation
import FoundationModels

/// Apple's model, built into macOS: it runs in a system service, never in the app's memory, and nothing
/// leaves the Mac (measured on 14/11: about a minute and a half for an hour of meeting).
public struct AppleSummaryEngine: SummaryEngine {
    public init() {}

    /// « l'IA d'Apple », never « le modèle » (lot 10, 20/11); « Apple Intelligence », the setting of macOS.
    public var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.appleIntelligenceNotEnabled): "Active Apple Intelligence dans Réglages Système pour avoir les comptes rendus."
        case .unavailable(.modelNotReady): "L'IA d'Apple se prépare (macOS le télécharge) : les comptes rendus suivront."
        case .unavailable(.deviceNotEligible): "Ce Mac ne peut pas faire tourner l'IA d'Apple."
        case .unavailable: "L'IA d'Apple n'est pas disponible pour l'instant."
        }
    }

    static let notesInstructions = """
        Tu prends des notes de réunion en français. « Moi » est l'utilisateur de l'application, qui a enregistré la réunion ; \
        « Les autres » sont ses interlocuteurs. N'invente rien : seulement ce qui est dit dans l'extrait.
        """
    static let mergeInstructions = """
        Tu fusionnes des notes de réunion en français, prises partie par partie, en notes plus courtes. « Moi » est \
        l'utilisateur de l'application. Garde les décisions et les actions avec leur porteur et leur échéance ; fusionne \
        les doublons ; n'invente rien.
        """
    static let summaryInstructions = """
        Tu rédiges le compte rendu d'une réunion en français, à partir des notes prises partie par partie. « Moi » est \
        l'utilisateur de l'application. Fusionne les doublons, garde l'essentiel, n'invente rien. Une décision est ce qui a été \
        arrêté ; une action est ce que quelqu'un fera après la réunion.
        """
    /// What a refused passage is asked again with, as plain text (15/11).
    static let plainNotesRequest = """
        Écris des notes en trois parties, « Points : », « Décisions : » et « Actions : », une ligne commençant par « - » \
        pour chaque élément.
        """
    /// An invented exchange, for the model's count of characters per token (15/11).
    static let sample = """
        [12:04] Moi : Bon, on reprend la maquette de l'accueil : la photo du haut est trop sombre, on la change ?
        [12:10] Les autres : D'accord, j'en envoie trois autres d'ici jeudi, avec les textes de la page des services.
        [12:21] Moi : Parfait. Et pour le devis, je le refais avec deux options, l'une sans le blog, l'autre avec.
        [12:35] Les autres : Très bien, on en parle vendredi en début d'après-midi, après la réunion de l'équipe.
        """

    /// The window, less the instructions, the schema and the answer, in characters of French: the larger request
    /// (the summary's) counts. Ten thousand characters at most, as measured on 14/11; the window and the ratio
    /// are the model's own counts, not measured by hand (15/11).
    public func characterBudget() async -> Int {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return SummaryPlan.maxCharacters }
        do {
            let notes = try await model.tokenCount(for: Instructions(Self.notesInstructions)) + model.tokenCount(for: PartNotes.generationSchema)
            let summary = try await model.tokenCount(for: Instructions(Self.summaryInstructions)) + model.tokenCount(for: Summary.generationSchema)
            let sampleTokens = try await model.tokenCount(for: Self.sample)
            return SummaryPlan.characterBudget(contextSize: model.contextSize, fixedTokens: max(notes, summary),
                                               sampleCharacters: Self.sample.count, sampleTokens: sampleTokens)
        } catch {
            return SummaryPlan.maxCharacters
        }
    }

    public func notes(for chunk: String, part: Int, of count: Int) async throws -> String {
        try await partNotes(for: chunk, part: part, of: count).text
    }

    public func partNotes(for chunk: String, part: Int, of count: Int) async throws -> SummaryNote {
        let prompt = "Extrait \(part) sur \(count) de la transcription :\n\n" + chunk
        do {
            let session = LanguageModelSession(instructions: Self.notesInstructions)
            let notes = try await respond { try await session.respond(to: prompt, generating: PartNotes.self).content }
            return SummaryNote(text: notes.text(part: part))
        } catch SummaryError.refused {
            // Asked again as plain text, with the guardrails Apple gives to the transformations of a text: they only
            // relax answers in text (not measured on French meetings, 15/11). Refused again, the part is left out.
            // The summary, asked with the usual guardrails, can do without these notes if it is refused.
            let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
            let session = LanguageModelSession(model: model, instructions: Self.notesInstructions)
            let text = try await respond { try await session.respond(to: prompt + "\n\n" + Self.plainNotesRequest).content }
            return SummaryNote(text: "Partie \(part)\n" + text.trimmingCharacters(in: .whitespacesAndNewlines), relaxed: true)
        }
    }

    public func merge(_ notes: String, part: Int, of count: Int) async throws -> String {
        let session = LanguageModelSession(instructions: Self.mergeInstructions)
        let merged = try await respond {
            try await session.respond(to: "Notes \(part) sur \(count) à fusionner :\n\n" + notes, generating: PartNotes.self).content
        }
        return merged.text(part: part)
    }

    public func summary(of notes: [String], title: String) async throws -> MeetingSummary {
        let session = LanguageModelSession(instructions: Self.summaryInstructions)
        let answer = try await respond {
            try await session.respond(to: "Titre de la réunion : \(title)\n\nNotes :\n\n" + notes.joined(separator: "\n\n"), generating: Summary.self).content
        }
        return MeetingSummary(overview: answer.resume, points: answer.points, decisions: answer.decisions,
                              actions: answer.actions.map { SummaryAction(text: $0.texte, owner: $0.porteur, due: $0.echeance) })
    }

    /// The model's refusals and limits, said in French.
    private func respond<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch _ where Task.isCancelled {
            // Stopped by a meeting: never a failure (review of 14/11, Important 4).
            throw CancellationError()
        } catch {
            throw Self.mapped(error)
        }
    }

    static let busy = "L'IA d'Apple est occupé : le compte rendu reprendra un peu plus tard."

    /// macOS 27 names the model's errors anew (`LanguageModelError`); the older names are kept, in case. A limit of
    /// the moment (too many requests, another one under way) waits a minute and is never a failure (15/11).
    static func mapped(_ error: any Error) -> any Error {
        if let error = error as? LanguageModelError {
            switch error {
            case .contextSizeExceeded: return SummaryError.tooLong
            case .guardrailViolation, .refusal: return SummaryError.refused
            case .rateLimited: return SummaryError.unavailable(busy)
            case .unsupportedLanguageOrLocale: return SummaryError.model("L'IA d'Apple ne prend pas cette langue.")
            default: // The system's own text never shows (lot 10, 20/11).
            return SummaryError.model("L'IA d'Apple n'a pas répondu.")
            }
        }
        if let error = error as? LanguageModelSession.Error, error == .concurrentRequests { return SummaryError.unavailable(busy) }
        if error is SystemLanguageModel.Error { return SummaryError.unavailable("L'IA d'Apple n'est pas disponible pour l'instant.") }
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize: return SummaryError.tooLong
            case .guardrailViolation, .refusal: return SummaryError.refused
            case .rateLimited, .concurrentRequests: return SummaryError.unavailable(busy)
            case .unsupportedLanguageOrLocale: return SummaryError.model("L'IA d'Apple ne prend pas cette langue.")
            case .assetsUnavailable: return SummaryError.unavailable("L'IA d'Apple n'est pas disponible pour l'instant.")
            default: // The system's own text never shows (lot 10, 20/11).
            return SummaryError.model("L'IA d'Apple n'a pas répondu.")
            }
        }
        return error
    }
}

@Generable struct ActionNote {
    @Guide(description: "L'action à faire, courte, à l'infinitif") var texte: String
    @Guide(description: "Qui la fait : « Moi » pour l'utilisateur, sinon le prénom dit dans la transcription ; vide si on ne sait pas") var porteur: String
    @Guide(description: "L'échéance seulement si une date ou un délai est dit (« vendredi », « dans deux semaines ») ; sinon vide") var echeance: String
}

@Generable struct PartNotes {
    @Guide(description: "Les points importants de cet extrait, en phrases courtes", .maximumCount(6)) var points: [String]
    @Guide(description: "Les décisions prises dans cet extrait : ce qui a été arrêté, pas ce qui a été simplement évoqué", .maximumCount(5)) var decisions: [String]
    @Guide(description: "Ce qu'une personne s'engage à faire après la réunion ; jamais un geste fait pendant la réunion (partager l'écran, présenter)", .maximumCount(5)) var actions: [ActionNote]

    /// As the next request reads them.
    func text(part: Int) -> String {
        SummaryNotes.text(part: part, points: points, decisions: decisions, actions: actions.map { action in
            "\(action.texte) (porteur : \(action.porteur.isEmpty ? "?" : action.porteur)\(action.echeance.isEmpty ? "" : ", échéance : \(action.echeance)"))"
        })
    }
}

/// The resume comes first, as measured on 14/11; the key points follow it (15/11, their quality not measured).
@Generable struct Summary {
    @Guide(description: "Résumé de la réunion en un paragraphe de 4 à 6 phrases") var resume: String
    @Guide(description: "Les points clés de la réunion, une phrase chacun, sans répéter les décisions", .maximumCount(6)) var points: [String]
    @Guide(description: "Les décisions les plus importantes, sans doublon", .maximumCount(8)) var decisions: [String]
    @Guide(description: "Les actions à faire après la réunion, sans doublon, les plus importantes d'abord", .maximumCount(10)) var actions: [ActionNote]
}
