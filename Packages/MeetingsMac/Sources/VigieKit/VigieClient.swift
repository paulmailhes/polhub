import Foundation

/// Where Vigie's engine lives on this Mac: the app Vigie installs it there, and keeps its private files in `data/`.
public struct VigieEngine: Sendable {
    public var folder: URL

    public init(folder: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".vigie", directoryHint: .isDirectory)) {
        self.folder = folder
    }

    var tokenFile: URL { folder.appending(path: "data/api-token") }

    /// The engine has run on this Mac: its token is there.
    public var isInstalled: Bool {
        FileManager.default.fileExists(atPath: tokenFile.path(percentEncoded: false))
    }

    /// The access token, read where the engine writes it at each request: never kept, never shown, never copied.
    func token() -> String? {
        guard let text = try? String(contentsOf: tokenFile, encoding: .utf8) else { return nil }
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}

public enum VigieFailure: Error, Equatable, Sendable {
    /// The engine is not on this Mac.
    case absent
    /// It does not answer.
    case stopped
    /// It refused: its status, and its own short sentence in French when it gave one.
    case refused(Int, String?)
    /// Its answer could not be read.
    case unreadable
}

/// hub talking to Vigie's engine (21/11): on this Mac only (`127.0.0.1`), with the engine's access token, as the app
/// Vigie does. Its contract is the engine's `docs/api-v2.md`.
public struct VigieClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public var engine: VigieEngine
    public var base: URL
    var transport: Transport

    public init(engine: VigieEngine = VigieEngine(), base: URL = URL(string: "http://127.0.0.1:4777")!, transport: Transport? = nil) {
        self.engine = engine
        self.base = base
        self.transport = transport ?? Self.local
    }

    /// Straight to the Mac itself: no proxy, no cache, no cookie, five seconds at most.
    static let local: Transport = { request in
        try await session.data(for: request)
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.connectionProxyDictionary = [:]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    /// The engine answers; asked without the token, as its installer does.
    public func isRunning() async -> Bool {
        var request = URLRequest(url: base.appending(path: "api/v2/health"))
        request.httpMethod = "GET"
        guard let (_, response) = try? await transport(request), let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    /// Everything the « Vue d'ensemble » shows.
    public func overview() async throws -> VigieOverview {
        let data = try await send("GET", "api/v2/overview", body: nil)
        guard let overview = try? JSONDecoder().decode(VigieOverview.self, from: data) else { throw VigieFailure.unreadable }
        return overview
    }

    /// A sensitive action that waits: allowed or refused, as a click in VS Code.
    public func decide(pending id: String, allow: Bool) async throws {
        _ = try await send("POST", "api/v2/pending/\(Self.segment(id))", body: ["decision": allow ? "allow" : "deny"])
    }

    /// A question Vigie answered for Paul: « Ça me va ».
    public func approve(question id: String) async throws {
        _ = try await send("POST", "api/v2/questions/\(Self.segment(id))/review", body: ["action": "ok"])
    }

    /// Takes a notice away from what is to see.
    public func dismiss(review id: String) async throws {
        _ = try await send("POST", "api/v2/review/\(Self.segment(id))/dismiss", body: [:])
    }

    /// Opens the conversation in VS Code.
    public func open(conversation id: String) async throws {
        _ = try await send("POST", "api/v2/open", body: ["kind": "conversation", "id": id])
    }

    static func segment(_ id: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
    }

    private func send(_ method: String, _ path: String, body: [String: String]?) async throws -> Data {
        guard engine.isInstalled, let token = engine.token() else { throw VigieFailure.absent }
        guard let url = URL(string: path, relativeTo: base.appending(path: "/")) else { throw VigieFailure.unreadable }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(token, forHTTPHeaderField: "X-Vigie-Token")
        if let body {
            // The engine's rule for every write.
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("1", forHTTPHeaderField: "X-Vigie")
            request.httpBody = try? JSONEncoder().encode(body)
        }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            throw VigieFailure.stopped
        }
        guard let http = response as? HTTPURLResponse else { throw VigieFailure.unreadable }
        guard (200..<300).contains(http.statusCode) else {
            let sentence = (try? JSONDecoder().decode(Refusal.self, from: data))?.error
            throw VigieFailure.refused(http.statusCode, sentence)
        }
        return data
    }

    private struct Refusal: Decodable {
        let error: String?
    }
}
