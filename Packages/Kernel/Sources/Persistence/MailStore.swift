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
                case .trash: targets = shown
                case .unarchive: targets = Array(shown.suffix(1))
                case .untrash: targets = all.filter { $0.labels.contains("TRASH") }
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

    /// Keeps a choice for the next mails of this address; `nil` leaves the other choice as it is.
    public func remember(address: String, principal: Bool? = nil, images: Bool? = nil, at date: Date) throws {
        let address = address.lowercased()
        try writer.write { db in
            var row = try MailSenderRow.fetchOne(db, key: address) ?? MailSenderRow(address: address, principal: false, images: false, createdAt: date)
            if let principal { row.principal = principal }
            if let images { row.images = images }
            if row.principal || row.images { try row.save(db) } else { _ = try MailSenderRow.deleteOne(db, key: address) }
        }
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
