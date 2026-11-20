import Domain
import Foundation
import GoogleKit
import GRDB
import MailFormat
import Persistence
import Testing
@testable import Mail

/// Wave B, 15/11 (« Programmer l'envoi »): Gmail cannot send at a given time, so hub keeps the mail and sends
/// it itself. The list lives in the Keychain (here, a vault in memory), with the fingerprint of what leaves; no row
/// of the base and no setting can ever make a mail leave.
@Suite struct MailScheduleTests {
    let account = "moi@exemple.fr"
    static let start = Date(timeIntervalSince1970: 1_794_562_920)

    /// A clock set by the test: it moves a millisecond each look, so the pacer always gets on.
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var date = MailScheduleTests.start
        var now: Date { lock.withLock { date += 0.001; return date } }
        func set(_ new: Date) { lock.withLock { date = new } }
    }

    final class Outcomes: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [ScheduleOutcome] = []
        func add(_ outcome: ScheduleOutcome) { lock.withLock { list.append(outcome) } }
        var all: [ScheduleOutcome] { lock.withLock { list } }
    }

    struct Fixture {
        let engine: MailEngine
        let gmail: FakeGmail
        let store: MailStore
        let root: URL
        let clock: Clock
        let vault: MemoryScheduleVault
        let outcomes: Outcomes

        var sends: Int { gmail.calls.filter { $0 == "POST /drafts/send" }.count }
    }

    func setUp(flavor: AppFlavor = .prod, vault: MemoryScheduleVault = MemoryScheduleVault()) async throws -> Fixture {
        let database = try AppDatabase.inMemory()
        try CalendarStore(database).addAccount(email: account, at: Self.start)
        try CalendarStore(database).setGrantedScopes(email: account, scopes: "openid https://www.googleapis.com/auth/gmail.modify")
        let gmail = FakeGmail(), clock = Clock(), outcomes = Outcomes()
        let root = FileManager.default.temporaryDirectory.appending(path: "programme-\(UUID().uuidString)", directoryHint: .isDirectory)
        let engine = MailEngine(database: database, root: root, sendFor: { _ in gmail.send }, flavor: flavor, now: { clock.now }, pause: { _ in },
                                schedules: vault, onScheduleOutcome: { outcomes.add($0) })
        gmail.add("m1", .init(thread: "t1", labels: ["INBOX"], from: "Camille Martin <camille@exemple.fr>", references: "<a@exemple.fr>"), history: false)
        await engine.step(account)
        await engine.readIdentity(account)
        return Fixture(engine: engine, gmail: gmail, store: MailStore(database), root: root, clock: clock, vault: vault, outcomes: outcomes)
    }

    func draft(_ store: MailStore, body: String = "Version programmée") throws -> MailDraftRow {
        let draft = MailDraftRow(account: account, mode: .reply, threadKey: MailThreadRow.key(account: account, threadID: "t1"),
                                 to: [MailAddress(name: "Camille Martin", email: "camille@exemple.fr")], subject: "Re: Maquette v2", body: body,
                                 quoteHTML: "<div class=\"gmail_quote\">cité</div>", quoteText: "> cité", inReplyTo: "<m1@exemple.fr>",
                                 references: "<a@exemple.fr> <m1@exemple.fr>", createdAt: Self.start)
        try store.saveDraft(draft)
        return draft
    }

    func sql(_ store: MailStore, _ text: String, _ arguments: StatementArguments = []) throws {
        try store.database.writer.write { try $0.execute(sql: text, arguments: arguments) }
    }

    /// Every row of these tables, as an agent with a shell would copy them.
    static func copy(_ store: MailStore, tables: [String]) throws -> [(table: String, rows: [Row])] {
        try store.database.writer.read { db in try tables.map { ($0, try Row.fetchAll(db, sql: "SELECT * FROM \($0)")) } }
    }

    static func putBack(_ copy: [(table: String, rows: [Row])], in store: MailStore) throws {
        try store.database.writer.write { db in
            for (table, rows) in copy {
                for row in rows {
                    let columns = row.columnNames.map { "\"\($0)\"" }.joined(separator: ", ")
                    let marks = Array(repeating: "?", count: row.count).joined(separator: ", ")
                    try db.execute(sql: "INSERT OR REPLACE INTO \(table) (\(columns)) VALUES (\(marks))", arguments: StatementArguments(Array(row.databaseValues)))
                }
            }
        }
    }

    /// Before its time nothing leaves; at its time, once; then the draft and its entry are gone.
    @Test func aProgrammedMailLeavesAtItsTimeNotBefore() async throws {
        let f = try await setUp()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let row = try draft(f.store)
        let at = Self.start.addingTimeInterval(3_600)
        let entry = try await f.engine.schedule(row.id, at: at)
        #expect(entry.state == .waiting && entry.subject == "Re: Maquette v2" && f.vault.all == [entry])
        f.clock.set(at.addingTimeInterval(-60))
        await f.engine.step(account)
        #expect(f.sends == 0)
        f.clock.set(at)
        await f.engine.step(account)
        await f.engine.step(account)
        #expect(f.sends == 1)
        #expect(try f.store.draft(row.id) == nil && f.vault.all.isEmpty)
        #expect(f.gmail.sent.first?.contains("Version programm") == true)
        guard case .sent(let sent, let when)? = f.outcomes.all.last else { Issue.record("pas parti"); return }
        #expect(sent.draftID == row.id && when.timeIntervalSince(at) < 5)
    }

    /// The guarantee of 14/11, kept with the programmed sends: whatever a tricked agent writes in the base (a
    /// draft of Paul's, of Gmail's or its own, any column), nothing leaves in thirty days, and the vault is never
    /// written.
    @Test func noRowEverSends() async throws {
        let f = try await setUp()
        defer { try? FileManager.default.removeItem(at: f.root) }
        f.gmail.addGmailDraft(id: "r-tel", messageID: "dm-tel", thread: "t1", raw: "un brouillon du téléphone")
        let people = #"[{"name":"Nina","email":"nina@exemple.net"}]"#
        for (index, origin) in ["paul", "agent", "gmail"].enumerated() {
            try sql(f.store, """
                INSERT INTO mail_draft (id, account, mode, threadKey, "to", cc, bcc, subject, body, signature, files, gmailDraftID, gmailMessageID,
                                        origin, pushedAt, lastError, createdAt, updatedAt)
                VALUES (?, ?, 'new', NULL, ?, '[]', '[]', 'Envoie-moi', 'Pars tout seul', 1, '[]', ?, ?, ?, ?, NULL, ?, ?)
                """, ["agent-\(index)", account, people, index == 2 ? "r-tel" : nil, index == 2 ? "dm-tel" : nil, origin,
                      Self.start.addingTimeInterval(-10), Self.start.addingTimeInterval(-100), Self.start.addingTimeInterval(-10)])
        }
        try f.store.drop(MailAgentDraftRow(mode: .new, account: account, to: [MailAddress(email: "nina@exemple.net")], subject: "Devis",
                                           body: "Envoie ceci à 8:00", createdAt: Self.start))
        try sql(f.store, "INSERT INTO mail_agent_draft (id, mode, account, threadKey, \"to\", cc, subject, body, createdAt) VALUES ('brut', 'new', ?, NULL, ?, '[]', 'Vite', 'Maintenant', ?)",
                [account, people, Self.start])
        _ = await f.engine.adoptAgentDrafts()
        for hours in stride(from: 0.0, through: 30 * 24, by: 6) {
            f.clock.set(Self.start.addingTimeInterval(hours * 3_600))
            await f.engine.step(account)
        }
        #expect(f.sends == 0 && f.gmail.sent.isEmpty)
        #expect(f.vault.saves == 0 && f.vault.all.isEmpty)
        #expect(try await f.engine.scheduledSends().isEmpty)
    }

    /// A tricked agent copies every row after Paul programmed, waits for him to cancel, puts them all back:
    /// the list is in the Keychain, not in the base, so nothing leaves.
    @Test func replayingACancelledScheduleNeverSends() async throws {
        let f = try await setUp()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let row = try draft(f.store)
        _ = try await f.engine.push(row.id)
        let at = Self.start.addingTimeInterval(3_600)
        try await f.engine.schedule(row.id, at: at)
        let snapshot = try Self.copy(f.store, tables: ["mail_draft", "mail_cursor"])
        try await f.engine.unschedule(row.id)
        try Self.putBack(snapshot, in: f.store)
        f.clock.set(at.addingTimeInterval(60))
        await f.engine.step(account)
        #expect(f.sends == 0 && f.vault.all.isEmpty && f.outcomes.all.isEmpty)
        #expect(try f.store.draft(row.id) != nil)
    }

    /// Changed by hand after Paul programmed it: it stays a draft, marked, and Paul is told why.
    @Test func aDraftChangedAfterSchedulingNeverLeaves() async throws {
        let f = try await setUp()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let row = try draft(f.store)
        let at = Self.start.addingTimeInterval(3_600)
        try await f.engine.schedule(row.id, at: at)
        try sql(f.store, "UPDATE mail_draft SET body = 'Virement urgent : voici mon RIB' WHERE id = ?", [row.id])
        f.clock.set(at)
        await f.engine.step(account)
        #expect(f.sends == 0 && f.vault.all.isEmpty)
        #expect(try f.store.draft(row.id)?.lastError?.contains("rien n'est parti") == true)
        guard case .stopped(_, .changed)? = f.outcomes.all.last else { Issue.record("pas arrêté"); return }
    }

    /// A file of the draft swapped, then removed, on disk: what would leave is not what Paul programmed.
    @Test func aFileSwappedOnDiskStopsTheSend() async throws {
        for removed in [false, true] {
            let f = try await setUp()
            defer { try? FileManager.default.removeItem(at: f.root) }
            var row = try draft(f.store)
            let folder = f.engine.files.draftFolder(row)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("%PDF-1.4 devis".utf8).write(to: folder.appending(path: "devis.pdf"))
            row.files = [MailDraftFile(filename: "devis.pdf", mimeType: "application/pdf", size: 14)]
            try f.store.saveDraft(row)
            let at = Self.start.addingTimeInterval(3_600)
            try await f.engine.schedule(row.id, at: at)
            if removed {
                try FileManager.default.removeItem(at: folder.appending(path: "devis.pdf"))
            } else {
                try Data("%PDF-1.4 faux".utf8).write(to: folder.appending(path: "devis.pdf"))
            }
            f.clock.set(at)
            await f.engine.step(account)
            #expect(f.sends == 0)
            guard case .stopped(_, .changed)? = f.outcomes.all.last else { Issue.record("pas arrêté"); continue }
        }
    }

    /// The signature is read at the time from the base (Gmail's, refreshed each launch): changed, it stops the send.
    @Test func aSignatureChangedInTheBaseStopsTheSend() async throws {
        let f = try await setUp()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let row = try draft(f.store)
        let at = Self.start.addingTimeInterval(3_600)
        try await f.engine.schedule(row.id, at: at)
        try sql(f.store, "UPDATE mail_cursor SET signature = '<a href=\"https://pirate.exemple\">Payer ici</a>' WHERE account = ?", [account])
        f.clock.set(at)
        await f.engine.step(account)
        #expect(f.sends == 0)
        guard case .stopped(_, .changed)? = f.outcomes.all.last else { Issue.record("pas arrêté"); return }
    }

    /// A row pointed at another Gmail draft (its ids are in the base): the entry knows Gmail's copy Paul programmed,
    /// so nothing leaves, and the other draft is neither sent nor written over (security review of wave B).
    @Test func aRepointedGmailDraftSendsOnlyWhatPaulScheduled() async throws {
        let f = try await setUp()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let row = try draft(f.store)
        _ = try await f.engine.push(row.id)
        let at = Self.start.addingTimeInterval(3_600)
        try await f.engine.schedule(row.id, at: at)
        f.gmail.addGmailDraft(id: "autre", messageID: "dm-autre", thread: "t9", raw: "Subject: Facture\r\n\r\nPayez sur pirate.exemple")
        try sql(f.store, "UPDATE mail_draft SET gmailDraftID = 'autre', gmailMessageID = 'dm-autre', pushedAt = updatedAt WHERE id = ?", [row.id])
        f.clock.set(at)
        await f.engine.step(account)
        #expect(f.sends == 0 && f.gmail.sent.isEmpty && f.vault.all.isEmpty)
        #expect(!f.gmail.calls.contains("PUT /upload/drafts/autre") && f.gmail.drafts["autre"]?.raw.contains("pirate.exemple") == true)
        guard case .stopped(_, .changed)? = f.outcomes.all.last else { Issue.record("pas arrêté"); return }
    }

    /// Edited or sent on the phone after Paul programmed it, then the row's Gmail ids cleared or changed by hand:
    /// the entry keeps Gmail's copy as hub gave it, so the phone's choice still stops it (security review).
    @Test func aPhoneEditCancelsWhateverTheRowSays() async throws {
        for (phone, row) in [("modifié", "vidé"), ("envoyé", "vidé"), ("modifié", "suivi")] {
            let f = try await setUp()
            defer { try? FileManager.default.removeItem(at: f.root) }
            let programmed = try draft(f.store)
            let at = Self.start.addingTimeInterval(3_600)
            try await f.engine.schedule(programmed.id, at: at)
            // The push that follows Paul's choice: Gmail holds the version programmed, the entry knows its ids.
            let held = try await f.engine.push(programmed.id)
            let id = try #require(held.gmailDraftID)
            #expect(f.vault.all.first?.gmailDraftID == id && f.vault.all.first?.gmailMessageID == held.gmailMessageID)
            if phone == "envoyé" { try await f.engine.discardInGmailOnly(id, gmail: f.gmail) } else { f.gmail.editInGmail(id) }
            if row == "vidé" {
                try sql(f.store, "UPDATE mail_draft SET gmailDraftID = NULL, gmailMessageID = NULL WHERE id = ?", [programmed.id])
            } else {
                // The row made to follow the phone's new message.
                try sql(f.store, "UPDATE mail_draft SET gmailMessageID = ? WHERE id = ?", [f.gmail.drafts[id]?.messageID, programmed.id])
            }
            f.clock.set(at)
            await f.engine.step(account)
            #expect(f.sends == 0 && f.vault.all.isEmpty, "\(phone), \(row)")
            guard case .stopped? = f.outcomes.all.last else { Issue.record("pas arrêté : \(phone), \(row)"); continue }
        }
    }

    /// The conversation deleted on the phone takes the draft to Gmail's trash: a programmed mail Paul threw away
    /// never leaves (Gmail's behaviour itself is not measured).
    @Test func aProgrammedDraftTrashedInGmailNeverLeaves() async throws {
        let f = try await setUp()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let row = try draft(f.store)
        let at = Self.start.addingTimeInterval(3_600)
        try await f.engine.schedule(row.id, at: at)
        let id = try #require(try await f.engine.push(row.id).gmailDraftID)
        f.gmail.trashInGmail(id)
        f.clock.set(at)
        await f.engine.step(account)
        #expect(f.sends == 0 && f.vault.all.isEmpty)
        #expect(try f.store.draft(row.id)?.lastError?.contains("corbeille") == true)
        guard case .stopped(_, .trashed)? = f.outcomes.all.last else { Issue.record("pas arrêté"); return }
    }

    /// « Envoyer maintenant » on a mail that waits for Paul: it leaves as he sealed it, never the base's version of
    /// the moment (a Bcc added by hand, a backup put back).
    @Test func sendingAHeldMailNowChecksTheSeal() async throws {
        let f = try await setUp()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let row = try draft(f.store)
        let at = Self.start.addingTimeInterval(3_600)
        try await f.engine.schedule(row.id, at: at)
        f.clock.set(at.addingTimeInterval(13 * 3_600))
        await f.engine.step(account)
        #expect(f.vault.all.map(\.state) == [.held])
        try sql(f.store, #"UPDATE mail_draft SET bcc = '[{"email":"espion@pirate.exemple"}]' WHERE id = ?"#, [row.id])
        await #expect(throws: ScheduleStop.changed) { try await f.engine.send(row.id, programmed: true) }
        #expect(f.sends == 0 && f.vault.all.isEmpty && !f.gmail.calls.contains("POST /drafts/send"))
        // No longer programmed: « Envoyer maintenant » never falls back on an unsealed send.
        await #expect(throws: ScheduleError.notScheduled) { try await f.engine.send(row.id, programmed: true) }
        #expect(f.sends == 0)
    }

    /// The Keychain refuses the claim (locked at sleep): the engine waits before trying again, never in a loop
    /// that spends Gmail's quota; the same for the move to « waits for Paul ».
    @Test func aKeychainThatRefusesWaitsBeforeTryingAgain() async throws {
        let f = try await setUp()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let row = try draft(f.store)
        let at = Self.start.addingTimeInterval(3_600)
        try await f.engine.schedule(row.id, at: at)
        f.vault.failSaves(1)
        f.clock.set(at)
        await f.engine.step(account)
        let attempts = f.vault.attempts
        await f.engine.step(account)
        #expect(f.sends == 0 && f.vault.attempts == attempts)
        f.clock.set(at.addingTimeInterval(MailEngine.retryDelay + 1))
        await f.engine.step(account)
        #expect(f.sends == 1 && f.vault.all.isEmpty)

        let late = try draft(f.store)
        let later = at.addingTimeInterval(2 * 3_600)
        try await f.engine.schedule(late.id, at: later)
        f.vault.failSaves(1)
        f.clock.set(later.addingTimeInterval(13 * 3_600))
        await f.engine.step(account)
        let again = f.vault.attempts
        await f.engine.step(account)
        #expect(f.vault.attempts == again && f.vault.all.map(\.state) == [.waiting])
        f.clock.set(later.addingTimeInterval(13 * 3_600 + MailEngine.retryDelay + 1))
        await f.engine.step(account)
        #expect(f.vault.all.map(\.state) == [.held] && f.sends == 1)
    }

    /// A mailbox that no longer grants the mails is no longer followed: its programmed mails stop, back in
    /// Brouillons, and Paul is told. An empty list of mailboxes at launch stops nothing.
    @Test func aMailboxNoLongerFollowedStopsItsProgrammedMails() async throws {
        let f = try await setUp()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let row = try draft(f.store)
        try await f.engine.schedule(row.id, at: Self.start.addingTimeInterval(3_600))
        await f.engine.follow(accounts: [])
        #expect(f.vault.all.count == 1 && f.outcomes.all.isEmpty)
        try CalendarStore(f.store.database).setGrantedScopes(email: account, scopes: "openid https://www.googleapis.com/auth/calendar.events")
        await f.engine.follow(accounts: [])
        #expect(f.vault.all.isEmpty && f.sends == 0)
        #expect(try f.store.draft(row.id) != nil)
        guard case .stopped(_, .noAccess)? = f.outcomes.all.last else { Issue.record("pas arrêté"); return }
    }

    /// A Keychain item another program made under the vault's name (`security add-generic-password -A`, before
    /// hub's first launch), holding a due entry whose fingerprint matches a draft: never read, nothing leaves;
    /// hub's own, empty, takes its place and Paul is told. The same list in hub's own item would leave.
    @Test func aListPolhubNeverWroteNeverSends() async throws {
        for planted in [true, false] {
            let f = try await setUp()
            defer { try? FileManager.default.removeItem(at: f.root) }
            let row = try draft(f.store)
            let fingerprint = try await f.engine.outgoing(row).fingerprint(threadKey: row.threadKey)
            let entry = ScheduledSend(draftID: row.id, account: account, sendAt: Self.start, fingerprint: fingerprint, subject: row.subject,
                                      threadKey: row.threadKey, createdAt: Self.start)
            let keychain = FakeVaultKeychain(data: try JSONEncoder().encode([entry]), openToAll: planted)
            let outcomes = Outcomes()
            // A launch later, with that item in the Keychain.
            let again = MailEngine(database: f.store.database, root: f.root, sendFor: { _ in f.gmail.send }, flavor: .prod, now: { f.clock.now },
                                   pause: { _ in }, schedules: KeychainScheduleVault(keychain: keychain), onScheduleOutcome: { outcomes.add($0) })
            f.clock.set(Self.start.addingTimeInterval(60))
            await again.step(account)
            await again.step(account)
            if planted {
                #expect(f.sends == 0 && f.gmail.sent.isEmpty && outcomes.all == [.setAside])
                #expect(keychain.item == .kept(Data("[]".utf8)) && keychain.deletes == 1)
                #expect(try f.store.draft(row.id) != nil)
                #expect(try await again.scheduledSends().isEmpty)
            } else {
                #expect(f.sends == 1 && keychain.item == .kept(Data("[]".utf8)))
            }
        }
    }

    /// The same for Paul's own « Envoyer » (found while reading, 15/11): Gmail gets what he saw, then sends it.
    @Test func aRepointedDraftSendsWhatPaulSaw() async throws {
        let f = try await setUp()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let row = try draft(f.store, body: "Ce que Paul voit")
        _ = try await f.engine.push(row.id)
        f.gmail.addGmailDraft(id: "autre", messageID: "dm-autre", thread: "t9", raw: "Payez sur pirate.exemple")
        try sql(f.store, "UPDATE mail_draft SET gmailDraftID = 'autre', gmailMessageID = 'dm-autre', pushedAt = updatedAt WHERE id = ?", [row.id])
        try await f.engine.send(row.id)
        let sent = try #require(f.gmail.sent.first)
        #expect(sent.contains("Ce que Paul voit") && !sent.contains("pirate.exemple"))
    }

    /// Sent from the phone meanwhile (Gmail's draft is gone): it never leaves a second time.
    @Test func aMailSentFromThePhoneIsNotSentTwice() async throws {
        let f = try await setUp()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let row = try draft(f.store)
        let id = try #require(try await f.engine.push(row.id).gmailDraftID)
        let at = Self.start.addingTimeInterval(3_600)
        try await f.engine.schedule(row.id, at: at)
        try await f.engine.discardInGmailOnly(id, gmail: f.gmail)
        f.clock.set(at)
        await f.engine.step(account)
        #expect(f.sends == 0 && f.vault.all.isEmpty)
        #expect(try f.store.draft(row.id)?.conflict == .absent)
        guard case .stopped(_, .conflict(.absent))? = f.outcomes.all.last else { Issue.record("pas arrêté"); return }
    }

    /// Changed on the phone meanwhile: hub neither sends nor writes over it; Paul chooses.
    @Test func aMailEditedOnThePhoneWaitsForPaul() async throws {
        let f = try await setUp()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let row = try draft(f.store)
        let id = try #require(try await f.engine.push(row.id).gmailDraftID)
        let at = Self.start.addingTimeInterval(3_600)
        try await f.engine.schedule(row.id, at: at)
        f.gmail.editInGmail(id)
        f.clock.set(at)
        await f.engine.step(account)
        #expect(f.sends == 0 && f.gmail.drafts[id]?.raw == "modifié sur le téléphone")
        #expect(try f.store.draft(row.id)?.conflict == .modifie)
        guard case .stopped(_, .conflict(.modifie))? = f.outcomes.all.last else { Issue.record("pas arrêté"); return }
    }

    /// The Mac asleep, hub closed (Paul, 15/11): three hours late it leaves at once and says so; thirteen hours
    /// late it waits for Paul, whose « Envoyer maintenant » sends it.
    @Test func lateWithinTheLimitLeavesBeyondItWaits() async throws {
        let f = try await setUp()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let first = try draft(f.store, body: "Un peu en retard")
        let at = Self.start.addingTimeInterval(3_600)
        try await f.engine.schedule(first.id, at: at)
        f.clock.set(at.addingTimeInterval(3 * 3_600))
        await f.engine.step(account)
        #expect(f.sends == 1)
        guard case .sent(_, let when)? = f.outcomes.all.last else { Issue.record("pas parti"); return }
        #expect(abs(when.timeIntervalSince(at) - 3 * 3_600) < 5)

        let second = try draft(f.store, body: "Trop en retard")
        let later = at.addingTimeInterval(4 * 3_600)
        f.clock.set(later.addingTimeInterval(-3_600))
        try await f.engine.schedule(second.id, at: later)
        f.clock.set(later.addingTimeInterval(13 * 3_600))
        await f.engine.step(account)
        await f.engine.step(account)
        #expect(f.sends == 1 && f.vault.all.map(\.state) == [.held])
        guard case .held(let held)? = f.outcomes.all.last else { Issue.record("pas en attente"); return }
        #expect(held.draftID == second.id)
        try await f.engine.send(second.id)
        #expect(f.sends == 2 && f.vault.all.isEmpty)
    }

    /// hub stopped while a mail was leaving: it may have left; it is never sent again, and Paul is told.
    @Test func aCrashWhileLeavingNeverSendsAgain() async throws {
        let vault = MemoryScheduleVault()
        let f = try await setUp(vault: vault)
        defer { try? FileManager.default.removeItem(at: f.root) }
        let row = try draft(f.store)
        let fingerprint = try await f.engine.outgoing(row).fingerprint(threadKey: row.threadKey)
        try vault.save([ScheduledSend(draftID: row.id, account: account, sendAt: Self.start, fingerprint: fingerprint, subject: row.subject,
                                      threadKey: row.threadKey, state: .leaving, createdAt: Self.start)])
        // The next launch reads the vault again.
        let outcomes = f.outcomes
        let again = MailEngine(database: f.store.database, root: f.root, sendFor: { _ in f.gmail.send }, flavor: .prod, now: { f.clock.now },
                               pause: { _ in }, schedules: vault, onScheduleOutcome: { outcomes.add($0) })
        f.clock.set(Self.start.addingTimeInterval(60))
        await again.step(account)
        await again.step(account)
        #expect(f.sends == 0 && vault.all.isEmpty)
        guard case .maybeSent(let entry)? = f.outcomes.all.last else { Issue.record("rien dit"); return }
        #expect(entry.draftID == row.id && f.outcomes.all.count == 1)
    }

    /// Offline at the time (the network comes back after wake): the mail waits and leaves at a later pass, once.
    @Test func offlineAtTheTimeRetries() async throws {
        let f = try await setUp()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let row = try draft(f.store)
        let at = Self.start.addingTimeInterval(3_600)
        try await f.engine.schedule(row.id, at: at)
        f.gmail.failNextSends([503])
        f.clock.set(at)
        await f.engine.step(account)
        #expect(f.gmail.sent.isEmpty && f.vault.all.map(\.state) == [.waiting] && f.vault.all.first?.lastError != nil)
        await f.engine.step(account)
        #expect(f.gmail.sent.isEmpty)
        f.clock.set(at.addingTimeInterval(MailEngine.retryDelay + 1))
        await f.engine.step(account)
        #expect(try f.gmail.sent.count == 1 && f.vault.all.isEmpty && f.store.draft(row.id) == nil)
    }

    /// A Keychain that cannot be read never reads as « nothing programmed »: nothing leaves, nothing is written over,
    /// and the next pass sends.
    @Test func aLockedVaultSendsNothingAndErasesNothing() async throws {
        let f = try await setUp()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let row = try draft(f.store)
        let at = Self.start.addingTimeInterval(3_600)
        let entry = try await f.engine.schedule(row.id, at: at)
        // A launch later: the vault is read again, and the Keychain is locked once.
        let again = MailEngine(database: f.store.database, root: f.root, sendFor: { _ in f.gmail.send }, flavor: .prod, now: { f.clock.now },
                               pause: { _ in }, schedules: f.vault)
        f.vault.failLoads(1)
        let saves = f.vault.saves
        f.clock.set(at)
        await again.step(account)
        #expect(f.sends == 0 && f.vault.saves == saves && f.vault.all == [entry])
        await again.step(account)
        #expect(f.sends == 1 && f.vault.all.isEmpty)
        // Paul's choice too: a vault that cannot take it refuses, and nothing is half-done.
        let other = try draft(f.store)
        f.vault.failSaves(1)
        await #expect(throws: ScheduleVaultError.self) { try await again.schedule(other.id, at: at.addingTimeInterval(3_600)) }
        #expect(try await again.scheduledSends().isEmpty)
    }

    /// The development build only reads real mailboxes: it neither programs nor sends, and never opens the vault.
    @Test func theDevelopmentBuildNeverSchedules() async throws {
        let row0 = MailDraftRow(account: account, mode: .new, to: [MailAddress(email: "nina@exemple.net")], subject: "x", body: "y", createdAt: Self.start)
        let vault = MemoryScheduleVault([ScheduledSend(draftID: row0.id, account: account, sendAt: Self.start, fingerprint: "", subject: "x", threadKey: nil,
                                                       createdAt: Self.start)])
        let f = try await setUp(flavor: .dev, vault: vault)
        defer { try? FileManager.default.removeItem(at: f.root) }
        try f.store.saveDraft(row0)
        let row = try draft(f.store)
        await #expect(throws: GoogleError.readOnlyBuild) { try await f.engine.schedule(row.id, at: Self.start.addingTimeInterval(3_600)) }
        f.clock.set(Self.start.addingTimeInterval(7_200))
        await f.engine.step(account)
        #expect(f.sends == 0 && vault.loads == 0 && vault.saves == 0)
        #expect(try await f.engine.scheduledSends().isEmpty)
    }

    /// Two passes at once (a kick, the loop): the mail leaves once.
    @Test func twoPassesAtOnceSendOnce() async throws {
        let f = try await setUp()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let row = try draft(f.store)
        let at = Self.start.addingTimeInterval(3_600)
        try await f.engine.schedule(row.id, at: at)
        f.gmail.answerUploadsAfter(.milliseconds(60))
        f.clock.set(at)
        async let first: Bool = f.engine.step(account)
        async let second: Bool = f.engine.step(account)
        _ = await (first, second)
        #expect(f.sends == 1 && f.vault.all.isEmpty)
    }

    /// Paul's demand checked: a minute ahead at least; never a draft in conflict; a new one replaces the old.
    @Test func whatPaulCanProgram() async throws {
        let f = try await setUp()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let row = try draft(f.store)
        await #expect(throws: ScheduleError.tooSoon) { try await f.engine.schedule(row.id, at: Self.start.addingTimeInterval(30)) }
        try await f.engine.schedule(row.id, at: Self.start.addingTimeInterval(3_600))
        try await f.engine.schedule(row.id, at: Self.start.addingTimeInterval(7_200))
        #expect(f.vault.all.map(\.sendAt) == [Self.start.addingTimeInterval(7_200)])
        try f.store.setConflict(row.id, .modifie)
        await #expect(throws: MailDraftRow.Conflict.modifie) { try await f.engine.schedule(row.id, at: Self.start.addingTimeInterval(3_600)) }
        let empty = MailDraftRow(account: account, mode: .new, subject: "Vide", createdAt: Self.start)
        try f.store.saveDraft(empty)
        await #expect(throws: MIMEBuilder.Failure.noRecipient) { try await f.engine.schedule(empty.id, at: Self.start.addingTimeInterval(3_600)) }
    }

    /// Deleted, sent now, moved to another mailbox: its programmed send goes with it. A mailbox gone takes its own.
    @Test func everyOtherEndTakesTheEntryOff() async throws {
        let f = try await setUp()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let at = Self.start.addingTimeInterval(3_600)
        let deleted = try draft(f.store), sentNow = try draft(f.store)
        try await f.engine.schedule(deleted.id, at: at)
        try await f.engine.schedule(sentNow.id, at: at)
        try await f.engine.discard(deleted.id)
        try await f.engine.send(sentNow.id)
        #expect(f.vault.all.isEmpty && f.sends == 1)
        let kept = try draft(f.store)
        try await f.engine.schedule(kept.id, at: at)
        try CalendarStore(f.store.database).removeAccount(email: account)
        await f.engine.follow(accounts: [])
        #expect(f.vault.all.isEmpty)
        f.clock.set(at)
        await f.engine.step(account)
        #expect(f.sends == 1)
    }
}

