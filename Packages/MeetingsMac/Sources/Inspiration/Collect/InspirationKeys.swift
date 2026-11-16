import Foundation

/// The key of each kind, written one way so that an item is never twice (16/11).
public enum InspirationKeys {
    /// A site by its address: `https`, the host in lowercase without `www.`, the path without its last slash,
    /// nothing after `?` or `#`. `nil` when it is not a web address. (n8n keyed sites on their title, and two
    /// « Home » trod on each other.)
    public static func website(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }
        if !text.contains("://") {
            guard !text.contains(":") || text.firstMatch(of: #/^[^/]+:\d+(/|$)/#) != nil else { return nil }
            text = "https://" + text
        }
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = components.host?.lowercased(),
              host.contains("."), host.wholeMatch(of: #/[\p{L}\p{N}.-]+/#) != nil
        else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        let port = components.port.map { [80, 443].contains($0) ? "" : ":\($0)" } ?? ""
        return "https://\(host)\(port)\(path)".precomposedStringWithCanonicalMapping
    }

    /// A LinkedIn post by its id (19 digits, beyond what a double holds: always text). From `urn`, else from the
    /// post's address.
    public static func linkedInPost(urn: String?, link: String?) -> String? {
        if let urn = urn?.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")), urn.wholeMatch(of: #/\d{6,25}/#) != nil {
            return urn
        }
        if let link, let match = link.firstMatch(of: #/urn:li:(?:activity|share|ugcPost):(\d{6,25})/#) {
            return String(match.output.1)
        }
        return nil
    }

    /// When a post was published: its id holds the Unix milliseconds in its upper bits (`id >> 22`).
    public static func publicationDate(urn: String) -> Date? {
        guard let id = UInt64(urn) else { return nil }
        let date = Date(timeIntervalSince1970: Double(id >> 22) / 1000)
        // LinkedIn's ids began in 2010; anything outside is not such an id.
        guard date > Date(timeIntervalSince1970: 1_262_304_000), date < Date(timeIntervalSince1970: 4_102_444_800) else { return nil }
        return date
    }

    /// Lowercase, without accents nor extra spaces: two writings of the same title meet.
    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
