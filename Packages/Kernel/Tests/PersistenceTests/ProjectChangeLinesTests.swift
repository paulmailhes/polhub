import Domain
import Foundation
import GRDB
import Testing
@testable import Persistence

/// The changes read as lines (one batch, one line) and undone (step 3 of Colin, 18/11): « Annuler » puts back what an
/// agent changed, and nothing that changed since.
@Suite struct ProjectChangeLinesTests {
    let now = Date(timeIntervalSince1970: 1_794_992_400)   // Wednesday 18/11/2026, 10:00 in Paris

    func world() throws -> (AppDatabase, ProjectStore, ProjectRow, ProjectRow) {
        let database = try AppDatabase.inMemory()
        let store = ProjectStore(database)
        let martin = try store.addProject(name: "Cabinet Martin", status: .priorite2, at: now)
        let nord = try store.addProject(name: "Studio Nord", status: .priorite2, at: now)
        return (database, store, martin, nord)
    }

    func key(_ id: UUID) -> String { id.uuidString.lowercased() }

    func edited(_ store: ProjectStore, _ id: UUID, _ change: (inout ProjectRow) -> Void) throws -> (ProjectRow, ProjectRow) {
        let current = try #require(try store.project(id: id))
        var next = current
        change(&next)
        return (current, next)
    }

    // MARK: - Lines

    @Test func linesGroupABatch() throws {
        let (database, store, martin, nord) = try world()
        let colin = store.signed(.colin, reason: "Après ton mail à Claire, 10:42", source: "mail:m-1")
        let (from, to) = try edited(store, martin.id) { $0.todo = "En attente retour de Claire" }
        try colin.saveChanges(from: from, to: to, at: now)
        try colin.move(martin.id, to: .priorite1, before: nil, at: now)
        let (other, otherTo) = try edited(store, nord.id) { $0.todo = "Relire la maquette" }
        try store.signed(.agent).saveChanges(from: other, to: otherTo, at: now.addingTimeInterval(60))
        let lines = try ProjectChanges(database).lines(since: now.addingTimeInterval(-3_600), authors: [.colin, .agent])
        #expect(lines.count == 2)
        #expect(lines.first?.projectName == "Cabinet Martin" && lines.first?.who == .colin && lines.first?.rows.count == 2)
        #expect(lines.first?.reason == "Après ton mail à Claire, 10:42")
        #expect(lines.last?.projectName == "Studio Nord" && lines.last?.who == .agent)
        // Only the authors asked; Paul's own changes are not lines unless asked.
        #expect(try ProjectChanges(database).lines(since: .distantPast, authors: [.agent]).map(\.projectName) == ["Studio Nord"])
        #expect(try ProjectChanges(database).lines(since: now.addingTimeInterval(30), authors: [.colin, .agent]).map(\.projectName) == ["Studio Nord"])
    }

    /// A helper of before writes no batch: its writes on a project within a few seconds are one line.
    @Test func anOldHelpersWritesGroupByTime() throws {
        let (database, _, martin, _) = try world()
        func write(_ sql: String, _ at: Date) throws {
            try database.writer.write { db in
                try db.execute(sql: sql, arguments: [key(martin.id)])
                try db.execute(sql: "UPDATE project_change SET at = ? WHERE id = (SELECT MAX(id) FROM project_change)", arguments: [at])
            }
        }
        try write("UPDATE project SET todo = 'Relancer Claire' WHERE id = ?", now)
        try write("UPDATE project SET status = 'priorité 1' WHERE id = ?", now.addingTimeInterval(2))
        try write("UPDATE project SET client = 'Cabinet' WHERE id = ?", now.addingTimeInterval(60))
        let lines = try ProjectChanges(database).lines(since: .distantPast, authors: [.agent])
        #expect(lines.map(\.rows.count) == [2, 1])
    }

    /// Paul's typing that came back to where it began is no change at all.
    @Test func aChangeBackToItsStartIsNoLine() throws {
        let (database, store, martin, _) = try world()
        let (from, to) = try edited(store, martin.id) { $0.todo = "E" }
        try store.saveChanges(from: from, to: to, at: now)
        try store.saveChanges(from: to, to: from, at: now.addingTimeInterval(1))
        #expect(try ProjectChanges(database).lines(since: .distantPast, authors: [.paul]).isEmpty)
    }

    // MARK: - Undo

