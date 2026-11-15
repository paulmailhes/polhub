import Foundation
import ImageIO
import Persistence
import UniformTypeIdentifiers

// The projects' logos (15/11): the icon of the client's site, asked of the site itself from the Mac, never of a
// third party; or an image Paul drops. Nothing here runs in the tests' network: the parsing and the images are
// pure, the fetching sits behind `LogoFetching`.

/// The site of a project: what Paul typed, else a domain guessed from its contacts.
public enum ProjectSites {
    /// `https://www.exemple.fr/contact` → `www.exemple.fr`; nothing for what is not a public name.
    public static func domain(_ text: String) -> String? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let scheme = value.range(of: "://") { value = String(value[scheme.upperBound...]) }
        value = String(value.prefix { !"/?#".contains($0) })
        if let at = value.lastIndex(of: "@") { value = String(value[value.index(after: at)...]) }
        if let colon = value.firstIndex(of: ":") { value = String(value[..<colon]) }
        while value.hasSuffix(".") { value.removeLast() }
        return isFetchable(value) ? value : nil
    }

    /// A name of the public Internet: letters, digits, dots and dashes, a dot at least, no address, nothing local.
    public static func isFetchable(_ host: String) -> Bool {
        let host = host.lowercased()
        guard host.contains("."), host.count <= 253, !host.hasPrefix("."), !host.hasPrefix("-"),
              host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }) else { return false }
        // An IP address written as such.
        if host.allSatisfy({ $0.isNumber || $0 == "." }) { return false }
        let local = ["localhost", ".local", ".localhost", ".internal", ".lan", ".home", ".arpa", ".test", ".invalid", ".example"]
        return !local.contains { host == $0 || host.hasSuffix($0) }
    }

    /// One link of a contact to a project, as the base holds it (links Paul removed left out).
    public struct Link: Equatable, Sendable {
        public let email: String
        public let projectID: UUID

        public init(email: String, projectID: UUID) {
            self.email = email
            self.projectID = projectID
        }
    }

    /// The domain of each project's contacts, when it says something: not everyone's mailbox (gmail.com…), not
    /// Paul's own domain, and used by this project's contacts only. The most frequent wins.
    public static func guesses(_ links: [Link], mine: Set<String>) -> [UUID: String] {
        let myDomains = Set(mine.compactMap(PublicMailDomains.domain(of:)))
        var projects: [String: Set<UUID>] = [:]
        var counts: [UUID: [String: Int]] = [:]
        for link in links {
            guard let domain = PublicMailDomains.domain(of: link.email), !PublicMailDomains.all.contains(domain),
                  !myDomains.contains(domain), isFetchable(domain) else { continue }
            projects[domain, default: []].insert(link.projectID)
            counts[link.projectID, default: [:]][domain, default: 0] += 1
        }
        var guesses: [UUID: String] = [:]
        for (project, domains) in counts {
            let own = domains.filter { projects[$0.key]?.count == 1 }
            if let best = own.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }) { guesses[project] = best.key }
        }
        return guesses
    }
}

/// The icons a home page names, the best first: the largest `apple-touch-icon`, then the PNG icons by size,
/// then the others, then `/favicon.ico`. Never SVG, never anything but https.
public enum FaviconParser {
    struct Candidate {
        let url: URL
        let rank: Int
        let size: Int
    }

