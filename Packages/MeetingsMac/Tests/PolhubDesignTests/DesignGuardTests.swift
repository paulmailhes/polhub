import Foundation
import Testing

/// The guard of the design system v2 (plan of 19/11): in the interface's code, what must disappear can only decrease.
/// Each rule has its ceiling, the count left when its lot ended; a lot that removes some lowers it here. Read, never
/// changed: the code of `MeetingsUI`, `ProjectsUI` and the app.
@Suite struct DesignGuardTests {
    struct Rule {
        let name: String
        let pattern: String
        let ceiling: Int
    }

    static let rules = [
        // Polhub's accent is its own, ink: never the Mac's (lot 3).
        Rule(name: "l'accent du Mac", pattern: #"accentColor|controlAccentColor"#, ceiling: 0),
        Rule(name: "un rayon déprécié (Radius.small, Radius.hero)", pattern: #"Radius\.(small|hero)\b"#, ceiling: 0),
        Rule(name: "un rayon écrit à la main", pattern: #"cornerRadius:\s*[0-9]"#, ceiling: 0),
        Rule(name: "un bouton plein du système (.borderedProminent)", pattern: #"\.borderedProminent\b"#, ceiling: 0),
        Rule(name: "une couleur de sens du système", pattern: #"(foregroundStyle|fill|tint|background)\((Color)?\.(orange|red|green|blue|pink)\b"#,
             ceiling: 0),
        // The typography of the screens moves at their lots (5 to 9). Lot 5 (19/11): the Accueil has none left, 57 → 42.
        // Lot 6 (19/11): the mails' bands, the programmed line and two chevrons, 42 → 37; lot 7: Réglages has none left, → 36.
        // Lot 8: the name of a card of the Kanban and the seal of a decision take the type's sizes, → 34.
        Rule(name: "une taille de texte écrite à la main", pattern: #"\.system\(size:\s*[0-9]"#, ceiling: 34),
        // Lot 5 (19/11): the lines of the Accueil take the secondary role, small; one outline in the whole app.
        Rule(name: "le bouton bordé d'avant (.subtle)", pattern: #"\.buttonStyle\(\.subtle\)"#, ceiling: 0),
    ]

    static let folders = ["Packages/MeetingsMac/Sources/MeetingsUI", "Packages/MeetingsMac/Sources/ProjectsUI", "App/Polhub"]

    /// The repository, from this file: `Packages/MeetingsMac/Tests/PolhubDesignTests/`.
    static var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Each matching line, as `fichier:ligne`.
    static func matches(_ pattern: String) throws -> [String] {
        let expression = try NSRegularExpression(pattern: pattern)
        var found: [String] = []
        for folder in folders {
            let base = root.appending(path: folder)
            guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in walker where file.pathExtension == "swift" {
                let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
                for (index, line) in lines.enumerated() where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                    if expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                        found.append("\(file.path(percentEncoded: false).replacingOccurrences(of: root.path(percentEncoded: false), with: "")):\(index + 1)")
                    }
                }
            }
        }
        return found
    }

    @Test func theCodeIsFound() throws {
        #expect(FileManager.default.fileExists(atPath: Self.root.appending(path: "Packages/MeetingsMac/Sources/MeetingsUI").path(percentEncoded: false)))
    }

    @Test func whatMustGoCanOnlyDecrease() throws {
        for rule in Self.rules {
            let found = try Self.matches(rule.pattern)
            #expect(found.count <= rule.ceiling, "\(rule.name) : \(found.count), plafond \(rule.ceiling)\n\(found.prefix(20).joined(separator: "\n"))")
        }
    }
}
