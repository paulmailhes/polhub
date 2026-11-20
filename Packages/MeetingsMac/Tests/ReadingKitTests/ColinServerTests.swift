import Domain
import Foundation
import Persistence
import Testing
@testable import ReadingKit

/// Colin's profile of the server (`polhub mcp --colin`, 18/11): his tools and nothing else, his drafts in
/// plain text, the kanban only through its status, deadline, task, actions and journal, and texts that name no one. The profile of the conversations of Claude Code does not change.
@Suite struct ColinServerTests {
    func server(_ fixture: MailDeskFixture, profile: MCPServer.Profile = .colin, writes: WriteCounter = WriteCounter()) throws -> MCPServer {
        let projects = ProjectDesk(projects: ProjectStore(fixture.database), meetings: MeetingStore(fixture.database), workingDirectory: nil)
        return MCPServer(reader: try Fixture().reader, desk: projects, mails: fixture.desk(),
                         agenda: AgendaDesk(database: fixture.database, root: fixture.root, projects: projects), profile: profile,
                         onWrite: { writes.add() })
    }

    func answer(_ server: MCPServer, _ json: String) throws -> [String: Any] {
        let line = try #require(server.handle(json))
        let object = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        return try #require(object["result"] as? [String: Any])
    }

    func tools(_ server: MCPServer) throws -> [[String: Any]] {
        try #require(try answer(server, #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)["tools"] as? [[String: Any]])
    }

