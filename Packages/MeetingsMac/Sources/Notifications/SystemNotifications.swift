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

/// macOS's notification center. A notification scheduled at a date is shown by macOS itself, even when Polhub is
/// not running; a click opens Polhub, which joins the Meet or opens the page (14/11).
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

    /// « autorisées », « refusées », « pas encore demandées ».
    public static func authorizationText() async -> String {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: "autorisées"
        case .denied: "refusées dans Réglages Système"
        case .notDetermined: "pas encore demandées"
        @unknown default: "inconnues"
        }
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
