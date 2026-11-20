import Domain
import Foundation
import GRDB
import Testing
@testable import Persistence

/// Base v18 (18/11): the journal of the changes of a project, kept by the base itself. A helper of before, which
/// never migrates and knows nothing of it, still writes the base; what it writes is journaled as an agent's.
@Suite struct MigrationV18Tests {
    let now = Date(timeIntervalSince1970: 1_794_992_400)   // 18/11/2026
    let projectID = UUID()

    /// A base as the version before left it; the caller removes its folder.
    func baseAtV17() throws -> (folder: URL, path: String) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-v18 \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appending(path: "Polhub.sqlite").path(percentEncoded: false)
        let queue = try DatabaseQueue(path: path)
        try AppDatabase.migrator.migrate(queue, upTo: "v17")
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO project (id, name, status, contacts, notes, kanbanOrder, createdAt, updatedAt)
                VALUES (?, 'Cabinet Martin', 'priorité 2', '[]', '', 0, ?, ?)
                """, arguments: [projectID.uuidString.lowercased(), now, now])
        }
        return (folder, path)
    }

    @Test func aBaseAtV17GainsTheJournal() throws {
        let (folder, path) = try baseAtV17()
        defer { try? FileManager.default.removeItem(at: folder) }
        let base = try AppDatabase(path: path)
        let change = try base.writer.read { try $0.columns(in: "project_change").map(\.name).sorted() }
        #expect(change == ["after", "at", "batch", "before", "detail", "field", "id", "projectID", "reason", "source", "subject", "undoneAt", "who"])
        let stamp = try base.writer.read { try $0.columns(in: "change_stamp").map(\.name).sorted() }
        #expect(stamp == ["at", "batch", "id", "reason", "source", "who"])
        #expect(base.author == .paul)
        let backups = try FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "Sauvegardes").path(percentEncoded: false))
        #expect(backups.contains { $0.hasPrefix("hub-board-avant-v18-") })
    }

    /// The helpers already running in open sessions keep their program of before: their writes still go through,
    /// and are an agent's.
    @Test func aHelperOfBeforeStillWritesABaseOfV18() throws {
        let (folder, path) = try baseAtV17()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try AppDatabase(path: path)
        let tools = try AppDatabase.forTools(path: path)
        #expect(tools.author == .agent)
        try tools.writer.write {
            try $0.execute(sql: "UPDATE project SET todo = 'Relancer Claire' WHERE id = ?", arguments: [projectID.uuidString.lowercased()])
        }
        let rows = try tools.writer.read { try ProjectChangeRow.fetchAll($0) }
        #expect(rows.map(\.who) == [.agent] && rows.map(\.field) == [.todo] && rows.first?.batch == nil)
        // The new helper signs its writes, one batch for each call of a tool.
        try ProjectStore(tools).batch().addJournal(ProjectJournalRow(projectID: projectID, date: now, title: "Relance prévue", body: "", createdAt: now))
        let signed = try tools.writer.read { try ProjectChangeRow.order(Column("id")).fetchAll($0) }.last
        #expect(signed?.who == .agent && signed?.batch != nil && signed?.field == .journalAdded)
        #expect(try AppDatabase.forTools(path: path, author: .colin).author == .colin)
    }

    /// A new helper on a base the app has not migrated yet (it opens it, it never migrates): nothing is written
    /// unsigned, the app has to open first.
    @Test func aNewHelperOnABaseOfBeforeWritesNothing() throws {
        let (folder, path) = try baseAtV17()
        defer { try? FileManager.default.removeItem(at: folder) }
        let tools = try AppDatabase.forTools(path: path)
        let store = ProjectStore(tools)
        #expect(throws: ProjectStoreError.needsApp) {
            try store.addJournal(ProjectJournalRow(projectID: projectID, date: now, title: "Relance prévue", body: "", createdAt: now))
        }
        #expect(try tools.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM project_journal") } == 0)
    }
}
