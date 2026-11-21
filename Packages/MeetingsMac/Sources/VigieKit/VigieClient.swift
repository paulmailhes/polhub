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

    /// Straight to the Mac itself: no proxy, no cache, no cookie; each request says how long it waits (`Patience`).
    static let local: Transport = { request in
        try await session.data(for: request)
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Patience.read.rawValue
        configuration.timeoutIntervalForResource = Patience.long.rawValue
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

    /// How long hub waits: a read, a write, and the writes the engine takes its time for (opening VS Code and waiting
    /// for its window, ~27 s by its contract).
    public enum Patience: TimeInterval, Sendable {
        case read = 5
        case write = 30
        case long = 90
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

    /// A question that waits: Paul's answers, one per question, as a click in VS Code.
    public func answer(pending id: String, answers: [String: String]) async throws {
        _ = try await send("POST", "api/v2/pending/\(Self.segment(id))", body: ["answers": answers])
    }

    /// A question Vigie answered for Paul: « Ça me va ».
    public func approve(question id: String) async throws {
        _ = try await send("POST", "api/v2/questions/\(Self.segment(id))/review", body: ["action": "ok"])
    }

    /// What the engine gives back when Paul changes an answer: the text to send the conversation, and where to paste it.
    public struct Correction: Decodable, Equatable, Sendable {
        public var correction: String?
        public var openURL: String?

        enum CodingKeys: String, CodingKey {
            case correction, openURL = "openUrl"
        }
    }

    /// A question Vigie answered for Paul, answered otherwise: « Changer ». The engine never sends it itself.
    public func change(question id: String, answers: [String: String]) async throws -> Correction {
        let data = try await send("POST", "api/v2/questions/\(Self.segment(id))/review", body: ["action": "change", "answers": answers])
        return (try? JSONDecoder().decode(Correction.self, from: data)) ?? Correction()
    }

    /// Takes a notice away from what is to see.
    public func dismiss(review id: String) async throws {
        _ = try await send("POST", "api/v2/review/\(Self.segment(id))/dismiss", body: [:])
    }

    /// What the engine said of an opening: a sentence to show when the conversation itself could not be opened.
    public struct Opening: Decodable, Equatable, Sendable {
        public var opened: String?
        public var message: String?
        public var mode: String?
    }

    /// Opens the conversation in VS Code: the engine waits for the project's window, up to ~27 s.
    @discardableResult
    public func open(conversation id: String) async throws -> Opening {
        let data = try await send("POST", "api/v2/open", body: ["kind": "conversation", "id": id], patience: .long)
        return (try? JSONDecoder().decode(Opening.self, from: data)) ?? Opening()
    }

    /// Terminal opens with the command typed, not run: Paul presses Enter and types his password. `id`: the element the
    /// command comes from, for the engine to find a masked command's exact text.
    @discardableResult
    public func openTerminal(command: String, cwd: String?, review id: String?) async throws -> Opening {
        var body: [String: Any] = ["kind": "terminal", "command": command]
        if let cwd { body["cwd"] = cwd }
        if let id { body["id"] = id }
        let data = try await send("POST", "api/v2/open", body: body, patience: .long)
        return (try? JSONDecoder().decode(Opening.self, from: data)) ?? Opening()
    }

    /// A conversation in detail; the engine keeps none past 48 hours (refused, 404).
    public func conversation(_ id: String) async throws -> VigieConversationDetail {
        let data = try await send("GET", "api/v2/conversation/\(Self.segment(id))", body: nil)
        guard let detail = try? JSONDecoder().decode(VigieConversationDetail.self, from: data) else { throw VigieFailure.unreadable }
        return detail
    }

    /// What the engine says of an account switch: done, or pending until the end of the turn.
    public struct Switch: Decodable, Equatable, Sendable {
        public var state: String?
        public var message: String?
    }

    /// A conversation's own settings: its account (`accountId`, `now` to interrupt it), its auto-accept (`autoAccept`,
    /// `NSNull` for the general setting), its account's MCP (`connectors`).
    @discardableResult
    public func conversationSettings(_ id: String, _ changes: [String: Any]) async throws -> Switch? {
        let data = try await send("POST", "api/v2/conversation/\(Self.segment(id))/settings", body: changes)
        struct Answer: Decodable { let `switch`: Switch? }
        return (try? JSONDecoder().decode(Answer.self, from: data))?.switch
    }

    /// The Claude accounts, in detail.
    public func accounts() async throws -> VigieAccounts {
        let data = try await send("GET", "api/v2/accounts", body: nil)
        guard let accounts = try? JSONDecoder().decode(VigieAccounts.self, from: data) else { throw VigieFailure.unreadable }
        return accounts
    }

    /// A gesture on the accounts (`action`: setDefault, connect, refresh, create, rename, remove, wrapper); the engine's
    /// sentence when it has one. Connecting opens Terminal or the browser: the engine waits for it.
    @discardableResult
    public func accounts(_ body: [String: Any]) async throws -> String? {
        let data = try await send("POST", "api/v2/accounts", body: body, patience: .long)
        struct Answer: Decodable { let message: String? }
        return (try? JSONDecoder().decode(Answer.self, from: data))?.message
    }

    /// Changes general settings: only the keys given; `guard` takes its own keys (`enabled`, `waitMin`, `rules`).
    @discardableResult
    public func settings(_ changes: [String: Any]) async throws -> VigieSettings? {
        let data = try await send("POST", "api/v2/settings", body: changes)
        struct Answer: Decodable { let settings: VigieSettings? }
        return (try? JSONDecoder().decode(Answer.self, from: data))?.settings
    }

    static func segment(_ id: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
    }

    private func send(_ method: String, _ path: String, body: [String: Any]?, patience: Patience? = nil) async throws -> Data {
        guard engine.isInstalled, let token = engine.token() else { throw VigieFailure.absent }
        guard let url = URL(string: path, relativeTo: base.appending(path: "/")) else { throw VigieFailure.unreadable }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(token, forHTTPHeaderField: "X-Vigie-Token")
        request.timeoutInterval = (patience ?? (body == nil ? .read : .write)).rawValue
        if let body {
            // The engine's rule for every write.
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("1", forHTTPHeaderField: "X-Vigie")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
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
