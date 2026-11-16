import Domain
import Foundation
import GoogleKit
import MailFormat
import Persistence
import Testing
@testable import Mail

/// Paul, 16/11: an agent joins files to a draft and formats it (bold, lists, links). The app makes the drop a draft
/// with its files and its HTML, as Paul's own; nothing leaves on its own.
@Suite struct AgentDraftTests {
    let account = "moi@exemple.fr"

    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var date = Date(timeIntervalSince1970: 1_794_562_920)
        var now: Date { lock.withLock { date += 61; return date } }
    }

    func setUp() async throws -> (MailEngine, FakeGmail, MailStore, URL) {
        let database = try AppDatabase.inMemory()
        try CalendarStore(database).addAccount(email: account, at: Date(timeIntervalSince1970: 1_794_562_920))
        try CalendarStore(database).setGrantedScopes(email: account, scopes: "openid https://www.googleapis.com/auth/gmail.modify")
        let gmail = FakeGmail(), clock = Clock()
        let root = FileManager.default.temporaryDirectory.appending(path: "agents-\(UUID().uuidString)", directoryHint: .isDirectory)
        let engine = MailEngine(database: database, root: root, sendFor: { _ in gmail.send }, now: { clock.now }, pause: { _ in })
        gmail.add("m1", .init(thread: "t1", labels: ["INBOX"], from: "Camille Martin <camille@exemple.fr>", references: "<a@exemple.fr>"), history: false)
        await engine.step(account)
        return (engine, gmail, MailStore(database), root)
    }

    var thread: String { MailThreadRow.key(account: account, threadID: "t1") }

    /// What the helper leaves: the files in the drop's own folder, their names on the row.
    func stage(_ files: [String: String], for drop: MailAgentDraftRow, in engine: MailEngine) throws {
        let folder = engine.files.agentFolder(id: drop.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, text) in files { try Data(text.utf8).write(to: folder.appending(path: name)) }
    }

    @Test func anAgentsFilesMoveIntoItsDraftAndLeaveWithIt() async throws {
        let (engine, gmail, store, root) = try await setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        let devis = MailDraftFile(filename: "devis.pdf", mimeType: "application/pdf", size: 14)
        let drop = MailAgentDraftRow(mode: .reply, account: account, threadKey: thread, body: "Voici le devis.", createdAt: Date(), files: [devis])
        try stage(["devis.pdf": "%PDF-1.4 devis"], for: drop, in: engine)
        try store.drop(drop)
        let draft = try #require(await engine.adoptAgentDrafts().first)
        #expect(draft.files == [devis] && draft.origin == .agent)
        #expect(try Data(contentsOf: try engine.files.draftFile(devis, of: draft)) == Data("%PDF-1.4 devis".utf8))
        #expect(!FileManager.default.fileExists(atPath: engine.files.agentFolder(id: drop.id).path(percentEncoded: false)))
        #expect(try store.draft(draft.id)?.files == [devis])
        // It leaves as a file Paul joined, once Paul sends it; nothing reached Gmail before.
        #expect(!gmail.calls.contains { $0.hasPrefix("POST") || $0.hasPrefix("PUT") })
        let mail = try await engine.outgoing(draft)
        #expect(mail.files.map(\.filename) == ["devis.pdf"] && mail.files.first?.data == Data("%PDF-1.4 devis".utf8))
    }

    /// A row written by hand (a tricked agent with the base in hand) never takes a file from outside its folder; a file
    /// gone meanwhile is left out; a drop let go takes its folder with it.
    @Test func aDropNeverTakesAFileFromOutsideItsFolder() async throws {
        let (engine, _, store, root) = try await setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        let secret = root.appending(path: "secret.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: secret)
        let drop = MailAgentDraftRow(mode: .new, account: account, to: [MailAddress(email: "nina@exemple.net")], subject: "Devis", body: "Bonjour",
                                     createdAt: Date(), files: [MailDraftFile(filename: "../../secret.txt", mimeType: "text/plain", size: 6),
                                                                MailDraftFile(filename: "absent.pdf", mimeType: "application/pdf", size: 3),
                                                                MailDraftFile(filename: "plan.png", mimeType: "image/png", size: 3)])
        try stage(["plan.png": "png"], for: drop, in: engine)
        try store.drop(drop)
        let draft = try #require(await engine.adoptAgentDrafts().first)
        #expect(draft.files.map(\.filename) == ["plan.png"])
        #expect(FileManager.default.fileExists(atPath: secret.path(percentEncoded: false)))
        // A reply whose thread is gone is let go, with its files.
        let orphan = MailAgentDraftRow(mode: .reply, account: account, threadKey: MailThreadRow.key(account: account, threadID: "parti"), body: "x",
                                       createdAt: Date(), files: [MailDraftFile(filename: "a.txt", mimeType: "text/plain", size: 1)])
        try stage(["a.txt": "a"], for: orphan, in: engine)
        try store.drop(orphan)
        #expect(await engine.adoptAgentDrafts().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: engine.files.agentFolder(id: orphan.id).path(percentEncoded: false)))
    }

    /// The agent's markdown becomes simple HTML, everything it wrote escaped: no tag of its own, no link but http(s)
    /// and mailto. It leaves above the quote of a reply; the text part carries its plain version.
    @Test func anAgentsFormattedReplyLeavesFormattedAboveItsQuote() async throws {
        let (engine, _, store, root) = try await setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        let markdown = """
        **Bonjour** Camille,

        Voici *les points* :
        - le devis, [en ligne](https://exemple.fr/devis?a=1&b=2)
        - <script>alert(1)</script> et [un piège](javascript:alert(1))

        1. relire
        2. signer
        """
        try store.drop(MailAgentDraftRow(mode: .reply, account: account, threadKey: thread, body: markdown, createdAt: Date(), format: .markdown))
        let draft = try #require(await engine.adoptAgentDrafts().first)
        let html = try #require(draft.bodyHTML)
        #expect(html.contains("<p><b>Bonjour</b> Camille,</p>") && html.contains("<i>les points</i>"))
        #expect(html.contains(#"<ul><li>le devis, <a href="https://exemple.fr/devis?a=1&amp;b=2">en ligne</a></li>"#))
        #expect(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;") && !html.contains("<script"))
        #expect(!html.contains("javascript") && html.contains("et un piège</li></ul>"))
        #expect(html.contains("<ol><li>relire</li><li>signer</li></ol>"))
        // The plain version: what the text part carries, and what « Repasser en texte simple » gives back.
        #expect(draft.body.hasPrefix("Bonjour Camille,\n\nVoici les points :\n- le devis, en ligne (https://exemple.fr/devis?a=1&b=2)"))
        #expect(!draft.body.contains("**") && !draft.body.contains("javascript"))
        let mail = try await engine.outgoing(draft)
        let body = try #require(mail.html.range(of: html)), quote = try #require(mail.html.range(of: "gmail_quote"))
        #expect(body.upperBound <= quote.lowerBound)
        #expect(mail.text.hasPrefix(draft.body) && mail.text.contains("> Corps de m1"))
        // Without format, a drop stays plain text: no HTML of its own.
        try store.drop(MailAgentDraftRow(mode: .reply, account: account, threadKey: thread, body: "**pas du gras**", createdAt: Date()))
        let plain = try #require(await engine.adoptAgentDrafts().first)
        #expect(plain.bodyHTML == nil && plain.body == "**pas du gras**")
    }
}

