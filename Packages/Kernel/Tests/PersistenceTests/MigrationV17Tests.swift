import Foundation
import GRDB
import Testing
@testable import Persistence

/// Base v17 (18/11): Colin's thread and what he knows. The migration only adds two tables: a helper that never
/// migrates still reads a base of after.
@Suite struct MigrationV17Tests {
    let now = Date(timeIntervalSince1970: 1_794_960_000)   // 18/11/2026

    /// A base as the version before left it; the caller removes its folder.
    func baseAtV16() throws -> (folder: URL, path: String) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-v17 \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appending(path: "Polhub.sqlite").path(percentEncoded: false)
        let queue = try DatabaseQueue(path: path)
        try AppDatabase.migrator.migrate(queue, upTo: "v16")
        try queue.write { db in
            try db.execute(sql: "INSERT INTO google_account (email, addedAt) VALUES (?, ?)", arguments: ["moi@exemple.fr", now])
            try db.execute(sql: """
                INSERT INTO project (id, name, status, contacts, notes, kanbanOrder, createdAt, updatedAt)
                VALUES (?, 'Cabinet Martin', 'priorite2', '[]', '', 0, ?, ?)
                """, arguments: [UUID().uuidString.lowercased(), now, now])
        }
        return (folder, path)
    }

    @Test func aBaseAtV16GainsTheThreadAndTheKnowledge() throws {
        let (folder, path) = try baseAtV16()
        defer { try? FileManager.default.removeItem(at: folder) }
        let base = try AppDatabase(path: path)
        let message = try base.writer.read { try $0.columns(in: "colin_message").map(\.name).sorted() }
        #expect(message == ["author", "costUSD", "createdAt", "drafts", "id", "state", "text"])
        let knowledge = try base.writer.read { try $0.columns(in: "colin_knowledge").map(\.name).sorted() }
        #expect(knowledge == ["id", "text", "updatedAt"])
        // The copy of the base made before the migration is named after it.
        let backups = try FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "Sauvegardes").path(percentEncoded: false))
        #expect(backups.contains { $0.hasPrefix("Polhub-avant-v17-") })
    }

    @Test func aHelperOfV16StillReadsABaseOfV17() throws {
        let (folder, path) = try baseAtV16()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(try AppDatabase.forTools(path: path).writer.read { try !$0.tableExists("colin_message") })
        _ = try AppDatabase(path: path)
        // The tools open the base without migrating it: what they read is still there.
        let tools = try AppDatabase.forTools(path: path)
        #expect(try tools.writer.read { try String.fetchAll($0, sql: "SELECT name FROM project") } == ["Cabinet Martin"])
        #expect(try tools.writer.read { try $0.tableExists("colin_message") })
    }
}
