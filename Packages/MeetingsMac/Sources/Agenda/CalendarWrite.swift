import Domain
import Foundation
import GoogleKit
import Persistence

/// An event as Paul fills it in Polhub's editor (14/11).
public struct EventDraft: Equatable, Sendable {
    public var title: String
    public var start: Date
    /// For a whole day, the last day (included); otherwise the end time.
    public var end: Date
    public var allDay: Bool
    public var location: String
    public var notes: String
    /// The guests' addresses, Paul excluded.
    public var guests: [String]
    /// A Google Meet link: made for a new event, kept for an existing one.
    public var addMeet: Bool

    public init(title: String = "", start: Date, end: Date, allDay: Bool = false, location: String = "", notes: String = "",
                guests: [String] = [], addMeet: Bool = true) {
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
        self.location = location
        self.notes = notes
        self.guests = guests
        self.addMeet = addMeet
    }

    /// A new event at that time, an hour long, with a Meet, as Google makes them.
    public static func new(at date: Date, calendar: Calendar = .current) -> EventDraft {
        EventDraft(start: date, end: calendar.date(byAdding: .hour, value: 1, to: date) ?? date.addingTimeInterval(3_600))
    }

    /// An existing event, to change.
    public init(event: CalendarEventRow, notes: String, calendar: Calendar = .current) {
        let lastDay = event.allDay ? (calendar.date(byAdding: .day, value: -1, to: event.endAt) ?? event.endAt) : event.endAt
        self.init(title: event.title == "(sans titre)" ? "" : event.title, start: event.startAt, end: max(event.startAt, lastDay),
                  allDay: event.allDay, location: event.location ?? "", notes: notes, guests: event.guests.map(\.email),
                  addMeet: event.meetCode != nil)
    }
}

/// What Polhub reads from Google before changing an event: its description and Google's own list of guests
/// (optional ones, comments, « +N »), kept as Google wrote it.
public struct EventDetails: Equatable, Sendable {
    public var notes: String
    /// The `attendees` array, as JSON.
    public var attendees: Data?

    public init(notes: String, attendees: Data?) {
        self.notes = notes
        self.attendees = attendees
    }
}

/// Polhub writes to the primary calendar of the event's account; Google sends the invitations.
public enum CalendarWrite {
    static let base = "https://www.googleapis.com/calendar/v3/calendars/primary/events"

    public static func insertRequest(accessToken: String, draft: EventDraft, timeZone: TimeZone, requestID: String) -> URLRequest {
        request("POST", path: "", query: draft.addMeet ? "conferenceDataVersion=1&sendUpdates=all" : "sendUpdates=all", accessToken: accessToken,
                body: body(draft, existing: nil, timeZone: timeZone, requestID: requestID))
    }

    /// The changes of an event: only the fields Paul changed (review of 14/11, Important 1 and 2); the guests
    /// who stay keep what Google holds for them; a Meet is made only if it had none.
    public static func patchRequest(accessToken: String, event: CalendarEventRow, original: EventDraft, draft: EventDraft,
                                    details: EventDetails?, timeZone: TimeZone, requestID: String) -> URLRequest {
        let addsMeet = draft.addMeet && event.meetCode == nil
        return request("PATCH", path: "/" + escaped(event.eventID), query: addsMeet ? "conferenceDataVersion=1&sendUpdates=all" : "sendUpdates=all",
                       accessToken: accessToken,
                       body: patchBody(event: event, original: original, draft: draft, details: details, timeZone: timeZone, requestID: requestID))
    }

    public static func deleteRequest(accessToken: String, eventID: String) -> URLRequest {
        request("DELETE", path: "/" + escaped(eventID), query: "sendUpdates=all", accessToken: accessToken, body: nil)
    }

    public static func getRequest(accessToken: String, eventID: String) -> URLRequest {
        request("GET", path: "/" + escaped(eventID), query: nil, accessToken: accessToken, body: nil)
    }

