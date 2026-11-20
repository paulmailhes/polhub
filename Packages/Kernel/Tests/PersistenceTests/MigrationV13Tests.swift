import Domain
import Foundation
import GRDB
import Testing
@testable import Persistence

/// Base v13 (16/11): the two tables of « Inspiration », added beside everything else, on a base that already
/// holds Paul's data.
@Suite struct MigrationV13Tests {
    let now = Date(timeIntervalSince1970: 1_794_822_000)   // 16/11/2026

    func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-v13 \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func aBaseAtV12GetsTheInspirationTablesAndKeepsItsProjects() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v12")
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO project (id, name, status, contacts, notes, kanbanOrder, createdAt, updatedAt)
                VALUES (?, 'Site vitrine', 'priorité 1', '[]', '', 0, ?, ?)
                """, arguments: [UUID().uuidString.lowercased(), now, now])
        }
        #expect(try queue.read { try $0.tableExists("inspiration_item") } == false)
        try AppDatabase.migrator.migrate(queue)
        try queue.read { db in
            #expect(try db.tableExists("inspiration_item") && db.tableExists("inspiration_source"))
            #expect(try String.fetchOne(db, sql: "SELECT name FROM project") == "Site vitrine")
            let indexes = try db.indexes(on: "inspiration_item")
            #expect(indexes.contains { $0.columns == ["kind", "date"] && !$0.isUnique })
            #expect(indexes.contains { $0.columns == ["kind", "key"] && $0.isUnique })
            #expect(try db.indexes(on: "inspiration_source").contains { $0.columns == ["link"] && $0.isUnique })
        }
    }

    /// The same key twice in a kind is refused by the base itself; the same key in two kinds is two items.
    @Test func aKeyIsUniqueWithinItsKind() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.write { db in
            try InspirationItemRow(kind: .website, key: "https://exemple.fr", title: "Exemple", date: now, createdAt: now).insert(db)
            try InspirationItemRow(kind: .mockup, key: "https://exemple.fr", title: "Autre genre", date: now, createdAt: now).insert(db)
        }
        #expect(throws: DatabaseError.self) {
            try database.writer.write { db in
                try InspirationItemRow(kind: .website, key: "https://exemple.fr", title: "Doublon", date: now, createdAt: now).insert(db)
            }
        }
    }

    /// A real file at v12 is copied before it gets v13, under the name of the migration it is about to get.
    @Test func aBaseAboutToGetV13IsCopiedFirst() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "Polhub.sqlite").path(percentEncoded: false)
        do {
            let queue = try DatabaseQueue(path: path)
            try AppDatabase.migrator.migrate(queue, upTo: "v12")
        }
        let database = try AppDatabase(path: path)
        #expect(try database.writer.read { try $0.tableExists("inspiration_item") })
        let backups = folder.appending(path: "Sauvegardes", directoryHint: .isDirectory)
        let copies = try FileManager.default.contentsOfDirectory(atPath: backups.path(percentEncoded: false)).filter { $0.hasSuffix(".sqlite") }
        #expect(copies.count == 1 && copies[0].hasPrefix("hub-board-avant-v13-"))
    }

    /// The images live beside the base, one folder per kind, in the flavor's own folder.
    @Test func theImagesHaveAFolderPerKind() {
        let paths = AppPaths(root: URL(fileURLWithPath: "/tmp/Polhub-test", isDirectory: true), logs: URL(fileURLWithPath: "/tmp/logs"))
        #expect(paths.inspiration.path(percentEncoded: false) == "/tmp/Polhub-test/Inspiration/")
        #expect(paths.inspirationImages(.website).lastPathComponent == "websites")
        #expect(paths.inspirationImages(.branding).lastPathComponent == "branding")
        #expect(paths.inspirationImages(.mockup).lastPathComponent == "mockups")
        #expect(paths.inspirationImages(.branding).deletingLastPathComponent().lastPathComponent == "Inspiration")
    }
}
