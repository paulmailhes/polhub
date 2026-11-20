import HubLink
import UserNotifications

/// hub's notifications reach the iPhone sealed (20/11): Apple carries « Nouveau mail » and a sealed text. This extension
/// opens it with the key the app made, and shows the sender, the subject and the first words, as Gmail would; with no key
/// or a text it cannot open, the notification stays as it came.
final class NotificationService: UNNotificationServiceExtension {
    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent,
              let sealed = request.content.userInfo["hub"] as? String, let key = PushKeyStore.key(create: false),
              let opened = PushSeal.open(sealed, key: key) else {
            contentHandler(request.content)
            return
        }
        content.title = opened.title
        content.subtitle = opened.subtitle ?? ""
        content.body = opened.body
        contentHandler(content)
    }
}
