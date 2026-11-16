import Domain
import Foundation
import Persistence
import Testing
@testable import ReadingKit

/// The project tools of `polhub mcp`, which replace those of the `obsidian` server (13/11).
struct DeskFixture {
    let now = ISO8601DateFormatter().date(from: "2026-11-13T17:30:00Z")!
    let database: AppDatabase
    let projects: ProjectStore
    let meetings: MeetingStore
    let atelier: ProjectRow
    let vitrine: ProjectRow

    init() throws {
        database = try AppDatabase.inMemory()
        projects = ProjectStore(database)
        meetings = MeetingStore(database)
        let due = ISO8601DateFormatter().date(from: "2026-11-20T00:00:00Z")!
        atelier = ProjectRow(name: "Atelier Nord", status: .priorite1, client: "Studio Sud", dueDate: due, todo: "Envoyer la maquette",
                             contacts: ["Camille Martin"], codeFolder: "file:///Users/exemple/Code/atelier-nord",
                             notes: "- Une idée de départ\n\n## Liens\n- https://exemple.fr", kanbanOrder: 0, createdAt: now)
        vitrine = ProjectRow(name: "Site vitrine", status: .enPause, codeFolder: "/Users/exemple/Code/site vitrine", kanbanOrder: 0, createdAt: now)
        let archive = ProjectRow(name: "Ancien site", status: .termine, kanbanOrder: 0, createdAt: now)
        let actions = [
            ActionRow(projectID: atelier.id, text: "Relire la maquette", position: 0, createdAt: now),
            ActionRow(projectID: atelier.id, text: "Envoyer le devis", done: true, position: 1, createdAt: now),
            ActionRow(projectID: atelier.id, text: "Préparer la réunion", position: 2, createdAt: now),
        ]
        let entry = ProjectJournalRow(projectID: atelier.id, date: now.addingTimeInterval(-86_400), title: "Maquette v1",
                                      body: "- La page d'accueil est posée.", createdAt: now)
        try database.writer.write { [atelier, vitrine] db in
            for project in [atelier, vitrine, archive] { try project.insert(db) }
            for action in actions { try action.insert(db) }
            try entry.insert(db)
        }
        let start = now.addingTimeInterval(-7_200)
        let meeting = MeetingRow(createdAt: start, status: .ended, source: .dia, candidateKey: "t/a", title: "Point maquette",
                                 startedAt: start, endedAt: start.addingTimeInterval(1_800))
        try meetings.save(meeting)
        try projects.setProject(meetingID: meeting.id, projectID: atelier.id)
    }

    func desk(in folder: String? = nil) -> ProjectDesk {
        ProjectDesk(projects: projects, meetings: meetings, workingDirectory: folder, now: { [now] in now },
                    timeZone: TimeZone(identifier: "Europe/Paris")!)
    }
}

@Suite struct ProjectDeskTests {
    /// What Paul asks a session to change (16/11: « modifier la priorité… le todo… il avait pas les droits »): the
    /// status, the due date, the task of the moment; only the fields given change, and the answer says what.
    @Test func aSessionChangesTheProjectWhenPaulAsks() throws {
        let fixture = try DeskFixture()
        let desk = fixture.desk()
        let answer = try desk.update("Atelier Nord", status: "priorité 2", due: "2026-12-04", todo: "Relancer le client")
        #expect(answer == "« Atelier Nord » : statut priorité 2, échéance 04/12/2026, tâche du moment « Relancer le client ».")
        let changed = try #require(try fixture.projects.project(id: fixture.atelier.id))
        #expect(changed.status == .priorite2 && changed.todo == "Relancer le client" && changed.client == "Studio Sud")
        #expect(desk.day(try #require(changed.dueDate)) == "04/12/2026")
        #expect(try desk.update("atelier", status: nil, due: "aucune", todo: "") == "« Atelier Nord » : sans échéance, sans tâche du moment.")
        let cleared = try #require(try fixture.projects.project(id: fixture.atelier.id))
        #expect(cleared.dueDate == nil && cleared.todo == nil && cleared.status == .priorite2)
        #expect(try desk.update("Atelier Nord", status: "Terminé", due: nil, todo: nil) == "« Atelier Nord » : statut terminé.")
        #expect(throws: ToolError.self) { try desk.update("Atelier Nord", status: "urgent", due: nil, todo: nil) }
        #expect(throws: ToolError.self) { try desk.update("Atelier Nord", status: nil, due: "demain", todo: nil) }
        #expect(throws: ToolError.self) { try desk.update("Atelier Nord", status: nil, due: nil, todo: nil) }
    }

