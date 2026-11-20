import HubLink
import SwiftUI
import UIKit
import UserNotifications

/// The notifications on the iPhone (20/11): asked once paired, the push token given to the Mac, a touch that opens
/// the mail or the calendar.
final class PhoneAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set by the app: the session that gives the token to the Mac and opens what was touched.
    @MainActor var session: PhoneSession?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in await session?.givePushToken(token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in session?.pushProblem = message }
    }

    /// Shown even while hub is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    /// A touch on a mail opens its thread; on an event, the calendar.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let thread = info["fil"] as? String
        let event = info["rendez-vous"] as? String
        Task { @MainActor in
            if let thread { self.session?.opening = .thread(thread) } else if event != nil { self.session?.opening = .calendar }
        }
        completionHandler()
    }

    /// Asks once, then registers with Apple: the token comes back above.
    @MainActor static func ask() async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }
}

extension PhoneSession {
    /// What a touched notification opens.
    enum Opening: Equatable {
        case thread(String)
        case calendar
    }
}
