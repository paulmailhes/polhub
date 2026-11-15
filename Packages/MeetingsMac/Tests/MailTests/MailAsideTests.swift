import Domain
import Foundation
import GoogleKit
import Persistence
import Testing
@testable import Mail
import MailFormat

/// Wave B (15/11): « Corbeille » and « Spam ». Gmail's own folders are read live, as headers only; a spam's body is
/// read each time and never kept; a thread brought back is read whole and kept like any other.
@Suite struct MailAsideTests {
    let account = "moi@exemple.fr"

    func setUp(flavor: AppFlavor = .prod) throws -> (MailEngine, FakeGmail, MailStore, URL) {
        let database = try AppDatabase.inMemory()
        try CalendarStore(database).addAccount(email: account, at: Date(timeIntervalSince1970: 1_794_562_920))
        let gmail = FakeGmail(), clock = MailEngineTests.Clock()
        let root = FileManager.default.temporaryDirectory.appending(path: "a-part-\(UUID().uuidString)", directoryHint: .isDirectory)
        let engine = MailEngine(database: database, root: root, sendFor: { _ in gmail.send }, flavor: flavor, now: { clock.now }, pause: { _ in })
        return (engine, gmail, MailStore(database), root)
    }

    func key(_ thread: String) -> String { MailThreadRow.key(account: account, threadID: thread) }
    func messageKey(_ id: String) -> String { MailMessageRow.key(account: account, messageID: id) }

