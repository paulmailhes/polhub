import Foundation

/// The little markdown an agent may write in a draft (Paul, 16/11: `brouillon` with « format » `markdown`): bold
/// `**…**`, italic `*…*`, lists `- ` and `1. `, links `[texte](https://…)`, paragraphs. Nothing else: a heading, an
/// image, a colour or HTML of its own stay text. Made by the app into simple HTML (`p`, `br`, `b`, `i`, `ul`, `ol`,
/// `li`, `a href` to http, https or mailto only) where everything the agent wrote is escaped, and into the plain
/// text the mail carries beside it. Pure, offline.
public enum MailMarkdown {
    enum Block: Equatable {
        case paragraph([String])
        case list(ordered: Bool, start: Int, items: [String])
    }

    /// The HTML that leaves in place of the plain text's.
    public static func html(_ markdown: String) -> String {
        blocks(markdown).map { block in
            switch block {
            case .paragraph(let lines):
                return "<p>" + lines.map(inline).joined(separator: "<br>") + "</p>"
            case .list(let ordered, let start, let items):
                let open = ordered ? (start == 1 ? "<ol>" : "<ol start=\"\(start)\">") : "<ul>"
                return open + items.map { "<li>" + inline($0) + "</li>" }.joined() + (ordered ? "</ol>" : "</ul>")
            }
        }.joined()
    }

    /// The same text without its marks, line for line as the agent wrote it: the mail's text part, and what Paul gets
    /// back to edit (« Repasser en texte simple »). A link keeps its address in brackets.
    public static func plain(_ markdown: String) -> String {
        var lines: [String] = []
        for line in Self.lines(markdown) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty, lines.last?.isEmpty ?? true { continue }
            lines.append(trimmed.isEmpty ? "" : unmarked(line.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)))
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Blocks

    static func lines(_ text: String) -> [String] {
        // No invisible character, nor the private ones the links borrow below.
        HTMLText.clean(text).replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    /// An item of a list: « - texte », or « 12. texte » with its number.
    static func item(_ line: String) -> (ordered: Bool, number: Int, text: String)? {
        if line.hasPrefix("- ") { return (false, 1, String(line.dropFirst(2))) }
        guard let range = line.range(of: #"^\d{1,4}\. "#, options: .regularExpression),
              let number = Int(line[range].dropLast(2)) else { return nil }
        return (true, number, String(line[range.upperBound...]))
    }

    /// Paragraphs and lists. A blank line ends a paragraph; between two items of one kind, it does not end their list.
    static func blocks(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var list: (ordered: Bool, start: Int, items: [String])?
        func endParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph)) }
            paragraph = []
        }
        func endList() {
            if let list { blocks.append(.list(ordered: list.ordered, start: list.start, items: list.items)) }
            list = nil
        }
        for raw in lines(markdown) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                endParagraph()
                continue
            }
            if let item = item(line) {
                endParagraph()
                if let open = list, open.ordered == item.ordered {
                    list?.items.append(item.text)
                } else {
                    endList()
                    list = (item.ordered, item.number, [item.text])
                }
                continue
            }
            endList()
            paragraph.append(line)
        }
        endParagraph()
        endList()
        return blocks
    }

    // MARK: - Within a line

    /// `[texte](adresse)`, and `![texte](adresse)` taken as a link: no image. The address may hold one pair of
    /// brackets (« …/Paris_(France) », « javascript:alert(1) », refused all the same).
    static let link = #"!?\[([^\[\]\n]+)\]\(((?:[^()\s]|\([^()\s]*\))+)\)"#
    static let bold = #"\*\*(?=\S)(.+?)(?<=\S)\*\*"#
    static let italic = #"(?<![*\w])\*(?=[^\s*])([^*\n<>]+?)(?<=\S)\*(?![*\w])"#
    /// An address written as it is (in the escaped text), up to a space, a tag, a mark or the last punctuation.
    static let bare = #"https?://[^\s<>"*\x{E000}\x{E001}]+[^\s<>"*.,;:!?)\x{E000}\x{E001}]"#

    /// Only these leave as links: never `javascript:`, `data:` or a file of the Mac.
    static func allowed(_ address: String) -> Bool {
        let lower = address.lowercased()
        return lower.hasPrefix("https://") || lower.hasPrefix("http://") || lower.hasPrefix("mailto:")
    }

    /// One line as HTML. The links are set aside first (each as private characters no text holds: `lines` took them
    /// out), then everything is escaped, then the marks become tags: no tag of the agent's ever passes.
    static func inline(_ line: String) -> String {
        var anchors: [String] = []
        let withoutLinks = replace(line, link) { groups in
            let label = emphasis(HTMLText.escape(groups[1])), address = groups[2]
            anchors.append(allowed(address) ? "<a href=\"\(HTMLText.escape(address))\">\(label)</a>" : label)
            return "\u{E000}\(anchors.count - 1)\u{E001}"
        }
        let marked = emphasis(HTMLText.escape(withoutLinks))
            .replacingOccurrences(of: bare, with: "<a href=\"$0\">$0</a>", options: .regularExpression)
        return replace(marked, #"\x{E000}(\d+)\x{E001}"#) { groups in
            Int(groups[1]).flatMap { anchors.indices.contains($0) ? anchors[$0] : nil } ?? ""
        }
    }

    static func emphasis(_ escaped: String) -> String {
        escaped.replacingOccurrences(of: bold, with: "<b>$1</b>", options: .regularExpression)
            .replacingOccurrences(of: italic, with: "<i>$1</i>", options: .regularExpression)
    }

    /// One line without its marks: « texte (adresse) » for a link, the bare text for a link refused.
    static func unmarked(_ line: String) -> String {
        replace(line, link) { groups in
            let label = groups[1], address = groups[2]
            guard allowed(address) else { return label }
            return label == address || "mailto:" + label == address ? label : "\(label) (\(address))"
        }
        .replacingOccurrences(of: bold, with: "$1", options: .regularExpression)
        .replacingOccurrences(of: italic, with: "$1", options: .regularExpression)
    }

    /// Each match of `pattern` replaced by what `transform` makes of its groups (the whole match first).
    static func replace(_ text: String, _ pattern: String, _ transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        for match in regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let whole = Range(match.range, in: result) else { continue }
            let groups = (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: result).map { String(result[$0]) } ?? "" }
            result.replaceSubrange(whole, with: transform(groups))
        }
        return result
    }
}
