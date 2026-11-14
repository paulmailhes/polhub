import Foundation
import GRDB

/// The local copy of the mailboxes (14/11): Gmail stays the reference, this copy follows it. Threads are
/// recomputed from their messages in the transaction that changes them.
public struct MailStore: Sendable {
    public let database: AppDatabase
    private var writer: any DatabaseWriter { database.writer }

    public init(_ database: AppDatabase) {
        self.database = database
    }

    // MARK: - Where the reading stands

    public func cursor(account: String) throws -> MailCursorRow? {
        try writer.read { try MailCursorRow.fetchOne($0, key: account.lowercased()) }
    }

    public func cursors() throws -> [MailCursorRow] {
        try writer.read { try MailCursorRow.fetchAll($0) }
    }

    public func save(_ cursor: MailCursorRow) throws {
        try writer.write { db in
            // The account may have been disconnected meanwhile: its cursor must not come back alone.
            guard try GoogleAccountRow.fetchOne(db, key: cursor.account) != nil else { return }
            try cursor.save(db)
        }
    }

    // MARK: - What Gmail says

    public func knownMessageIDs(account: String) throws -> Set<String> {
        try writer.read { try String.fetchSet($0, sql: "SELECT messageID FROM mail_message WHERE account = ?", arguments: [account.lowercased()]) }
    }

    /// The labels the copy holds for each message of a mailbox.
    public func labels(account: String) throws -> [String: [String]] {
        try writer.read { db in
            Dictionary(uniqueKeysWithValues: try MailMessageRow.filter(Column("account") == account.lowercased()).fetchAll(db).map { ($0.messageID, $0.labels) })
        }
    }

    /// Gmail's news for one mailbox: whole messages (new, or read again), labels of messages already known, and
    /// messages Gmail no longer has. The gestures still waiting are applied again on top: what Paul just did is
    /// never undone by a reading that started before.
    public func apply(account: String, upserts: [MailMessageRow] = [], labels: [String: [String]] = [:], removed: [String] = []) throws {
        let account = account.lowercased()
        try writer.write { db in
            guard try GoogleAccountRow.fetchOne(db, key: account) != nil else { return }
            let pending = try MailGestureRow.filter(Column("account") == account).order(Column("id")).fetchAll(db)
            func withGestures(_ labels: [String], messageID: String) -> [String] {
                pending.filter { $0.messageIDs.contains(messageID) }.reduce(labels) { $1.kind.apply(to: $0) }
            }
            var touched: Set<String> = []
            for var message in upserts {
                message.labels = withGestures(message.labels, messageID: message.messageID)
                if let known = try MailMessageRow.fetchOne(db, key: message.id) {
                    // A message read again keeps what only the app knows.
                    if !message.hasBody { message.hasBody = known.hasBody; message.bodyIsHTML = known.bodyIsHTML }
                    if message.attachments.isEmpty { message.attachments = known.attachments }
                }
                try ensureThread(db, key: message.threadKey, account: account, at: message.date)
                try message.save(db)
                touched.insert(message.threadKey)
            }
            for (messageID, fresh) in labels {
                guard var message = try MailMessageRow.fetchOne(db, key: MailMessageRow.key(account: account, messageID: messageID)) else { continue }
                message.labels = withGestures(fresh, messageID: messageID)
                try message.update(db)
                touched.insert(message.threadKey)
            }
            for messageID in removed {
                guard let message = try MailMessageRow.fetchOne(db, key: MailMessageRow.key(account: account, messageID: messageID)) else { continue }
                try message.delete(db)
                touched.insert(message.threadKey)
            }
            try refresh(db, threads: touched)
        }
    }

    /// A message needs its thread's row to exist; the real values come from `refresh`.
    private func ensureThread(_ db: Database, key: String, account: String, at date: Date) throws {
        guard try MailThreadRow.fetchOne(db, key: key) == nil else { return }
        try MailThreadRow(id: key, account: account, threadID: String(key.dropFirst(account.count + 1)), subject: "", snippet: "", senders: [],
                          lastMessageAt: date, messageCount: 0, unread: false, inInbox: false, hidden: true, hasAttachment: false,
                          category: nil, lastSender: nil, paulWrote: false).insert(db)
    }

