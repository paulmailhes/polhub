import Foundation
import Inspiration
import Persistence
import PolhubDesign

// What the pages of « Inspiration » show, without a screen (16/11): the words of each page, the search, the
// filters (one value per family, as the vault's tag bar), the chips each family offers, the meta line of a card,
// the links of an item. Pure: the library and the tests share it.

extension InspirationKind {
    /// The page's name in the sidebar (Paul, 16/11: the vault's folders).
    public var title: String {
        switch self {
        case .website: "Websites"
        case .branding: "Branding"
        case .mockup: "Mock-ups"
        }
    }

    public var appIcon: AppIcon {
        switch self {
        case .website: .websites
        case .branding: .branding
        case .mockup: .mockups
        }
    }

    /// « 212 sites », « 488 branding », « 292 mock-ups ».
    func count(_ count: Int) -> String {
        switch self {
        case .website: "\(count) site\(count > 1 ? "s" : "")"
        case .branding: "\(count) branding"
        case .mockup: "\(count) mock-up\(count > 1 ? "s" : "")"
        }
    }

    var searchPrompt: String {
        switch self {
        case .website: "Chercher un site, un style, une techno…"
        case .branding: "Chercher un projet, un studio, un style…"
        case .mockup: "Chercher un mock-up, un type…"
        }
    }

    /// The « + » of the toolbar.
    var addTitle: String {
        switch self {
        case .website: "Ajouter un site"
        case .branding: "Ajouter une page LinkedIn"
        case .mockup: "Ajouter un mock-up"
        }
    }

    /// The page without an item.
    var emptyTitle: String {
        switch self {
        case .website: "Aucun site"
        case .branding: "Aucun branding"
        case .mockup: "Aucun mock-up"
        }
    }

    var emptyText: String {
        switch self {
        case .website: "Chaque site du jour d'Awwwards arrive ici, avec ceux que tu ajoutes."
        case .branding: "Les nouveaux posts de tes pages LinkedIn arrivent ici."
        case .mockup: "Les mock-ups que tu ajoutes arrivent ici, avec leur aperçu et le lien vers leur dossier."
        }
    }
}

enum InspirationBrowse {
    /// The LinkedIn pages a branding came from: filtered as a family of its own, first on Branding.
    static let sourceFamily = "source"
    static let locale = Locale(identifier: "fr_FR")

    /// A filter of the search field: a value of a family (« Minimal », in Style), or a LinkedIn page.
    struct InspirationToken: Identifiable, Hashable, Sendable {
        let family: String
        let familyTitle: String
        let value: String
        /// The items it would show (for the suggestions).
        let count: Int
        let color: String?
        var id: String { family + "|" + InspirationBrowse.fold(value) }
        var label: String { InspirationBrowse.label(value) }

        static func == (left: Self, right: Self) -> Bool { left.id == right.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    /// One value of a family's row of chips.
    struct ChipValue: Hashable, Identifiable, Sendable {
        let value: String
        /// The items it would show, given the search and the other families' choices.
        let count: Int
        /// A LinkedIn page's color.
        let color: String?
        var id: String { value }
        /// « Minimaliste » for `minimaliste`: the vault's tags are lowercase.
        var label: String { InspirationBrowse.label(value) }
    }

    /// The values of one family, the most used first: what the search suggests and detects.
    struct ChipRow: Hashable, Identifiable, Sendable {
        let family: String
        let title: String
        let values: [ChipValue]
        /// The value chosen, `nil` for « Tout ».
        let selected: String?
        var id: String { family }
    }

    // MARK: - Search

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
    }

