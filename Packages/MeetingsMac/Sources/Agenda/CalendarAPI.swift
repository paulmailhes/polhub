import Domain
import Foundation
import Persistence

/// The Google Calendar API, version 3: the events of the primary calendar.
public enum CalendarAPI {
    public struct Page: Sendable {
        public var events: [CalendarEventRow]
        public var cancelled: [String]
        public var nextPageToken: String?
    }

    public static func eventsRequest(accessToken: String, from: Date, to: Date, pageToken: String?) -> URLRequest {
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        let format = ISO8601DateFormatter()
        components.queryItems = [
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "250"),
            URLQueryItem(name: "timeMin", value: format.string(from: from)),
            URLQueryItem(name: "timeMax", value: format.string(from: to)),
        ] + (pageToken.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    public static func page(from data: Data, account: String) throws -> Page {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw GoogleError.badAnswer }
        var page = Page(events: [], cancelled: [], nextPageToken: json["nextPageToken"] as? String)
        for item in json["items"] as? [[String: Any]] ?? [] {
            guard let id = item["id"] as? String else { continue }
            if item["status"] as? String == "cancelled" {
                page.cancelled.append(id)
                continue
            }
            if let event = event(from: item, account: account) { page.events.append(event) }
        }
        return page
    }

    /// One event of Google's answer; `nil` without an id or dates.
    static func event(from item: [String: Any], account: String) -> CalendarEventRow? {
        guard let id = item["id"] as? String, let (start, allDay) = date(item["start"]), let (end, _) = date(item["end"]) else { return nil }
        let video = ((item["conferenceData"] as? [String: Any])?["entryPoints"] as? [[String: Any]])?
            .first { $0["entryPointType"] as? String == "video" }?["uri"] as? String
        let link = (item["hangoutLink"] as? String) ?? video
        let attendees = (item["attendees"] as? [[String: Any]] ?? []).compactMap { guest -> Attendee? in
            guard let email = guest["email"] as? String else { return nil }
            return Attendee(email: email, name: guest["displayName"] as? String, response: guest["responseStatus"] as? String,
                            isSelf: guest["self"] as? Bool ?? false, isOrganizer: guest["organizer"] as? Bool ?? false,
                            isResource: guest["resource"] as? Bool ?? email.hasSuffix("resource.calendar.google.com"))
        }
        let title = (item["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CalendarEventRow(
            account: account, eventID: id, recurringEventID: item["recurringEventId"] as? String,
            title: title?.isEmpty == false ? title! : "(sans titre)", startAt: start, endAt: end, allDay: allDay,
            meetCode: link.flatMap { MeetLink.parse($0)?.code }, location: item["location"] as? String,
            htmlLink: item["htmlLink"] as? String, organizer: (item["organizer"] as? [String: Any])?["email"] as? String,
            attendees: attendees, updatedAt: Date()
        )
    }

    /// `{"dateTime": …}` or, for a whole day, `{"date": "2026-11-14"}` (a local day).
    static func date(_ value: Any?) -> (Date, Bool)? {
        guard let value = value as? [String: Any] else { return nil }
        if let text = value["dateTime"] as? String {
            let format = ISO8601DateFormatter()
            if let date = format.date(from: text) { return (date, false) }
            format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return format.date(from: text).map { ($0, false) }
        }
        if let text = value["date"] as? String {
            let format = DateFormatter()
            format.locale = Locale(identifier: "en_US_POSIX")
            format.timeZone = .current
            format.dateFormat = "yyyy-MM-dd"
            return format.date(from: text).map { ($0, true) }
        }
        return nil
    }
}

/// One account's primary calendar, read again over the whole window at each sync: what Google no
/// longer has goes (plan of 13/11: simpler and sturdier than Google's incremental tokens).
public struct CalendarSync: Sendable {
    public static let past: TimeInterval = 180 * 86_400
    public static let future: TimeInterval = 60 * 86_400
    let fetch: @Sendable (URLRequest) async throws -> (Data, Int)

    public init(fetch: @escaping @Sendable (URLRequest) async throws -> (Data, Int) = CalendarSync.live) {
        self.fetch = fetch
    }

