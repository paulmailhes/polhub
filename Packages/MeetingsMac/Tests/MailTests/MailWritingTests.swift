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
        // Deleted in Gmail (the phone): the next push makes a new one.
        try await engine.discardInGmailOnly(id, gmail: gmail)
        row.updatedAt = row.updatedAt.addingTimeInterval(10)
        try store.saveDraft(row)
        let again = try await engine.push(row.id)
        #expect(again.gmailDraftID != id && again.gmailDraftID.flatMap { gmail.drafts[$0] } != nil)
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
