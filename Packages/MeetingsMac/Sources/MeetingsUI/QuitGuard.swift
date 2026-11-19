import Foundation
import Pipeline

/// ⌘Q while something would be lost (audit of 19/11): a meeting being recorded, a mail about to leave (it waits a few
/// seconds in memory, and quitting calls it back). Quitting then asks first; the rest of the time it quits at once.
public enum QuitGuard {
    public struct Question: Equatable, Sendable {
        public let title: String
        public let detail: String
        /// The first button, the one Return presses: nothing is lost.
        public let stay: String
        public let quit: String
    }

    public static func question(status: RecorderStatus, sending: Bool) -> Question? {
        switch status {
        case .recording, .presumedEnded:
            return Question(title: "Polhub enregistre une réunion",
                            detail: "Si tu quittes maintenant, la suite de la réunion ne sera pas enregistrée.",
                            stay: "Continuer l'enregistrement", quit: "Quitter quand même")
        case .idle, .prompting, .paused:
            guard sending else { return nil }
            return Question(title: "Un mail part dans un instant",
                            detail: "Si tu quittes maintenant, il ne partira pas.", stay: "Attendre l'envoi", quit: "Quitter quand même")
        }
    }
}
