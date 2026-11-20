import Foundation
import Persistence
import HubDesign
import Yams

/// The controlled vocabulary of a collection's categories (16/11): its families (`secteur`, `style`…), the tags
/// of each with their French description, how many a note takes, and the pieces of the tagger's prompt. The same
/// files as the vault's (`vocabulaire-websites.json`, `vocabulaire-branding.json`, without their `_doc`), plus
/// the mock-ups' types as the family `type`.
public struct InspirationVocabulary: Sendable, Equatable {
    /// Where it was read.
    public enum Origin: Sendable, Equatable {
        /// hub's own copy (`AppPaths.inspiration`): the vault's, with the tags Paul added by hand, brought by the
        /// import while there was a vault.
        case app(URL)
        /// The one shipped with hub.
        case bundled
    }

    public struct Tag: Sendable, Equatable, Hashable, Identifiable {
        public let value: String
        public let description: String
        public var id: String { value }
    }

    public struct Family: Sendable, Equatable, Identifiable {
        /// `secteur`, `style`, `techno`, `typo`, `support`; `type` for the mock-ups.
        public let name: String
        /// In the file's order.
        public let tags: [Tag]
        public let minimum: Int
        public let maximum: Int
        /// What the family means, for the tagger.
        public let prompt: String?
        private let values: Set<String>

        init(name: String, tags: [Tag], minimum: Int, maximum: Int, prompt: String?) {
            self.name = name
            self.tags = tags
            self.minimum = minimum
            self.maximum = maximum
            self.prompt = prompt
            self.values = Set(tags.map { $0.value.lowercased() })
        }

        public var id: String { name }
        /// « Secteur », as the vault's tag bar wrote it.
        // `Words`' capital, the same everywhere (lot 10, 20/11).
        public var title: String { Words.capitalizedFirst(name) }

        public func contains(_ tag: String) -> Bool { values.contains(tag.lowercased()) }

        public func description(of tag: String) -> String? {
            tags.first { $0.value.lowercased() == tag.lowercased() }?.description
        }
    }

    /// The tagger's prompt, as the vault's file words it (English, for the model).
    public struct Prompt: Sendable, Equatable {
        /// « branding case studies (…) for a designer's reference library ».
        public let subject: String
        public let rules: [String]
        /// The `police` (fonts) and `client` answers.
        public let fonts: String
        public let client: String
        /// Said after the text, and when the first answer was not usable.
        public let suffix: String
        public let reminder: String
    }

    /// A line of the text's header: « Brand: » followed by the note's `titre`.
    public struct HeaderField: Sendable, Equatable {
        public let label: String
        public let property: String
    }

    /// The family of the tags no vocabulary knows: kept, never dropped.
    public static let otherFamily = "autres"
    /// The mock-ups' types.
    public static let typeFamily = "type"

    public let kind: InspirationKind
    public let version: Int
    public let families: [Family]
    public let minimumTotal: Int
    public let maximumTotal: Int
    /// The families trimmed first when an answer has too many tags.
    public let trimOrder: [String]
    public let header: [HeaderField]
    /// Lines left out of the text submitted (« [Voir sur LinkedIn] »).
    public let ignoredLines: [String]
    /// Fewer words than this (header labels aside), a note is not submitted.
    public let minimumWords: Int
    /// The tags every note of the collection carries (`site`, `branding`, `mockup`): not categories.
    public let fixedTags: [String]
    /// The property whose slug is also a tag (`source` on branding: `galerie-exemple`).
    public let sourceTagProperty: String?
    public let prompt: Prompt?
    public var origin: Origin

    public func family(_ name: String) -> Family? { families.first { $0.name == name } }

    // MARK: - Reading

    public static func fileName(_ kind: InspirationKind) -> String {
        "vocabulaire-\(collection(kind)).json"
    }

    static func collection(_ kind: InspirationKind) -> String {
        switch kind {
        case .website: "websites"
        case .branding: "branding"
        case .mockup: "mockups"
        }
    }

    public static func bundledURL(_ kind: InspirationKind) -> URL? {
        Bundle.module.url(forResource: "vocabulaire-\(collection(kind))", withExtension: "json", subdirectory: "Resources")
    }

    public static func bundled(_ kind: InspirationKind) throws -> InspirationVocabulary {
        guard let url = bundledURL(kind) else { throw VocabularyError.missing(fileName(kind)) }
        return try parse(Data(contentsOf: url), kind: kind, origin: .bundled)
    }

    /// hub's own copy: the vault's, brought by the import, so that Paul's tags outlived Obsidian.
    public static func appCopy(_ kind: InspirationKind, paths: AppPaths) -> URL {
        paths.inspiration.appending(path: fileName(kind))
    }

    /// hub's own copy when there is one that reads, else the bundled one.
    public static func load(_ kind: InspirationKind, paths: AppPaths? = nil) -> InspirationVocabulary {
        if let paths {
            let url = appCopy(kind, paths: paths)
            if let data = try? Data(contentsOf: url), let vocabulary = try? parse(data, kind: kind, origin: .app(url)) {
                return vocabulary
            }
        }
        return (try? bundled(kind)) ?? InspirationVocabulary(
            kind: kind, version: 0, families: [], minimumTotal: 0, maximumTotal: 0, trimOrder: [], header: [], ignoredLines: [],
            minimumWords: 0, fixedTags: [], sourceTagProperty: nil, prompt: nil, origin: .bundled)
    }