    /// Threads recomputed from their messages; a thread without any message goes.
    private func refresh(_ db: Database, threads: Set<String>) throws {
        guard !threads.isEmpty else { return }
        let mine = try String.fetchSet(db, sql: "SELECT email FROM google_account")
        for key in threads {
            let messages = try MailMessageRow.filter(Column("threadKey") == key).fetchAll(db)
            guard let first = messages.first,
                  let thread = MailThreadRow.aggregate(account: first.account, threadID: String(key.dropFirst(first.account.count + 1)),
                                                       messages: messages, mine: mine)
            else {
                _ = try MailThreadRow.deleteOne(db, key: key)
                continue
            }
            try thread.save(db)
        }
    }

    /// The body of a message is now in its file.
    public func markBody(messageKey: String, isHTML: Bool, attachments: [MailAttachment]) throws {
        try writer.write { db in
            guard var message = try MailMessageRow.fetchOne(db, key: messageKey) else { return }
            message.hasBody = true
            message.bodyIsHTML = isHTML
            message.attachments = attachments
            try message.update(db)
            try refresh(db, threads: [message.threadKey])
        }
    }

    // MARK: - Reading the copy

    /// The inbox of these mailboxes, the most recent thread first.
    public func inbox(accounts: Set<String>? = nil) throws -> [MailThreadRow] {
        try writer.read { db in
            var request = MailThreadRow.filter(Column("hidden") == false && Column("inInbox") == true)
            if let accounts { request = request.filter(accounts.map { $0.lowercased() }.contains(Column("account"))) }
            return try request.order(Column("lastMessageAt").desc).fetchAll(db)
        }
    }

    public func thread(_ key: String) throws -> MailThreadRow? {
        try writer.read { try MailThreadRow.fetchOne($0, key: key) }
    }

    public func threads(keys: [String]) throws -> [MailThreadRow] {
        try writer.read { try MailThreadRow.filter(keys: keys).order(Column("lastMessageAt").desc).fetchAll($0) }
    }

    /// The messages of a thread, the oldest first; those in the trash or the spam are left out.
    public func messages(threadKey: String) throws -> [MailMessageRow] {
        try writer.read { try MailMessageRow.filter(Column("threadKey") == threadKey).order(Column("date")).fetchAll($0) }.filter { !$0.isAside }
    }

    public func message(_ key: String) throws -> MailMessageRow? {
        try writer.read { try MailMessageRow.fetchOne($0, key: key) }
    }

    // MARK: - Paul's gestures

    /// The gesture changes the copy at once and waits in the outbox for Gmail. It names the messages it touches
    /// now (or `messageIDs`, to undo a gesture exactly): a reply that arrives later is never carried along.
    @discardableResult
    public func enqueue(_ kind: MailGestureKind, threadKey: String, messageIDs: [String]? = nil, at date: Date) throws -> MailGestureRow? {
        try writer.write { db in
            let all = try MailMessageRow.filter(Column("threadKey") == threadKey).order(Column("date")).fetchAll(db)
            guard let account = all.first?.account else { return nil }
            let targets: [MailMessageRow]
            if let messageIDs {
                targets = all.filter { messageIDs.contains($0.messageID) }
            } else {
                let shown = all.filter { !$0.isAside }
                switch kind {
                case .archive: targets = shown.filter { $0.labels.contains("INBOX") }
                case .markRead: targets = shown.filter(\.isUnread)
                // As Gmail does: the last message becomes unread again.
                case .markUnread: targets = Array(shown.suffix(1))
                case .trash, .spam: targets = shown
                case .unarchive: targets = Array(shown.suffix(1))
                case .untrash: targets = all.filter { $0.labels.contains("TRASH") }
                case .notSpam: targets = all.filter { $0.labels.contains("SPAM") }
                }
            }
            guard !targets.isEmpty else { return nil }
            for var message in targets {
                message.labels = kind.apply(to: message.labels)
                try message.update(db)
            }
            try refresh(db, threads: [threadKey])
            var gesture = MailGestureRow(id: nil, account: account, threadKey: threadKey, kind: kind, messageIDs: targets.map(\.messageID),
                                         attempts: 0, error: nil, createdAt: date)
            try gesture.insert(db)
            return gesture
        }
    }

