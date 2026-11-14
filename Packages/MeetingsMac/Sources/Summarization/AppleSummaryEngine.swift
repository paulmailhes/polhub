import Foundation
import FoundationModels

/// Apple's model, built into macOS: it runs in a system service, never in the app's memory, and nothing
/// leaves the Mac (measured on 14/11: about a minute and a half for an hour of meeting).
public struct AppleSummaryEngine: SummaryEngine {
    public init() {}

    public var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.appleIntelligenceNotEnabled): "Active Apple Intelligence dans Réglages Système pour avoir les comptes rendus."
        case .unavailable(.modelNotReady): "Le modèle d'Apple se prépare (macOS le télécharge) : les comptes rendus suivront."
        case .unavailable(.deviceNotEligible): "Ce Mac ne peut pas faire tourner le modèle d'Apple."
        case .unavailable: "Le modèle d'Apple n'est pas disponible pour l'instant."
        }
    }

    static let notesInstructions = """
        Tu prends des notes de réunion en français. « Moi » est l'utilisateur de l'application, qui a enregistré la réunion ; \
        « Les autres » sont ses interlocuteurs. N'invente rien : seulement ce qui est dit dans l'extrait.
        """
    static let summaryInstructions = """
        Tu rédiges le compte rendu d'une réunion en français, à partir des notes prises partie par partie. « Moi » est \
        l'utilisateur de l'application. Fusionne les doublons, garde l'essentiel, n'invente rien. Une décision est ce qui a été \
        arrêté ; une action est ce que quelqu'un fera après la réunion.
        """

    public func notes(for chunk: String, part: Int, of count: Int) async throws -> String {
        let session = LanguageModelSession(instructions: Self.notesInstructions)
        let notes = try await respond {
            try await session.respond(to: "Extrait \(part) sur \(count) de la transcription :\n\n" + chunk, generating: PartNotes.self).content
        }
        var text = "Partie \(part)\nPoints :\n" + notes.points.map { "- \($0)" }.joined(separator: "\n")
        text += "\nDécisions :\n" + notes.decisions.map { "- \($0)" }.joined(separator: "\n")
        text += "\nActions :\n" + notes.actions.map { action in
            "- \(action.texte) (porteur : \(action.porteur.isEmpty ? "?" : action.porteur)\(action.echeance.isEmpty ? "" : ", échéance : \(action.echeance)"))"
        }.joined(separator: "\n")
        return text
    }

    public func summary(of notes: [String], title: String) async throws -> MeetingSummary {
        let session = LanguageModelSession(instructions: Self.summaryInstructions)
        let answer = try await respond {
            try await session.respond(to: "Titre de la réunion : \(title)\n\nNotes :\n\n" + notes.joined(separator: "\n\n"), generating: Summary.self).content
        }
        return MeetingSummary(overview: answer.resume, decisions: answer.decisions,
                              actions: answer.actions.map { SummaryAction(text: $0.texte, owner: $0.porteur, due: $0.echeance) })
    }

    /// The model's refusals and limits, said in French.
    private func respond<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch _ where Task.isCancelled {
            // Stopped by a meeting: never a failure (review of 14/11, Important 4).
            throw CancellationError()
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize: throw SummaryError.model("La transcription dépasse la fenêtre du modèle.")
            case .guardrailViolation, .refusal: throw SummaryError.model("Le modèle d'Apple a refusé ce passage.")
            case .unsupportedLanguageOrLocale: throw SummaryError.model("Le modèle d'Apple ne prend pas cette langue.")
            case .assetsUnavailable: throw SummaryError.unavailable("Le modèle d'Apple n'est pas disponible pour l'instant.")
            default: throw SummaryError.model("Le modèle d'Apple n'a pas répondu : \(error.localizedDescription)")
            }
        }
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
}

@Generable struct Summary {
    @Guide(description: "Résumé de la réunion en un paragraphe de 4 à 6 phrases") var resume: String
    @Guide(description: "Les décisions les plus importantes, sans doublon", .maximumCount(8)) var decisions: [String]
    @Guide(description: "Les actions à faire après la réunion, sans doublon, les plus importantes d'abord", .maximumCount(10)) var actions: [ActionNote]
}
