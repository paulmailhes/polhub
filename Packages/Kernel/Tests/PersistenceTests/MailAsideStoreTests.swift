import Foundation
import Testing
@testable import Persistence

/// Wave B (15/11): « Corbeille » and « Spam ». Their threads are put aside whole: the folders list them, nothing
/// else does (lists, counts, search, agents).
@Suite struct MailAsideStoreTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)
    let account = "moi@exemple.fr"
    let other = "perso@exemple.org"

    func store() throws -> MailStore {
        let database = try AppDatabase.inMemory()
        try CalendarStore(database).addAccount(email: account, at: now)
        try CalendarStore(database).addAccount(email: other, at: now.addingTimeInterval(1))
        return MailStore(database)
    }

    func message(_ id: String, thread: String, minutes: Double = 0, account mailbox: String? = nil, from: String = "camille@exemple.fr",
                 labels: [String], subject: String = "Maquette v2", hasBody: Bool = false) -> MailMessageRow {
        MailMessageRow(account: mailbox ?? account, messageID: id, threadID: thread, date: now.addingTimeInterval(minutes * 60),
                       sender: MailAddress(name: "Camille Martin", email: from), subject: subject, snippet: "extrait \(id)", labels: labels,
                       hasBody: hasBody, bodyIsHTML: hasBody)
    }

    func key(_ thread: String, _ mailbox: String? = nil) -> String { MailThreadRow.key(account: mailbox ?? account, threadID: thread) }

    /// The trash and the spam list the threads put aside whole, the most recent first; a thread with one message
    /// left in the inbox stays in the inbox; nothing of them shows in the other lists.
    @Test func theTrashAndTheSpamListTheThreadsPutAsideWhole() throws {
        let mails = try store()
        try mails.apply(account: account, upserts: [
            message("m1", thread: "boite", labels: ["INBOX", "UNREAD", "CATEGORY_PERSONAL"]),
            message("c1", thread: "corbeille-ancienne", minutes: 1, labels: ["TRASH", "CATEGORY_PERSONAL"], subject: "Ancien devis"),
            message("c2", thread: "corbeille-recente", minutes: 8, labels: ["TRASH"], subject: "Facture refaite"),
            message("p1", thread: "partiel", minutes: 4, labels: ["INBOX"]),
            message("p2", thread: "partiel", minutes: 5, labels: ["TRASH"]),
            message("s1", thread: "spam", minutes: 6, from: "gagnant@loterie.exemple", labels: ["SPAM", "UNREAD"], subject: "Vous avez gagné"),
            message("d1", thread: "spam", minutes: 7, from: account, labels: ["DRAFT"]),
        ])
        try mails.apply(account: other, upserts: [message("o1", thread: "autre", minutes: 9, account: other, labels: ["TRASH"])])

        #expect(try mails.asideThreads(label: "TRASH").map(\.threadID) == ["autre", "corbeille-recente", "corbeille-ancienne"])
        #expect(try mails.asideThreads(label: "TRASH", accounts: [account]).map(\.threadID) == ["corbeille-recente", "corbeille-ancienne"])
        #expect(try mails.asideThreads(label: "SPAM").map(\.threadID) == ["spam"])
        #expect(try mails.asideThreads(label: "INBOX").isEmpty)
        let spam = try #require(try mails.asideThreads(label: "SPAM").first)
        #expect(spam.hidden && !spam.unread && spam.subject == "Vous avez gagné")
        // Nowhere else: the inbox, every thread, the search, the agents.
        #expect(try Set(mails.inbox().map(\.threadID)) == ["boite", "partiel"])
        #expect(try !mails.allThreads().contains { $0.hidden })
        #expect(try Set(mails.readableThreads().map(\.threadID)) == ["boite", "partiel"])
        #expect(try Set(mails.searchEntries().map(\.thread.threadID)) == ["boite", "partiel"])
        // Opened from its folder, a thread put aside shows its messages, never a draft.
        #expect(try mails.messages(threadKey: key("spam")).isEmpty)
        #expect(try mails.messages(threadKey: key("spam"), aside: true).map(\.messageID) == ["s1"])
        #expect(try mails.messages(threadKey: key("partiel")).map(\.messageID) == ["p1"])
    }

    /// The search typed in the trash reads the trash only.
    @Test func theTrashIsSearchedApart() throws {
        let mails = try store()
        try mails.apply(account: account, upserts: [
            message("m1", thread: "boite", labels: ["INBOX"], subject: "Facture de novembre"),
            message("c1", thread: "corbeille", minutes: 3, labels: ["TRASH"], subject: "Facture refaite"),
            message("s1", thread: "spam", minutes: 6, labels: ["SPAM"], subject: "Facture impayée"),
        ])
        let entries = try mails.searchEntries(aside: "TRASH")
        #expect(entries.map(\.thread.threadID) == ["corbeille"])
        #expect(MailSearch.filter(entries, words: ["facture"]).map(\.threadID) == ["corbeille"])
        #expect(try mails.searchEntries(aside: "SPAM").map(\.thread.threadID) == ["spam"])
        // Gmail's operators do not reach Gmail from there: their words filter the folder.
        #expect(MailSearch.localWords("from:camille facture") == ["camille", "facture"])
        #expect(MailSearch.localWords("Réfection") == ["refection"] && MailSearch.localWords("é") == nil && MailSearch.localWords("  ") == nil)
    }

    /// A mail known before it went to the spam: its body and its files are no longer kept, only its headers.
    @Test func aSpamKeepsNothingButItsHeaders() throws {
        let mails = try store()
        var known = message("s1", thread: "spam", labels: ["SPAM"], hasBody: true)
        known.attachments = [MailAttachment(partID: "2", filename: "facture.pdf", mimeType: "application/pdf", size: 1_000, attachmentID: "a",
                                            contentID: nil, inline: false)]
        try mails.apply(account: account, upserts: [known, message("m1", thread: "boite", labels: ["INBOX"], hasBody: true),
                                                     message("c1", thread: "corbeille", labels: ["TRASH"], hasBody: true)])
        #expect(try mails.spamOnDisk(account: account).map(\.messageID) == ["s1"])
        try mails.forgetSpamFiles(messageKeys: [known.id])
        let after = try #require(try mails.message(known.id))
        #expect(!after.hasBody && after.attachments.isEmpty && after.labels == ["SPAM"])
        #expect(try mails.spamOnDisk(account: account).isEmpty)
        // The trash keeps its bodies, as any mail.
        #expect(try mails.message(MailMessageRow.key(account: account, messageID: "c1"))?.hasBody == true)
    }
}
