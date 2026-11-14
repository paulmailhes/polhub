import Domain
import Foundation
import GoogleKit
import MailFormat
import Persistence
import Testing
@testable import Mail

/// 14/11, step « Écrire »: a draft lives on the Mac, then in Gmail; only Paul's click sends it.
@Suite struct MailWritingTests {
    let account = "moi@exemple.fr"

    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var date = Date(timeIntervalSince1970: 1_794_562_920)
        var now: Date { lock.withLock { date += 61; return date } }
    }

    func setUp(flavor: AppFlavor = .prod) async throws -> (MailEngine, FakeGmail, MailStore, URL) {
        let database = try AppDatabase.inMemory()
        try CalendarStore(database).addAccount(email: account, at: Date(timeIntervalSince1970: 1_794_562_920))
        let gmail = FakeGmail(), clock = Clock()
        let root = FileManager.default.temporaryDirectory.appending(path: "ecrire-\(UUID().uuidString)", directoryHint: .isDirectory)
        let engine = MailEngine(database: database, root: root, sendFor: { _ in gmail.send }, flavor: flavor, now: { clock.now }, pause: { _ in })
        gmail.add("m1", .init(thread: "t1", labels: ["INBOX"], from: "Camille Martin <camille@exemple.fr>", references: "<a@exemple.fr>"), history: false)
        await engine.step(account)
        return (engine, gmail, MailStore(database), root)
    }

    func draft(_ store: MailStore, body: String = "Merci, je regarde.") throws -> MailDraftRow {
        let draft = MailDraftRow(account: account, mode: .reply, threadKey: MailThreadRow.key(account: account, threadID: "t1"),
                                 to: [MailAddress(name: "Camille Martin", email: "camille@exemple.fr")], subject: "Re: Maquette v2", body: body,
                                 quoteHTML: "<div class=\"gmail_quote\">cité</div>", quoteText: "> cité", inReplyTo: "<m1@exemple.fr>",
                                 references: "<a@exemple.fr> <m1@exemple.fr>", createdAt: Date(timeIntervalSince1970: 1_794_562_000))
        try store.saveDraft(draft)
        return draft
    }

    @Test func theMailboxSignsAsGmailDoes() async throws {
        let (engine, _, store, root) = try await setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        await engine.readIdentity(account)
        let cursor = try #require(try store.cursor(account: account))
        #expect(cursor.senderName == "Moi Exemple" && cursor.signature == "<b>Moi</b> · Studio Exemple")
    }

    @Test func aReplyKnowsItsThreadAndItsPeople() async throws {
        let (engine, gmail, store, root) = try await setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        gmail.add("m2", .init(thread: "t1", labels: ["INBOX"], from: "Camille Martin <camille@exemple.fr>", minutes: 3, replyTo: "equipe@exemple.fr",
                              references: "<a@exemple.fr> <m1@exemple.fr>"))
        await engine.step(account)
        let message = try #require(try store.messages(threadKey: MailThreadRow.key(account: account, threadID: "t1")).last)
        let source = try await engine.replySource(for: message)
        #expect(source.messageID == "<m2@exemple.fr>" && source.references == "<a@exemple.fr> <m1@exemple.fr>")
        #expect(source.replyTo.map(\.email) == ["equipe@exemple.fr"] && source.body == "<p>Corps de m2</p>" && source.isHTML)
        #expect(ReplyBuilder.recipients(.reply, source: source, mine: [account]).to.map(\.email) == ["equipe@exemple.fr"])
    }

    /// The first push creates Gmail's draft, in the thread; the next ones replace it; one deleted in Gmail
    /// meanwhile comes back.
    @Test func aDraftReachesGmailThenFollowsItsChanges() async throws {
        let (engine, gmail, store, root) = try await setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        await engine.readIdentity(account)
        var row = try draft(store)
        row = try await engine.push(row.id)
        let id = try #require(row.gmailDraftID)
        #expect(!row.needsPush && gmail.drafts[id]?.threadID == "t1")
        let raw = try #require(gmail.drafts[id]?.raw)
        #expect(raw.contains("From: Moi Exemple <moi@exemple.fr>") && raw.contains("To: Camille Martin <camille@exemple.fr>"))
        // The HTML travels in quoted-printable: its soft line breaks are taken out to read it.
        let unfolded = raw.replacingOccurrences(of: "=\r\n", with: "")
        #expect(raw.contains("In-Reply-To: <m1@exemple.fr>"))
        #expect(unfolded.contains("gmail_signature") && unfolded.contains("gmail_quote"))
        row.body = "Merci, c'est parfait."
        row.updatedAt = row.updatedAt.addingTimeInterval(10)
        try store.saveDraft(row)
        _ = try await engine.push(row.id)
        #expect(gmail.drafts.count == 1 && gmail.drafts[id]?.raw.contains("parfait") == true)
        #expect(gmail.calls.filter { $0.hasPrefix("PUT /upload/drafts/\(id)") }.count == 1)
    }

    /// Review of 14/11: a draft sent or deleted elsewhere (the phone) is never made again on its own; its next
    /// « Envoyer » would send it twice. Paul chooses.
    @Test func aDraftGoneFromGmailWaitsForPaul() async throws {
        let (engine, gmail, store, root) = try await setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        var row = try draft(store)
        let id = try #require(try await engine.push(row.id).gmailDraftID)
        try await engine.discardInGmailOnly(id, gmail: gmail)
        row = try #require(try store.updateDraft(row.id, at: Date().addingTimeInterval(60)) { $0.body = "Encore une ligne" })
        await #expect(throws: MailDraftRow.Conflict.absent) { try await engine.push(row.id) }
        await #expect(throws: MailDraftRow.Conflict.absent) { try await engine.send(row.id) }
        #expect(gmail.drafts.isEmpty && !gmail.calls.contains("POST /drafts/send") && gmail.calls.filter { $0 == "POST /upload/drafts" }.count == 1)
        #expect(try store.draft(row.id)?.conflict == .absent)
        // « Le garder »: Gmail gets it afresh.
        try await engine.keepMine(row.id)
        let again = try await engine.push(row.id)
        #expect(again.gmailDraftID != id && again.gmailDraftID.flatMap { gmail.drafts[$0] } != nil && again.conflict == nil)
    }

    /// Changed on the phone meanwhile: Polhub does not write over it.
    @Test func aDraftChangedInGmailIsNotWrittenOver() async throws {
        let (engine, gmail, store, root) = try await setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        let row = try draft(store)
        let id = try #require(try await engine.push(row.id).gmailDraftID)
        gmail.editInGmail(id)
        try store.updateDraft(row.id, at: Date().addingTimeInterval(60)) { $0.body = "Version du Mac" }
        await #expect(throws: MailDraftRow.Conflict.modifie) { try await engine.push(row.id) }
        #expect(gmail.drafts[id]?.raw == "modifié sur le téléphone")
        await #expect(throws: MailDraftRow.Conflict.modifie) { try await engine.send(row.id) }
        // « Garder celle du Mac »: it replaces the phone's.
        try await engine.keepMine(row.id)
        _ = try await engine.push(row.id)
        #expect(gmail.drafts[id]?.raw.contains("Version du Mac") == true && gmail.drafts.count == 1)
    }

    /// Review of 14/11: two pushes of one draft never make two Gmail drafts, and a push called off on the way
    /// still records what Gmail made.
    @Test func onePushAtATimeAndNoneCutHalfway() async throws {
        let (engine, gmail, store, root) = try await setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        let row = try draft(store)
        gmail.answerUploadsAfter(.milliseconds(80))
        async let first = engine.push(row.id)
        async let second = engine.push(row.id)
        _ = try await (first, second)
        #expect(gmail.drafts.count == 1 && gmail.calls.filter { $0 == "POST /upload/drafts" }.count == 1)
        let other = MailDraftRow(account: account, mode: .new, to: [MailAddress(email: "jules@exemple.fr")], subject: "Autre", createdAt: Date())
        try store.saveDraft(other)
        let task = Task { try await engine.push(other.id) }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()
        _ = try? await task.value
        let kept = try #require(try store.draft(other.id))
        #expect(gmail.drafts.count == 2 && kept.gmailDraftID.flatMap { gmail.drafts[$0] } != nil)
    }

    /// A new mail moved to another mailbox leaves nothing in the first one (review of 14/11).
    @Test func aNewMailMovedToAnotherMailboxLeavesTheFirst() async throws {
        let (engine, gmail, store, root) = try await setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        try CalendarStore(store.database).addAccount(email: "perso@exemple.fr", at: Date())
        let row = MailDraftRow(account: account, mode: .new, subject: "Perso", body: "à la maison", createdAt: Date())
        try store.saveDraft(row)
        let id = try #require(try await engine.push(row.id).gmailDraftID)
        try await engine.changeAccount(row.id, to: "perso@exemple.fr")
        let moved = try #require(try store.draft(row.id))
        #expect(gmail.drafts[id] == nil && gmail.calls.contains("DELETE /drafts/\(id)"))
        #expect(moved.account == "perso@exemple.fr" && moved.gmailDraftID == nil && moved.pushedAt == nil)
    }

    /// Rows written by hand (a tricked agent) never reach a file outside the draft's folder.
    @Test func aDraftNeverReachesOutsideItsFolder() async throws {
        let (engine, _, store, root) = try await setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(engine.files.draftFolder(id: "../..").deletingLastPathComponent() == engine.files.root.appending(path: "brouillons", directoryHint: .isDirectory))
        var row = try draft(store)
        row.files = [MailDraftFile(filename: "../../../secret.txt", mimeType: "text/plain", size: 3)]
        try store.saveDraft(row)
        await #expect(throws: (any Error).self) { try await engine.outgoing(row) }
    }

    @Test func sendingGivesGmailTheLatestVersionThenSendsIt() async throws {
        let (engine, gmail, store, root) = try await setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        let row = try draft(store, body: "Version finale")
        try await engine.send(row.id)
        #expect(gmail.calls.contains("POST /upload/drafts") && gmail.calls.contains("POST /drafts/send"))
        #expect(try gmail.drafts.isEmpty && store.draft(row.id) == nil)
        // The sent message comes back through the history, in its thread.
        await engine.step(account)
        #expect(try store.sentThreads().map(\.threadID) == ["t1"])
    }

    @Test func aDraftWithoutRecipientIsKeptButNeverSent() async throws {
        let (engine, gmail, store, root) = try await setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        var row = MailDraftRow(account: account, mode: .new, subject: "Idée", body: "à envoyer plus tard", createdAt: Date())
        row.to = [MailAddress(email: "pas-encore-fini@")]
        try store.saveDraft(row)
        let pushed = try await engine.push(row.id)
        #expect(pushed.gmailDraftID != nil && gmail.drafts.first?.value.raw.contains("To:") == false)
        await #expect(throws: MIMEBuilder.Failure.badAddress("pas-encore-fini@")) { try await engine.send(row.id) }
        #expect(!gmail.calls.contains("POST /drafts/send"))
    }

    @Test func discardingDeletesTheDraftHereAndInGmail() async throws {
        let (engine, gmail, store, root) = try await setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        let row = try draft(store)
        let pushed = try await engine.push(row.id)
        try await engine.discard(row.id)
        #expect(try gmail.drafts.isEmpty && store.draft(row.id) == nil)
        #expect(pushed.gmailDraftID != nil)
    }

    /// The development build only reads real mailboxes: its drafts stay on the Mac.
    @Test func theDevelopmentBuildNeitherPushesNorSends() async throws {
        let (engine, gmail, store, root) = try await setUp(flavor: .dev)
        defer { try? FileManager.default.removeItem(at: root) }
        let row = try draft(store)
        await #expect(throws: GoogleError.readOnlyBuild) { try await engine.push(row.id) }
        await #expect(throws: GoogleError.readOnlyBuild) { try await engine.send(row.id) }
        #expect(gmail.drafts.isEmpty && !gmail.calls.contains { $0.hasPrefix("POST") || $0.hasPrefix("PUT") })
    }

    /// Gmail's draft with a link: its HTML stays whole, under what Paul adds; taken up twice, one draft.
    @Test func aGmailDraftWithLinksKeepsItsHTML() async throws {
        let (engine, gmail, store, root) = try await setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        gmail.add("d2", .init(thread: "t9", labels: ["DRAFT"], from: "Moi <moi@exemple.fr>", minutes: 5, to: "Camille Martin <camille@exemple.fr>",
                              body: #"<div>Voir <a href="https://exemple.fr/devis">le devis</a></div>"#))
        gmail.addGmailDraft(id: "r-lien", messageID: "d2", thread: "t9")
        await engine.step(account)
        let message = try #require(try store.gmailOnlyDrafts().first)
        let row = try await engine.resume(gmailDraft: message)
        #expect(row.body.isEmpty)
        #expect(row.quoteHTML?.contains("https://exemple.fr/devis") == true)
        #expect(row.quoteText?.contains("le devis") == true)
        let twice = try await engine.resume(gmailDraft: message)
        #expect(try twice.id == row.id && store.drafts().count == 1)
    }

    @Test func aDraftWrittenInGmailIsTakenUp() async throws {
        let (engine, gmail, store, root) = try await setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        gmail.add("d1", .init(thread: "t1", labels: ["DRAFT"], from: "Moi <moi@exemple.fr>", minutes: 5, to: "Camille Martin <camille@exemple.fr>"))
        gmail.addGmailDraft(id: "r-tel", messageID: "d1", thread: "t1")
        await engine.step(account)
        let message = try #require(try store.gmailOnlyDrafts().first)
        let row = try await engine.resume(gmailDraft: message)
        #expect(row.gmailDraftID == "r-tel" && row.origin == .gmail && row.mode == .reply && row.body == "Corps de d1")
        #expect(row.to.map(\.email) == ["camille@exemple.fr"] && !row.needsPush)
        #expect(try store.gmailOnlyDrafts().isEmpty)
    }

    /// Step « Agents »: what an agent drops becomes a draft marked as his, its people worked out by Polhub
    /// from the thread, never by the agent; nothing reaches Gmail and nothing leaves on its own.
    @Test func anAgentsDropBecomesADraftAndNeverLeavesOnItsOwn() async throws {
        let (engine, gmail, store, root) = try await setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        try CalendarStore(store.database).setGrantedScopes(email: account, scopes: "openid https://www.googleapis.com/auth/gmail.modify")
        let thread = MailThreadRow.key(account: account, threadID: "t1")
        try store.drop(MailAgentDraftRow(mode: .reply, account: account, threadKey: thread, to: [MailAddress(email: "pirate@exemple.org")],
                                         subject: "Autre chose", body: "Merci, je regarde.", createdAt: Date()))
        try store.drop(MailAgentDraftRow(mode: .new, account: account, to: [MailAddress(email: "nina@exemple.net")], subject: "Devis", body: "Bonjour", createdAt: Date()))
        try store.drop(MailAgentDraftRow(mode: .new, account: "pas-une-boite@exemple.fr", to: [MailAddress(email: "nina@exemple.net")], subject: "x", body: "y",
                                         createdAt: Date()))
        let adopted = await engine.adoptAgentDrafts()
        #expect(adopted.count == 2)
        #expect(try store.agentDrafts().isEmpty)
        let reply = try #require(adopted.first)
        #expect(reply.origin == .agent && reply.mode == .reply && reply.threadKey == thread)
        #expect(reply.to.map(\.email) == ["camille@exemple.fr"] && reply.subject == "Re: Maquette v2" && reply.quoteHTML != nil && reply.gmailDraftID == nil)
        #expect(adopted.last?.to.map(\.email) == ["nina@exemple.net"] && adopted.last?.origin == .agent)
        await engine.step(account)
        #expect(!gmail.calls.contains { $0.hasPrefix("POST") || $0.hasPrefix("PUT") })
        #expect(try store.drafts().count == 2)
    }

    /// Second review of 14/11: two passes at once adopt a drop once and ask Gmail once; the text loses its
    /// invisible characters a second time.
    @Test func oneAdoptionAtATime() async throws {
        let (engine, gmail, store, root) = try await setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        try CalendarStore(store.database).setGrantedScopes(email: account, scopes: "openid https://www.googleapis.com/auth/gmail.modify")
        try store.drop(MailAgentDraftRow(mode: .reply, account: account, threadKey: MailThreadRow.key(account: account, threadID: "t1"),
                                         body: "Merci\u{E0041}", createdAt: Date()))
        let before = gmail.calls.count
        async let first = engine.adoptAgentDrafts()
        async let second = engine.adoptAgentDrafts()
        let (a, b) = await (first, second)
        let drafts = try store.drafts()
        #expect(a.count + b.count == 1 && drafts.count == 1)
        #expect(gmail.calls.dropFirst(before).filter { $0.contains("/messages/") }.count == 1)
        #expect(try store.drafts().first?.body == "Merci")
    }

    @Test func filesJoinedToADraftLeaveWithIt() async throws {
        let (engine, gmail, store, root) = try await setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        var row = try draft(store)
        let folder = engine.files.draftFolder(row)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("%PDF-1.4 devis".utf8).write(to: folder.appending(path: "devis.pdf"))
        row.files = [MailDraftFile(filename: "devis.pdf", mimeType: "application/pdf", size: 14)]
        try store.saveDraft(row)
        let pushed = try await engine.push(row.id)
        let raw = try #require(pushed.gmailDraftID.flatMap { gmail.drafts[$0]?.raw })
        #expect(raw.contains("filename*=UTF-8''devis.pdf") && raw.contains(Data("%PDF-1.4 devis".utf8).base64EncodedString()))
        try await engine.send(row.id)
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
    }
}

extension MailEngine {
    /// For the tests: the draft disappears in Gmail only, as when Paul deletes it on his phone.
    func discardInGmailOnly(_ gmailDraftID: String, gmail: FakeGmail) async throws {
        _ = try await gmail.send { GmailAPI.draftDeleteRequest(accessToken: $0, draftID: gmailDraftID) }
    }
}

/// Review of 14/11: what Paul joins is a file, under a name of its own.
@Suite struct JoiningFilesTests {
    @Test func twoFilesOfOneNameKeepTheirOwn() {
        #expect(AttachmentSafety.uniqueName("devis.pdf", taken: []) == "devis.pdf")
        #expect(AttachmentSafety.uniqueName("devis.pdf", taken: ["devis.pdf"]) == "devis 2.pdf")
        #expect(AttachmentSafety.uniqueName("", taken: ["piece-jointe", "piece-jointe 2"]) == "piece-jointe 3")
    }

    @Test func aFolderIsRefusedAndALinkGivesItsFile() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "joindre-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appending(path: "Projet.app/Contents"), withIntermediateDirectories: true)
        try Data("devis".utf8).write(to: folder.appending(path: "devis.txt"))
        try FileManager.default.createSymbolicLink(at: folder.appending(path: "lien.txt"), withDestinationURL: folder.appending(path: "devis.txt"))
        #expect(throws: AttachmentSafety.Refusal.folder(folder.lastPathComponent)) { try AttachmentSafety.joinable(folder) }
        #expect(throws: AttachmentSafety.Refusal.folder("Projet.app")) { try AttachmentSafety.joinable(folder.appending(path: "Projet.app")) }
        let linked = try AttachmentSafety.joinable(folder.appending(path: "lien.txt"))
        #expect(linked.url.lastPathComponent == "devis.txt" && linked.size == 5)
    }
}
