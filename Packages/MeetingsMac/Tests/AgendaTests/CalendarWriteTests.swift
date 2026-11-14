import Domain
import Foundation
import Persistence
import Testing
@testable import Agenda

/// Calendrier writes (Paul, 14/11): create, change and delete his events, sent to Google.
@Suite struct CalendarWriteTests {
    let paris = TimeZone(identifier: "Europe/Paris")!
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = paris
        return calendar
    }
    func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func json(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func aNewTimedEventWithAMeetAndGuests() throws {
        var draft = EventDraft.new(at: date(17, 10), calendar: calendar)
        draft.title = "Point maquette"
        draft.location = "Atelier"
        draft.notes = "Ordre du jour"
        draft.guests = ["camille@exemple.fr", "Jules@Atelier-Nord.fr"]
        #expect(draft.end == date(17, 11))
        let request = CalendarWrite.insertRequest(accessToken: "jeton", draft: draft, timeZone: paris, requestID: "demande-1")
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://www.googleapis.com/calendar/v3/calendars/primary/events?conferenceDataVersion=1&sendUpdates=all")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer jeton")
        let body = try json(request)
        #expect(body["summary"] as? String == "Point maquette" && body["location"] as? String == "Atelier" && body["description"] as? String == "Ordre du jour")
        #expect((body["start"] as? [String: String]) == ["dateTime": "2026-11-17T10:00:00+01:00", "timeZone": "Europe/Paris"])
        #expect((body["end"] as? [String: String]) == ["dateTime": "2026-11-17T11:00:00+01:00", "timeZone": "Europe/Paris"])
        #expect((body["attendees"] as? [[String: String]]) == [["email": "camille@exemple.fr"], ["email": "jules@atelier-nord.fr"]])
        let create = (body["conferenceData"] as? [String: Any])?["createRequest"] as? [String: Any]
        #expect(create?["requestId"] as? String == "demande-1")
        #expect((create?["conferenceSolutionKey"] as? [String: String]) == ["type": "hangoutsMeet"])
    }

    @Test func aWholeDayEndsTheDayAfterItsLastDay() throws {
        var draft = EventDraft.new(at: date(20, 9), calendar: calendar)
        draft.title = "Séminaire"
        draft.allDay = true
        draft.addMeet = false
        draft.end = date(21)
        let body = try json(CalendarWrite.insertRequest(accessToken: "jeton", draft: draft, timeZone: paris, requestID: "x"))
        #expect((body["start"] as? [String: String]) == ["date": "2026-11-20"])
        #expect((body["end"] as? [String: String]) == ["date": "2026-11-22"])
        #expect(body["conferenceData"] == nil)
        #expect(CalendarWrite.insertRequest(accessToken: "jeton", draft: draft, timeZone: paris, requestID: "x").url?.query == "sendUpdates=all")
    }

    @Test func anEditKeepsTheAnswersOfTheGuestsWhoStay() throws {
        let event = CalendarEventRow(account: "paul@exemple.fr", eventID: "e1", title: "Point", startAt: date(17, 10), endAt: date(17, 11),
                                     meetCode: "abc-defg-hij", organizer: "paul@exemple.fr",
                                     attendees: [Attendee(email: "paul@exemple.fr", response: "accepted", isSelf: true, isOrganizer: true),
                                                 Attendee(email: "camille@exemple.fr", response: "accepted"), Attendee(email: "jules@exemple.fr", response: "needsAction")],
                                     updatedAt: date(1))
        var draft = EventDraft(event: event, notes: "Notes", calendar: calendar)
        #expect(draft.guests == ["camille@exemple.fr", "jules@exemple.fr"] && draft.addMeet && draft.notes == "Notes")
        draft.guests = ["camille@exemple.fr", "zoe@exemple.fr"]
        draft.title = "Point déplacé"
        let request = CalendarWrite.patchRequest(accessToken: "jeton", event: event, draft: draft, timeZone: paris, requestID: "x")
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.absoluteString == "https://www.googleapis.com/calendar/v3/calendars/primary/events/e1?sendUpdates=all")
        let body = try json(request)
        #expect((body["attendees"] as? [[String: String]]) == [
            ["email": "paul@exemple.fr", "responseStatus": "accepted"], ["email": "camille@exemple.fr", "responseStatus": "accepted"], ["email": "zoe@exemple.fr"],
        ])
        #expect(body["conferenceData"] == nil)
    }

    @Test func aWholeDayEventReadsBackItsLastDay() {
        let event = CalendarEventRow(account: "paul@exemple.fr", eventID: "e2", title: "Salon", startAt: date(20), endAt: date(22), allDay: true, updatedAt: date(1))
        let draft = EventDraft(event: event, notes: "", calendar: calendar)
        #expect(draft.allDay && draft.start == date(20) && draft.end == date(21))
    }

    @Test func deleteAndRead() {
        let delete = CalendarWrite.deleteRequest(accessToken: "jeton", eventID: "e1")
        #expect(delete.httpMethod == "DELETE" && delete.url?.absoluteString == "https://www.googleapis.com/calendar/v3/calendars/primary/events/e1?sendUpdates=all")
        #expect(CalendarWrite.getRequest(accessToken: "jeton", eventID: "e1").url?.absoluteString == "https://www.googleapis.com/calendar/v3/calendars/primary/events/e1")
    }

    @Test func googlesAnswerBecomesAnEvent() throws {
        let data = Data("""
            {"id": "neuf", "status": "confirmed", "summary": "Point maquette", "htmlLink": "https://www.google.com/calendar/event?eid=x",
             "start": {"dateTime": "2026-11-17T10:00:00+01:00"}, "end": {"dateTime": "2026-11-17T11:00:00+01:00"},
             "hangoutLink": "https://meet.google.com/abc-defg-hij", "organizer": {"email": "paul@exemple.fr", "self": true}}
            """.utf8)
        let event = try #require(try CalendarWrite.event(from: data, account: "paul@exemple.fr"))
        #expect(event.eventID == "neuf" && event.title == "Point maquette" && event.meetCode == "abc-defg-hij" && event.startAt == date(17, 10))
    }

    @Test func aReadOnlyConnectionAsksToReconnect() {
        let scope = Data(#"{"error": {"code": 403, "status": "PERMISSION_DENIED", "details": [{"reason": "ACCESS_TOKEN_SCOPE_INSUFFICIENT"}]}}"#.utf8)
        #expect(CalendarWrite.error(status: 403, data: scope) == .needsWrite)
        #expect(CalendarWrite.error(status: 403, data: Data(#"{"error": {"errors": [{"reason": "forbiddenForNonOrganizer"}]}}"#.utf8)) == .notOrganizer)
        #expect(CalendarWrite.error(status: 401, data: Data()) == .expired)
        #expect(CalendarWrite.error(status: 500, data: Data()) == .http(500))
        #expect(GoogleOAuth.scopes.contains("https://www.googleapis.com/auth/calendar.events"))
        #expect(GoogleOAuth.canWrite(scope: "openid https://www.googleapis.com/auth/calendar.events email"))
        #expect(!GoogleOAuth.canWrite(scope: "openid https://www.googleapis.com/auth/calendar.readonly"))
    }

    @Test func onlyTheOrganizersCopyIsEditable() {
        let mine = CalendarEventRow(account: "paul@exemple.fr", eventID: "a", title: "", startAt: date(1), endAt: date(2), organizer: "Paul@Exemple.fr", updatedAt: date(1))
        let invitation = CalendarEventRow(account: "paul@exemple.fr", eventID: "b", title: "", startAt: date(1), endAt: date(2), organizer: "client@ailleurs.fr", updatedAt: date(1))
        let alone = CalendarEventRow(account: "paul@exemple.fr", eventID: "c", title: "", startAt: date(1), endAt: date(2), updatedAt: date(1))
        #expect(EventCopies.canEdit(mine) && !EventCopies.canEdit(invitation) && EventCopies.canEdit(alone))
    }
}
