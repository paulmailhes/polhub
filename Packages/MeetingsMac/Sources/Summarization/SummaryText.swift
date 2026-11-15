import Domain
import Foundation
import Persistence

/// A summary as the page shows it: its four parts (15/11), when it has the app's shape.
public struct SummarySections: Equatable, Sendable {
    public var overview: String
    public var points: [String]
    public var decisions: [String]
    /// What could not be summarized (« Partiel »), or `nil`.
    public var missing: String?

    public init(overview: String, points: [String] = [], decisions: [String] = [], missing: String? = nil) {
        self.overview = overview
        self.points = points
        self.decisions = decisions
        self.missing = missing
    }
}

/// What the base keeps (the text on the meeting, the actions as rows), and how it is read back: the page's
/// parts, the list's first line, « Copier le compte rendu ».
public enum SummaryText {
    static let overviewTitle = "Résumé"
    static let pointsTitle = "Points clés"
    static let decisionsTitle = "Décisions"

    public static func markdown(_ summary: MeetingSummary) -> String {
        var text = "## \(overviewTitle)\n\n" + summary.overview
        if !summary.points.isEmpty {
            text += "\n\n## \(pointsTitle)\n\n" + summary.points.map { "- " + $0 }.joined(separator: "\n")
        }
        if !summary.decisions.isEmpty {
            text += "\n\n## \(decisionsTitle)\n\n" + summary.decisions.map { "- " + $0 }.joined(separator: "\n")
        }
        if let missing = summary.missing { text += "\n\n_Partiel : \(missing)._" }
        return text
    }

    public static func actionRows(_ actions: [SummaryAction], at date: Date) -> [ActionRow] {
        actions.enumerated().map { index, action in
            ActionRow(text: action.text + (action.due.map { " (\($0))" } ?? ""), owner: action.owner, position: Double(index), createdAt: date)
        }
    }

    /// « la partie 2 sur 5 n'a pas pu être résumée (refusée par le modèle d'Apple) ; … », or `nil`.
    static func missing(dropped: [Int], of count: Int, shortened: Bool) -> String? {
        var parts: [String] = []
        if dropped.count == 1 {
            parts.append("la partie \(dropped[0]) sur \(count) n'a pas pu être résumée (refusée par le modèle d'Apple)")
        } else if dropped.count > 1 {
            let numbers = dropped.map(String.init)
            let list = numbers.dropLast().joined(separator: ", ") + " et " + numbers.last!
            parts.append("les parties \(list) sur \(count) n'ont pas pu être résumées (refusées par le modèle d'Apple)")
        }
        if shortened { parts.append("les notes ont été raccourcies pour tenir dans la fenêtre du modèle") }
        return parts.isEmpty ? nil : parts.joined(separator: " ; ")
    }

    // MARK: - Reading it back

