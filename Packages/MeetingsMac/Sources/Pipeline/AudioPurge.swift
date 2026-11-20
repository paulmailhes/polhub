import Domain
import Foundation
import Persistence
import HubDesign

/// Audio is kept 30 days, counted from the transcription (validated choice): a meeting recorded before
/// step 2 keeps its audio until it is transcribed. Detection journals are kept 30 days too.
public enum AudioPurge {
    public static let keepDays = 30

    public static let warnDays = 23

    /// Transcribed 30 days ago; or, when the transcription failed for good, ended 30 days ago (validated
    /// choice: the audio of a failed transcription goes like the others, with an alert from day 23).
    public static func due(_ rows: [MeetingRow], failed: Set<UUID> = [], now: Date) -> [MeetingRow] {
        let limit = now.addingTimeInterval(-Double(keepDays) * 86_400)
        return rows.filter { row in
            guard row.audioPurgedAt == nil, row.deletedAt == nil else { return false }
            if let transcribed = row.transcribedAt { return transcribed <= limit }
            return failed.contains(row.id) && (row.endedAt ?? row.startedAt) <= limit
        }
    }

    /// The alerts of the day for failed transcriptions entering their last week (one day long window: the
    /// maintenance runs once a day).
    public static func warnings(_ rows: [MeetingRow], failed: Set<UUID>, now: Date) -> [JournalEntry] {
        rows.compactMap { row in
            guard failed.contains(row.id), row.transcribedAt == nil, row.audioPurgedAt == nil, row.deletedAt == nil else { return nil }
            let age = now.timeIntervalSince(row.endedAt ?? row.startedAt) / 86_400
            guard age >= Double(warnDays), age < Double(warnDays + 1) else { return nil }
            let left = Int((Double(keepDays) - age).rounded(.up))
            return JournalEntry(
                createdAt: now, kind: .alert,
                // « supprimé », as the meeting's page says it; the days accorded by `Words` (lot 10, 20/11).
                message: "L'audio de « \(row.title) » sera supprimé dans \(Words.count(left, "jour")) : sa transcription a échoué. « Réessayer » dans la fenêtre.",
                meetingID: row.id
            )
        }
    }

    /// `detection-<yyyyMMdd>.jsonl` files older than 30 days.
    public static func expiredLogs(_ names: [String], now: Date) -> [String] {
        let limit = now.addingTimeInterval(-Double(keepDays) * 86_400)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return names.filter { name in
            guard let match = name.firstMatch(of: /^detection-(\d{8})\.jsonl$/),
                  let day = formatter.date(from: String(match.output.1)) else { return false }
            return day < limit
        }
    }

    /// Returns the number of meetings whose audio was removed.
    @discardableResult
    public static func run(store: MeetingStore, paths: AppPaths, now: Date) throws -> Int {
        let manager = FileManager.default
        var purged = 0
        let rows = try store.recent(limit: 100_000)
        let failed = Set(try TranscriptStore(store.database).latestJobs().values.filter { $0.state == .failed }.map(\.meetingID))
        for warning in warnings(rows, failed: failed, now: now) {
            try? store.addJournal(warning)
        }
        for var row in due(rows, failed: failed, now: now) {
            // The raw audio and the 16 kHz archive; the dialogue stays (base and meeting.json).
            for name in ["audio", "pistes"] {
                try? manager.removeItem(at: paths.meetingFolder(row.id).appending(path: name, directoryHint: .isDirectory))
            }
            row.audioPurgedAt = now
            row.updatedAt = now
            try store.save(row)
            purged += 1
        }
        let logs = (try? manager.contentsOfDirectory(atPath: paths.logs.path)) ?? []
        for name in expiredLogs(logs, now: now) {
            try? manager.removeItem(at: paths.logs.appending(path: name))
        }
        return purged
    }
}
