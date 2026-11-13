import Domain
import Foundation
import Testing
@testable import Persistence

@Suite struct ProjectStoreTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)   // 13/11/2026

    func stores() throws -> (ProjectStore, MeetingStore) {
        let database = try AppDatabase.inMemory()
        return (ProjectStore(database), MeetingStore(database))
    }

    func names(_ store: ProjectStore, _ status: ProjectStatus) throws -> [String] {
        try store.projects().filter { $0.status == status }.sorted { $0.kanbanOrder < $1.kanbanOrder }.map(\.name)
    }

    @Test func obsidianStatusesMapBothWays() {
        #expect(ProjectStatus(obsidian: "priorité 2") == .priorite2)
        #expect(ProjectStatus(obsidian: "idée") == .idee)
        #expect(ProjectStatus(obsidian: "Priorité 9") == ProjectStatus.none)
        #expect(ProjectStatus(obsidian: nil) == ProjectStatus.none)
        #expect(ProjectStatus.none.label == "Sans statut" && ProjectStatus.enAttente.label == "en attente")
        #expect(ProjectStatus.boardOrder == [.idee, .priorite3, .priorite2, .priorite1, .enAttente, .termine, .none])
    }

    @Test func movingIntoAnEmptyColumnPutsTheCardFirst() throws {
        let (store, _) = try stores()
        let alpha = try store.addProject(name: "Alpha", status: .idee, at: now)
        try store.move(alpha.id, to: .priorite1, before: nil)
        #expect(try names(store, .priorite1) == ["Alpha"])
        #expect(try names(store, .idee).isEmpty)
    }

    @Test func movingBeforeACardPutsItJustAbove() throws {
        let (store, _) = try stores()
        let a = try store.addProject(name: "A", status: .priorite2, at: now)
        let b = try store.addProject(name: "B", status: .priorite2, at: now)
        let c = try store.addProject(name: "C", status: .priorite3, at: now)
        #expect(try names(store, .priorite2) == ["A", "B"])
        try store.move(c.id, to: .priorite2, before: b.id)
        #expect(try names(store, .priorite2) == ["A", "C", "B"])
        try store.move(b.id, to: .priorite2, before: a.id)
        #expect(try names(store, .priorite2) == ["B", "A", "C"])
    }

    @Test func movingOntoItselfChangesNothing() throws {
        let (store, _) = try stores()
        let a = try store.addProject(name: "A", status: .idee, at: now)
        _ = try store.addProject(name: "B", status: .idee, at: now)
        try store.move(a.id, to: .idee, before: a.id)
        #expect(try names(store, .idee) == ["A", "B"])
    }

    @Test func closePositionsAreRenumbered() throws {
        let (store, _) = try stores()
        let first = try store.addProject(name: "Premier", status: .idee, at: now)
        let last = try store.addProject(name: "Dernier", status: .idee, at: now)
        var expected = ["Premier"]
        for index in 0..<40 {
            let card = try store.addProject(name: "N\(index)", status: .priorite3, at: now)
            try store.move(card.id, to: .idee, before: last.id)
            expected.append("N\(index)")
        }
        expected.append("Dernier")
        #expect(try names(store, .idee) == expected)
        _ = first
    }

    @Test func aMeetingCanBeFiledInAProject() throws {
        let (store, meetings) = try stores()
        let project = try store.addProject(name: "Atelier client", status: .priorite3, at: now)
        let meeting = MeetingRow(createdAt: now, status: .ended, source: .dia, candidateKey: "t/a", title: "Cadrage", startedAt: now)
        try meetings.save(meeting)
        try store.setProject(meetingID: meeting.id, projectID: project.id)
        #expect(try store.meetings(projectID: project.id).map(\.title) == ["Cadrage"])
        try store.setProject(meetingID: meeting.id, projectID: nil)
        #expect(try store.meetings(projectID: project.id).isEmpty)
    }

    @Test func editingAProjectSetsLastEditedAt() throws {
        let (store, _) = try stores()
        var project = try store.addProject(name: "Alpha", status: .idee, at: now)
        #expect(project.lastEditedAt == nil)
        project.todo = "Envoyer la maquette"
        try store.save(project, at: now.addingTimeInterval(60))
        let back = try #require(try store.project(id: project.id))
        #expect(back.todo == "Envoyer la maquette" && back.lastEditedAt == now.addingTimeInterval(60))
    }

    @Test func actionsAndJournalBelongToTheirProject() throws {
        let (store, _) = try stores()
        let project = try store.addProject(name: "Alpha", status: .idee, at: now)
        try store.saveAction(ActionRow(projectID: project.id, text: "Relancer le client", position: 1, createdAt: now))
        try store.saveAction(ActionRow(projectID: project.id, text: "Lire la fiche", position: 0, createdAt: now))
        #expect(try store.actions(projectID: project.id).map(\.text) == ["Lire la fiche", "Relancer le client"])
        try store.addJournal(ProjectJournalRow(projectID: project.id, date: now.addingTimeInterval(-86_400), title: "Hier", body: "", createdAt: now))
        try store.addJournal(ProjectJournalRow(projectID: project.id, date: now, title: "Aujourd'hui", body: "- fait", createdAt: now))
        #expect(try store.journal(projectID: project.id).map(\.title) == ["Aujourd'hui", "Hier"])
    }

    // Revue finale, Important 3 : le coordinateur réécrit sa copie de la réunion ; le projet choisi reste.
    @Test func savingAMeetingKeepsTheProjectItWasFiledIn() throws {
        let (store, meetings) = try stores()
        let project = try store.addProject(name: "Atelier client", status: .priorite3, at: now)
        var meeting = MeetingRow(createdAt: now, status: .recording, source: .dia, candidateKey: "t/a", title: "Cadrage", startedAt: now)
        try meetings.save(meeting)
        try store.setProject(meetingID: meeting.id, projectID: project.id)
        meeting.status = .ended
        try meetings.save(meeting)
        #expect(try meetings.meeting(id: meeting.id)?.projectID == project.id)
        #expect(try meetings.meeting(id: meeting.id)?.status == .ended)
    }

    // Revue finale, mineur 13 : les actions venues d'une réunion survivent à un réimport.
    @Test func replacingProjectsKeepsActionsOfMeetings() throws {
        let (store, meetings) = try stores()
        let project = try store.addProject(name: "Atelier client", status: .priorite3, at: now)
        let meeting = MeetingRow(createdAt: now, status: .ended, source: .dia, candidateKey: "t/a", title: "Cadrage", startedAt: now)
        try meetings.save(meeting)
        try store.saveAction(ActionRow(projectID: project.id, meetingID: meeting.id, text: "Venue de la réunion", position: 0, createdAt: now))
        try store.saveAction(ActionRow(projectID: project.id, text: "Venue du coffre", position: 1, createdAt: now))
        try store.replaceAll([], actions: [], journal: [])
        let left = try store.database.writer.read { try ActionRow.fetchAll($0) }
        #expect(left.map(\.text) == ["Venue de la réunion"] && left.first?.projectID == nil)
    }

    // Revue finale, mineur 8 : changer une carte de colonne est un signe de vie.
    @Test func movingACardIsASignOfLife() throws {
        let (store, _) = try stores()
        let project = try store.addProject(name: "A", status: .idee, at: now)
        try store.move(project.id, to: .priorite1, before: nil, at: now.addingTimeInterval(120))
        #expect(try store.project(id: project.id)?.lastEditedAt == now.addingTimeInterval(120))
    }
}
