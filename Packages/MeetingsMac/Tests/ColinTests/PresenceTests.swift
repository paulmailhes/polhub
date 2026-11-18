import Foundation
import Testing
@testable import Colin

/// When Paul comes back (18/11): the first presence of the day, or three hours without one.
@Suite struct PresenceTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func theVeryFirstPresenceIsAReturnWithNothingBeforeIt() {
        let seen = Presence.seen(Presence.State(), at: at(18, 9, 4), calendar: calendar)
        #expect(seen.returned)
        #expect(seen.awayMinutes == nil)
        #expect(seen.state == Presence.State(lastSeen: at(18, 9, 4), since: nil, preparedAt: at(18, 9, 4)))
    }

    @Test func theFirstPresenceOfTheDayIsAReturn() {
        // Seen at 23:50, back at 0:10: twenty minutes, and another day.
        let before = Presence.State(lastSeen: at(17, 23, 50), since: at(16, 18), preparedAt: at(17, 9))
        let seen = Presence.seen(before, at: at(18, 0, 10), calendar: calendar)
        #expect(seen.returned)
        #expect(seen.awayMinutes == 20)
        // « Depuis » is the last time he was there.
        #expect(seen.state == Presence.State(lastSeen: at(18, 0, 10), since: at(17, 23, 50), preparedAt: at(18, 0, 10)))
    }

    @Test func threeHoursAwayIsAReturnTwoAreNot() {
        let morning = Presence.State(lastSeen: at(18, 10), since: at(17, 19, 40), preparedAt: at(18, 9, 4))
        let soon = Presence.seen(morning, at: at(18, 12), calendar: calendar)
        #expect(!soon.returned && soon.awayMinutes == nil)
        // Nothing of « Le point » moves: only the last time he was seen.
        #expect(soon.state == Presence.State(lastSeen: at(18, 12), since: at(17, 19, 40), preparedAt: at(18, 9, 4)))
        let late = Presence.seen(morning, at: at(18, 13), calendar: calendar)
        #expect(late.returned && late.awayMinutes == 180)
        #expect(late.state == Presence.State(lastSeen: at(18, 13), since: at(18, 10), preparedAt: at(18, 13)))
        #expect(!Presence.seen(morning, at: at(18, 12, 59), calendar: calendar).returned)
        #expect(Presence.awayAfter == 3 * 3_600)
    }

    @Test func aClockThatWentBackIsNoReturn() {
        let state = Presence.State(lastSeen: at(18, 10), since: nil, preparedAt: at(18, 9))
        let seen = Presence.seen(state, at: at(18, 9, 30), calendar: calendar)
        #expect(!seen.returned)
        #expect(seen.state.lastSeen == at(18, 9, 30))
    }

    @Test func theStateIsKeptAsItIs() throws {
        let state = Presence.State(lastSeen: at(18, 10), since: at(17, 19, 40), preparedAt: at(18, 9, 4))
        #expect(try JSONDecoder().decode(Presence.State.self, from: JSONEncoder().encode(state)) == state)
        #expect(try JSONDecoder().decode(Presence.State.self, from: Data("{}".utf8)) == Presence.State())
    }
}