    static func words(_ query: String) -> [String] {
        fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Everything a search looks into: title, text, studio, client, fonts, pages, the site's host, categories.
    static func haystack(_ item: InspirationItemRow) -> String {
        let categories = item.categories.values.flatMap { $0 }
        let parts = [item.title, item.text, item.studio ?? "", item.client ?? "", host(item.url) ?? ""] + item.fonts + item.sources + categories
            + (item.extra.hashtags ?? [])
        return fold(parts.joined(separator: " "))
    }

    /// Every word of the search is somewhere in the item.
    static func matches(haystack: String, words: [String]) -> Bool {
        words.allSatisfy { haystack.contains($0) }
    }

    // MARK: - Filters

    /// The values an item has in a family: its LinkedIn pages for `source`, else its categories.
    static func values(of item: InspirationItemRow, family: String) -> [String] {
        family == sourceFamily ? item.sources : item.categories[family] ?? []
    }

    /// One value per family; an item passes when it has every value chosen.
    static func passes(_ item: InspirationItemRow, filters: [String: String]) -> Bool {
        filters.allSatisfy { family, value in
            values(of: item, family: family).contains { fold($0) == fold(value) }
        }
    }

    /// The items the page shows, in the base's order (newest first).
    static func filter(_ items: [InspirationItemRow], query: String, filters: [String: String],
                       haystacks: [UUID: String] = [:]) -> [InspirationItemRow] {
        let words = words(query)
        let filters = filters.filter { !$0.value.isEmpty }
        guard !words.isEmpty || !filters.isEmpty else { return items }
        return items.filter { item in
            passes(item, filters: filters) && (words.isEmpty || matches(haystack: haystacks[item.id] ?? haystack(item), words: words))
        }
    }

    /// The families a page filters by, in order: the LinkedIn pages first on Branding, then the vocabulary's
    /// families, then « autres » (the tags no vocabulary knows) when some item has one.
    static func families(_ kind: InspirationKind, vocabulary: InspirationVocabulary, items: [InspirationItemRow]) -> [(name: String, title: String)] {
        var result: [(name: String, title: String)] = []
        if kind == .branding { result.append((sourceFamily, "Source")) }
        result += vocabulary.families.map { ($0.name, $0.title) }
        let known = Set(result.map(\.name))
        let other = InspirationVocabulary.otherFamily
        if !known.contains(other), items.contains(where: { !($0.categories[other] ?? []).isEmpty }) {
            result.append((other, label(other)))
        }
        return result
    }

    /// One row of chips per family: the values the items have, given the search and the other families' choices
    /// (a chip never leads to an empty page), the most used first; the value chosen always stays. A family with
    /// nothing to offer has no row.
    static func chipRows(_ items: [InspirationItemRow], kind: InspirationKind, vocabulary: InspirationVocabulary,
                         sources: [InspirationSourceRow], query: String, filters: [String: String],
                         haystacks: [UUID: String] = [:]) -> [ChipRow] {
        let words = words(query)
        let searched = words.isEmpty ? items : items.filter { matches(haystack: haystacks[$0.id] ?? haystack($0), words: words) }
        return families(kind, vocabulary: vocabulary, items: items).compactMap { family in
            var others = filters
            others[family.name] = nil
            let candidates = others.isEmpty ? searched : searched.filter { passes($0, filters: others) }
            var counts: [String: Int] = [:]
            var spelling: [String: String] = [:]
            for item in candidates {
                for value in Set(values(of: item, family: family.name).map(fold)) {
                    counts[value, default: 0] += 1
                }
                for value in values(of: item, family: family.name) where spelling[fold(value)] == nil {
                    spelling[fold(value)] = value
                }
            }
            let selected = filters[family.name].flatMap { $0.isEmpty ? nil : $0 }
            if let selected, counts[fold(selected)] == nil {
                counts[fold(selected)] = 0
                spelling[fold(selected)] = selected
            }
            guard !counts.isEmpty else { return nil }
            let order = Dictionary(vocabulary.family(family.name)?.tags.enumerated().map { (fold($0.element.value), $0.offset) } ?? [],
                                   uniquingKeysWith: { first, _ in first })
            let values = counts.keys.sorted { a, b in
                if counts[a] != counts[b] { return counts[a]! > counts[b]! }
                let left = order[a] ?? Int.max, right = order[b] ?? Int.max
                if left != right { return left < right }
                return a < b
            }.map { key in
                let value = spelling[key] ?? key
                return ChipValue(value: value, count: counts[key] ?? 0,
                                 color: family.name == sourceFamily ? color(ofSource: value, in: sources) : nil)
            }
            return ChipRow(family: family.name, title: family.title, values: values,
                           selected: selected.map { spelling[fold($0)] ?? $0 })
        }
    }

    // MARK: - The search's filters

    /// The values of the page's rows as filters of the search field, with their counts; the ones chosen out.
    static func tokens(_ rows: [ChipRow]) -> [InspirationToken] {
        rows.flatMap { row in
            row.values.filter { value in row.selected.map { fold($0) != fold(value.value) } ?? true }.map { value in
                InspirationToken(family: row.family, familyTitle: row.title, value: value.value, count: value.count, color: value.color)
            }
        }
    }

    /// What is being typed suggests the values one of whose words starts with its last word, the most used first;
    /// nothing typed, the most used of all (Paul, 16/11: « une barre de recherche avec détection automatique »).
    static func suggestions(_ rows: [ChipRow], text: String, limit: Int = 8) -> [InspirationToken] {
        let all = tokens(rows).sorted { $0.count != $1.count ? $0.count > $1.count : $0.id < $1.id }
        guard !text.hasSuffix(" "), let last = words(text).last else {
            return text.trimmingCharacters(in: .whitespaces).isEmpty ? Array(all.prefix(limit)) : []
        }
        return Array(all.filter { token in words(spaced(token.value)).contains { $0.hasPrefix(last) } }.prefix(limit))
    }

    /// A value typed in full, then a space, becomes a filter (« minimal », « bas de casse », « Beyond Branding »):
    /// the token, and the text without it. A value of two families goes to the one where it is most used.
    static func detect(_ text: String, in rows: [ChipRow]) -> (token: InspirationToken, rest: String)? {
        guard text.last?.isWhitespace == true else { return nil }
        let typed = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let candidates = rows.flatMap { row in
            row.values.map { InspirationToken(family: row.family, familyTitle: row.title, value: $0.value, count: $0.count, color: $0.color) }
        }
        for size in stride(from: min(4, typed.count), through: 1, by: -1) {
            let phrase = words(typed.suffix(size).joined(separator: " ")).joined(separator: " ")
            let found = candidates.filter { words(spaced($0.value)).joined(separator: " ") == phrase }
            if let best = found.max(by: { $0.count < $1.count }) {
                let rest = typed.dropLast(size).joined(separator: " ")
                return (best, rest.isEmpty ? "" : rest + " ")
            }
        }
        return nil
    }

    /// `bas-de-casse` read as « bas de casse ».
    static func spaced(_ value: String) -> String {
        value.replacingOccurrences(of: "-", with: " ")
    }

    // MARK: - Titles

    /// The title a card shows: a site's name without its page's words, a post's without the emoji it starts with.
    /// The logic lives in Persistence since 16/11 (`InspirationItemRow.displayTitle`), where the agents' tool
    /// `inspiration` reads it too.
    static func displayTitle(_ item: InspirationItemRow) -> String {
        item.displayTitle
    }

    /// « Minimaliste » for `minimaliste`, « Business card » for `business card`, « Bas de casse » for
    /// `bas-de-casse` (one hyphen belongs to the word: « E-commerce »); the mock-ups' types, written without
    /// accents in the vault, get theirs back (« Signalétique », « Boîte », « iPhone »).
    static func label(_ value: String) -> String {
        if let known = spelled[value.lowercased()] { return known }
        let words = value.filter { $0 == "-" }.count >= 2 ? value.replacingOccurrences(of: "-", with: " ") : value
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    static let spelled = [
        "signaletique": "Signalétique", "boite": "Boîte", "boite aux lettres": "Boîte aux lettres", "fenetre": "Fenêtre",
        "ecran": "Écran", "vehicule": "Véhicule", "iphone": "iPhone", "macbook": "MacBook",
        "3d": "3D", "gsap": "GSAP", "sombre-clair": "Sombre / clair",
    ]

    /// The window's subtitle: « 212 sites », « 4 sites sur 212 » while filtered, nothing for an empty page.
    static func subtitle(_ kind: InspirationKind, shown: Int, total: Int) -> String {
        guard total > 0 else { return "" }
        return shown == total ? kind.count(total) : "\(kind.count(shown)) sur \(total)"
    }

    // MARK: - A card's meta line

    /// « 20 oct. » this year, « 20 oct. 2025 » before.
    static func dateText(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated)
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) { style = style.year() }
        return date.formatted(style)
    }

