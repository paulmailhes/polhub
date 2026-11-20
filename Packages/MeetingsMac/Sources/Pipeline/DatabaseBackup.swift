import Foundation
import GRDB
import Persistence

/// One copy of the base a day, seven kept, on the same disk (design: a real backup off the M3 is still
/// to be decided with Paul).
public enum DatabaseBackup {
    public static let keep = 7
    /// The copies made before a migration (`hub-board-avant-v12-20261115.sqlite`, AppDatabase): the three newest.
    public static let keepBeforeMigration = 3

    public static func name(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return "hub-board-\(formatter.string(from: date)).sqlite"
    }

    /// The daily copies beyond the seven most recent, and those made before a migration beyond the three most
    /// recent; any other file is left alone.
    /// The copies of both names count together, by their day: `hub-board-…` since 20/11, `Polhub-…` before.
    public static func toRemove(_ names: [String]) -> [String] {
        func newestFirst(_ pattern: Regex<(Substring, Substring)>) -> [String] {
            names.compactMap { name -> (day: String, name: String)? in
                guard let match = name.wholeMatch(of: pattern) else { return nil }
                return (String(match.output.1), name)
            }
            .sorted { ($0.day, $0.name) > ($1.day, $1.name) }
            .map(\.name)
        }
        let copies = newestFirst(/(?:hub-board|Polhub)-(\d{8})\.sqlite/)
        let beforeMigration = newestFirst(/(?:hub-board|Polhub)-avant-[A-Za-z0-9_.]+-(\d{8})\.sqlite/)
        return Array(copies.dropFirst(keep)) + Array(beforeMigration.dropFirst(keepBeforeMigration))
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
