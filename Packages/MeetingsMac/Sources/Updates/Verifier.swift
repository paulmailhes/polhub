import Foundation

/// Why a downloaded app is refused.
public enum VerificationError: Error, Equatable, CustomStringConvertible {
    case invalidSignature
    case wrongTeam
    case wrongIdentifier
    case wrongVersion

    public var description: String {
        switch self {
        case .invalidSignature: "la signature de l'app téléchargée est invalide"
        case .wrongTeam: "l'app téléchargée n'est pas signée par l'auteur de Polhub"
        case .wrongIdentifier: "l'app téléchargée n'est pas Polhub"
        case .wrongVersion: "l'app téléchargée n'a pas la version annoncée"
        }
    }
}

/// An update is installed only if its app is signed by the author's team, is Polhub, and has the
/// announced version: a hacked GitHub account cannot get anything else installed.
public enum Verifier {
    public static let teamID = "CQ43U6XX4Z"
    public static let bundleID = "fr.paulmailhes.polhub"

    /// `signature`: the output of `codesign -dv --verbose=2`; `info`: the app's Info.plist.
    public static func check(signature: String, info: [String: Any], expected: SemanticVersion) -> VerificationError? {
        let lines = Set(signature.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        guard lines.contains("TeamIdentifier=\(teamID)") else { return .wrongTeam }
        guard lines.contains("Identifier=\(bundleID)"), info["CFBundleIdentifier"] as? String == bundleID else { return .wrongIdentifier }
        guard (info["CFBundleShortVersionString"] as? String).flatMap(SemanticVersion.init) == expected else { return .wrongVersion }
        return nil
    }
}

/// The script that swaps the two versions once the app has quit. Started detached from the app (its own
/// session), so that launchd does not take it down with the app.
public enum SwapScript {
    public static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// A path without the trailing slash Foundation gives existing folders.
    static func path(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }

    public static func make(newApp: URL, installed: URL, keepOld: URL, agent: String, log: URL, pid: Int32, uid: uid_t) -> String {
        let new = quote(path(newApp)), app = quote(path(installed))
        let keep = quote(path(keepOld)), old = quote(path(keepOld) + "/Polhub.app")
        return """
        #!/bin/bash
        # Polhub : échange de versions, écrit par l'app et lancé hors d'elle.
        mkdir -p \(quote(path(log.deletingLastPathComponent())))
        exec >>\(quote(path(log))) 2>&1
        say() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }
        start() { launchctl kickstart gui/\(uid)/\(agent) 2>/dev/null || open \(app); }
        say "début : attente de la fin de l'app (\(pid))"
        for i in $(seq 1 150); do kill -0 \(pid) 2>/dev/null || break; sleep 0.2; done
        if kill -0 \(pid) 2>/dev/null; then say "l'app ne s'est pas arrêtée : rien n'est changé"; exit 1; fi
        mkdir -p \(keep)
        rm -rf \(old)
        if ! mv \(app) \(old); then say "l'ancienne version ne se met pas de côté : rien n'est changé"; start; exit 1; fi
        if ! ditto \(new) \(app); then
          say "copie de la nouvelle version ratée : retour à l'ancienne version"
          rm -rf \(app); mv \(old) \(app); start; exit 1
        fi
        xattr -dr com.apple.quarantine \(app) 2>/dev/null
        start
        sleep 20
        if ! pgrep -x Polhub >/dev/null; then
          say "la nouvelle version ne démarre pas : retour à l'ancienne version"
          rm -rf \(app); mv \(old) \(app); start; exit 1
        fi
        say "nouvelle version installée et lancée"

        """
    }
}