    /// `galerie-lumiere.example.com` for `https://www.galerie-lumiere.example.com/fr/`.
    static func host(_ url: String?) -> String? {
        guard let url, let host = URL(string: url)?.host(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Websites: the date and the site's host; Branding: the date and the studio (or the page); Mock-ups: their
    /// types (the date without one).
    static func meta(_ item: InspirationItemRow, now: Date = Date(), calendar: Calendar = .current) -> String {
        let date = dateText(item.date, now: now, calendar: calendar)
        switch item.kind {
        case .website:
            return [date, host(item.url)].compactMap { $0 }.joined(separator: " · ")
        case .branding:
            let who = item.studio.flatMap { $0.isEmpty ? nil : $0 } ?? item.sources.first
            return [date, who].compactMap { $0 }.joined(separator: " · ")
        case .mockup:
            let types = (item.categories[InspirationVocabulary.typeFamily] ?? []).enumerated().map { index, type in
                index == 0 ? label(type) : (spelled[type.lowercased()].map { $0 == "iPhone" || $0 == "MacBook" ? $0 : $0.lowercased() } ?? type)
            }
            return types.isEmpty ? date : types.joined(separator: ", ")
        }
    }

    // MARK: - The LinkedIn pages' colors

    /// The page's own color, else one drawn from its name, always the same, as the vault's tag bar did.
    static func color(ofSource name: String, in sources: [InspirationSourceRow]) -> String {
        if let source = sources.first(where: { fold($0.name) == fold(name) }), let color = source.color, isHex(color) { return color }
        return derivedColor(name)
    }

    /// The color of a branding's dot: its first page's.
    static func sourceColor(_ item: InspirationItemRow, sources: [InspirationSourceRow]) -> String? {
        item.sources.first.map { color(ofSource: $0, in: sources) }
    }

    /// One of the palette's colors, from the name (the same on every launch: no `hashValue`).
    static func derivedColor(_ name: String) -> String {
        let colors = [Palette.blue, Palette.violet, Palette.pink, Palette.orange, Palette.teal, Palette.green, Palette.yellow, Palette.red, Palette.brown]
        let hash = fold(name).unicodeScalars.reduce(UInt32(5_381)) { ($0 &* 33) &+ $1.value }
        return colors[Int(hash % UInt32(colors.count))]
    }

    static func isHex(_ text: String) -> Bool {
        text.wholeMatch(of: #/#[0-9A-Fa-f]{6}/#) != nil
    }

    // MARK: - An item's categories

    /// One family of an item's page: its values and what the vocabulary offers.
    struct CategoryRow: Identifiable, Equatable {
        let family: String
        let title: String
        let values: [String]
        /// The vocabulary's tags, in its order; for « autres », the item's own values.
        let options: [String]
        var id: String { family }
    }

    /// The families of an item's page: every family of the vocabulary (to add a value to an empty one), then the
    /// families the item has that the vocabulary does not know (« autres »).
    static func categoryRows(_ item: InspirationItemRow, vocabulary: InspirationVocabulary) -> [CategoryRow] {
        var rows = vocabulary.families.map { family in
            CategoryRow(family: family.name, title: family.title, values: item.categories[family.name] ?? [], options: family.tags.map(\.value))
        }
        let known = Set(rows.map(\.family))
        for family in item.categories.keys.sorted() where !known.contains(family) && !(item.categories[family] ?? []).isEmpty {
            let values = item.categories[family] ?? []
            rows.append(CategoryRow(family: family, title: label(family), values: values, options: values))
        }
        return rows
    }

    /// The categories once a value is ticked or unticked in a family; an empty family goes.
    static func toggling(_ categories: [String: [String]], family: String, value: String) -> [String: [String]] {
        var result = categories
        var values = result[family] ?? []
        if let index = values.firstIndex(where: { fold($0) == fold(value) }) {
            values.remove(at: index)
        } else {
            values.append(value)
        }
        result[family] = values.isEmpty ? nil : values
        return result
    }

    // MARK: - An item's links

    struct Link: Equatable, Identifiable {
        enum Target: Equatable {
            case web(URL)
            case finder(URL)
        }

        let title: String
        let target: Target
        var id: String { title }
    }

    /// The item's main links: « Ouvrir le site », « Voir sur LinkedIn », « Ouvrir le dossier » (in the Finder when
    /// the folder is on the Mac, else its Nextcloud link).
    static func links(_ item: InspirationItemRow, folderExists: (String) -> Bool = { path in
        var folder: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &folder) && folder.boolValue
    }) -> [Link] {
        func web(_ text: String?) -> URL? {
            guard let text, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
            return url
        }
        switch item.kind {
        case .website:
            return web(item.url).map { [Link(title: "Ouvrir le site", target: .web($0))] } ?? []
        case .branding:
            return web(item.url).map { [Link(title: "Voir sur LinkedIn", target: .web($0))] } ?? []
        case .mockup:
            if let local = item.extra.localFolder, folderExists(local) {
                return [Link(title: "Ouvrir le dossier", target: .finder(URL(fileURLWithPath: local, isDirectory: true)))]
            }
            return web(item.extra.folderURL).map { [Link(title: "Ouvrir le dossier", target: .web($0))] } ?? []
        }
    }

    /// The other addresses the item carries (a post's links), without the main one, each once.
    static func otherLinks(_ item: InspirationItemRow) -> [URL] {
        var seen = Set([item.url].compactMap { $0 })
        return item.links.compactMap { text -> URL? in
            guard seen.insert(text).inserted, let url = URL(string: text), url.scheme?.hasPrefix("http") == true else { return nil }
            return url
        }
    }
}
