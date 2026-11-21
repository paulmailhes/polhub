import Domain
import Foundation
import Persistence
import HubDesign

/// One notification hub asks macOS to show, now or at a date.
public struct PlannedNotice: Equatable, Sendable {
    /// `test`: « Envoyer une notification d'essai » (15/11: it has its own kind, so the list does not file it under
    /// Calendrier). `draft`: a draft an agent prepared waits for Paul on the Accueil (18/11).
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case reminder, newEvent, unrecorded, summary, mail, test, draft
        /// Vigie (21/11): what waits for Paul in Claude Code, what finished, an account full.
        case vigie
    }

    public var id: String
    public var fireDate: Date
    public var title: String
    public var body: String
    /// Under the title, on the iPhone: a mail's subject (20/11).
    public var subtitle: String?
    /// The event's row id (`account|eventID`), for a click that opens it.
    public var eventID: String?
    public var meetCode: String?
    /// The Google account to join the Meet with.
    public var account: String?
    /// The meeting a summary belongs to.
    public var meetingID: UUID?
    /// The thread a mail belongs to (`account|threadID`).
    public var threadKey: String?
    /// The mails' folder a click opens when there is no thread (« Programmés », wave B).
    public var folder: String?
    public var kind: Kind
    /// Vigie: the conversation a click opens (empty: the page).
    public var vigie: String?
    /// Asks nothing: the notification center only, without a banner or a sound (21/11, as the app Vigie).
    public var quiet = false

    public init(id: String, fireDate: Date, title: String, body: String, eventID: String?, meetCode: String?, account: String?,
                meetingID: UUID? = nil, threadKey: String? = nil, folder: String? = nil, kind: Kind = .reminder, subtitle: String? = nil,
                vigie: String? = nil, quiet: Bool = false) {
        self.id = id
        self.vigie = vigie
        self.quiet = quiet
        self.subtitle = subtitle
        self.fireDate = fireDate
        self.title = title
        self.body = body
        self.eventID = eventID
        self.meetCode = meetCode
        self.account = account
        self.meetingID = meetingID
        self.threadKey = threadKey
        self.folder = folder
        self.kind = kind
    }

    /// A click joins the Meet.
    public var joinable: Bool { meetCode != nil && account != nil }
}

/// What to notify, from the calendars (14/11). Pure: the scheduling is `ReminderSync`'s.
public enum NotificationPlan {
    /// macOS keeps a limited number of pending notifications per app: the nearest ones only.
    public static let limit = 48
    /// Reminders are planned this far ahead (a week: they still come when hub is closed for a weekend), and
    /// planned again at each reading of the calendars; `limit` keeps under macOS's cap (review of 14/11).
    public static let horizon: TimeInterval = 7 * 86_400
    /// A meeting with a Meet still not recorded after this long is flagged.
    public static let unrecordedDelay: TimeInterval = 5 * 60
    static let reminderPrefix = "rappel|"

