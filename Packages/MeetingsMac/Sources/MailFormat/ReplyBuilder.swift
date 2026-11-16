import Foundation
import Persistence

/// What a reply or a forward needs of the message it answers.
public struct ReplySource: Sendable, Equatable {
    public var from: MailAddress?
    public var replyTo: [MailAddress]
    public var to: [MailAddress]
    public var cc: [MailAddress]
    public var date: Date
    public var subject: String
    public var messageID: String?
    public var references: String?
    /// Its body, as kept: HTML, or text.
    public var body: String
    public var isHTML: Bool

    public init(from: MailAddress?, replyTo: [MailAddress] = [], to: [MailAddress], cc: [MailAddress] = [], date: Date, subject: String,
                messageID: String?, references: String? = nil, body: String, isHTML: Bool) {
        self.from = from
        self.replyTo = replyTo
        self.to = to
        self.cc = cc
        self.date = date
        self.subject = subject
        self.messageID = messageID
        self.references = references
        self.body = body
        self.isHTML = isHTML
    }
}

/// Replies and forwards written the way Gmail writes them (14/11): who receives them, their subject, the thread
/// they stay in, and the message quoted below Paul's text.
public enum ReplyBuilder {
    static let locale = Locale(identifier: "fr_FR")

    /// Reply: the one who wrote (or the address he asked replies at). Reply to all: everyone else in copy. A
    /// message Paul wrote himself is answered to its recipients. Paul's own addresses never receive it.
    public static func recipients(_ mode: MailDraftRow.Mode, source: ReplySource, mine: Set<String>) -> (to: [MailAddress], cc: [MailAddress]) {
        guard mode == .reply || mode == .replyAll else { return ([], []) }
        let fromMe = source.from.map { mine.contains($0.email) } ?? false
        var to = fromMe ? source.to : (source.replyTo.isEmpty ? source.from.map { [$0] } ?? [] : source.replyTo)
        to = unique(to.filter { !mine.contains($0.email) })
        guard mode == .replyAll else { return (to, []) }
        let taken = Set(to.map(\.email))
        let cc = unique((fromMe ? source.cc : source.to + source.cc).filter { !mine.contains($0.email) && !taken.contains($0.email) })
        return (to, cc)
    }

    static func unique(_ addresses: [MailAddress]) -> [MailAddress] {
        var seen: Set<String> = [], result: [MailAddress] = []
        for address in addresses where seen.insert(address.email).inserted { result.append(address) }
        return result
    }

    /// « Re: » or « Fwd: », never doubled.
    public static func subject(_ mode: MailDraftRow.Mode, original: String) -> String {
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .new: return trimmed
        case .reply, .replyAll:
            return trimmed.range(of: #"^(re|ré|réf|aw|sv)\s*:"#, options: [.regularExpression, .caseInsensitive]) != nil ? trimmed : "Re: \(trimmed)"
        case .forward:
            return trimmed.range(of: #"^(fwd?|tr)\s*:"#, options: [.regularExpression, .caseInsensitive]) != nil ? trimmed : "Fwd: \(trimmed)"
        }
    }

    /// The headers that keep a reply in its thread, at Gmail and at the other end.
    public static func threading(_ source: ReplySource) -> (inReplyTo: String?, references: String?) {
        guard let id = source.messageID else { return (nil, source.references) }
        let references = [source.references, id].compactMap { $0 }.joined(separator: " ")
        return (id, references)
    }

    static func display(_ address: MailAddress) -> String {
        address.name.map { "\($0) <\(address.email)>" } ?? address.email
    }

    /// « Le ven. 13 nov. 2026 à 16:45, Camille <camille@exemple.fr> a écrit : »
    static func attribution(_ source: ReplySource) -> String {
        let date = source.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().locale(locale))
        let hour = source.date.formatted(.dateTime.hour().minute().locale(locale))
        return "Le \(date) à \(hour), \(source.from.map(display) ?? "?") a écrit :"
    }

