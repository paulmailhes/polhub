import Foundation

/// Where the iPhone reaches its Mac, and the key it shows: kept in the iPhone's Keychain.
public struct LinkConnection: Codable, Sendable, Equatable {
    public var address: URL
    public var token: String

    public init(address: URL, token: String) {
        self.address = address
        self.token = token
    }
}

/// Why the Mac did not answer, in Paul's words.
public enum LinkFailure: Error, Equatable, Sendable {
    /// The Mac sleeps, is off, or the iPhone is off Tailscale.
    case unreachable
    /// The Mac no longer knows this iPhone.
    case notPaired(String)
    /// The Mac answered, but no.
    case refused(String)
    /// The Mac answered something the iPhone does not read: another version.
    case unreadable

    public var message: String {
        switch self {
        case .unreachable: "Le Mac ne répond pas : il dort, il est éteint, ou Tailscale est coupé sur l'iPhone."
        case .notPaired(let text), .refused(let text): text
        case .unreadable: "Le Mac a répondu dans une autre langue : mets à jour hub sur le Mac et sur l'iPhone."
        }
    }
}

/// The iPhone's side of the API: one request, its token, its answer read (20/11).
public struct LinkClient: Sendable {
    public let connection: LinkConnection
    let session: URLSession
    /// The Mac asleep never answers: the iPhone says so after this long.
    public static let timeout: TimeInterval = 8

    public init(connection: LinkConnection, session: URLSession = .shared) {
        self.connection = connection
        self.session = session
    }

    public func url(_ path: String, query: [String: String] = [:]) -> URL {
        var components = URLComponents(url: connection.address, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.path = path
        components.queryItems = query.isEmpty ? nil : query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url ?? connection.address
    }

    /// The answer's bytes, as they came. With a `body`, a POST (lot 3, 20/11).
    public func data(_ path: String, query: [String: String] = [:], body: Data? = nil) async throws(LinkFailure) -> Data {
        var request = URLRequest(url: url(path, query: query), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.timeout)
        request.setValue(LinkAPI.bearer(connection.token), forHTTPHeaderField: LinkAPI.authorization)
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .unreachable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? LinkAPI.decoder.decode(LinkError.self, from: data))?.message ?? "Le Mac n'a pas pu répondre. Réessaie dans un instant."
            throw status == 401 ? .notPaired(message) : .refused(message)
        }
        return data
    }

    /// A POST: `body` in JSON, its answer read.
    public func post<Value: Decodable>(_ type: Value.Type, _ path: String, body: some Encodable & Sendable) async throws(LinkFailure) -> Value {
        guard let encoded = try? LinkAPI.encoder.encode(body) else { throw .unreadable }
        let data = try await data(path, body: encoded)
        do { return try LinkAPI.decoder.decode(type, from: data) } catch { throw .unreadable }
    }

    public func get<Value: Decodable>(_ type: Value.Type, _ path: String, query: [String: String] = [:]) async throws(LinkFailure) -> Value {
        let data = try await data(path, query: query)
        do { return try LinkAPI.decoder.decode(type, from: data) } catch { throw .unreadable }
    }
}

/// What the iPhone shows: the Mac's answer, or the last one kept when the Mac sleeps (`keptAt`).
public struct Fetched<Value: Sendable>: Sendable {
    public var value: Value
    /// When this copy was taken, when it is not fresh.
    public var keptAt: Date?

    public init(value: Value, keptAt: Date?) {
        self.value = value
        self.keptAt = keptAt
    }
}

/// The last answers, on the iPhone, protected as long as it was not unlocked once since it started (20/11).
public struct LinkCache: Sendable {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// The default place: the app's own support folder.
    public static var standard: LinkCache {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return LinkCache(folder: base.appending(path: "copie", directoryHint: .isDirectory))
    }

    func file(_ key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        return folder.appending(path: String(safe.prefix(180)) + ".json")
    }

    /// - at: when the answer was made, which the copy shows (« copie de 18:42 »): now for the Mac's answer, the Mac's
    ///   time for a copy read in iCloud.
    public func store(_ data: Data, for key: String, at date: Date = Date()) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = file(key)
        #if os(iOS)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try? data.write(to: url, options: .atomic)
        #endif
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path(percentEncoded: false))
    }

    /// A copy from iCloud: kept only if it is more recent than the one already kept (the Mac's answer, seen live, wins
    /// over an older copy).
    @discardableResult
    public func storeIfNewer(_ data: Data, for key: String, at date: Date) -> Bool {
        if let kept = load(key), kept.keptAt >= date { return false }
        store(data, for: key, at: date)
        return true
    }

    /// A copy the Mac took away from iCloud (a project gone).
    public func remove(_ key: String) {
        try? FileManager.default.removeItem(at: file(key))
    }

    public func load(_ key: String) -> (data: Data, keptAt: Date)? {
        let url = file(key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let date = (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.modificationDate] as? Date) ?? Date.distantPast
        return (data, date)
    }

    /// Everything kept goes: the iPhone is unpaired.
    public func clear() {
        try? FileManager.default.removeItem(at: folder)
    }
}

extension LinkClient {
    /// The Mac's answer, kept for later; when the Mac does not answer, the last answer kept, with its date. A Mac that
    /// no longer knows this iPhone never falls back on the copy.
    public func fetch<Value: Decodable & Sendable>(_ type: Value.Type, _ path: String, query: [String: String] = [:],
                                                    cache: LinkCache) async throws(LinkFailure) -> Fetched<Value> {
        let key = LinkAPI.key(path, query: query)
        do throws(LinkFailure) {
            let data = try await data(path, query: query)
            guard let value = try? LinkAPI.decoder.decode(type, from: data) else { throw LinkFailure.unreadable }
            cache.store(data, for: key)
            return Fetched(value: value, keptAt: nil)
        } catch .unreachable {
            guard let kept = cache.load(key), let value = try? LinkAPI.decoder.decode(type, from: kept.data) else { throw .unreachable }
            return Fetched(value: value, keptAt: kept.keptAt)
        }
    }
}