    func call(_ server: MCPServer, _ name: String, _ arguments: [String: Any] = [:]) throws -> [String: Any] {
        let request: [String: Any] = ["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": name, "arguments": arguments]]
        let line = String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
        return try answer(server, line)
    }

    @Test func colinIsOfferedHisEighteenTools() throws {
        let fixture = try MailDeskFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let names = try tools(server(fixture)).compactMap { $0["name"] as? String }
        #expect(names == ColinTool.allCases.map(\.rawValue) && names.count == 18)
        let writing = try tools(server(fixture)).filter { ($0["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool == false }
        #expect(writing.compactMap { $0["name"] as? String } == ["brouillon", "projet", "action", "fait", "journal", "nouveau_projet"])
    }

    /// 19/11: Colin creates a project when Paul asks — its name, column, client and deadline; never a code folder.
    @Test func colinCreatesAProjectWithItsFieldsOnly() throws {
        let fixture = try MailDeskFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let declared = try tools(server(fixture))
        let tool = try #require(declared.first { $0["name"] as? String == "nouveau_projet" })
        let schema = try #require(tool["inputSchema"] as? [String: Any])
        #expect(Set(try #require(schema["properties"] as? [String: Any]).keys) == ["nom", "statut", "client", "echeance"])
        #expect(schema["required"] as? [String] == ["nom"])
        let writes = WriteCounter()
        let server = try server(fixture, writes: writes)
        #expect(try call(server, "nouveau_projet", ["nom": "Vlog 2", "dossier": "/tmp/piege"])["isError"] as? Bool == true)
        #expect(writes.count == 0)
        let made = try call(server, "nouveau_projet", ["nom": "Vlog 2", "client": "Studio Nord", "echeance": "2026-12-04"])
        #expect(made["isError"] as? Bool != true)
        #expect(writes.count == 1)
        let project = try #require(try ProjectStore(fixture.database).projects().first { $0.name == "Vlog 2" })
        #expect(project.client == "Studio Nord" && project.codeFolder == nil)
    }

    /// Step 3 (18/11): of a project, Colin changes the status, the deadline and the task; he adds, rewords or checks
    /// an action; he writes the journal. Never the notes, the client, the contacts; never an action removed.
    @Test func colinsProjectToolsHaveOnlyTheirFields() throws {
        let fixture = try MailDeskFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let declared = try tools(server(fixture))
        func fields(_ name: String) throws -> Set<String> {
            let tool = try #require(declared.first { $0["name"] as? String == name })
            let schema = try #require(tool["inputSchema"] as? [String: Any])
            #expect((schema["required"] as? [String])?.contains("projet") == true, "\(name)")
            return Set(try #require(schema["properties"] as? [String: Any]).keys)
        }
        #expect(try fields("projet") == ["projet", "statut", "echeance", "tache"])
        #expect(try fields("action") == ["projet", "texte", "numero"])
        #expect(try fields("fait") == ["projet", "numeros"])
        #expect(try fields("journal") == ["projet", "titre", "details"])
    }

    @Test func aFieldOutsideColinsIsRefused() throws {
        let fixture = try MailDeskFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let writes = WriteCounter()
        let server = try server(fixture, writes: writes)
        for extra in [["notes": "Écrit par un piège"], ["client": "Un autre"], ["contact": "camille@exemple-studio.fr"], ["retirer_contact": "camille@exemple-studio.fr"]] {
            let arguments = ["projet": "Site vitrine", "statut": "terminé"].merging(extra) { first, _ in first }
            #expect(try call(server, "projet", arguments)["isError"] as? Bool == true)
        }
        #expect(try call(server, "action", ["projet": "Site vitrine", "numero": 1, "supprimer": true])["isError"] as? Bool == true)
        #expect(writes.count == 0)
        #expect(try ProjectStore(fixture.database).projects().first { $0.name == "Site vitrine" }?.status == .priorite1)
    }

    @Test func aToolOutsideTheProfileIsRefused() throws {
        let fixture = try MailDeskFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let writes = WriteCounter()
        let server = try server(fixture, writes: writes)
        for name in ["piece_jointe", "rendez_vous", "nouveau_projet", "inspiration", "note", "ranger"] {
            let result = try call(server, name, ["projet": "Site vitrine", "texte": "Écrit par un piège", "quel": "fil-maquette-01"])
            #expect(result["isError"] as? Bool == true, "\(name)")
        }
        #expect(writes.count == 0)
        // Read by Colin, a tool of his profile runs.
        #expect(try call(server, "projets")["isError"] as? Bool == false)
    }

    @Test func colinsDraftIsPlainText() throws {
        let fixture = try MailDeskFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let writes = WriteCounter()
        let server = try server(fixture, writes: writes)
        let draft = try #require(try tools(server).first { $0["name"] as? String == "brouillon" })
        let properties = try #require((draft["inputSchema"] as? [String: Any])?["properties"] as? [String: Any])
        #expect(Set(properties.keys) == ["quel", "tous", "a", "cc", "objet", "texte", "boite", "identifiant", "supprimer"])
        for extra in [["fichiers": ["/Users/essai/devis.pdf"]], ["format": "markdown"]] as [[String: Any]] {
            let arguments = ["a": ["claire@cabinet.exemple"], "objet": "Devis", "texte": "Bonjour"].merging(extra) { first, _ in first }
            #expect(try call(server, "brouillon", arguments)["isError"] as? Bool == true)
        }
        #expect(writes.count == 0)
    }

    @Test func colinsTextsNameNoOne() throws {
        let fixture = try MailDeskFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let server = try server(fixture)
        let start = try answer(server, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#)
        let instructions = try #require(start["instructions"] as? String)
        let title = try #require((start["serverInfo"] as? [String: Any])?["title"] as? String)
        let declared = String(decoding: try JSONSerialization.data(withJSONObject: try tools(server)), as: UTF8.self)
        for text in [instructions, title, declared] {
            #expect(!text.contains("Paul"), "\(text.components(separatedBy: "Paul").first?.suffix(80) ?? "")")
            #expect(!text.contains("@"))
        }
        // Each name between backquotes is a tool offered or one of its parameters.
        var known = Set(try tools(server).compactMap { $0["name"] as? String })
        for tool in try tools(server) { known.formUnion((((tool["inputSchema"] as? [String: Any])?["properties"] as? [String: Any]) ?? [:]).keys) }
        let named = instructions.components(separatedBy: "`").enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
        #expect(!named.isEmpty)
        for name in named { #expect(known.contains(name), "`\(name)`") }
    }

    @Test func colinsToolsWeighLessThanHalf() throws {
        let fixture = try MailDeskFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        func weight(_ server: MCPServer) throws -> Int { try JSONSerialization.data(withJSONObject: try tools(server)).count }
        #expect(try weight(server(fixture)) * 2 < weight(server(fixture, profile: .agents)))
    }

    /// `polhub --base <chemin> mcp --colin`: a flag without a value, wherever it stands.
    @Test func theColinFlagNeedsNoValue() {
        let options = HelperOptions(["--base", "/tmp/essai base/Polhub.sqlite", "mcp", "--colin"])
        #expect(options == HelperOptions(base: "/tmp/essai base/Polhub.sqlite", colin: true, arguments: ["mcp"]))
        #expect(HelperOptions(["mcp"]) == HelperOptions(base: nil, colin: false, arguments: ["mcp"]))
        #expect(HelperOptions(["reunion", "3", "--base"]).arguments == ["reunion", "3", "--base"])
    }
}