    /// A reminder `minutes` before each coming event: not a whole day, not declined; with a Meet only if asked.
    public static func reminders(for events: [CalendarEventRow], now: Date, minutes: [Int], meetOnly: Bool) -> [PlannedNotice] {
        var notices: [PlannedNotice] = []
        for event in events where attends(event) && event.startAt > now && (!meetOnly || event.meetCode != nil) {
            for minute in Set(minutes) where minute >= 0 {
                let fire = event.startAt.addingTimeInterval(-Double(minute) * 60)
                guard fire > now, fire <= now.addingTimeInterval(horizon) else { continue }
                // « Dans 10 min », « Dans 1 h », « Maintenant », from the minutes asked, exactly: a start between two
                // seconds never rounds up into one minute more (`Words.duration`, lot 10, 20/11).
                let when = minute == 0 ? "Maintenant" : "Dans " + Words.duration(minute * 60)
                notices.append(PlannedNotice(
                    id: "\(reminderPrefix)\(event.id)|\(Int(event.startAt.timeIntervalSince1970))|\(minute)", fireDate: fire, title: event.title,
                    body: when + (event.meetCode != nil ? " · Google Meet" : ""), eventID: event.id, meetCode: event.meetCode,
                    account: event.account, kind: .reminder
                ))
            }
        }
        return Array(notices.sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }.prefix(limit))
    }

    /// The coming events that appeared since the previous reading, by Google's id (a copy shown under another
    /// account is not new): never at an account's first reading (no flood when an account is connected), nor those
    /// Paul made from hub, declined ones, whole days. The reading window slides ahead: an event beyond the end
    /// of the previous window (`windowEnds`, per account) only entered it, it is not new (review of 14/11).
    public static func newEvents(before: Set<String>, after: [CalendarEventRow], firstReading: Set<String>, madeHere: Set<String>,
                                 windowEnds: [String: Date], now: Date) -> [CalendarEventRow] {
        after.filter { event in
            !before.contains(event.eventID) && !firstReading.contains(event.account) && !madeHere.contains(event.eventID) && attends(event)
                && event.startAt > now && windowEnds[event.account].map { event.startAt < $0 } ?? true
        }
        .sorted { $0.startAt < $1.startAt }
    }

    /// « Atelier · demain 14:00 », « Atelier · mercredi 2 décembre à 14:00 » (`Words.moment`, lot 10, 20/11).
    public static func newEventNotice(_ event: CalendarEventRow, now: Date) -> PlannedNotice {
        let when = Words.moment(event.startAt, now: now)
        return PlannedNotice(id: "nouveau|\(event.id)", fireDate: now, title: "Nouveau rendez-vous", body: "\(event.title) · \(when)",
                             eventID: event.id, meetCode: event.meetCode, account: event.account, kind: .newEvent)
    }

    /// Events with a Meet under way for a few minutes while nothing records: flagged once each.
    public static func unrecorded(_ events: [CalendarEventRow], now: Date, recording: Bool, alerted: Set<String>) -> [CalendarEventRow] {
        guard !recording else { return [] }
        return events.filter { event in
            event.meetCode != nil && attends(event) && event.startAt <= now.addingTimeInterval(-unrecordedDelay) && event.endAt > now
                && !alerted.contains(event.id)
        }
    }

    /// A visio, a meeting of the agenda with a Meet link, not a « réunion »: what hub recorded (lot 10, 20/11). The
    /// title says it is not recorded, the body need not: shorter, it holds in the bell's two lines (« …ne l'enregistre
    /// pas.… » was cut).
    public static func unrecordedNotice(_ event: CalendarEventRow, now: Date) -> PlannedNotice {
        PlannedNotice(id: "non-enregistree|\(event.id)", fireDate: now, title: "Visio non enregistrée",
                      body: "« \(event.title) » a commencé. Rejoindre ?", eventID: event.id,
                      meetCode: event.meetCode, account: event.account, kind: .unrecorded)
    }

    public static func summaryNotice(meetingID: UUID, title: String, now: Date) -> PlannedNotice {
        PlannedNotice(id: "compte-rendu|\(meetingID.uuidString)", fireDate: now, title: "Compte rendu prêt", body: title, eventID: nil,
                      meetCode: nil, account: nil, meetingID: meetingID, kind: .summary)
    }

    /// New mails of the main tab (14/11): one notice per mail, or one line for a burst. A click opens the thread.
    public static func mailNotices(_ mails: [(threadKey: String, sender: String, subject: String)], now: Date) -> [PlannedNotice] {
        guard mails.count <= 3 else {
            // « 5 nouveaux mails » (`Words.count`, lot 10, 20/11).
            return [PlannedNotice(id: "mails|\(Int(now.timeIntervalSince1970))", fireDate: now, title: Words.count(mails.count, "nouveau mail", "nouveaux mails"),
                                  body: mails.prefix(3).map(\.sender).joined(separator: ", ") + "…", eventID: nil, meetCode: nil, account: nil, kind: .mail)]
        }
        return mails.map { mail in
            PlannedNotice(id: "mail|\(mail.threadKey)|\(Int(now.timeIntervalSince1970))", fireDate: now, title: mail.sender, body: mail.subject,
                          eventID: nil, meetCode: nil, account: nil, threadKey: mail.threadKey, kind: .mail)
        }
    }

    /// The mails on the iPhone (Paul, 20/11: « comme si c'était Gmail qui me l'affichait »): each one, its sender, its
    /// subject and its first words, grouped by thread; past ten at once, one line for the rest.
    public static func phoneMailNotices(_ mails: [(threadKey: String, sender: String, subject: String, snippet: String)], now: Date) -> [PlannedNotice] {
        let shown = mails.prefix(10).map { mail in
            PlannedNotice(id: "mail|\(mail.threadKey)|\(Int(now.timeIntervalSince1970))", fireDate: now, title: mail.sender,
                          body: mail.snippet.isEmpty ? mail.subject : mail.snippet, eventID: nil, meetCode: nil, account: nil,
                          threadKey: mail.threadKey, kind: .mail, subtitle: mail.snippet.isEmpty ? nil : mail.subject)
        }
        guard mails.count > 10 else { return shown }
        let rest = mails.count - 10
        return shown + [PlannedNotice(id: "mails|\(Int(now.timeIntervalSince1970))", fireDate: now,
                                      title: rest == 1 ? "1 autre nouveau mail" : "\(rest) autres nouveaux mails",
                                      body: mails.dropFirst(10).prefix(3).map(\.sender).joined(separator: ", ") + (rest > 3 ? "…" : ""),
                                      eventID: nil, meetCode: nil, account: nil, kind: .mail)]
    }

    /// The drafts an agent just prepared (18/11), said by Colin: one notice each, or one line for more than three.
    /// `recipient`: the first name of who the mail is written to, empty when nobody yet. A click opens the Accueil,
    /// where they wait at the head of « À valider ». The same draft said again replaces its notice. « À relire. », the
    /// word of the button that waits for them (lot 10, 20/11: « On le valide ? »).
    public static func draftNotices(_ drafts: [(id: String, recipient: String, threadKey: String?)], now: Date) -> [PlannedNotice] {
        guard drafts.count <= 3 else {
            return [PlannedNotice(id: "brouillons|\(Int(now.timeIntervalSince1970))", fireDate: now, title: "Colin",
                                  body: Words.count(drafts.count, "brouillon prêt", "brouillons prêts") + ". À relire.", eventID: nil,
                                  meetCode: nil, account: nil, kind: .draft)]
        }
        return drafts.map { draft in
            PlannedNotice(id: "brouillon|\(draft.id)", fireDate: now, title: "Colin",
                          body: (draft.recipient.isEmpty ? "Brouillon prêt." : "Brouillon prêt pour \(draft.recipient).") + " À relire.",
                          eventID: nil, meetCode: nil, account: nil, threadKey: draft.threadKey, kind: .draft)
        }
    }

    /// Not a whole day, not declined by Paul.
    static func attends(_ event: CalendarEventRow) -> Bool {
        !event.allDay && event.attendees.first(where: \.isSelf)?.response != "declined"
    }
}

