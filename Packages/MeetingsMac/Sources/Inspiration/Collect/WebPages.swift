import Foundation

/// Awwwards' home page, as n8n read it (`awwwards-sotd-obsidian.v5`): the « Visit Sotd. » link of the bottom bar
/// (the site of the day), the thumbnail of the `c-sotd-new` block, and the site's page on Awwwards.
public struct AwwwardsHome: Sendable, Equatable {
    public static let address = URL(string: "https://www.awwwards.com/")!

    /// The site of the day, as Awwwards links it.
    public var site: URL
    /// Awwwards' capture of it: the image when the site's own is missing or wrong.
    public var thumbnail: URL?
    /// `https://www.awwwards.com/sites/<slug>`.
    public var page: URL?

    public init(site: URL, thumbnail: URL? = nil, page: URL? = nil) {
        self.site = site
        self.thumbnail = thumbnail
        self.page = page
    }

    /// `nil` when the page has no « Visit Sotd. » link to another site (Awwwards changed its page).
    public static func parse(_ html: String, base: URL = address) -> AwwwardsHome? {
        var site: URL?
        for (tag, content) in HTMLScan.elements("a", in: html) {
            guard content.range(of: "sotd", options: .caseInsensitive) != nil,
                  HTMLScan.text(content).range(of: #"^Visit\s+Sotd\.?$"#, options: [.regularExpression, .caseInsensitive]) != nil,
                  let href = HTMLScan.attributes(tag)["href"],
                  let url = HTMLScan.resolve(href.replacing(#/#.*$/#, with: ""), base: base),
                  let host = url.host()?.lowercased(), !host.hasSuffix("awwwards.com") else { continue }
            site = url
            break
        }
        guard let site else { return nil }
        var home = AwwwardsHome(site: site)
        // The block of the site of the day: its thumbnail and its page.
        if let start = html.range(of: #"class="c-sotd-new[\s"]"#, options: .regularExpression) {
            let block = String(html[start.lowerBound...].prefix(20_000))
            for tag in HTMLScan.openingTags("img", in: block) {
                let attributes = HTMLScan.attributes(tag)
                guard HTMLScan.hasClass(attributes, "c-sotd-new__img"),
                      let source = attributes["src"] ?? attributes["data-src"] ?? attributes["srcset"]?.split(separator: " ").first.map(String.init),
                      let url = HTMLScan.resolve(source, base: base) else { continue }
                home.thumbnail = url
                break
            }
            if home.thumbnail == nil,
               let match = block.firstMatch(of: #/https://assets\.awwwards\.com/awards/submissions/[^"'\s)]+/#) {
                home.thumbnail = URL(string: HTMLScan.decode(match.output))
            }
            for (tag, _) in HTMLScan.elements("a", in: block) {
                let attributes = HTMLScan.attributes(tag)
                guard HTMLScan.hasClass(attributes, "item-link"), let href = attributes["href"], href.hasPrefix("/sites/") else { continue }
                home.page = URL(string: href, relativeTo: base)?.absoluteURL
                break
            }
        }
        return home
    }
}

/// A page's OpenGraph tags, with the Twitter ones and `<title>` behind them, as n8n read them.
public struct OpenGraph: Sendable, Equatable {
    public var title: String?
    public var description: String?
    /// As written: maybe relative, maybe `localhost`.
    public var image: String?

    public init(title: String? = nil, description: String? = nil, image: String? = nil) {
        self.title = title
        self.description = description
        self.image = image
    }

    public static func parse(_ html: String) -> OpenGraph {
        // The head is enough when it closes; some sites put their tags lower.
        let head = html.range(of: "</head>", options: .caseInsensitive).map { String(html[..<$0.upperBound]) } ?? html
        var meta: [String: String] = [:]
        for tag in HTMLScan.openingTags("meta", in: head) {
            let attributes = HTMLScan.attributes(tag)
            guard let name = (attributes["property"] ?? attributes["name"])?.lowercased(),
                  let content = attributes["content"]?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty,
                  meta[name] == nil else { continue }
            meta[name] = content
        }
        func first(_ names: String...) -> String? {
            names.lazy.compactMap { meta[$0] }.map(HTMLScan.line).first { !$0.isEmpty }
        }
        var graph = OpenGraph()
        graph.title = first("og:title", "twitter:title")
        if graph.title == nil, let title = HTMLScan.elements("title", in: head).first.map({ HTMLScan.line(String($0.content)) }), !title.isEmpty {
            graph.title = String(title.prefix(200))
        }
        graph.description = first("og:description", "twitter:description", "description")
        graph.image = ["og:image", "og:image:secure_url", "og:image:url", "twitter:image", "twitter:image:src"].lazy.compactMap { meta[$0] }.first
        return graph
    }

    /// The image's address, made absolute on the page; `nil` unless it is on the public web (never
    /// `localhost:3000`, a private address, `data:`).
    public func imageURL(base: URL) -> URL? {
        guard let image, let url = HTMLScan.resolve(image, base: base), PublicWeb.isAllowed(url) else { return nil }
        return url
    }
}
