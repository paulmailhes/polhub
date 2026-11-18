import Foundation

/// An answer of Colin's as the thread shows it (18/11): text, a message to copy (« Copier »), a line to keep
/// (« Garder »). The model writes the two last between fences its instructions name.
public enum ColinAnswer {
    public enum Block: Equatable, Sendable {
        case text(String)
        case message(String)
        case keep(String)
    }

    /// `open`: the answer is being written — a block begun is already what it will be (the Accueil's pass, 18/11).
    public static func blocks(_ answer: String, open: Bool = false) -> [Block] {
        var blocks: [Block] = []
        var text: [String] = []
        var fenced: (kind: String, lines: [String], opening: String)?
        func flush() {
            let joined = text.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { blocks.append(.text(joined)) }
            text = []
        }
        for line in answer.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let open = fenced {
                if trimmed == "```" {
                    let body = open.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    flush()
                    blocks.append(open.kind == "message" ? .message(body) : .keep(body))
                    fenced = nil
                } else {
                    fenced?.lines.append(line)
                }
            } else if trimmed == "```message" || trimmed == "```retenir" {
                fenced = (String(trimmed.dropFirst(3)), [], line)
            } else {
                text.append(line)
            }
        }
        // A block never closed is what it looks like: text; while it is written, what it will be.
        if let begun = fenced {
            if open {
                flush()
                let body = begun.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                blocks.append(begun.kind == "message" ? .message(body) : .keep(body))
                return blocks
            }
            text += [begun.opening] + begun.lines
        }
        flush()
        return blocks
    }

    /// The inline markdown of a text (bold, italics), every link turned into plain words: its words, then its address
    /// in clear. A link written by the model is never clickable.
    public static func inline(_ text: String) -> AttributedString {
        var shown = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        for run in shown.runs.reversed() {
            guard let link = run.link else { continue }
            let words = String(shown[run.range].characters)
            shown[run.range].link = nil
            let address = link.absoluteString
            if words != address, !address.hasSuffix(words) { shown.insert(AttributedString(" (\(address))"), at: run.range.upperBound) }
        }
        return shown
    }
}
