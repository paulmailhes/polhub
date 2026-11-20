import Foundation
import Security

/// Why a downloaded app is refused.
public enum VerificationError: Error, Equatable, CustomStringConvertible {
    case invalidSignature
    case wrongTeam
    case wrongIdentifier
    case wrongVersion
    case unsafeArchive(String)

    public var description: String {
        switch self {
        case .invalidSignature: "la signature de l'app téléchargée est invalide"
        case .wrongTeam: "l'app téléchargée n'est pas signée par l'auteur de hub"
        case .wrongIdentifier: "l'app téléchargée n'est pas hub"
        case .wrongVersion: "l'app téléchargée n'a pas la version annoncée"
        case .unsafeArchive(let reason): "l'archive téléchargée est refusée (\(reason))"
        }
    }
}

/// An update is installed only if Apple's own check says its app is signed with the author's Developer ID
/// (team CQ43U6XX4Z), notarized, is hub, and has the announced version: a hacked GitHub account cannot get
/// anything else installed (review, critical 1: no reading of `codesign`'s text).
public enum Verifier {
    public static let teamID = "CQ43U6XX4Z"
    public static let bundleID = "fr.paulmailhes.polhub"

    /// The designated requirement of a Developer ID app of the team, notarized by Apple (audit of 19/11: a version
    /// published without notarization never installs itself).
    public static func requirement(identifier: String = bundleID) -> String {
        #"anchor apple generic and identifier ""# + identifier
            + #"" and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13]"#
            + #" and certificate leaf[subject.OU] = ""# + teamID + #"" and notarized"#
    }

    /// `nil` when the bundle is a real folder whose signature, nested code included, meets the requirement.
    public static func signatureError(app: URL, identifier: String = bundleID) -> VerificationError? {
        var status = stat()
        guard lstat(app.path(percentEncoded: false), &status) == 0, (status.st_mode & S_IFMT) == S_IFDIR else { return .invalidSignature }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return .invalidSignature }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(Self.requirement(identifier: identifier) as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return .invalidSignature }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        switch SecStaticCodeCheckValidityWithErrors(code, flags, requirement, nil) {
        case errSecSuccess: return nil
        case errSecCSReqFailed: return .wrongTeam
        default: return .invalidSignature
        }
    }

    /// The Info.plist as sealed by the signature.
    public static func signedInfo(app: URL) -> [String: Any] {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return [:] }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any] else { return [:] }
        return dictionary[kSecCodeInfoPList as String] as? [String: Any] ?? [:]
    }

    /// Identifier and version of the signed Info.plist.
    public static func check(info: [String: Any], expected: SemanticVersion) -> VerificationError? {
        guard info["CFBundleIdentifier"] as? String == bundleID else { return .wrongIdentifier }
        guard (info["CFBundleShortVersionString"] as? String).flatMap(SemanticVersion.init) == expected else { return .wrongVersion }
        return nil
    }
}

/// The archive is looked at before it is opened (review, important 1): only `hub.app/…` (or `Polhub.app/…`, before 20/11) paths, no
/// symbolic link (the app has none), no way out of the folder, a sane size.
public enum ArchiveCheck {
    public static let maxUncompressed: Int64 = 1_000_000_000

    /// `listing`: the output of `zipinfo <archive>`.
    public static func problem(listing: String) -> String? {
        var app: String?
        for line in listing.components(separatedBy: "\n") {
            if let total = line.firstMatch(of: #/(\d+) bytes uncompressed/#), let bytes = Int64(total.output.1), bytes > maxUncompressed {
                return "\(bytes) octets une fois ouverte"
            }
            guard let first = line.first, "-dl".contains(first) else { continue }
            let fields = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
            guard fields.count == 9 else { continue }
            let name = String(fields[8])
            if first == "l" { return "lien symbolique : \(name)" }
            if name.hasPrefix("/") || name.split(separator: "/").contains("..") { return "chemin hors du dossier : \(name)" }
            // One app only, under its name of today or the one before 20/11.
            guard let folder = Installer.appNames.first(where: { name.hasPrefix($0 + "/") }) else { return "élément inattendu : \(name)" }
            if let app, app != folder { return "deux apps : \(app) et \(folder)" }
            app = folder
        }
        return nil
    }
}

/// The script that swaps the two versions once the app has quit. Started in a session of its own, so that
/// launchd does not take it down with the app.
public enum SwapScript {
    public static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// A text `pgrep -f` reads as itself: every sign of an extended regular expression escaped.
    static func pattern(_ text: String) -> String {
        text.reduce(into: "") { result, character in
            if #"\.[]()*+?{}|^$"#.contains(character) { result.append("\\") }
            result.append(character)
        }
    }

    /// A path without the trailing slash Foundation gives existing folders.
    static func path(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }

    /// - Parameters:
    ///   - signal: the file the new version writes its version into once it has really started.
    ///   - start: the shell command that launches the installed app.
    ///   - failedKey: the preference written when the new version is rolled back (no loop of attempts).
    /// Registers an app with LaunchServices again: its new icon shows at once in the Dock and the Finder (14/11).
    public static let launchServicesRegister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f"

    /// The check of an app where it lies, the verifier's own (audit of 19/11): the script runs it on the copy it made,
    /// and before it starts any app; `codesign` answers by its exit code, never by its text.
    public static var signatureCheck: String {
        "/usr/bin/codesign --verify --strict --deep -R " + quote("=" + Verifier.requirement())
    }