    static func forwardHeader(_ source: ReplySource) -> [String] {
        let date = source.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().hour().minute().locale(locale))
        var lines = ["---------- Message transféré ---------", "De : \(source.from.map(display) ?? "?")", "Date : \(date)", "Objet : \(source.subject)"]
        if !source.to.isEmpty { lines.append("À : \(source.to.map(display).joined(separator: ", "))") }
        if !source.cc.isEmpty { lines.append("Cc : \(source.cc.map(display).joined(separator: ", "))") }
        return lines
    }

    /// The quoted message in Gmail's own form, which every client folds.
    public static func quoteHTML(_ mode: MailDraftRow.Mode, source: ReplySource) -> String? {
        let original = source.isHTML ? HTMLText.quotable(source.body) : "<div dir=\"ltr\">\(HTMLText.escape(source.body).replacingOccurrences(of: "\n", with: "<br>"))</div>"
        switch mode {
        case .new: return nil
        case .reply, .replyAll:
            return "<div class=\"gmail_quote\"><div dir=\"ltr\" class=\"gmail_attr\">\(HTMLText.escape(attribution(source)))<br></div>"
                + "<blockquote class=\"gmail_quote\" style=\"margin:0px 0px 0px 0.8ex;border-left:1px solid rgb(204,204,204);padding-left:1ex\">"
                + original + "</blockquote></div>"
        case .forward:
            return "<div class=\"gmail_quote\"><div dir=\"ltr\" class=\"gmail_attr\">"
                + forwardHeader(source).map(HTMLText.escape).joined(separator: "<br>") + "<br></div><br><br>" + original + "</div>"
        }
    }

    public static func quoteText(_ mode: MailDraftRow.Mode, source: ReplySource) -> String? {
        let original = source.isHTML ? HTMLText.plain(source.body) : source.body
        switch mode {
        case .new: return nil
        case .reply, .replyAll:
            return attribution(source) + "\n\n" + original.components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> \($0)" }.joined(separator: "\n")
        case .forward:
            return forwardHeader(source).joined(separator: "\n") + "\n\n" + original
        }
    }

    /// The HTML that leaves: Paul's text, his signature, then the quoted message. An agent's formatted text (16/11)
    /// takes the place of the plain one's, the app having made it from its markdown (`MailMarkdown`).
    public static func html(body: String, bodyHTML: String? = nil, signature: String?, quote: String?) -> String {
        var html = "<div dir=\"ltr\">\(bodyHTML ?? HTMLText.linked(HTMLText.escape(body)).replacingOccurrences(of: "\n", with: "<br>"))</div>"
        if let signature, !signature.isEmpty {
            html += "<br><div dir=\"ltr\" class=\"gmail_signature\">\(signature)</div>"
        }
        if let quote { html += "<br>" + quote }
        return html
    }

    public static func text(body: String, signature: String?, quote: String?) -> String {
        var text = body
        if let signature, !signature.isEmpty { text += "\n\n-- \n" + HTMLText.plain(signature) }
        if let quote { text += "\n\n" + quote }
        return text
    }
}

