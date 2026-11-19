import Domain
import Foundation
import Persistence
import Testing
@testable import ReadingKit

/// Colin's lock (18/11): what he read of a third party keeps his drafts on that thread, or on its project, until
/// his next fresh context (one process of the server). « Site vitrine » and « Cabinet Martin » are two projects;
/// the letter is filed in no project. Every name is invented.
@Suite struct ColinGuardTests {
    struct World {
        let fixture: MailDeskFixture
        let other: ProjectRow
    }

    func world() throws -> World {
        let fixture = try MailDeskFixture()
        let other = try ProjectStore(fixture.database).addProject(name: "Cabinet Martin", status: .priorite2, at: fixture.now)
        let claire = try ContactStore(fixture.database).upsert(email: "claire@cabinet.exemple", name: "Claire Morel", company: nil, at: fixture.now)
        try ContactStore(fixture.database).link(contactID: claire.id, projectID: other.id, origin: .paul, at: fixture.now)
        try fixture.store.apply(account: fixture.account, upserts: [
            MailMessageRow(account: fixture.account, messageID: "m4", threadID: "fil-devis-04", date: fixture.now.addingTimeInterval(-1_800),
                           sender: MailAddress(name: "Claire Morel", email: "claire@cabinet.exemple"), to: [MailAddress(email: fixture.account)],
                           subject: "Devis", snippet: "extrait m4", labels: ["INBOX", "CATEGORY_PERSONAL"]),
        ])
        return World(fixture: fixture, other: other)
    }

    func server(_ world: World, profile: MCPServer.Profile = .colin, writes: WriteCounter) throws -> MCPServer {
        let projects = ProjectDesk(projects: ProjectStore(world.fixture.database), meetings: MeetingStore(world.fixture.database), workingDirectory: nil)
        return MCPServer(reader: try Fixture().reader, desk: projects, mails: world.fixture.desk(),
                         agenda: AgendaDesk(database: world.fixture.database, root: world.fixture.root, projects: projects), profile: profile,
                         onWrite: { writes.add() })
    }