    @Test func undoPutsBackTheFieldsOfAProject() throws {
        let (database, store, martin, _) = try world()
        let (from, start) = try edited(store, martin.id) {
            $0.todo = "Envoyer le devis"
            $0.client = "Cabinet Martin SARL"
            $0.notes = "Les notes de Paul"
            $0.dueDate = now.addingTimeInterval(86_400)
        }
        try store.saveChanges(from: from, to: start, at: now)
        let (current, changed) = try edited(store, martin.id) {
            $0.todo = "En attente retour de Claire"
            $0.client = nil
            $0.notes = "Des notes réécrites"
            $0.dueDate = now.addingTimeInterval(7 * 86_400)
        }
        let agent = store.signed(.agent)
        try agent.saveChanges(from: current, to: changed, at: now.addingTimeInterval(600))
        let changes = ProjectChanges(database)
        let line = try #require(try changes.lines(since: .distantPast, authors: [.agent]).first)
        #expect(Set(line.rows.map(\.field)) == [.todo, .client, .notes, .dueDate])
        #expect(try changes.undo(line, at: now.addingTimeInterval(900)) == .undone)
        let back = try #require(try store.project(id: martin.id))
        #expect(back.todo == "Envoyer le devis" && back.client == "Cabinet Martin SARL" && back.notes == "Les notes de Paul")
        #expect(back.dueDate == now.addingTimeInterval(86_400))
        let undone = try #require(try changes.lines(since: .distantPast, authors: [.agent]).first)
        #expect(undone.undoneAt == now.addingTimeInterval(900))
        // Undone twice: nothing more.
        #expect(try changes.undo(undone, at: now.addingTimeInterval(960)) == .undone)
    }

    /// The card goes back to its column, before the card that came after it.
    @Test func undoPutsTheCardBackBeforeItsNeighbour() throws {
        let (database, store, martin, nord) = try world()
        let leroy = try store.addProject(name: "Maison Leroy", status: .priorite2, at: now)
        try store.signed(.agent).move(nord.id, to: .priorite1, before: nil, at: now)
        let changes = ProjectChanges(database)
        let line = try #require(try changes.lines(since: .distantPast, authors: [.agent]).first)
        #expect(try changes.undo(line, at: now) == .undone)
        #expect(try store.projects().filter { $0.status == .priorite2 }.map(\.name) == ["Cabinet Martin", "Studio Nord", "Maison Leroy"])
        // The card after it left meanwhile: back as near as it can, by its old place.
        try store.signed(.agent).move(martin.id, to: .priorite1, before: nil, at: now)
        try store.move(nord.id, to: .enPause, before: nil, at: now)
        let second = try #require(try changes.lines(since: .distantPast, authors: [.agent]).last)
        #expect(try changes.undo(second, at: now) == .undone)
        #expect(try store.projects().filter { $0.status == .priorite2 }.map(\.name) == ["Cabinet Martin", "Maison Leroy"])
        _ = leroy
    }

    /// The actions an agent added, checked, reworded or removed, and his journal entry.
    @Test func undoPutsBackTheActionsAndTheJournal() throws {
        let (database, store, martin, _) = try world()
        var kept = ActionRow(projectID: martin.id, text: "Relire la maquette", position: 0, createdAt: now)
        let gone = ActionRow(projectID: martin.id, text: "Appeler Claire", position: 1, createdAt: now)
        try store.saveAction(kept)
        try store.saveAction(gone)
        let agent = store.signed(.agent)
        let added = ActionRow(projectID: martin.id, text: "Envoyer le devis", position: 2, createdAt: now)
        try agent.saveAction(added)
        kept.done = true
        kept.text = "Relire la maquette de Claire"
        try agent.saveAction(kept)
        try agent.deleteAction(id: gone.id)
        let entry = ProjectJournalRow(projectID: martin.id, date: now, title: "Devis préparé", body: "", createdAt: now)
        try agent.addJournal(entry)
        let changes = ProjectChanges(database)
        let line = try #require(try changes.lines(since: .distantPast, authors: [.agent]).first)
        #expect(line.rows.count == 5)
        #expect(try changes.undo(line, at: now) == .undone)
        let actions = try store.actions(projectID: martin.id).sorted { $0.position < $1.position }
        #expect(actions.map(\.text) == ["Relire la maquette", "Appeler Claire"])
        #expect(actions.map(\.done) == [false, false])
        #expect(actions.last?.id == gone.id && actions.last?.position == 1)
        #expect(try store.journal(projectID: martin.id).isEmpty)
    }