    public static func candidates(html: String, page: URL) -> [URL] {
        let head = html.prefix(512 * 1024)
        var base = page
        if let tag = head.firstMatch(of: #/(?i)<base\b[^>]*>/#), let href = attributes(String(tag.output))["href"],
           let url = URL(string: href, relativeTo: page)?.absoluteURL {
            base = url
        }
        var found: [Candidate] = []
        for tag in head.matches(of: #/(?i)<link\b[^>]*>/#) {
            let attributes = attributes(String(tag.output))
            let rel = Set((attributes["rel"] ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
            guard rel.contains("icon") || rel.contains("apple-touch-icon") || rel.contains("apple-touch-icon-precomposed"),
                  let href = attributes["href"], let url = resolve(href, base: base) else { continue }
            let type = (attributes["type"] ?? "").lowercased()
            if type.contains("svg") || url.path.lowercased().hasSuffix(".svg") { continue }
            let size = (attributes["sizes"] ?? "").lowercased().split(whereSeparator: \.isWhitespace)
                .compactMap { $0.split(separator: "x").first.flatMap { Int($0) } }.max()
            let touch = rel.contains("apple-touch-icon") || rel.contains("apple-touch-icon-precomposed")
            let png = type.contains("png") || url.path.lowercased().hasSuffix(".png")
            found.append(Candidate(url: url, rank: touch ? 0 : png ? 1 : 2, size: size ?? (touch ? 180 : 0)))
        }
        var urls = found.enumerated().sorted { a, b in
            (a.element.rank, -a.element.size, a.offset) < (b.element.rank, -b.element.size, b.offset)
        }.map(\.element.url)
        if let ico = resolve("/favicon.ico", base: page) { urls.append(ico) }
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }

    /// An address of the page, kept only when it is https on a public name.
    static func resolve(_ href: String, base: URL) -> URL? {
        let href = href.replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !href.isEmpty, !href.lowercased().hasPrefix("data:"),
              let url = URL(string: href, relativeTo: base)?.absoluteURL, url.scheme?.lowercased() == "https",
              let host = url.host(), ProjectSites.isFetchable(host) else { return nil }
        return url
    }

    /// The attributes of one tag, their names in lower case.
    static func attributes(_ tag: String) -> [String: String] {
        var values: [String: String] = [:]
        for match in tag.matches(of: #/([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/#) {
            let name = String(match.output.1).lowercased()
            guard values[name] == nil else { continue }
            values[name] = String(match.output.2 ?? match.output.3 ?? match.output.4 ?? "")
        }
        return values
    }
}

/// What a logo may be, and how it is kept: a PNG of 256 pixels at most.
public enum LogoImage {
    /// The four kinds of images a site's icon may be (no SVG: ImageIO would decode untrusted vectors).
    public static let webTypes: Set<String> = [UTType.png.identifier, UTType.ico.identifier, UTType.jpeg.identifier, UTType.gif.identifier]
    public static let maxWebBytes = 1_048_576
    /// Smaller, initials read better than a blurred icon.
    public static let minimumWebSide = 32

    public static func type(of data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceGetType(source) as String?
    }

    /// A site's icon: one of the four kinds, a megabyte at most, 32 pixels at least.
    public static func png(fromWeb data: Data) -> Data? {
        guard data.count <= maxWebBytes, let type = type(of: data), webTypes.contains(type) else { return nil }
        return png(from: data, minimumSide: minimumWebSide)
    }

    /// An image Paul chose: any kind ImageIO reads.
    public static func png(fromFile data: Data) -> Data? {
        png(from: data, minimumSide: 1)
    }

    /// The largest image file Paul may drop.
    public static let maxFileBytes = 20 * 1_048_576

    /// An image file Paul dropped or chose: read only when it is a file, an image, of 20 MB at most (correctifs,
    /// 15/11). Slow for a large file: never on the main thread.
    public static func png(fromFileAt url: URL) -> Data? {
        guard url.isFileURL else { return nil }
        let readable = url.startAccessingSecurityScopedResource()
        defer { if readable { url.stopAccessingSecurityScopedResource() } }
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey]),
              let size = values.fileSize, size <= maxFileBytes, values.contentType?.conforms(to: .image) == true,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return png(fromFile: data)
    }

    static func png(from data: Data, minimumSide: Int, maxSide: Int = 256) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        func side(_ index: Int) -> Int {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
            let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0, height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
            return min(width, height)
        }
        // An .ico holds several sizes: the largest.
        let index = (0..<count).max { side($0) < side($1) } ?? 0
        guard side(index) >= minimumSide else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

/// Asks a site for its icon; `nil` when it has none Polhub takes.
public protocol LogoFetching: Sendable {
    func logo(for domain: String) async -> Data?
}

/// From the Mac to the client's site, nothing in between: no cookie, no cache, 10 seconds, https only, the home
/// page read up to 512 KB, each icon up to 1 MB.
public struct LiveLogoFetcher: LogoFetching {
    static let pageLimit = 512 * 1024
    /// A browser's name, as any visit: the site learns nothing more of the Mac than its address.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        session = URLSession(configuration: configuration)
    }

    public func logo(for domain: String) async -> Data? {
        guard ProjectSites.isFetchable(domain), let home = URL(string: "https://\(domain)/") else { return nil }
        var candidates: [URL]
        if let page = try? await read(home, limit: Self.pageLimit, cut: true) {
            candidates = FaviconParser.candidates(html: String(decoding: page.data, as: UTF8.self), page: page.url)
        } else {
            candidates = [URL(string: "https://\(domain)/favicon.ico")].compactMap { $0 }
        }
        for candidate in candidates.prefix(5) {
            guard let image = try? await read(candidate, limit: LogoImage.maxWebBytes, cut: false) else { continue }
            if let png = LogoImage.png(fromWeb: image.data) { return png }
        }
        return nil
    }

    /// The body, up to `limit` bytes: cut there (a page, whose head comes first), or refused (an image).
    func read(_ url: URL, limit: Int, cut: Bool) async throws -> (data: Data, url: URL) {
        let (bytes, response) = try await session.bytes(for: URLRequest(url: url), delegate: HTTPSOnly())
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let final = http.url, final.scheme == "https", let host = final.host(), ProjectSites.isFetchable(host) else {
            throw URLError(.badServerResponse)
        }
        if !cut, http.expectedContentLength > Int64(limit) { throw URLError(.dataLengthExceedsMaximum) }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= limit {
                if cut { break }
                throw URLError(.dataLengthExceedsMaximum)
            }
        }
        return (data, final)
    }
}

/// Every redirection stays on https.
final class HTTPSOnly: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard request.url?.scheme == "https", let host = request.url?.host(), ProjectSites.isFetchable(host) else { return nil }
        return request
    }
}
