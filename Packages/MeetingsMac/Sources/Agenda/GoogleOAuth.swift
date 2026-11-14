import CryptoKit
import Foundation
import Network
import Security

public enum GoogleError: Error, Equatable, CustomStringConvertible {
    case noKey
    case badKey
    case refused(String)
    case badAnswer
    case expired
    case http(Int)
    case timeout
    /// The account was connected for reading only (before 14/11).
    case needsWrite
    /// Only the organizer changes an event.
    case notOrganizer

    public var description: String {
        switch self {
        case .noKey: "la clé Google n'est pas encore en place (scripts/configurer-google.command)"
        case .badKey: "la clé Google n'est pas une clé « application de bureau »"
        case .refused(let reason): "Google a refusé la connexion (\(reason))"
        case .badAnswer: "réponse de Google illisible"
        case .expired: "la connexion à ce compte a expiré : reconnecte-le"
        case .http(let code): "Google répond \(code)"
        case .timeout: "la connexion n'a pas été faite dans le navigateur à temps"
        case .needsWrite: "ce compte n'a autorisé que la lecture : reconnecte-le pour pouvoir modifier ses rendez-vous"
        case .notOrganizer: "seul l'organisateur peut modifier ce rendez-vous"
        }
    }
}

/// The key of the « Polhub » Google project, a desktop app: never in the repository, never shown.
public struct GoogleClientConfig: Sendable {
    public let clientID: String
    public let clientSecret: String
    public let authURI: URL
    public let tokenURI: URL

    public static var file: URL { URL.applicationSupportDirectory.appending(path: "Polhub/google-client.json") }

    public init(clientID: String, clientSecret: String, authURI: URL, tokenURI: URL) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.authURI = authURI
        self.tokenURI = tokenURI
    }

    public static func parse(_ data: Data) throws -> GoogleClientConfig {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let installed = root["installed"] as? [String: Any],
              let id = installed["client_id"] as? String, let secret = installed["client_secret"] as? String,
              let auth = (installed["auth_uri"] as? String).flatMap(URL.init(string:)),
              let token = (installed["token_uri"] as? String).flatMap(URL.init(string:))
        else { throw GoogleError.badKey }
        return GoogleClientConfig(clientID: id, clientSecret: secret, authURI: auth, tokenURI: token)
    }

    public static func load() throws -> GoogleClientConfig {
        guard let data = try? Data(contentsOf: file) else { throw GoogleError.noKey }
        return try parse(data)
    }
}

/// RFC 7636: the browser's return is only usable by the app that asked.
public enum PKCE {
    public static func verifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    public static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

public struct GoogleTokens: Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int
    /// The account's address, from the ID token.
    public let email: String?
    /// What Google granted, space-separated.
    public var scope: String? = nil
}

public enum GoogleOAuth {
    /// Events in read and write (14/11: Paul creates and changes his events from Polhub).
    public static let scopes = "openid email https://www.googleapis.com/auth/calendar.events"
    static let writeScope = "https://www.googleapis.com/auth/calendar.events"

    /// The scopes Google granted (the `scope` of a token answer) allow writing events.
    public static func canWrite(scope: String?) -> Bool {
        (scope ?? "").split(separator: " ").contains { $0 == writeScope || $0 == "https://www.googleapis.com/auth/calendar" }
    }

    public static func authorizationURL(config: GoogleClientConfig, redirect: URL, challenge: String, state: String, loginHint: String? = nil) -> URL {
        var components = URLComponents(url: config.authURI, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: redirect.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            // Always a refresh token, even for an account connected before.
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
        ] + (loginHint.map { [URLQueryItem(name: "login_hint", value: $0)] } ?? [])
        return components.url!
    }

    /// `GET /?state=…&code=… HTTP/1.1` → the code.
    public static func code(fromRequestLine line: String, state: String) throws -> String {
        let target = line.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        let items = URLComponents(string: "http://localhost\(target)")?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        if let error = value("error") { throw GoogleError.refused(error) }
        guard value("state") == state else { throw GoogleError.refused("réponse d'une autre demande") }
        guard let code = value("code"), !code.isEmpty else { throw GoogleError.badAnswer }
        return code
    }

    public static func exchangeRequest(config: GoogleClientConfig, code: String, verifier: String, redirect: URL) -> URLRequest {
        form(config.tokenURI, [
            "grant_type": "authorization_code", "code": code, "code_verifier": verifier, "redirect_uri": redirect.absoluteString,
            "client_id": config.clientID, "client_secret": config.clientSecret,
        ])
    }