    /// What Paul changed after the agent stays: nothing of it is undone.
    @Test func undoAfterAChangeOfPaulsKeepsIt() throws {
        let (database, store, martin, _) = try world()
        let (from, to) = try edited(store, martin.id) { $0.todo = "En attente retour de Claire" }
        try store.signed(.agent).saveChanges(from: from, to: to, at: now)
        let (paulFrom, paulTo) = try edited(store, martin.id) { $0.todo = "Appeler Claire" }
        try store.saveChanges(from: paulFrom, to: paulTo, at: now.addingTimeInterval(60))
        let changes = ProjectChanges(database)
        let line = try #require(try changes.lines(since: .distantPast, authors: [.agent]).first)
        #expect(try changes.undo(line, at: now.addingTimeInterval(120)) == .changedSince)
        #expect(try store.project(id: martin.id)?.todo == "Appeler Claire")
    }

    @Test func undoOfHalfAChangedLineIsPartly() throws {
        let (database, store, martin, _) = try world()
        let agent = store.signed(.agent)
        let (from, to) = try edited(store, martin.id) { $0.todo = "En attente retour de Claire" }
        try agent.saveChanges(from: from, to: to, at: now)
        try agent.move(martin.id, to: .priorite1, before: nil, at: now)
        try store.move(martin.id, to: .enPause, before: nil, at: now.addingTimeInterval(60))
        let changes = ProjectChanges(database)
        let line = try #require(try changes.lines(since: .distantPast, authors: [.agent]).first)
        #expect(try changes.undo(line, at: now.addingTimeInterval(120)) == .partly(kept: 1))
        let project = try #require(try store.project(id: martin.id))
        #expect(project.todo == nil && project.status == .enPause)
    }

    // MARK: - What a rule writes

    /// A rule's change (step 3, 18/11): one batch, in one transaction; its event answered once, never twice; not a sign
    /// of Paul's life on the project.
    @Test func aKanbanEditIsOneBatchAndNeverTwice() throws {
        let (database, store, martin, _) = try world()
        let edit = KanbanEdit(projectID: martin.id, status: .priorite1, todo: "En attente retour de Claire", dueDate: nil,
                              journal: "Mail envoyé à Claire le 18/11", reason: "Après ton mail à Claire, 9:50", source: "mail:m-1")
        #expect(try store.edit(edit, by: .colin, at: now))
        #expect(try store.edit(edit, by: .colin, at: now.addingTimeInterval(60)) == false)
        let lines = try ProjectChanges(database).lines(since: .distantPast, authors: [.colin])
        #expect(lines.count == 1)
        #expect(Set(lines.first?.rows.map(\.field) ?? []) == [.status, .todo, .journalAdded])
        #expect(lines.first?.reason == "Après ton mail à Claire, 9:50")
        let project = try #require(try store.project(id: martin.id))
        #expect(project.status == .priorite1 && project.todo == "En attente retour de Claire" && project.lastEditedAt == nil)
        #expect(try store.journal(projectID: martin.id).map(\.title) == ["Mail envoyé à Claire le 18/11"])
        // A card in the trash is left.
        try store.moveToTrash(projectID: martin.id, at: now)
        var other = edit
        other.source = "mail:m-2"
        #expect(try store.edit(other, by: .colin, at: now) == false)
    }

    // MARK: - What the rules read

    /// What Paul changed himself in the last 24 hours: a rule leaves it.
    @Test func paulTouchesAreWhatHeChanged() throws {
        let (database, store, martin, nord) = try world()
        let (from, to) = try edited(store, martin.id) { $0.todo = "Appeler Claire" }
        try store.saveChanges(from: from, to: to, at: now.addingTimeInterval(-25 * 3_600))
        try store.move(nord.id, to: .priorite1, before: nil, at: now.addingTimeInterval(-3_600))
        let (agentFrom, agentTo) = try edited(store, nord.id) { $0.todo = "Relire" }
        try store.signed(.agent).saveChanges(from: agentFrom, to: agentTo, at: now)
        let touched = try ProjectChanges(database).paulTouches(since: now.addingTimeInterval(-24 * 3_600))
        #expect(touched == [ProjectFieldKey(projectID: nord.id, field: .status)])
    }

    /// A rule's event, once written, is known — even undone: it is never done again.
    @Test func sourcesIncludeUndoneOnes() throws {
        let (database, store, martin, _) = try world()
        let rule = store.signed(.colin, reason: "Rendez-vous du jeudi 19/11", source: "event:e-1")
        let (from, to) = try edited(store, martin.id) { $0.dueDate = now.addingTimeInterval(86_400) }
        try rule.saveChanges(from: from, to: to, at: now)
        let changes = ProjectChanges(database)
        let line = try #require(try changes.lines(since: .distantPast, authors: [.colin]).first)
        _ = try changes.undo(line, at: now)
        #expect(try changes.sources(since: now.addingTimeInterval(-86_400)) == ["event:e-1"])
        #expect(try changes.isReady())
    }
}