/// HTML to text and back, for what a mail carries as its text part and what Paul edits (14/11).
public enum HTMLText {
    /// A sender's HTML, ready to quote in a mail Paul sends (review of 14/11): only what its body shows, its
    /// tags balanced, without styles, scripts, forms, frames or `on…` handlers. Nothing in it can close the
    /// quote and pass for Paul's words. Parsed by Foundation, offline.
    public static func quotable(_ html: String) -> String {
        let options: XMLNode.Options = [.documentTidyHTML, .nodeLoadExternalEntitiesNever]
        // From the text, not its bytes: read as bytes, tidy takes UTF-8 for Latin-1 and drops the accents.
        guard let document = try? XMLDocument(xmlString: html, options: options) else {
            return "<div dir=\"ltr\">" + escape(plain(html)).replacingOccurrences(of: "\n", with: "<br>") + "</div>"
        }
        let banned = ["script", "style", "meta", "base", "link", "form", "input", "button", "select", "textarea", "iframe", "frame",
                      "frameset", "object", "embed", "applet", "title", "head", "svg", "math"]
        for name in banned {
            for node in (try? document.nodes(forXPath: "//*[local-name()='\(name)']")) ?? [] { node.detach() }
        }
        for case let element as XMLElement in (try? document.nodes(forXPath: "//*")) ?? [] {
            for attribute in element.attributes ?? [] {
                guard let name = attribute.name?.lowercased() else { continue }
                let value = attribute.stringValue?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
                if name.hasPrefix("on") || value.hasPrefix("javascript:") || name == "srcdoc" || name == "formaction" {
                    element.removeAttribute(forName: attribute.name!)
                }
            }
        }
        let body = (try? document.nodes(forXPath: "//*[local-name()='body']"))?.first ?? document.rootElement()
        let inner = (body?.children ?? []).map { $0.xmlString }.joined()
        // XML writes `<br></br>`, which an HTML reader takes for two lines: void elements lose their end tag.
        // Tidy also puts a line break before each closing tag.
        return inner.replacingOccurrences(of: #"</(br|img|hr|wbr|col|area|source|track)>"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\n(?=</)"#, with: "", options: .regularExpression)
    }

    /// The words a reader sees, for an agent (step « Agents »): what the mail hides and the invisible
    /// characters are taken out, as best as can be. A hidden text is the usual way to slip an order to an
    /// assistant. Read as a tree (review of 14/11): a hidden element goes with everything inside it, whether
    /// hidden by `hidden`, by its own style (entities decoded) or by a class or id its style sheets hide.
    public static func visible(_ html: String) -> String {
        // Tidy does not know `<template>`: it would keep what is inside.
        let source = html.replacingOccurrences(of: #"(?is)<template\b.*?</template\s*>"#, with: "", options: .regularExpression)
        guard let document = try? XMLDocument(xmlString: source, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]) else {
            return clean(plain(source))
        }
        func nodes(_ path: String) -> [XMLNode] { (try? document.nodes(forXPath: path)) ?? [] }
        var classes: Set<String> = [], ids: Set<String> = []
        let rule = try? NSRegularExpression(pattern: #"([^{}]+)\{([^{}]*)\}"#)
        for sheet in nodes("//*[local-name()='style']") {
            let css = sheet.stringValue ?? ""
            for match in rule?.matches(in: css, range: NSRange(css.startIndex..., in: css)) ?? [] {
                guard let selectors = Range(match.range(at: 1), in: css), let body = Range(match.range(at: 2), in: css), hides(String(css[body])) else { continue }
                for selector in css[selectors].split(separator: ",") {
                    let last = selector.split(whereSeparator: { $0 == " " || $0 == ">" || $0 == "+" || $0 == "~" }).last.map(String.init) ?? ""
                    for piece in last.split(separator: ".", omittingEmptySubsequences: false).dropFirst() {
                        classes.insert(String(piece.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }))
                    }
                    if let hash = last.firstIndex(of: "#") {
                        ids.insert(String(last[last.index(after: hash)...].prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }))
                    }
                }
            }
        }
        var gone: [XMLNode] = []
        for name in ["script", "style", "head", "title", "template", "noscript", "iframe", "object"] {
            gone += nodes("//*[local-name()='\(name)']")
        }
        for case let element as XMLElement in nodes("//*") {
            let style = element.attribute(forName: "style")?.stringValue ?? ""
            let own = (element.attribute(forName: "class")?.stringValue ?? "").split(separator: " ").map(String.init)
            if element.attribute(forName: "hidden") != nil || hides(style) || own.contains(where: classes.contains)
                || (element.attribute(forName: "id")?.stringValue).map(ids.contains) == true {
                gone.append(element)
            }
        }
        for node in gone { node.detach() }
        let body = nodes("//*[local-name()='body']").first ?? document.rootElement()
        // Tidy puts a line break before each closing tag.
        let markup = (body?.children ?? []).map(\.xmlString).joined().replacingOccurrences(of: #"\n(?=</)"#, with: "", options: .regularExpression)
        return clean(plain(markup))
    }

    /// A style that keeps its element out of sight: none, hidden, transparent, no height, a tiny font, off
    /// the page, Outlook's own hiding.
    static func hides(_ style: String) -> Bool {
        let css = style.lowercased().filter { !$0.isWhitespace }
        func has(_ pattern: String) -> Bool { css.range(of: pattern, options: .regularExpression) != nil }
        if has(#"(^|;)display:none"#) || has(#"(^|;)visibility:(hidden|collapse)"#) || has(#"(^|;)opacity:0*(\.0+)?(;|!|$)"#)
            || has(#"mso-hide:all"#) || has(#"(^|;)(text-indent|left|top|margin-left):-[0-9]{3,}"#) {
            return true
        }
        if has(#"(^|;)(max-)?(height|width):0(px|pt|em|rem|%)?(;|!|$)"#), has(#"overflow:hidden"#) { return true }
        if let range = css.range(of: #"(^|;)font-size:[0-9.]+(px|pt|em|rem|%)?"#, options: .regularExpression) {
            let value = css[range].drop { $0 != ":" }.dropFirst()
            let number = Double(value.prefix { $0.isNumber || $0 == "." }) ?? 1
            let unit = value.drop { $0.isNumber || $0 == "." }
            switch unit {
            case "em", "rem": return number < 0.2
            case "%": return number < 20
            default: return number < 2
            }
        }
        return false
    }

    /// No invisible character: zero widths, direction marks, tags, private use.
    public static func clean(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .format, .privateUse, .unassigned, .surrogate: return false
            case .control: return scalar == "\n" || scalar == "\t"
            default: return true
            }
        }))
    }

    /// Gmail's draft has formatting a plain text would lose: links, images, lists, emphasis, tables.
    public static func isFormatted(_ html: String) -> Bool {
        html.range(of: #"<(?:a\s[^>]*href|(?:img|table|ul|ol|b|strong|i|em|u|font|h[1-6]|blockquote)[\s>/])"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    public static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// The addresses of an escaped text become links.
    public static func linked(_ escaped: String) -> String {
        escaped.replacingOccurrences(of: #"https?://[^\s<>"]+[^\s<>".,;:!?)]"#, with: "<a href=\"$0\">$0</a>", options: .regularExpression)
    }

    /// The words of an HTML page, its paragraphs kept: no style, no script, no tags; entities read.
    public static func plain(_ html: String) -> String {
        var text = html
        for pattern in [#"(?is)<(style|script|head|title)[^>]*>.*?</\1>"#, #"(?s)<!--.*?-->"#] {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)</(p|div|tr|li|h[1-6]|blockquote|table)>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)<li[^>]*>"#, with: "• ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        text = entities(text)
        text = text.replacingOccurrences(of: "\u{a0}", with: " ")
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        var result: [String] = []
        for line in lines where !(line.isEmpty && (result.last?.isEmpty ?? true)) { result.append(line) }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func entities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        let named = ["&nbsp;": "\u{a0}", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&eacute;": "é", "&egrave;": "è",
                     "&agrave;": "à", "&ccedil;": "ç", "&ecirc;": "ê", "&ocirc;": "ô", "&euro;": "€", "&rsquo;": "’", "&laquo;": "«",
                     "&raquo;": "»", "&hellip;": "…", "&mdash;": "—", "&ndash;": "–"]
        for (entity, character) in named { result = result.replacingOccurrences(of: entity, with: character) }
        if let pattern = try? NSRegularExpression(pattern: #"&#(x?)([0-9a-fA-F]+);"#) {
            for match in pattern.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
                guard let whole = Range(match.range, in: result), let hex = Range(match.range(at: 1), in: result),
                      let digits = Range(match.range(at: 2), in: result),
                      let value = UInt32(result[digits], radix: result[hex].isEmpty ? 10 : 16), let scalar = UnicodeScalar(value) else { continue }
                result.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }
}
