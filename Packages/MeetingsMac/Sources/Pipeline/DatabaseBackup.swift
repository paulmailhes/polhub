import Foundation
import GRDB
import Persistence

/// One copy of the base a day, seven kept, on the same disk (design: a real backup off the M3 is still
/// to be decided with Paul).
public enum DatabaseBackup {
    public static let keep = 7

    public static func name(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return "Transcriptor-\(formatter.string(from: date)).sqlite"
    }

    /// The copies beyond the seven most recent; any other file is left alone.
    public static func toRemove(_ names: [String]) -> [String] {
        let copies = names.filter { $0.wholeMatch(of: /Transcriptor-\d{8}\.sqlite/) != nil }.sorted(by: >)
        return Array(copies.dropFirst(keep))
    }

    public static func run(_ database: AppDatabase, into folder: URL, now: Date) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appending(path: name(for: now))
        if !manager.fileExists(atPath: target.path) {
            try database.writer.backup(to: DatabaseQueue(path: target.path))
        }
        for old in toRemove((try? manager.contentsOfDirectory(atPath: folder.path)) ?? []) {
            try? manager.removeItem(at: folder.appending(path: old))
        }
    }
}
