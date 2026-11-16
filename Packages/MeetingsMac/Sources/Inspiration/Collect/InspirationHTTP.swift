import Foundation

// What the collection asks of the web (16/11): one GET at a time, from the Mac to the site, as a browser without
// cookie nor account would. Everything that goes on the network sits behind `InspirationHTTP`, so that the tests
// never touch it.

/// One page or one image to read.
public struct InspirationRequest: Sendable {
    public enum Purpose: Sendable, Equatable {
        /// An HTML page: cut at `limit` (its head comes first).
        case page
        /// An image: refused beyond `limit`.
        case image
    }

    public var url: URL
    public var purpose: Purpose
    /// The most bytes read.
    public var limit: Int
    /// An image already complete enough before its end (the first frame of a GIF): the download stops there.
    public var isEnough: (@Sendable (Data) -> Bool)?

    public init(url: URL, purpose: Purpose, limit: Int, isEnough: (@Sendable (Data) -> Bool)? = nil) {
        self.url = url
        self.purpose = purpose
        self.limit = limit
        self.isEnough = isEnough
    }
}

/// What came back, whatever the status: a 999 or a 429 from LinkedIn is an answer, not a failure.
public struct InspirationResponse: Sendable, Equatable {
    /// The address finally read, after the redirections (LinkedIn's login wall shows there).
    public var url: URL
    public var status: Int
    /// `image/gif`, `text/html`: lowercase, without its parameters.
    public var contentType: String?
    public var body: Data
    /// Cut at the limit, or stopped once enough was read.
    public var truncated: Bool

    public init(url: URL, status: Int, contentType: String? = nil, body: Data, truncated: Bool = false) {
        self.url = url
        self.status = status
        self.contentType = contentType
        self.body = body
        self.truncated = truncated
    }

    public var isSuccess: Bool { (200..<300).contains(status) }

    /// The body as text (UTF-8, else Latin-1: a page always reads).
    public var text: String {
        String(data: body, encoding: .utf8) ?? String(decoding: body, as: UTF8.self)
    }
}

/// Why nothing came back.
public enum InspirationFetchError: Error, Equatable, Sendable, CustomStringConvertible {
    /// Not http(s), or a local or private address (`file:`, `localhost`, `192.168.…`).
    case refusedAddress
    /// An image over the limit (30 MB).
    case tooLarge

    public var description: String {
        switch self {
        case .refusedAddress: "adresse refusée (ni publique ni web)"
        case .tooLarge: "image trop lourde"
        }
    }
}

/// One GET. Any HTTP status comes back as a response; a network failure, a refused address or an image over its
/// limit throws.
public protocol InspirationHTTP: Sendable {
    func get(_ request: InspirationRequest) async throws -> InspirationResponse
}

/// The addresses the collection may read: the public web only.
public enum PublicWeb {
    /// http(s), on a public name or address: no `file:`, no `localhost` nor `.local`, no private, loopback,
    /// link-local or shared address (`10.`, `127.`, `169.254.`, `172.16–31.`, `192.168.`, `100.64–127.`), no IPv6
    /// written as such, no name without a dot, no user nor password in the address.
    public static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.user == nil, url.password == nil,
              var host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return false }
        while host.hasSuffix(".") { host.removeLast() }
        guard host.contains("."), !host.contains(":"), !host.hasPrefix("["), !host.contains("%") else { return false }
        let local = ["localhost", ".localhost", ".local", ".internal", ".lan", ".home.arpa", ".intranet", ".corp"]
        if local.contains(where: { host == $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) || host.hasSuffix($0) }) { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.contains(where: \.isEmpty) else { return false }
        // An address written as numbers.
        if labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) {
            let parts = labels.compactMap { Int($0) }
            guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
            return isPublicIPv4(parts)
        }
        // `0x7f.1` and its kind: numbers in disguise.
        if labels.allSatisfy({ $0.allSatisfy(\.isNumber) || $0.hasPrefix("0x") }) { return false }
        return true
    }

    static func isPublicIPv4(_ parts: [Int]) -> Bool {
        let (a, b) = (parts[0], parts[1])
        switch a {
        case 0, 10, 127: return false
        case 100 where (64...127).contains(b): return false
        case 169 where b == 254: return false
        case 172 where (16...31).contains(b): return false
        case 192 where b == 168: return false
        case 192 where b == 0 && parts[2] == 0: return false
        case 198 where b == 18 || b == 19: return false
        case 224...255: return false
        default: return true
        }
    }

    /// The https address of an http one: the app only reads https (macOS's App Transport Security), and the sites
    /// of today answer it.
    public static func secure(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.scheme = "https"
        if components.port == 80 { components.port = nil }
        return components.url ?? url
    }
}

