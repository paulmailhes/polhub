import Foundation
import Persistence

/// LinkedIn's public pages, read as the vault's n8n workflow and its import did (`branding-linkedin.v4`,
/// `branding-linkedin-import.js`), without account nor cookie:
/// - a company page (`https://www.linkedin.com/company/<slug>/`) shows its ten latest posts as
///   `<article data-activity-urn="urn:li:activity:<id>">` blocks (`/posts/` asks for a login);
/// - a post's embed page (`https://www.linkedin.com/embed/feed/update/urn:li:activity:<id>`) gives its whole text,
///   its links and up to five images in high resolution.
public enum LinkedInPublic {
    /// One post of a company page.
    public struct Article: Sendable, Equatable {
        public let urn: String
        public let html: String
    }

    /// What a company page gave.
    public enum PageReading: Sendable, Equatable {
        case posts([Article])
        /// LinkedIn asks for a login (`authwall`, a login form): nothing to read this time.
        case loginWall
        /// A page without any post and without a login wall: LinkedIn changed its page, or the page is empty.
        case noPosts
    }

    /// A post's content: its text, its images (best first, never a logo) and its links (never LinkedIn's chrome).
    public struct Content: Sendable, Equatable {
        public var text: String
        public var images: [String]
        public var links: [String]
    }

    /// A post made into a Polhub item's fields, as the vault's notes were written.
    public struct Post: Sendable, Equatable {
        /// The first line, without hashtags nor links; what precedes « by ».
        public var title: String
        /// What follows « by » on the first line.
        public var studio: String?
        /// The text without the lines of hashtags at its end.
        public var body: String
        public var hashtags: [String]
        /// The links outside LinkedIn first.
        public var links: [String]
    }

    public static func postURL(urn: String) -> String { "https://www.linkedin.com/feed/update/urn:li:activity:\(urn)/" }

    public static func embedURL(urn: String) -> URL { URL(string: "https://www.linkedin.com/embed/feed/update/urn:li:activity:\(urn)")! }

    // MARK: - The company page

