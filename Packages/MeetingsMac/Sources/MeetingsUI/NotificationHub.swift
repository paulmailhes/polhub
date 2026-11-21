import Agenda
import Colin
import Foundation
import Notifications
import Persistence
import HubDesign

/// hub's notifications, run by the app (14/11): the reminders macOS keeps (shown even when hub is not
/// running), the new events, a meeting not recorded, a summary ready. Réglages › Notifications decides. Every
/// notification shown is also kept in hub's own list, `inbox` (15/11): what Réglages turns off is neither shown
/// nor kept.
@MainActor
public final class NotificationHub: ObservableObject {
    let client: any NotificationCenterClient
    let agenda: AgendaLibrary
    let settings: () -> Preferences
    /// Events Paul made from hub: not announced as new.
    var madeHere: Set<String> = []
    /// Meetings already flagged as not recorded.
    var alerted: Set<String> = []
    /// The reminders handed to macOS, until they come: macOS shows them on its own, the list keeps them then.
    var scheduled: [PlannedNotice] = []
    /// What macOS lets them do, a state (lot 10, 20/11); `nil` until it is read.
    @Published public private(set) var authorization: NotificationAuthorization?
    /// hub's own list of what it notified (15/11): the bell of the sidebar reads it.
    public let inbox: NotificationInbox?

    public init(agenda: AgendaLibrary, client: any NotificationCenterClient = SystemNotifications(),
                settings: @escaping () -> Preferences = { Preferences() }, inbox: NotificationInbox? = nil) {
        self.agenda = agenda
        self.client = client
        self.settings = settings
        self.inbox = inbox
    }

    /// The iPhone (20/11): what the Mac notifies, and the reminders, at their time.
    public var phone: ((PlannedNotice) async -> Void)?
    public var phoneReminders: (([PlannedNotice]) -> Void)?

    /// The one door of the notifications shown now: macOS shows it, the list keeps it, the iPhone gets it.
    private func deliver(_ notice: PlannedNotice, toPhone: Bool = true) async {
        await client.deliverNow(notice, sound: settings().sound)
        inbox?.record(notice, at: notice.fireDate)
        if toPhone { await phone?(notice) }
    }

    /// Vigie's notifications (21/11): shown by macOS and kept in the list, never sent to the iPhone.
    public func vigie(_ notice: PlannedNotice) async {
        await deliver(notice, toPhone: false)
    }

    /// Vigie's waits that ended: their notifications go.
    public func removeVigie(_ ids: [String]) async {
        await client.removeDelivered(ids)
    }

    /// The reminders whose time came since the last look go to the list, at the time macOS showed them.
    func recordDueReminders(now: Date) {
        let due = scheduled.filter { $0.fireDate <= now }
        guard !due.isEmpty else { return }
        scheduled.removeAll { $0.fireDate <= now }
        for notice in due.sorted(by: { $0.fireDate < $1.fireDate }) { inbox?.record(notice, at: notice.fireDate) }
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
        // What came before this new plan is kept first; reminders turned off leave nothing to keep.
        if settings.reminders { recordDueReminders(now: now) }
        scheduled = plan
        await ReminderSync.apply(plan, to: client, sound: settings.sound)
        phoneReminders?(plan)
    }

    /// After a reading: the events that appeared (`before`: Google's ids), then the reminders.
    func afterSync(before: Set<String>, firstReading: Set<String>, windowEnds: [String: Date] = [:], now: Date = Date()) async {
        if settings().newEvents {
            let found = NotificationPlan.newEvents(before: before, after: events(), firstReading: firstReading, madeHere: madeHere,
                                                   windowEnds: windowEnds, now: now)
            // A burst (a calendar shared at once) is said in one line.
            if found.count > 3 {
                await deliver(PlannedNotice(id: "nouveaux|\(Int(now.timeIntervalSince1970))", fireDate: now, title: "Nouveaux rendez-vous",
                                            body: "\(found.count) rendez-vous sont arrivés dans tes agendas.", eventID: nil, meetCode: nil,
                                            account: nil, kind: .newEvent))
            } else {
                for event in found { await deliver(NotificationPlan.newEventNotice(event, now: now)) }
            }
        }
        await refresh(now: now)
    }

    /// Google's id of an event Paul made from hub.
    func madeFromHub(_ eventID: String) {
        madeHere.insert(eventID)
    }

    /// The events an agent just made in Paul's agendas (audit of 19/11): said at once, as a draft an agent prepared is, and
    /// kept in the list; a click opens the event. Never said again as new at the next reading. Not under « Nouveaux
    /// rendez-vous » of Réglages › Notifications: it also guards against an agent misled by a mail.
    public func agentMade(_ events: [CalendarEventRow], now: Date = Date()) async {
        for event in events {
            madeHere.insert(event.eventID)
            var notice = NotificationPlan.newEventNotice(event, now: now)
            notice.id = "agent|\(event.id)"
            notice.title = "Rendez-vous créé par un agent"
            await deliver(notice)
        }
    }