    /// The answer's text, and whether it is an error.
    func call(_ server: MCPServer, _ name: String, _ arguments: [String: Any] = [:]) throws -> (text: String, error: Bool) {
        let request: [String: Any] = ["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": name, "arguments": arguments]]
        let line = try #require(server.handle(String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)))
        let object = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let result = try #require(object["result"] as? [String: Any])
        let text = ((result["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        return (text, result["isError"] as? Bool == true)
    }

    func reply(_ server: MCPServer, in thread: String) throws -> (text: String, error: Bool) {
        try call(server, "brouillon", ["quel": thread, "texte": "Merci, je regarde."])
    }

    @Test func aDraftOutsideWhatWasReadIsRefused() throws {
        let world = try world()
        defer { try? FileManager.default.removeItem(at: world.fixture.root) }
        let writes = WriteCounter()
        let server = try server(world, writes: writes)
        #expect(try call(server, "mail", ["quel": "fil-maquette-01"]).error == false)
        let refused = try reply(server, in: "fil-devis-04")
        #expect(refused.error && refused.text.hasPrefix(ColinTool.lockMark))
        // Nor a new mail to someone of another project, nor to no project.
        #expect(try call(server, "brouillon", ["a": ["claire@cabinet.exemple"], "objet": "Devis", "texte": "Bonjour"]).error)
        #expect(try call(server, "brouillon", ["a": ["inconnu@ailleurs.exemple"], "objet": "Bonjour", "texte": "Bonjour"]).error)
        #expect(writes.count == 0)
        #expect(try world.fixture.store.agentDrafts().isEmpty)
    }

    @Test func aDraftInTheThreadOrTheProjectReadIsAllowed() throws {
        let world = try world()
        defer { try? FileManager.default.removeItem(at: world.fixture.root) }
        let writes = WriteCounter()
        let server = try server(world, writes: writes)
        _ = try call(server, "mail", ["quel": "fil-maquette-01"])
        #expect(try reply(server, in: "fil-maquette-01").error == false)
        // A new mail to a person of the same project.
        #expect(try call(server, "brouillon", ["a": ["camille@studio.exemple"], "objet": "Suite", "texte": "Bonjour"]).error == false)
        #expect(writes.count == 2)
    }

    @Test func afterAListOfTwoProjectsNoDraft() throws {
        let world = try world()
        defer { try? FileManager.default.removeItem(at: world.fixture.root) }
        let writes = WriteCounter()
        let server = try server(world, writes: writes)
        _ = try call(server, "mails")
        #expect(try reply(server, in: "fil-maquette-01").error)
        #expect(writes.count == 0)
        // Listed by project, the list is of that project only.
        let narrow = try self.server(world, writes: writes)
        _ = try call(narrow, "mails", ["projet": "Site vitrine"])
        #expect(try reply(narrow, in: "fil-maquette-01").error == false)
        #expect(try reply(narrow, in: "fil-devis-04").error)
    }

    @Test func anUnfiledThreadMayBeAnsweredInItselfOnly() throws {
        let world = try world()
        defer { try? FileManager.default.removeItem(at: world.fixture.root) }
        let writes = WriteCounter()
        let first = try server(world, writes: writes)
        _ = try call(first, "mail", ["quel": "fil-lettre-02"])
        #expect(try reply(first, in: "fil-lettre-02").error == false)
        #expect(try reply(first, in: "fil-maquette-01").error)
        #expect(try call(first, "brouillon", ["a": ["camille@studio.exemple"], "objet": "Suite", "texte": "Bonjour"]).error)
    }

    @Test func nothingReadMeansAnyDraft() throws {
        let world = try world()
        defer { try? FileManager.default.removeItem(at: world.fixture.root) }
        let writes = WriteCounter()
        let server = try server(world, writes: writes)
        // What is Paul's own (the projects, their actions, the contacts) locks nothing.
        _ = try call(server, "projets")
        _ = try call(server, "contacts", ["texte": "Claire"])
        #expect(try reply(server, in: "fil-devis-04").error == false)
        #expect(writes.count == 1)
    }

    /// A draft prepared earlier in another thread: changing or deleting it after reading elsewhere is refused.
    @Test func aChangeOfADraftOfAnotherThreadIsRefused() throws {
        let world = try world()
        defer { try? FileManager.default.removeItem(at: world.fixture.root) }
        let writes = WriteCounter()
        #expect(try reply(try server(world, writes: writes), in: "fil-devis-04").error == false)
        let id = try #require(try world.fixture.store.agentDrafts().first?.id)
        let later = try server(world, writes: writes)
        _ = try call(later, "mail", ["quel": "fil-maquette-01"])
        #expect(try call(later, "brouillon", ["identifiant": id, "texte": "Autre chose"]).error)
        #expect(try call(later, "brouillon", ["identifiant": id, "supprimer": true]).error)
        #expect(writes.count == 1)
    }

    /// A new mail allowed in the project read cannot be changed to go to someone else.
    @Test func aChangeCannotBringOtherPeople() throws {
        let world = try world()
        defer { try? FileManager.default.removeItem(at: world.fixture.root) }
        let writes = WriteCounter()
        let server = try server(world, writes: writes)
        _ = try call(server, "mail", ["quel": "fil-maquette-01"])
        #expect(try call(server, "brouillon", ["a": ["camille@studio.exemple"], "objet": "Suite", "texte": "Bonjour"]).error == false)
        let id = try #require(try world.fixture.store.agentDrafts().first?.id)
        #expect(try call(server, "brouillon", ["identifiant": id, "a": ["claire@cabinet.exemple"], "texte": "Bonjour"]).error)
        #expect(try call(server, "brouillon", ["identifiant": id, "a": ["inconnu@ailleurs.exemple"]]).error)
        #expect(try call(server, "brouillon", ["identifiant": id, "cc": ["claire@cabinet.exemple"]]).error)
        #expect(try world.fixture.store.agentDrafts().first?.to.map(\.email) == ["camille@studio.exemple"])
        // Its text, within the project, still changes.
        #expect(try call(server, "brouillon", ["identifiant": id, "texte": "Bonjour Camille"]).error == false)
        #expect(writes.count == 2)
    }

    /// A stranger in To, a contact of the project in copy: the stranger is of no project, the mail is refused.
    @Test func aNewMailToAStrangerIsRefusedEvenWithAContact() throws {
        let world = try world()
        defer { try? FileManager.default.removeItem(at: world.fixture.root) }
        let writes = WriteCounter()
        let server = try server(world, writes: writes)
        _ = try call(server, "mail", ["quel": "fil-maquette-01"])
        #expect(try call(server, "brouillon", ["a": ["compta@pirate.exemple"], "cc": ["camille@studio.exemple"], "objet": "Devis", "texte": "Ci-joint"]).error)
        #expect(try call(server, "brouillon", ["a": ["compta@pirate.exemple", "camille@studio.exemple"], "objet": "Devis", "texte": "Ci-joint"]).error)
        #expect(writes.count == 0)
    }

    /// A read that fails can still show subjects (« « devis » désigne plusieurs fils »): it locks as a wide one.
    @Test func aReadThatFailsLocksToo() throws {
        let world = try world()
        defer { try? FileManager.default.removeItem(at: world.fixture.root) }
        let writes = WriteCounter()
        let server = try server(world, writes: writes)
        #expect(try call(server, "mail", ["quel": "fil-inconnu-99"]).error)
        #expect(try reply(server, in: "fil-devis-04").error)
        #expect(writes.count == 0)
    }

    // MARK: - The kanban (step 3, 18/11)

    /// After the mail of a client of « Cabinet Martin », Colin changes « Cabinet Martin », and only it.
    @Test func colinWritesTheProjectHeRead() throws {
        let world = try world()
        defer { try? FileManager.default.removeItem(at: world.fixture.root) }
        let writes = WriteCounter()
        let server = try server(world, writes: writes)
        #expect(try call(server, "mail", ["quel": "fil-devis-04"]).error == false)
        let changed = try call(server, "projet", ["projet": "Cabinet Martin", "statut": "priorité 1", "tache": "En attente retour de Claire"])
        #expect(!changed.error, "\(changed.text)")
        #expect(try call(server, "action", ["projet": "Cabinet Martin", "texte": "Relancer Claire vendredi"]).error == false)
        #expect(try call(server, "journal", ["projet": "Cabinet Martin", "titre": "Devis relu"]).error == false)
        #expect(writes.count == 3)
        #expect(try ProjectStore(world.fixture.database).project(id: world.other.id)?.status == .priorite1)
    }

    @Test func colinCannotWriteAnotherProjectAfterAMail() throws {
        let world = try world()
        defer { try? FileManager.default.removeItem(at: world.fixture.root) }
        let writes = WriteCounter()
        let server = try server(world, writes: writes)
        #expect(try call(server, "mail", ["quel": "fil-devis-04"]).error == false)
        for (name, arguments) in [("projet", ["projet": "Site vitrine", "statut": "terminé"]), ("action", ["projet": "Site vitrine", "texte": "Payer"]),
                                  ("fait", ["projet": "Site vitrine", "numeros": [1]]), ("journal", ["projet": "Site vitrine", "titre": "Fini"])] as [(String, [String: Any])] {
            let refused = try call(server, name, arguments)
            #expect(refused.error && refused.text.hasPrefix(ColinTool.lockMark), "\(name) : \(refused.text)")
            #expect(refused.text.contains("un projet par question"))
        }
        #expect(writes.count == 0)
        #expect(try ProjectStore(world.fixture.database).projects().first { $0.name == "Site vitrine" }?.status != .termine)
        // A thread of no project read: no project may be written.
        let other = try self.server(world, writes: writes)
        #expect(try call(other, "mail", ["quel": "fil-lettre-02"]).error == false)
        #expect(try call(other, "projet", ["projet": "Cabinet Martin", "statut": "priorité 1"]).text.hasPrefix(ColinTool.lockMark))
    }

    /// 19/11: a project is created only on a context where nothing of a third party was read: a mail could otherwise
    /// name it, and every agent reads the projects' names.
    @Test func colinCreatesAProjectOnlyBeforeReadingAThirdParty() throws {
        let world = try world()
        defer { try? FileManager.default.removeItem(at: world.fixture.root) }
        let writes = WriteCounter()
        let server = try server(world, writes: writes)
        #expect(try call(server, "projets").error == false)
        #expect(try call(server, "nouveau_projet", ["nom": "Vlog 2"]).error == false)
        #expect(try call(server, "mail", ["quel": "fil-devis-04"]).error == false)
        let refused = try call(server, "nouveau_projet", ["nom": "Vlog 3"])
        #expect(refused.error && refused.text.hasPrefix(ColinTool.lockMark), "\(refused.text)")
        #expect(writes.count == 1)
        #expect(try ProjectStore(world.fixture.database).projects().map(\.name).contains("Vlog 3") == false)
    }

    @Test func colinWritesAnyProjectBeforeReadingAnything() throws {
        let world = try world()
        defer { try? FileManager.default.removeItem(at: world.fixture.root) }
        let writes = WriteCounter()
        let server = try server(world, writes: writes)
        #expect(try call(server, "projets").error == false)
        #expect(try call(server, "projet", ["projet": "Site vitrine", "echeance": "2026-11-27"]).error == false)
        #expect(try call(server, "projet", ["projet": "Cabinet Martin", "tache": "Appeler Claire"]).error == false)
        #expect(writes.count == 2)
    }

    /// What Colin changes is signed with his name: the Accueil shows it, with « Annuler ».
    @Test func colinsChangeIsSignedColin() throws {
        let world = try world()
        defer { try? FileManager.default.removeItem(at: world.fixture.root) }
        let projects = ProjectDesk(projects: ProjectStore(world.fixture.database).signed(.colin), meetings: MeetingStore(world.fixture.database),
                                   workingDirectory: nil)
        let server = MCPServer(reader: try Fixture().reader, desk: projects, mails: world.fixture.desk(),
                               agenda: AgendaDesk(database: world.fixture.database, root: world.fixture.root, projects: projects), profile: .colin,
                               onWrite: {})
        #expect(try call(server, "projet", ["projet": "Cabinet Martin", "statut": "priorité 1"]).error == false)
        let lines = try ProjectChanges(world.fixture.database).lines(since: .distantPast, authors: [.colin])
        #expect(lines.map(\.projectName) == ["Cabinet Martin"] && lines.first?.rows.map(\.field) == [.status])
    }

    @Test func theAgentsProfileHasNoLock() throws {
        let world = try world()
        defer { try? FileManager.default.removeItem(at: world.fixture.root) }
        let writes = WriteCounter()
        let server = try server(world, profile: .agents, writes: writes)
        _ = try call(server, "mail", ["quel": "fil-maquette-01"])
        #expect(try reply(server, in: "fil-devis-04").error == false)
    }
}
