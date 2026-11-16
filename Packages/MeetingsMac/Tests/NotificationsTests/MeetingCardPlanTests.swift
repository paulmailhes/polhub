import Domain
import Foundation
import Persistence
import Testing
@testable import Notifications

/// The card that stays at the top right before a meeting with a Meet, with « Rejoindre » (Paul, 16/11: « une
/// notification qui reste en haut à droite… deux minutes avant… avec un bouton rejoindre »).
@Suite struct MeetingCardPlanTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)

    func event(_ id: String, inMinutes: Double, minutes: Double = 30, code: String? = "abc-defg-hij", allDay: Bool = false,
               response: String? = "accepted", account: String = "paul@exemple.fr") -> CalendarEventRow {
        CalendarEventRow(account: account, eventID: id, title: "Point \(id)", startAt: now.addingTimeInterval(inMinutes * 60),
                         endAt: now.addingTimeInterval((inMinutes + minutes) * 60), allDay: allDay, meetCode: code, organizer: "client@ailleurs.fr",
                         attendees: [Attendee(email: account, response: response, isSelf: true)], updatedAt: now)
    }

    func due(_ events: [CalendarEventRow], minutes: Int = 2, closed: Set<String> = [], meeting: String? = nil, at date: Date? = nil) -> [String] {
        MeetingCardPlan.due(events, now: date ?? now, minutes: minutes, closed: closed, meetingCode: meeting).map(\.eventID)
    }

    /// From `minutes` before the start; not before.
    @Test func theCardComesTheChosenMinutesBefore() {
        #expect(due([event("a", inMinutes: 2)]) == ["a"])
        #expect(due([event("a", inMinutes: 2.5)]).isEmpty)
        #expect(due([event("a", inMinutes: 4)], minutes: 5) == ["a"])
        #expect(due([event("a", inMinutes: 0.5)], minutes: 1) == ["a"])
    }

    /// It stays after the start, ten minutes at most (Paul late, the card still there), never past the end.
    @Test func itStaysTenMinutesAfterTheStartAtMost() {
        #expect(due([event("a", inMinutes: -9)]) == ["a"])
        #expect(due([event("a", inMinutes: -10)]).isEmpty)
        #expect(due([event("court", inMinutes: -5, minutes: 4)]).isEmpty)
    }

    /// Only an event with a Meet, Paul attends (not declined, not a whole day).
    @Test func onlyAMeetPaulAttends() {
        let events = [event("salle", inMinutes: 1, code: nil), event("refuse", inMinutes: 1, response: "declined"),
                      event("journee", inMinutes: 1, allDay: true), event("visio", inMinutes: 1)]
        #expect(due(events) == ["visio"])
    }

    /// Closed with its cross, that occurrence never comes back; the next one of a series does.
    @Test func aClosedCardStaysClosed() {
        let today = event("serie", inMinutes: 1)
        var tomorrow = event("serie", inMinutes: 1 + 24 * 60)
        #expect(due([today], closed: [MeetingCardPlan.key(today)]).isEmpty)
        tomorrow.startAt = now.addingTimeInterval(24 * 3600 + 60)
        #expect(due([tomorrow], closed: [MeetingCardPlan.key(today)], at: now.addingTimeInterval(24 * 3600)) == ["serie"])
    }

    /// The meeting Polhub records or offers to record is the one Paul is in: no card for it. The next one, back to
    /// back, still comes.
    @Test func noCardForTheMeetingUnderWay() {
        let current = event("en-cours", inMinutes: -1, code: "abc-defg-hij")
        let next = event("suivante", inMinutes: 2, code: "xyz-uvwx-rst")
        #expect(due([current, next], meeting: "abc-defg-hij") == ["suivante"])
        #expect(due([current, next], meeting: "ABC-DEFG-HIJ") == ["suivante"])
    }

    /// The same event in two calendars is one card; the soonest first, three at most.
    @Test func oneCardPerEventTheSoonestFirst() {
        let copy = event("a", inMinutes: 1, account: "autre@exemple.fr")
        let events = [event("c", inMinutes: 2), event("a", inMinutes: 1), copy, event("b", inMinutes: 1.5), event("d", inMinutes: 0.2)]
        #expect(due(events) == ["d", "a", "b"])
    }

    /// « Dans 2 min », « Dans 1 min », « Maintenant », « Commencé il y a 3 min ».
    @Test func theCardSaysWhen() {
        let start = now
        #expect(MeetingCardPlan.when(start, now: now.addingTimeInterval(-110)) == "Dans 2 min")
        #expect(MeetingCardPlan.when(start, now: now.addingTimeInterval(-50)) == "Dans 1 min")
        #expect(MeetingCardPlan.when(start, now: now.addingTimeInterval(20)) == "Maintenant")
        #expect(MeetingCardPlan.when(start, now: now.addingTimeInterval(190)) == "Commencé il y a 3 min")
    }
}
