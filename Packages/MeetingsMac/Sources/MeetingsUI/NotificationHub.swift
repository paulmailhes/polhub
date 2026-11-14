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

    /// After a reading: the events that appeared, then the reminders.
    func afterSync(before: Set<String>, firstReading: Set<String>, now: Date = Date()) async {
        if settings().newEvents {
            let found = NotificationPlan.newEvents(before: before, after: events(), firstReading: firstReading, madeHere: madeHere, now: now)
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

    func madeFromPolhub(_ rowID: String) {
        madeHere.insert(rowID)
    }

    /// Every minute: a meeting of the calendar under way for five minutes while nothing records.
    public func tick(recording: Bool, now: Date = Date()) async {
        guard settings().unrecorded else { return }
        for event in NotificationPlan.unrecorded(events(), now: now, recording: recording, alerted: alerted) {
            alerted.insert(event.id)
            await client.deliverNow(NotificationPlan.unrecordedNotice(event, now: now), sound: settings().sound)
        }
    }

    public func summaryReady(meetingID: UUID, title: String) async {
        guard settings().summaryReady else { return }
        await client.deliverNow(NotificationPlan.summaryNotice(meetingID: meetingID, title: title, now: Date()), sound: settings().sound)
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

    public init(read: @escaping () -> Bool, write: @escaping (Bool) -> String?) {
        self.read = read
        self.write = write
        isOn = read()
    }

    public func set(_ on: Bool) {
        message = write(on)
        isOn = read()
    }
}
