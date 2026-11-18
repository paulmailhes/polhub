import Domain
import Foundation
import GRDB
@testable import Persistence
import Testing
@testable import ReadingKit

/// Step 3 of Colin (18/11): what a session's helper writes is signed — an agent's, or Colin's — and one call of a tool
/// is one change, undone together.
@Suite struct ProjectDeskJournalTests {
    /// The fixture writes its rows straight into the base, unsigned: they are not the desk's.
    func fixture(_ author: ChangeAuthor) throws -> DeskFixture {
        let fixture = try DeskFixture(author: author)
        try fixture.database.writer.write { try $0.execute(sql: "DELETE FROM project_change") }
        return fixture
    }

    @Test func oneCallIsOneLine() throws {
        let fixture = try fixture(.agent)
        _ = try fixture.desk().update("Atelier Nord", status: "priorité 2", due: nil, todo: "Relancer le client", notes: "Des notes neuves")
        var lines = try ProjectChanges(fixture.database).lines(since: .distantPast, authors: [.agent])
        #expect(lines.count == 1)
        #expect(Set(lines.first?.rows.map(\.field) ?? []) == [.status, .todo, .notes, .journalAdded])
        _ = try fixture.desk().addAction("Atelier Nord", text: "Appeler Camille")
        _ = try fixture.desk().done("Atelier Nord", numbers: [1])
        lines = try ProjectChanges(fixture.database).lines(since: .distantPast, authors: [.agent])
        #expect(lines.map(\.rows.count) == [4, 1, 1])
        // Undone, the call leaves nothing of itself.
        #expect(try ProjectChanges(fixture.database).undo(lines[0], at: fixture.now) == .undone)
        let project = try #require(try fixture.projects.project(id: fixture.atelier.id))
        #expect(project.status == .priorite1 && project.todo == "Envoyer la maquette" && project.notes.hasPrefix("- Une idée de départ"))
        #expect(try fixture.projects.journal(projectID: fixture.atelier.id).map(\.title) == ["Maquette v1"])
    }

    @Test func colinsHelperSignsColin() throws {
        let fixture = try fixture(.colin)
        _ = try fixture.desk().addJournal("Atelier Nord", title: "Maquette relue", details: [])
        let lines = try ProjectChanges(fixture.database).lines(since: .distantPast, authors: [.colin])
        #expect(lines.count == 1 && lines.first?.who == .colin)
    }

    /// A helper newer than the base (the app not opened since its update): nothing is written, and the session is told.
    @Test func aBaseWithoutTheJournalRefusesTheTools() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "outils-v17 \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "Polhub.sqlite").path(percentEncoded: false)
        let queue = try DatabaseQueue(path: path)
        try AppDatabase.migrator.migrate(queue, upTo: "v17")
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO project (id, name, status, contacts, notes, kanbanOrder, createdAt, updatedAt)
                VALUES (?, 'Atelier Nord', 'priorité 1', '[]', '', 0, ?, ?)
                """, arguments: [UUID().uuidString.lowercased(), Date(), Date()])
        }
        let tools = try AppDatabase.forTools(path: path)
        let desk = ProjectDesk(projects: ProjectStore(tools), meetings: MeetingStore(tools), workingDirectory: nil)
        #expect { try desk.addAction("Atelier Nord", text: "Appeler Camille") } throws: { error in
            "\(error)" == "Polhub doit être ouvert une fois : sa base n'a pas encore le journal des changements. Rien n'a été écrit."
        }
        #expect(try tools.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM action") } == 0)
    }
}
