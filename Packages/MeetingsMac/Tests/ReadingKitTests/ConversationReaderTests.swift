import Domain
import Foundation
import Persistence
import Testing
@testable import ReadingKit

/// The conversations of Claude Code, for Colin (Paul, 20/11: « Colin peut voir l'historique de toutes mes
/// conversations Claude Code, en lecture seule »). Two conversations, invented: the site's, recent, and an invoice's,
/// older; and a sub-agent's file, which is no conversation of the user's.
struct ConversationFixture {
    static let site = "1a2b3c4d-0000-4000-8000-00000000aaaa"
    static let invoice = "9f8e7d6c-0000-4000-8000-00000000bbbb"
    static let siteFolder = "/Users/essai/Code/site"
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "conversations-\(UUID().uuidString)", directoryHint: .isDirectory)
        let site = root.appending(path: "-Users-essai-Code-site", directoryHint: .isDirectory)
        let invoice = root.appending(path: "-Users-essai-Code-factures", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: site.appending(path: "\(Self.site)/subagents"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: invoice, withIntermediateDirectories: true)
        try Self.write(Self.siteLines(), to: site.appending(path: "\(Self.site).jsonl"), modified: Date(timeIntervalSince1970: 1_795_000_000))
        try Self.write([
            Self.line(["type": "user", "cwd": "/Users/essai/Code/factures", "message": ["role": "user", "content": "Prépare la facture de novembre."]]),
            Self.line(["type": "assistant", "cwd": "/Users/essai/Code/factures", "message": ["role": "assistant", "content": [["type": "text", "text": "La facture est prête."]]]]),
            Self.line(["type": "ai-title", "aiTitle": "Facture de novembre"]),
        ], to: invoice.appending(path: "\(Self.invoice).jsonl"), modified: Date(timeIntervalSince1970: 1_794_000_000))
        try Self.write([Self.line(["type": "user", "cwd": Self.siteFolder, "message": ["role": "user", "content": "Consigne d'un sous-agent"]]),
                        Self.line(["type": "ai-title", "aiTitle": "Travail d'un sous-agent"])],
                       to: site.appending(path: "\(Self.site)/subagents/agent-1.jsonl"), modified: Date(timeIntervalSince1970: 1_796_000_000))
    }

    var reader: ConversationReader { ConversationReader(roots: [root]) }

    static func siteLines() -> [String] {
        let folder = siteFolder
        return [
            line(["type": "user", "cwd": folder, "isSidechain": false, "timestamp": "2026-11-18T09:00:00.000Z",
                  "message": ["role": "user", "content": "<system-reminder>Texte caché du système</system-reminder>Peux-tu refaire la page Expertise ?"]]),
            line(["type": "assistant", "cwd": folder, "isSidechain": false, "timestamp": "2026-11-18T09:00:05.000Z",
                  "message": ["role": "assistant", "content": [["type": "thinking", "thinking": "Une pensée de Claude"], ["type": "text", "text": "Je regarde la page."]]]]),
            line(["type": "assistant", "cwd": folder, "message": ["role": "assistant", "content": [["type": "tool_use", "name": "Read", "input": ["file_path": "/x"]]]]]),
            line(["type": "user", "cwd": folder, "toolUseResult": ["ok": true],
                  "message": ["role": "user", "content": [["type": "tool_result", "content": "Contenu d'un fichier lu par un outil"]]]]),
            line(["type": "user", "cwd": folder, "isSidechain": true, "message": ["role": "user", "content": "Consigne d'un sous-agent"]]),
            line(["type": "user", "cwd": folder, "isMeta": true, "message": ["role": "user", "content": "Texte d'une compétence chargée"]]),
            line(["type": "user", "cwd": folder, "message": ["role": "user", "content": [
                ["type": "text", "text": "<ide_selection>Une sélection de l'éditeur</ide_selection>"],
                ["type": "text", "text": "<pasted_content id=\"x1\">\nLe texte collé par l'utilisateur\n</pasted_content id=\"x1\">"],
            ]]]),
            line(["type": "assistant", "cwd": folder, "message": ["role": "assistant", "content": [
                ["type": "text", "text": "C'est fait. La clé sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789 et le jeton ghp_abcdefghijklmnopqrstuvwxyz0123456789 sont dans le fichier."],
            ]]]),
            line(["type": "ai-title", "aiTitle": "Une ancienne idée de titre"]),
            line(["type": "ai-title", "aiTitle": "Refonte de la page Expertise"]),
            line(["type": "last-prompt", "lastPrompt": "Le texte collé par l'utilisateur"]),
        ]
    }

    static func line(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }

    static func write(_ lines: [String], to file: URL, modified: Date) throws {
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path(percentEncoded: false))
    }
}

@Suite struct ConversationReaderTests {
    @Test func theConversationsComeNewestFirstWithTheirTitleAndFolder() throws {
        let fixture = try ConversationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let list = try fixture.reader.list(limit: 20)
        let site = try #require(list.range(of: "Refonte de la page Expertise"))
        let invoice = try #require(list.range(of: "Facture de novembre"))
        #expect(site.lowerBound < invoice.lowerBound)
        #expect(list.contains("[1a2b3c4d]") && list.contains("Code/site"))
        // A sub-agent's work is no conversation of the user's; an old title gives way to the last one.
        #expect(!list.contains("sous-agent") && !list.contains("ancienne idée"))
    }

    @Test func theyAreFoundByFolderOrByWords() throws {
        let fixture = try ConversationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let inFolder = try fixture.reader.list(folder: ConversationFixture.siteFolder, limit: 20)
        #expect(inFolder.contains("Expertise") && !inFolder.contains("Facture"))
        let byWords = try fixture.reader.list(text: "facture", limit: 20)
        #expect(byWords.contains("Facture de novembre") && !byWords.contains("Expertise"))
        #expect(try fixture.reader.list(text: "introuvable", limit: 20).contains("Aucune conversation"))
    }