    /// - register: the command that registers the installed app again (`launchServicesRegister`); the tests pass a
    ///   harmless one, so that no test app is ever registered.
    /// - verify: the command that says, by its exit code, whether the app whose path follows is the author's
    ///   (`signatureCheck`); the tests pass their own.
    /// - target: where the new version goes; `installed` itself, unless the app changes its name (20/11: hub.app
    ///   becomes hub.app). Then the old app is kept aside and taken away, and comes back if the new one does not start.
    /// - start: the command that launches the new version, at `target`; `startOld`, the one that launches the installed
    ///   app again (`start` when the name does not change).
    public static func make(
        newApp: URL, installed: URL, target: URL? = nil, keepOld: URL, version: String, signal: URL, log: URL, pid: Int32,
        processName: String, newProcessName: String? = nil, start: String, startOld: String? = nil, startTimeout: Int,
        failedKey: String?, register: String? = nil, verify: String, waitSteps: Int = 150
    ) -> String {
        let target = target ?? installed
        let renamed = path(target) != path(installed)
        let registration = register.map { "touch \(quote(path(target))); \($0) \(quote(path(target))) 2>/dev/null || true" } ?? "true"
        let new = quote(path(newApp)), app = quote(path(installed)), dest = quote(path(target))
        let parent = quote(path(installed.deletingLastPathComponent()))
        let keep = quote(path(keepOld)), zip = quote(path(keepOld) + "/hub-board-precedente.zip"), signalFile = quote(path(signal))
        let failed = failedKey.map { "defaults write \(Verifier.bundleID) \($0) \(quote(version))" } ?? "true"
        // Only a copy of the installed app counts, by its path (20/11: the iPhone app in the simulator is called
        // hub too, and the name alone stopped an update).
        let copy = quote(pattern(path(installed) + "/Contents/MacOS/" + processName))
        let newCopy = quote(pattern(path(target) + "/Contents/MacOS/" + (newProcessName ?? processName)))
        // A renamed version left half-way is taken away: the old app is the one that stays.
        let dropTarget = renamed ? "rm -rf \(dest)" : "true"
        return """
        #!/bin/bash
        # hub : échange de versions, écrit par l'app et lancé hors d'elle.
        set -u
        mkdir -p \(quote(path(log.deletingLastPathComponent()))) 2>/dev/null
        exec >>\(quote(path(log))) 2>&1 || exec >/dev/null 2>&1
        say() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }
        verified() { \(verify) "$1" >/dev/null 2>&1; }
        # Nothing starts that the author did not sign: a copy changed after its check, or an old version replaced.
        start_new() { if verified \(dest); then \(start); else say "l'app en place n'est pas signée par l'auteur de hub : elle n'est pas lancée"; fi; }
        start_old() { if verified \(app); then \(startOld ?? start); else say "l'app en place n'est pas signée par l'auteur de hub : elle n'est pas lancée"; fi; }
        restore() { rm -rf \(dest); rm -rf \(app); ditto -x -k \(zip) \(parent); }
        DONE=0
        # Whatever happens, Paul is never left without an app.
        finish() {
          if [ "$DONE" = 0 ]; then
            if [ -d \(app) ]; then \(dropTarget); else restore; fi
            start_old
          fi
        }
        trap finish EXIT
        say "début : passage à la version \(version)"
        for i in $(seq 1 \(waitSteps)); do kill -0 \(pid) 2>/dev/null || break; sleep 0.2; done
        if kill -0 \(pid) 2>/dev/null; then say "l'app ne s'est pas arrêtée : rien n'est changé"; DONE=1; exit 1; fi
        for i in $(seq 1 \(waitSteps)); do pgrep -f \(copy) >/dev/null || break; sleep 0.2; done
        # Nothing is changed, but the app that quit for the update starts again.
        if pgrep -f \(copy) >/dev/null; then say "une autre copie tourne encore : rien n'est changé"; exit 1; fi
        mkdir -p \(keep)
        rm -f \(zip)
        if ! ditto -c -k --keepParent \(app) \(zip); then say "l'ancienne version ne se met pas de côté : rien n'est changé"; DONE=1; start_old; exit 1; fi
        rm -rf \(dest)
        if ! ditto \(new) \(dest); then
          say "copie de la nouvelle version ratée : retour à l'ancienne version"
          restore; \(failed); DONE=1; start_old; exit 1
        fi
        if ! verified \(dest); then
          say "la nouvelle version copiée n'est pas signée par l'auteur de hub : retour à l'ancienne version"
          restore; \(failed); DONE=1; start_old; exit 1
        fi
        \(renamed ? "rm -rf \(app)" : "true")
        xattr -dr com.apple.quarantine \(dest) 2>/dev/null
        \(registration)
        rm -f \(signalFile)
        start_new
        for i in $(seq 1 $(( \(startTimeout) * 5 ))); do
          if [ "$(cat \(signalFile) 2>/dev/null)" = \(quote(version)) ]; then
            say "nouvelle version \(version) installée et lancée"
            DONE=1
            rm -rf \(quote(path(newApp.deletingLastPathComponent())))
            exit 0
          fi
          sleep 0.2
        done
        say "la nouvelle version ne démarre pas : retour à l'ancienne version"
        pkill -f \(newCopy) 2>/dev/null; sleep 1
        restore; \(failed); DONE=1; start_old; exit 1

        """
    }
}
