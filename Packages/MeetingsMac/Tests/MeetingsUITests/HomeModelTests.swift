import Foundation
import Persistence
import Testing
@testable import MeetingsUI

/// Accueil opens on the next event, to join it in one click (Paul, 14/11).
@Suite struct HomeModelTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)

    func event(_ id: String, _ startMinutes: Double, _ minutes: Double = 30, allDay: Bool = false, declined: Bool = false) -> CalendarEventRow {
        CalendarEventRow(account: "moi@exemple.fr", eventID: id, title: id, startAt: now.addingTimeInterval(startMinutes * 60),
                         endAt: now.addingTimeInterval((startMinutes + minutes) * 60), allDay: allDay,
                         attendees: [Attendee(email: "moi@exemple.fr", response: declined ? "declined" : "accepted", isSelf: true)], updatedAt: now)
    }

    @Test func theEventUnderWayComesBeforeTheNextOne() {
        let events = [event("plus-tard", 90), event("en-cours", -10), event("fini", -60)]
        #expect(HomeModel.next(events, now: now)?.eventID == "en-cours")
    }

    @Test func notTheWholeDayOnesNorTheDeclinedOnes() {
        let events = [event("journee", -60, 24 * 60, allDay: true), event("refuse", 10, declined: true), event("ensuite", 40)]
        #expect(HomeModel.next(events, now: now)?.eventID == "ensuite")
    }

    @Test func nothingWhenTheDayIsOver() {
        #expect(HomeModel.next([event("fini", -60)], now: now) == nil)
    }

    @Test func theStartIsSaidPlainly() {
        #expect(HomeModel.when(event("a", 12), now: now) == "dans 12 min")
        #expect(HomeModel.when(event("b", -5), now: now) == "en cours")
        #expect(HomeModel.when(event("c", 150), now: now).hasPrefix("à "))
    }

    // MARK: - « Aujourd'hui » (18/11)

    /// Wednesday 18/11/2026, in Paris.
    var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.firstWeekday = 2
        return calendar
    }

    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        paris.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func meeting(_ id: String, day: Int, hour: Int, minute: Int = 0, allDay: Bool = false, declined: Bool = false) -> CalendarEventRow {
        CalendarEventRow(account: "moi@exemple.fr", eventID: id, title: id, startAt: at(day, hour, minute), endAt: at(day, hour, minute).addingTimeInterval(allDay ? 86_400 : 1_800),
                         allDay: allDay, attendees: [Attendee(email: "moi@exemple.fr", response: declined ? "declined" : "accepted", isSelf: true)], updatedAt: at(1, 0))
    }

    @Test func todayIsWhatIsLeftOfTheDay() {
        let events = [
            meeting("fini", day: 18, hour: 8), meeting("en-cours", day: 18, hour: 9, minute: 45), meeting("tantot", day: 18, hour: 16, minute: 30),
            meeting("refuse", day: 18, hour: 14, declined: true), meeting("journee", day: 18, hour: 0, allDay: true), meeting("demain", day: 19, hour: 10),
        ]
        // The whole-day ones first, then by the hour; what is over, or declined, is gone.
        #expect(HomeModel.today(events, now: at(18, 10), calendar: paris).map(\.eventID) == ["journee", "en-cours", "tantot"])
        #expect(HomeModel.today(events, now: at(18, 17, 30), calendar: paris).map(\.eventID) == ["journee"])
    }

    @Test func tomorrowIsSaidWhenTheDayIsOver() {
        let events = [meeting("fini", day: 18, hour: 8), meeting("refuse", day: 19, hour: 9, declined: true), meeting("demain", day: 19, hour: 10),
                      meeting("journee-de-demain", day: 19, hour: 0, allDay: true), meeting("plus-tard", day: 20, hour: 9)]
        let evening = at(18, 19)
        #expect(HomeModel.today(events, now: evening, calendar: paris).isEmpty)
        let next = HomeModel.upcoming(events, now: evening, calendar: paris)
        #expect(next?.eventID == "demain")
        #expect(HomeModel.dayLabel(at(19, 10), now: evening, calendar: paris) == "Demain 10:00")
        #expect(HomeModel.dayLabel(at(20, 9, 5), now: evening, calendar: paris) == "Vendredi 9:05")
        #expect(HomeModel.dayLabel(at(18, 21), now: evening, calendar: paris) == "Aujourd'hui 21:00")
        // Nothing to come at all.
        #expect(HomeModel.upcoming([meeting("fini", day: 18, hour: 8)], now: evening, calendar: paris) == nil)
    }

    /// 14/11: « Nouveau rendez-vous » starts at the next half hour.
    @Test func aNewEventStartsAtTheNextHalfHour() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let ten = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 10, minute: 10, second: 42))!
        #expect(calendar.dateComponents([.hour, .minute, .second], from: EventEditor.nextSlot(after: ten, calendar: calendar)) == DateComponents(hour: 10, minute: 30, second: 0))
        let late = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 10, minute: 40))!
        #expect(calendar.dateComponents([.hour, .minute], from: EventEditor.nextSlot(after: late, calendar: calendar)) == DateComponents(hour: 11, minute: 0))
    }
}
