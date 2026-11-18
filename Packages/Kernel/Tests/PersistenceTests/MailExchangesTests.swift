import Foundation
import Testing
@testable import Persistence

/// Who wrote to whom, and when (18/11): what the rules of « À valider » read of a message. Never its subject nor its
/// text. Every name and address here is invented.
@Suite struct MailExchangesTests {
    let now = Date(timeIntervalSince1970: 1_794_992_400)
    static let me = "moi@exemple.fr", other = "moi@atelier.exemple", claire = "claire@cabinet.exemple", marc = "marc@exemple.net"

    func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    func store() throws -> MailStore {
        let database = try AppDatabase.inMemory()
        try CalendarStore(database).addAccount(email: Self.me, at: ago(400))
        try CalendarStore(database).addAccount(email: Self.other, at: ago(400))
        return MailStore(database)
    }

    func received(_ id: String, thread: String, from: String, daysAgo: Double, to: [String] = [me], cc: [String] = [], subject: String = "Maquette",
                  box: String = me, labels: [String] = ["INBOX", "CATEGORY_PERSONAL"], files: [MailAttachment] = [], list: String? = nil) -> MailMessageRow {
        MailMessageRow(account: box, messageID: id, threadID: thread, date: ago(daysAgo), sender: MailAddress(name: "Quelqu'un Exemple", email: from),
                       to: to.map { MailAddress(email: $0) }, cc: cc.map { MailAddress(email: $0) }, subject: subject, snippet: "extrait", labels: labels,
                       listUnsubscribe: list, attachments: files)
    }

    func sent(_ id: String, thread: String, to: [String], cc: [String] = [], daysAgo: Double, box: String = me, labels: [String] = ["SENT"]) -> MailMessageRow {
        MailMessageRow(account: box, messageID: id, threadID: thread, date: ago(daysAgo), sender: MailAddress(name: "Moi", email: box),
                       to: to.map { MailAddress(email: $0) }, cc: cc.map { MailAddress(email: $0) }, subject: "Maquette", snippet: "extrait", labels: labels)
    }

    func file(_ name: String, _ type: String) -> MailAttachment {
        MailAttachment(partID: "2", filename: name, mimeType: type, size: 900, attachmentID: "a", contentID: nil, inline: false)
    }

    func key(_ thread: String, box: String = me) -> String { MailThreadRow.key(account: box, threadID: thread) }

    @Test func eachMessageSaysWhoWroteToWhomAndWhen() throws {
        let mails = try store()
        try mails.apply(account: Self.me, upserts: [
            received("a1", thread: "a", from: "Claire@Cabinet.Exemple", daysAgo: 5, cc: [Self.marc]),
            // Paul answers in another thread, to Claire with Marc in copy; Claire twice counts once.
            sent("b1", thread: "b", to: [Self.claire, "CLAIRE@cabinet.exemple"], cc: [Self.marc], daysAgo: 2),
        ])
        let exchanges = try mails.exchanges(since: ago(30))
        #expect(exchanges.count == 2)
        // The oldest first.
        #expect(exchanges.map(\.threadKey) == [key("a"), key("b")])
        #expect(exchanges[0] == MailExchange(threadKey: key("a"), date: ago(5), mine: false, sender: Self.claire, recipients: [Self.me, Self.marc], calendar: false))
        #expect(exchanges[1] == MailExchange(threadKey: key("b"), date: ago(2), mine: true, sender: Self.me, recipients: [Self.claire, Self.marc], calendar: false))
    }

    @Test func aMessageOfPaulIsHisWhateverItsBoxOrItsLabel() throws {
        let mails = try store()
        try mails.apply(account: Self.me, upserts: [
            // Seen in this box without `SENT`: written from his other address.
            received("a1", thread: "a", from: Self.other, daysAgo: 3, to: [Self.claire]),
        ])
        try mails.apply(account: Self.other, upserts: [sent("x1", thread: "x", to: [Self.marc], daysAgo: 1, box: Self.other)])
        let exchanges = try mails.exchanges(since: ago(30))
        #expect(exchanges.map(\.mine) == [true, true])
        #expect(exchanges.map(\.recipients) == [[Self.claire], [Self.marc]])
    }

