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
