import Foundation

/// An event Google puts in several of Paul's calendars (an invitation sent to two of his addresses) shows once,
/// under the account to join it with (Paul, 14/11). The rule lives here since 16/11, so that the app (`EventCopies`,
/// Agenda) and the agents' helper (`agenda` of `polhub mcp`, which never links the Agenda module) read the calendars alike.
public enum CalendarCopies {
    /// A public mailbox (gmail.com and the like): Paul's personal account rather than a work one.
    public static func isPublicMailbox(_ email: String) -> Bool {
        PublicMailDomains.domain(of: email).map(PublicMailDomains.all.contains) ?? true
    }

    /// The organizing account; else the one of the organizer's domain; else a work account rather than the
    /// personal one; else the first connected.
    public static func joinAccount(for copies: [CalendarEventRow], accounts: [GoogleAccountRow],
                                   isPersonal: (String) -> Bool = isPublicMailbox) -> String {
        let order = Dictionary(accounts.map { ($0.email, $0.addedAt) }, uniquingKeysWith: { first, _ in first })
        let owners = copies.map(\.account).sorted { (order[$0] ?? .distantFuture) < (order[$1] ?? .distantFuture) }
        guard let first = owners.first else { return "" }
        let organizer = copies.compactMap(\.organizer).first?.lowercased()
        if let organizer, owners.contains(organizer) { return organizer }
        if let organizer, let domain = domain(of: organizer), let same = owners.first(where: { self.domain(of: $0) == domain }) { return same }
        return owners.first { !isPersonal($0) } ?? first
    }

    /// One row per Google event, the one of `joinAccount`. A project or a recording another copy has is
    /// carried over, Paul's filing first.
    public static func merge(_ events: [CalendarEventRow], accounts: [GoogleAccountRow],
                             isPersonal: (String) -> Bool = isPublicMailbox) -> [CalendarEventRow] {
        var groups: [String: [CalendarEventRow]] = [:]
        var order: [String] = []
        for event in events {
            if groups[event.eventID] == nil { order.append(event.eventID) }
            groups[event.eventID, default: []].append(event)
        }
        return order.compactMap { id in
            guard let copies = groups[id] else { return nil }
            guard copies.count > 1 else { return copies.first }
            let account = joinAccount(for: copies, accounts: accounts, isPersonal: isPersonal)
            guard var shown = copies.first(where: { $0.account == account }) ?? copies.first else { return nil }
            // The strongest reason wins: Paul's choice, then the recording, the series, the guests, the title
            // (review of 14/11, Important 7).
            if let filed = copies.filter({ $0.projectOrigin != nil }).min(by: { rank($0.projectOrigin) < rank($1.projectOrigin) }),
               rank(filed.projectOrigin) < rank(shown.projectOrigin) {
                shown.projectID = filed.projectID
                shown.projectOrigin = filed.projectOrigin
            }
            if shown.meetingID == nil { shown.meetingID = copies.compactMap(\.meetingID).first }
            // Paul's answer on any of his addresses counts: accepted on one, declined on the other is accepted
            // (review of 14/11).
            let answers = copies.compactMap { $0.attendees.first(where: \.isSelf)?.response }
            if let best = ["accepted", "tentative"].first(where: answers.contains), let index = shown.attendees.firstIndex(where: \.isSelf),
               shown.attendees[index].response != best, shown.attendees[index].response != "accepted" {
                shown.attendees[index].response = best
            }
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
