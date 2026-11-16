import Foundation

/// Just enough HTML for public pages read once (16/11): the opening tags of an element, the text inside one,
/// the attributes of a tag, the entities. No DOM: the pages are scanned, never rendered nor run.
enum HTMLScan {
    /// The opening tags `<name …>` of the page, in order, attributes included.
    static func openingTags(_ name: String, in html: String) -> [Substring] {
        elements(name, in: html, withContent: false).map(\.tag)
    }

    /// Each `<name …>…</name>`: its opening tag and what it holds up to the first `</name>` (nested elements of
    /// the same name are not counted: enough for `<a>`, `<p>`, `<article>`).
    static func elements(_ name: String, in html: String, withContent: Bool = true) -> [(tag: Substring, content: Substring)] {
        var found: [(Substring, Substring)] = []
        let opening = "<" + name
        let closing = "</" + name
        var cursor = html.startIndex
        while let start = html.range(of: opening, options: .caseInsensitive, range: cursor..<html.endIndex) {
            // `<a` must not be the start of `<abbr`.
            guard start.upperBound < html.endIndex else { break }
            let next = html[start.upperBound]
            guard next == ">" || next == "/" || next.isWhitespace else {
                cursor = start.upperBound
                continue
            }
            guard let end = tagEnd(in: html, from: start.upperBound) else { break }
            let tag = html[start.lowerBound..<end]
            cursor = end
            guard withContent else {
                found.append((tag, html[end..<end]))
                continue
            }
            if let close = html.range(of: closing, options: .caseInsensitive, range: end..<html.endIndex) {
                found.append((tag, html[end..<close.lowerBound]))
                cursor = close.upperBound
            } else {
                found.append((tag, html[end..<html.endIndex]))
                break
            }
        }
        return found
    }

    /// After the `>` that closes a tag, quotes respected.
    private static func tagEnd(in html: String, from index: String.Index) -> String.Index? {
        var quote: Character?
        var index = index
        while index < html.endIndex {
            let character = html[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return html.index(after: index)
            }
            index = html.index(after: index)
        }
        return nil
    }

    /// The attributes of one tag, their names in lowercase, their values decoded (`&amp;` → `&`).
    static func attributes(_ tag: Substring) -> [String: String] {
        var values: [String: String] = [:]
        var index = tag.startIndex
        // Past the element's name.
        if index < tag.endIndex, tag[index] == "<" { index = tag.index(after: index) }
        while index < tag.endIndex, !tag[index].isWhitespace, tag[index] != ">", tag[index] != "/" { index = tag.index(after: index) }
        func skipSpaces() { while index < tag.endIndex, tag[index].isWhitespace || tag[index] == "/" { index = tag.index(after: index) } }
        while index < tag.endIndex {
            skipSpaces()
            guard index < tag.endIndex, tag[index] != ">" else { break }
            let nameStart = index
            while index < tag.endIndex, !tag[index].isWhitespace, tag[index] != "=", tag[index] != ">", tag[index] != "/" {
                index = tag.index(after: index)
            }
            let name = tag[nameStart..<index].lowercased()
            while index < tag.endIndex, tag[index].isWhitespace { index = tag.index(after: index) }
            var value = ""
            if index < tag.endIndex, tag[index] == "=" {
                index = tag.index(after: index)
                while index < tag.endIndex, tag[index].isWhitespace { index = tag.index(after: index) }
                if index < tag.endIndex, tag[index] == "\"" || tag[index] == "'" {
                    let quote = tag[index]
                    index = tag.index(after: index)
                    let valueStart = index
                    while index < tag.endIndex, tag[index] != quote { index = tag.index(after: index) }
                    value = String(tag[valueStart..<index])
                    if index < tag.endIndex { index = tag.index(after: index) }
                } else {
                    let valueStart = index
                    while index < tag.endIndex, !tag[index].isWhitespace, tag[index] != ">" { index = tag.index(after: index) }
                    value = String(tag[valueStart..<index])
                }
            }
            if !name.isEmpty, values[name] == nil { values[name] = decode(value) }
        }
        return values
    }

    /// Whether a tag's `class` holds this class.
    static func hasClass(_ attributes: [String: String], _ name: String) -> Bool {
        (attributes["class"] ?? "").split(whereSeparator: \.isWhitespace).contains { $0 == name }
    }

    /// The text of a piece of HTML: `<br>` and the ends of paragraphs as line breaks, the tags gone, the entities
    /// decoded, the non-breaking spaces as spaces.
    static func text(_ fragment: some StringProtocol) -> String {
        var text = String(fragment)
        text = text.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"</(p|div|li|h[1-6])>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
        text = decode(text).replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
        text = text.replacingOccurrences(of: "\r", with: "")
        text = text.replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One line: the spaces and line breaks folded into one space.
    static func line(_ text: String) -> String {
        decode(text).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}", "hellip": "…", "mdash": "—",
        "ndash": "–", "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“", "laquo": "«", "raquo": "»", "middot": "·",
        "bull": "•", "copy": "©", "reg": "®", "trade": "™", "euro": "€", "deg": "°", "times": "×",
        "eacute": "é", "egrave": "è", "ecirc": "ê", "euml": "ë", "agrave": "à", "acirc": "â", "auml": "ä",
        "ccedil": "ç", "icirc": "î", "iuml": "ï", "ocirc": "ô", "ouml": "ö", "ugrave": "ù", "ucirc": "û", "uuml": "ü",
        "Eacute": "É", "Egrave": "È", "Ecirc": "Ê", "Agrave": "À", "Ccedil": "Ç", "oelig": "œ", "OElig": "Œ",
        "aelig": "æ", "szlig": "ß", "ntilde": "ñ", "aacute": "á", "iacute": "í", "oacute": "ó", "uacute": "ú",
    ]

    /// `&amp;`, `&#39;`, `&#x27;`, `&eacute;` → their characters; an unknown entity stays as written.
    static func decode(_ text: some StringProtocol) -> String {
        guard text.contains("&") else { return String(text) }
        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            guard character == "&", let semicolon = text[index...].prefix(12).firstIndex(of: ";") else {
                result.append(character)
                index = text.index(after: index)
                continue
            }
            let entity = text[text.index(after: index)..<semicolon]
            var replacement: String?
            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                replacement = UInt32(entity.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if entity.hasPrefix("#") {
                replacement = UInt32(entity.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                replacement = named[String(entity)]
            }
            if let replacement {
                result += replacement
                index = text.index(after: semicolon)
            } else {
                result.append(character)
                index = text.index(after: index)
            }
        }
        return result
    }

    /// An address found in a page, made absolute on it: `//cdn…`, `/image.jpg`, `image.jpg`. `nil` for
    /// `data:`, `javascript:` and the like.
    static func resolve(_ href: String, base: URL) -> URL? {
        let href = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !href.isEmpty, let url = URL(string: href, relativeTo: base)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url
    }
}
