import Foundation
import UserNotifications

/// What a notification carries, to know what a click opens.
public enum NoticeKey {
    public static let event = "evenement"
    public static let meet = "meet"
    public static let account = "compte"
    public static let meeting = "reunion"
    public static let thread = "fil"
    public static let folder = "dossier"
    public static let kind = "genre"
    /// The « Rejoindre » button.
    public static let joinAction = "rejoindre"
    static let joinCategory = "rendez-vous"
    static let plainCategory = "polhub"
}

/// What macOS lets hub's notifications do (lot 10, 20/11): Réglages offers to open Réglages Système when they are
/// refused, by this state, never by its words.
public enum NotificationAuthorization: Equatable, Sendable {
    case allowed, denied, notAsked, unknown

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .authorized, .provisional, .ephemeral: self = .allowed
        case .denied: self = .denied
        case .notDetermined: self = .notAsked
        @unknown default: self = .unknown
        }
    }

    /// « autorisées », « refusées dans Réglages Système », « pas encore demandées ».
    public var text: String {
        switch self {
        case .allowed: "autorisées"
        case .denied: "refusées dans Réglages Système"
        case .notAsked: "pas encore demandées"
        case .unknown: "inconnues"
        }
    }
}

/// macOS's notification center. A notification scheduled at a date is shown by macOS itself, even when hub is
/// not running; a click opens hub, which joins the Meet or opens the page (14/11).
public struct SystemNotifications: NotificationCenterClient {
    public init() {}

    private var center: UNUserNotificationCenter { .current() }

    /// The « Rejoindre » button of the events' notifications.
    public static func registerCategories() {
        let join = UNNotificationAction(identifier: NoticeKey.joinAction, title: "Rejoindre", options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: NoticeKey.joinCategory, actions: [join], intentIdentifiers: []),
            UNNotificationCategory(identifier: NoticeKey.plainCategory, actions: [], intentIdentifiers: []),
        ])
    }

    /// Asks once; macOS remembers the answer (Réglages Système › Notifications).
    public static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// What macOS lets hub's notifications do: a state, read by Réglages, its words beside it (lot 10, 20/11).
    public static func authorization() async -> NotificationAuthorization {
        NotificationAuthorization(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
    }

    public func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    public func schedule(_ notice: PlannedNotice, sound: Bool) async {
        var parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: notice.fireDate)
        parts.calendar = Calendar.current
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: notice.id, content: Self.content(notice, sound: sound), trigger: trigger))
    }

    public func removePending(_ ids: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    public func deliverNow(_ notice: PlannedNotice, sound: Bool) async {
        try? await center.add(UNNotificationRequest(identifier: notice.id, content: Self.content(notice, sound: sound), trigger: nil))
    }

    static func content(_ notice: PlannedNotice, sound: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.sound = sound ? .default : nil
        content.categoryIdentifier = notice.joinable ? NoticeKey.joinCategory : NoticeKey.plainCategory
        var info: [String: String] = [NoticeKey.kind: notice.kind.rawValue]
        info[NoticeKey.event] = notice.eventID
        info[NoticeKey.meet] = notice.meetCode
        info[NoticeKey.account] = notice.account
        info[NoticeKey.meeting] = notice.meetingID?.uuidString
        info[NoticeKey.thread] = notice.threadKey
        info[NoticeKey.folder] = notice.folder
        content.userInfo = info
        // One thread per event: its reminders stack together.
        content.threadIdentifier = notice.eventID ?? notice.kind.rawValue
        return content
    }
}
