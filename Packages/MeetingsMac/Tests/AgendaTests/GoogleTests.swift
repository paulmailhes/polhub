import Domain
import Foundation
import Persistence
import Testing
@testable import Agenda

/// The Google connection (desktop app, PKCE, local return address) and the reading of calendars (13/11).
@Suite struct GoogleOAuthTests {
    let config = GoogleClientConfig(clientID: "client-exemple.apps.googleusercontent.com", clientSecret: "secret-exemple",
                                    authURI: URL(string: "https://accounts.google.com/o/oauth2/auth")!,
                                    tokenURI: URL(string: "https://oauth2.googleapis.com/token")!)

    @Test func theKeyFileIsRead() throws {
        let json = #"{"installed":{"client_id":"a.apps.googleusercontent.com","client_secret":"s","auth_uri":"https://accounts.google.com/o/oauth2/auth","token_uri":"https://oauth2.googleapis.com/token","redirect_uris":["http://localhost"]}}"#
        let parsed = try GoogleClientConfig.parse(Data(json.utf8))
        #expect(parsed.clientID == "a.apps.googleusercontent.com" && parsed.tokenURI.host() == "oauth2.googleapis.com")
        #expect(throws: (any Error).self) { try GoogleClientConfig.parse(Data(#"{"web":{}}"#.utf8)) }
    }

    @Test func pkceFollowsTheRFC() {
        // RFC 7636, appendix B.
        #expect(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let verifier = PKCE.verifier()
        #expect((43...128).contains(verifier.count) && verifier.allSatisfy { $0.isLetter || $0.isNumber || "-._~".contains($0) })
    }

    @Test func theAuthorizationAsksForOfflineCalendarEvents() throws {
        let url = GoogleOAuth.authorizationURL(config: config, redirect: URL(string: "http://127.0.0.1:53682")!, challenge: "c", state: "s")
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["client_id"] == config.clientID && items["redirect_uri"] == "http://127.0.0.1:53682")
        // 14/11: Paul creates and changes his events from Polhub.
        #expect(items["scope"] == "openid email https://www.googleapis.com/auth/calendar.events")
        #expect(items["access_type"] == "offline" && items["prompt"] == "consent")
        #expect(items["code_challenge"] == "c" && items["code_challenge_method"] == "S256" && items["state"] == "s")
    }

    @Test func theBrowsersReturnGivesTheCodeOrTheRefusal() throws {
        #expect(try GoogleOAuth.code(fromRequestLine: "GET /?state=s&code=4%2F0abc&scope=email HTTP/1.1", state: "s") == "4/0abc")
        #expect(throws: GoogleError.self) { try GoogleOAuth.code(fromRequestLine: "GET /?state=autre&code=x HTTP/1.1", state: "s") }
        #expect(throws: GoogleError.self) { try GoogleOAuth.code(fromRequestLine: "GET /?error=access_denied&state=s HTTP/1.1", state: "s") }
    }

    @Test func tokensAndTheAccountsAddressAreRead() throws {
        // A made-up ID token: header.payload.signature, the payload carrying the address.
        let payload = Data(#"{"email":"Moi@Exemple.fr","email_verified":true}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        let json = #"{"access_token":"a1","expires_in":3599,"refresh_token":"r1","scope":"openid","token_type":"Bearer","id_token":"e30.\#(payload).sig"}"#
        let tokens = try GoogleOAuth.tokens(from: Data(json.utf8))
        #expect(tokens.accessToken == "a1" && tokens.refreshToken == "r1" && tokens.expiresIn == 3599)
        #expect(tokens.email == "moi@exemple.fr")
        #expect(throws: GoogleError.self) { try GoogleOAuth.tokens(from: Data(#"{"error":"invalid_grant"}"#.utf8)) }
    }

    @Test func theTokenRequestsAreForms() throws {
        let exchange = GoogleOAuth.exchangeRequest(config: config, code: "4/0abc", verifier: "v", redirect: URL(string: "http://127.0.0.1:1")!)
        let body = String(decoding: exchange.httpBody ?? Data(), as: UTF8.self)
        #expect(exchange.httpMethod == "POST" && exchange.url == config.tokenURI)
        #expect(body.contains("grant_type=authorization_code") && body.contains("code=4%2F0abc") && body.contains("code_verifier=v"))
        let refresh = String(decoding: GoogleOAuth.refreshRequest(config: config, refreshToken: "r1").httpBody ?? Data(), as: UTF8.self)
        #expect(refresh.contains("grant_type=refresh_token") && refresh.contains("refresh_token=r1"))
    }

    /// The local return address, for real: the browser's request reaches it, and the browser gets a page.
    @Test func theLocalReceiverGetsTheBrowsersRequest() async throws {
        let receiver = try await LoopbackReceiver.start()
        async let line = receiver.nextRequestLine(timeout: 5)
        let (data, _) = try await URLSession.shared.data(from: URL(string: "\(receiver.redirect.absoluteString)/?state=s&code=c")!)
        #expect(try await line.contains("code=c"))
        #expect(String(decoding: data, as: UTF8.self).contains("Polhub"))
    }
}

