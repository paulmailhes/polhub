import Foundation
import GRDB
import Testing
@testable import Persistence

/// Base v16 (18/11): each thread keeps who spoke last (the last message received, the last one of Paul's), and
/// hub keeps what Paul sets aside on the Accueil. The migration only adds columns and a table; the threads
/// already there get their turn right after it, in a pass of its own that can never keep the base shut. A helper
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
            // Several messages on each side: the last of each counts.
            try thread(db, "e")
            try message(db, "e1", thread: "e", hours: 10, sender: Self.client, labels: #"["INBOX"]"#)
            try message(db, "e2", thread: "e", hours: 11, sender: Self.client, labels: #"["INBOX"]"#)
            try message(db, "e3", thread: "e", hours: 12, sender: Self.mine, labels: #"["SENT"]"#)
            try message(db, "e4", thread: "e", hours: 13, sender: Self.mine, labels: #"["SENT"]"#)
            // A label that only looks like Gmail's own, in small letters, is not it.
            try thread(db, "f")
            try message(db, "f1", thread: "f", hours: 14, sender: Self.client, labels: #"["sent","trash"]"#)
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        let base = try AppDatabase(path: path)
        let hour = 3_600.0
        #expect(try turn(base, "a") == (now, now.addingTimeInterval(hour)))
        #expect(try turn(base, "b") == (nil, now.addingTimeInterval(2 * hour)))
        #expect(try turn(base, "c") == (now.addingTimeInterval(3 * hour), nil))
        #expect(try turn(base, "d") == (nil, nil))
        #expect(try turn(base, "e") == (now.addingTimeInterval(11 * hour), now.addingTimeInterval(13 * hour)))
        #expect(try turn(base, "f") == (now.addingTimeInterval(14 * hour), nil))
        // The threads read as records carry the same turn, and a change after the migration keeps them right.
        let mails = MailStore(base)
        let answered = try #require(try mails.thread("\(Self.me)|a"))
        #expect(answered.lastReceivedAt == now && answered.lastSentAt == now.addingTimeInterval(hour))
        try mails.apply(account: Self.me, upserts: [
            MailMessageRow(account: Self.me, messageID: "a3", threadID: "a", date: now.addingTimeInterval(9 * hour),
                           sender: MailAddress(name: "Camille Martin", email: "camille@exemple.fr"), subject: "Maquette", snippet: "extrait", labels: ["INBOX"]),
        ])
        #expect(try turn(base, "a") == (now.addingTimeInterval(9 * hour), now.addingTimeInterval(hour)))
        // Opened again, nothing is counted a second time: what the threads hold stays.
        try base.writer.write { try $0.execute(sql: "UPDATE mail_thread SET lastSentAt = NULL WHERE id = ?", arguments: ["\(Self.me)|b"]) }
        let again = try AppDatabase(path: path)
        #expect(try turn(again, "a") == (now.addingTimeInterval(9 * hour), now.addingTimeInterval(hour)))
        // A thread shown that lost its turn gets it back at the next opening.
        #expect(try turn(again, "b") == (nil, now.addingTimeInterval(2 * hour)))
    }

    @Test func aBaseStillAtV15ReadsItsThreads() throws {
        // `hub mcp` never migrates: on a base the app has not opened since its update, the threads still read.
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
        // threads keep an empty turn, and get it at the first opening where the count can be made.
        let (folder, path) = try baseAtV15 { db in
            try thread(db, "a")
            try message(db, "a1", thread: "a", hours: 0, sender: Self.client, labels: #"["INBOX"]"#)
            try db.execute(sql: "ALTER TABLE mail_message RENAME COLUMN labels TO etiquettes")
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            let base = try AppDatabase(path: path)
            #expect(try turn(base, "a") == (nil, nil))
            #expect(try base.writer.read { try $0.tableExists("colin_dismissal") })
            #expect(try base.writer.read { try AppDatabase.migrator.appliedIdentifiers($0).contains("v16") })
            try base.writer.write { try $0.execute(sql: "ALTER TABLE mail_message RENAME COLUMN etiquettes TO labels") }
        }
        let healed = try AppDatabase(path: path)
        #expect(try turn(healed, "a") == (now, nil))
    }

    @Test func aCountThatDropsTheWholeTransactionNeverKeepsTheBaseShut() throws {
        // The worst a count can do: SQLite itself drops the transaction it runs in (a disk that fills, here a
        // trigger). The migration has its own transaction, already kept: the base opens, at v16.
        let (folder, path) = try baseAtV15 { db in
            try thread(db, "a")
            try message(db, "a1", thread: "a", hours: 0, sender: Self.client, labels: #"["INBOX"]"#)
            try db.execute(sql: "CREATE TRIGGER casse BEFORE UPDATE ON mail_thread BEGIN SELECT RAISE(ROLLBACK, 'plus de place'); END")
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            let base = try AppDatabase(path: path)
            #expect(try base.writer.read { try AppDatabase.migrator.appliedIdentifiers($0).contains("v16") })
            #expect(try base.writer.read { try $0.tableExists("colin_dismissal") })
            #expect(try turn(base, "a") == (nil, nil))
            // The base works: what Paul sets aside is kept.
            try ColinStore(base).dismiss(ColinDismissalRow(kind: "reply", subject: "\(Self.me)|a", reason: .notNeeded, createdAt: now))
            try base.writer.write { try $0.execute(sql: "DROP TRIGGER casse") }
        }
        let healed = try AppDatabase(path: path)
        #expect(try turn(healed, "a") == (now, nil))
        #expect(try ColinStore(healed).dismissals().count == 1)
    }

    @Test func aCountThatFailsMidwayWritesNothing() throws {
        // The second thread makes the count fail: no thread keeps half a count, and the base opens.
        let (folder, path) = try baseAtV15 { db in
            for id in ["a", "b", "c"] {
                try thread(db, id)
                try message(db, "\(id)1", thread: id, hours: 0, sender: Self.client, labels: #"["INBOX"]"#)
            }
            try db.execute(sql: "CREATE TRIGGER casse BEFORE UPDATE ON mail_thread WHEN NEW.id = '\(Self.me)|b' BEGIN SELECT RAISE(ABORT, 'non'); END")
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        let base = try AppDatabase(path: path)
        for id in ["a", "b", "c"] { #expect(try turn(base, id) == (nil, nil), "\(id)") }
        #expect(try base.writer.read { try AppDatabase.migrator.appliedIdentifiers($0).contains("v16") })
    }

    @Test func aRowLeftWithoutItsParentDoesNotKeepTheBaseShut() throws {
        // A tool that does not check the links between tables left a message whose thread is gone. The migration
        // only adds columns and a table: it has no reason to look at that row, and the base opens.
        let (folder, path) = try baseAtV15 { db in
            try thread(db, "a")
            try message(db, "a1", thread: "a", hours: 0, sender: Self.client, labels: #"["INBOX"]"#)
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            var configuration = Configuration()
            configuration.foreignKeysEnabled = false
            let loose = try DatabaseQueue(path: path, configuration: configuration)
            try loose.write { db in try message(db, "x1", thread: "parti", hours: 0, sender: Self.client, labels: #"["INBOX"]"#) }
        }
        let base = try AppDatabase(path: path)
        #expect(try base.writer.read { try AppDatabase.migrator.appliedIdentifiers($0).contains("v16") })
        #expect(try turn(base, "a") == (now, nil))
    }

    @Test func aDateThatIsNoDateLeavesTheThreadsReadable() throws {
        // Not a row the app writes. Copied as it is into the thread, it would make every list of threads fail:
        // the turn stays empty instead.
        let (folder, path) = try baseAtV15 { db in
            try thread(db, "a")
            try message(db, "a1", thread: "a", hours: 0, sender: Self.client, labels: #"["INBOX"]"#)
            try thread(db, "b")
            try db.execute(sql: """
                INSERT INTO mail_message (id, account, messageID, threadKey, date, sender, "to", cc, subject, snippet, labels, authenticated, hasBody, bodyIsHTML, attachments)
                VALUES ('moi@exemple.fr|b1', 'moi@exemple.fr', 'b1', 'moi@exemple.fr|b', '0 pas une date', NULL, '[]', '[]', 'Maquette', 'extrait', '["INBOX"]', 0, 0, 0, '[]')
                """)
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        let base = try AppDatabase(path: path)
        #expect(try turn(base, "a") == (now, nil))
        let threads = try MailStore(base).allThreads()
        #expect(threads.count == 2)
        #expect(threads.first { $0.threadID == "b" }?.lastReceivedAt == nil)
    }

    @Test func whatPaulSetsAsideHasItsTable() throws {
        let (folder, path) = try baseAtV15 { _ in }
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(try AppDatabase.forTools(path: path).writer.read { try !$0.tableExists("colin_dismissal") })
        let base = try AppDatabase(path: path)
        let columns = try base.writer.read { try $0.columns(in: "colin_dismissal").map(\.name).sorted() }
        #expect(columns == ["createdAt", "id", "kind", "lastMessageAt", "projectID", "reason", "subject", "times"])
        // The copy of the base made before the migration is named after it.
        let backups = try FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "Sauvegardes").path(percentEncoded: false))
        #expect(backups.contains { $0.hasPrefix("hub-board-avant-v16-") })
    }
}
