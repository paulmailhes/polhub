import Agenda
import Foundation
import Notifications
import Persistence
import PolhubDesign
import Testing
@testable import MeetingsUI

/// The notifications as the app runs them (14/11), with a stand-in for macOS's center.
@MainActor @Suite struct NotificationHubTests {
    final class Center: NotificationCenterClient, @unchecked Sendable {
        var pending: [PlannedNotice] = []
        var delivered: [PlannedNotice] = []
        func pendingIdentifiers() async -> [String] { pending.map(\.id) }
        func schedule(_ notice: PlannedNotice, sound: Bool) async { pending.append(notice) }
        func removePending(_ ids: [String]) async { pending.removeAll { ids.contains($0.id) } }
        func deliverNow(_ notice: PlannedNotice, sound: Bool) async { delivered.append(notice) }
    }

    // Whole seconds: the base keeps dates to the millisecond.
    let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    let database: AppDatabase
    let defaults: UserDefaults

    init() throws {
        database = try AppDatabase.inMemory()
        defaults = try #require(UserDefaults(suiteName: "hub-\(UUID().uuidString)"))
    }

    func event(_ id: String, inMinutes: Double, account: String = "paul@exemple.fr") -> CalendarEventRow {
        CalendarEventRow(account: account, eventID: id, title: "Point \(id)", startAt: now.addingTimeInterval(inMinutes * 60),
                         endAt: now.addingTimeInterval((inMinutes + 30) * 60), meetCode: "abc-defg-hij", organizer: "client@ailleurs.fr",
                         attendees: [Attendee(email: account, response: "accepted", isSelf: true)], updatedAt: now)
    }

    func hub(_ center: Center) -> NotificationHub {
        let defaults = defaults
        return NotificationHub(agenda: AgendaLibrary(database: database), client: center, settings: { Preferences(defaults: defaults) })
    }

    @Test func remindersAreScheduledAndFollowTheSettings() async throws {
        let calendar = CalendarStore(database)
        try calendar.addAccount(email: "paul@exemple.fr", at: now)
        try calendar.applyGoogle(account: "paul@exemple.fr", changed: [event("a", inMinutes: 60)], cancelled: [], at: now)
        let center = Center()
        let hub = hub(center)
        await hub.refresh(now: now)
        #expect(center.pending.map(\.fireDate) == [now.addingTimeInterval(50 * 60), now.addingTimeInterval(59 * 60)])
        defaults.set(false, forKey: Preferences.Key.reminders)
        await hub.refresh(now: now)
        #expect(center.pending.isEmpty)
    }

    @Test func aNewEventIsAnnouncedButNotOneMadeFromPolhubNorAtAFirstReading() async throws {
        let calendar = CalendarStore(database)
        try calendar.addAccount(email: "paul@exemple.fr", at: now)
        try calendar.applyGoogle(account: "paul@exemple.fr", changed: [event("a", inMinutes: 60)], cancelled: [], at: now)
        let before = Set(try calendar.allEvents().map(\.id))
        try calendar.applyGoogle(account: "paul@exemple.fr", changed: [event("b", inMinutes: 90), event("c", inMinutes: 120)], cancelled: [], at: now)
        let center = Center()
        let hub = hub(center)
        hub.madeFromPolhub(CalendarEventRow.key(account: "paul@exemple.fr", eventID: "c"))
        await hub.afterSync(before: before, firstReading: [], now: now)
        #expect(center.delivered.map(\.title) == ["Nouveau rendez-vous"])
        #expect(center.delivered.first?.eventID == CalendarEventRow.key(account: "paul@exemple.fr", eventID: "b"))
        center.delivered = []
        await hub.afterSync(before: [], firstReading: ["paul@exemple.fr"], now: now)
        #expect(center.delivered.isEmpty)
    }

    @Test func aMeetingNotRecordedIsFlaggedOnceAndNeverWhileRecording() async throws {
        let calendar = CalendarStore(database)
        try calendar.addAccount(email: "paul@exemple.fr", at: now)
        try calendar.applyGoogle(account: "paul@exemple.fr", changed: [event("en-cours", inMinutes: -8)], cancelled: [], at: now)
        let center = Center()
        let hub = hub(center)
        await hub.tick(recording: true, now: now)
        #expect(center.delivered.isEmpty)
        await hub.tick(recording: false, now: now)
        await hub.tick(recording: false, now: now)
        #expect(center.delivered.map(\.title) == ["Réunion non enregistrée"])
        #expect(center.delivered.first?.joinable == true)
    }

    @Test func aSummaryReadyIsAnnouncedUnlessTurnedOff() async {
        let center = Center()
        let hub = hub(center)
        await hub.summaryReady(meetingID: UUID(), title: "Atelier maquette")
        defaults.set(false, forKey: Preferences.Key.summaryReady)
        await hub.summaryReady(meetingID: UUID(), title: "Autre")
        #expect(center.delivered.map(\.body) == ["Atelier maquette"])
    }
}
