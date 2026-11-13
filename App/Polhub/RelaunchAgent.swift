import Foundation
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
        case .requiresApproval: "à autoriser dans Réglages → Général → Ouverture"
        case .notFound: "introuvable dans l'application"
        @unknown default: "inconnue"
        }
    }

    /// Returns an error message, or nil when the agent is enabled.
    static func enable() -> String? {
        do {
            try service.register()
        } catch {
            return "Activation refusée : \(error.localizedDescription)"
        }
        return isEnabled ? nil : "Relance \(statusText)."
    }

    static func disable() -> String? {
        do {
            try service.unregister()
            return nil
        } catch {
            return "Désactivation refusée : \(error.localizedDescription)"
        }
    }
}
