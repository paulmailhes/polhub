import Foundation
import Testing
@testable import GoogleKit

/// 14/11: the calendar and the mails share one session; asking for the mails never costs an account its calendar.
@Suite struct GoogleScopeTests {
    static let calendar = "https://www.googleapis.com/auth/calendar.events"
    static let mail = "https://www.googleapis.com/auth/gmail.modify"

    final class MemoryVault: TokenVault, @unchecked Sendable {
        private let lock = NSLock()
        private var tokens: [String: String] = [:]
        func save(refreshToken: String, for email: String) throws { lock.withLock { tokens[email] = refreshToken } }
        func refreshToken(for email: String) -> String? { lock.withLock { tokens[email] } }
        func remove(for email: String) { lock.withLock { tokens[email] = nil } }
    }

    final class Grants: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String] = []
        func add(_ value: String) { lock.withLock { values.append(value) } }
        var all: [String] { lock.withLock { values } }
    }

    static let config = GoogleClientConfig(clientID: "id", clientSecret: "secret")

    @Test func theScopesAskedComeInAFixedOrder() {
        #expect(GoogleOAuth.scopeText([.gmailModify, .calendarEvents]) == "openid email \(Self.calendar) \(Self.mail)")
        // The calendar alone asks what it asked before the mails.
        #expect(GoogleOAuth.scopes == "openid email \(Self.calendar)")
        let url = GoogleOAuth.authorizationURL(config: Self.config, redirect: URL(string: "http://127.0.0.1:1")!, challenge: "c", state: "s",
                                               loginHint: "moi@exemple.fr", scopes: [.calendarEvents, .gmailModify])
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "scope" }?.value == "openid email \(Self.calendar) \(Self.mail)")
        #expect(items.first { $0.name == "login_hint" }?.value == "moi@exemple.fr")
    }

    @Test func whatGoogleGrantedSaysWhichAccessIsOpen() {
        let both = "openid https://www.googleapis.com/auth/userinfo.email \(Self.calendar) \(Self.mail)"
        #expect(GoogleOAuth.grants(.gmailModify, in: both) && GoogleOAuth.grants(.calendarEvents, in: both))
        #expect(!GoogleOAuth.grants(.gmailModify, in: "openid \(Self.calendar)"))
        #expect(!GoogleOAuth.grants(.gmailModify, in: nil))
        // A wider grant holds the narrower one.
        #expect(GoogleOAuth.grants(.gmailModify, in: "https://mail.google.com/"))
        #expect(GoogleOAuth.canWrite(scope: both) && !GoogleOAuth.canWrite(scope: "openid \(Self.mail)"))
    }

    /// Paul unticks the calendar on Google's page while adding the mails: nothing is saved, the old token stays.
    @Test func anAnswerNarrowerThanWhatMustBeKeptIsThrownAway() async throws {
        let vault = MemoryVault(), grants = Grants()
        try vault.save(refreshToken: "ancien", for: "moi@exemple.fr")
        let session = GoogleSession(config: { Self.config }, vault: vault, fetch: { _ in (Data(), 200) }, onGrant: { grants.add("\($0) \($1)") })
        let narrow = GoogleTokens(accessToken: "a", refreshToken: "nouveau", expiresIn: 3_600, email: "moi@exemple.fr", scope: "openid \(Self.mail)")
        await #expect(throws: GoogleError.missingScope(.calendarEvents)) { try await session.accept(narrow, mustKeep: [.calendarEvents]) }
        #expect(vault.refreshToken(for: "moi@exemple.fr") == "ancien")
        #expect(grants.all.isEmpty)
        #expect(await session.grants(.gmailModify, for: "moi@exemple.fr") == nil)
    }

    @Test func aFullAnswerIsKeptAndItsGrantsAreTold() async throws {
        let vault = MemoryVault(), grants = Grants()
        let session = GoogleSession(config: { Self.config }, vault: vault, fetch: { _ in (Data(), 200) }, onGrant: { grants.add("\($0) \($1)") })
        let both = "openid \(Self.calendar) \(Self.mail)"
        let tokens = GoogleTokens(accessToken: "a", refreshToken: "r", expiresIn: 3_600, email: "moi@exemple.fr", scope: both)
        #expect(try await session.accept(tokens, mustKeep: [.calendarEvents]) == "moi@exemple.fr")
        #expect(vault.refreshToken(for: "moi@exemple.fr") == "r")
        #expect(grants.all == ["moi@exemple.fr \(both)"])
        #expect(await session.grants(.gmailModify, for: "moi@exemple.fr") == true)
        #expect(await session.scopes(for: "moi@exemple.fr") == both)
        // The calendar alone, unticked mails: kept too, the mails stay to be granted.
        let calendarOnly = GoogleTokens(accessToken: "a", refreshToken: "r2", expiresIn: 3_600, email: "moi@exemple.fr", scope: "openid \(Self.calendar)")
        _ = try await session.accept(calendarOnly, mustKeep: [.calendarEvents])
        #expect(await session.grants(.gmailModify, for: "moi@exemple.fr") == false)
    }

    /// Each service says what a refusal means: the session only carries the token.
    @Test func aRefusalIsTranslatedByTheServiceThatAsked() async throws {
        let vault = MemoryVault(), grants = Grants()
        try vault.save(refreshToken: "r", for: "moi@exemple.fr")
        let session = GoogleSession(config: { Self.config }, vault: vault, fetch: { request in
            // The token's refresh, at Google's own address (nothing leaves: the fetch is the test's).
            if request.url == GoogleClientConfig.tokenEndpoint {
                return (Data(#"{"access_token":"jeton","expires_in":3600,"scope":"openid \#(Self.mail)"}"#.utf8), 200)
            }
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer jeton")
            return (Data("trop vite".utf8), 429)
        }, onGrant: { grants.add("\($0) \($1)") })
        await #expect(throws: GoogleError.rateLimited) {
            try await session.send({ token in
                var request = URLRequest(url: URL(string: "https://api.exemple.fr/chose")!)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return request
            }, for: "moi@exemple.fr", mapping: { status, _ in status == 429 ? .rateLimited : .http(status) })
        }
        // A refreshed token tells what the account granted, for the base to keep.
        #expect(grants.all == ["moi@exemple.fr openid \(Self.mail)"])
    }
}
