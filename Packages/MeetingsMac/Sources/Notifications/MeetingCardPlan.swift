import Foundation
import Persistence
import HubDesign

/// The card that stays at the top right of the screen before a meeting with a Meet, with « Rejoindre » (Paul,
/// 16/11: macOS's banners « s'en vont direct »). Pure: the panel is the app's (`MeetingCardPresenter`).
public enum MeetingCardPlan {
    /// How long after its start a card stays when Paul neither joined nor closed it.
    public static let lingers: TimeInterval = 10 * 60
    /// The cards shown at once, the soonest first.
    public static let maxCards = 3
    /// « 1 min », « 2 min », « 5 min » before (Réglages › Notifications).
    public static let choices = [1, 2, 5]
    public static let defaultMinutes = 2

    /// One occurrence of an event: closing its card hides that one only, the next one of a series still comes.
    public static func key(_ event: CalendarEventRow) -> String {
        "\(event.eventID)|\(Int(event.startAt.timeIntervalSince1970))"
    }

    /// The events whose card shows now: a Meet Paul attends, from `minutes` before its start to ten minutes after
    /// (never past its end), not closed, and not the meeting hub records or offers to record (Paul is in it).
    public static func due(_ events: [CalendarEventRow], now: Date, minutes: Int, closed: Set<String>, meetingCode: String?) -> [CalendarEventRow] {
        let current = meetingCode?.lowercased()
        var seen: Set<String> = []
        return events
            .filter { event in
                guard let code = event.meetCode, NotificationPlan.attends(event), code.lowercased() != current else { return false }
                let opens = event.startAt.addingTimeInterval(-Double(max(0, minutes)) * 60)
                let ends = min(event.endAt, event.startAt.addingTimeInterval(lingers))
                return now >= opens && now < ends && !closed.contains(key(event))
            }
            .sorted { ($0.startAt, $0.eventID, $0.account) < ($1.startAt, $1.eventID, $1.account) }
            // The same event in two calendars: one card.
            .filter { seen.insert(key($0)).inserted }
            .prefix(maxCards)
            .map { $0 }
    }

    /// « dans 2 min », « maintenant » for the first minute, then « commencé il y a 3 min »: a meta, in small letters, by
    /// `Words` (lot 10, 20/11: « Dans 2 min », « Maintenant », « Commencé… »).
    public static func when(_ start: Date, now: Date) -> String {
        if now.timeIntervalSince(start) < 60 { return Words.until(start, now: now) }
        return "commencé " + Words.ago(start, now: now)
    }
}