/// macOS's notification center, as hub uses it: behind a protocol for the tests.
public protocol NotificationCenterClient: Sendable {
    func pendingIdentifiers() async -> [String]
    func schedule(_ notice: PlannedNotice, sound: Bool) async
    func removePending(_ ids: [String]) async
    func deliverNow(_ notice: PlannedNotice, sound: Bool) async
    /// Takes away notifications already shown (21/11: Vigie's waits that ended).
    func removeDelivered(_ ids: [String]) async
}

extension NotificationCenterClient {
    public func removeDelivered(_ ids: [String]) async {}
}

/// Brings macOS's pending reminders in line with the plan: hub's stale ones go, missing ones come; nothing else
/// is touched.
public enum ReminderSync {
    public static func apply(_ plan: [PlannedNotice], to center: any NotificationCenterClient, sound: Bool) async {
        let pending = await center.pendingIdentifiers()
        let wanted = Set(plan.map(\.id))
        let stale = pending.filter { $0.hasPrefix(NotificationPlan.reminderPrefix) && !wanted.contains($0) }
        if !stale.isEmpty { await center.removePending(stale) }
        // Every planned one is given again: macOS replaces a pending request with the same id, so a Meet added, a
        // new title or the sound turned off reach the reminders already planned (review of 14/11).
        for notice in plan {
            await center.schedule(notice, sound: sound)
        }
    }
}
