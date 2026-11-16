import Foundation

// The title an item shows (16/11). Moved here from the app's `InspirationBrowse` (16/11) so that the agents' tool
// `inspiration` (`polhub mcp`, which never links the app's modules) shows the same title as the cards. Pure.

extension InspirationItemRow {
    /// A site's name without its page's words (« Adam Exemple - Home » → « Adam Exemple », « Home - ADA » → « ADA »),
    /// a post's without the emoji it starts with (« 💥 Café… »). The stored title stays as collected (16/11: the
    /// vault's titles are the pages' own).
    public var displayTitle: String {
        let trimmed = String(title.drop { !($0.isLetter || $0.isNumber || "\"«“'(".contains($0)) })
            .trimmingCharacters(in: .whitespaces)
        let clean = kind == .website ? Self.siteName(trimmed) : trimmed
        return clean.isEmpty ? title : clean
    }

    static let pageWords: Set<String> = ["home", "homepage", "home page", "accueil", "page d'accueil", "index", "welcome", "bienvenue",
                                         "official site", "official website", "site officiel"]

    /// The first part of a page's title that is not « Home » or the like, between its separators.
    static func siteName(_ title: String) -> String {
        var parts = [title]
        for separator in [" - ", " | ", " — ", " – ", " · ", " :: "] {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        let named = parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let locale = Locale(identifier: "fr_FR")
        return named.first { !pageWords.contains($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)) }
            ?? named.first ?? title
    }
}
