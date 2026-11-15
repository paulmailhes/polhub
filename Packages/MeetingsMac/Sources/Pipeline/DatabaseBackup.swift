import Foundation
import GRDB
import Persistence

/// One copy of the base a day, seven kept, on the same disk (design: a real backup off the M3 is still
/// to be decided with Paul).
public enum DatabaseBackup {
    public static let keep = 7
    /// The copies made before a migration (`Polhub-avant-v12-20261115.sqlite`, AppDatabase): the three newest.
    public static let keepBeforeMigration = 3

    public static func name(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return "Polhub-\(formatter.string(from: date)).sqlite"
    }

    /// The daily copies beyond the seven most recent, and those made before a migration beyond the three most
    /// recent; any other file is left alone.
    public static func toRemove(_ names: [String]) -> [String] {
        let copies = names.filter { $0.wholeMatch(of: /Polhub-\d{8}\.sqlite/) != nil }.sorted(by: >)
        let beforeMigration = names.compactMap { name -> (day: String, name: String)? in
            guard let match = name.wholeMatch(of: /Polhub-avant-[A-Za-z0-9_.]+-(\d{8})\.sqlite/) else { return nil }
            return (String(match.output.1), name)
        }
        .sorted { ($0.day, $0.name) > ($1.day, $1.name) }
        .map(\.name)
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
