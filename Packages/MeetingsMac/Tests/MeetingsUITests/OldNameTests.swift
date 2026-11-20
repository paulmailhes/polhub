import Foundation
import GoogleKit
import HubCloud
import Persistence
import Testing
import Updates

/// 20/11 : Polhub devient hub-board, dit « hub ». Plus rien de ce qu'on lit ne dit « Polhub » ; seuls restent les
/// identifiants cachés, que changer ferait perdre la copie iCloud, la base, les autorisations ou les connexions.
@Suite struct OldNameTests {
    /// The code that keeps the old name on purpose, and why: a hidden identifier, or the name before 20/11 recognized.
    static let allowed = [
        "zoneName: \"Polhub\"",                                   // la zone CloudKit de la copie iCloud
        "databaseFileName = \"Polhub.sqlite\"",                   // le fichier de la base
        "dev ? \"Polhub-dev\" : \"Polhub\"",                      // les dossiers d'avant, déplacés puis liés
        "archiveNames = [\"hub-board.zip\", \"Polhub.zip\"]",     // les versions publiées sous l'ancien nom
        "appNames = [\"hub.app\", \"Polhub.app\"]",
        "(?:hub-board|Polhub)-",                                  // les copies de la base d'avant
        "(\"Polhub\", \"hub\")",                                    // la Dictée corrige l'ancien nom entendu
    ]

    static var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../../..").standardizedFileURL
    }

    /// The code of a line, without its comment: a `//` at the start, or after a space (a URL's `://` stays).
    static func code(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") { return "" }
        guard let range = line.range(of: " //") else { return line }
        return String(line[..<range.lowerBound])
    }

    @Test func noOldNameIsShown() throws {
        var found: [String] = []
        let manager = FileManager.default
        for folder in ["Packages/Kernel/Sources", "Packages/MeetingsMac/Sources", "Packages/Link/Sources", "App"] {
            let base = Self.root.appending(path: folder, directoryHint: .isDirectory)
            guard let walk = manager.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in walk where ["swift", "plist", "strings"].contains(file.pathExtension) {
                let text = try String(contentsOf: file, encoding: .utf8)
                for (number, line) in text.components(separatedBy: "\n").enumerated() {
                    let code = file.pathExtension == "swift" ? Self.code(line) : line
                    guard code.contains("Polhub"), !Self.allowed.contains(where: line.contains) else { continue }
                    found.append("\(file.lastPathComponent):\(number + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(found.isEmpty, "\(found.count) lignes :\n\(found.prefix(40).joined(separator: "\n"))")
    }

    @Test func hiddenIdentifiersStay() {
        #expect(CloudRecords.zoneID.zoneName == "Polhub")
        #expect(CloudRecords.container == "iCloud.fr.paulmailhes.polhub")
        #expect(Verifier.bundleID == "fr.paulmailhes.polhub")
        #expect(KeychainVault.service == "fr.paulmailhes.polhub.google")
        #expect(Installer.agent == "fr.paulmailhes.polhub.relance")
        #expect(AppPaths.databaseFileName == "Polhub.sqlite")
    }
}