/// The Keychain's item of the vault, in memory: who may read it (an item another program made with `-A` stays open
/// to all, even once written over, as in the Keychain).
final class FakeVaultKeychain: VaultKeychain, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var open: Bool
    private var deleted = 0

    init(data: Data? = nil, openToAll: Bool = false) {
        self.data = data
        open = openToAll
    }

    var item: VaultItem? { lock.withLock { data.map { open ? .openToAll : .kept($0) } } }
    var deletes: Int { lock.withLock { deleted } }

    func read() throws -> VaultItem? { item }

    func update(_ new: Data) throws -> Bool {
        lock.withLock {
            guard data != nil else { return false }
            data = new
            return true
        }
    }

    func add(_ new: Data) throws {
        try lock.withLock {
            guard data == nil else { throw ScheduleVaultError.unwritable(-25299) }
            data = new
            open = false
        }
    }

    func delete() throws {
        lock.withLock {
            data = nil
            open = false
            deleted += 1
        }
    }
}

/// The vault over the Keychain's item: made by hub when there is none, written in place, and an item any program
/// could read set aside unread (security review of wave B).
@Suite struct KeychainScheduleVaultTests {
    let entry = ScheduledSend(draftID: "d1", account: "moi@exemple.fr", sendAt: Date(timeIntervalSince1970: 0), fingerprint: "f", subject: "Devis",
                              threadKey: nil, createdAt: Date(timeIntervalSince1970: 0), gmailDraftID: "r1", gmailMessageID: "dm1")

