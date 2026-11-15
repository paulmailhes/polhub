import Domain
import Foundation
import Persistence
import Testing
@testable import ProjectsUI

/// Projets, 14/11: the Kanban and the « Liste », a search for both, a project created with all its fields.
@MainActor @Suite struct ProjectListTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)

    func project(_ name: String, _ status: ProjectStatus, client: String? = nil, due: Date? = nil, todo: String? = nil,
                 activity: Date? = nil, notes: String = "") -> ProjectRow {
        ProjectRow(name: name, status: status, client: client, dueDate: due, todo: todo, lastActivity: activity, notes: notes, createdAt: now)
    }

    @Test func theViewsAreTheKanbanAndTheList() {
        #expect(ProjectsMode.allCases.map(\.rawValue) == ["Kanban", "Liste"])
    }

    @Test func theSearchLooksInTheNameTheClientTheNextStepAndTheNotes() {
        let projects = [project("Refonte du site", .priorite1, client: "Atelier Nord"), project("Identité", .enPause, todo: "Valider la typographie"),
                        project("Agence", .enPause, notes: "Le **logo** est chez l'imprimeur."), project("Landing", .priorite2)]
        #expect(ProjectViews.matching(projects, "atelier").map(\.name) == ["Refonte du site"])
        #expect(ProjectViews.matching(projects, "TYPO").map(\.name) == ["Identité"])
        #expect(ProjectViews.matching(projects, "imprimeur").map(\.name) == ["Agence"])
        #expect(ProjectViews.matching(projects, "identite").map(\.name) == ["Identité"])
        #expect(ProjectViews.matching(projects, "  ").count == 4)
    }

    @Test func theListFiltersByStatusAndSortsByAnyColumn() {
        let projects = [project("B", .priorite2, client: "Zeta", due: now.addingTimeInterval(86_400 * 3), activity: now.addingTimeInterval(3_600)),
                        project("A", .priorite1, due: now.addingTimeInterval(86_400), activity: now.addingTimeInterval(-86_400)),
                        project("C", .termine, client: "Alpha"), project("D", .enPause, client: "beta")]
        let rows = ProjectListRow.rows(projects, lastMeetings: [:], status: nil)
        #expect(Set(rows.map(\.project.name)) == ["A", "B", "C", "D"])
        #expect(ProjectListRow.rows(projects, lastMeetings: [:], status: .priorite1).map(\.project.name) == ["A"])
        #expect(rows.sorted(using: KeyPathComparator(\ProjectListRow.statusRank)).map(\.project.name) == ["B", "A", "D", "C"])
        #expect(rows.sorted(using: KeyPathComparator(\ProjectListRow.dueSort)).map(\.project.name).prefix(2) == ["A", "B"])
        #expect(rows.sorted(using: KeyPathComparator(\ProjectListRow.clientSort)).map(\.project.name) == ["C", "D", "B", "A"])
        #expect(rows.sorted(using: KeyPathComparator(\ProjectListRow.activitySort, order: .reverse)).map(\.project.name).first == "B")
    }

    @Test func aNewProjectKeepsEveryFieldAndGoesToTheBottomOfItsColumn() throws {
        let database = try AppDatabase.inMemory()
        let store = ProjectStore(database)
        let library = ProjectLibrary(store: store, meetings: MeetingStore(database), defaults: UserDefaults(suiteName: "nouveau-\(UUID().uuidString)")!)
        _ = try store.addProject(name: "Déjà là", status: .priorite1, at: now)
        var draft = ProjectRow(name: "  Nouveau site  ", status: .priorite1, createdAt: now)
        draft.client = "Atelier Nord"
        draft.todo = "Envoyer le devis"
        draft.dueDate = now
        draft.icon = "🌿"
        draft.color = "vert"
        draft.codeFolder = "/Users/exemple/Code/site"
        draft.notes = "Premier contact."
        let created = try #require(library.create(draft))
        let stored = try #require(try store.project(id: created.id))
        #expect(stored.name == "Nouveau site" && stored.client == "Atelier Nord" && stored.todo == "Envoyer le devis" && stored.dueDate == now)
        #expect(stored.icon == "🌿" && stored.color == "vert" && stored.codeFolder == "/Users/exemple/Code/site" && stored.notes == "Premier contact.")
        let column = try store.projects().filter { $0.status == .priorite1 }.sorted { $0.kanbanOrder < $1.kanbanOrder }
        #expect(column.map(\.name) == ["Déjà là", "Nouveau site"])
        #expect(library.create(ProjectRow(name: " ", status: .enPause, createdAt: now)) == nil)
    }
}