/// The little markdown of the agents (16/11), alone.
@Suite struct MailMarkdownTests {
    @Test func onlyWhatTheBriefAllowsBecomesHTML() {
        // No heading, no image: a title stays text, an image its link.
        #expect(MailMarkdown.html("# Titre\n![image](https://exemple.fr/a.png)") == "<p># Titre<br><a href=\"https://exemple.fr/a.png\">image</a></p>")
        #expect(MailMarkdown.html("Écris à [Camille](mailto:camille@exemple.fr) ou [là](HTTPS://exemple.fr)")
            == #"<p>Écris à <a href="mailto:camille@exemple.fr">Camille</a> ou <a href="HTTPS://exemple.fr">là</a></p>"#)
        #expect(MailMarkdown.html(#"[x](https://exemple.fr/"onmouseover="alert(1))"#).contains("&quot;onmouseover=&quot;"))
        #expect(MailMarkdown.html("[données](data:text/html,<b>x</b>)") == "<p>données</p>")
        #expect(MailMarkdown.html("2*3*4 et **gras**").hasPrefix("<p>2*3*4 et <b>gras</b>"))
        #expect(MailMarkdown.html("3. trois\n4. quatre") == #"<ol start="3"><li>trois</li><li>quatre</li></ol>"#)
        #expect(MailMarkdown.html("- un\n\n- deux") == "<ul><li>un</li><li>deux</li></ul>")
        #expect(MailMarkdown.html("Le site : https://exemple.fr/page.") == #"<p>Le site : <a href="https://exemple.fr/page">https://exemple.fr/page</a>.</p>"#)
        #expect(MailMarkdown.plain("**Bonjour**\n\n- [le site](https://exemple.fr)\n- [https://exemple.fr](https://exemple.fr)")
            == "Bonjour\n\n- le site (https://exemple.fr)\n- https://exemple.fr")
    }
}
