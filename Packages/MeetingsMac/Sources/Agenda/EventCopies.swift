import Foundation
import Persistence

/// An event Google puts in several of Paul's calendars (an invitation sent to two of his addresses) shows
/// once, under the account to join it with (Paul, 14/11).
public enum EventCopies {
    /// The organizing account; else the one of the organizer's domain; else a work account rather than the
    /// personal one; else the first connected.
    public static func joinAccount(for copies: [CalendarEventRow], accounts: [GoogleAccountRow]) -> String {
        let order = Dictionary(accounts.map { ($0.email, $0.addedAt) }, uniquingKeysWith: { first, _ in first })
        let owners = copies.map(\.account).sorted { (order[$0] ?? .distantFuture) < (order[$1] ?? .distantFuture) }
        guard let first = owners.first else { return "" }
        let organizer = copies.compactMap(\.organizer).first?.lowercased()
        if let organizer, owners.contains(organizer) { return organizer }
        if let organizer, let domain = domain(of: organizer), let same = owners.first(where: { self.domain(of: $0) == domain }) { return same }
        return owners.first { !AccountStyle.isPersonal($0) } ?? first
    }

    /// One row per Google event, the one of `joinAccount`. A project or a recording another copy has is
    /// carried over, Paul's filing first.
    public static func merge(_ events: [CalendarEventRow], accounts: [GoogleAccountRow]) -> [CalendarEventRow] {
        var groups: [String: [CalendarEventRow]] = [:]
        var order: [String] = []
        for event in events {
            if groups[event.eventID] == nil { order.append(event.eventID) }
            groups[event.eventID, default: []].append(event)
        }
        return order.compactMap { id in
            guard let copies = groups[id] else { return nil }
            guard copies.count > 1 else { return copies.first }
            let account = joinAccount(for: copies, accounts: accounts)
            guard var shown = copies.first(where: { $0.account == account }) ?? copies.first else { return nil }
            // The strongest reason wins: Paul's choice, then the recording, the series, the guests, the title
            // (review of 14/11, Important 7).
            if let filed = copies.filter({ $0.projectOrigin != nil }).min(by: { rank($0.projectOrigin) < rank($1.projectOrigin) }),
               rank(filed.projectOrigin) < rank(shown.projectOrigin) {
                shown.projectID = filed.projectID
                shown.projectOrigin = filed.projectOrigin
            }
            if shown.meetingID == nil { shown.meetingID = copies.compactMap(\.meetingID).first }
            return shown
        }
    }

    static func rank(_ origin: EventProjectOrigin?) -> Int {
        switch origin {
        case .paul?: 0
        case .reunion?: 1
        case .serie?: 2
        case .invites?: 3
        case .titre?: 4
        case nil: 5
        }
    }

    static func domain(of email: String) -> String? {
        email.lowercased().split(separator: "@").last.map(String.init)
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
