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
        try database.writer.read(Self.correspondentStats)
    }

    /// One reading of what Paul sent, in date order: the count, the last date and the last name of each address.
    static func correspondentStats(_ db: Database) throws -> [String: MailCorrespondent] {
        let decoder = JSONDecoder()
        var found: [String: MailCorrespondent] = [:]
        for row in try Row.fetchAll(db, sql: #"SELECT "to", cc, date FROM mail_message WHERE labels LIKE '%"SENT"%' ORDER BY date"#) {
            let date: Date = row["date"] ?? .distantPast
            var seen: Set<String> = []
            for column in ["to", "cc"] {
                guard let text: String = row[column], let people = try? decoder.decode([MailAddress].self, from: Data(text.utf8)) else { continue }
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
