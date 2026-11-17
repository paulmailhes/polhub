import Foundation

/// The formatted text Paul writes, as in Gmail (17/11: « une mise en forme comme si j'étais sur Gmail, et que je
/// puisse la modifier »): what the editor gives is kept to simple formatting before it is saved or sent — bold,
/// italic, underline, lists, quotes, links to http, https or mailto — and everything else goes, or keeps only its
/// words (a colour, a font, a span). Parsed by Foundation, offline, nothing loaded.
public enum MailRichText {
    /// The elements that stay, without any attribute but a link's address and a list's first number.
    static let kept: Set<String> = ["p", "div", "br", "b", "strong", "i", "em", "u", "ul", "ol", "li", "a", "blockquote"]
    /// The elements that go with everything inside them.
    static let dropped: Set<String> = ["script", "style", "head", "title", "meta", "link", "base", "iframe", "frame", "frameset", "object",
                                       "embed", "applet", "img", "svg", "math", "form", "input", "button", "select", "textarea",
                                       "template", "noscript", "video", "audio", "source", "picture", "canvas"]
    static let rootID = "polhub-texte"

    /// The editor's HTML, kept to simple formatting.
    public static func clean(_ html: String) -> String {
        // Inside a block of its own: the parser never wraps loose words in a paragraph there.
        let source = "<html><body><div id=\"\(rootID)\">" + HTMLText.clean(html) + "</div></body></html>"
        guard let document = try? XMLDocument(xmlString: source, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]),
              let root = (try? document.nodes(forXPath: "//*[@id='\(rootID)']"))?.first as? XMLElement else {
            return Self.html(fromPlain: HTMLText.plain(html))
        }
        sanitize(root)
        let inner = (root.children ?? []).map(\.xmlString).joined()
        // XML writes `<br></br>` (an HTML reader sees two lines), and tidy lays its output out with line breaks (after a
        // `<br>`, before closing tags, at the end), which HTML reads as spaces at most.
        return inner.replacingOccurrences(of: #"</br>"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<br\s*/>"#, with: "<br>", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"(?i)<br>\n"#, with: "<br>", options: .regularExpression)
            .replacingOccurrences(of: #"\n(?=</)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .newlines)
            .replacingOccurrences(of: "\n", with: " ")
    }

    /// The mail's text part: paragraphs and lines kept, list items as bullets, a link's address after its words.
    public static func plain(_ html: String) -> String {
        let cleaned = clean(html)
        let unlinked = MailMarkdown.replace(cleaned, #"<a href="([^"]*)">(.*?)</a>"#) { groups in
            let address = groups[1], label = groups[2]
            let words = HTMLText.plain(label), target = HTMLText.plain(address)
            return words == target || "mailto:" + words == target ? label : "\(label) (\(address))"
        }
        return HTMLText.plain(unlinked)
    }

    /// What the editor cannot hold and would lose: images and tables.
    public static func holdsMoreThanText(_ html: String) -> Bool {
        html.range(of: #"<(?:img|table|video|svg)[\s>/]"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// A plain text as the editor's HTML: one block a line, its addresses as links, nothing of it read as markup.
    public static func html(fromPlain text: String) -> String {
        guard !text.isEmpty else { return "" }
        return text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").map { line in
            line.isEmpty ? "<div><br></div>" : "<div>" + HTMLText.linked(HTMLText.escape(line)) + "</div>"
        }.joined()
    }

    // MARK: - The tree

    static func sanitize(_ element: XMLElement) {
        for child in element.children ?? [] {
            switch child.kind {
            case .element:
                guard let node = child as? XMLElement else { continue }
                let name = (node.localName ?? node.name ?? "").lowercased()
                if dropped.contains(name) {
                    node.detach()
                    continue
                }
                sanitize(node)
                guard kept.contains(name) else {
                    unwrap(node)
                    continue
                }
                for attribute in node.attributes ?? [] {
                    guard let attributeName = attribute.name else { continue }
                    let value = attribute.stringValue ?? ""
                    let keep = (name == "a" && attributeName.lowercased() == "href" && MailMarkdown.allowed(value.trimmingCharacters(in: .whitespaces)))
                        || (name == "ol" && attributeName.lowercased() == "start" && Int(value) != nil)
                    if !keep { node.removeAttribute(forName: attributeName) }
                }
                // A link without an address worth keeping is only its words.
                if name == "a", node.attribute(forName: "href") == nil { unwrap(node) }
            case .text:
                continue
            default:
                child.detach()
            }
        }
    }

    /// The element goes, its children take its place.
    static func unwrap(_ element: XMLElement) {
        guard let parent = element.parent as? XMLElement else {
            element.detach()
            return
        }
        let index = element.index
        let children = element.children ?? []
        element.setChildren(nil)
        parent.removeChild(at: index)
        for (offset, child) in children.enumerated() { parent.insertChild(child, at: index + offset) }
    }
}
