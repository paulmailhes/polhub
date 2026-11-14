import Domain
import Foundation
import Persistence
import Testing
@testable import Notifications

/// Polhub's notifications (Paul, 14/11): reminders before an event, new events, a meeting not recorded.
@Suite struct NotificationPlanTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)

    func event(_ id: String, inMinutes: Double, minutes: Double = 30, code: String? = "abc-defg-hij", allDay: Bool = false,
               response: String? = "accepted", account: String = "paul@exemple.fr", organizer: String? = "client@ailleurs.fr") -> CalendarEventRow {
        CalendarEventRow(account: account, eventID: id, title: "Point \(id)", startAt: now.addingTimeInterval(inMinutes * 60),
                         endAt: now.addingTimeInterval((inMinutes + minutes) * 60), allDay: allDay, meetCode: code, organizer: organizer,
                         attendees: [Attendee(email: account, response: response, isSelf: true)], updatedAt: now)
    }

    @Test func remindersComeTenAndOneMinuteBeforeEachEvent() {
        let plan = NotificationPlan.reminders(for: [event("a", inMinutes: 60), event("b", inMinutes: 5)], now: now, minutes: [10, 1], meetOnly: false)
        #expect(plan.map(\.fireDate) == [now.addingTimeInterval(4 * 60), now.addingTimeInterval(50 * 60), now.addingTimeInterval(59 * 60)])
        let first = try? #require(plan.first)
        #expect(first?.title == "Point b" && first?.body == "Dans 1 min · Google Meet" && first?.joinable == true)
        #expect(plan[1].body == "Dans 10 min · Google Meet")
        #expect(Set(plan.map(\.id)).count == plan.count)
    }

    @Test func noReminderForWholeDaysDeclinedOrPastEventsAndMeetOnlyIsRespected() {
        let events = [event("journee", inMinutes: 120, allDay: true), event("refuse", inMinutes: 30, response: "declined"),
                      event("passe", inMinutes: -5), event("salle", inMinutes: 45, code: nil)]
        #expect(NotificationPlan.reminders(for: events, now: now, minutes: [10], meetOnly: false).map(\.eventID) == ["paul@exemple.fr|salle"])
        #expect(NotificationPlan.reminders(for: events, now: now, minutes: [10], meetOnly: true).isEmpty)
        let salle = NotificationPlan.reminders(for: events, now: now, minutes: [10], meetOnly: false).first
        #expect(salle?.joinable == false && salle?.body == "Dans 10 min")
    }

    @Test func remindersStayWithinTheHorizonAndTheLimit() {
        let events = (0..<100).map { event("e\($0)", inMinutes: Double($0) * 20 + 30) }
        let plan = NotificationPlan.reminders(for: events, now: now, minutes: [10, 1], meetOnly: false)
        #expect(plan.count == NotificationPlan.limit)
        #expect(plan.allSatisfy { $0.fireDate <= now.addingTimeInterval(NotificationPlan.horizon) })
        #expect(plan == plan.sorted { $0.fireDate < $1.fireDate })
    }

    @Test func newEventsAreThoseThatAppearedAfterAPreviousReading() {
        let before: Set<String> = ["paul@exemple.fr|a"]
        let after = [event("a", inMinutes: 60), event("b", inMinutes: 90), event("c", inMinutes: -30), event("d", inMinutes: 120, response: "declined"),
                     event("e", inMinutes: 200, allDay: true), event("f", inMinutes: 300, account: "perso@gmail.com"), event("g", inMinutes: 400)]
        let found = NotificationPlan.newEvents(before: before, after: after, firstReading: ["perso@gmail.com"], madeHere: ["paul@exemple.fr|g"], now: now)
        #expect(found.map(\.eventID) == ["b"])
        #expect(NotificationPlan.newEventNotice(found[0], now: now).title == "Nouveau rendez-vous")
    }

    @Test func aMeetingNotRecordedFiveMinutesInIsFlaggedOnce() {
        let events = [event("en-cours", inMinutes: -6), event("vient-de-commencer", inMinutes: -2), event("sans-meet", inMinutes: -10, code: nil),
                      event("refuse", inMinutes: -8, response: "declined")]
        #expect(NotificationPlan.unrecorded(events, now: now, recording: false, alerted: []).map(\.eventID) == ["en-cours"])
        #expect(NotificationPlan.unrecorded(events, now: now, recording: true, alerted: []).isEmpty)
        #expect(NotificationPlan.unrecorded(events, now: now, recording: false, alerted: ["paul@exemple.fr|en-cours"]).isEmpty)
    }
}

/// Only Polhub's reminders are replaced when the plan changes; the others stay.
@Suite struct ReminderSyncTests {
    final class FakeCenter: NotificationCenterClient, @unchecked Sendable {
        var pending: [String] = []
        var added: [PlannedNotice] = []
        var removed: [String] = []
        func pendingIdentifiers() async -> [String] { pending }
        func schedule(_ notice: PlannedNotice, sound: Bool) async { added.append(notice); pending.append(notice.id) }
        func removePending(_ ids: [String]) async { removed += ids; pending.removeAll { ids.contains($0) } }
        func deliverNow(_ notice: PlannedNotice, sound: Bool) async {}
    }

    @Test func theScheduleFollowsThePlan() async {
        let now = Date(timeIntervalSince1970: 1_794_562_920)
        let center = FakeCenter()
        center.pending = ["rappel|ancien|1", "autre-chose"]
        let keep = PlannedNotice(id: "rappel|a|10", fireDate: now.addingTimeInterval(600), title: "A", body: "", eventID: "a", meetCode: nil, account: nil)
        center.pending.append(keep.id)
        let new = PlannedNotice(id: "rappel|b|1", fireDate: now.addingTimeInterval(60), title: "B", body: "", eventID: "b", meetCode: nil, account: nil)
        await ReminderSync.apply([keep, new], to: center, sound: true)
        #expect(center.removed == ["rappel|ancien|1"])
        #expect(center.added.map(\.id) == ["rappel|b|1"])
        #expect(Set(center.pending) == ["autre-chose", "rappel|a|10", "rappel|b|1"])
    }
}
