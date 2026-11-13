import Foundation

/// The blocks of a note, as Obsidian's reading mode shows them: enough for Paul's notes and journal.
public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case bullet(depth: Int, text: String)
    case task(done: Bool, text: String)
    case quote(String)
    case callout(kind: String, title: String, body: String)
    case numbered(number: Int, depth: Int, text: String)
    case code(String)
    case paragraph(String)
}

public enum MarkdownBlocks {
    public static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []

        func flushParagraph() {
            // A single line break stays one, as in Obsidian's reading mode (review, minor 12).
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }
        func flushQuote() {
            guard !quote.isEmpty else { return }
            if let head = quote.first?.firstMatch(of: #/^\[!(\w+)\][-+]?\s*(.*)$/#) {
                blocks.append(.callout(kind: String(head.output.1).lowercased(), title: String(head.output.2),
                                       body: quote.dropFirst().joined(separator: "\n")))
            } else {
                blocks.append(.quote(quote.joined(separator: "\n")))
            }
            quote = []
        }

        var fence: [String]?
        for raw in text.components(separatedBy: "\n") {
            let line = raw.replacingOccurrences(of: "\t", with: "  ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if let lines = fence {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    fence = nil
                } else {
                    flushQuote()
                    flushParagraph()
                    fence = []
                }
                continue
            }
            if fence != nil {
                fence?.append(raw)
                continue
            }
            if trimmed.hasPrefix(">") {
                flushParagraph()
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }
            flushQuote()
            if trimmed.isEmpty {
                flushParagraph()
            } else if let heading = trimmed.firstMatch(of: #/^(#{1,6})\s+(.+)$/#) {
                flushParagraph()
                blocks.append(.heading(level: heading.output.1.count, text: String(heading.output.2)))
            } else if let task = line.firstMatch(of: #/^\s*[-*+] \[([ xX])\]\s+(.*)$/#) {
                flushParagraph()
                blocks.append(.task(done: task.output.1 != " ", text: String(task.output.2)))
            } else if let item = line.firstMatch(of: #/^(\s*)(\d+)[.)]\s+(.*)$/#) {
                flushParagraph()
                blocks.append(.numbered(number: Int(item.output.2) ?? 1, depth: item.output.1.count / 2, text: String(item.output.3)))
            } else if let bullet = line.firstMatch(of: #/^(\s*)[-*+]\s+(.*)$/#) {
                flushParagraph()
                blocks.append(.bullet(depth: bullet.output.1.count / 2, text: String(bullet.output.2)))
            } else {
                paragraph.append(trimmed)
            }
        }
        if let lines = fence { blocks.append(.code(lines.joined(separator: "\n"))) }
        flushQuote()
        flushParagraph()
        return blocks
    }
}
