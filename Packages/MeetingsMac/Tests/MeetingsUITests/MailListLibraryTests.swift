import Agenda
import Foundation
import Persistence
import Testing
@testable import MeetingsUI

/// The list of 15/11: one search bar over the whole copy, « À : » in « Envoyés », the files of a line shown
/// without opening the thread. No Gmail here: nothing is asked of the network.
@MainActor
@Suite struct MailListLibraryTests {
    let account = "moi@exemple.fr"
    let other = "perso@exemple.org"

    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<150 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
        #expect(condition())
    }

    /// Two mailboxes that granted the mails, and a library on them.
    func library(_ messages: [MailMessageRow]) async throws -> (MailLibrary, MailStore, URL) {
        let database = try AppDatabase.inMemory()
        let calendar = CalendarStore(database)
        for (index, email) in [account, other].enumerated() {
            try calendar.addAccount(email: email, at: Date().addingTimeInterval(Double(index)))
            try calendar.setGrantedScopes(email: email, scopes: "openid https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/gmail.modify")
        }
        let store = MailStore(database)
        for mailbox in [account, other] { try store.apply(account: mailbox, upserts: messages.filter { $0.account == mailbox }) }
        let root = FileManager.default.temporaryDirectory.appending(path: "liste-\(UUID().uuidString)", directoryHint: .isDirectory)
        let mails = MailLibrary(agenda: AgendaLibrary(database: database), root: root, defaults: UserDefaults(suiteName: "liste-\(UUID().uuidString)")!)
        try await waitUntil { mails.accounts.count == 2 && !mails.rules.mine.isEmpty }
        return (mails, store, root)
    }

    func mail(_ id: String, _ mailbox: String? = nil, thread: String, from: MailAddress, to: [MailAddress] = [], subject: String, labels: [String],
              minutes: Double = 0, files: [MailAttachment] = []) -> MailMessageRow {
        MailMessageRow(account: mailbox ?? account, messageID: id, threadID: thread, date: Date().addingTimeInterval(-minutes * 60), sender: from, to: to,
                       subject: subject, snippet: "Extrait de \(subject)", labels: labels, attachments: files)
    }

    let camille = MailAddress(name: "Camille Martin", email: "camille@exemple-studio.fr")
    let jules = MailAddress(name: "Jules Durand", email: "jules@atelier.exemple")
    var me: MailAddress { MailAddress(name: "Moi", email: account) }

    /// As Paul types: the whole copy (inbox, archived, sent, every tab, both mailboxes), accents and capitals
    /// aside; one letter or an operator of Gmail's gives the folder back.
    @Test func typingFiltersTheWholeCopyAtOnce() async throws {
        let devis = MailAttachment(partID: "2", filename: "Devis-Réfection.pdf", mimeType: "application/pdf", size: 1_000, attachmentID: "a", contentID: nil, inline: false)
        let (mails, store, root) = try await library([
            mail("a1", thread: "a", from: camille, subject: "Réunion de chantier", labels: ["INBOX", "CATEGORY_PERSONAL"], minutes: 10),
            mail("b1", thread: "b", from: jules, subject: "Planning", labels: ["CATEGORY_PERSONAL"], minutes: 20, files: [devis]),
            mail("c1", thread: "c", from: me, to: [MailAddress(name: "Nina Roche", email: "nina@exemple.fr")], subject: "Photos", labels: ["SENT"], minutes: 30),
            mail("d1", thread: "d", from: MailAddress(email: "lettre@lettre.exemple"), subject: "La réunion des lecteurs", labels: ["INBOX", "CATEGORY_PROMOTIONS"], minutes: 40),
            mail("e1", other, thread: "e", from: camille, subject: "Une REUNION perso", labels: ["INBOX", "CATEGORY_PERSONAL"], minutes: 50),
            mail("f1", thread: "f", from: camille, subject: "Réunion supprimée", labels: ["TRASH"], minutes: 5),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        func found() -> [String]? { mails.found?.map(\.threadID) }

        mails.query = "réunion"
        try await waitUntil { mails.found != nil }
        #expect(found() == ["a", "d", "e"])
        #expect(mails.searchSummary == "3 fils dans tes mails · Entrée : chercher aussi dans Gmail")
        mails.query = "REFECTION"
        #expect(found() == ["b"])
        // An archived thread found: its file shows under its line too.
        #expect(mails.files[MailThreadRow.key(account: account, threadID: "b")]?.map(\.attachment.filename) == [devis.filename])
        mails.query = "nina"
        #expect(found() == ["c"])
        mails.query = "camille reunion"
        #expect(found() == ["a", "e"])
        mails.query = "introuvable"
        #expect(found() == [] && mails.searchSummary == "Aucun fil dans tes mails · Entrée : chercher aussi dans Gmail")
        // A hidden mailbox stays out.
        mails.hidden = [other]
        mails.query = "reunion"
        #expect(found() == ["a", "d"])
        mails.hidden = []
        #expect(found() == ["a", "d", "e"])

        // A new mail that answers joins the results by itself.
        try store.apply(account: account, upserts: [mail("g1", thread: "g", from: jules, subject: "Compte rendu de réunion", labels: ["INBOX", "CATEGORY_PERSONAL"])])
        try await waitUntil { found()?.first == "g" }

        mails.query = "r"
        #expect(mails.found == nil && mails.searchSummary == nil)
        mails.query = "from:camille"
        #expect(mails.found == nil && mails.searchSummary == "Entrée : chercher dans Gmail")
        mails.query = ""
        #expect(mails.found == nil && mails.searchSummary == nil)
    }

    /// « Envoyés » say who Paul wrote to, as Gmail's: « À : Camille, Jules ».
    @Test func theSentFolderKnowsWhoPaulWroteTo() async throws {
        let (mails, _, root) = try await library([
            mail("a1", thread: "a", from: camille, subject: "Maquette", labels: ["INBOX", "CATEGORY_PERSONAL"], minutes: 30),
            mail("a2", thread: "a", from: me, to: [camille], subject: "Re: Maquette", labels: ["SENT"], minutes: 20),
            mail("a3", thread: "a", from: me, to: [jules], subject: "Re: Maquette", labels: ["SENT"], minutes: 10),
            mail("b1", thread: "b", from: me, to: [MailAddress(email: "nina@exemple.fr")], subject: "Photos", labels: ["SENT"], minutes: 5),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        mails.folder = .sent
        let a = MailThreadRow.key(account: account, threadID: "a"), b = MailThreadRow.key(account: account, threadID: "b")
        #expect(mails.shown.map(\.id) == [b, a])
        #expect(mails.sentTo[a]?.map(\.email) == [camille.email, jules.email])
        let mine: Set<String> = [account]
        #expect(MailText.recipients(mails.sentTo[a] ?? [], mine: mine) == "Camille, Jules")
        #expect(MailText.recipients(mails.sentTo[b] ?? [], mine: mine) == "nina@exemple.fr")
        #expect(MailText.recipients([camille], mine: mine) == "Camille Martin" && MailText.recipients([me, jules], mine: mine) == "moi, Jules")
    }

    /// A chip under a line: Quick Look shows the file at once, through the section's one preview, without
    /// opening the thread. The file was downloaded before: nothing is asked of Gmail.
    @Test func aChipShowsItsFileInQuickLook() async throws {
        let pdf = MailAttachment(partID: "2", filename: "maquette.pdf", mimeType: "application/pdf", size: 4, attachmentID: "a", contentID: nil, inline: false)
        let message = mail("a1", thread: "a", from: camille, subject: "Maquette", labels: ["INBOX", "CATEGORY_PERSONAL"], files: [pdf])
        let (mails, _, root) = try await library([message])
        defer { try? FileManager.default.removeItem(at: root) }
        let key = MailThreadRow.key(account: account, threadID: "a")
        try await waitUntil { mails.files[key] != nil }
        let listed = try #require(mails.files[key]?.first)
        #expect(listed == MailListedFile(messageKey: message.id, attachment: pdf))
        let url = mails.engine.files.attachment(pdf, of: message)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("%PDF".utf8).write(to: url)

        mails.open(listed)
        #expect(mails.opening.contains(listed.id))
        try await waitUntil { mails.preview == url }
        #expect(mails.opening.isEmpty)
    }

    /// « Tous les mails de cet expéditeur »: every thread he wrote in, from the copy, which holds the whole mailbox;
    /// not one page of Gmail's search (25 threads by mailbox), which an « Archiver » on all would leave short (audit
    /// of 19/11).
    @Test func everyMailOfASenderShowsAllOfThem() async throws {
        let database = try AppDatabase.inMemory()
        let calendar = CalendarStore(database)
        try calendar.addAccount(email: account, at: Date())
        try calendar.setGrantedScopes(email: account, scopes: "openid https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/gmail.modify")
        let letter = MailAddress(name: "La Lettre", email: "lettre@lettre.exemple")
        let store = MailStore(database)
        try store.apply(account: account, upserts: (0..<30).map { index in
            mail("l\(index)", thread: "l\(index)", from: letter, subject: "Numéro \(index)", labels: ["INBOX", "CATEGORY_PROMOTIONS"], minutes: Double(index) * 60)
        } + [mail("c1", thread: "c", from: camille, subject: "Maquette", labels: ["INBOX", "CATEGORY_PERSONAL"])])
        let root = FileManager.default.temporaryDirectory.appending(path: "liste-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        // Gmail answers nothing here: what shows comes from the copy.
        let gmail = SilentGmail()
        let mails = MailLibrary(agenda: AgendaLibrary(database: database), root: root, defaults: UserDefaults(suiteName: "liste-\(UUID().uuidString)")!,
                                send: { _ in gmail.send })
        try await waitUntil { mails.accounts.count == 1 && mails.inbox.count == 31 }
        mails.showAll(from: letter.email)
        try await waitUntil { mails.found?.count == 30 }
        #expect(mails.found?.allSatisfy { $0.lastSender == letter.email } == true)
        // An archived one is his too; one in the trash is not.
        try store.apply(account: account, upserts: [
            mail("l0", thread: "l0", from: letter, subject: "Numéro 0", labels: ["CATEGORY_PROMOTIONS"]),
            mail("l1", thread: "l1", from: letter, subject: "Numéro 1", labels: ["TRASH", "CATEGORY_PROMOTIONS"], minutes: 60),
        ])
        try await waitUntil { mails.found?.count == 29 }
        #expect(mails.found?.contains { $0.threadID == "l0" } == true && mails.found?.contains { $0.threadID == "l1" } == false)
        // A name alone, typed, still waits for Enter: only Gmail answers an operator.
        mails.query = "from:lettre"
        #expect(mails.found == nil)
    }
}
