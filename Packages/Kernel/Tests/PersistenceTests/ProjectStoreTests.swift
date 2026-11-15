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

    /// 15/11 (Paul): four statuses, the most urgent first (« priorité 2 c'est le plus priorité »); their raw values
    /// stay lowercase for `polhub mcp`, their titles are the board's.
    @Test func fourStatusesInTheBoardsOrder() {
        #expect(ProjectStatus.boardOrder == [.priorite2, .priorite1, .enPause, .termine])
        #expect(ProjectStatus.allCases.map(\.label) == ["priorité 2", "priorité 1", "en pause", "terminé"])
        #expect(ProjectStatus.allCases.map(\.title) == ["Priorité 2", "Priorité 1", "En pause", "Terminé"])
    }

    /// « Supprimer le projet » (15/11): it leaves every list, its mails stop going there, and it comes back whole.
    @Test func aDeletedProjectLeavesTheBoardAndTheMailRules() throws {
        let database = try AppDatabase.inMemory()
        let store = ProjectStore(database)
        let project = try store.addProject(name: "Site vitrine", status: .priorite2, at: now)
        let contact = try ContactStore(database).upsert(email: "camille@exemple-studio.fr", name: "Camille", company: nil, at: now)
        try ContactStore(database).link(contactID: contact.id, projectID: project.id, origin: .paul, at: now)
        #expect(try MailStore(database).filingRules().contactProjects["camille@exemple-studio.fr"] == [project.id])
        try store.moveToTrash(projectID: project.id, at: now)
        #expect(try store.projects().isEmpty)
        let rules = try MailStore(database).filingRules()
        #expect(rules.contactProjects["camille@exemple-studio.fr"] == nil && rules.projects.isEmpty)
        #expect(!rules.exists(.project(project.id)) && rules.exists(.perso))
        try store.restore(projectID: project.id, at: now)
        #expect(try store.projects().map(\.name) == ["Site vitrine"])
    }

    /// Review of 15/11: an old or unknown value never fails; « priorité 2 » keeps its meaning (only the
    /// migration moves the old ones).
    @Test func anOldStatusIsReadWithoutFailing() throws {
        #expect(ProjectStatus(tolerant: "idée") == .priorite1)
        #expect(ProjectStatus(tolerant: "priorité 3") == .priorite2)
        #expect(ProjectStatus(tolerant: "en attente") == .enPause)
        #expect(ProjectStatus(tolerant: "") == .enPause && ProjectStatus(tolerant: "Priorité 9") == .enPause)
        #expect(ProjectStatus(tolerant: " priorité 2 ") == .priorite2 && ProjectStatus(tolerant: "terminé") == .termine)
        let decoded = try JSONDecoder().decode([ProjectStatus].self, from: Data(#"["idée", "priorité 2", "n'importe quoi", "en pause"]"#.utf8))
        #expect(decoded == [.priorite1, .priorite2, .enPause, .enPause])
        #expect(String(decoding: try JSONEncoder().encode(ProjectStatus.enPause), as: UTF8.self) == #""en pause""#)
    }

    @Test func movingIntoAnEmptyColumnPutsTheCardFirst() throws {
        let (store, _) = try stores()
        let alpha = try store.addProject(name: "Alpha", status: .enPause, at: now)
        try store.move(alpha.id, to: .priorite1, before: nil)
        #expect(try names(store, .priorite1) == ["Alpha"])
        #expect(try names(store, .enPause).isEmpty)
    }

    @Test func movingBeforeACardPutsItJustAbove() throws {
        let (store, _) = try stores()
        let a = try store.addProject(name: "A", status: .priorite2, at: now)
        let b = try store.addProject(name: "B", status: .priorite2, at: now)
        let c = try store.addProject(name: "C", status: .enPause, at: now)
        #expect(try names(store, .priorite2) == ["A", "B"])
        try store.move(c.id, to: .priorite2, before: b.id)
        #expect(try names(store, .priorite2) == ["A", "C", "B"])
        try store.move(b.id, to: .priorite2, before: a.id)
        #expect(try names(store, .priorite2) == ["B", "A", "C"])
    }

    @Test func movingOntoItselfChangesNothing() throws {
        let (store, _) = try stores()
        let a = try store.addProject(name: "A", status: .enPause, at: now)
        _ = try store.addProject(name: "B", status: .enPause, at: now)
        try store.move(a.id, to: .enPause, before: a.id)
        #expect(try names(store, .enPause) == ["A", "B"])
    }

    @Test func closePositionsAreRenumbered() throws {
        let (store, _) = try stores()
        let first = try store.addProject(name: "Premier", status: .enPause, at: now)
        let last = try store.addProject(name: "Dernier", status: .enPause, at: now)
        var expected = ["Premier"]
        for index in 0..<40 {
            let card = try store.addProject(name: "N\(index)", status: .priorite2, at: now)
            try store.move(card.id, to: .enPause, before: last.id)
            expected.append("N\(index)")
        }
        expected.append("Dernier")
        #expect(try names(store, .enPause) == expected)
        _ = first
    }

    @Test func aMeetingCanBeFiledInAProject() throws {
        let (store, meetings) = try stores()
        let project = try store.addProject(name: "Atelier client", status: .priorite2, at: now)
        let meeting = MeetingRow(createdAt: now, status: .ended, source: .dia, candidateKey: "t/a", title: "Cadrage", startedAt: now)
        try meetings.save(meeting)
        try store.setProject(meetingID: meeting.id, projectID: project.id)
        #expect(try store.meetings(projectID: project.id).map(\.title) == ["Cadrage"])
        try store.setProject(meetingID: meeting.id, projectID: nil)
        #expect(try store.meetings(projectID: project.id).isEmpty)
    }

    @Test func editingAProjectSetsLastEditedAt() throws {
        let (store, _) = try stores()
        var project = try store.addProject(name: "Alpha", status: .enPause, at: now)
        #expect(project.lastEditedAt == nil)
        project.todo = "Envoyer la maquette"
        try store.save(project, at: now.addingTimeInterval(60))
        let back = try #require(try store.project(id: project.id))
        #expect(back.todo == "Envoyer la maquette" && back.lastEditedAt == now.addingTimeInterval(60))
    }

    @Test func actionsAndJournalBelongToTheirProject() throws {
        let (store, _) = try stores()
        let project = try store.addProject(name: "Alpha", status: .enPause, at: now)
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
        let project = try store.addProject(name: "Atelier client", status: .priorite2, at: now)
        var meeting = MeetingRow(createdAt: now, status: .recording, source: .dia, candidateKey: "t/a", title: "Cadrage", startedAt: now)
        try meetings.save(meeting)
        try store.setProject(meetingID: meeting.id, projectID: project.id)
        meeting.status = .ended
        try meetings.save(meeting)
        #expect(try meetings.meeting(id: meeting.id)?.projectID == project.id)
        #expect(try meetings.meeting(id: meeting.id)?.status == .ended)
    }

    // Revue finale, mineur 8 : changer une carte de colonne est un signe de vie.
    @Test func movingACardIsASignOfLife() throws {
        let (store, _) = try stores()
        let project = try store.addProject(name: "A", status: .enPause, at: now)
        try store.move(project.id, to: .priorite1, before: nil, at: now.addingTimeInterval(120))
        #expect(try store.project(id: project.id)?.lastEditedAt == now.addingTimeInterval(120))
    }
}