    /// The vault's format. The values come from `JSONSerialization`; the tags' order, which it loses, from
    /// YAML (JSON is YAML), and alphabetical when that fails.
    public static func parse(_ data: Data, kind: InspirationKind, origin: Origin = .bundled) throws -> InspirationVocabulary {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let names = json["familles"] as? [String], !names.isEmpty else {
            throw VocabularyError.unreadable
        }
        let order = keyOrder(data)
        let minimum = json["minimum"] as? [String: Any] ?? [:]
        let maximum = json["maximum"] as? [String: Any] ?? [:]
        let promptJSON = json["prompt"] as? [String: Any]
        let familyPrompts = promptJSON?["familles"] as? [String: Any] ?? [:]
        func int(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }
        let families = try names.map { name -> Family in
            guard let entries = json[name] as? [String: Any] else { throw VocabularyError.unreadable }
            let known = order[name] ?? []
            let keys = known.filter { entries[$0] != nil } + entries.keys.filter { !known.contains($0) }.sorted()
            let tags = keys.map { Tag(value: $0, description: entries[$0] as? String ?? "") }
            return Family(name: name, tags: tags, minimum: int(minimum[name]) ?? 0, maximum: int(maximum[name]) ?? tags.count,
                          prompt: familyPrompts[name] as? String)
        }
        let text = json["texte"] as? [String: Any] ?? [:]
        let writing = json["ecriture"] as? [String: Any] ?? [:]
        let header = (text["entete"] as? [[String]] ?? []).compactMap { pair in
            pair.count == 2 ? HeaderField(label: pair[0], property: pair[1]) : nil
        }
        let prompt = promptJSON.map { p in
            Prompt(subject: p["objet"] as? String ?? "", rules: p["regles"] as? [String] ?? [], fonts: p["police"] as? String ?? "",
                   client: p["client"] as? String ?? "", suffix: p["suffixe"] as? String ?? "", reminder: p["rappel"] as? String ?? "")
        }
        let source = (writing["tag_source"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return InspirationVocabulary(
            kind: kind, version: int(json["version"]) ?? 0, families: families,
            minimumTotal: int(minimum["total"]) ?? 0, maximumTotal: int(maximum["total"]) ?? families.reduce(0) { $0 + $1.maximum },
            trimOrder: json["rognage"] as? [String] ?? [], header: header, ignoredLines: text["ignorer_lignes"] as? [String] ?? [],
            minimumWords: int(text["minimum_mots"]) ?? 0, fixedTags: writing["tags_fixes"] as? [String] ?? [],
            sourceTagProperty: source, prompt: prompt, origin: origin)
    }

    /// The order of the keys of each top-level object, as written.
    static func keyOrder(_ data: Data) -> [String: [String]] {
        guard let text = String(data: data, encoding: .utf8), let root = try? Yams.compose(yaml: text)?.mapping else { return [:] }
        var order: [String: [String]] = [:]
        for (key, value) in root {
            guard let name = key.string, let mapping = value.mapping else { continue }
            order[name] = mapping.keys.compactMap(\.string)
        }
        return order
    }

    // MARK: - Using it

    /// The tagger's instructions, built as the vault's `ia_locale.py` did: what is classified, the rules, each
    /// family with its bounds, fonts and client, then every tag with its description. `nil` without a prompt.
    public var instructions: String? {
        guard let prompt else { return nil }
        var lines = ["You classify \(prompt.subject).", "", "Rules:",
                     "- Use ONLY the tags listed below, spelled exactly as written (they are French, lowercase). Never invent a tag."]
        lines += prompt.rules.map { "- \($0)" }
        lines += families.map { "- \"\($0.name)\" (\($0.minimum)-\($0.maximum)): \($0.prompt ?? "")" }
        lines.append("- \"police\": \(prompt.fonts)")
        lines.append("- \"client\": \(prompt.client)")
        for family in families {
            lines += ["", "\(family.name):"] + family.tags.map { "  \($0.value): \($0.description)" }
        }
        return lines.joined(separator: "\n")
    }

    /// The text submitted to the tagger: the header (« Brand: … ») from the properties, then the body without
    /// embeds nor ignored lines, links reduced to their text.
    public func taggingText(fields: [String: String], body: String) -> String {
        let lines = body.components(separatedBy: "\n").filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("![[") && trimmed.hasSuffix("]]") { return false }
            return !ignoredLines.contains { trimmed.hasPrefix($0) }
        }.map { $0.replacing(#/\[([^\]]+)\]\([^)]+\)/#) { String($0.output.1) } }
        let text = lines.joined(separator: "\n").replacing(#/\n{3,}/#, with: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let head = header.map { "\($0.label): \((fields[$0.property] ?? "").replacingOccurrences(of: "💥", with: "").trimmingCharacters(in: .whitespaces))" }
            .joined(separator: "\n")
        return head.isEmpty ? text : "\(head)\n\n\(text)"
    }

    /// Fewer words than `minimumWords`, the header's labels aside: nothing to read, no call.
    public func isTooShort(_ text: String) -> Bool {
        minimumWords > 0 && text.split(whereSeparator: \.isWhitespace).count < minimumWords + header.count
    }
}

public enum VocabularyError: Error, Equatable, CustomStringConvertible {
    case missing(String)
    case unreadable

    public var description: String {
        switch self {
        case .missing(let name): "Le vocabulaire « \(name) » manque à hub."
        case .unreadable: "Le vocabulaire est illisible."
        }
    }
}
