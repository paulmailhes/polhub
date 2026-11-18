import Foundation

/// When Paul comes back to the Accueil (18/11): the first time he is there in a day, or after three hours away. A
/// return is when « Le point » is prepared again.
public enum Presence {
    public struct State: Codable, Equatable, Sendable {
        /// The last time the Accueil was before him.
        public var lastSeen: Date?
        /// The last time he was there before his last return: what « Depuis hier 19:40 » says.
        public var since: Date?
        /// When « Le point » was last prepared.
        public var preparedAt: Date?

        public init(lastSeen: Date? = nil, since: Date? = nil, preparedAt: Date? = nil) {
            self.lastSeen = lastSeen
            self.since = since
            self.preparedAt = preparedAt
        }
    }

    /// Away for this long, he is back.
    public static let awayAfter: TimeInterval = 3 * 3_600

    /// Paul leaves the Accueil at `now` (another app in front, another page): his absence starts then, not at his
    /// last arrival. Nothing is prepared. A departure before any arrival, or a clock that went back, says nothing.
    public static func left(_ state: State, at now: Date) -> State {
        guard let last = state.lastSeen, now > last else { return state }
        var next = state
        next.lastSeen = now
        return next
    }

    /// The Accueil is before Paul at `now`. `returned`: he is back (another day than the last time, or three hours
    /// later); `awayMinutes`: how long he was away, when he is back.
    public static func seen(_ state: State, at now: Date, calendar: Calendar) -> (state: State, returned: Bool, awayMinutes: Int?) {
        var next = state
        next.lastSeen = now
        guard let last = state.lastSeen else {
            // The very first time: nothing before it.
            next.since = nil
            next.preparedAt = now
            return (next, true, nil)
        }
        let away = now.timeIntervalSince(last)
        // A clock that went back says nothing of an absence.
        guard away >= 0, away >= awayAfter || !calendar.isDate(last, inSameDayAs: now) else { return (next, false, nil) }
        next.since = last
        next.preparedAt = now
        return (next, true, Int(away / 60))
    }
}
