import Foundation
import PolhubDesign
import ProbeKit
import ServiceManagement

/// The launchd agent that restarts the app after a crash.
///
/// launchd restarts only the copy it started itself. Enabling the agent therefore hands over: launchd
/// starts its own copy at once (`RunAtLoad`), and the copy the person had opened quits.
@MainActor
enum RelaunchAgent {
    private static var service: SMAppService {
        .agent(plistName: LaunchContext.agentPlistName)
    }

    static var isEnabled: Bool {
        service.status == .enabled
    }

    static var statusText: String {
        switch service.status {
        case .enabled: "activée"
        case .notRegistered: "désactivée"
        // A path of System Settings, its levels apart by « › » (lot 10, 20/11).
        case .requiresApproval: "à autoriser dans Réglages Système › Général › Ouverture"
        case .notFound: "introuvable dans l'application"
        @unknown default: "inconnue"
        }
    }

    /// Returns an error message, or nil when the agent is enabled. The message says what did not work, in French, then
    /// what to do; the system's own text goes to the log (lot 10, 20/11).
    static func enable() -> String? {
        do {
            try service.register()
        } catch {
            let problem = Words.problem("La relance n'a pas pu être activée", error)
            if let journal = problem.journal { NSLog("%@", journal) }
            return problem.sentence
        }
        return isEnabled ? nil : "Relance \(statusText)."
    }

    static func disable() -> String? {
        do {
            try service.unregister()
            return nil
        } catch {
            let problem = Words.problem("La relance n'a pas pu être désactivée", error)
            if let journal = problem.journal { NSLog("%@", journal) }
            return problem.sentence
        }
    }
}