/// From the Mac to the site, nothing in between: an ephemeral session, no cookie, no cache, no stored password,
/// a browser's name, 20 seconds without an answer, every redirection kept on the public web and on https. A page
/// is read up to its limit, an image refused beyond it.
public struct LiveInspirationHTTP: InspirationHTTP {
    /// A browser's name, as n8n sent it: LinkedIn serves its public pages to browsers only.
    public static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
    let session: URLSession

    public init(timeout: TimeInterval = 20) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = timeout
        // A 30 MB image on a slow line: the whole download may take longer than one silence.
        configuration.timeoutIntervalForResource = max(timeout, 120)
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.httpAdditionalHeaders = ["User-Agent": Self.userAgent, "Accept-Language": "fr-FR,fr;q=0.9,en;q=0.8"]
        session = URLSession(configuration: configuration)
    }

    /// The same session, its loading handed to `protocolClasses` (the tests' recorded answers: no network).
    init(timeout: TimeInterval = 20, protocolClasses: [AnyClass]) {
        let live = LiveInspirationHTTP(timeout: timeout)
        let configuration = live.session.configuration
        configuration.protocolClasses = protocolClasses
        session = URLSession(configuration: configuration)
    }

    public func get(_ request: InspirationRequest) async throws -> InspirationResponse {
        guard PublicWeb.isAllowed(request.url) else { throw InspirationFetchError.refusedAddress }
        var urlRequest = URLRequest(url: PublicWeb.secure(request.url))
        urlRequest.httpShouldHandleCookies = false
        switch request.purpose {
        case .page: urlRequest.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        case .image: urlRequest.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        }
        let loader = BoundedLoader(limit: request.limit, cut: request.purpose == .page, isEnough: request.isEnough)
        return try await loader.load(urlRequest, in: session)
    }
}

/// One download that stops at its limit (cut or refused) or once enough was read.
final class BoundedLoader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let limit: Int
    private let cut: Bool
    private let isEnough: (@Sendable (Data) -> Bool)?
    private let lock = NSLock()
    private var data = Data()
    private var response: HTTPURLResponse?
    private var continuation: CheckedContinuation<InspirationResponse, any Error>?
    private var finished = false

    init(limit: Int, cut: Bool, isEnough: (@Sendable (Data) -> Bool)?) {
        self.limit = limit
        self.cut = cut
        self.isEnough = isEnough
    }

    func load(_ request: URLRequest, in session: URLSession) async throws -> InspirationResponse {
        let task = session.dataTask(with: request)
        task.delegate = self
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock { self.continuation = continuation }
                if Task.isCancelled {
                    finish(.failure(CancellationError()))
                    task.cancel()
                } else {
                    task.resume()
                }
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            finish(.failure(URLError(.badServerResponse)))
            completionHandler(.cancel)
            return
        }
        lock.withLock { self.response = http }
        if !cut, (200..<300).contains(http.statusCode), http.expectedContentLength > Int64(limit) {
            finish(.failure(InspirationFetchError.tooLarge))
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        enum Next { case more, stop(truncated: Bool), tooLarge }
        let next: Next = lock.withLock {
            data.append(chunk)
            if data.count > limit {
                if cut {
                    data = data.prefix(limit)
                    return .stop(truncated: true)
                }
                return .tooLarge
            }
            if let isEnough, isEnough(data) { return .stop(truncated: true) }
            return .more
        }
        switch next {
        case .more:
            return
        case .stop(let truncated):
            finish(.success(makeResponse(truncated: truncated)))
            dataTask.cancel()
        case .tooLarge:
            finish(.failure(InspirationFetchError.tooLarge))
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            finish(.failure(error))
        } else {
            finish(.success(makeResponse(truncated: false)))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let url = request.url, PublicWeb.isAllowed(url) else {
            completionHandler(nil)
            return
        }
        var secured = request
        secured.url = PublicWeb.secure(url)
        completionHandler(secured)
    }

    private func makeResponse(truncated: Bool) -> InspirationResponse {
        lock.withLock {
            let type = (response?.value(forHTTPHeaderField: "Content-Type") ?? response?.mimeType)?
                .split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            return InspirationResponse(url: response?.url ?? URL(string: "about:blank")!, status: response?.statusCode ?? 0,
                                       contentType: type, body: data, truncated: truncated)
        }
    }

    private func finish(_ result: Result<InspirationResponse, any Error>) {
        let continuation: CheckedContinuation<InspirationResponse, any Error>? = lock.withLock {
            guard !finished, let waiting = self.continuation else { return nil }
            finished = true
            self.continuation = nil
            return waiting
        }
        continuation?.resume(with: result)
    }
}
