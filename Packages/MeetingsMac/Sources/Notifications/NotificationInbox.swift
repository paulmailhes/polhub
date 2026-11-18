import Combine
import Foundation

// Polhub's own list of the notifications it sent (Paul, 15/11: « un système de notification dans l'outil »): every
// notification macOS showed is kept here too, in a small file outside the base, so Paul finds it again in the app.

/// The part of Polhub a notification belongs to: its color and symbol in the list.
public enum NoticeSection: String, Sendable {
    case calendar, meetings, mails, polhub
    /// The Accueil: what Colin says (18/11).
    case home
}

extension PlannedNotice.Kind {
    public var section: NoticeSection {
        switch self {
        case .reminder, .newEvent: .calendar
        case .unrecorded, .summary: .meetings
        case .mail: .mails
        case .test: .polhub
        case .draft: .home
        }
    }
}

/// What a click on a notification opens, the same from macOS's center and from Polhub's list.
public enum NoticeAction: Equatable, Sendable {
    /// The Meet, with the event's account.
    case join(meetCode: String, account: String)
    case meeting(UUID)
    /// The event's card in Calendrier (`account|eventID`).
    case event(String)
    /// Calendrier: « Nouveaux rendez-vous », several at once.
    case calendar
    /// A thread of Mails (`account|threadID`).
    case mailThread(String)
    /// The mails' folder it names (« Programmés », « Brouillons »…), the list when none.
    case mailFolder(String?)
    /// Nothing to open but the window (the test).
    case window
    /// The Accueil: a draft ready waits there, at the head of « À valider » (18/11).
    case home

    /// A mail opens its thread, else its folder; a reminder or a meeting not recorded joins the Meet when `join`
    /// (« Rejoindre », or a click on it); otherwise the meeting, the event, or Calendrier (review of 14/11).
    public static func of(kind: PlannedNotice.Kind?, eventID: String?, meetCode: String?, account: String?, meetingID: UUID?,
                          threadKey: String?, folder: String?, join: Bool) -> NoticeAction {
        switch kind {
        case .mail:
            return threadKey.map(NoticeAction.mailThread) ?? .mailFolder(folder)
        case .test:
            return .window
        case .draft:
            return .home
        default:
            if join, let meetCode, let account { return .join(meetCode: meetCode, account: account) }
            if let meetingID { return .meeting(meetingID) }
            if let eventID { return .event(eventID) }
            return .calendar
        }
    }
}

/// One notification as Polhub's list keeps it: what macOS showed, and what a click opens.
public struct InboxNotice: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// Shared by the repeats of one kind for one event, meeting or thread: the list keeps one card for them.
    public var key: String
    public var date: Date
    public var title: String
    public var body: String
    public var kind: PlannedNotice.Kind
    public var eventID: String?
    public var meetCode: String?
    public var account: String?
    public var meetingID: UUID?
    public var threadKey: String?
    public var folder: String?
    /// How many notifications this card stands for: repeats collapse into one, the latest on top.
    public var count: Int
    public var seen: Bool

    public init(_ notice: PlannedNotice, at date: Date, id: UUID = UUID(), seen: Bool = false) {
        self.id = id
        key = Self.key(notice)
        self.date = date
        title = notice.title
        body = notice.body
        kind = notice.kind
        eventID = notice.eventID
        meetCode = notice.meetCode
        account = notice.account
        meetingID = notice.meetingID
        threadKey = notice.threadKey
        folder = notice.folder
        count = 1
        self.seen = seen
    }

    /// Two reminders of one event, two mails of one thread: one key.
    static func key(_ notice: PlannedNotice) -> String {
        let subject: String = switch notice.kind {
        case .reminder, .newEvent, .unrecorded: notice.eventID ?? notice.title
        case .summary: notice.meetingID?.uuidString ?? notice.title
        case .mail: notice.threadKey ?? "\(notice.folder ?? "")|\(notice.title)"
        case .test: "essai"
        // One card by draft, whatever its thread: its notice carries its name.
        case .draft: notice.id
        }
        return "\(notice.kind.rawValue)|\(subject)"
    }

    /// From the list, a click joins the Meet only while it is still time: a reminder or a meeting not recorded of
    /// the last half hour. Past that, the event opens: its card has « Rejoindre » if the meeting still runs.
    public func action(now: Date) -> NoticeAction {
        let join = (kind == .reminder || kind == .unrecorded) && now.timeIntervalSince(date) < NotificationInbox.joinWindow
        return .of(kind: kind, eventID: eventID, meetCode: meetCode, account: account, meetingID: meetingID, threadKey: threadKey,
                   folder: folder, join: join)
    }
}

/// The notifications Polhub sent, newest first: kept 30 days, at most 100, the repeats of one thread or one event
/// collapsed into one card. Saved in a small JSON file (no migration of the base); `nil` keeps them in memory.
@MainActor
public final class NotificationInbox: ObservableObject {
    nonisolated public static let keepDays = 30
    nonisolated public static let limit = 100
    /// Repeats closer than this collapse into one card (the 10- and 1-minute reminders, a thread's replies of a day).
    nonisolated public static let collapseWindow: TimeInterval = 12 * 3_600
    /// From the list, a reminder still joins the Meet this long after it came.
    nonisolated public static let joinWindow: TimeInterval = 30 * 60