    /// The four parts of a summary the app wrote; `nil` for another shape (the vault's summaries), which the page
    /// shows as Markdown.
    public static func sections(_ markdown: String) -> SummarySections? {
        var sections = SummarySections(overview: "")
        var current: String?
        var paragraphs: [String] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { paragraphs.append(paragraph.joined(separator: "\n")) }
            paragraph = []
        }
        for raw in markdown.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let missing = missingLine(line) {
                sections.missing = missing
                continue
            }
            if line.hasPrefix("#") {
                guard line.hasPrefix("## "), [overviewTitle, pointsTitle, decisionsTitle].contains(String(line.dropFirst(3))) else { return nil }
                flush()
                current = String(line.dropFirst(3))
                continue
            }
            switch current {
            case overviewTitle?:
                if line.isEmpty { flush() } else { paragraph.append(line) }
            case pointsTitle?, decisionsTitle?:
                guard !line.isEmpty else { continue }
                var items = current == pointsTitle ? sections.points : sections.decisions
                if line.hasPrefix("- ") {
                    items.append(String(line.dropFirst(2)))
                } else if let last = items.popLast() {
                    // A line that goes on the item above.
                    items.append(last + " " + line)
                } else {
                    return nil
                }
                if current == pointsTitle { sections.points = items } else { sections.decisions = items }
            default:
                // Text before the first part: not the app's shape.
                if !line.isEmpty { return nil }
            }
        }
        flush()
        sections.overview = paragraphs.joined(separator: "\n\n")
        guard current != nil, !sections.overview.isEmpty || !sections.points.isEmpty || !sections.decisions.isEmpty else { return nil }
        return sections
    }

    /// The italic line that says the summary is « Partiel ».
    static func missingLine(_ line: String) -> String? {
        guard line.hasPrefix("_Partiel : "), line.hasSuffix("_"), line.count > 12 else { return nil }
        var text = String(line.dropFirst("_Partiel : ".count).dropLast())
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// The first lines of a summary, for the list of meetings: its « Résumé »; in another shape, the first lines under
    /// a « Résumé » title, else the first ones of the text, in its order (correctifs, 15/11); cut at `limit` characters.
    public static func overview(_ markdown: String, limit: Int = 200) -> String? {
        var text = sections(markdown)?.overview
        if text?.isEmpty != false {
            let blocks = blocks(markdown)
            func first(_ blocks: ArraySlice<Block>) -> String? { blocks.first { $0.kind != .heading }?.text }
            if let title = blocks.firstIndex(where: { $0.kind == .heading && fold($0.text).hasPrefix("resume") }) {
                text = first(blocks[(title + 1)...].prefix { $0.kind != .heading })
            } else {
                text = nil
            }
            text = text ?? first(blocks[...])
        }
        guard var text = text?.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        text = plain(text)
        guard text.count > limit else { return text }
        let cut = text.prefix(limit)
        return (cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)) + "…"
    }

    // MARK: - « Copier le compte rendu »

    /// The summary and its actions, ready to paste in a mail: plain text, and simple HTML (titles in bold, lists)
    /// that Gmail keeps when it is pasted (15/11).
    public static func export(title: String, subtitle: String, markdown: String, actions: [ActionRow]) -> (plain: String, html: String) {
        var blocks = blocks(markdown)
        if !actions.isEmpty {
            blocks.append(Block(kind: .heading, text: "Actions"))
            blocks += actions.map { action in
                Block(kind: .item, text: action.text + (action.owner.map { " — \($0)" } ?? "") + (action.done ? " (fait)" : ""))
            }
        }
        var plain = title + (subtitle.isEmpty ? "" : "\n" + subtitle)
        var html = "<p><b>\(escaped(title))</b>" + (subtitle.isEmpty ? "" : "<br>\(escaped(subtitle))") + "</p>"
        var inList = false
        for (index, block) in blocks.enumerated() {
            let previous = index > 0 ? blocks[index - 1].kind : nil
            switch block.kind {
            case .heading:
                plain += "\n\n" + block.text
            case .paragraph:
                plain += (previous == .heading ? "\n" : "\n\n") + block.text
            case .item:
                plain += (previous == .item ? "\n" : previous == .heading ? "\n" : "\n\n") + "- " + block.text
            }
            if block.kind == .item, !inList { html += "<ul>"; inList = true }
            if block.kind != .item, inList { html += "</ul>"; inList = false }
            switch block.kind {
            case .heading: html += "<p><b>\(escaped(block.text))</b></p>"
            case .paragraph: html += "<p>\(escaped(block.text).replacingOccurrences(of: "\n", with: "<br>"))</p>"
            case .item: html += "<li>\(escaped(block.text))</li>"
            }
        }
        if inList { html += "</ul>" }
        return (plain + "\n", html)
    }

    struct Block: Equatable {
        enum Kind { case heading, paragraph, item }
        var kind: Kind
        var text: String
    }

    /// Markdown as titles, paragraphs and list items, without its marks; the « Partiel » line stays out.
    static func blocks(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { blocks.append(Block(kind: .paragraph, text: plain(paragraph.joined(separator: "\n")))) }
            paragraph = []
        }
        for raw in markdown.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || missingLine(line) != nil {
                flush()
            } else if let heading = line.firstMatch(of: #/^#{1,6}\s+(.+)$/#) {
                flush()
                blocks.append(Block(kind: .heading, text: plain(String(heading.output.1))))
            } else if let item = line.firstMatch(of: #/^(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?(.*)$/#) {
                flush()
                blocks.append(Block(kind: .item, text: plain(String(item.output.1))))
            } else {
                var text = line.hasPrefix(">") ? String(line.drop { $0 == ">" || $0 == " " }) : line
                // A callout of the vault (`> [!note] Titre`): its title only.
                if let callout = text.firstMatch(of: #/^\[![A-Za-z-]+\][+-]?\s*(.*)$/#) { text = String(callout.output.1) }
                if !text.isEmpty { paragraph.append(text) }
            }
        }
        flush()
        return blocks
    }

    /// Without its inline Markdown (bold, italic, code, links) and the vault's wiki links (`[[Nom|texte]]` → texte);
    /// the line breaks stay (correctifs, 15/11: also what the projects' excerpts use).
    public static func plain(_ text: String) -> String {
        let unlinked = text.replacing(#/\[\[([^\]|#]+)(#[^\]|]*)?(\|([^\]]+))?\]\]/#) { match in
            String(match.output.4 ?? match.output.1)
        }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: unlinked, options: options)).map { String($0.characters) } ?? unlinked
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