    /// Every minute: a meeting of the calendar under way for five minutes while nothing records. Not while
    /// detection is paused, nor for a meeting already recorded, declined at the prompt or never to record (review of
    /// 14/11).
    public func tick(recording: Bool, paused: Bool = false, now: Date = Date()) async {
        if settings().reminders { recordDueReminders(now: now) }
        guard settings().unrecorded, !paused else { return }
        let meetings = MeetingStore(agenda.database)
        let never = (try? meetings.neverCodes()) ?? []
        for event in NotificationPlan.unrecorded(events(), now: now, recording: recording, alerted: alerted) {
            guard let code = event.meetCode else { continue }
            let handled = never.contains(code)
                || ((try? meetings.anyMeeting(code: code, from: event.startAt.addingTimeInterval(-30 * 60), to: now)) ?? false)
            alerted.insert(event.id)
            if handled { continue }
            await deliver(NotificationPlan.unrecordedNotice(event, now: now))
        }
    }

    public func summaryReady(meetingID: UUID, title: String) async {
        guard settings().summaryReady else { return }
        await deliver(NotificationPlan.summaryNotice(meetingID: meetingID, title: title, now: Date()))
    }

    /// New mails of the main tab, as the mail engine heard them (14/11).
    public func mailsArrived(_ mails: [(threadKey: String, sender: String, subject: String)]) async {
        guard !mails.isEmpty, settings().mailNotices else { return }
        // The iPhone has its own, for every mail (`phoneMailsArrived`).
        for notice in NotificationPlan.mailNotices(mails, now: Date()) { await deliver(notice, toPhone: false) }
    }

    /// Every new mail, on the iPhone, as Gmail would show it (20/11), whatever the Mac says of mails.
    public func phoneMailsArrived(_ mails: [(threadKey: String, sender: String, subject: String, snippet: String)]) async {
        for notice in NotificationPlan.phoneMailNotices(mails, now: Date()) { await phone?(notice) }
    }

    /// The drafts an agent just prepared (18/11): Colin says they are ready, by the first name of who each is written
    /// to. A click opens the Accueil.
    public func draftsReady(_ drafts: [MailDraftRow]) async {
        await draftsReady(drafts.map { (id: $0.id, recipient: $0.to.first.map { ReviewRules.short($0.display) } ?? "", threadKey: $0.threadKey) })
    }

    public func draftsReady(_ drafts: [(id: String, recipient: String, threadKey: String?)]) async {
        guard settings().colinDraftNotice, !drafts.isEmpty else { return }
        for notice in NotificationPlan.draftNotices(drafts, now: Date()) { await deliver(notice) }
    }

    /// A mail Paul sent that did not leave: told even when the window is closed. A click opens its thread.
    public func mailNotSent(subject: String, threadKey: String?) async {
        await deliver(PlannedNotice(id: "non-envoye|\(Int(Date().timeIntervalSince1970))", fireDate: Date(), title: "Mail non envoyé",
                                    body: "« \(subject) » t'attend dans Brouillons.", eventID: nil, meetCode: nil, account: nil,
                                    threadKey: threadKey, kind: .mail))
    }

    /// A programmed mail that left late, waits for Paul or did not leave (wave B): told even window closed. A
    /// click opens its thread, else its folder (« Programmés », « Brouillons », « Envoyés »).
    public func mailScheduleNotice(_ notice: MailScheduleNotice, now: Date = Date()) async {
        await deliver(PlannedNotice(id: "programme|\(UUID().uuidString)", fireDate: now, title: notice.title,
                                    body: notice.body, eventID: nil, meetCode: nil, account: nil, threadKey: notice.threadKey,
                                    folder: notice.threadKey == nil ? notice.folder?.rawValue : nil, kind: .mail))
    }

    /// « Envoyer une notification d'essai ».
    public func test() async {
        _ = await SystemNotifications.requestAuthorization()
        await deliver(PlannedNotice(id: "essai|\(Int(Date().timeIntervalSince1970))", fireDate: Date(), title: "hub",
                                    body: "Les notifications marchent.", eventID: nil, meetCode: nil, account: nil, kind: .test))
        await readAuthorization()
    }

    public func readAuthorization() async {
        authorization = await SystemNotifications.authorization()
    }
}

/// « Ouvrir hub à l'ouverture de session »: the app's relaunch agent, which also starts it with the session.
@MainActor
public final class StartupControl: ObservableObject {
    @Published public private(set) var isOn: Bool
    @Published public private(set) var message: String?
    let read: () -> Bool
    let write: (Bool) -> String?
    /// A meeting is on: the switch waits (turning it off stops hub, on hands it over to macOS).
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
