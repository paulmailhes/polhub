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

    /// 15/11: two columns that each stack their cards, so a short card never leaves a hole beside a long one;
    /// every card once, in either layout.
    @Test func everyCardOnceInEitherLayout() {
        let all = Set(HomeModel.Part.allCases)
        #expect(HomeModel.columns.count == 2)
        #expect(HomeModel.columns.flatMap { $0 }.count == all.count && Set(HomeModel.columns.flatMap { $0 }) == all)
        #expect(HomeModel.single.count == all.count && Set(HomeModel.single) == all)
        #expect(HomeModel.columns[0].first == .today && HomeModel.columns[1].first == .urgent)
    }

    @Test func theStartIsSaidPlainly() {
        #expect(HomeModel.when(event("a", 12), now: now) == "dans 12 min")
        #expect(HomeModel.when(event("b", -5), now: now) == "en cours")
        #expect(HomeModel.when(event("c", 150), now: now).hasPrefix("à "))
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
