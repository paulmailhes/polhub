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

    /// `author`: who the desk writes as — Paul's by default, as the tests of before the journal expect.
    init(author: ChangeAuthor = .paul) throws {
        database = try AppDatabase.inMemory(author: author)
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

    /// `root`: the folder of Polhub's data, where Inspiration's images live.
    func desk(in folder: String? = nil, root: URL? = nil) -> ProjectDesk {
        ProjectDesk(projects: projects, meetings: meetings, workingDirectory: folder, dataRoot: root, now: { [now] in now },
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
        #expect(throws: ToolError.self) { try desk.update("Atelier Nord", status: nil, due: nil, todo: nil, notes: "", contact: "", removeContact: "") }
    }

    /// Paul's 7 (16/11): a session creates a project when he asks, with what it was given, at the bottom of its
    /// column, as the board's « + » does.
    @Test func aSessionCreatesAProjectWhenPaulAsks() throws {
        let fixture = try DeskFixture()
        let desk = fixture.desk()
        let code = try Self.folder("Code/refonte")
        defer { try? FileManager.default.removeItem(at: code.deletingLastPathComponent().deletingLastPathComponent()) }
        let path = ProjectDesk.normalized(code.path(percentEncoded: false))
        let answer = try desk.create(name: " Refonte Exemple ", status: "priorité 2", client: "Studio Est", due: "2026-12-04", folder: path + "/")
        #expect(answer == "Projet « Refonte Exemple » créé : priorité 2, client « Studio Est », échéance 04/12/2026, dossier \(path). "
                + "Une session ouverte dans ce dossier travaillera sur ce projet.")
        let created = try desk.resolve("Refonte Exemple")
        #expect(created.status == .priorite2 && created.client == "Studio Est" && created.codeFolder == path)
        #expect(desk.day(try #require(created.dueDate)) == "04/12/2026" && created.createdOn == fixture.now)
        // The session opened in its folder finds it.
        #expect(try fixture.desk(in: path + "/front").resolve(nil).id == created.id)
    }

    /// The code folder of a new project is one folder of the Mac, its own: never the home folder or above it (every
    /// session would take the project for its own), never one holding another project's folder (review of 16/11).
    @Test func aNewProjectsFolderIsItsOwn() throws {
        let fixture = try DeskFixture()
        let base = try Self.folder("maison/Code/piste")
        let top = base.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: top) }
        let home = top.appending(path: "maison", directoryHint: .isDirectory)
        let desk = ProjectDesk(projects: fixture.projects, meetings: fixture.meetings, workingDirectory: nil, now: { [now = fixture.now] in now },
                               home: home)
        func refused(_ folder: String, _ reason: String, sourceLocation: SourceLocation = #_sourceLocation) {
            do {
                _ = try desk.create(name: "Autre piste", status: nil, client: nil, due: nil, folder: folder)
                Issue.record("accepté : \(folder)", sourceLocation: sourceLocation)
            } catch {
                #expect(error is ToolError && "\(error)".contains(reason), "\(error)", sourceLocation: sourceLocation)
            }
        }
        refused(home.path(percentEncoded: false), "trop large")
        refused(top.path(percentEncoded: false), "trop large")
        refused("/", "trop large")
        refused(top.appending(path: "absent").path(percentEncoded: false), "n'est pas un dossier")
        try Data("x".utf8).write(to: top.appending(path: "note.txt"))
        refused(top.appending(path: "note.txt").path(percentEncoded: false), "n'est pas un dossier")
        // An app is a folder too, which a click would launch (audit of 19/11).
        try FileManager.default.createDirectory(at: top.appending(path: "Outil.app/Contents", directoryHint: .isDirectory), withIntermediateDirectories: true)
        refused(top.appending(path: "Outil.app").path(percentEncoded: false), "paquet")
        _ = try desk.create(name: "Piste", status: nil, client: nil, due: nil, folder: base.path(percentEncoded: false))
        refused(base.path(percentEncoded: false), "« Piste »")
        refused(home.appending(path: "Code").path(percentEncoded: false), "« Piste »")
        #expect(try fixture.projects.projects().count == 4)
    }

    /// A folder made for a test, under a temporary one of its own.
    static func folder(_ relative: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "projets-\(UUID().uuidString)/\(relative)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.standardizedFileURL
    }

    @Test func aNewProjectHasDefaultsAndComesLastInItsColumn() throws {
        let fixture = try DeskFixture()
        let desk = fixture.desk()
        #expect(try desk.create(name: "Nouvelle piste", status: nil, client: nil, due: nil, folder: nil) == "Projet « Nouvelle piste » créé : priorité 1.")
        let created = try desk.resolve("Nouvelle piste")
        #expect(created.status == .priorite1 && created.client == nil && created.dueDate == nil && created.codeFolder == nil && created.todo == nil)
        // « Atelier Nord » is first in « priorité 1 »: the new one comes after it.
        #expect(created.kanbanOrder > fixture.atelier.kanbanOrder)
        #expect(try desk.list(filter: nil).contains("Nouvelle piste"))
        _ = try desk.create(name: "Autre piste", status: "", client: "", due: "", folder: "")
        #expect(try desk.resolve("Autre piste").kanbanOrder > created.kanbanOrder)
    }

    /// A name that exists is refused (case and accents ignored), and so is what cannot be read: nothing is created.
    @Test func aNewProjectNeedsANewNameAndReadableFields() throws {
        let fixture = try DeskFixture()
        let desk = fixture.desk()
        do {
            _ = try desk.create(name: "atelier nörd", status: nil, client: nil, due: nil, folder: nil)
            Issue.record("« Atelier Nord » existe déjà")
        } catch let error as ToolError {
            #expect(error.description.contains("« Atelier Nord »"))
        }
        #expect(throws: ToolError.self) { try desk.create(name: "  ", status: nil, client: nil, due: nil, folder: nil) }
        #expect(throws: ToolError.self) { try desk.create(name: "Piste", status: "urgent", client: nil, due: nil, folder: nil) }
        #expect(throws: ToolError.self) { try desk.create(name: "Piste", status: nil, client: nil, due: "vendredi", folder: nil) }
        #expect(throws: ToolError.self) { try desk.create(name: "Piste", status: nil, client: nil, due: nil, folder: "Code/piste") }
        #expect(try fixture.projects.projects().count == 3)
    }

    /// The client changes, or goes (empty or « aucun »); the notes are replaced whole, as a session wrote them.
    @Test func theClientAndTheNotesChange() throws {
        let fixture = try DeskFixture()
        let desk = fixture.desk()
        #expect(try desk.update("Atelier Nord", status: nil, due: nil, todo: nil, client: "Studio Est") == "« Atelier Nord » : client « Studio Est ».")
        #expect(try fixture.projects.project(id: fixture.atelier.id)?.client == "Studio Est")
        #expect(try desk.update("Atelier Nord", status: nil, due: nil, todo: nil, client: "aucun") == "« Atelier Nord » : sans client.")
        #expect(try fixture.projects.project(id: fixture.atelier.id)?.client == nil)
        _ = try desk.update("Atelier Nord", status: nil, due: nil, todo: nil, client: "Studio Est")
        #expect(try desk.update("Atelier Nord", status: nil, due: nil, todo: nil, client: "") == "« Atelier Nord » : sans client.")
        let rewritten = "- Le client veut une version anglaise.\n\n## Liens\n- https://exemple.fr"
        // The notes Paul had are kept whole in the journal, and the answer says how much was replaced (review of 16/11).
        #expect(try desk.update("Atelier Nord", status: nil, due: nil, todo: nil, notes: rewritten)
                == "« Atelier Nord » : notes remplacées (\(fixture.atelier.notes.count) → \(rewritten.count) caractères ; les anciennes sont gardées au journal du projet).")
        let changed = try #require(try fixture.projects.project(id: fixture.atelier.id))
        #expect(changed.notes == rewritten)
        #expect(changed.todo == "Envoyer la maquette" && changed.status == .priorite1)
        let kept = try #require(try fixture.projects.journal(projectID: fixture.atelier.id).first)
        #expect(kept.title == "Notes avant leur remplacement par un agent" && kept.body == fixture.atelier.notes)
        // The same notes again: nothing to keep.
        #expect(try desk.update("Atelier Nord", status: nil, due: nil, todo: nil, notes: rewritten).contains("notes remplacées"))
        #expect(try fixture.projects.journal(projectID: fixture.atelier.id).count == 2)
        // Empty notes are no notes given: nothing is wiped.
        #expect(throws: ToolError.self) { try desk.update("Atelier Nord", status: nil, due: nil, todo: nil, notes: "  ") }
        #expect(try fixture.projects.project(id: fixture.atelier.id)?.notes == changed.notes)
    }

    /// A contact is linked as Paul links one, by its address or its name, and taken out as Paul takes one out (it
    /// stays out); an unknown or ambiguous one is refused and nothing changes.
    @Test func aContactIsLinkedOrTakenOutByAddressOrName() throws {
        let fixture = try DeskFixture()
        let desk = fixture.desk()
        let contacts = ContactStore(fixture.database)
        let jules = try contacts.upsert(email: "jules@exemple.fr", name: "Jules Roy", company: "Exemple", at: fixture.now)
        _ = try contacts.upsert(email: "alex.durand@exemple.fr", name: "Alex Durand", company: nil, at: fixture.now)
        _ = try contacts.upsert(email: "alex.petit@exemple.fr", name: "Alex Petit", company: nil, at: fixture.now)
        #expect(try desk.update("Atelier Nord", status: nil, due: nil, todo: nil, contact: "JULES@exemple.fr")
                == "« Atelier Nord » : contact Jules Roy (jules@exemple.fr) lié.")
        #expect(try contacts.contacts(projectID: fixture.atelier.id).map(\.id) == [jules.id])
        #expect(try contacts.links().first { $0.contactID == jules.id }?.origin == .paul)
        #expect(try desk.update("Atelier Nord", status: nil, due: nil, todo: nil, contact: "Jules Roy <jules@exemple.fr>")
                == "« Atelier Nord » : contact Jules Roy (jules@exemple.fr) déjà lié.")
        #expect(try desk.update("Atelier Nord", status: nil, due: nil, todo: nil, removeContact: "jules roy")
                == "« Atelier Nord » : contact Jules Roy (jules@exemple.fr) retiré.")
        #expect(try contacts.contacts(projectID: fixture.atelier.id).isEmpty)
        #expect(try contacts.links().first { $0.contactID == jules.id }?.excluded == true)
        // Taken out, it stays out: only Paul puts it back, from the project's page (review of 16/11).
        do {
            _ = try desk.update("Atelier Nord", status: nil, due: nil, todo: nil, contact: "Jules")
            Issue.record("Jules a été retiré du projet")
        } catch let error as ToolError {
            #expect(error.description.contains("retiré de « Atelier Nord »") && error.description.contains("Paul"))
        }
        #expect(try contacts.contacts(projectID: fixture.atelier.id).isEmpty)
        // By a piece of the name, a contact never linked comes in; the page open on the project hears of it.
        let later = ProjectDesk(projects: fixture.projects, meetings: fixture.meetings, workingDirectory: nil, now: { [now = fixture.now] in now.addingTimeInterval(60) })
        let nina = try contacts.upsert(email: "nina@exemple.fr", name: "Nina Durand", company: nil, at: fixture.now)
        #expect(try later.update("Atelier Nord", status: nil, due: nil, todo: nil, contact: "Nina").contains("Nina Durand (nina@exemple.fr) lié"))
        #expect(try contacts.contacts(projectID: fixture.atelier.id).map(\.id) == [nina.id])
        #expect(try fixture.projects.project(id: fixture.atelier.id)?.updatedAt == fixture.now.addingTimeInterval(60))
        // Unknown, ambiguous, not linked: refused, and the status given with it is not changed.
        #expect(throws: ToolError.self) { try desk.update("Atelier Nord", status: "en pause", due: nil, todo: nil, contact: "inconnu@exemple.fr") }
        #expect(throws: ToolError.self) { try desk.update("Atelier Nord", status: "en pause", due: nil, todo: nil, contact: "Personne Inconnue") }
        do {
            _ = try desk.update("Atelier Nord", status: nil, due: nil, todo: nil, contact: "alex")
            Issue.record("« alex » est ambigu")
        } catch let error as ToolError {
            #expect(error.description.contains("alex.durand@exemple.fr") && error.description.contains("alex.petit@exemple.fr"))
        }
        #expect(throws: ToolError.self) { try desk.update("Atelier Nord", status: nil, due: nil, todo: nil, removeContact: "Alex Durand") }
        #expect(try fixture.projects.project(id: fixture.atelier.id)?.status == .priorite1)
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
