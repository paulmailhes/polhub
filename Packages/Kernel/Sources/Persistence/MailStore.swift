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
        let mine = Set(try String.fetchAll(db, sql: "SELECT email FROM google_account").map { $0.lowercased() })
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

    /// « Tous les messages » (15/11): every thread of the copy, archived ones too, never the trash nor the spam.
    /// The copy holds the whole mailbox (about 6 000 threads in 3 boxes): the limit only guards against a runaway.
    public func allThreads(accounts: Set<String>? = nil, limit: Int = 20_000) throws -> [MailThreadRow] {
        try writer.read { db in
            var request = MailThreadRow.filter(Column("hidden") == false)
            if let accounts { request = request.filter(accounts.map { $0.lowercased() }.contains(Column("account"))) }
            return try request.order(Column("lastMessageAt").desc).limit(limit).fetchAll(db)
        }
    }

    // MARK: - Who spoke last (18/11)

    /// A message of Paul's, said in SQL as `MailMessageRow.isMine` says it: marked as sent, or written from one of
    /// his accounts. A sender that is missing, or not what it should be, is not his.
    private static let isMineSQL = """
        (instr(message.labels, '"SENT"') > 0 OR COALESCE(
            lower(json_extract(CASE WHEN json_valid(message.sender) THEN message.sender END, '$.email')) IN (SELECT lower(email) FROM google_account), 0))
        """
    /// Not in the trash, not in the spam, not a draft: `MailMessageRow.isAside`, with the same exact labels.
    private static let countsSQL = """
        instr(message.labels, '"TRASH"') = 0 AND instr(message.labels, '"SPAM"') = 0 AND instr(message.labels, '"DRAFT"') = 0
        """

    /// The turn of every thread as it stood at `asOf`: the messages dated after it do not count, nor what is in the
    /// trash, in the spam, or a draft. Counted from the messages in one pass: the threads' own columns say today.
    public func turns(asOf: Date) throws -> [String: MailTurn] {
        try writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT message.threadKey AS threadKey,
                    MAX(CASE WHEN \(Self.isMineSQL) THEN message.date END) AS lastSentAt,
                    MAX(CASE WHEN NOT \(Self.isMineSQL) THEN message.date END) AS lastReceivedAt
                FROM mail_message AS message
                WHERE \(Self.countsSQL) AND message.date <= ?
                GROUP BY message.threadKey
                """, arguments: [asOf])
            var turns: [String: MailTurn] = [:]
            for row in rows {
                guard let key = String.fromDatabaseValue(row["threadKey"]) else { continue }
                // Read without a trap: a date that is no date is no turn.
                turns[key] = MailTurn(lastReceivedAt: Date.fromDatabaseValue(row["lastReceivedAt"]), lastSentAt: Date.fromDatabaseValue(row["lastSentAt"]))
            }
            return turns
        }
    }

    /// Who wrote the last message received in each thread, as it stood at `asOf`: an address in small letters.
    public func lastSenders(asOf: Date) throws -> [String: String] {
        try writer.read { db in
            // With MAX(), SQLite takes the other columns from the row that holds the maximum.
            let rows = try Row.fetchAll(db, sql: """
                SELECT message.threadKey AS threadKey,
                    lower(json_extract(CASE WHEN json_valid(message.sender) THEN message.sender END, '$.email')) AS email,
                    MAX(message.date) AS date
                FROM mail_message AS message
                WHERE \(Self.countsSQL) AND NOT \(Self.isMineSQL) AND message.date <= ?
                GROUP BY message.threadKey
                """, arguments: [asOf])
            var senders: [String: String] = [:]
            for row in rows {
                guard let key = String.fromDatabaseValue(row["threadKey"]), let email = String.fromDatabaseValue(row["email"]) else { continue }
                senders[key] = email
            }
            return senders
        }
    }

    /// The copies of one conversation in several of Paul's mailboxes: a mail delivered to two boxes is two messages
    /// with the same identifier (its « Message-ID »), in two threads. For each thread that has such a copy, the key
    /// of its group; a thread alone is not in the answer. Only the messages dated after `since` are read.
    public func conversations(since: Date) throws -> [String: String] {
        try writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT rfcMessageID, threadKey FROM mail_message
                WHERE rfcMessageID IS NOT NULL AND rfcMessageID != '' AND date > ? AND instr(labels, '"DRAFT"') = 0
                """, arguments: [since])
            var parent: [String: String] = [:]
            func root(_ thread: String) -> String {
                var current = thread
                while let next = parent[current], next != current { current = next }
                return current
            }
            var first: [String: String] = [:]
            for row in rows {
                guard let identifier = String.fromDatabaseValue(row["rfcMessageID"]), let thread = String.fromDatabaseValue(row["threadKey"]) else { continue }
                if parent[thread] == nil { parent[thread] = thread }
                guard let other = first[identifier] else {
                    first[identifier] = thread
                    continue
                }
                let one = root(other), two = root(thread)
                // The smaller key leads: the group's name does not depend on the order of the reading.
                if one != two { parent[max(one, two)] = min(one, two) }
            }
            var sizes: [String: Int] = [:]
            for thread in parent.keys { sizes[root(thread), default: 0] += 1 }
            var groups: [String: String] = [:]
            for thread in parent.keys {
                let group = root(thread)
                if sizes[group, default: 0] > 1 { groups[thread] = group }
            }
            return groups
        }
    }

    /// Calls `onChange` on the main queue with the threads shown whose last message, received or sent, is after
    /// `since`: now, and after every change of one of them. A writing that changes none of them calls nobody.
    public func observeTurns(since: Date, onChange: @escaping @MainActor @Sendable ([MailThreadRow]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { db in
                try MailThreadRow
                    .filter(Column("hidden") == false && (Column("lastReceivedAt") > since || Column("lastSentAt") > since))
                    .order(Column("lastMessageAt").desc)
                    .fetchAll(db)
            }
            .removeDuplicates()
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { rows in
                MainActor.assumeIsolated { onChange(rows) }
            })
    }

    /// The files of these threads, as the list shows them under each line: once each, without the images the
    /// HTML shows, nor those of a message in the trash, the spam or a draft. Each keeps the message that
    /// carries it (its first), so a click previews it (15/11).
    public func attachments(threadKeys: [String]) throws -> [String: [MailListedFile]] {
        guard !threadKeys.isEmpty else { return [:] }
        return try writer.read { db in
            var result: [String: [MailListedFile]] = [:]
            let messages = try MailMessageRow.filter(threadKeys.contains(Column("threadKey"))).filter(sql: "attachments <> '[]'")
                .order(Column("date")).fetchAll(db)
            for message in messages where !message.isAside {
                for file in message.files where !(result[message.threadKey] ?? []).contains(where: {
                    $0.attachment.filename == file.filename && $0.attachment.size == file.size
                }) {
                    result[message.threadKey, default: []].append(MailListedFile(messageKey: message.id, attachment: file))
                }
            }
            return result
        }
    }

    /// What the instant search reads (15/11): every thread shown somewhere (neither trash nor spam), the most
    /// recent first, each with the words it is found by. Built in one reading; the list filters it as Paul types.
    public func searchEntries() throws -> [MailSearchEntry] {
        try writer.read { db in
            let threads = try MailThreadRow.filter(Column("hidden") == false).order(Column("lastMessageAt").desc).fetchAll(db)
            var messages: [String: [MailMessageRow]] = [:]
            for message in try MailMessageRow.fetchAll(db) where !message.isAside {
                messages[message.threadKey, default: []].append(message)
            }
            return threads.map { MailSearchEntry(thread: $0, words: MailSearch.words(of: $0, messages: messages[$0.id] ?? [])) }
        }
    }

    /// What a search typed in « Corbeille » or « Spam » reads: that folder's threads only (wave B, 15/11).
    public func searchEntries(aside label: String) throws -> [MailSearchEntry] {
        guard Self.asideLabels.contains(label) else { return [] }
        return try writer.read { db in
            let threads = try asideRequest(label: label, accounts: nil).fetchAll(db)
            var messages: [String: [MailMessageRow]] = [:]
            for message in try MailMessageRow.filter(threads.map(\.id).contains(Column("threadKey"))).fetchAll(db) where Self.shows(message, aside: true) {
                messages[message.threadKey, default: []].append(message)
            }
            return threads.map { MailSearchEntry(thread: $0, words: MailSearch.words(of: $0, messages: messages[$0.id] ?? [])) }
        }
    }

    /// The messages of a thread, the oldest first; those in the trash or the spam are left out. Opened from the
    /// trash or the spam (`aside`), they show, never a draft.
    public func messages(threadKey: String, aside: Bool = false) throws -> [MailMessageRow] {
        try writer.read { try MailMessageRow.filter(Column("threadKey") == threadKey).order(Column("date")).fetchAll($0) }.filter { Self.shows($0, aside: aside) }
    }

    static func shows(_ message: MailMessageRow, aside: Bool) -> Bool {
        aside ? !message.labels.contains("DRAFT") : !message.isAside
    }

    // MARK: - The trash and the spam (wave B, 15/11)

    /// Gmail's labels of the two folders put aside.
    public static let asideLabels: Set<String> = ["TRASH", "SPAM"]

    /// « Corbeille » or « Spam »: the threads put aside whole (shown nowhere else) that hold a message with this
    /// label, the most recent first. Never read by the agents, never counted: they read and count `hidden == false`.
    public func asideThreads(label: String, accounts: Set<String>? = nil, limit: Int = 1_000) throws -> [MailThreadRow] {
        guard Self.asideLabels.contains(label) else { return [] }
        return try writer.read { db in try asideRequest(label: label, accounts: accounts).limit(limit).fetchAll(db) }
    }

    private func asideRequest(label: String, accounts: Set<String>?) -> QueryInterfaceRequest<MailThreadRow> {
        var request = MailThreadRow.filter(Column("hidden") == true)
            .filter(sql: "id IN (SELECT threadKey FROM mail_message WHERE labels LIKE ?)", arguments: ["%\"\(label)\"%"])
        if let accounts { request = request.filter(accounts.map { $0.lowercased() }.contains(Column("account"))) }
        return request.order(Column("lastMessageAt").desc)
    }

    /// The spam whose body or files the Mac still holds: mails known before they went to the spam.
    public func spamOnDisk(account: String) throws -> [MailMessageRow] {
        try writer.read { db in
            try MailMessageRow.filter(Column("account") == account.lowercased())
                .filter(sql: #"labels LIKE '%"SPAM"%' AND (hasBody = 1 OR attachments <> '[]')"#).fetchAll(db)
        }
    }

    /// Their files are gone from the Mac: the rows keep the headers only, as a spam listed from Gmail.
    public func forgetSpamFiles(messageKeys: [String]) throws {
        guard !messageKeys.isEmpty else { return }
        try writer.write { db in
            var touched: Set<String> = []
            for var message in try MailMessageRow.filter(keys: messageKeys).fetchAll(db) where message.labels.contains("SPAM") {
                message.hasBody = false
                message.bodyIsHTML = false
                message.attachments = []
                try message.update(db)
                touched.insert(message.threadKey)
            }
            try refresh(db, threads: touched)
        }
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
    public func remember(address: String, tab: String?? = nil, images: Bool? = nil, filing: String?? = nil, at date: Date) throws {
        let address = address.lowercased()
        try writer.write { db in
            var row = try MailSenderRow.fetchOne(db, key: address)
                ?? MailSenderRow(address: address, principal: false, images: false, createdAt: date, tab: nil)
            if let tab {
                row.tab = tab
                row.principal = tab == "personnes"
            }
            if let images { row.images = images }
            if let filing { row.filing = filing }
            if row.tab != nil || row.images || row.filing != nil { try row.save(db) } else { _ = try MailSenderRow.deleteOne(db, key: address) }
        }
    }

    // MARK: - The agents (step « Agents », 14/11)

    /// Whether the base knows the agents' drafts (an app of 0.15 or later opened it once).
    public func acceptsAgentDrafts() throws -> Bool {
        try writer.read { try $0.tableExists(MailAgentDraftRow.databaseTableName) }
    }

    /// Whether the base takes a drop as this helper writes it, with its files and its format (v14): the helper never
    /// migrates, and a drop on an older base would not fit its table.
    public func agentDraftsTakeFiles() throws -> Bool {
        try writer.read { try $0.columns(in: MailAgentDraftRow.databaseTableName).contains { $0.name == "format" } }
    }

    /// An agent's draft, dropped by `polhub mcp`.
    /// The base knows the changes of an agent's draft (17/11): the app of 0.31 opened once.
    public func agentDraftsChange() throws -> Bool {
        try writer.read { try $0.columns(in: MailAgentDraftRow.databaseTableName).contains { $0.name == "replaces" } }
    }

    public func agentDraft(_ id: String) throws -> MailAgentDraftRow? {
        try writer.read { try MailAgentDraftRow.fetchOne($0, key: id) }
    }

    /// A drop still waiting for the app, changed in place; `false` once the app took it.
    public func updateDrop(_ draft: MailAgentDraftRow) throws -> Bool {
        try writer.write { db in
            guard try MailAgentDraftRow.fetchOne(db, key: draft.id) != nil else { return false }
            try draft.update(db)
            return true
        }
    }

    public func drop(_ draft: MailAgentDraftRow) throws {
        try writer.write { try draft.insert($0) }
    }

    public func agentDrafts() throws -> [MailAgentDraftRow] {
        try writer.read { try MailAgentDraftRow.order(Column("createdAt")).fetchAll($0) }
    }

    /// The app made a draft of what the agent dropped: the draft takes its place, in one transaction. False
    /// when the drop was already taken.
    /// `expecting`: the drop as the app read it; changed meanwhile by an agent (17/11), it waits for the next pass.
    @discardableResult
    public func adopt(_ agentDraftID: String, as draft: MailDraftRow, expecting: MailAgentDraftRow? = nil) throws -> Bool {
        try writer.write { db in
            guard let current = try MailAgentDraftRow.fetchOne(db, key: agentDraftID), expecting.map({ $0 == current }) ?? true else { return false }
            try draft.insert(db)
            _ = try MailAgentDraftRow.deleteOne(db, key: agentDraftID)
            return true
        }
    }

    /// The version an agent just gave a draft (17/11).
    public func setAgentVersion(_ id: String, at date: Date) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE mail_draft SET agentVersionAt = ? WHERE id = ?", arguments: [date, id])
        }
    }

    public func discardAgentDraft(_ id: String) throws {
        _ = try writer.write { try MailAgentDraftRow.deleteOne($0, key: id) }
    }

    public func observeAgentDrafts(onChange: @escaping @MainActor @Sendable ([MailAgentDraftRow]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { try MailAgentDraftRow.fetchAll($0) }
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { rows in
                MainActor.assumeIsolated { onChange(rows) }
            })
    }

    /// The threads the agents may read: shown somewhere (neither spam nor trash), the most recent first; the
    /// whole copy, the limit only guards against a runaway.
    public func readableThreads(limit: Int = 20_000) throws -> [MailThreadRow] {
        try writer.read { try MailThreadRow.filter(Column("hidden") == false).order(Column("lastMessageAt").desc).limit(limit).fetchAll($0) }
    }

    /// Paul's mailboxes that granted the mails, oldest first.
    public func mailAccounts() throws -> [String] {
        try writer.read { try String.fetchAll($0, sql: "SELECT email FROM google_account WHERE grantedScopes LIKE '%gmail.modify%' ORDER BY addedAt") }
    }

    // MARK: - The case (step « Ranger », 14/11)

    /// Paul's case for a thread; `nil` gives it back to the rules.
    public func file(threadKey: String, as filing: MailFiling?, at date: Date) throws {
        try writer.write { db in
            if let filing {
                try MailFilingRow(threadKey: threadKey, value: filing.rawValue, createdAt: date).save(db)
            } else {
                _ = try MailFilingRow.deleteOne(db, key: threadKey)
            }
        }
    }

    public func filingRules() throws -> MailFilingRules {
        try writer.read(Self.rules)
    }

    /// Everything the rules read: Paul's choices, the senders, the contacts and their projects, Paul's
    /// addresses, the people he wrote to.
    static func rules(_ db: Database) throws -> MailFilingRules {
        let choices = Dictionary(try MailFilingRow.fetchAll(db).compactMap { row in MailFiling(rawValue: row.value).map { (row.threadKey, $0) } },
                                 uniquingKeysWith: { first, _ in first })
        let senders = Dictionary(uniqueKeysWithValues: try MailSenderRow.fetchAll(db).map { ($0.address, $0) })
        var contactProjects: [String: Set<UUID>] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT contact.email AS email, contact_project.projectID AS projectID FROM contact_project
            JOIN contact ON contact.id = contact_project.contactID
            JOIN project ON project.id = contact_project.projectID
            WHERE contact_project.excluded = 0 AND contact.email IS NOT NULL AND project.deletedAt IS NULL
            """) {
            guard let email: String = row["email"], let id = (row["projectID"] as String?).flatMap(UUID.init(uuidString:)) else { continue }
            contactProjects[email.lowercased(), default: []].insert(id)
        }
        let contacts = Set(try String.fetchAll(db, sql: "SELECT lower(email) FROM contact WHERE email IS NOT NULL"))
        // Raw rows, never ProjectRow: the mails' rules must not depend on the statuses (review of 15/11).
        let projects = try Row.fetchAll(db, sql: "SELECT id, name FROM project WHERE deletedAt IS NULL").compactMap { row -> (id: UUID, name: String)? in
            guard let id = (row["id"] as String?).flatMap(UUID.init(uuidString:)), let name: String = row["name"] else { return nil }
            return (id: id, name: name)
        }
        let mine = Set(try String.fetchAll(db, sql: "SELECT lower(email) FROM google_account"))
        // One reading of what Paul sent gives both who he wrote to and how often (15/11).
        let stats = try correspondentStats(db)
        var rules = MailFilingRules(choices: choices, senders: senders, contactProjects: contactProjects, contacts: contacts, projects: projects,
                                    mine: mine, correspondents: Set(stats.keys))
        rules.correspondentStats = stats
        rules.excludedProjects = try excludedProjects(db)
        return rules
    }

    public func observeFilingRules(onChange: @escaping @MainActor @Sendable (MailFilingRules) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking(Self.rules)
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { rules in
                MainActor.assumeIsolated { onChange(rules) }
            })
    }

    /// The threads whose case is this project, the most recent first: the « Mails » of its page.
    public func threads(filedIn projectID: UUID) throws -> [MailThreadRow] {
        try writer.read { db in
            let rules = try Self.rules(db)
            return try MailThreadRow.filter(Column("hidden") == false).order(Column("lastMessageAt").desc).fetchAll(db)
                .filter { rules.filing(of: $0)?.filing == .project(projectID) }
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

    /// Paul's change, in one transaction on the row as it is now: what Gmail answered meanwhile (its ids, the
    /// version it holds) is never written over (review of 14/11). `nil` when the draft is gone or nothing
    /// changed: a draft only shown is never sent to Gmail (second review of 14/11).
    @discardableResult
    public func updateDraft(_ id: String, at date: Date, _ change: (inout MailDraftRow) -> Void) throws -> MailDraftRow? {
        try writer.write { db in
            guard var draft = try MailDraftRow.fetchOne(db, key: id) else { return nil }
            let before = draft
            change(&draft)
            guard draft != before else { return nil }
            draft.updatedAt = max(date, before.updatedAt.addingTimeInterval(0.001))
            draft.lastError = nil
            try draft.save(db)
            return draft
        }
    }

    public func setConflict(_ id: String, _ conflict: MailDraftRow.Conflict?) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE mail_draft SET conflict = ? WHERE id = ?", arguments: [conflict?.rawValue, id])
        }
    }

    /// A draft that leaves from another mailbox, or that Gmail must take afresh: Gmail's ids are forgotten.
    public func forgetGmailCopy(_ id: String, account: String? = nil) throws {
        try writer.write { db in
            guard var draft = try MailDraftRow.fetchOne(db, key: id) else { return }
            if let account { draft.account = account.lowercased() }
            draft.gmailDraftID = nil
            draft.gmailMessageID = nil
            draft.pushedAt = nil
            draft.conflict = nil
            draft.lastError = nil
            try draft.save(db)
        }
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

    /// The people Paul wrote to (To and Cc of what he sent), in lower case: never strangers.
    public func correspondents() throws -> Set<String> {
        try writer.read(Self.correspondents)
    }

    static func correspondents(_ db: Database) throws -> Set<String> {
        Set(try correspondentStats(db).keys)
    }

    /// What Paul sent, as Gmail's « Envoyés » counts it: neither a draft nor a mail he put in the trash or the spam.
    private static let sentMessage = #"labels LIKE '%"SENT"%' AND labels NOT LIKE '%"DRAFT"%' AND labels NOT LIKE '%"TRASH"%' AND labels NOT LIKE '%"SPAM"%'"#

    /// The threads Paul wrote in, the most recent first: the « Envoyés ». A sent mail he trashed leaves them.
    public func sentThreads(accounts: Set<String>? = nil, limit: Int = 500) throws -> [MailThreadRow] {
        try writer.read { db in
            let keys = try String.fetchAll(db, sql: """
                SELECT threadKey FROM mail_message WHERE \(Self.sentMessage) GROUP BY threadKey ORDER BY MAX(date) DESC LIMIT ?
                """, arguments: [limit])
            let threads = try MailThreadRow.filter(keys: keys).fetchAll(db)
            let byKey = Dictionary(uniqueKeysWithValues: threads.map { ($0.id, $0) })
            return keys.compactMap { byKey[$0] }.filter { accounts?.contains($0.account) ?? true }
        }
    }

    /// Who Paul wrote to in each thread (To, then Cc, of what he sent, the oldest first), once each: the
    /// « Envoyés » say « À : Camille, Jules », as Gmail's (15/11).
    public func sentRecipients(threadKeys: [String]) throws -> [String: [MailAddress]] {
        guard !threadKeys.isEmpty else { return [:] }
        return try writer.read { db in
            var result: [String: [MailAddress]] = [:]
            let messages = try MailMessageRow.filter(threadKeys.contains(Column("threadKey"))).filter(sql: Self.sentMessage)
                .order(Column("date")).fetchAll(db)
            for message in messages {
                for person in message.to + message.cc where !(result[message.threadKey] ?? []).contains(where: { $0.email == person.email }) {
                    result[message.threadKey, default: []].append(person)
                }
            }
            return result
        }
    }

    /// The drafts Gmail holds that Polhub did not make (written on the phone, in Gmail web). One whose thread went to
    /// the trash or the spam is no draft to take up: Gmail no longer lists it among the drafts (wave B review).
    public func gmailOnlyDrafts() throws -> [MailMessageRow] {
        try writer.read { db in
            let mine = try String.fetchSet(db, sql: "SELECT gmailMessageID FROM mail_draft WHERE gmailMessageID IS NOT NULL")
            return try MailMessageRow.filter(sql: #"labels LIKE '%"DRAFT"%' AND labels NOT LIKE '%"TRASH"%' AND labels NOT LIKE '%"SPAM"%'"#)
                .order(Column("date").desc).fetchAll(db)
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

    /// Calls `onChange` when the messages of this thread change (a new reply, a body just loaded). `aside`: the
    /// thread is opened from the trash or the spam.
    public func observeMessages(threadKey: String, aside: Bool = false,
                                onChange: @escaping @MainActor @Sendable ([MailMessageRow]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { try MailMessageRow.filter(Column("threadKey") == threadKey).order(Column("date")).fetchAll($0) }
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { rows in
                MainActor.assumeIsolated { onChange(rows.filter { Self.shows($0, aside: aside) }) }
            })
    }
}
