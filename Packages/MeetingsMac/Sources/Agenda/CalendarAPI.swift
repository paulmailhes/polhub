import Domain
import Foundation
import GoogleKit
import Persistence

extension CalendarEventRow {
    /// The title the base keeps for an event Google gave without one (lot 10, 20/11): a format, never reworded; the code
    /// asks `isUntitled`, never compares the words.
    public static let untitledTitle = "(sans titre)"

    /// An event without a title of its own.
    public var isUntitled: Bool { title == Self.untitledTitle }
}

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
            title: title?.isEmpty == false ? title! : CalendarEventRow.untitledTitle, startAt: start, endAt: end, allDay: allDay,
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
    /// The window, shared with the agents' helper (`CalendarWindow`, 16/11).
    public static let past = CalendarWindow.past
    public static let future = CalendarWindow.future
    let fetch: @Sendable (URLRequest) async throws -> (Data, Int)

    public init(fetch: @escaping @Sendable (URLRequest) async throws -> (Data, Int) = CalendarSync.live) {
        self.fetch = fetch
    }

    public static let live: @Sendable (URLRequest) async throws -> (Data, Int) = GoogleHTTP.live

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
        // What hub wrote since this sync started is newer than what it read (review of 14/11).
        let gone = try store.allEvents().filter {
            $0.account == account.lowercased() && $0.startAt >= from && $0.startAt < to && !seen.contains($0.eventID) && $0.updatedAt <= now
        }
        try store.applyGoogle(account: account, changed: events, cancelled: cancelled + gone.map(\.eventID), at: now, keepingNewerThan: now)
        try store.recordSync(email: account, syncToken: nil, error: nil, at: now)
    }
}
