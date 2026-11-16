import Foundation
import Persistence
import Yams

/// The properties of a vault note and its body, read as the vault's scripts wrote them.
enum VaultFrontmatter {
    /// Numbers, dates and booleans stay text: a LinkedIn id (19 digits) would lose its last digits as a number,
    /// the vault's days are local days, not UTC midnights, and a bare hashtag `- no` or `- on` is a word, not
    /// `false` or `true` (YAML 1.1, review of 16/11); `bool(_:)` reads « true » and « yes » from the text.
    static let resolver = Resolver.default.removing(.timestamp).removing(.int).removing(.float).removing(.bool)

    enum Failure: Error, Equatable {
        /// No `---` block at the top.
        case none
        /// A block YAML cannot read.
        case unreadable
    }

    static func read(_ raw: String) -> Result<(properties: [String: Any], body: String), Failure> {
        // Windows line endings and a byte-order mark would hide everything.
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let (frontmatter, body) = split(text)
        guard let frontmatter else { return .failure(.none) }
        guard let loaded = try? Yams.load(yaml: frontmatter, resolver) else { return .failure(.unreadable) }
        if loaded == nil || loaded is NSNull { return .success(([:], body)) }
        guard let properties = loaded as? [String: Any] else { return .failure(.unreadable) }
        return .success((properties, body))
    }

    /// The YAML between the first two `---`, and the rest.
    static func split(_ text: String) -> (String?, String) {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return (nil, text) }
        return (lines[1..<end].joined(separator: "\n"), lines[(end + 1)...].joined(separator: "\n"))
    }

    /// A list, a list of lists (`[[X]]` unquoted reads as a list in a list: it was a link), or one value.
    static func strings(_ value: Any?) -> [String] {
        switch value {
        case let list as [Any]:
            list.flatMap { item in (item as? [Any]).map { inner in strings(inner).map { "[[\($0)]]" } } ?? strings(item) }
        case let string as String: [string]
        case nil, is NSNull: []
        case let other?: ["\(other)"]
        }
    }

    /// The trimmed, non-empty values.
    static func list(_ value: Any?) -> [String] {
        strings(value).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// The first non-empty value.
    static func text(_ value: Any?) -> String? {
        list(value).first
    }

    static func bool(_ value: Any?) -> Bool {
        switch value {
        case let flag as Bool: flag
        case let text as String: ["true", "yes", "1", "oui"].contains(text.trimmingCharacters(in: .whitespaces).lowercased())
        default: false
        }
    }

    static func double(_ value: Any?) -> Double? {
        text(value).flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
    }

    static func int(_ value: Any?) -> Int? {
        text(value).flatMap { Int($0) }
    }

    /// `2026-11-13` or `2026-11-13T10:00`, in the Mac's time zone.
    static func date(_ value: Any?) -> Date? {
        guard let text = text(value) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    /// `[[database/Branding/_media/x.jpg]]`, `[[x.jpg|alias]]`, `![[x.jpg]]` → the target; a plain text is
    /// returned as it is.
    static func linkTarget(_ text: String) -> String {
        var target = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if target.hasPrefix("!") { target.removeFirst() }
        if target.hasPrefix("[["), target.hasSuffix("]]") {
            target = String(target.dropFirst(2).dropLast(2))
            if let bar = target.firstIndex(of: "|") { target = String(target[..<bar]) }
            if let hash = target.firstIndex(of: "#") { target = String(target[..<hash]) }
        }
        return target.trimmingCharacters(in: .whitespaces)
    }

    static func isRemote(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }
}

/// `_sources.md`: the table `| Nom | Lien | Couleur |` of the LinkedIn pages followed.
public enum SourcesTable {
    public struct Page: Equatable, Sendable {
        public let name: String
        /// As `InspirationSourceRow.normalizedLink` writes it.
        public let link: String
        /// `#e8b923`, lowercase; `nil` when the cell is empty or not a color.
        public let color: String?
    }

    public static func parse(_ text: String) -> [Page] {
        text.components(separatedBy: "\n").compactMap { line in
            let cells = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 4, !cells[1].isEmpty, cells[1].wholeMatch(of: #/[-: ]+/#) == nil,
                  VaultFrontmatter.isRemote(cells[2]) else { return nil }
            let color = cells[3].wholeMatch(of: #/#[0-9a-fA-F]{6}/#) != nil ? cells[3].lowercased() : nil
            return Page(name: cells[1], link: InspirationSourceRow.normalizedLink(cells[2]), color: color)
        }
    }
}