    public static func refreshRequest(config: GoogleClientConfig, refreshToken: String) -> URLRequest {
        form(config.tokenURI, ["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": config.clientID,
                               "client_secret": config.clientSecret])
    }

    static func form(_ url: URL, _ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = Data(fields.sorted { $0.key < $1.key }.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&").utf8)
        return request
    }

    public static func tokens(from data: Data) throws -> GoogleTokens {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw GoogleError.badAnswer }
        if let error = json["error"] as? String { throw error == "invalid_grant" ? GoogleError.expired : GoogleError.refused(error) }
        guard let access = json["access_token"] as? String else { throw GoogleError.badAnswer }
        return GoogleTokens(accessToken: access, refreshToken: json["refresh_token"] as? String, expiresIn: json["expires_in"] as? Int ?? 3_600,
                            email: (json["id_token"] as? String).flatMap(email(fromIDToken:)), scope: json["scope"] as? String)
    }

    /// The address in the ID token's payload (received straight from Google over TLS: no signature check needed).
    static func email(fromIDToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["email"] as? String)?.lowercased()
    }
}

/// The local address Google sends the browser back to: one request, then it closes.
public final class LoopbackReceiver: @unchecked Sendable {
    let listener: NWListener
    public let redirect: URL
    private let lock = NSLock()
    private var waiting: CheckedContinuation<String, Error>?
    private var received: String?

    init(listener: NWListener, port: UInt16) {
        self.listener = listener
        self.redirect = URL(string: "http://127.0.0.1:\(port)")!
    }

    public static func start() async throws -> LoopbackReceiver {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let once = Once()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: once.run { continuation.resume(returning: listener.port?.rawValue ?? 0) }
                case .failed(let error): once.run { continuation.resume(throwing: error) }
                default: break
                }
            }
            listener.newConnectionHandler = { _ in }
            listener.start(queue: .global())
        }
        let receiver = LoopbackReceiver(listener: listener, port: port)
        listener.newConnectionHandler = { [weak receiver] connection in receiver?.handle(connection) }
        return receiver
    }

    func handle(_ connection: NWConnection) {
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            let text = String(decoding: data ?? Data(), as: UTF8.self)
            let line = text.components(separatedBy: "\r\n").first ?? ""
            let page = """
            <!doctype html><html lang="fr"><meta charset="utf-8"><title>Polhub</title>
            <body style="font: 16px -apple-system; padding: 48px">Polhub est connecté à ce compte Google. Tu peux fermer cet onglet.</body></html>
            """
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(page.utf8.count)\r\nConnection: close\r\n\r\n\(page)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            guard line.hasPrefix("GET /?") else { return }   // the browser's favicon, for instance
            self?.deliver(.success(line))
        }
    }

    func deliver(_ result: Result<String, Error>) {
        lock.withLock {
            if let waiting {
                waiting.resume(with: result)
                self.waiting = nil
            } else if case .success(let line) = result {
                received = line
            }
        }
    }

    /// The first request line of the browser's return.
    public func nextRequestLine(timeout: TimeInterval) async throws -> String {
        defer { listener.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                if let received {
                    continuation.resume(returning: received)
                } else {
                    waiting = continuation
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in self?.deliver(.failure(GoogleError.timeout)) }
        }
    }
}

final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func run(_ body: () -> Void) {
        lock.withLock {
            guard !done else { return }
            done = true
            body()
        }
    }
}

/// Where the refresh tokens live.
public protocol TokenVault: Sendable {
    func save(refreshToken: String, for email: String) throws
    func refreshToken(for email: String) -> String?
    func remove(for email: String)
}

/// The login Keychain: one item per account, readable only by Polhub.
public struct KeychainVault: TokenVault {
    public static let service = "fr.paulmailhes.polhub.google"

    public init() {}

    func query(_ email: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: email.lowercased()]
    }

    public func save(refreshToken: String, for email: String) throws {
        SecItemDelete(query(email) as CFDictionary)
        var item = query(email)
        item[kSecValueData as String] = Data(refreshToken.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw GoogleError.refused("Trousseau : \(status)") }
    }

    public func refreshToken(for email: String) -> String? {
        var item = query(email)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public func remove(for email: String) {
        SecItemDelete(query(email) as CFDictionary)
    }
}
