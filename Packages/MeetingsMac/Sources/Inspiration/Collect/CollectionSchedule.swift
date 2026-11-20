import Foundation

/// When each collection is due (16/11), as n8n ran them, with no timer here: the app asks.
/// - Websites: every two hours from 8:00 to 22:00 (Awwwards publishes at a variable time).
/// - Branding: at 9, 14 and 20 h.
/// - A slot missed while the Mac slept or hub was closed is caught up once, at the next check (wake, launch,
///   the periodic timer), however many were missed.
public struct CollectionSchedule: Sendable, Equatable {
    /// The hours of each job's slots, on the hour, local time.
    public var hours: [CollectionJob: [Int]]
    public var calendar: Calendar

    public static let websiteHours = Array(stride(from: 8, through: 22, by: 2))
    public static let brandingHours = [9, 14, 20]

    public init(hours: [CollectionJob: [Int]] = [.websites: CollectionSchedule.websiteHours, .branding: CollectionSchedule.brandingHours],
                calendar: Calendar = .current) {
        self.hours = hours
        self.calendar = calendar
    }

    /// The job's slots of the day of `day`, in order.
    public func slots(_ job: CollectionJob, on day: Date) -> [Date] {
        let start = calendar.startOfDay(for: day)
        return (hours[job] ?? []).sorted().compactMap { hour in
            calendar.date(bySettingHour: hour, minute: 0, second: 0, of: start)
        }
    }

    /// The last slot at or before `now` (today's, else a previous day's).
    public func lastSlot(_ job: CollectionJob, atOrBefore now: Date) -> Date? {
        guard !(hours[job] ?? []).isEmpty else { return nil }
        for daysBack in 0...2 {
            guard let day = calendar.date(byAdding: .day, value: -daysBack, to: now) else { continue }
            if let slot = slots(job, on: day).last(where: { $0 <= now }) { return slot }
        }
        return nil
    }

    /// The first slot after `now`.
    public func nextSlot(_ job: CollectionJob, after now: Date) -> Date? {
        guard !(hours[job] ?? []).isEmpty else { return nil }
        for daysAhead in 0...2 {
            guard let day = calendar.date(byAdding: .day, value: daysAhead, to: now) else { continue }
            if let slot = slots(job, on: day).first(where: { $0 > now }) { return slot }
        }
        return nil
    }

    /// Due when a slot has passed since the last run (never run: due at once). Several missed slots make one run.
    public func isDue(_ job: CollectionJob, lastRun: Date?, now: Date) -> Bool {
        guard let slot = lastSlot(job, atOrBefore: now) else { return false }
        guard let lastRun else { return true }
        return lastRun < slot
    }

    /// The jobs to run now, websites first.
    public func due(lastRuns: [CollectionJob: Date], now: Date) -> [CollectionJob] {
        CollectionJob.allCases.filter { isDue($0, lastRun: lastRuns[$0], now: now) }
    }

    /// The next moment a job falls due: when the app's timer should check again.
    public func nextCheck(after now: Date) -> Date? {
        CollectionJob.allCases.compactMap { nextSlot($0, after: now) }.min()
    }
}

/// When each collection last ran, and how Awwwards' last reading went: kept in the app's preferences (not
/// settings Paul sees), so that a relaunch knows what is due and Réglages shows the last state.
public struct CollectionRunLog: @unchecked Sendable {
    let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func lastRunKey(_ job: CollectionJob) -> String { "inspiration.collecte.dernierPassage.\(job.rawValue)" }
    static let awwwardsKey = "inspiration.collecte.etatAwwwards"

    public func lastRun(_ job: CollectionJob) -> Date? {
        defaults.object(forKey: Self.lastRunKey(job)) as? Date
    }

    public var lastRuns: [CollectionJob: Date] {
        Dictionary(uniqueKeysWithValues: CollectionJob.allCases.compactMap { job in lastRun(job).map { (job, $0) } })
    }

    public func setLastRun(_ job: CollectionJob, _ date: Date) {
        defaults.set(date, forKey: Self.lastRunKey(job))
    }

    /// Awwwards' last reading.
    public var awwwards: CollectionStatus? {
        guard let stored = defaults.dictionary(forKey: Self.awwwardsKey), let date = stored["date"] as? Date else { return nil }
        let outcome: CollectionStatus.Outcome = (stored["probleme"] as? String).map { .failed($0) }
            ?? .read(newItems: stored["nouveaux"] as? Int)
        return CollectionStatus(source: .awwwards, name: "Awwwards", date: date, outcome: outcome)
    }

    public func setAwwwards(_ status: CollectionStatus) {
        var stored: [String: Any] = ["date": status.date]
        if let problem = status.problem { stored["probleme"] = problem }
        if case .read(let count?) = status.outcome { stored["nouveaux"] = count }
        defaults.set(stored, forKey: Self.awwwardsKey)
    }

    static let unreadableKey = "inspiration.collecte.postsIllisibles"
    /// The unreadable posts remembered: far more than the ten a page shows, each studio's.
    static let unreadableKept = 500

    /// The posts found on a page that gave neither words nor image (a video, a page LinkedIn changed): never asked
    /// again (review of 16/11).
    public var unreadablePosts: Set<String> {
        Set(defaults.stringArray(forKey: Self.unreadableKey) ?? [])
    }

    public func addUnreadable(_ urns: [String]) {
        guard !urns.isEmpty else { return }
        var kept = defaults.stringArray(forKey: Self.unreadableKey) ?? []
        for urn in urns where !kept.contains(urn) { kept.append(urn) }
        defaults.set(Array(kept.suffix(Self.unreadableKept)), forKey: Self.unreadableKey)
    }
}
