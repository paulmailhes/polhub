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
        // What was left out is said on the draft, never skipped in silence (review of 16/11).
        #expect(draft.lastError?.contains("« absent.pdf »") == true && draft.lastError?.contains("« ../../secret.txt »") == true)
        #expect(draft.lastError?.contains("« plan.png »") == false)
        // A reply whose thread is gone is let go, with its files.
        let orphan = MailAgentDraftRow(mode: .reply, account: account, threadKey: MailThreadRow.key(account: account, threadID: "parti"), body: "x",
                                       createdAt: Date(), files: [MailDraftFile(filename: "a.txt", mimeType: "text/plain", size: 1)])
        try stage(["a.txt": "a"], for: orphan, in: engine)
        try store.drop(orphan)
        #expect(await engine.adoptAgentDrafts().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: engine.files.agentFolder(id: orphan.id).path(percentEncoded: false)))
    }

    /// The agents' files wait for the app in their own folder: the clean-up of the mailboxes' folders leaves them, and
    /// only the folders of drops gone for an hour go (review of 16/11).
    @Test func theAgentsFilesWaitingAreKept() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "agents-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = MailFiles(root: root)
        let pending = UUID().uuidString, recent = UUID().uuidString, old = UUID().uuidString
        func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }
        for id in [pending, recent, old] {
            try FileManager.default.createDirectory(at: files.agentFolder(id: id), withIntermediateDirectories: true)
            try Data("%PDF-1.4".utf8).write(to: files.agentFolder(id: id).appending(path: "devis.pdf"))
        }
        try FileManager.default.createDirectory(at: files.folder(account: "parti@exemple.fr"), withIntermediateDirectories: true)
        files.keepOnly(accounts: [account], drafts: [])
        for id in [pending, recent, old] { #expect(exists(files.agentFolder(id: id).appending(path: "devis.pdf"))) }
        #expect(!exists(files.folder(account: "parti@exemple.fr")))
        let now = Date()
        for id in [pending, old] {
            try FileManager.default.setAttributes([.creationDate: now.addingTimeInterval(-7_200)], ofItemAtPath: files.agentFolder(id: id).path(percentEncoded: false))
        }
        files.forgetAgentFolders(keeping: [pending], now: now)
        #expect(exists(files.agentFolder(id: pending)) && exists(files.agentFolder(id: recent)) && !exists(files.agentFolder(id: old)))
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

/// Paul, 17/11: « il me le recrée à chaque fois ». An agent changes the draft it prepared instead of making another:
/// the draft keeps its place, its people, its quote and its Gmail copy; deleted, it goes. Paul's own never changes.
@Suite struct AgentDraftChangeTests {
    let base = AgentDraftTests()
    var account: String { base.account }
    var thread: String { base.thread }

    @Test func anAgentsChangeAppliesToItsDraft() async throws {
        let (engine, _, store, root) = try await base.setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        let drop = MailAgentDraftRow(mode: .reply, account: account, threadKey: thread, body: "Merci.", createdAt: Date())
        try store.drop(drop)
        let draft = try #require(await engine.adoptAgentDrafts().first)
        // The draft takes the drop's identifier: the agent was given it.
        #expect(draft.id == drop.id && !draft.retouchedByPaul)
        try store.drop(MailAgentDraftRow(mode: .reply, account: account, threadKey: thread, body: "**Merci** Camille, je valide.", createdAt: Date(),
                                         format: .markdown, replaces: draft.id))
        let pass = await engine.takeAgentDrafts()
        #expect(pass.adopted.isEmpty && pass.changed.map(\.id) == [draft.id])
        let stored = try #require(try store.draft(draft.id))
        #expect(stored.body == "Merci Camille, je valide." && stored.bodyHTML?.contains("<b>Merci</b>") == true)
        #expect(stored.quoteHTML == draft.quoteHTML && stored.to == draft.to && stored.subject == draft.subject && stored.createdAt == draft.createdAt)
        // The agent's own version: not a retouch of Paul's.
        #expect(stored.origin == .agent && !stored.retouchedByPaul)
        #expect(try store.agentDrafts().isEmpty)
        // Deleted: gone.
        try store.drop(MailAgentDraftRow(mode: .reply, account: account, threadKey: thread, body: "", createdAt: Date(), replaces: draft.id, discard: true))
        let gone = await engine.takeAgentDrafts()
        #expect(gone.discarded.map(\.id) == [draft.id])
        #expect(try store.draft(draft.id) == nil && store.agentDrafts().isEmpty)
    }

    /// A drop an agent changes while the app makes it a draft: the app waits for the next pass, the change is kept.
    @Test func aDropChangedWhileTakenWaitsForTheNextPass() throws {
        let database = try AppDatabase.inMemory()
        try CalendarStore(database).addAccount(email: account, at: Date(timeIntervalSince1970: 1_794_562_920))
        let store = MailStore(database)
        let drop = MailAgentDraftRow(mode: .new, account: account, to: [MailAddress(email: "nina@exemple.net")], subject: "Devis", body: "Bonjour",
                                     createdAt: Date(timeIntervalSince1970: 1_794_562_920))
        try store.drop(drop)
        let read = try #require(try store.agentDrafts().first)
        var changed = read
        changed.body = "Bonjour Nina"
        #expect(try store.updateDrop(changed))
        let draft = MailDraftRow(id: read.id, account: account, mode: .new, body: read.body, origin: .agent, createdAt: read.createdAt)
        #expect(try !store.adopt(read.id, as: draft, expecting: read))
        #expect(try store.draft(read.id) == nil && store.agentDrafts().first?.body == "Bonjour Nina")
        #expect(try store.adopt(read.id, as: draft, expecting: try #require(try store.agentDrafts().first)))
    }

    /// A draft Gmail holds (Paul opened it): the agent's version never goes there before Paul has seen it; Gmail's
    /// copy goes.
    @Test func anAgentsVersionStaysOutOfGmail() async throws {
        let (engine, gmail, store, root) = try await MailWritingTests().setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        try CalendarStore(store.database).setGrantedScopes(email: account, scopes: "openid https://www.googleapis.com/auth/gmail.modify")
        try store.drop(MailAgentDraftRow(mode: .new, account: account, to: [MailAddress(email: "nina@exemple.net")], subject: "Devis", body: "Bonjour",
                                         createdAt: Date()))
        let draft = try #require(await engine.adoptAgentDrafts().first)
        let gmailID = try #require(try await engine.push(draft.id).gmailDraftID)
        try store.drop(MailAgentDraftRow(mode: .new, account: account, body: "Bonjour Nina", createdAt: Date(), replaces: draft.id,
                                         basedOn: try store.draft(draft.id)?.updatedAt))
        #expect(await engine.takeAgentDrafts().changed.count == 1)
        let stored = try #require(try store.draft(draft.id))
        #expect(stored.body == "Bonjour Nina" && stored.gmailDraftID == nil && stored.pushedAt == nil)
        #expect(gmail.drafts[gmailID] == nil && gmail.calls.contains("DELETE /drafts/\(gmailID)"))
    }

    /// A new mail: only what the agent gives changes; the rest stays as it is, files included.
    @Test func aNewMailChangesOnlyWhatIsGiven() async throws {
        let (engine, _, store, root) = try await base.setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        let nina = MailAddress(name: "Nina", email: "nina@exemple.net")
        try store.drop(MailAgentDraftRow(mode: .new, account: account, to: [nina], subject: "Devis", body: "Bonjour Nina", createdAt: Date()))
        let draft = try #require(await engine.adoptAgentDrafts().first)
        try store.drop(MailAgentDraftRow(mode: .new, account: account, subject: "Devis du site", body: "", createdAt: Date(), replaces: draft.id))
        #expect(await engine.takeAgentDrafts().changed.count == 1)
        let stored = try #require(try store.draft(draft.id))
        #expect(stored.subject == "Devis du site" && stored.body == "Bonjour Nina" && stored.to == [nina])
        let jules = MailAddress(email: "jules@exemple.net")
        try store.drop(MailAgentDraftRow(mode: .new, account: account, to: [jules], cc: [nina], body: "Bonjour Jules", createdAt: Date(), replaces: draft.id))
        _ = await engine.takeAgentDrafts()
        let again = try #require(try store.draft(draft.id))
        #expect(again.to == [jules] && again.cc == [nina] && again.subject == "Devis du site" && again.body == "Bonjour Jules" && again.bodyHTML == nil)
    }

    /// Paul's own draft, or one leaving now: refused, untouched, and said.
    @Test func paulsOwnDraftOrOneLeavingIsNeverChanged() async throws {
        let (engine, _, store, root) = try await base.setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        let mine = MailDraftRow(account: account, mode: .new, subject: "À moi", body: "Mon texte", createdAt: Date())
        try store.saveDraft(mine)
        try store.drop(MailAgentDraftRow(mode: .new, account: account, body: "Remplacé", createdAt: Date(), replaces: mine.id))
        try store.drop(MailAgentDraftRow(mode: .new, account: account, body: "", createdAt: Date(), replaces: mine.id, discard: true))
        let refused = await engine.takeAgentDrafts()
        #expect(refused.refused.map(\.id) == [mine.id, mine.id] && refused.changed.isEmpty && refused.discarded.isEmpty)
        #expect(refused.refused.allSatisfy { $0.reason == "tu l'as écrit toi-même" })
        #expect(try store.draft(mine.id)?.body == "Mon texte" && store.agentDrafts().isEmpty)
        try store.drop(MailAgentDraftRow(mode: .new, account: account, to: [MailAddress(email: "nina@exemple.net")], subject: "Devis", body: "Bonjour", createdAt: Date()))
        let leaving = try #require(await engine.adoptAgentDrafts().first)
        try store.drop(MailAgentDraftRow(mode: .new, account: account, body: "Trop tard", createdAt: Date(), replaces: leaving.id))
        let busy = await engine.takeAgentDrafts(busy: { $0 == leaving.id })
        #expect(busy.refused.map(\.id) == [leaving.id] && busy.refused.first?.reason == "il est en train de partir")
        #expect(try store.draft(leaving.id)?.body == "Bonjour")
        // Retouched by Paul since the agent read it: refused; read after the retouch: applied.
        let read = try #require(try store.draft(leaving.id))
        let retouched = try #require(try store.updateDraft(leaving.id, at: read.updatedAt.addingTimeInterval(60)) { $0.body = "Bonjour, de Paul" })
        #expect(retouched.retouchedByPaul)
        try store.drop(MailAgentDraftRow(mode: .new, account: account, body: "De mémoire", createdAt: Date(), replaces: leaving.id, basedOn: read.updatedAt))
        let stale = await engine.takeAgentDrafts()
        #expect(try stale.refused.first?.reason == "tu l'as retouché depuis que l'agent l'a lu" && store.draft(leaving.id)?.body == "Bonjour, de Paul")
        try store.drop(MailAgentDraftRow(mode: .new, account: account, body: "Bonjour, de Paul, et la date", createdAt: Date(), replaces: leaving.id,
                                         basedOn: retouched.updatedAt))
        #expect(await engine.takeAgentDrafts().changed.count == 1)
        #expect(try store.draft(leaving.id)?.body == "Bonjour, de Paul, et la date")
        // A draft gone meanwhile: the request goes, nothing is made.
        try store.drop(MailAgentDraftRow(mode: .new, account: account, body: "x", createdAt: Date(), replaces: "parti"))
        let none = await engine.takeAgentDrafts()
        #expect(try none.changed.isEmpty && none.adopted.isEmpty && store.agentDrafts().isEmpty)
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
