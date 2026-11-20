import Foundation
import Notifications

/// The number on hub's icon, in the Dock and on the iPhone (Paul, 20/11: « un nombre de notifications qui mélangent
/// un peu les mails et tout »): the unread mails of the main tab, and what hub told that Paul did not see yet; a
/// mail's notice is counted by its mail.
public enum AppBadge {
    public static func count(unreadMails: Int, notices: [InboxNotice]) -> Int {
        unreadMails + notices.count { !$0.seen && $0.kind != .mail }
    }

    /// What the Dock shows: nothing at zero, « 99+ » past it.
    public static func label(_ count: Int) -> String? {
        count <= 0 ? nil : count > 99 ? "99+" : String(count)
    }
}