    /// What the folder of the Mac holds for a mailbox: the bodies and files kept.
    func kept(_ engine: MailEngine) -> [String] {
        let folder = engine.files.folder(account: account)
        return ((try? FileManager.default.subpathsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }

    /// The first reading never sees the spam nor the trash; opening their folder asks Gmail for them, headers only,
    /// 50 at most per mailbox, and keeps no body. A second look does not read them again.
    @Test func theTrashAndTheSpamComeFromGmailAsHeadersOnly() async throws {
        let (engine, gmail, store, root) = try setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        gmail.add("m1", .init(thread: "t1", labels: ["INBOX"]), history: false)
        gmail.add("s1", .init(thread: "ts1", labels: ["SPAM", "UNREAD"], from: "Gagnant <gagnant@loterie.exemple>", subject: "Vous avez gagné", minutes: 3), history: false)
        gmail.add("s2", .init(thread: "ts2", labels: ["SPAM"], from: "Banque <alerte@banque-fausse.exemple>", subject: "Compte bloqué", minutes: 5), history: false)
        gmail.add("c1", .init(thread: "tc1", labels: ["TRASH"], subject: "Ancien devis", minutes: 1), history: false)
        await engine.step(account)
        #expect(Set(try store.knownMessageIDs(account: account)) == ["m1"])

        let keys = try await engine.aside("SPAM", accounts: [account])
        #expect(Set(keys) == [key("ts1"), key("ts2")])
        let listing = try #require(gmail.queries.last { $0.hasPrefix("GET /messages?") })
        #expect(listing.contains("labelIds=SPAM") && listing.contains("includeSpamTrash=true") && listing.contains("maxResults=50"))
        // Headers only: never `format=full`, and no body on the Mac.
        #expect(!gmail.calls.contains { $0.hasSuffix(" full") && ($0.contains("/s1") || $0.contains("/s2")) })
        #expect(gmail.queries.contains { $0.hasPrefix("GET /messages/s1?format=metadata") && $0.contains("metadataHeaders=From") })
        #expect(kept(engine) == ["m1.html"])
        let spam = try store.asideThreads(label: "SPAM")
        #expect(spam.map(\.threadID) == ["ts2", "ts1"] && spam.allSatisfy(\.hidden))
        #expect(spam.first?.subject == "Compte bloqué" && spam.first?.senders.first?.email == "alerte@banque-fausse.exemple")
        let row = try #require(try store.message(messageKey("s1")))
        #expect(!row.hasBody && row.attachments.isEmpty && row.labels.contains("SPAM"))
        // Nothing else shows them.
        #expect(try store.inbox().map(\.threadID) == ["t1"] && store.readableThreads().map(\.threadID) == ["t1"])
        // Known already, with the label: not read again.
        let reads = gmail.calls.filter { $0.hasSuffix(" metadata") }.count
        _ = try await engine.aside("SPAM", accounts: [account])
        #expect(gmail.calls.filter { $0.hasSuffix(" metadata") }.count == reads)
        _ = try await engine.aside("TRASH", accounts: [account])
        #expect(try store.asideThreads(label: "TRASH").map(\.threadID) == ["tc1"])
        // Only Gmail's two folders.
        #expect(try await engine.aside("INBOX", accounts: [account]).isEmpty)
    }

    /// A spam's body comes from Gmail each time it opens and never goes to disk; its files never open. A mail
    /// known before it went to the spam (on the phone) loses the body and the files the Mac kept.
    @Test func aSpamIsReadFromGmailEachTimeAndNeverKept() async throws {
        let (engine, gmail, store, root) = try setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        gmail.add("m1", .init(thread: "t1", labels: ["INBOX"]), history: false)
        gmail.add("s1", .init(thread: "ts1", labels: ["SPAM"], subject: "Vous avez gagné", body: "<p>Cliquez ici</p>"), history: false)
        await engine.step(account)
        _ = try await engine.aside("SPAM", accounts: [account])
        let spam = try #require(try store.message(messageKey("s1")))
        #expect(try await engine.body(of: spam) == "<p>Cliquez ici</p>")
        // Listed by its headers, it says it is HTML once read.
        #expect(try await engine.read(spam) == ("<p>Cliquez ici</p>", true))
        #expect(gmail.calls.filter { $0 == "GET /messages/s1 full" }.count == 2)
        #expect(try kept(engine) == ["m1.html"] && store.message(messageKey("s1"))?.hasBody == false)
        let file = MailAttachment(partID: "2", filename: "facture.pdf", mimeType: "application/pdf", size: 10, attachmentID: "a", contentID: nil, inline: false)
        await #expect(throws: GoogleError.self) { try await engine.file(file, of: spam) }

        // The phone puts m1 in the spam: its body leaves the Mac at the next pass.
        let known = try #require(try store.message(messageKey("m1")))
        try FileManager.default.createDirectory(at: engine.files.attachment(file, of: known).deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("pdf".utf8).write(to: engine.files.attachment(file, of: known))
        gmail.change("m1", labels: ["SPAM"])
        await engine.step(account)
        #expect(kept(engine).isEmpty)
        #expect(try store.message(messageKey("m1"))?.hasBody == false && store.inbox().isEmpty)
        #expect(try store.asideThreads(label: "SPAM").map(\.threadID).sorted() == ["t1", "ts1"])
    }

    /// « Restaurer » and « Pas un spam »: once Gmail took the gesture, the mail listed by its headers is read whole
    /// and kept like any inbox mail, body and files.
    @Test func aThreadBroughtBackIsReadWhole() async throws {
        let (engine, gmail, store, root) = try setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        gmail.add("m1", .init(thread: "t1", labels: ["INBOX"]), history: false)
        gmail.add("c1", .init(thread: "tc1", labels: ["TRASH"], subject: "Devis signé", minutes: 2), history: false)
        gmail.add("s1", .init(thread: "ts1", labels: ["SPAM"], subject: "Vraie réponse", minutes: 4), history: false)
        await engine.step(account)
        _ = try await engine.aside("TRASH", accounts: [account])
        _ = try await engine.aside("SPAM", accounts: [account])

        let restored = try #require(try await engine.perform(.untrash, threadKey: key("tc1")))
        #expect(try restored.messageIDs == ["c1"] && store.asideThreads(label: "TRASH").isEmpty)
        try await engine.perform(.notSpam, threadKey: key("ts1"))
        await engine.step(account)
        #expect(gmail.labels("c1") == ["INBOX"] && gmail.labels("s1") == ["INBOX"])
        #expect(gmail.calls.contains("POST /messages/c1/untrash"))
        #expect(gmail.calls.contains("GET /messages/c1 full") && gmail.calls.contains("GET /messages/s1 full"))
        for id in ["c1", "s1"] {
            let row = try #require(try store.message(messageKey(id)))
            #expect(row.hasBody && row.bodyIsHTML)
        }
        #expect(kept(engine) == ["c1.html", "m1.html", "s1.html"])
        #expect(try store.inbox().map(\.threadID) == ["ts1", "tc1", "t1"])
        #expect(try store.readableThreads().count == 3)
    }

    /// The Mac closed longer than Gmail keeps its history, a spam marked « Pas un spam » and a mail restored from the
    /// trash on the phone meanwhile: the copy put square again shows them in the inbox, read whole (wave B review).
    @Test func aMailBroughtBackWhileTheMacWasClosedComesBackWhole() async throws {
        let (engine, gmail, store, root) = try setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        gmail.add("m1", .init(thread: "t1", labels: ["INBOX"]), history: false)
        gmail.add("s1", .init(thread: "ts1", labels: ["SPAM"], subject: "Vraie réponse", minutes: 2), history: false)
        gmail.add("c1", .init(thread: "tc1", labels: ["TRASH"], subject: "Devis signé", minutes: 3), history: false)
        await engine.step(account)
        _ = try await engine.aside("SPAM", accounts: [account])
        _ = try await engine.aside("TRASH", accounts: [account])
        gmail.change("s1", labels: ["INBOX"], history: false)
        gmail.change("c1", labels: ["INBOX"], history: false)
        gmail.forgetCursors()
        await engine.step(account)
        for id in ["s1", "c1"] {
            let row = try #require(try store.message(messageKey(id)))
            #expect(row.labels == ["INBOX"] && row.hasBody, "\(id)")
        }
        #expect(try store.inbox().map(\.threadID) == ["tc1", "ts1", "t1"] && store.asideThreads(label: "SPAM").isEmpty)
        #expect(kept(engine) == ["c1.html", "m1.html", "s1.html"])
    }

    /// A mail Paul read, then put in the spam on the phone while the Mac was closed (or deleted for good between two
    /// passes): its row goes, and so do its body and its files.
    @Test func aMailGoneFromGmailLeavesNothingOnTheMac() async throws {
        let (engine, gmail, store, root) = try setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        gmail.add("m1", .init(thread: "t1", labels: ["INBOX"]), history: false)
        gmail.add("m2", .init(thread: "t2", labels: ["INBOX"], minutes: 1), history: false)
        gmail.add("m3", .init(thread: "t3", labels: ["INBOX"], minutes: 2), history: false)
        await engine.step(account)
        let file = MailAttachment(partID: "2", filename: "facture.pdf", mimeType: "application/pdf", size: 3, attachmentID: "a", contentID: nil, inline: false)
        let known = try #require(try store.message(messageKey("m1")))
        try FileManager.default.createDirectory(at: engine.files.attachment(file, of: known).deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("pdf".utf8).write(to: engine.files.attachment(file, of: known))
        #expect(kept(engine) == ["m1-2", "m1-2/facture.pdf", "m1.html", "m2.html", "m3.html"])
        // Deleted for good between two passes.
        gmail.change("m3", labels: nil)
        await engine.step(account)
        #expect(kept(engine) == ["m1-2", "m1-2/facture.pdf", "m1.html", "m2.html"])
        // Put in the spam while Gmail forgot the history.
        gmail.change("m1", labels: ["SPAM"], history: false)
        gmail.forgetCursors()
        await engine.step(account)
        #expect(try store.message(messageKey("m1")) == nil)
        #expect(kept(engine) == ["m2.html"])
    }

    /// The development build reads the folders (a reading), and brings nothing back (a gesture).
    @Test func theDevelopmentBuildListsButNeverRestores() async throws {
        let (engine, gmail, store, root) = try setUp(flavor: .dev)
        defer { try? FileManager.default.removeItem(at: root) }
        gmail.add("c1", .init(thread: "tc1", labels: ["TRASH"]), history: false)
        _ = try await engine.aside("TRASH", accounts: [account])
        #expect(try store.asideThreads(label: "TRASH").count == 1)
        await #expect(throws: GoogleError.readOnlyBuild) { try await engine.perform(.untrash, threadKey: key("tc1")) }
        #expect(!gmail.calls.contains { $0.hasPrefix("POST") })
    }
}