    /// The user's messages and Claude's answers only: no tool, no thought, no sub-agent, no text of the system.
    @Test func aConversationIsTheUsersMessagesAndClaudesAnswers() throws {
        let fixture = try ConversationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let text = try fixture.reader.conversation("Expertise")
        for shown in ["Peux-tu refaire la page Expertise ?", "Je regarde la page.", "Le texte collé par l'utilisateur", "Refonte de la page Expertise"] {
            #expect(text.contains(shown), "\(shown)")
        }
        for hidden in ["Texte caché", "pensée", "Contenu d'un fichier", "sous-agent", "compétence", "sélection de l'éditeur", "pasted_content"] {
            #expect(!text.contains(hidden), "\(hidden)")
        }
        #expect(text.contains("Toi") || text.contains("Utilisateur"))
        #expect(text.contains("Claude"))
    }

    @Test func aSecretIsMasked() throws {
        let fixture = try ConversationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let text = try fixture.reader.conversation(String(ConversationFixture.site.prefix(8)))
        #expect(!text.contains("abcdefghijklmnopqrstuvwxyz0123456789"))
        #expect(text.contains("(secret masqué)"))
    }

    /// Long, a conversation is read by pages; the last one comes first, where the work stands.
    @Test func theLastPageComesFirst() throws {
        let fixture = try ConversationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let folder = fixture.root.appending(path: "-Users-essai-Code-long", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let lines = (1...60).map { number in
            ConversationFixture.line(["type": number % 2 == 1 ? "user" : "assistant", "cwd": "/Users/essai/Code/long", "message": [
                "role": number % 2 == 1 ? "user" : "assistant",
                "content": [["type": "text", "text": "Message numéro \(number) " + String(repeating: "texte ", count: 150)]],
            ]])
        } + [ConversationFixture.line(["type": "ai-title", "aiTitle": "Longue conversation"])]
        try ConversationFixture.write(lines, to: folder.appending(path: "5e5e5e5e-0000-4000-8000-00000000cccc.jsonl"), modified: Date())
        let last = try fixture.reader.conversation("5e5e5e5e")
        #expect(last.contains("Message numéro 60 ") && !last.contains("Message numéro 1 "))
        let pages = try #require(last.firstMatch(of: /page (\d+) sur (\d+)/))
        #expect(pages.1 == pages.2 && Int(pages.2)! > 1)
        let first = try fixture.reader.conversation("5e5e5e5e", page: 1)
        #expect(first.contains("Message numéro 1 ") && !first.contains("Message numéro 60 "))
    }

    @Test func anUnknownConversationIsSaidSo() throws {
        let fixture = try ConversationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        #expect(throws: ToolError.self) { try fixture.reader.conversation("ffffffff") }
    }
}

/// Colin reads them (20/11); what he read of a conversation counts as read of a third party: of its project when its
/// folder is the project's, else wide.
@Suite struct ColinConversationTests {
    func server(_ fixture: MailDeskFixture, conversations: ConversationFixture) throws -> MCPServer {
        let projects = ProjectDesk(projects: ProjectStore(fixture.database), meetings: MeetingStore(fixture.database), workingDirectory: nil)
        return MCPServer(reader: try Fixture().reader, desk: projects, mails: fixture.desk(),
                         agenda: AgendaDesk(database: fixture.database, root: fixture.root, projects: projects),
                         conversations: conversations.reader, profile: .colin)
    }

    func call(_ server: MCPServer, _ name: String, _ arguments: [String: Any] = [:]) throws -> (text: String, error: Bool) {
        let request: [String: Any] = ["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": name, "arguments": arguments]]
        let line = try #require(server.handle(String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)))
        let object = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let result = try #require(object["result"] as? [String: Any])
        return (((result["content"] as? [[String: Any]])?.first?["text"] as? String) ?? "", result["isError"] as? Bool == true)
    }

    @Test func colinListsAndReadsTheConversations() throws {
        let fixture = try MailDeskFixture()
        let conversations = try ConversationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root); try? FileManager.default.removeItem(at: conversations.root) }
        let server = try server(fixture, conversations: conversations)
        #expect(try call(server, "conversations").text.contains("Facture de novembre"))
        #expect(try call(server, "conversation", ["quelle": "Expertise"]).text.contains("Je regarde la page."))
    }

    @Test func aConversationOfNoProjectLocksHisDrafts() throws {
        let fixture = try MailDeskFixture()
        let conversations = try ConversationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root); try? FileManager.default.removeItem(at: conversations.root) }
        let server = try server(fixture, conversations: conversations)
        #expect(try call(server, "conversation", ["quelle": "Facture"]).error == false)
        let refused = try call(server, "brouillon", ["quel": "fil-maquette-01", "texte": "Merci, je regarde."])
        #expect(refused.error && refused.text.hasPrefix(ColinTool.lockMark))
    }

    @Test func aConversationInTheProjectsFolderKeepsHisDraftsInTheProject() throws {
        let fixture = try MailDeskFixture()
        let conversations = try ConversationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root); try? FileManager.default.removeItem(at: conversations.root) }
        var project = fixture.project
        project.codeFolder = ConversationFixture.siteFolder
        try fixture.database.writer.write { [project] db in try project.update(db) }
        let server = try server(fixture, conversations: conversations)
        #expect(try call(server, "conversation", ["quelle": "Expertise"]).error == false)
        // The mockup's thread is filed in « Site vitrine », the project of the site's folder.
        #expect(try call(server, "brouillon", ["quel": "fil-maquette-01", "texte": "Merci, je regarde."]).error == false)
    }
}
