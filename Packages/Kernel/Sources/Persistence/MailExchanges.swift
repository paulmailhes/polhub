import Foundation
import GRDB

/// One message as the rules of « À valider » read it (18/11): who wrote to whom, when, in which thread. Never its
/// subject nor its text. Paul answers a client in a new mail more often than in the thread, and his clients do the
/// same: who owes an answer is read from the exchange with a person, not from the thread alone.
public struct MailExchange: Equatable, Sendable {
    public var threadKey: String
    public var date: Date
    /// Paul wrote it: it carries `SENT`, or its sender is one of his accounts.
    public var mine: Bool
    /// Who wrote it, in small letters; `nil` when no header said.
    public var sender: String?
    /// Who it was written to, To then Cc, in small letters, once each.
    public var recipients: [String]
    /// A calendar's own mail (an invitation, an answer to one), even sent from a person's address: nobody expects
    /// an answer to it.
    public var calendar: Bool
    /// A mail no person wrote, even from a person's address: a list's (it says how to leave it), an answer sent by
    /// an absent mailbox.
    public var automatic: Bool

    public init(threadKey: String, date: Date, mine: Bool, sender: String?, recipients: [String], calendar: Bool, automatic: Bool = false) {
        self.threadKey = threadKey
        self.date = date
        self.mine = mine
        self.sender = sender
        self.recipients = recipients
        self.calendar = calendar
        self.automatic = automatic
    }

    /// How the subject of an absent mailbox's answer begins, in French, in English and in German.
    static let automaticWords = ["réponse automatique", "automatic reply", "auto-reply", "autoreply", "out of office", "absent du bureau",
                                 "absence du bureau", "automatische antwort", "abwesenheitsnotiz", "abwesend"]

    /// A list's mail by its header, an absent mailbox's answer by how its subject begins.
    static func isAutomatic(subject: String, listUnsubscribe: String?) -> Bool {
        if let listUnsubscribe, !listUnsubscribe.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        let start = subject.trimmingCharacters(in: .whitespaces).lowercased()
        return automaticWords.contains { start.hasPrefix($0) }
    }

    /// How the subject of a calendar's mail begins, at Google and at Outlook, in French and in English: one of these
    /// words, then its colon.
    static let calendarWords = ["invitation mise à jour", "invitation", "updated invitation", "accepté", "accepted", "refusé", "declined", "provisoire",
                                "tentative", "peut-être", "événement annulé", "annulé", "canceled event", "cancelled event", "canceled", "cancelled",
                                "proposition de nouvel horaire", "proposed new time", "nouvel événement", "new event"]

    /// A calendar's mail by what it carries (a part of calendar type, an `.ics` file), else by how its subject begins.
    static func isCalendar(subject: String, attachments: [MailAttachment]) -> Bool {
        if attachments.contains(where: { file in
            let type = file.mimeType.lowercased()
            return type.hasPrefix("text/calendar") || type.hasPrefix("application/ics") || file.filename.lowercased().hasSuffix(".ics")
        }) { return true }
        let start = subject.trimmingCharacters(in: .whitespaces).lowercased()
        return calendarWords.contains { start.hasPrefix($0 + ":") || start.hasPrefix($0 + " :") }
    }
}

extension MailStore {
    /// The messages shown (neither in the trash, nor in the spam, nor a draft) dated after `since`, the oldest
    /// first: who wrote to whom. One pass over the messages, read without a trap: a row that says less is read as
    /// less, one without a date is left out.
    public func exchanges(since: Date) throws -> [MailExchange] {
        try database.writer.read { db in
            let mine = Set(try String.fetchAll(db, sql: "SELECT lower(email) FROM google_account"))
            let decoder = JSONDecoder()
            func decoded<T: Decodable>(_ type: T.Type, _ value: DatabaseValue) -> T? {
                String.fromDatabaseValue(value).flatMap { try? decoder.decode(type, from: Data($0.utf8)) }
            }
            let rows = try Row.fetchAll(db, sql: """
                SELECT threadKey, date, sender, "to", cc, labels, subject, attachments, listUnsubscribe FROM mail_message
                WHERE date > ? AND labels NOT LIKE '%"TRASH"%' AND labels NOT LIKE '%"SPAM"%' AND labels NOT LIKE '%"DRAFT"%'
                ORDER BY date
                """, arguments: [since])
            var found: [MailExchange] = []
            found.reserveCapacity(rows.count)
            for row in rows {
                guard let thread = String.fromDatabaseValue(row["threadKey"]), let date = Date.fromDatabaseValue(row["date"]) else { continue }
                let sender = decoded(MailAddress.self, row["sender"])?.email.lowercased()
                let labels = decoded([String].self, row["labels"]) ?? []
                var recipients: [String] = []
                for column in ["to", "cc"] {
                    for person in decoded([MailAddress].self, row[column]) ?? [] {
                        let email = person.email.lowercased()
                        if !recipients.contains(email) { recipients.append(email) }
                    }
                }
                let subject = String.fromDatabaseValue(row["subject"]) ?? ""
                let calendar = MailExchange.isCalendar(subject: subject, attachments: decoded([MailAttachment].self, row["attachments"]) ?? [])
                let automatic = MailExchange.isAutomatic(subject: subject, listUnsubscribe: String.fromDatabaseValue(row["listUnsubscribe"]))
                found.append(MailExchange(threadKey: thread, date: date, mine: MailMessageRow.isMine(labels: labels, sender: sender, mine: mine),
                                          sender: sender, recipients: recipients, calendar: calendar, automatic: automatic))
            }
            return found
        }
    }
}
