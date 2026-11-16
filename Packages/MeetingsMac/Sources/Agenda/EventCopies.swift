import Foundation
import Persistence

/// An event Google puts in several of Paul's calendars (an invitation sent to two of his addresses) shows
/// once, under the account to join it with (Paul, 14/11). The rule itself is `CalendarCopies` (Persistence, 16/11),
/// which the agents' helper reads too; here, a personal account is one `AccountStyle` calls so.
public enum EventCopies {
    /// The organizing account; else the one of the organizer's domain; else a work account rather than the
    /// personal one; else the first connected.
    public static func joinAccount(for copies: [CalendarEventRow], accounts: [GoogleAccountRow]) -> String {
        CalendarCopies.joinAccount(for: copies, accounts: accounts, isPersonal: AccountStyle.isPersonal)
    }

    /// One row per Google event, the one of `joinAccount`. A project or a recording another copy has is
    /// carried over, Paul's filing first.
    public static func merge(_ events: [CalendarEventRow], accounts: [GoogleAccountRow]) -> [CalendarEventRow] {
        CalendarCopies.merge(events, accounts: accounts, isPersonal: AccountStyle.isPersonal)
    }
}

/// The link that opens a Meet under the given Google account.
public enum MeetJoin {
    public static func url(code: String, account: String) -> URL {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        let value = account.addingPercentEncoding(withAllowedCharacters: allowed) ?? account
        return URL(string: "https://meet.google.com/\(code)?authuser=\(value)")!
    }
}
