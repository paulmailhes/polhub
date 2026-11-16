import Foundation

/// The days the copy of a calendar holds: each sync reads Google again from 180 days before it to 60 days after it
/// (plan of 13/11). The rule lives here since 16/11, so that the app (`CalendarSync`, Agenda) and the agents' helper
/// (`agenda` of `polhub mcp`, which never links the Agenda module) agree on what the copy knows.
public enum CalendarWindow {
    public static let past: TimeInterval = 180 * 86_400
    public static let future: TimeInterval = 60 * 86_400

    /// What every account read holds: from the latest reading's start to the oldest reading's end; `nil` when none was
    /// ever read.
    public static func covered(by accounts: [GoogleAccountRow]) -> (from: Date, to: Date)? {
        let readings = accounts.compactMap(\.lastSyncAt)
        guard let newest = readings.max(), let oldest = readings.min() else { return nil }
        return (newest.addingTimeInterval(-past), oldest.addingTimeInterval(future))
    }
}
