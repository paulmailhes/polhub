import Foundation

/// Access tokens, refreshed from the Keychain's refresh tokens. One session for the whole app: the calendar and
/// the mails share an account's token (14/11).
public actor GoogleSession {
    let config: @Sendable () throws -> GoogleClientConfig
    let vault: any TokenVault
    let fetch: GoogleHTTP.Fetch
    /// The address and what it granted, at each token answer that says so: the app keeps it in its base.
    let onGrant: @Sendable (String, String) -> Void
    private var cache: [String: (token: String, until: Date)] = [:]
    /// What each account granted, from its last token.
    private var granted: [String: String] = [:]

    public init(config: @escaping @Sendable () throws -> GoogleClientConfig = GoogleClientConfig.load, vault: any TokenVault = KeychainVault(),
                fetch: @escaping GoogleHTTP.Fetch = GoogleHTTP.live, onGrant: @escaping @Sendable (String, String) -> Void = { _, _ in }) {
        self.config = config
        self.vault = vault
        self.fetch = fetch
        self.onGrant = onGrant
    }

    public func accessToken(for email: String, now: Date = Date()) async throws -> String {
        if let cached = cache[email], cached.until > now.addingTimeInterval(60) { return cached.token }
        guard let refresh = vault.refreshToken(for: email) else { throw GoogleError.expired }
        let (data, status) = try await fetch(GoogleOAuth.refreshRequest(config: try config(), refreshToken: refresh))
        // Google's page down or busy (right after wake): a failure that passes, never « refused » for good (wave B review).
        if status == 429 { throw GoogleError.rateLimited }
        if status >= 500 || status == 408 { throw GoogleError.http(status) }
        let tokens = try GoogleOAuth.tokens(from: data)
        cache[email] = (tokens.accessToken, now.addingTimeInterval(TimeInterval(tokens.expiresIn)))
        note(tokens.scope, for: email)
        return tokens.accessToken
    }

    private func note(_ scope: String?, for email: String) {
        guard let scope else { return }
        granted[email] = scope
        onGrant(email, scope)
    }

    /// Whether the account's events can be written; `nil` before its first token.
    public func canWrite(_ email: String) -> Bool? {
        grants(.calendarEvents, for: email)
    }

    /// Whether the account granted this access; `nil` before its first token.
    public func grants(_ scope: GoogleScope, for email: String) -> Bool? {
        granted[email].map { GoogleOAuth.grants(scope, in: $0) }
    }

    /// The browser opens on Google's page; the account comes back connected. Returns its address.
    /// An answer that lacks one of `mustKeep` is refused and nothing is saved: asking for the mails never costs
    /// an account its calendar (Paul unticks a box, an administrator narrows the access).
    public func connect(open: @escaping @Sendable (URL) -> Void, requesting: Set<GoogleScope> = [.calendarEvents],
                        mustKeep: Set<GoogleScope> = [], loginHint: String? = nil, timeout: TimeInterval = 300) async throws -> String {
        let config = try config()
        let receiver = try await LoopbackReceiver.start()
        let verifier = PKCE.verifier(), state = UUID().uuidString
        open(GoogleOAuth.authorizationURL(config: config, redirect: receiver.redirect, challenge: PKCE.challenge(for: verifier), state: state,
                                          loginHint: loginHint, scopes: requesting))
        let line = try await receiver.nextRequestLine(timeout: timeout)
        let code = try GoogleOAuth.code(fromRequestLine: line, state: state)
        let (data, _) = try await fetch(GoogleOAuth.exchangeRequest(config: config, code: code, verifier: verifier, redirect: receiver.redirect))
        return try accept(GoogleOAuth.tokens(from: data), mustKeep: mustKeep)
    }

    /// Keeps a fresh answer of Google's, unless it is narrower than what the account must keep.
    func accept(_ tokens: GoogleTokens, mustKeep: Set<GoogleScope>, now: Date = Date()) throws -> String {
        guard let email = tokens.email, let refresh = tokens.refreshToken else { throw GoogleError.badAnswer }
        if let missing = GoogleScope.allCases.first(where: { mustKeep.contains($0) && !GoogleOAuth.grants($0, in: tokens.scope) }) {
            throw GoogleError.missingScope(missing)
        }
        try vault.save(refreshToken: refresh, for: email)
        cache[email] = (tokens.accessToken, now.addingTimeInterval(TimeInterval(tokens.expiresIn)))
        note(tokens.scope, for: email)
        return email
    }

    /// What the account granted at its last token, as Google gave it; `nil` before.
    public func scopes(for email: String) -> String? {
        granted[email]
    }

    public func forget(_ email: String) {
        cache[email] = nil
        granted[email] = nil
        vault.remove(for: email)
    }

    /// Sends a request with the account's token; each service says what a refusal means (`mapping`).
    public func send(_ build: @Sendable (String) -> URLRequest, for email: String,
                     mapping: @Sendable (Int, Data) -> GoogleError) async throws -> Data {
        let token = try await accessToken(for: email)
        let (data, status) = try await fetch(build(token))
        guard (200..<300).contains(status) else { throw mapping(status, data) }
        return data
    }
}
