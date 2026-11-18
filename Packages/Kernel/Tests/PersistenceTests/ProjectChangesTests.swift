import Domain
import Foundation
import GRDB
import Testing
@testable import Persistence

/// Step 3 of Colin (18/11): the base keeps the journal of the changes of a project itself, with who made them — Paul,
/// Colin, or an agent (a session's `polhub mcp`, of now or of before) — so that what an agent changed can be undone.
@Suite(.timeLimit(.minutes(1))) struct ProjectChangesTests {
    let now = Date(timeIntervalSince1970: 1_794_992_400)   // Wednesday 18/11/2026, 10:00 in Paris

    func world() throws -> (AppDatabase, ProjectStore, ProjectRow, ProjectRow) {
        let database = try AppDatabase.inMemory()
        let store = ProjectStore(database)
        let martin = try store.addProject(name: "Cabinet Martin", status: .priorite2, at: now)
        let nord = try store.addProject(name: "Studio Nord", status: .priorite2, at: now)
        return (database, store, martin, nord)
    }

    func rows(_ database: AppDatabase) throws -> [ProjectChangeRow] {
        try database.writer.read { try ProjectChangeRow.order(Column("id")).fetchAll($0) }
    }

    func stamps(_ database: AppDatabase) throws -> Int {
        try database.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM change_stamp") ?? -1 }
    }

    func key(_ id: UUID) -> String { id.uuidString.lowercased() }

    // MARK: - Who

    /// Every write of the app says it is Paul's, and leaves no stamp behind: an old helper writing next would
    /// otherwise pass for him. Of Paul's own gestures, only what a rule may need is kept (status, deadline, task).
    @Test func paulsWritesAreStampedAndTheStampLeaves() throws {
        let (database, store, martin, nord) = try world()
        var edited = martin
        edited.todo = "Envoyer le devis"
        edited.dueDate = now.addingTimeInterval(86_400)
        try store.saveChanges(from: martin, to: edited, at: now)
        #expect(try stamps(database) == 0)
        try store.move(martin.id, to: .priorite1, before: nil, at: now)
        try store.save(nord, at: now)
        let action = ActionRow(projectID: martin.id, text: "Relire la maquette", position: 0, createdAt: now)
        try store.saveAction(action)
        try store.deleteAction(id: action.id)
        try store.addJournal(ProjectJournalRow(projectID: martin.id, date: now, title: "Devis envoyé", body: "", createdAt: now))
        var notes = nord
        notes.notes = "Une note de Paul"
        try store.saveNotes(notes)
        try store.touch(nord.id, at: now)
        try store.moveToTrash(projectID: nord.id, at: now)
        try store.restore(projectID: nord.id, at: now)
        _ = try store.addProject(name: "Maison Leroy", status: .enPause, at: now)
        #expect(try stamps(database) == 0)
        let found = try rows(database)
        #expect(Set(found.map(\.who)) == [.paul])
        #expect(Set(found.map(\.field)) == [.todo, .dueDate, .status])
    }

    /// A write with no stamp comes from a helper of before the journal: an agent's.
    @Test func anUnstampedWriteIsAnAgents() throws {
        let (database, _, martin, _) = try world()
        try database.writer.write {
            try $0.execute(sql: "UPDATE project SET todo = 'Relancer Claire', status = 'priorité 1' WHERE id = ?", arguments: [key(martin.id)])
        }
        let found = try rows(database)
        #expect(found.map(\.who) == [.agent, .agent])
        #expect(Set(found.map(\.field)) == [.todo, .status])
        #expect(found.allSatisfy { $0.batch == nil && $0.projectID == martin.id })
    }

    /// The writes of one signed store belong to one batch, with its reason and its source.
    @Test func aSignedStoreWritesOneBatch() throws {
        let (database, store, martin, _) = try world()
        let colin = store.signed(.colin, reason: "Après ton mail à Claire, 10:42", source: "mail:m-1")
        var edited = martin
        edited.todo = "En attente retour de Claire"
        try colin.saveChanges(from: martin, to: edited, at: now)
        try colin.move(martin.id, to: .priorite1, before: nil, at: now)
        try colin.addJournal(ProjectJournalRow(projectID: martin.id, date: now, title: "Mail envoyé à Claire le 18/11", body: "", createdAt: now))
        let found = try rows(database)
        #expect(found.count == 3)
        #expect(Set(found.map(\.batch)).count == 1 && found.first?.batch != nil)
        #expect(found.allSatisfy { $0.who == .colin && $0.reason == "Après ton mail à Claire, 10:42" && $0.source == "mail:m-1" })
        #expect(found.allSatisfy { $0.at == now })
        // Another signing is another batch.
        var task = edited
        task.todo = "Relancer Claire"
        try store.signed(.colin).saveChanges(from: edited, to: task, at: now)
        #expect(Set(try rows(database).map(\.batch)).count == 2)
    }

    /// `lastEditedAt` says when Paul last changed the project: an agent's write, of now or of before, leaves it.
    @Test func anAgentWriteKeepsLastEditedAt() throws {
        let (database, store, martin, _) = try world()
        var edited = martin
        edited.todo = "Envoyer le devis"
        try store.saveChanges(from: martin, to: edited, at: now)
        #expect(try store.project(id: martin.id)?.lastEditedAt == now)
        let later = now.addingTimeInterval(3_600)
        let agent = store.signed(.agent)
        let current = try #require(try store.project(id: martin.id))
        var again = current
        again.todo = "Relancer Claire"
        try agent.saveChanges(from: current, to: again, at: later)
        try agent.move(martin.id, to: .priorite1, before: nil, at: later)
        try database.writer.write {
            try $0.execute(sql: "UPDATE project SET lastEditedAt = ?, client = 'Cabinet' WHERE id = ?", arguments: [later, key(martin.id)])
        }
        let project = try #require(try store.project(id: martin.id))
        #expect(project.lastEditedAt == now)
        #expect(project.todo == "Relancer Claire" && project.status == .priorite1 && project.client == "Cabinet")
    }

    // MARK: - What is kept

    @Test func onlyWhatChangedIsWritten() throws {
        let (database, store, martin, _) = try world()
        var edited = martin
        edited.todo = "Envoyer le devis"
        try store.signed(.agent).saveChanges(from: martin, to: edited, at: now)
        let found = try rows(database)
        #expect(found.map(\.field) == [.todo])
        #expect(found.first?.before == nil && found.first?.after == "Envoyer le devis")
    }

    /// The project's page writes at every keystroke: Paul's typing of a minute is one change.
    @Test func paulsKeystrokesMakeOneLine() throws {
        let (database, store, martin, _) = try world()
        var current = martin
        for (index, text) in ["E", "En", "Env", "Envo", "Envoyer"].enumerated() {
            var next = current
            next.todo = text
            try store.saveChanges(from: current, to: next, at: now.addingTimeInterval(Double(index) * 2))
            current = next
        }
        var found = try rows(database)
        #expect(found.count == 1)
        #expect(found.first?.before == nil && found.first?.after == "Envoyer")
        var later = current
        later.todo = "Envoyer le devis"
        try store.saveChanges(from: current, to: later, at: now.addingTimeInterval(120))
        found = try rows(database)
        #expect(found.count == 2)
        #expect(found.last?.before == "Envoyer" && found.last?.after == "Envoyer le devis")
    }

    /// The order of a column is Paul's own business, and a column numbered again writes nothing; a card that changes
    /// column is one change.
    @Test func aRenumberedColumnWritesNothing() throws {
        let (database, store, martin, nord) = try world()
        let leroy = try store.addProject(name: "Maison Leroy", status: .priorite2, at: now)
        try database.writer.write { db in
            for (id, order) in [(martin.id, 0.0), (nord.id, 0.000_000_1), (leroy.id, 5.0)] {
                try db.execute(sql: "UPDATE project SET kanbanOrder = ? WHERE id = ?", arguments: [order, key(id)])
            }
        }
        let agent = store.signed(.agent)
        try agent.move(leroy.id, to: .priorite2, before: nord.id, at: now)
        #expect(try rows(database).isEmpty)
        try agent.move(leroy.id, to: .priorite1, before: nil, at: now)
        #expect(try rows(database).map(\.field) == [.status])
    }

    /// A change of column keeps where the card was: its order, and the card that came after it.
    @Test func aStatusChangeKeepsThePlace() throws {
        let (database, store, martin, nord) = try world()
        let leroy = try store.addProject(name: "Maison Leroy", status: .priorite2, at: now)
        #expect(try store.projects().filter { $0.status == .priorite2 }.map(\.name) == ["Cabinet Martin", "Studio Nord", "Maison Leroy"])
        try store.signed(.agent).move(nord.id, to: .priorite1, before: nil, at: now)
        let change = try #require(try rows(database).first)
        #expect(change.field == .status && change.before == "priorité 2" && change.after == "priorité 1")
        let detail = try #require(change.detail.flatMap { try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] })
        #expect(detail["next"] as? String == key(leroy.id))
        #expect((detail["order"] as? NSNumber)?.doubleValue == 1)
        _ = martin
    }

    /// The actions an agent adds, rewords, checks or removes, and the journal he writes. A removed action keeps its
    /// whole row, to be put back.
    @Test func anAgentsActionsAndJournalAreKept() throws {
        let (database, store, martin, _) = try world()
        let agent = store.signed(.agent)
        var action = ActionRow(projectID: martin.id, text: "Relire la maquette", position: 0, createdAt: now)
        try agent.saveAction(action)
        action.text = "Relire la maquette de Claire"
        try agent.saveAction(action)
        action.done = true
        try agent.saveAction(action)
        try agent.deleteAction(id: action.id)
        try agent.addJournal(ProjectJournalRow(projectID: martin.id, date: now, title: "Maquette relue", body: "- page Équipe", createdAt: now))
        let found = try rows(database)
        #expect(found.map(\.field) == [.actionAdded, .actionText, .actionDone, .actionRemoved, .journalAdded])
        #expect(found.prefix(4).allSatisfy { $0.subject == key(action.id) })
        #expect(found[1].before == "Relire la maquette" && found[1].after == "Relire la maquette de Claire")
        #expect(found[2].before == "0" && found[2].after == "1")
        let removed = try #require(found[3].detail.flatMap { try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] })
        #expect(removed["text"] as? String == "Relire la maquette de Claire")
        #expect(removed["projectID"] as? String == key(martin.id))
        #expect(found[4].after == "Maquette relue")
    }

    /// A meeting's summary writes its actions on the meeting, in no project: no change of a project.
    @Test func aMeetingsSummaryWritesNoLine() throws {
        let (database, _, _, _) = try world()
        let meeting = MeetingRow(createdAt: now, status: .ended, source: .dia, candidateKey: "t/a", title: "Cadrage", startedAt: now)
        try MeetingStore(database).save(meeting)
        let summaries = SummaryStore(database)
        try summaries.finish(meetingID: meeting.id, summary: "Le cadrage.", actions: [ActionRow(text: "Envoyer le compte rendu", position: 0, createdAt: now)], at: now)
        try summaries.finish(meetingID: meeting.id, summary: "Le cadrage.", actions: [], at: now)
        #expect(try rows(database).isEmpty)
    }

    /// Final review (18/11): an action of a meeting Paul put in a project is the project's: what an agent does to it
    /// is kept, and a removed one comes back still of its meeting.
    @Test func aFiledMeetingActionIsJournaled() throws {
        let (database, store, martin, _) = try world()
        let meeting = MeetingRow(createdAt: now, status: .ended, source: .dia, candidateKey: "t/a", title: "Cadrage", startedAt: now)
        try MeetingStore(database).save(meeting)
        var action = ActionRow(projectID: martin.id, meetingID: meeting.id, text: "Envoyer le devis", position: 0, createdAt: now)
        try store.saveAction(action)
        let agent = store.signed(.agent)
        action.done = true
        try agent.saveAction(action)
        try agent.deleteAction(id: action.id)
        let found = try rows(database)
        #expect(found.map(\.field) == [.actionDone, .actionRemoved])
        let changes = ProjectChanges(database)
        for line in try changes.lines(since: .distantPast, authors: [.agent]).reversed() { _ = try changes.undo(line, at: now) }
        let back = try #require(try store.actions(projectID: martin.id).first)
        #expect(back.meetingID == meeting.id && back.text == "Envoyer le devis")
    }

    /// The app's observations hear what the triggers write.
    @Test func theObservationHearsTheTriggers() async throws {
        let (database, store, martin, _) = try world()
        var counts = ValueObservation.tracking { try ProjectChangeRow.fetchCount($0) }.values(in: database.writer).makeAsyncIterator()
        #expect(try await counts.next() == 0)
        try store.signed(.agent).move(martin.id, to: .priorite1, before: nil, at: now)
        #expect(try await counts.next() == 1)
    }
}
