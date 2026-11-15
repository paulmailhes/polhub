import Foundation
import Testing
@testable import GoogleKit

/// Security review of wave B (15/11): what Google answers never reaches the disk, and a refusal of Google's token
/// page that passes (a 5xx at wake) says so.
@Suite struct GoogleHTTPTests {
    /// `URLSession.shared` keeps its answers in `Caches/…/Cache.db` and `fsCachedData`: a spam's body would stay
    /// there. Polhub's own session keeps nothing, neither answers nor cookies.
    @Test func whatGoogleAnswersIsNeverKeptOnDisk() {
        let configuration = GoogleHTTP.session.configuration
        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(configuration.httpCookieStorage == nil && !configuration.httpShouldSetCookies)
        #expect(GoogleHTTP.session !== URLSession.shared)
    }

    func session(answer: Data, status: Int) -> GoogleSession {
        let vault = GoogleScopeTests.MemoryVault()
        try? vault.save(refreshToken: "jeton-de-test", for: "moi@exemple.fr")
        return GoogleSession(config: { GoogleScopeTests.config }, vault: vault, fetch: { _ in (answer, status) })
    }

    /// Google's token page down (an HTML 5xx right after wake, a JSON « internal_failure »): a failure that passes,
    /// which a programmed mail waits through, never a refusal for good.
    @Test func aTokenPageDownPasses() async throws {
        await #expect(throws: GoogleError.http(503)) {
            try await session(answer: Data("<html>Service indisponible</html>".utf8), status: 503).accessToken(for: "moi@exemple.fr")
        }
        await #expect(throws: GoogleError.http(500)) {
            try await session(answer: Data(#"{"error":"internal_failure"}"#.utf8), status: 500).accessToken(for: "moi@exemple.fr")
        }
        await #expect(throws: GoogleError.rateLimited) {
            try await session(answer: Data(#"{"error":"rate_limit_exceeded"}"#.utf8), status: 429).accessToken(for: "moi@exemple.fr")
        }
        // A revoked access is still « reconnect », and a good answer still gives the token.
        await #expect(throws: GoogleError.expired) {
            try await session(answer: Data(#"{"error":"invalid_grant"}"#.utf8), status: 400).accessToken(for: "moi@exemple.fr")
        }
        let token = try await session(answer: Data(#"{"access_token":"acces","expires_in":3600}"#.utf8), status: 200).accessToken(for: "moi@exemple.fr")
        #expect(token == "acces")
    }
}
