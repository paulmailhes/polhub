import Foundation
import GRDB
import Testing
@testable import Persistence

/// Base v16 (18/11): each thread keeps who spoke last (the last message received, the last one of Paul's), and
/// Polhub keeps what Paul sets aside on the Accueil. The threads already there get their turn in one pass. A helper
/// that never migrates still reads a base of before.
@Suite struct MigrationV16Tests {
    let now = Date(timeIntervalSince1970: 1_794_960_000)   // 18/11/2026
    static let me = "moi@exemple.fr"

    /// A base as the version before left it, with one mailbox; the caller removes its folder.
    func baseAtV15(_ fill: (Database) throws -> Void) throws -> (folder: URL, path: String) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-v16 \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appending(path: "Polhub.sqlite").path(percentEncoded: false)
        let queue = try DatabaseQueue(path: path)
        try AppDatabase.migrator.migrate(queue, upTo: "v15")
        try queue.write { db in
            try db.execute(sql: "INSERT INTO google_account (email, addedAt) VALUES (?, ?)", arguments: [Self.me, now])
            try fill(db)
        }
        return (folder, path)
    }

    func thread(_ db: Database, _ id: String) throws {
        try db.execute(sql: """
            INSERT INTO mail_thread (id, account, threadID, subject, snippet, senders, lastMessageAt, messageCount, unread, inInbox, hidden, hasAttachment, paulWrote)
            VALUES (?, ?, ?, 'Maquette', 'extrait', '[]', ?, 1, 0, 1, 0, 0, 0)
            """, arguments: ["\(Self.me)|\(id)", Self.me, id, now])
    }

    /// `sender` and `labels` as the base holds them: JSON text.
    func message(_ db: Database, _ id: String, thread: String, hours: Double, sender: String?, labels: String) throws {
        try db.execute(sql: """
            INSERT INTO mail_message (id, account, messageID, threadKey, date, sender, "to", cc, subject, snippet, labels, authenticated, hasBody, bodyIsHTML, attachments)
            VALUES (?, ?, ?, ?, ?, ?, '[]', '[]', 'Maquette', 'extrait', ?, 0, 0, 0, '[]')
            """, arguments: ["\(Self.me)|\(id)", Self.me, id, "\(Self.me)|\(thread)", now.addingTimeInterval(hours * 3_600), sender, labels])
    }

    static let client = #"{"name":"Camille Martin","email":"camille@exemple.fr"}"#
    static let mine = #"{"name":"Moi","email":"moi@exemple.fr"}"#

    func turn(_ base: AppDatabase, _ id: String) throws -> (received: Date?, sent: Date?) {
        try base.writer.read { db in
            let row = try #require(try Row.fetchOne(db, sql: "SELECT lastReceivedAt, lastSentAt FROM mail_thread WHERE id = ?", arguments: ["\(Self.me)|\(id)"]))
            return (row["lastReceivedAt"], row["lastSentAt"])
        }
    }

    @Test func everyThreadGetsItsTurn() throws {
        let (folder, path) = try baseAtV15 { db in
            // Received, then answered by Paul.
            try thread(db, "a")
            try message(db, "a1", thread: "a", hours: 0, sender: Self.client, labels: #"["INBOX","UNREAD"]"#)
            try message(db, "a2", thread: "a", hours: 1, sender: Self.mine, labels: #"["SENT"]"#)
            // Of Paul by his address alone, written in capitals.
            try thread(db, "b")
            try message(db, "b1", thread: "b", hours: 2, sender: #"{"email":"MOI@Exemple.fr"}"#, labels: #"["INBOX"]"#)
            // What is in the trash, in the spam, or a draft does not count.
            try thread(db, "c")
            try message(db, "c1", thread: "c", hours: 3, sender: Self.client, labels: #"["INBOX"]"#)
            try message(db, "c2", thread: "c", hours: 4, sender: Self.client, labels: #"["TRASH"]"#)
            try message(db, "c3", thread: "c", hours: 5, sender: Self.mine, labels: #"["DRAFT"]"#)
            try message(db, "c4", thread: "c", hours: 6, sender: Self.client, labels: #"["SPAM"]"#)
            // Everything aside: no turn at all.
            try thread(db, "d")
            try message(db, "d1", thread: "d", hours: 7, sender: Self.client, labels: #"["TRASH"]"#)
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        let base = try AppDatabase(path: path)
        let hour = 3_600.0
        #expect(try turn(base, "a") == (now, now.addingTimeInterval(hour)))
        #expect(try turn(base, "b") == (nil, now.addingTimeInterval(2 * hour)))
        #expect(try turn(base, "c") == (now.addingTimeInterval(3 * hour), nil))
        #expect(try turn(base, "d") == (nil, nil))
        // The threads read as records carry the same turn, and a change after the migration keeps them right.
        let mails = MailStore(base)
        let answered = try #require(try mails.thread("\(Self.me)|a"))
        #expect(answered.lastReceivedAt == now && answered.lastSentAt == now.addingTimeInterval(hour))
        try mails.apply(account: Self.me, upserts: [
            MailMessageRow(account: Self.me, messageID: "a3", threadID: "a", date: now.addingTimeInterval(9 * hour),
                           sender: MailAddress(name: "Camille Martin", email: "camille@exemple.fr"), subject: "Maquette", snippet: "extrait", labels: ["INBOX"]),
        ])
        #expect(try turn(base, "a") == (now.addingTimeInterval(9 * hour), now.addingTimeInterval(hour)))
    }

    @Test func aBaseStillAtV15ReadsItsThreads() throws {
        // `polhub mcp` never migrates: on a base the app has not opened since its update, the threads still read.
        let (folder, path) = try baseAtV15 { db in
            try thread(db, "a")
            try message(db, "a1", thread: "a", hours: 0, sender: Self.client, labels: #"["INBOX"]"#)
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        let mails = MailStore(try AppDatabase.forTools(path: path))
        let threads = try mails.allThreads()
        #expect(threads.map(\.threadID) == ["a"])
        #expect(threads.first?.lastReceivedAt == nil && threads.first?.lastSentAt == nil)
        #expect(try mails.readableThreads().count == 1)
        // The turns counted from the messages need nothing of v16.
        #expect(try mails.turns(asOf: now.addingTimeInterval(60))["\(Self.me)|a"] == MailTurn(lastReceivedAt: now, lastSentAt: nil))
    }

    @Test func rowsThatAreNotWhatTheyShouldBeDoNotStopTheMigration() throws {
        // A sender or labels that are not JSON, a sender that is no object, none at all: the base opens all the same.
        let (folder, path) = try baseAtV15 { db in
            try thread(db, "a")
            try message(db, "a1", thread: "a", hours: 0, sender: "pas du JSON", labels: #"["INBOX"]"#)
            try message(db, "a2", thread: "a", hours: 1, sender: nil, labels: "pas du JSON non plus")
            try message(db, "a3", thread: "a", hours: 2, sender: #"["un","tableau"]"#, labels: "")
            try message(db, "a4", thread: "a", hours: 3, sender: #"{"name":"sans adresse"}"#, labels: #"["SENT"]"#)
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        let base = try AppDatabase(path: path)
        // What can be told is told: the message marked as sent is Paul's, the others were received.
        #expect(try turn(base, "a") == (now.addingTimeInterval(2 * 3_600), now.addingTimeInterval(3 * 3_600)))
    }

    @Test func aTurnThatCannotBeCountedNeverKeepsTheBaseShut() throws {
        // Whatever makes the count fail (here, a column that is not where it should be): Paul's app must open. The
        // threads keep an empty turn, which fills as they change.
        let (folder, path) = try baseAtV15 { db in
            try thread(db, "a")
            try message(db, "a1", thread: "a", hours: 0, sender: Self.client, labels: #"["INBOX"]"#)
            try db.execute(sql: "ALTER TABLE mail_message RENAME COLUMN labels TO etiquettes")
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        let base = try AppDatabase(path: path)
        #expect(try turn(base, "a") == (nil, nil))
        #expect(try base.writer.read { try $0.tableExists("colin_dismissal") })
        #expect(try base.writer.read { try AppDatabase.migrator.appliedIdentifiers($0).contains("v16") })
    }

    @Test func whatPaulSetsAsideHasItsTable() throws {
        let (folder, path) = try baseAtV15 { _ in }
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(try AppDatabase.forTools(path: path).writer.read { try !$0.tableExists("colin_dismissal") })
        let base = try AppDatabase(path: path)
        let columns = try base.writer.read { try $0.columns(in: "colin_dismissal").map(\.name).sorted() }
        #expect(columns == ["createdAt", "id", "kind", "projectID", "reason", "subject"])
        // The copy of the base made before the migration is named after it.
        let backups = try FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "Sauvegardes").path(percentEncoded: false))
        #expect(backups.contains { $0.hasPrefix("Polhub-avant-v16-") })
    }
}