    /// Google's answer to a creation or a change.
    public static func event(from data: Data, account: String) throws -> CalendarEventRow? {
        guard let item = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw GoogleError.badAnswer }
        return CalendarAPI.event(from: item, account: account)
    }

    /// The description of an event, read before changing it.
    public static func notes(from data: Data) -> String {
        ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["description"] as? String) ?? ""
    }

    /// The description and Google's own list of guests, read before a change.
    public static func details(from data: Data) -> EventDetails {
        let item = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let attendees = (item["attendees"] as? [[String: Any]]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        return EventDetails(notes: item["description"] as? String ?? "", attendees: attendees)
    }

    /// What a refusal means for Paul.
    public static func error(status: Int, data: Data) -> GoogleError {
        let text = String(decoding: data, as: UTF8.self)
        switch status {
        case 401: return .expired
        case 403 where text.contains("ACCESS_TOKEN_SCOPE_INSUFFICIENT") || text.contains("insufficientPermissions"): return .needsWrite
        case 403 where text.contains("forbiddenForNonOrganizer") || text.contains("forbidden"): return .notOrganizer
        default: return .http(status)
        }
    }

    static func body(_ draft: EventDraft, existing: CalendarEventRow?, timeZone: TimeZone, requestID: String) -> [String: Any] {
        var body: [String: Any] = [
            "summary": draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            "location": draft.location,
            "description": draft.notes,
        ]
        let (start, end) = times(draft, timeZone: timeZone)
        body["start"] = start
        body["end"] = end
        // Paul and the rooms stay as they were; the guests who stay keep their answer.
        let previous = Dictionary((existing?.attendees ?? []).map { ($0.email, $0) }, uniquingKeysWith: { first, _ in first })
        let kept = (existing?.attendees ?? []).filter { $0.isSelf || $0.isResource }
        let wanted = draft.guests.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var seen = Set<String>()
        let guests = (kept.map(\.email) + wanted).filter { seen.insert($0).inserted }
        if !guests.isEmpty || existing?.attendees.isEmpty == false {
            body["attendees"] = guests.map { email -> [String: String] in
                var guest = ["email": email]
                if let response = previous[email]?.response { guest["responseStatus"] = response }
                return guest
            }
        }
        if draft.addMeet && existing?.meetCode == nil {
            body["conferenceData"] = ["createRequest": ["requestId": requestID, "conferenceSolutionKey": ["type": "hangoutsMeet"]]]
        }
        return body
    }

    /// Google's start and end: a day (the end the day after the last one) or a time in the zone.
    static func times(_ draft: EventDraft, timeZone: TimeZone) -> (start: [String: Any], end: [String: Any]) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if draft.allDay {
            let after = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(draft.start, draft.end))) ?? draft.end
            return (["date": day(draft.start, timeZone: timeZone)], ["date": day(after, timeZone: timeZone)])
        }
        return (["dateTime": time(draft.start, timeZone: timeZone), "timeZone": timeZone.identifier],
                ["dateTime": time(max(draft.start, draft.end), timeZone: timeZone), "timeZone": timeZone.identifier])
    }

    static func patchBody(event: CalendarEventRow, original: EventDraft, draft: EventDraft, details: EventDetails?,
                          timeZone: TimeZone, requestID: String) -> [String: Any] {
        var body: [String: Any] = [:]
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title != original.title.trimmingCharacters(in: .whitespacesAndNewlines) { body["summary"] = title }
        if draft.location != original.location { body["location"] = draft.location }
        if draft.notes != original.notes { body["description"] = draft.notes }
        if draft.allDay != original.allDay || draft.start != original.start || draft.end != original.end {
            var (start, end) = times(draft, timeZone: timeZone)
            // A whole day becomes a time, or the other way: the other key goes (Google merges objects in a PATCH).
            if draft.allDay != original.allDay {
                let other = draft.allDay ? "dateTime" : "date"
                start[other] = NSNull()
                end[other] = NSNull()
            }
            body["start"] = start
            body["end"] = end
        }
        let wanted = normalized(draft.guests)
        if Set(wanted) != Set(normalized(original.guests)) {
            body["attendees"] = attendees(wanted, event: event, google: details?.attendees)
        }
        if draft.addMeet && event.meetCode == nil {
            body["conferenceData"] = ["createRequest": ["requestId": requestID, "conferenceSolutionKey": ["type": "hangoutsMeet"]]]
        }
        return body
    }

    static func normalized(_ emails: [String]) -> [String] {
        var seen = Set<String>()
        return emails.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The new list: Google's entries for Paul, the rooms and the guests who stay, as Google holds them; then the
    /// new guests. Without Google's list, the stored answers.
    static func attendees(_ wanted: [String], event: CalendarEventRow, google: Data?) -> [[String: Any]] {
        if let google, let raw = try? JSONSerialization.jsonObject(with: google) as? [[String: Any]] {
            let kept = raw.filter { entry in
                let email = (entry["email"] as? String)?.lowercased() ?? ""
                return entry["self"] as? Bool == true || entry["organizer"] as? Bool == true || entry["resource"] as? Bool == true
                    || wanted.contains(email)
            }
            let present = Set(kept.compactMap { ($0["email"] as? String)?.lowercased() })
            return kept + wanted.filter { !present.contains($0) }.map { ["email": $0] }
        }
        let previous = Dictionary(event.attendees.map { ($0.email, $0) }, uniquingKeysWith: { first, _ in first })
        let fixed = event.attendees.filter { $0.isSelf || $0.isResource }.map(\.email)
        var seen = Set<String>()
        return (fixed + wanted).filter { seen.insert($0).inserted }.map { email -> [String: Any] in
            var guest: [String: Any] = ["email": email]
            if let response = previous[email]?.response { guest["responseStatus"] = response }
            return guest
        }
    }

    static func request(_ method: String, path: String, query: String?, accessToken: String, body: [String: Any]?) -> URLRequest {
        var request = URLRequest(url: URL(string: base + path + (query.map { "?" + $0 } ?? ""))!)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }
        return request
    }

    static func escaped(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? id
    }

    static func day(_ date: Date, timeZone: TimeZone) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = timeZone
        format.dateFormat = "yyyy-MM-dd"
        return format.string(from: date)
    }

    static func time(_ date: Date, timeZone: TimeZone) -> String {
        let format = ISO8601DateFormatter()
        format.timeZone = timeZone
        format.formatOptions = [.withInternetDateTime]
        return format.string(from: date)
    }
}

extension EventCopies {
    /// Paul changes the events he organizes (or alone in his calendar); an invitation belongs to its organizer.
    public static func canEdit(_ event: CalendarEventRow) -> Bool {
        guard let organizer = event.organizer?.lowercased() else { return true }
        return organizer == event.account.lowercased()
    }
}

extension GoogleSession {
    /// Sends a request with the account's token; a refusal says why, in French.
    public func send(_ build: @Sendable (String) -> URLRequest, for email: String) async throws -> Data {
        try await send(build, for: email, mapping: { CalendarWrite.error(status: $0, data: $1) })
    }
}