    public static func companyPage(_ html: String, url: URL?) -> PageReading {
        if let url, isLoginAddress(url) { return .loginWall }
        var articles: [Article] = []
        var seen = Set<String>()
        for (tag, content) in HTMLScan.elements("article", in: html) {
            guard let urn = HTMLScan.attributes(tag)["data-activity-urn"]?.firstMatch(of: #/urn:li:activity:(\d{6,25})/#)?.output.1,
                  seen.insert(String(urn)).inserted else { continue }
            articles.append(Article(urn: String(urn), html: String(tag) + content + "</article>"))
        }
        if !articles.isEmpty { return .posts(articles) }
        return hasLoginMarkers(html) ? .loginWall : .noPosts
    }

    /// The post as the company page shows it: the fallback when its embed page cannot be read.
    public static func content(of article: Article) -> Content {
        var text = ""
        var links: [String] = []
        for (tag, inner) in HTMLScan.elements("p", in: article.html)
        where HTMLScan.attributes(tag)["data-test-id"] == "main-feed-activity-card__commentary" {
            text = HTMLScan.text(inner)
            for (anchor, _) in HTMLScan.elements("a", in: String(inner)) {
                if let href = HTMLScan.attributes(anchor)["href"], let link = cleanLink(href), !links.contains(link) { links.append(link) }
            }
            break
        }
        return Content(text: text, images: bestImages(imageAddresses(in: article.html, attributes: ["data-delayed-url", "src", "poster", "data-poster-url"])),
                       links: links.filter { !isChrome($0, urn: article.urn) })
    }

    // MARK: - The embed page

    /// `nil` when the page is a login wall or holds no post.
    public static func embed(_ html: String, url: URL?, urn: String) -> Content? {
        if let url, isLoginAddress(url) { return nil }
        var text = ""
        for (tag, inner) in HTMLScan.elements("p", in: html) where HTMLScan.hasClass(HTMLScan.attributes(tag), "attributed-text-segment-list__content") {
            text = HTMLScan.text(inner)
            break
        }
        let images = bestImages(imageAddresses(in: html, attributes: ["data-delayed-url", "src"]))
        if text.isEmpty, images.isEmpty { return nil }
        var links: [String] = []
        for (tag, _) in HTMLScan.elements("a", in: html, withContent: false) {
            guard let href = HTMLScan.attributes(tag)["href"], href.lowercased().hasPrefix("http"),
                  !isChrome(href, urn: urn), let link = cleanLink(href), !links.contains(link) else { continue }
            links.append(link)
        }
        return Content(text: text, images: images, links: links)
    }

    // MARK: - Pieces

    /// The images of LinkedIn's media server named by these attributes, in the page's order, whatever the element.
    static func imageAddresses(in html: String, attributes names: [String]) -> [String] {
        let pattern = "(?:\(names.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")))=\"(https://media\\.licdn\\.com/dms/image/v2/[^\"]+)\""
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        var found: [String] = []
        let text = html as NSString
        for match in expression.matches(in: html, range: NSRange(location: 0, length: text.length)) {
            let value = HTMLScan.decode(text.substring(with: match.range(at: 1)))
            if !found.contains(value) { found.append(value) }
        }
        return found
    }

    /// One address per image, the best variant of each (`image-high-res` › `shrink_2048` › `shrink_1280` ›
    /// `shrink_800`), in the order of their first appearance. Only a post's own variants pass
    /// (`feedshare`, `thumbnail`, `poster`, `article-cover`): never the page's logo nor an avatar.
    public static func bestImages(_ urls: [String]) -> [String] {
        func rank(_ variant: String) -> Int {
            if variant.contains("image-high-res") { return 4 }
            if variant.contains("shrink_2048") { return 3 }
            if variant.contains("shrink_1280") { return 2 }
            if variant.contains("shrink_800") { return 1 }
            return 0
        }
        var best: [String: (url: String, rank: Int, order: Int)] = [:]
        for url in urls {
            guard let match = url.firstMatch(of: #/media\.licdn\.com/dms/image/v2/([^/?"]+)/([^/?"]+)//#) else { continue }
            let id = String(match.output.1), variant = String(match.output.2)
            let lower = variant.lowercased()
            guard !["logo", "profile", "avatar", "ghost"].contains(where: lower.contains),
                  ["feedshare", "thumbnail", "poster", "article-cover"].contains(where: lower.contains) else { continue }
            if let previous = best[id] {
                if rank(variant) > previous.rank { best[id] = (url, rank(variant), previous.order) }
            } else {
                best[id] = (url, rank(variant), best.count)
            }
        }
        return best.values.sorted { $0.order < $1.order }.map(\.url)
    }

    /// Whether a link belongs to LinkedIn's interface rather than to the post (`estChrome`): its static files, the
    /// feed, the search, the legal pages, the login, the post itself. A link outside LinkedIn is the post's.
    public static func isChrome(_ link: String, urn: String) -> Bool {
        let lower = link.lowercased()
        if lower.firstMatch(of: #/^https?://([a-z0-9-]+\.)*licdn\.com//#) != nil { return true }
        guard let match = lower.firstMatch(of: #/^https?://([a-z0-9-]+\.)*linkedin\.com(/[^?#]*)?/#) else { return false }
        let path = String(match.output.2 ?? "/")
        if !urn.isEmpty, path.contains("urn:li:activity:\(urn)") { return true }
        if path == "/" || path.isEmpty { return true }
        return path.firstMatch(of: #/^/(feed|search|mypreferences|legal|help|signup|login|uas|embed|checkpoint|pulse|posts|authwall|company/[^/]+/(posts|about))(/|$)/#) != nil
    }

    /// A link kept as the vault kept it (`nettoieLien`): http(s) only, never a hashtag, a login or a sign-up, and a
    /// LinkedIn link without its `?trk=`.
    public static func cleanLink(_ href: String) -> String? {
        var link = HTMLScan.decode(href).trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = link.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return nil }
        if lower.firstMatch(of: #/linkedin\.com/(signup|login|uas|feed/hashtag|help)\b/#) != nil { return nil }
        if lower.contains("session_redirect=") { return nil }
        if lower.firstMatch(of: #/^https?://([a-z0-9-]+\.)*linkedin\.com//#) != nil {
            return link.replacing(#/[?#].*$/#, with: "")
        }
        // LinkedIn's tracking (`trk`) added to the post's own links.
        if lower.contains("trk"), var components = URLComponents(string: link), let items = components.queryItems {
            let kept = items.filter { !["trk", "trkinfo"].contains($0.name.lowercased()) }
            if kept.count != items.count {
                components.queryItems = kept.isEmpty ? nil : kept
                link = components.string ?? link
            }
        }
        return link
    }

    /// A post's fields from its text, as the vault derived them (`derive`, « Extrait les publications »).
    public static func post(text raw: String, links: [String], urn: String) -> Post {
        var text = raw.replacing(#/(?i)\bhashtag\s*#/#, with: "#").replacingOccurrences(of: "\r", with: "")
        text = droppingSeeMore(text)
        // The hashtags, then the lines made only of them taken off the end.
        var hashtags: [String] = []
        for match in text.matches(of: #/(?:^|[\s(])#([\p{L}\p{N}_]+)/#) {
            let tag = match.output.1.lowercased()
            if tag.allSatisfy(\.isNumber) || hashtags.contains(tag) { continue }
            hashtags.append(tag)
        }
        var lines = text.components(separatedBy: "\n")
        while let last = lines.last, isHashtagsOnly(last) || last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // The title: the first line without hashtags nor links; the studio after « by ».
        let first = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        var line = first.replacing(#/(?:^|\s)#[\p{L}\p{N}_]+/#, with: "").replacing(#/https?://\S+/#, with: "")
        line = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        line = line.replacing(#/[\s:.\-–—|]+$/#, with: "")
        var title = line
        var studio: String?
        if let by = line.firstMatch(of: #/(?i)^(.*?)\s+by\s+(.+)$/#), !by.output.1.trimmingCharacters(in: .whitespaces).isEmpty {
            title = by.output.1.trimmingCharacters(in: .whitespaces)
            studio = by.output.2.trimmingCharacters(in: .whitespaces)
        }
        if title.isEmpty { title = "Publication \(urn)" }
        let outside = links.filter { $0.lowercased().firstMatch(of: #/^https?://([a-z0-9-]+\.)*linkedin\.com//#) == nil }
        let inside = links.filter { !outside.contains($0) }
        return Post(title: title, studio: studio, body: body, hashtags: hashtags, links: InspirationMerge.union(outside, inside))
    }

    /// A line made only of hashtags (`#marque #identité`, glued or spaced), read word by word: the pattern it
    /// replaces tried every way of sharing the spaces between hashtags, hours for a line of 20 that ends with a full
    /// stop, and a meeting could not stop it (review of 16/11).
    static func isHashtagsOnly(_ line: String) -> Bool {
        let words = line.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return false }
        return words.allSatisfy { word in
            guard word.first == "#" else { return false }
            let pieces = word.dropFirst().split(separator: "#", omittingEmptySubsequences: false)
            return pieces.allSatisfy { !$0.isEmpty && $0.unicodeScalars.allSatisfy(isHashtagScalar) }
        }
    }

    /// `[\p{L}\p{N}_]`, and the accents of a decomposed letter.
    private static func isHashtagScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber, .nonspacingMark:
            true
        default:
            scalar == "_"
        }
    }

    /// The text without the « … voir plus » LinkedIn adds when it cuts a post (« see more », « afficher plus », any
    /// case), and without the spaces around it; read from the end, never with a pattern (a long run of spaces made
    /// the one it replaces cubic).
    static func droppingSeeMore(_ text: String) -> String {
        var rest = Substring(text)
        func trimEnd() {
            while let last = rest.last, last.isWhitespace { rest.removeLast() }
        }
        trimEnd()
        for phrase in ["voir plus", "see more", "afficher plus"] where rest.count >= phrase.count && rest.suffix(phrase.count).lowercased() == phrase {
            rest.removeLast(phrase.count)
            trimEnd()
            if rest.last == "…" {
                rest.removeLast()
                trimEnd()
            }
            break
        }
        return String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// LinkedIn's login addresses: where a page refused to a visitor redirects.
    static func isLoginAddress(_ url: URL) -> Bool {
        let path = url.path().lowercased()
        return ["/authwall", "/login", "/uas/", "/checkpoint/", "/signup"].contains { path.hasPrefix($0) || path.contains($0 + "/") }
            || path == "/uas" || path.hasPrefix("/uas/login")
    }

    /// A page that asks for a login.
    static func hasLoginMarkers(_ html: String) -> Bool {
        html.range(of: #"/uas/login|authwall|/checkpoint/"#, options: [.regularExpression, .caseInsensitive]) != nil
            || html.range(of: #"<form[^>]+login"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