@Suite struct CalendarReadingTests {
    static let page = #"""
    {"kind":"calendar#events","nextPageToken":"p2","items":[
     {"id":"e1","status":"confirmed","htmlLink":"https://www.google.com/calendar/event?eid=x","summary":"Atelier maquette",
      "location":"Paris","start":{"dateTime":"2026-11-13T10:00:00+01:00"},"end":{"dateTime":"2026-11-13T11:00:00+01:00"},
      "recurringEventId":"serie1","hangoutLink":"https://meet.google.com/abc-defg-hij","organizer":{"email":"moi@exemple.fr","self":true},
      "attendees":[{"email":"moi@exemple.fr","self":true,"organizer":true,"responseStatus":"accepted"},
                   {"email":"Camille@Exemple.fr","displayName":"Camille","responseStatus":"tentative"},
                   {"email":"salle@resource.calendar.google.com","resource":true}],
      "updated":"2026-11-12T08:00:00.000Z"},
     {"id":"e2","status":"confirmed","start":{"date":"2026-11-14"},"end":{"date":"2026-11-15"}},
     {"id":"e3","status":"cancelled"}
    ]}
    """#

    @Test func eventsAreReadWithTheirGuestsAndMeetCode() throws {
        let page = try CalendarAPI.page(from: Data(Self.page.utf8), account: "moi@exemple.fr")
        #expect(page.nextPageToken == "p2" && page.cancelled == ["e3"])
        let first = try #require(page.events.first)
        #expect(first.title == "Atelier maquette" && first.meetCode == "abc-defg-hij" && first.recurringEventID == "serie1")
        #expect(first.startAt == ISO8601DateFormatter().date(from: "2026-11-13T09:00:00Z"))
        #expect(first.guests.map(\.email) == ["camille@exemple.fr"] && first.guests.first?.name == "Camille")
        #expect(first.attendees.contains { $0.isResource } && first.attendees.contains { $0.isSelf })
        let allDay = try #require(page.events.last)
        #expect(allDay.allDay && allDay.title == "(sans titre)")
    }

    @Test func theRequestReadsThePrimaryCalendarInAWindow() throws {
        let from = ISO8601DateFormatter().date(from: "2026-05-17T00:00:00Z")!, to = ISO8601DateFormatter().date(from: "2027-01-12T00:00:00Z")!
        let request = CalendarAPI.eventsRequest(accessToken: "a1", from: from, to: to, pageToken: "p2")
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(request.url?.path() == "/calendar/v3/calendars/primary/events")
        #expect(items["singleEvents"] == "true" && items["pageToken"] == "p2" && items["timeMin"] == "2026-05-17T00:00:00Z")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer a1")
    }

    @Test func aSyncStoresTheWindowAndForgetsWhatGoogleNoLongerHas() async throws {
        let database = try AppDatabase.inMemory()
        let calendar = CalendarStore(database)
        let now = ISO8601DateFormatter().date(from: "2026-11-13T12:00:00Z")!
        try calendar.addAccount(email: "moi@exemple.fr", at: now)
        let second = #"{"items":[{"id":"e4","status":"confirmed","summary":"Suite","start":{"dateTime":"2026-11-20T10:00:00Z"},"end":{"dateTime":"2026-11-20T10:30:00Z"}}]}"#
        let pages = PageQueue([Self.page, second])
        let sync = CalendarSync(fetch: { _ in (Data(pages.next().utf8), 200) })
        try await sync.sync(account: "moi@exemple.fr", accessToken: "a1", store: calendar, now: now)
        #expect(try calendar.allEvents().map(\.eventID) == ["e1", "e2", "e4"])

        let later = #"{"items":[{"id":"e4","status":"confirmed","summary":"Suite","start":{"dateTime":"2026-11-20T10:00:00Z"},"end":{"dateTime":"2026-11-20T10:30:00Z"}}]}"#
        try await CalendarSync(fetch: { _ in (Data(later.utf8), 200) }).sync(account: "moi@exemple.fr", accessToken: "a1", store: calendar, now: now)
        #expect(try calendar.allEvents().map(\.eventID) == ["e4"])
        #expect(try calendar.accounts().first?.lastSyncAt == now)
    }

    /// Review of 14/11: what Paul writes while a sync reads Google is neither deleted nor put back by it.
    @Test func aWriteDuringASyncSurvivesIt() async throws {
        let database = try AppDatabase.inMemory()
        let calendar = CalendarStore(database)
        let now = ISO8601DateFormatter().date(from: "2026-11-13T12:00:00Z")!
        try calendar.addAccount(email: "moi@exemple.fr", at: now)
        let old = #"{"items":[{"id":"e1","status":"confirmed","summary":"Ancien titre","start":{"dateTime":"2026-11-20T10:00:00Z"},"end":{"dateTime":"2026-11-20T10:30:00Z"}}]}"#
        try await CalendarSync(fetch: { _ in (Data(old.utf8), 200) }).sync(account: "moi@exemple.fr", accessToken: "a1", store: calendar, now: now)
        let later = now.addingTimeInterval(600)
        // The next sync reads Google; meanwhile Paul renames e1 and creates e9 from Polhub.
        let sync = CalendarSync(fetch: { _ in
            var renamed = CalendarEventRow(account: "moi@exemple.fr", eventID: "e1", title: "Nouveau titre", startAt: now, endAt: now, updatedAt: now)
            renamed.startAt = ISO8601DateFormatter().date(from: "2026-11-20T10:00:00Z")!
            renamed.endAt = renamed.startAt.addingTimeInterval(1_800)
            let created = CalendarEventRow(account: "moi@exemple.fr", eventID: "e9", title: "Créé", startAt: renamed.startAt, endAt: renamed.endAt, updatedAt: now)
            try calendar.applyGoogle(account: "moi@exemple.fr", changed: [renamed, created], cancelled: [], at: later.addingTimeInterval(5))
            return (Data(old.utf8), 200)
        })
        try await sync.sync(account: "moi@exemple.fr", accessToken: "a1", store: calendar, now: later)
        let rows = try calendar.allEvents()
        #expect(Set(rows.map(\.eventID)) == ["e1", "e9"])
        #expect(rows.first { $0.eventID == "e1" }?.title == "Nouveau titre")
    }

    @Test func aRefusedTokenIsAnError() async throws {
        let calendar = CalendarStore(try AppDatabase.inMemory())
        await #expect(throws: GoogleError.self) {
            try await CalendarSync(fetch: { _ in (Data(#"{"error":{"code":401}}"#.utf8), 401) })
                .sync(account: "moi@exemple.fr", accessToken: "périmé", store: calendar, now: Date())
        }
    }
}

final class PageQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var pages: [String]
    init(_ pages: [String]) { self.pages = pages }
    func next() -> String { lock.withLock { pages.isEmpty ? #"{"items":[]}"# : pages.removeFirst() } }
}