    public static let live: @Sendable (URLRequest) async throws -> (Data, Int) = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    public func sync(account: String, accessToken: String, store: CalendarStore, now: Date) async throws {
        let from = now.addingTimeInterval(-Self.past), to = now.addingTimeInterval(Self.future)
        var events: [CalendarEventRow] = []
        var cancelled: [String] = []
        var pageToken: String?
        repeat {
            let (data, status) = try await fetch(CalendarAPI.eventsRequest(accessToken: accessToken, from: from, to: to, pageToken: pageToken))
            guard status == 200 else { throw status == 401 ? GoogleError.expired : GoogleError.http(status) }
            let page = try CalendarAPI.page(from: data, account: account)
            events += page.events
            cancelled += page.cancelled
            pageToken = page.nextPageToken
        } while pageToken != nil
        let seen = Set(events.map(\.eventID))
        let gone = try store.allEvents().filter { $0.account == account.lowercased() && $0.startAt >= from && $0.startAt < to && !seen.contains($0.eventID) }
        try store.applyGoogle(account: account, changed: events, cancelled: cancelled + gone.map(\.eventID), at: now)
        try store.recordSync(email: account, syncToken: nil, error: nil, at: now)
    }
}

/// Access tokens, refreshed from the Keychain's refresh tokens.
public actor GoogleSession {
    let config: @Sendable () throws -> GoogleClientConfig
    let vault: any TokenVault
    let fetch: @Sendable (URLRequest) async throws -> (Data, Int)
    private var cache: [String: (token: String, until: Date)] = [:]
    /// What each account granted, from its last token (14/11: read only before, read and write since).
    private var granted: [String: String] = [:]

    public init(config: @escaping @Sendable () throws -> GoogleClientConfig = GoogleClientConfig.load, vault: any TokenVault = KeychainVault(),
                fetch: @escaping @Sendable (URLRequest) async throws -> (Data, Int) = CalendarSync.live) {
        self.config = config
        self.vault = vault
        self.fetch = fetch
    }

    public func accessToken(for email: String, now: Date = Date()) async throws -> String {
        if let cached = cache[email], cached.until > now.addingTimeInterval(60) { return cached.token }
        guard let refresh = vault.refreshToken(for: email) else { throw GoogleError.expired }
        let (data, _) = try await fetch(GoogleOAuth.refreshRequest(config: try config(), refreshToken: refresh))
        let tokens = try GoogleOAuth.tokens(from: data)
        cache[email] = (tokens.accessToken, now.addingTimeInterval(TimeInterval(tokens.expiresIn)))
        if let scope = tokens.scope { granted[email] = scope }
        return tokens.accessToken
    }

    /// Whether the account can be written to; `nil` before its first token.
    public func canWrite(_ email: String) -> Bool? {
        granted[email].map { GoogleOAuth.canWrite(scope: $0) }
    }

    /// The browser opens on Google's page; the account comes back connected. Returns its address.
    public func connect(open: @escaping @Sendable (URL) -> Void, loginHint: String? = nil, timeout: TimeInterval = 300) async throws -> String {
        let config = try config()
        let receiver = try await LoopbackReceiver.start()
        let verifier = PKCE.verifier(), state = UUID().uuidString
        open(GoogleOAuth.authorizationURL(config: config, redirect: receiver.redirect, challenge: PKCE.challenge(for: verifier), state: state, loginHint: loginHint))
        let line = try await receiver.nextRequestLine(timeout: timeout)
        let code = try GoogleOAuth.code(fromRequestLine: line, state: state)
        let (data, _) = try await fetch(GoogleOAuth.exchangeRequest(config: config, code: code, verifier: verifier, redirect: receiver.redirect))
        let tokens = try GoogleOAuth.tokens(from: data)
        guard let email = tokens.email, let refresh = tokens.refreshToken else { throw GoogleError.badAnswer }
        try vault.save(refreshToken: refresh, for: email)
        cache[email] = (tokens.accessToken, Date().addingTimeInterval(TimeInterval(tokens.expiresIn)))
        if let scope = tokens.scope { granted[email] = scope }
        return email
    }

    public func forget(_ email: String) {
        cache[email] = nil
        vault.remove(for: email)
    }
}