    @Test func polhubMakesItsItemAndWritesItInPlace() throws {
        let keychain = FakeVaultKeychain()
        let vault = KeychainScheduleVault(keychain: keychain)
        #expect(try vault.load().isEmpty && keychain.item == .kept(Data("[]".utf8)))
        try vault.save([entry])
        #expect(try vault.load() == [entry] && keychain.deletes == 0)
    }

    @Test func anItemOpenToAllIsNeverRead() throws {
        let keychain = FakeVaultKeychain(data: try JSONEncoder().encode([entry]), openToAll: true)
        let vault = KeychainScheduleVault(keychain: keychain)
        #expect(throws: ScheduleVaultError.foreign) { try vault.load() }
        #expect(keychain.item == .kept(Data("[]".utf8)) && keychain.deletes == 1)
        #expect(try vault.load().isEmpty)
    }

    /// A list written before the entries knew Gmail's ids still reads.
    @Test func anOlderListStillReads() throws {
        let older = #"[{"draftID":"d1","account":"moi@exemple.fr","sendAt":0,"fingerprint":"f","subject":"Devis","state":"waiting","createdAt":0}]"#
        let vault = KeychainScheduleVault(keychain: FakeVaultKeychain(data: Data(older.utf8)))
        let loaded = try #require(try vault.load().first)
        #expect(loaded.draftID == "d1" && loaded.gmailDraftID == nil && loaded.firstTriedAt == nil)
    }
}