    @Published public private(set) var notices: [InboxNotice]
    let file: URL?
    let now: () -> Date

    public init(file: URL?, now: @escaping () -> Date = Date.init) {
        self.file = file
        self.now = now
        notices = Self.prune(Self.load(file), now: now())
    }

    /// The badge of the bell.
    public var unreadCount: Int { notices.count(where: { !$0.seen }) }

    /// A notification macOS showed (`at`: when it came, now by default).
    public func record(_ notice: PlannedNotice, at date: Date? = nil) {
        let date = date ?? now()
        var entry = InboxNotice(notice, at: date)
        if let index = notices.firstIndex(where: { $0.key == entry.key && abs($0.date.timeIntervalSince(date)) < Self.collapseWindow }) {
            let earlier = notices.remove(at: index)
            // The newest text wins; the card keeps its identity, counts one more and is unread again.
            if earlier.date > date { entry = earlier }
            entry.id = earlier.id
            entry.count = earlier.count + 1
            entry.seen = false
        }
        notices = Self.prune(notices + [entry], now: max(now(), date))
        save()
    }

    /// The panel opened: the badge goes.
    public func markAllSeen() {
        guard notices.contains(where: { !$0.seen }) else { return }
        for index in notices.indices { notices[index].seen = true }
        save()
    }

    /// The × of a card, or of a stack.
    public func remove(_ ids: Set<UUID>) {
        notices.removeAll { ids.contains($0.id) }
        save()
    }

    /// « Tout effacer ».
    public func removeAll() {
        notices = []
        save()
    }

    /// Newest first, the last 30 days, at most 100.
    static func prune(_ notices: [InboxNotice], now: Date) -> [InboxNotice] {
        let oldest = now.addingTimeInterval(-Double(keepDays) * 86_400)
        return Array(notices.filter { $0.date > oldest }.sorted { ($0.date, $0.id.uuidString) > ($1.date, $1.id.uuidString) }.prefix(limit))
    }

    private struct Archive: Codable {
        var version = 1
        var notices: [InboxNotice]
    }

    static func load(_ file: URL?) -> [InboxNotice] {
        guard let file, let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode(Archive.self, from: data))?.notices ?? []
    }

    private func save() {
        guard let file else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Archive(notices: notices)) else { return }
        try? data.write(to: file, options: .atomic)
    }
}

/// The list as the panel shows it: by day (« Aujourd'hui », « Hier »…), and a burst of one part of Polhub (several
/// notifications a few minutes apart) stacked into one group, as in macOS's Notification Center.
public enum NoticeFeed {
    /// Two notifications of one part of Polhub this close stack together.
    public static let burstGap: TimeInterval = 10 * 60

    public struct Group: Identifiable, Equatable, Sendable {
        /// Newest first.
        public var notices: [InboxNotice]
        public var id: UUID { notices[0].id }
        public var section: NoticeSection { notices[0].kind.section }
    }

    public struct Day: Identifiable, Equatable, Sendable {
        public var start: Date
        public var title: String
        public var groups: [Group]
        public var id: Date { start }
    }

    public static func days(_ notices: [InboxNotice], now: Date, calendar: Calendar = .current) -> [Day] {
        var days: [Day] = []
        for notice in notices.sorted(by: { $0.date > $1.date }) {
            let start = calendar.startOfDay(for: notice.date)
            if days.last?.start != start {
                days.append(Day(start: start, title: title(of: start, now: now, calendar: calendar), groups: []))
            }
            let day = days.count - 1
            if let group = days[day].groups.last, group.section == notice.kind.section,
               let previous = group.notices.last, previous.date.timeIntervalSince(notice.date) <= burstGap {
                days[day].groups[days[day].groups.count - 1].notices.append(notice)
            } else {
                days[day].groups.append(Group(notices: [notice]))
            }
        }
        return days
    }

    /// « Aujourd'hui », « Hier », « Mercredi » within the week, then « Mercredi 5 novembre ».
    public static func title(of day: Date, now: Date, calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: now), start = calendar.startOfDay(for: day)
        if start == today { return "Aujourd'hui" }
        let ago = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        if ago == 1 { return "Hier" }
        let style = format(calendar)
        let text = day.formatted(ago < 7 ? style.weekday(.wide) : style.weekday(.wide).day().month(.wide))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// « À l'instant », « il y a 5 min », then the time: the day is in the heading.
    public static func time(of date: Date, now: Date, calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "À l'instant" }
        if seconds < 3_600 { return "il y a \(Int(seconds / 60)) min" }
        return date.formatted(format(calendar).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private static func format(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(locale: Locale(identifier: "fr_FR"), calendar: calendar, timeZone: calendar.timeZone)
    }
}