    /// An action reworded or removed by its number in `actions`.
    @Test func anActionIsRewordedOrRemoved() throws {
        let fixture = try DeskFixture()
        let desk = fixture.desk()
        #expect(try desk.editAction("Atelier Nord", number: 2, text: "Préparer la réunion de lundi", remove: false)
                == "Action 2 de « Atelier Nord » : Préparer la réunion de lundi")
        #expect(try desk.actions("Atelier Nord", all: false).contains("2. Préparer la réunion de lundi"))
        #expect(try desk.editAction("Atelier Nord", number: 1, text: "", remove: true) == "Action retirée de « Atelier Nord » : Relire la maquette")
        #expect(try desk.actions("Atelier Nord", all: false).contains("1. Préparer la réunion de lundi"))
        #expect(throws: ToolError.self) { try desk.editAction("Atelier Nord", number: 9, text: "x", remove: false) }
        #expect(throws: ToolError.self) { try desk.editAction("Atelier Nord", number: 1, text: " ", remove: false) }
    }

    @Test func aProjectIsFoundByNameByPieceOrByTheSessionsFolder() throws {
        let fixture = try DeskFixture()
        let desk = fixture.desk(in: "/Users/exemple/Code/atelier-nord/back")
        #expect(try desk.resolve("atelier nord").id == fixture.atelier.id)
        #expect(try desk.resolve("ATELIER NÖRD").id == fixture.atelier.id)
        #expect(try desk.resolve("vitrine").id == fixture.vitrine.id)
        #expect(try desk.resolve(nil).id == fixture.atelier.id)
        #expect(try fixture.desk(in: "/Users/exemple/Code/site vitrine").resolve(nil).id == fixture.vitrine.id)
    }

    @Test func anUnknownOrAmbiguousProjectSaysWhatToDo() throws {
        let fixture = try DeskFixture()
        #expect(throws: ToolError.self) { try fixture.desk(in: "/Users/exemple/Documents").resolve(nil) }
        do {
            _ = try fixture.desk().resolve("site")
            Issue.record("« site » est ambigu")
        } catch let error as ToolError {
            #expect(error.description.contains("Site vitrine") && error.description.contains("Ancien site"))
        }
        do {
            _ = try fixture.desk(in: "/tmp").resolve(nil)
        } catch let error as ToolError {
            #expect(error.description.contains("projets"))
        }
    }

    @Test func theListGroupsByStatusAndPointsAtTheSessionsProject() throws {
        let text = try DeskFixture().desk(in: "/Users/exemple/Code/atelier-nord").list(filter: nil)
        // Lowercase, as the `obsidian` server wrote them (15/11: four statuses).
        let first = try #require(text.range(of: "## priorité 1")), paused = try #require(text.range(of: "## en pause")),
            done = try #require(text.range(of: "## terminé"))
        #expect(first.lowerBound < paused.lowerBound && paused.lowerBound < done.lowerBound)
        #expect(text.contains("Atelier Nord · Studio Sud · échéance 20/11/2026"))
        #expect(text.contains("Atelier Nord") && text.contains("← ce dossier"))
        #expect(try DeskFixture().desk().list(filter: "vitrine").contains("Site vitrine"))
        #expect(!(try DeskFixture().desk().list(filter: "vitrine").contains("Atelier Nord")))
    }

    @Test func openActionsAreNumberedAndDoneOnesAreOnlyShownOnRequest() throws {
        let desk = try DeskFixture().desk()
        let open = try desk.actions("Atelier Nord", all: false)
        #expect(open.contains("1. Relire la maquette") && open.contains("2. Préparer la réunion"))
        #expect(!open.contains("Envoyer le devis"))
        #expect(try desk.actions("Atelier Nord", all: true).contains("✓ Envoyer le devis"))
    }

    @Test func anAddedActionComesLastAndTheAnswerNamesTheProject() throws {
        let fixture = try DeskFixture()
        let desk = fixture.desk()
        let answer = try desk.addAction("Atelier Nord", text: "Corriger la page Contact")
        #expect(answer.contains("« Atelier Nord »"))
        #expect(try desk.actions("Atelier Nord", all: false).contains("3. Corriger la page Contact"))
    }

    @Test func doneChecksTheNumberedActions() throws {
        let fixture = try DeskFixture()
        let desk = fixture.desk()
        let answer = try desk.done("Atelier Nord", numbers: [1])
        #expect(answer.contains("Relire la maquette") && answer.contains("« Atelier Nord »"))
        let open = try desk.actions("Atelier Nord", all: false)
        #expect(open.contains("1. Préparer la réunion") && !open.contains("Relire la maquette"))
        #expect(throws: ToolError.self) { try desk.done("Atelier Nord", numbers: [5]) }
    }

    @Test func aNoteIsADatedBulletAtTheEndOfTheNotesPart() throws {
        let fixture = try DeskFixture()
        _ = try fixture.desk().addNote("Atelier Nord", text: "Le client veut une version anglaise.")
        let notes = try #require(try fixture.projects.project(id: fixture.atelier.id)).notes
        #expect(notes == "- Une idée de départ\n- 13/11/2026 : Le client veut une version anglaise.\n\n## Liens\n- https://exemple.fr")
        _ = try fixture.desk().addNote("Site vitrine", text: "Première note.")
        #expect(try #require(try fixture.projects.project(id: fixture.vitrine.id)).notes == "- 13/11/2026 : Première note.")
    }

    @Test func aJournalEntryIsDatedAndShownFirst() throws {
        let fixture = try DeskFixture()
        let desk = fixture.desk()
        _ = try desk.addJournal("Atelier Nord", title: "Page Contact", details: ["Formulaire branché.", "Retour arrière : git revert."])
        let entries = try fixture.projects.journal(projectID: fixture.atelier.id)
        #expect(entries.first?.title == "Page Contact")
        #expect(entries.first?.body == "- Formulaire branché.\n- Retour arrière : git revert.")
        #expect(throws: ToolError.self) { try desk.addJournal("Atelier Nord", title: "  ", details: []) }
    }

    @Test func theBriefHasEverything() throws {
        let text = try DeskFixture().desk(in: "/Users/exemple/Code/atelier-nord").context(nil, all: false)
        for piece in ["# Atelier Nord", "priorité 1", "Studio Sud", "20/11/2026", "Envoyer la maquette", "Camille Martin",
                      "1. Relire la maquette", "Point maquette", "Une idée de départ", "Maquette v1", "La page d'accueil est posée."] {
            #expect(text.contains(piece), "il manque « \(piece) »")
        }
    }

    /// Base v4 (13/11): the brief shows the linked contacts and the coming events.
    @Test func theBriefShowsContactsAndComingEvents() throws {
        let fixture = try DeskFixture()
        let contacts = ContactStore(fixture.database)
        let jules = try contacts.upsert(email: "jules@exemple.fr", name: "Jules Roy", company: "Exemple", at: fixture.now)
        try contacts.link(contactID: jules.id, projectID: fixture.atelier.id, origin: .agenda, at: fixture.now)
        let calendar = CalendarStore(fixture.database)
        try calendar.applyGoogle(account: "moi@exemple.fr", changed: [
            CalendarEventRow(account: "moi@exemple.fr", eventID: "e1", title: "Revue de la maquette", startAt: fixture.now.addingTimeInterval(86_400),
                             endAt: fixture.now.addingTimeInterval(88_200), updatedAt: fixture.now),
        ], cancelled: [], at: fixture.now)
        try calendar.setProject(eventID: CalendarEventRow.key(account: "moi@exemple.fr", eventID: "e1"), projectID: fixture.atelier.id, origin: .invites)
        let text = try fixture.desk().context("Atelier Nord", all: false)
        #expect(text.contains("Jules Roy (Exemple, jules@exemple.fr)"))
        #expect(text.contains("Revue de la maquette"))
    }

    @Test func theProjectsMeetingsKeepTheirNumberInTheWholeList() throws {
        let fixture = try DeskFixture()
        let other = MeetingRow(createdAt: fixture.now, status: .ended, source: .dia, candidateKey: "t/b", title: "Autre réunion",
                               startedAt: fixture.now.addingTimeInterval(-600), endedAt: fixture.now)
        try fixture.meetings.save(other)
        let text = try fixture.desk().meetings("Atelier Nord")
        #expect(text.contains("2. ") && text.contains("Point maquette") && !text.contains("Autre réunion"))
    }

    @Test func searchFindsProjectsByTheirTextWithoutCaseOrAccents() throws {
        let text = try #require(try DeskFixture().desk().search("PREPARER"))
        #expect(text.contains("Atelier Nord") && text.contains("Préparer la réunion"))
        #expect(try DeskFixture().desk().search("introuvable") == nil)
    }
}
