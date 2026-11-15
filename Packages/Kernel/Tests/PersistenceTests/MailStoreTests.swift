import Foundation
import Testing
@testable import Persistence

/// Base v8 (14/11): the copy of the mailboxes follows Gmail; a gesture changes it at once and names its messages.
@Suite struct MailStoreTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)
    let account = "moi@exemple.fr"

    func store() throws -> MailStore {
        let database = try AppDatabase.inMemory()
        try CalendarStore(database).addAccount(email: account, at: now)
        return MailStore(database)
    }

    func message(_ id: String, thread: String = "t1", minutes: Double = 0, from: String = "camille@exemple.fr", labels: [String] = ["INBOX", "UNREAD", "CATEGORY_PERSONAL"],
                 subject: String = "Maquette v2") -> MailMessageRow {
        MailMessageRow(account: account, messageID: id, threadID: thread, date: now.addingTimeInterval(minutes * 60),
                       sender: MailAddress(name: from == account ? "Moi" : "Camille Martin", email: from), subject: subject,
                       snippet: "extrait \(id)", labels: labels)
    }

    var key: String { MailThreadRow.key(account: account, threadID: "t1") }

    @Test func aThreadIsWhatItsMessagesSay() throws {
        let mails = try store()
        try mails.apply(account: account, upserts: [
            message("m1"),
            message("m2", minutes: 5, from: account, labels: ["SENT"]),
            message("m3", minutes: 9, labels: ["INBOX", "UNREAD", "CATEGORY_UPDATES"]),
        ])
        let thread = try #require(try mails.inbox().first)
        #expect(thread.id == key && thread.subject == "Maquette v2" && thread.snippet == "extrait m3" && thread.messageCount == 3)
        #expect(thread.senders.map(\.email) == ["camille@exemple.fr", account])
        #expect(thread.unread && thread.inInbox && !thread.hidden && thread.paulWrote)
        #expect(thread.category == "updates" && thread.lastSender == "camille@exemple.fr")
        #expect(thread.lastMessageAt == now.addingTimeInterval(540))
        #expect(try mails.messages(threadKey: key).map(\.messageID) == ["m1", "m2", "m3"])
    }

    /// Paul archives a thread; the client replies before Gmail has heard of the gesture. The reply stays in the
    /// inbox, and an older reading of Gmail's does not bring the archived message back.
    @Test func aGestureNamesItsMessagesAndSurvivesAnOlderReading() throws {
        let mails = try store()
        try mails.apply(account: account, upserts: [message("m1")])
        let gesture = try #require(try mails.enqueue(.archive, threadKey: key, at: now))
        #expect(gesture.messageIDs == ["m1"] && gesture.kind == .archive)
        #expect(try mails.inbox().isEmpty)
        #expect(try mails.pendingGestures(account: account).map(\.id) == [gesture.id])
        // Gmail, read before the gesture reached it, still says « in the inbox ».
        try mails.apply(account: account, labels: ["m1": ["INBOX", "UNREAD"]])
        #expect(try mails.inbox().isEmpty)
        // The reply arrives: the thread is back, for the new message only.
        try mails.apply(account: account, upserts: [message("m2", minutes: 3)])
        let thread = try #require(try mails.inbox().first)
        #expect(thread.messageCount == 2 && thread.snippet == "extrait m2")
        #expect(try mails.message(MailMessageRow.key(account: account, messageID: "m1"))?.labels.contains("INBOX") == false)
        // Gmail took the gesture: nothing waits, and its own labels are now the truth.
        try mails.finish(gestureID: try #require(gesture.id))
        #expect(try mails.pendingGestures(account: account).isEmpty)
    }

    @Test func theTrashHidesAThreadAndUndoingBringsItBack() throws {
        let mails = try store()
        try mails.apply(account: account, upserts: [message("m1"), message("m2", minutes: 2)])
        let trash = try #require(try mails.enqueue(.trash, threadKey: key, at: now))
        #expect(trash.messageIDs == ["m1", "m2"])
        #expect(try mails.inbox().isEmpty && mails.thread(key)?.hidden == true)
        // Undoing is the inverse gesture on the same messages.
        let undo = try #require(try mails.enqueue(trash.kind.inverse, threadKey: key, messageIDs: trash.messageIDs, at: now))
        #expect(undo.kind == .untrash && undo.messageIDs == ["m1", "m2"])
        let thread = try #require(try mails.inbox().first)
        #expect(thread.messageCount == 2 && !thread.hidden)
        #expect(try mails.pendingGestures(account: account).map(\.kind) == [.trash, .untrash])
    }

    @Test func readAndUnreadTouchTheRightMessages() throws {
        let mails = try store()
        try mails.apply(account: account, upserts: [message("m1"), message("m2", minutes: 2)])
        #expect(try mails.enqueue(.markRead, threadKey: key, at: now)?.messageIDs == ["m1", "m2"])
        #expect(try mails.thread(key)?.unread == false)
        // Nothing left to mark read: no gesture is made.
        #expect(try mails.enqueue(.markRead, threadKey: key, at: now) == nil)
        // As in Gmail: « unread » marks the last message.
        #expect(try mails.enqueue(.markUnread, threadKey: key, at: now)?.messageIDs == ["m2"])
        #expect(try mails.thread(key)?.unread == true)
    }

    @Test func whatGmailNoLongerHasGoes() throws {
        let mails = try store()
        try mails.apply(account: account, upserts: [message("m1"), message("m2", minutes: 2)])
        try mails.apply(account: account, removed: ["m2"])
        #expect(try mails.inbox().first?.messageCount == 1)
        try mails.apply(account: account, removed: ["m1"])
        #expect(try mails.thread(key) == nil)
    }

    /// A message read again from Gmail keeps what only the app knows: its body is on disk.
    @Test func aMessageReadAgainKeepsItsBody() throws {
        let mails = try store()
        try mails.apply(account: account, upserts: [message("m1")])
        let file = MailAttachment(partID: "1", filename: "devis.pdf", mimeType: "application/pdf", size: 1_200, attachmentID: "a", contentID: nil, inline: false)
        try mails.markBody(messageKey: MailMessageRow.key(account: account, messageID: "m1"), isHTML: true, attachments: [file])
        #expect(try mails.thread(key)?.hasAttachment == true)
        try mails.apply(account: account, upserts: [message("m1", labels: ["INBOX"])])
        let again = try #require(try mails.message(MailMessageRow.key(account: account, messageID: "m1")))
        #expect(again.hasBody && again.bodyIsHTML && again.attachments == [file] && !again.isUnread)
    }

    @Test func spamHidesAThreadAndUndoingBringsItBack() throws {
        let mails = try store()
        try mails.apply(account: account, upserts: [message("m1")])
        let spam = try #require(try mails.enqueue(.spam, threadKey: key, at: now))
        #expect(try mails.inbox().isEmpty && mails.thread(key)?.hidden == true)
        try mails.enqueue(spam.kind.inverse, threadKey: key, messageIDs: spam.messageIDs, at: now)
        #expect(try mails.inbox().first?.messageCount == 1)
    }

    /// The senders Paul could leave, the busiest first.
    @Test func theSubscriptionsAreCountedBySender() throws {
        let mails = try store()
        func letter(_ id: String, from: String, minutes: Double, unread: Bool) -> MailMessageRow {
            var row = message(id, thread: id, minutes: minutes, from: from, labels: unread ? ["INBOX", "UNREAD", "CATEGORY_PROMOTIONS"] : ["CATEGORY_PROMOTIONS"])
            row.listUnsubscribe = "<https://liste.exemple/stop>"
            row.listUnsubscribePost = "List-Unsubscribe=One-Click"
            row.authenticated = true
            return row
        }
        try mails.apply(account: account, upserts: [
            letter("l1", from: "lettre@liste.exemple", minutes: 1, unread: true), letter("l2", from: "lettre@liste.exemple", minutes: 2, unread: false),
            letter("l3", from: "promo@boutique.exemple", minutes: 3, unread: true), message("m1"),
        ])
        let subscriptions = try mails.subscriptions(since: now.addingTimeInterval(-86_400))
        #expect(subscriptions.map(\.sender.email) == ["lettre@liste.exemple", "promo@boutique.exemple"])
        #expect(subscriptions[0].count == 2 && subscriptions[0].unread == 1 && subscriptions[0].inboxThreads == ["moi@exemple.fr|l1"])
        #expect(subscriptions[0].listUnsubscribePost == "List-Unsubscribe=One-Click" && subscriptions[0].authenticated)
    }

    @Test func disconnectingAnAccountTakesItsMailsAway() throws {
        let mails = try store()
        try mails.apply(account: account, upserts: [message("m1")])
        try mails.enqueue(.archive, threadKey: key, at: now)
        try mails.save(MailCursorRow(account: account, historyID: "7", total: 1, done: 1))
        try CalendarStore(mails.database).removeAccount(email: account)
        #expect(try mails.thread(key) == nil && mails.messages(threadKey: key).isEmpty)
        #expect(try mails.cursors().isEmpty && mails.pendingGestures(account: account).isEmpty)
        // News that arrive after the disconnection create nothing.
        try mails.apply(account: account, upserts: [message("m9")])
        try mails.save(MailCursorRow(account: account, historyID: "8"))
        #expect(try mails.inbox().isEmpty && mails.cursors().isEmpty)
    }

    @Test func whatPaulSaidAboutASenderIsKept() throws {
        let mails = try store()
        try mails.remember(address: "Lettre@Exemple.fr", tab: "newsletters", at: now)
        try mails.remember(address: "lettre@exemple.fr", images: true, at: now)
        let rule = try #require(try mails.senders()["lettre@exemple.fr"])
        #expect(rule.tab == "newsletters" && rule.images && !rule.principal)
        try mails.remember(address: "lettre@exemple.fr", tab: .some(nil), images: false, at: now)
        #expect(try mails.senders().isEmpty)
    }

    /// Base v9 (14/11): a draft is kept on the Mac, then marked as Gmail took it; it leaves with its account.
    @Test func aDraftIsKeptThenPushedAndLeavesWithItsAccount() throws {
        let mails = try store()
        var draft = MailDraftRow(account: account, mode: .reply, threadKey: key, to: [MailAddress(name: "Camille", email: "camille@exemple.fr")],
                                 subject: "Re: Maquette v2", body: "Merci !", createdAt: now)
        try mails.saveDraft(draft)
        #expect(try mails.draft(draft.id) == draft)
        #expect(draft.isSendable && draft.needsPush)
        try mails.markPushed(draftID: draft.id, gmailDraftID: "r-1", gmailMessageID: "m-9", version: draft.updatedAt, at: now)
        draft = try #require(try mails.draft(draft.id))
        #expect(draft.gmailDraftID == "r-1" && !draft.needsPush)
        draft.body = "Merci beaucoup !"
        draft.updatedAt = now.addingTimeInterval(5)
        try mails.saveDraft(draft)
        #expect(try mails.draft(draft.id)?.needsPush == true)
        // An empty draft has nothing to send.
        #expect(!MailDraftRow(account: account, mode: .new, createdAt: now).isSendable)
        try CalendarStore(mails.database).removeAccount(email: account)
        #expect(try mails.drafts().isEmpty)
    }

    /// Step « Ranger »: the rules read the base (Paul's choices, the senders, the contacts of the projects);
    /// a project's threads are those its case names.
    @Test func theCaseOfAThreadComesFromTheBase() throws {
        let database = try AppDatabase.inMemory()
        try CalendarStore(database).addAccount(email: account, at: now)
        let mails = MailStore(database), contacts = ContactStore(database)
        let project = try ProjectStore(database).addProject(name: "Site vitrine", status: .priorite1, at: now)
        let camille = try contacts.upsert(email: "camille@studio.exemple", name: "Camille Martin", company: nil, at: now)
        try contacts.link(contactID: camille.id, projectID: project.id, origin: .paul, at: now)
        var sent = message("m2", minutes: 5, from: account, labels: ["SENT"])
        sent.to = [MailAddress(email: "marc@exemple.net")]
        try mails.apply(account: account, upserts: [message("m1", from: "camille@studio.exemple"), message("n1", thread: "t2", from: "lettre@lettre.exemple", labels: ["INBOX", "CATEGORY_PROMOTIONS"]), sent])
        var rules = try mails.filingRules()
        let thread = try #require(try mails.thread(key))
        #expect(rules.filing(of: thread)?.filing == .project(project.id) && rules.correspondents == ["marc@exemple.net"] && rules.mine == [account])
        #expect(try mails.threads(filedIn: project.id).map(\.id) == [key])
        // Paul files it elsewhere: kept for the thread, and for the sender's next mails.
        try mails.file(threadKey: key, as: .perso, at: now)
        try mails.remember(address: "camille@studio.exemple", filing: .some(MailFiling.perso.rawValue), at: now)
        rules = try mails.filingRules()
        #expect(rules.choices[key] == .perso && rules.senders["camille@studio.exemple"]?.filing == "perso")
        #expect(try mails.threads(filedIn: project.id).isEmpty)
        // Taken back: the rules answer again.
        try mails.file(threadKey: key, as: nil, at: now)
        try mails.remember(address: "camille@studio.exemple", filing: .some(nil), at: now)
        #expect(try mails.filingRules().filing(of: thread)?.filing == .project(project.id))
        // A link and a contact taken back (« Annuler »): the rules no longer see them.
        try contacts.unlink(contactID: camille.id, projectID: project.id)
        #expect(try mails.filingRules().filing(of: thread) == nil && contacts.links().isEmpty)
        try contacts.delete(contactID: camille.id)
        #expect(try contacts.contact(email: "camille@studio.exemple") == nil)
    }

    /// Review of 15/11: a project written with an old status (an older `polhub mcp`, a row the migration left
    /// in the bin) never breaks the mails' rules, nor the projects' reading.
    @Test func anOldStatusNeverBreaksTheRules() throws {
        let database = try AppDatabase.inMemory()
        let old = UUID(), odd = UUID()
        try database.writer.write { db in
            for (id, name, status, deleted) in [(old, "Ancien", "idée", true), (odd, "Bizarre", "statut inconnu", false)] {
                try db.execute(sql: """
                    INSERT INTO project (id, name, status, contacts, notes, kanbanOrder, createdAt, updatedAt, deletedAt)
                    VALUES (?, ?, ?, '[]', '', 0, ?, ?, ?)
                    """, arguments: [id.uuidString.lowercased(), name, status, now, now, deleted ? now : nil])
            }
        }
        let rules = try MailStore(database).filingRules()
        // The one in the bin is no case for mails (a deleted project, 15/11); the odd status still reads.
        #expect(Set(rules.projects.map(\.id)) == [odd])
        let all = try database.writer.read { try ProjectRow.fetchAll($0) }
        #expect(Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.status) }) == [old: .priorite1, odd: .enPause])
    }

    /// Review of 14/11: Paul's change is written on the row as it is now, Gmail's answer meanwhile included.
    @Test func changingADraftKeepsWhatGmailAnswered() throws {
        let mails = try store()
        let draft = MailDraftRow(account: account, mode: .new, subject: "Idée", createdAt: now)
        try mails.saveDraft(draft)
        try mails.markPushed(draftID: draft.id, gmailDraftID: "r1", gmailMessageID: "dm1", version: draft.updatedAt, at: now)
        let changed = try #require(try mails.updateDraft(draft.id, at: now.addingTimeInterval(5)) { $0.body = "Plus long" })
        #expect(changed.gmailDraftID == "r1" && changed.gmailMessageID == "dm1" && changed.body == "Plus long" && changed.needsPush)
        // Shown, not changed: nothing to give Gmail (second review of 14/11).
        #expect(try mails.updateDraft(draft.id, at: now.addingTimeInterval(9)) { $0.body = "Plus long" } == nil)
        try mails.setConflict(draft.id, .absent)
        #expect(try mails.draft(draft.id)?.conflict == .absent)
        try mails.forgetGmailCopy(draft.id)
        let fresh = try #require(try mails.draft(draft.id))
        #expect(fresh.gmailDraftID == nil && fresh.conflict == nil && fresh.pushedAt == nil && fresh.body == "Plus long")
    }

    /// The people Paul wrote to: To and Cc of what he sent.
    @Test func thePeoplePaulWroteTo() throws {
        let mails = try store()
        var sent = message("m1", from: account, labels: ["SENT"])
        sent.to = [MailAddress(name: "Camille", email: "Camille@Exemple.fr")]
        sent.cc = [MailAddress(email: "jules@exemple.fr")]
        try mails.apply(account: account, upserts: [sent, message("m2", thread: "t2", from: "lettre@lettre.exemple")])
        #expect(try mails.correspondents() == ["camille@exemple.fr", "jules@exemple.fr"])
    }

    /// 15/11, « comme Gmail »: « Tous les messages » holds the archived threads, never the trash; the list shows
    /// the files of each thread under it, without the images its HTML shows.
    @Test func everyThreadAndTheFilesOfEachThread() throws {
        let mails = try store()
        var withFiles = message("m1")
        withFiles.attachments = [MailAttachment(partID: "2", filename: "devis.pdf", mimeType: "application/pdf", size: 1_000, attachmentID: "a", contentID: nil, inline: false),
                                 MailAttachment(partID: "3", filename: "logo.png", mimeType: "image/png", size: 10, attachmentID: "b", contentID: "logo", inline: true)]
        var again = message("m2", minutes: 3)
        again.attachments = [withFiles.attachments[0]]
        try mails.apply(account: account, upserts: [
            withFiles, again,
            message("m3", thread: "t2", minutes: 5, labels: ["CATEGORY_PERSONAL"]),
            message("m4", thread: "t3", minutes: 7, labels: ["TRASH"]),
        ])
        #expect(try mails.allThreads().map(\.threadID) == ["t2", "t1"])
        #expect(try mails.allThreads(accounts: ["autre@exemple.fr"]).isEmpty)
        // The file keeps the first message that carries it: a click on its chip previews it (15/11).
        #expect(try mails.attachments(threadKeys: [key, MailThreadRow.key(account: account, threadID: "t2")])
            == [key: [MailListedFile(messageKey: withFiles.id, attachment: withFiles.attachments[0])]])
    }

    /// 15/11: the copy is the whole mailbox; « Tous les messages » and the agents are no longer cut at 2 000 and
    /// 5 000 threads.
    @Test func everyThreadOfTheCopyIsListed() throws {
        let mails = try store()
        let count = 5_100
        try mails.apply(account: account, upserts: (0..<count).map { index in
            message("m\(index)", thread: "t\(index)", minutes: Double(index), labels: ["CATEGORY_PERSONAL"])
        })
        let all = try mails.allThreads()
        #expect(all.count == count && all.first?.threadID == "t\(count - 1)" && all.last?.threadID == "t0")
        #expect(try mails.readableThreads().count == count)
        #expect(try mails.allThreads(limit: 10).count == 10)
    }

    /// 15/11, as Gmail: the « Envoyés » say who Paul wrote to; a sent mail he trashed leaves them.
    @Test func whoPaulWroteToInEachSentThread() throws {
        let mails = try store()
        var first = message("m2", minutes: 3, from: account, labels: ["SENT"])
        first.to = [MailAddress(name: "Camille Martin", email: "camille@exemple.fr")]
        first.cc = [MailAddress(name: "Jules Durand", email: "jules@exemple.fr")]
        var second = message("m3", minutes: 6, from: account, labels: ["SENT"])
        second.to = [MailAddress(name: "Camille Martin", email: "Camille@Exemple.fr"), MailAddress(email: "lou@exemple.fr")]
        var draft = message("m4", minutes: 8, from: account, labels: ["DRAFT"])
        draft.to = [MailAddress(email: "brouillon@exemple.fr")]
        var trashed = message("x1", thread: "t2", minutes: 9, from: account, labels: ["SENT", "TRASH"])
        trashed.to = [MailAddress(email: "nina@exemple.fr")]
        try mails.apply(account: account, upserts: [message("m1"), first, second, draft, trashed])
        let t2 = MailThreadRow.key(account: account, threadID: "t2")
        #expect(try mails.sentThreads().map(\.threadID) == ["t1"])
        #expect(try mails.sentRecipients(threadKeys: [key, t2]).mapValues { $0.map(\.email) }
            == [key: ["camille@exemple.fr", "jules@exemple.fr", "lou@exemple.fr"]])
        #expect(try mails.sentRecipients(threadKeys: []).isEmpty)
    }

    /// Correctifs du 15/11 : la recherche compare des octets, et trouve ce que `String.contains` trouvait, accents
    /// repliés, lettres d'autres écritures et chaînes venues de Foundation comprises.
    @Test func theSearchOfBytesFindsWhatTheSearchOfTextFound() {
        let found = " devis ete 2026 東京 camille exemple.fr"
        for words in [["dev"], ["ete", "camille"], ["東"], ["exemple.fr"], ["evis"], ["2026", "zzz"], ["京"], ["camillea"]] {
            let expected = words.allSatisfy { found.contains(" " + $0) }
            #expect(MailSearch.matches(words, in: found) == expected, "\(words)")
            #expect(MailSearch.matches(words, in: NSString(string: found) as String) == expected, "\(words)")
        }
        #expect(MailSearch.matches(["dev"], in: found) && !MailSearch.matches(["evis"], in: found) && !MailSearch.matches(["dev"], in: ""))
    }

    /// 15/11: the instant search reads the whole copy, never the trash, the spam nor the drafts; each thread is
    /// found by its subject, its extracts, its people (senders and recipients) and the names of its files.
    @Test func theSearchEntriesHoldTheWholeCopy() throws {
        let mails = try store()
        var sent = message("m2", minutes: 3, from: account, labels: ["SENT"], subject: "Réunion de chantier")
        sent.to = [MailAddress(name: "Jules Durand", email: "jules@atelier.exemple")]
        var withFile = message("m3", thread: "t2", minutes: 5, labels: ["CATEGORY_PERSONAL"], subject: "Le devis")
        withFile.attachments = [MailAttachment(partID: "2", filename: "Devis-Été_2026.pdf", mimeType: "application/pdf", size: 1_000,
                                               attachmentID: "a", contentID: nil, inline: false)]
        var draft = message("d1", thread: "t2", minutes: 7, from: account, labels: ["DRAFT"])
        draft.to = [MailAddress(email: "secret@exemple.fr")]
        try mails.apply(account: account, upserts: [
            message("m1"), sent, withFile, draft,
            message("m4", thread: "t3", minutes: 9, labels: ["TRASH"], subject: "Réunion à la corbeille"),
        ])
        let entries = try mails.searchEntries()
        #expect(entries.map(\.thread.threadID) == ["t2", "t1"])
        func found(_ text: String) -> [String] {
            guard case .local(let words) = MailSearch.mode(text) else { return [] }
            return MailSearch.filter(entries, words: words).map(\.threadID)
        }
        #expect(found("reunion") == ["t1"] && found("RÉUN") == ["t1"])
        #expect(found("jules") == ["t1"] && found("atelier.exemple") == ["t1"] && found("Camille Martin") == ["t2", "t1"])
        #expect(found("ete 2026") == ["t2"] && found("devis.pdf") == ["t2"])
        #expect(found("secret").isEmpty && found("corbeille").isEmpty)
        #expect(MailSearch.filter(entries, words: ["devis"], accounts: ["autre@exemple.fr"]).isEmpty)
        // Two letters at least; Gmail's operators go to Gmail only, on Enter.
        #expect(MailSearch.mode("") == .none && MailSearch.mode("  ") == .none && MailSearch.mode("é") == .tooShort)
        #expect(MailSearch.mode(" Ré ") == .local(["re"]) && MailSearch.mode("Re: devis") == .local(["re", "devis"]))
        #expect(MailSearch.mode("from:camille@exemple.fr") == .gmailOnly && MailSearch.mode("devis has:attachment") == .gmailOnly)
        #expect(MailSearch.mode("-in:inbox devis") == .gmailOnly)
    }

    @Test func theSentThreadsAndTheDraftsWrittenElsewhere() throws {
        let mails = try store()
        try mails.apply(account: account, upserts: [
            message("m1"), message("m2", minutes: 3, from: account, labels: ["SENT"]),
            message("d1", thread: "t2", minutes: 9, from: account, labels: ["DRAFT"], subject: "Brouillon du téléphone"),
        ])
        #expect(try mails.sentThreads().map(\.threadID) == ["t1"])
        #expect(try mails.gmailOnlyDrafts().map(\.messageID) == ["d1"])
        var draft = MailDraftRow(account: account, mode: .new, createdAt: now)
        draft.gmailMessageID = "d1"
        try mails.saveDraft(draft)
        #expect(try mails.gmailOnlyDrafts().isEmpty)
    }
}
