import Agenda
import Domain
import Foundation
import GoogleKit
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

    func hub(_ center: Center, inbox: NotificationInbox? = nil) -> NotificationHub {
        let defaults = defaults
        return NotificationHub(agenda: AgendaLibrary(database: database), client: center, settings: { Preferences(defaults: defaults) },
                               inbox: inbox)
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
        let before = Set(try calendar.allEvents().map(\.eventID))
        try calendar.applyGoogle(account: "paul@exemple.fr", changed: [event("b", inMinutes: 90), event("c", inMinutes: 120)], cancelled: [], at: now)
        let center = Center()
        let hub = hub(center)
        hub.madeFromPolhub("c")
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
        #expect(center.delivered.map(\.title) == ["Visio non enregistrée"])
        #expect(center.delivered.first?.joinable == true)
    }

    /// Review of 14/11: a meeting recorded and stopped early, declined at the prompt, or on « jamais pour ce
    /// lien » is not « non enregistrée »; nor anything while detection is paused.
    @Test func aMeetingAlreadyHandledIsNeverFlagged() async throws {
        let calendar = CalendarStore(database), meetings = MeetingStore(database)
        try calendar.addAccount(email: "paul@exemple.fr", at: now)
        var recorded = event("enregistree", inMinutes: -20)
        recorded.meetCode = "aaa-bbbb-ccc"
        var declined = event("refusee-au-pop-up", inMinutes: -15)
        declined.meetCode = "ddd-eeee-fff"
        var never = event("jamais", inMinutes: -10)
        never.meetCode = "ggg-hhhh-iii"
        try calendar.applyGoogle(account: "paul@exemple.fr", changed: [recorded, declined, never], cancelled: [], at: now)
        try meetings.save(MeetingRow(createdAt: now, status: .ended, source: .dia, candidateKey: "t/1", meetCode: "aaa-bbbb-ccc", title: "x",
                                     startedAt: now.addingTimeInterval(-19 * 60), endedAt: now.addingTimeInterval(-12 * 60)))
        try meetings.save(MeetingRow(createdAt: now, status: .discarded, source: .dia, candidateKey: "t/2", meetCode: "ddd-eeee-fff", title: "y",
                                     startedAt: now.addingTimeInterval(-14 * 60), deletedAt: now.addingTimeInterval(-14 * 60)))
        try meetings.addNeverCode("ggg-hhhh-iii", at: now)
        let center = Center()
        let hub = hub(center)
        await hub.tick(recording: false, now: now)
        #expect(center.delivered.isEmpty)
    }

    @Test func nothingIsFlaggedWhileDetectionIsPaused() async throws {
        let calendar = CalendarStore(database)
        try calendar.addAccount(email: "paul@exemple.fr", at: now)
        try calendar.applyGoogle(account: "paul@exemple.fr", changed: [event("en-cours", inMinutes: -8)], cancelled: [], at: now)
        let center = Center()
        await hub(center).tick(recording: false, paused: true, now: now)
        #expect(center.delivered.isEmpty)
    }

    /// A refresh token for every address: the agenda's session never reaches the Keychain here.
    final class Vault: TokenVault, @unchecked Sendable {
        func save(refreshToken: String, for email: String) throws {}
        func refreshToken(for email: String) -> String? { "jeton-de-test" }
        func remove(for email: String) {}
    }

    /// Audit of 19/11: an event an agent made in Paul's own agenda is said at once and kept in the list, its click opening
    /// it; until now only a line under Réglages › Comptes Google said so. Google is a fake; nothing leaves the Mac.
    @Test func anEventMadeByAnAgentIsAnnounced() async throws {
        let calendar = CalendarStore(database)
        try calendar.addAccount(email: "paul@exemple.fr", at: now)
        let root = FileManager.default.temporaryDirectory.appending(path: "agent-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        // The token's refresh, then the event Google makes from what was sent.
        let session = GoogleSession(config: { GoogleClientConfig(clientID: "id", clientSecret: "secret") }, vault: Vault(), fetch: { request in
            if request.url == GoogleClientConfig.tokenEndpoint { return (Data(#"{"access_token":"jeton","expires_in":3600}"#.utf8), 200) }
            let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]) ?? [:]
            let event: [String: Any] = ["id": "agent1", "status": "confirmed", "summary": body["summary"] ?? "", "start": body["start"] ?? [:],
                                        "end": body["end"] ?? [:], "organizer": ["email": "paul@exemple.fr", "self": true]]
            return (try JSONSerialization.data(withJSONObject: event), 200)
        })
        let agenda = AgendaLibrary(database: database, session: session, sync: CalendarSync(fetch: { _ in throw URLError(.notConnectedToInternet) }))
        let center = Center(), inbox = NotificationInbox(file: nil)
        let defaults = defaults
        let hub = NotificationHub(agenda: agenda, client: center, settings: { Preferences(defaults: defaults) }, inbox: inbox)
        agenda.notifications = hub
        try AgentEventFiles(root: root).request(AgentEventRequest(title: "Point devis", start: now.addingTimeInterval(86_400), minutes: 30,
                                                                 account: "paul@exemple.fr", createdAt: Date()))

        agenda.startAgentEvents(root: root, flavor: .prod)
        // The list is written once macOS's center has the notice: waiting for it, both are done.
        for _ in 0..<150 where inbox.notices.isEmpty { try await Task.sleep(for: .milliseconds(20)) }

        // The event was made: what is missing is only the word to Paul.
        #expect(try calendar.allEvents().map(\.eventID) == ["agent1"])
        let notice = try #require(center.delivered.first)
        #expect(notice.body.contains("Point devis"))
        #expect(inbox.notices.first?.action(now: now) == .event(CalendarEventRow.key(account: "paul@exemple.fr", eventID: "agent1")))
        withExtendedLifetime(hub) {}
    }

    @Test func aSummaryReadyIsAnnouncedUnlessTurnedOff() async {
        let center = Center()
        let hub = hub(center)
        await hub.summaryReady(meetingID: UUID(), title: "Atelier maquette")
        defaults.set(false, forKey: Preferences.Key.summaryReady)
        await hub.summaryReady(meetingID: UUID(), title: "Autre")
        #expect(center.delivered.map(\.body) == ["Atelier maquette"])
    }

    // MARK: - Polhub's own list (15/11)

    /// Every notification shown is kept in the list, with what its click opens.
    @Test func everyNotificationShownIsKeptInTheList() async throws {
        let calendar = CalendarStore(database)
        try calendar.addAccount(email: "paul@exemple.fr", at: now)
        try calendar.applyGoogle(account: "paul@exemple.fr", changed: [event("en-cours", inMinutes: -8)], cancelled: [], at: now)
        let center = Center(), inbox = NotificationInbox(file: nil)
        let hub = hub(center, inbox: inbox)
        let meeting = UUID()
        await hub.summaryReady(meetingID: meeting, title: "Atelier maquette")
        await hub.mailsArrived([(threadKey: "paul@exemple.fr|fil", sender: "Camille Exemple", subject: "Maquette")])
        await hub.mailNotSent(subject: "Devis", threadKey: nil)
        await hub.mailScheduleNotice(MailScheduleNotice(title: "Mail programmé parti en retard", body: "« Devis » est parti à 9 h 12.",
                                                        threadKey: nil, folder: .scheduled))
        await hub.tick(recording: false, now: now)
        #expect(center.delivered.count == 5)
        #expect(Set(inbox.notices.map(\.title)) == Set(center.delivered.map(\.title)))
        #expect(inbox.unreadCount == 5)
        #expect(inbox.notices.first { $0.kind == .summary }?.action(now: Date()) == .meeting(meeting))
        #expect(inbox.notices.first { $0.kind == .unrecorded }?.action(now: now) == .join(meetCode: "abc-defg-hij", account: "paul@exemple.fr"))
        #expect(inbox.notices.first { $0.title == "Camille Exemple" }?.action(now: now) == .mailThread("paul@exemple.fr|fil"))
        #expect(inbox.notices.first { $0.title == "Mail non envoyé" }?.action(now: now) == .mailFolder(nil))
        #expect(inbox.notices.first { $0.title == "Mail programmé parti en retard" }?.action(now: now) == .mailFolder(MailFolder.scheduled.rawValue))
    }

    /// What Réglages › Notifications turned off is neither shown nor kept.
    @Test func aKindTurnedOffIsNeitherShownNorKept() async {
        defaults.set(false, forKey: Preferences.Key.summaryReady)
        defaults.set(false, forKey: Preferences.Key.mailNotices)
        let center = Center(), inbox = NotificationInbox(file: nil)
        let hub = hub(center, inbox: inbox)
        await hub.summaryReady(meetingID: UUID(), title: "Atelier maquette")
        await hub.mailsArrived([(threadKey: "paul@exemple.fr|fil", sender: "Camille Exemple", subject: "Maquette")])
        #expect(center.delivered.isEmpty && inbox.notices.isEmpty)
    }

    /// macOS shows the reminders on its own: the list keeps each once its time has come, and none turned off.
    @Test func aReminderIsKeptOnceItsTimeHasCome() async throws {
        let calendar = CalendarStore(database)
        try calendar.addAccount(email: "paul@exemple.fr", at: now)
        try calendar.applyGoogle(account: "paul@exemple.fr", changed: [event("a", inMinutes: 30)], cancelled: [], at: now)
        let center = Center(), inbox = NotificationInbox(file: nil)
        let hub = hub(center, inbox: inbox)
        await hub.refresh(now: now)
        await hub.tick(recording: false, paused: true, now: now.addingTimeInterval(10 * 60))
        #expect(inbox.notices.isEmpty)
        await hub.tick(recording: false, paused: true, now: now.addingTimeInterval(21 * 60))
        #expect(inbox.notices.map(\.body) == ["Dans 10 min · Google Meet"])
        #expect(inbox.notices.first?.date == now.addingTimeInterval(20 * 60))
        // A new plan keeps what came before it; the 1-minute reminder joins the same card.
        await hub.refresh(now: now.addingTimeInterval(29.5 * 60))
        #expect(inbox.notices.count == 1 && inbox.notices.first?.body == "Dans 1 min · Google Meet" && inbox.notices.first?.count == 2)
        // Turned off: the plan empties, nothing more is kept.
        try calendar.applyGoogle(account: "paul@exemple.fr", changed: [event("b", inMinutes: 60)], cancelled: [], at: now)
        await hub.refresh(now: now.addingTimeInterval(30 * 60))
        defaults.set(false, forKey: Preferences.Key.reminders)
        await hub.refresh(now: now.addingTimeInterval(30 * 60))
        await hub.tick(recording: false, paused: true, now: now.addingTimeInterval(80 * 60))
        #expect(inbox.notices.count == 1)
    }

    /// 18/11: Colin says a draft is ready, by the first name of who it is written to, unless Réglages › Notifications
    /// says not to.
    @Test func aDraftReadyIsAnnouncedUnlessTurnedOff() async {
        let center = Center()
        let inbox = NotificationInbox(file: nil)
        let hub = hub(center, inbox: inbox)
        #expect(Preferences(defaults: defaults).colinDraftNotice && Preferences.Key.colinDraftNotice == "notifications.colin.brouillon")
        await hub.draftsReady([(id: "d1", recipient: "Claire", threadKey: "moi@exemple.fr|t1")])
        #expect(center.delivered.map(\.title) == ["Colin"])
        #expect(center.delivered.first?.body == "Brouillon prêt pour Claire. À relire." && center.delivered.first?.kind == .draft)
        #expect(inbox.notices.count == 1 && inbox.notices.first?.kind == .draft)
        await hub.draftsReady([(id: String, recipient: String, threadKey: String?)]())
        #expect(center.delivered.count == 1)
        // The drafts as the mails give them: « Claire Morel » is « Claire ».
        let row = MailDraftRow(id: "d2", account: "moi@exemple.fr", mode: .new, to: [MailAddress(name: "Marc Dubois", email: "marc@exemple.net")],
                               subject: "Devis", body: "Bonjour", origin: .agent, createdAt: now)
        await hub.draftsReady([row])
        #expect(center.delivered.last?.body == "Brouillon prêt pour Marc. À relire." && center.delivered.last?.id == "brouillon|d2")
        defaults.set(false, forKey: Preferences.Key.colinDraftNotice)
        await hub.draftsReady([(id: "d3", recipient: "Anne", threadKey: nil)])
        await hub.draftsReady([row])
        #expect(center.delivered.count == 2 && inbox.notices.count == 2)
    }

    /// A click in the list opens the same pages as a click on macOS's notification.
    @Test func aClickOpensThePageOfTheNotification() {
        let router = WindowRouter()
        let meeting = UUID()
        #expect(router.perform(.meeting(meeting), agenda: nil, mails: nil))
        #expect(router.section == .meetings && router.selection == meeting)
        router.perform(.event("paul@exemple.fr|e"), agenda: nil, mails: nil)
        #expect(router.section == .calendar && router.eventSelection == "paul@exemple.fr|e")
        router.perform(.mailThread("paul@exemple.fr|fil"), agenda: nil, mails: nil)
        #expect(router.section == .mails && router.mailSelection == "paul@exemple.fr|fil")
        router.perform(.mailFolder("programmes"), agenda: nil, mails: nil)
        #expect(router.section == .mails && router.mailSelection == nil)
        router.section = .home
        router.perform(.calendar, agenda: nil, mails: nil)
        #expect(router.section == .calendar)
        // The Meet opens in Dia: no window to show.
        #expect(!router.perform(.join(meetCode: "abc-defg-hij", account: "paul@exemple.fr"), agenda: nil, mails: nil))
        #expect(router.perform(.window, agenda: nil, mails: nil))
        // « Brouillon prêt » : the Accueil.
        #expect(router.perform(.home, agenda: nil, mails: nil))
        #expect(router.section == .home)
        // A thread left open over the Accueil would hide the draft that waits: it is closed.
        router.homeMail = "paul@exemple.fr|vieux"
        router.section = .projects
        #expect(router.perform(.home, agenda: nil, mails: nil))
        #expect(router.section == .home && router.homeMail == nil)
    }
}
