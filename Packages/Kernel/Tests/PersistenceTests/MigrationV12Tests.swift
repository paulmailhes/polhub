import Domain
import Foundation
import GRDB
import Testing
@testable import Persistence

/// Base v12 (15/11): the seven statuses of the vault become four, on a base that holds every old one.
@Suite struct MigrationV12Tests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)

    /// (name, old status, kanbanOrder, in the bin).
    static let cards: [(String, String, Double, Bool)] = [
        ("P1 b", "priorité 1", 1, false), ("P1 a", "priorité 1", 0, false),
        ("P2 a", "priorité 2", 0, false), ("P2 b", "priorité 2", 1, false),
        ("Idée a", "idée", 0, false), ("Idée b", " idée ", 0, false),
        ("P3 a", "priorité 3", 3, false), ("P3 b", "priorité 3", 2, false),
        ("Attente", "en attente", 5, false), ("Sans", "", 0, false), ("Autre", "à voir", 0, false),
        ("Fini b", "terminé", 1, false), ("Fini a", "terminé", 0, false),
        ("Jeté", "idée", 42, true),
    ]

    func oldBase() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v11")
        try queue.write { db in try insert(Self.cards, into: db) }
        return queue
    }

    func insert(_ cards: [(String, String, Double, Bool)], into db: Database) throws {
        for (name, status, order, deleted) in cards {
            try db.execute(sql: """
                INSERT INTO project (id, name, status, contacts, notes, kanbanOrder, lastEditedAt, createdAt, updatedAt, deletedAt)
                VALUES (?, ?, ?, '[]', '', ?, ?, ?, ?, ?)
                """, arguments: [UUID().uuidString.lowercased(), name, status, order, now, now, now, deleted ? now : nil])
        }
    }

    func column(_ db: Database, _ status: String) throws -> [String] {
        try String.fetchAll(db, sql: "SELECT name FROM project WHERE status = ? AND deletedAt IS NULL ORDER BY kanbanOrder", arguments: [status])
    }

    @Test func everyOldStatusFindsItsColumnInOrder() throws {
        let queue = try oldBase()
        try AppDatabase.migrator.migrate(queue)
        try queue.read { db in
            let counts = Dictionary(uniqueKeysWithValues: try Row.fetchAll(db, sql: """
                SELECT status, COUNT(*) AS n FROM project WHERE deletedAt IS NULL GROUP BY status
                """).map { ($0["status"] as String, $0["n"] as Int) })
            #expect(counts == ["priorité 1": 6, "priorité 2": 2, "en pause": 3, "terminé": 2])
            // The old P1 first, then the old P2, then the ideas; each by its old place, then its name.
            #expect(try column(db, "priorité 1") == ["P1 a", "P1 b", "P2 a", "P2 b", "Idée a", "Idée b"])
            #expect(try column(db, "priorité 2") == ["P3 b", "P3 a"])
            #expect(try column(db, "en pause") == ["Attente", "Sans", "Autre"])
            #expect(try column(db, "terminé") == ["Fini a", "Fini b"])
            let orders = try Double.fetchAll(db, sql: "SELECT kanbanOrder FROM project WHERE status = 'priorité 1' AND deletedAt IS NULL ORDER BY kanbanOrder")
            #expect(orders == [0, 1, 2, 3, 4, 5])
            // In the bin: a new status, its old place.
            let bin = try #require(try Row.fetchOne(db, sql: "SELECT status, kanbanOrder FROM project WHERE deletedAt IS NOT NULL"))
            #expect(bin["status"] as String == "priorité 1" && bin["kanbanOrder"] as Double == 42)
            // The signs of life stay.
            #expect(try Date.fetchAll(db, sql: "SELECT lastEditedAt FROM project").allSatisfy { $0 == now })
            #expect(try Date.fetchAll(db, sql: "SELECT updatedAt FROM project").allSatisfy { $0 == now })
        }
    }

    /// Review of 15/11: every row decodes after it, the bin included, and the mails' rules still read.
    @Test func everyRowDecodesAfterwardsAndTheMailRulesRead() throws {
        let queue = try oldBase()
        try AppDatabase.migrator.migrate(queue)
        let all = try queue.read { try ProjectRow.fetchAll($0) }
        #expect(all.count == Self.cards.count)
        let rules = try queue.read(MailStore.rules)
        #expect(rules.projects.count == Self.cards.count)
    }

    // MARK: - Before a migration, on a real file

    func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func aBaseAboutToMigrateIsCopiedFirst() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "Polhub.sqlite").path(percentEncoded: false)
        do {
            let queue = try DatabaseQueue(path: path)
            try AppDatabase.migrator.migrate(queue, upTo: "v11")
            try queue.write { db in try insert([("Ancien", "idée", 0, false)], into: db) }
        }
        let database = try AppDatabase(path: path)
        #expect(try database.writer.read { try String.fetchOne($0, sql: "SELECT status FROM project") } == "priorité 1")
        let backups = folder.appending(path: "Sauvegardes", directoryHint: .isDirectory)
        let copies = try FileManager.default.contentsOfDirectory(atPath: backups.path(percentEncoded: false)).filter { $0.hasSuffix(".sqlite") }
        #expect(copies.count == 1 && copies[0].hasPrefix("Polhub-avant-v12-") && copies[0].hasSuffix(".sqlite"))
        let copy = try DatabaseQueue(path: backups.appending(path: copies[0]).path(percentEncoded: false))
        #expect(try copy.read { try String.fetchOne($0, sql: "SELECT status FROM project") } == "idée")
        // Opened again, nothing left to migrate: no other copy.
        _ = try AppDatabase(path: path)
        #expect(try FileManager.default.contentsOfDirectory(atPath: backups.path(percentEncoded: false)).filter { $0.hasSuffix(".sqlite") }.count == 1)
    }

    /// Correctifs du 15/11 : une copie qui échoue en route (disque plein, Polhub arrêté) ne laisse rien sous le nom
    /// de la copie, et l'ouverture suivante en fait une vraie avant de migrer.
    @Test func aFailedCopyLeavesNothingAndTheNextOpeningCopiesAgain() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "Polhub.sqlite").path(percentEncoded: false)
        let queue = try DatabaseQueue(path: path)
        try AppDatabase.migrator.migrate(queue, upTo: "v11")
        try queue.write { db in try insert([("Ancien", "idée", 0, false)], into: db) }
        let backups = folder.appending(path: "Sauvegardes", directoryHint: .isDirectory)
        struct DiskFull: Error {}
        #expect(throws: DiskFull.self) {
            try AppDatabase.protect(queue, backups: backups, now: Date()) { _, target in
                // As SQLite does: the file is made, then the copy fails.
                FileManager.default.createFile(atPath: target, contents: Data())
                throw DiskFull()
            }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: backups.path(percentEncoded: false)).isEmpty)
        try AppDatabase.protect(queue, backups: backups, now: Date())
        let copies = try FileManager.default.contentsOfDirectory(atPath: backups.path(percentEncoded: false))
        #expect(copies.count == 1 && copies[0].hasPrefix("Polhub-avant-v12-") && copies[0].hasSuffix(".sqlite"))
        let copy = try DatabaseQueue(path: backups.appending(path: copies[0]).path(percentEncoded: false))
        #expect(try copy.read { try String.fetchOne($0, sql: "SELECT status FROM project") } == "idée")
    }

    @Test func aNewBaseHasNoCopy() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try AppDatabase(path: folder.appending(path: "Polhub.sqlite").path(percentEncoded: false))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "Sauvegardes").path(percentEncoded: false)))
    }

    /// A base left by a newer Polhub is refused, never read with the wrong meanings.
    @Test func aBaseFromANewerVersionIsRefused() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "Polhub.sqlite").path(percentEncoded: false)
        do {
            let database = try AppDatabase(path: path)
            try database.writer.write { try $0.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v99')") }
        }
        #expect(throws: AppDatabaseError.newerBase) { try AppDatabase(path: path) }
    }

    @Test func theCopyIsNamedAfterTheMigration() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 12))!
        #expect(AppDatabase.backupName(before: "v12", on: day) == "Polhub-avant-v12-20261115.sqlite")
    }
}
