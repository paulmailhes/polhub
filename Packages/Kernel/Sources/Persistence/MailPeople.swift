import Foundation
import GRDB

/// Someone Paul wrote to, from what he sent (To and Cc): how often, when last, under which name (15/11). The
/// people index ranks the suggestions with it.
public struct MailCorrespondent: Equatable, Sendable {
    /// The last name a header gave this address; `nil` when none ever did.
    public var name: String?
    /// How many of Paul's mails went to this address.
    public var sent: Int
    public var lastAt: Date

    public init(name: String? = nil, sent: Int, lastAt: Date) {
        self.name = name
        self.sent = sent
        self.lastAt = lastAt
    }
}

extension MailStore {
    /// The people Paul wrote to, by lowercased address.
    public func correspondentStats() throws -> [String: MailCorrespondent] {
        try database.writer.read { try Self.correspondentStats($0) }
    }

    /// The people Paul had written to at `asOf` (To and Cc of what he had sent by then), by lowercased address:
    /// who « someone he already wrote to » was on that day.
    public func correspondents(asOf: Date) throws -> Set<String> {
        try database.writer.read { Set(try Self.correspondentStats($0, asOf: asOf).keys) }
    }

    /// One reading of what Paul sent, in date order: the count, the last date and the last name of each address.
    /// `asOf`: only what he had sent by then.
    static func correspondentStats(_ db: Database, asOf: Date? = nil) throws -> [String: MailCorrespondent] {
        let decoder = JSONDecoder()
        var found: [String: MailCorrespondent] = [:]
        let rows = try asOf.map { date in
            try Row.fetchAll(db, sql: #"SELECT "to", cc, date FROM mail_message WHERE labels LIKE '%"SENT"%' AND date <= ? ORDER BY date"#, arguments: [date])
        } ?? Row.fetchAll(db, sql: #"SELECT "to", cc, date FROM mail_message WHERE labels LIKE '%"SENT"%' ORDER BY date"#)
        for row in rows {
            // Read without a trap: a date that is no date, or people that are no text, are read as none.
            let date = Date.fromDatabaseValue(row["date"]) ?? .distantPast
            var seen: Set<String> = []
            for column in ["to", "cc"] {
                guard let text = String.fromDatabaseValue(row[column]), let people = try? decoder.decode([MailAddress].self, from: Data(text.utf8)) else { continue }
                for person in people {
                    let email = person.email.lowercased()
                    // One mail counts once for an address, in To and Cc alike.
                    guard seen.insert(email).inserted else { continue }
                    var known = found[email] ?? MailCorrespondent(sent: 0, lastAt: date)
                    known.sent += 1
                    known.lastAt = max(known.lastAt, date)
                    if let name = person.name, name.lowercased() != email { known.name = name }
                    found[email] = known
                }
            }
        }
        return found
    }

    // MARK: - A contact's mails (Contacts, 15/11)

    /// A message shown somewhere: neither in the trash, nor in the spam, nor a draft (`MailMessageRow.isAside`).
    private static let shownMessage = #"message.labels NOT LIKE '%"TRASH"%' AND message.labels NOT LIKE '%"SPAM"%' AND message.labels NOT LIKE '%"DRAFT"%'"#

    /// The people of a message's column, read by SQLite itself; a column that is not JSON reads as nobody.
    private static func people(_ column: String) -> String {
        "json_each(CASE WHEN json_valid(message.\(column)) THEN message.\(column) ELSE '[]' END)"
    }

    /// The threads this address took part in (who wrote, To or Cc of a message shown), the most recent first:
    /// the « Mails » of a contact's page. Every one of them: the page says how many.
    public func threads(with email: String) throws -> [MailThreadRow] {
        let email = email.lowercased()
        return try database.writer.read { db in
            let keys = try String.fetchAll(db, sql: """
                SELECT DISTINCT message.threadKey FROM mail_message AS message
                WHERE \(Self.shownMessage) AND (
                    lower(json_extract(CASE WHEN json_valid(message.sender) THEN message.sender END, '$.email')) = :email
                    OR EXISTS (SELECT 1 FROM \(Self.people("\"to\"")) WHERE lower(json_extract(value, '$.email')) = :email)
                    OR EXISTS (SELECT 1 FROM \(Self.people("cc")) WHERE lower(json_extract(value, '$.email')) = :email))
                """, arguments: ["email": email])
            guard !keys.isEmpty else { return [] }
            return try MailThreadRow.filter(keys: keys).filter(Column("hidden") == false).order(Column("lastMessageAt").desc).fetchAll(db)
        }
    }

    /// The date of the last message shown in which each address appears (who wrote, To or Cc), by lowercased
    /// address; only `emails` when given. One reading of the copy, for the list of the contacts.
    public func lastExchanges(with emails: Set<String>? = nil) throws -> [String: Date] {
        let rows = try database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT email, MAX(date) AS last FROM (
                    SELECT lower(json_extract(message.sender, '$.email')) AS email, message.date AS date FROM mail_message AS message
                    WHERE json_valid(message.sender) AND \(Self.shownMessage)
                    UNION ALL
                    SELECT lower(json_extract(value, '$.email')), message.date FROM mail_message AS message, \(Self.people("\"to\""))
                    WHERE \(Self.shownMessage)
                    UNION ALL
                    SELECT lower(json_extract(value, '$.email')), message.date FROM mail_message AS message, \(Self.people("cc"))
                    WHERE \(Self.shownMessage)
                ) WHERE email IS NOT NULL GROUP BY email
                """)
        }
        let wanted = emails.map { Set($0.map { $0.lowercased() }) }
        var result: [String: Date] = [:]
        for row in rows {
            guard let email: String = row["email"], wanted?.contains(email) ?? true, let date: Date = row["last"] else { continue }
            result[email] = date
        }
        return result
    }

    /// The projects Paul took each address out of: a gesture on many people never puts them back.
    static func excludedProjects(_ db: Database) throws -> [String: Set<UUID>] {
        var excluded: [String: Set<UUID>] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT contact.email AS email, contact_project.projectID AS projectID FROM contact_project
            JOIN contact ON contact.id = contact_project.contactID
            WHERE contact_project.excluded = 1 AND contact.email IS NOT NULL AND contact.deletedAt IS NULL
            """) {
            guard let email: String = row["email"], let id = (row["projectID"] as String?).flatMap(UUID.init(uuidString:)) else { continue }
            excluded[email.lowercased(), default: []].insert(id)
        }
        return excluded
    }
}

extension MailFilingRules {
    /// An address of one of Paul's own domains (his company's, never gmail.com): a colleague, who writes about
    /// every project. None of Paul's own addresses.
    public func isColleague(_ email: String) -> Bool {
        let address = email.lowercased()
        guard !mine.contains(address), let domain = PublicMailDomains.domain(of: address), !PublicMailDomains.all.contains(domain) else { return false }
        return mine.contains { PublicMailDomains.domain(of: $0) == domain }
    }
}