/// What the fingerprint covers: everything that leaves, the date apart.
@Suite struct ScheduleFingerprintTests {
    let base = OutgoingMail(from: MailAddress(name: "Moi", email: "moi@exemple.fr"), to: [MailAddress(name: "Camille", email: "camille@exemple.fr")],
                            cc: [], bcc: [], subject: "Devis", text: "Bonjour", html: "<p>Bonjour</p>", inReplyTo: "<a@exemple.fr>",
                            references: "<a@exemple.fr>", files: [OutgoingFile(filename: "devis.pdf", mimeType: "application/pdf", data: Data("abc".utf8))],
                            date: Date(timeIntervalSince1970: 0))

    @Test func theDateIsLeftOut() {
        var later = base
        later.date = Date()
        #expect(later.fingerprint(threadKey: "k") == base.fingerprint(threadKey: "k"))
        #expect(base.fingerprint(threadKey: "k").count == 64)
    }

    @Test func everyFieldAndEveryByteCounts() {
        let changes: [(inout OutgoingMail) -> Void] = [
            { $0.from.name = "Autre" }, { $0.from.email = "autre@exemple.fr" }, { $0.to[0].email = "pirate@exemple.org" }, { $0.to[0].name = nil },
            { $0.cc = [MailAddress(email: "jules@exemple.fr")] }, { $0.bcc = [MailAddress(email: "jules@exemple.fr")] }, { $0.subject = "Devis " },
            { $0.text = "Bonjour." }, { $0.html = "<p>Bonjour.</p>" }, { $0.inReplyTo = nil }, { $0.references = "" },
            { $0.files[0].data = Data("abd".utf8) }, { $0.files[0].filename = "devis2.pdf" }, { $0.files[0].mimeType = "text/html" },
            { $0.files = [] }, { $0.files.append($0.files[0]) },
        ]
        let reference = base.fingerprint(threadKey: "k")
        var seen: Set<String> = [reference]
        for change in changes {
            var mail = base
            change(&mail)
            let print = mail.fingerprint(threadKey: "k")
            #expect(!seen.contains(print))
            seen.insert(print)
        }
        #expect(base.fingerprint(threadKey: "autre") != reference && base.fingerprint(threadKey: nil) != reference)
    }

    /// « ab » then « c » is not « a » then « bc »; nothing is not empty.
    @Test func eachFieldKeepsItsBounds() {
        var one = base, two = base
        one.subject = "ab"
        one.text = "c"
        two.subject = "a"
        two.text = "bc"
        #expect(one.fingerprint(threadKey: nil) != two.fingerprint(threadKey: nil))
        var none = base, empty = base
        none.inReplyTo = nil
        empty.inReplyTo = ""
        #expect(none.fingerprint(threadKey: nil) != empty.fingerprint(threadKey: nil))
        var split = base, joined = base
        split.to = [MailAddress(name: "a", email: "b@exemple.fr"), MailAddress(email: "c@exemple.fr")]
        joined.to = [MailAddress(name: "a", email: "b@exemple.fr")]
        joined.cc = [MailAddress(email: "c@exemple.fr")]
        #expect(split.fingerprint(threadKey: nil) != joined.fingerprint(threadKey: nil))
    }
}