    @Test func neitherTheTrashNorTheSpamNorADraftNorWhatIsOlder() throws {
        let mails = try store()
        try mails.apply(account: Self.me, upserts: [
            received("a1", thread: "a", from: Self.claire, daysAgo: 4, labels: ["TRASH"]),
            received("b1", thread: "b", from: Self.claire, daysAgo: 4, labels: ["SPAM"]),
            sent("c1", thread: "c", to: [Self.claire], daysAgo: 4, labels: ["DRAFT"]),
            received("d1", thread: "d", from: Self.claire, daysAgo: 40),
            received("e1", thread: "e", from: Self.claire, daysAgo: 4),
        ])
        #expect(try mails.exchanges(since: ago(30)).map(\.threadKey) == [key("e")])
        // Exactly at the date: not after it.
        #expect(try mails.exchanges(since: ago(4)).isEmpty)
    }

    /// A calendar's own mail, sent from a person's address: it carries an invitation, or its subject begins as
    /// Google's and Outlook's do. Nobody expects an answer to it.
    @Test func aCalendarsMailIsKnownByItsFileOrItsSubject() throws {
        let mails = try store()
        try mails.apply(account: Self.me, upserts: [
            received("a1", thread: "a", from: Self.claire, daysAgo: 9, subject: "Point projet", files: [file("invite.ics", "application/ics")]),
            received("b1", thread: "b", from: Self.claire, daysAgo: 8, subject: "Point projet", files: [file("", "text/calendar; method=REQUEST")]),
            received("c1", thread: "c", from: Self.claire, daysAgo: 7, subject: "Accepté : Rendez-vous de 30 min"),
            received("d1", thread: "d", from: Self.claire, daysAgo: 6, subject: "Invitation mise à jour: Point - jeu. 12 nov."),
            received("e1", thread: "e", from: Self.claire, daysAgo: 5, subject: "Updated invitation: Weekly"),
            // Not a calendar's: a word of the list without its colon, a plain file.
            received("f1", thread: "f", from: Self.claire, daysAgo: 4, subject: "Invitation au séminaire de juin"),
            received("g1", thread: "g", from: Self.claire, daysAgo: 3, subject: "Accepté par le client", files: [file("devis.pdf", "application/pdf")]),
        ])
        #expect(try mails.exchanges(since: ago(30)).map(\.calendar) == [true, true, true, true, true, false, false])
    }

    /// A mail no person wrote, even from a person's address: a list's, by its header; an absent mailbox's answer, by
    /// how its subject begins. A subject that only speaks of an absence is a person's.
    @Test func anAutomaticMailIsKnownByItsHeaderOrItsSubject() throws {
        let mails = try store()
        try mails.apply(account: Self.me, upserts: [
            received("a1", thread: "a", from: Self.claire, daysAgo: 9, subject: "La lettre du cabinet", list: "<https://cabinet.exemple/quitter>"),
            received("b1", thread: "b", from: Self.claire, daysAgo: 8, subject: "Réponse automatique : Maquette v2"),
            received("c1", thread: "c", from: Self.claire, daysAgo: 7, subject: "Automatic reply: Maquette v2"),
            received("d1", thread: "d", from: Self.claire, daysAgo: 6, subject: "Mon absence de la semaine prochaine"),
            received("e1", thread: "e", from: Self.claire, daysAgo: 5, subject: "Maquette v2", list: "  "),
        ])
        #expect(try mails.exchanges(since: ago(30)).map(\.automatic) == [true, true, true, false, false])
    }

    /// Read without a trap: people that are no list, a sender that is no person, a date that is no date.
    @Test func aRowThatCannotBeReadIsReadAsLittleAsItSays() throws {
        let mails = try store()
        try mails.apply(account: Self.me, upserts: [
            received("a1", thread: "a", from: Self.claire, daysAgo: 5),
            received("b1", thread: "b", from: Self.claire, daysAgo: 4),
            received("c1", thread: "c", from: Self.claire, daysAgo: 3),
        ])
        try mails.database.writer.write { db in
            try db.execute(sql: #"UPDATE mail_message SET "to" = 'pas une liste', sender = '42' WHERE messageID = 'a1'"#)
            try db.execute(sql: "UPDATE mail_message SET date = 'bientôt' WHERE messageID = 'b1'")
            try db.execute(sql: "UPDATE mail_message SET attachments = '{', labels = 'x' WHERE messageID = 'c1'")
        }
        let exchanges = try mails.exchanges(since: ago(30))
        // The message without a date is left out; the others say what they can.
        #expect(exchanges.map(\.threadKey) == [key("a"), key("c")])
        #expect(exchanges[0].sender == nil && exchanges[0].recipients.isEmpty && !exchanges[0].mine)
        #expect(exchanges[1].sender == Self.claire && !exchanges[1].calendar)
    }
}
