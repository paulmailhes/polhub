import Agenda
import Foundation
import Notifications
import Persistence
import PolhubDesign

/// Polhub's notifications, run by the app (14/11): the reminders macOS keeps (shown even when Polhub is not
/// running), the new events, a meeting not recorded, a summary ready. Réglages › Notifications decides.
@MainActor
public final class NotificationHub: ObservableObject {
    let client: any NotificationCenterClient
    let agenda: AgendaLibrary
    let settings: () -> Preferences
    /// Events Paul made from Polhub: not announced as new.
    var madeHere: Set<String> = []
    /// Meetings already flagged as not recorded.
    var alerted: Set<String> = []
    @Published public private(set) var authorization = ""

    public init(agenda: AgendaLibrary, client: any NotificationCenterClient = SystemNotifications(),
                settings: @escaping () -> Preferences = { Preferences() }) {
        self.agenda = agenda
        self.client = client
        self.settings = settings
    }

    /// The events of every calendar, once each.
    private func events() -> [CalendarEventRow] {
        let store = CalendarStore(agenda.database)
        return EventCopies.merge((try? store.allEvents()) ?? [], accounts: (try? store.accounts()) ?? [])
    }

    /// The reminders macOS keeps, planned again: after a reading of the calendars and a change of the settings.
    public func refresh(now: Date = Date()) async {
        let settings = settings()
        let plan = settings.reminders
            ? NotificationPlan.reminders(for: events(), now: now, minutes: settings.reminderMinutes, meetOnly: settings.remindersMeetOnly) : []
        await ReminderSync.apply(plan, to: client, sound: settings.sound)
    }

    /// After a reading: the events that appeared (`before`: Google's ids), then the reminders.
    func afterSync(before: Set<String>, firstReading: Set<String>, windowEnds: [String: Date] = [:], now: Date = Date()) async {
        if settings().newEvents {
            let found = NotificationPlan.newEvents(before: before, after: events(), firstReading: firstReading, madeHere: madeHere,
                                                   windowEnds: windowEnds, now: now)
            // A burst (a calendar shared at once) is said in one line.
            if found.count > 3 {
                await client.deliverNow(PlannedNotice(id: "nouveaux|\(Int(now.timeIntervalSince1970))", fireDate: now, title: "Nouveaux rendez-vous",
                                                      body: "\(found.count) rendez-vous sont arrivés dans tes agendas.", eventID: nil, meetCode: nil,
                                                      account: nil, kind: .newEvent), sound: settings().sound)
            } else {
                for event in found { await client.deliverNow(NotificationPlan.newEventNotice(event, now: now), sound: settings().sound) }
            }
        }
        await refresh(now: now)
    }

    /// Google's id of an event Paul made from Polhub.
    func madeFromPolhub(_ eventID: String) {
        madeHere.insert(eventID)
    }

    /// Every minute: a meeting of the calendar under way for five minutes while nothing records. Not while
    /// detection is paused, nor for a meeting already recorded, declined at the prompt or never to record (review of
    /// 14/11).
    public func tick(recording: Bool, paused: Bool = false, now: Date = Date()) async {
        guard settings().unrecorded, !paused else { return }
        let meetings = MeetingStore(agenda.database)
        let never = (try? meetings.neverCodes()) ?? []
        for event in NotificationPlan.unrecorded(events(), now: now, recording: recording, alerted: alerted) {
            guard let code = event.meetCode else { continue }
            let handled = never.contains(code)
                || ((try? meetings.anyMeeting(code: code, from: event.startAt.addingTimeInterval(-30 * 60), to: now)) ?? false)
            alerted.insert(event.id)
            if handled { continue }
            await client.deliverNow(NotificationPlan.unrecordedNotice(event, now: now), sound: settings().sound)
        }
    }

    public func summaryReady(meetingID: UUID, title: String) async {
        guard settings().summaryReady else { return }
        await client.deliverNow(NotificationPlan.summaryNotice(meetingID: meetingID, title: title, now: Date()), sound: settings().sound)
    }

    /// New mails of the main tab, as the mail engine heard them (14/11).
    public func mailsArrived(_ mails: [(threadKey: String, sender: String, subject: String)]) async {
        guard settings().mailNotices, !mails.isEmpty else { return }
        for notice in NotificationPlan.mailNotices(mails, now: Date()) { await client.deliverNow(notice, sound: settings().sound) }
    }

    /// « Envoyer une notification d'essai ».
    public func test() async {
        _ = await SystemNotifications.requestAuthorization()
        await client.deliverNow(PlannedNotice(id: "essai|\(Int(Date().timeIntervalSince1970))", fireDate: Date(), title: "Polhub",
                                              body: "Les notifications marchent.", eventID: nil, meetCode: nil, account: nil, kind: .newEvent),
                                sound: settings().sound)
        await readAuthorization()
    }

    public func readAuthorization() async {
        authorization = await SystemNotifications.authorizationText()
    }
}

/// « Ouvrir Polhub à l'ouverture de session »: the app's relaunch agent, which also starts it with the session.
@MainActor
public final class StartupControl: ObservableObject {
    @Published public private(set) var isOn: Bool
    @Published public private(set) var message: String?
    let read: () -> Bool
    let write: (Bool) -> String?
    /// A meeting is on: the switch waits (turning it off stops Polhub, on hands it over to macOS).
    let busy: () -> Bool
    /// This copy was opened by Paul: turning it on hands over to macOS's copy, and this window closes.
    public let handsOver: Bool

    public init(read: @escaping () -> Bool, write: @escaping (Bool) -> String?, busy: @escaping () -> Bool = { false },
                handsOver: Bool = false) {
        self.read = read
        self.write = write
        self.busy = busy
        self.handsOver = handsOver
        isOn = read()
    }

    /// `false` when it must wait for the end of a meeting (review of 14/11).
    public func canChange() -> Bool {
        if busy() {
            message = "Pendant une réunion, ce réglage attend qu'elle soit finie."
            return false
        }
        message = nil
        return true
    }

    public func set(_ on: Bool) {
        guard canChange() else { return }
        message = write(on)
        isOn = read()
    }
}