    /// The gestures of a mailbox still to send, the oldest first.
    public func pendingGestures(account: String) throws -> [MailGestureRow] {
        try writer.read { try MailGestureRow.filter(Column("account") == account.lowercased()).order(Column("id")).fetchAll($0) }
    }

    /// Gmail took it, or it can never be taken: it leaves the outbox.
    public func finish(gestureID: Int64) throws {
        _ = try writer.write { try MailGestureRow.deleteOne($0, key: gestureID) }
    }

    /// A passing failure: it stays, to be sent again.
    public func retryLater(gestureID: Int64, error: String) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE mail_outbox SET attempts = attempts + 1, error = ? WHERE id = ?", arguments: [error, gestureID])
        }
    }

    // MARK: - What Paul said about a sender

    public func senders() throws -> [String: MailSenderRow] {
        try writer.read { db in Dictionary(uniqueKeysWithValues: try MailSenderRow.fetchAll(db).map { ($0.address, $0) }) }
    }

    /// Keeps a choice for the next mails of this address: its tab (`.some(nil)` gives it back to Gmail's
    /// category), its images. What is not given stays as it is.
    public func remember(address: String, tab: String?? = nil, images: Bool? = nil, at date: Date) throws {
        let address = address.lowercased()
        try writer.write { db in
            var row = try MailSenderRow.fetchOne(db, key: address)
                ?? MailSenderRow(address: address, principal: false, images: false, createdAt: date, tab: nil)
            if let tab {
                row.tab = tab
                row.principal = tab == "personnes"
            }
            if let images { row.images = images }
            if row.tab != nil || row.images { try row.save(db) } else { _ = try MailSenderRow.deleteOne(db, key: address) }
        }
    }

    // MARK: - Subscriptions (14/11)

    /// The senders whose mails carry a way to leave (List-Unsubscribe), the busiest first, since a date.
    public func subscriptions(since: Date, accounts: Set<String>? = nil) throws -> [MailSubscription] {
        let messages = try writer.read { db in
            try MailMessageRow.filter(sql: "listUnsubscribe IS NOT NULL AND date >= ?", arguments: [since]).order(Column("date").desc).fetchAll(db)
        }
        var bySender: [String: MailSubscription] = [:]
        for message in messages where !message.isAside && (accounts?.contains(message.account) ?? true) {
            guard let sender = message.sender else { continue }
            var subscription = bySender[sender.email] ?? MailSubscription(
                sender: sender, count: 0, unread: 0, lastAt: message.date, listUnsubscribe: message.listUnsubscribe,
                listUnsubscribePost: message.listUnsubscribePost, authenticated: message.authenticated, inboxThreads: [])
            subscription.count += 1
            if message.isUnread { subscription.unread += 1 }
            if message.labels.contains("INBOX"), !subscription.inboxThreads.contains(message.threadKey) { subscription.inboxThreads.append(message.threadKey) }
            bySender[sender.email] = subscription
        }
        return bySender.values.sorted { ($0.count, $0.lastAt) > ($1.count, $1.lastAt) }
    }

    // MARK: - Drafts (step « Écrire »)

    public func saveDraft(_ draft: MailDraftRow) throws {
        try writer.write { db in
            guard try GoogleAccountRow.fetchOne(db, key: draft.account) != nil else { return }
            try draft.save(db)
        }
    }

    public func draft(_ id: String) throws -> MailDraftRow? {
        try writer.read { try MailDraftRow.fetchOne($0, key: id) }
    }

    public func drafts() throws -> [MailDraftRow] {
        try writer.read { try MailDraftRow.order(Column("updatedAt").desc).fetchAll($0) }
    }

    public func deleteDraft(_ id: String) throws {
        _ = try writer.write { try MailDraftRow.deleteOne($0, key: id) }
    }

    /// Gmail took a version: what it holds, and when. A draft changed meanwhile keeps its newer text.
    public func markPushed(draftID: String, gmailDraftID: String, gmailMessageID: String?, version: Date, at date: Date) throws {
        try writer.write { db in
            try db.execute(sql: """
                UPDATE mail_draft SET gmailDraftID = ?, gmailMessageID = ?, pushedAt = ?, lastError = NULL WHERE id = ?
                """, arguments: [gmailDraftID, gmailMessageID, version, draftID])
        }
    }

    public func markDraftError(_ id: String, error: String?) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE mail_draft SET lastError = ? WHERE id = ?", arguments: [error, id])
        }
    }

    /// The threads Paul wrote in, the most recent first: the « Envoyés ».
    public func sentThreads(accounts: Set<String>? = nil, limit: Int = 500) throws -> [MailThreadRow] {
        try writer.read { db in
            let keys = try String.fetchAll(db, sql: """
                SELECT threadKey FROM mail_message WHERE labels LIKE '%"SENT"%' GROUP BY threadKey ORDER BY MAX(date) DESC LIMIT ?
                """, arguments: [limit])
            let threads = try MailThreadRow.filter(keys: keys).fetchAll(db)
            let byKey = Dictionary(uniqueKeysWithValues: threads.map { ($0.id, $0) })
            return keys.compactMap { byKey[$0] }.filter { accounts?.contains($0.account) ?? true }
        }
    }

    /// The drafts Gmail holds that Polhub did not make (written on the phone, in Gmail web).
    public func gmailOnlyDrafts() throws -> [MailMessageRow] {
        try writer.read { db in
            let mine = try String.fetchSet(db, sql: "SELECT gmailMessageID FROM mail_draft WHERE gmailMessageID IS NOT NULL")
            return try MailMessageRow.filter(sql: "labels LIKE '%\"DRAFT\"%'").order(Column("date").desc).fetchAll(db)
                .filter { !mine.contains($0.messageID) }
        }
    }

    public func observeDrafts(onChange: @escaping @MainActor @Sendable ([MailDraftRow]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { try MailDraftRow.order(Column("updatedAt").desc).fetchAll($0) }
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { rows in
                MainActor.assumeIsolated { onChange(rows) }
            })
    }

    // MARK: - Observation

    /// Calls `onChange` on the main queue with the inbox of every mailbox, now and after every change.
    public func observeInbox(onChange: @escaping @MainActor @Sendable ([MailThreadRow]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { try MailThreadRow.filter(Column("hidden") == false && Column("inInbox") == true).order(Column("lastMessageAt").desc).fetchAll($0) }
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { rows in
                MainActor.assumeIsolated { onChange(rows) }
            })
    }

    public func observeCursors(onChange: @escaping @MainActor @Sendable ([MailCursorRow]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { try MailCursorRow.fetchAll($0) }
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { rows in
                MainActor.assumeIsolated { onChange(rows) }
            })
    }

    public func observeSenders(onChange: @escaping @MainActor @Sendable ([String: MailSenderRow]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { try MailSenderRow.fetchAll($0) }
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { rows in
                MainActor.assumeIsolated { onChange(Dictionary(uniqueKeysWithValues: rows.map { ($0.address, $0) })) }
            })
    }

    /// Calls `onChange` when the messages of this thread change (a new reply, a body just loaded).
    public func observeMessages(threadKey: String, onChange: @escaping @MainActor @Sendable ([MailMessageRow]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { try MailMessageRow.filter(Column("threadKey") == threadKey).order(Column("date")).fetchAll($0) }
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { rows in
                MainActor.assumeIsolated { onChange(rows.filter { !$0.isAside }) }
            })
    }
}
