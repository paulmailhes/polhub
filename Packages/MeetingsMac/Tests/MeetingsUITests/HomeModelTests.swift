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
}
