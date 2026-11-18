import Foundation
import GRDB

/// Someone in a mail: a name when the header gives one, and an address in lowercase.
public struct MailAddress: Codable, Equatable, Hashable, Sendable {
    public var name: String?
    public var email: String

    public init(name: String? = nil, email: String) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmed?.isEmpty == false ? trimmed : nil
        self.email = email.lowercased()
    }

    /// The name, or the address when there is none.
    public var display: String { name ?? email }
}

/// A file a message carries. `inline` ones are the images the HTML shows by `cid:`.
public struct MailAttachment: Codable, Equatable, Hashable, Sendable {
    public var partID: String
    public var filename: String
    public var mimeType: String
    public var size: Int
    public var attachmentID: String?
    public var contentID: String?
    public var inline: Bool

    public init(partID: String, filename: String, mimeType: String, size: Int, attachmentID: String?, contentID: String?, inline: Bool) {
        self.partID = partID
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.attachmentID = attachmentID
        self.contentID = contentID
        self.inline = inline
    }
}

/// A file shown under a thread's line in the list, with the message that carries it: a click previews it
/// without opening the thread (15/11).
public struct MailListedFile: Hashable, Identifiable, Sendable {
    /// `account|messageID`.
    public var messageKey: String
    public var attachment: MailAttachment

    public init(messageKey: String, attachment: MailAttachment) {
        self.messageKey = messageKey
        self.attachment = attachment
    }

    public var id: String { "\(messageKey)#\(attachment.partID)" }
}

/// One message of a mailbox, as Gmail has it. Its HTML lives in a file beside the base, never here.
public struct MailMessageRow: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "mail_message"

    /// `account|messageID`.
    public var id: String
    public var account: String
    public var messageID: String
    public var threadKey: String
    public var date: Date
    public var sender: MailAddress?
    public var to: [MailAddress]
    public var cc: [MailAddress]
    public var subject: String
    public var snippet: String
    /// Gmail's labels: `INBOX`, `UNREAD`, `SENT`, `TRASH`, `CATEGORY_UPDATES`…
    public var labels: [String]
    public var rfcMessageID: String?
    /// Gmail checked that the mail comes from who it says (`dmarc=pass` in its own header).
    public var authenticated: Bool
    public var listUnsubscribe: String?
    public var listUnsubscribePost: String?
    /// The body is in its file.
    public var hasBody: Bool
    public var bodyIsHTML: Bool
    public var attachments: [MailAttachment]

    public init(account: String, messageID: String, threadID: String, date: Date, sender: MailAddress?, to: [MailAddress] = [],
                cc: [MailAddress] = [], subject: String, snippet: String, labels: [String], rfcMessageID: String? = nil,
                authenticated: Bool = false, listUnsubscribe: String? = nil, listUnsubscribePost: String? = nil, hasBody: Bool = false,
                bodyIsHTML: Bool = false, attachments: [MailAttachment] = []) {
        let account = account.lowercased()
        self.id = Self.key(account: account, messageID: messageID)
        self.account = account
        self.messageID = messageID
        self.threadKey = MailThreadRow.key(account: account, threadID: threadID)
        self.date = date
        self.sender = sender
        self.to = to
        self.cc = cc
        self.subject = subject
        self.snippet = snippet
        self.labels = labels
        self.rfcMessageID = rfcMessageID
        self.authenticated = authenticated
        self.listUnsubscribe = listUnsubscribe
        self.listUnsubscribePost = listUnsubscribePost
        self.hasBody = hasBody
        self.bodyIsHTML = bodyIsHTML
        self.attachments = attachments
    }

    public static func key(account: String, messageID: String) -> String { "\(account.lowercased())|\(messageID)" }

    /// In the trash, in the spam or a draft: kept, but out of what the list shows.
    public var isAside: Bool { labels.contains("TRASH") || labels.contains("SPAM") || labels.contains("DRAFT") }

    /// Of Paul: it carries `SENT`, or its sender is one of his accounts (`mine`, in small letters).
    public static func isMine(labels: [String], sender: String?, mine: Set<String>) -> Bool {
        labels.contains("SENT") || sender.map { mine.contains($0.lowercased()) } == true
    }
    public var isUnread: Bool { labels.contains("UNREAD") }
    /// The files to show under the message: not the images the HTML already shows.
    public var files: [MailAttachment] { attachments.filter { !$0.inline } }
}

/// Who spoke last in a thread (18/11): the last message received, and the last one of Paul's. What is in the
/// trash, in the spam, or a draft does not count.
public struct MailTurn: Equatable, Sendable {
    public var lastReceivedAt: Date?
    public var lastSentAt: Date?

    public init(lastReceivedAt: Date? = nil, lastSentAt: Date? = nil) {
        self.lastReceivedAt = lastReceivedAt
        self.lastSentAt = lastSentAt
    }

    /// `mine` holds Paul's own addresses, in small letters.
    public static func of(_ messages: [MailMessageRow], mine: Set<String>) -> MailTurn {
        var turn = MailTurn()
        for message in messages where !message.isAside {
            if MailMessageRow.isMine(labels: message.labels, sender: message.sender?.email, mine: mine) {
                turn.lastSentAt = max(turn.lastSentAt ?? message.date, message.date)
            } else {
                turn.lastReceivedAt = max(turn.lastReceivedAt ?? message.date, message.date)
            }
        }
        return turn
    }
}

/// One thread of one mailbox: what the list shows, recomputed from its messages at each change.
public struct MailThreadRow: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "mail_thread"

    /// `account|threadID`.
    public var id: String
    public var account: String
    public var threadID: String
    public var subject: String
    public var snippet: String
    /// Who wrote in the thread, in order, once each.
    public var senders: [MailAddress]
    public var lastMessageAt: Date
    public var messageCount: Int
    public var unread: Bool
    public var inInbox: Bool
    /// Every message is in the trash or the spam: the thread stays in the base (an undo brings it back) but
    /// shows nowhere.
    public var hidden: Bool
    public var hasAttachment: Bool
    /// Gmail's category of the last message received: `personal`, `updates`, `promotions`, `social`, `forums`.
    public var category: String?
    /// The address of the last message Paul did not write.
    public var lastSender: String?
    public var paulWrote: Bool
    /// Who spoke last (base v16): the last message received, the last one of Paul's. Empty on a base of before, and
    /// for a thread whose every message is aside.
    public var lastReceivedAt: Date? = nil
    public var lastSentAt: Date? = nil

    public static func key(account: String, threadID: String) -> String { "\(account.lowercased())|\(threadID)" }

    /// Gmail's own tabs: what it files as notifications, promotions or social is automatic mail.
    public static let automaticCategories: Set<String> = ["updates", "promotions", "social"]

    /// The thread, from its messages; `nil` without any. `mine` holds Paul's own addresses.
    public static func aggregate(account: String, threadID: String, messages: [MailMessageRow], mine: Set<String>) -> MailThreadRow? {
        let all = messages.sorted { $0.date < $1.date }
        guard let first = all.first else { return nil }
        let shown = all.filter { !$0.isAside }
        let visible = shown.isEmpty ? all : shown
        func isMine(_ message: MailMessageRow) -> Bool {
            MailMessageRow.isMine(labels: message.labels, sender: message.sender?.email, mine: mine)
        }
        let turn = MailTurn.of(all, mine: mine)
        var senders: [MailAddress] = []
        for sender in visible.compactMap(\.sender) where !senders.contains(where: { $0.email == sender.email }) { senders.append(sender) }
        let received = visible.last { !isMine($0) }
        let category = received?.labels.first { $0.hasPrefix("CATEGORY_") }.map { String($0.dropFirst("CATEGORY_".count)).lowercased() }
        return MailThreadRow(
            id: key(account: account, threadID: threadID), account: account.lowercased(), threadID: threadID,
            subject: (visible.first ?? first).subject, snippet: visible.last?.snippet ?? "", senders: senders,
            lastMessageAt: visible.last?.date ?? first.date, messageCount: visible.count, unread: shown.contains(where: \.isUnread),
            inInbox: shown.contains { $0.labels.contains("INBOX") }, hidden: shown.isEmpty,
            hasAttachment: visible.contains { !$0.files.isEmpty }, category: category, lastSender: received?.sender?.email,
            paulWrote: visible.contains(where: isMine), lastReceivedAt: turn.lastReceivedAt, lastSentAt: turn.lastSentAt
        )
    }
}

/// Where the reading of a mailbox stands.
public struct MailCursorRow: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "mail_cursor"

    public var account: String
    /// Gmail's point to resume from; `nil` before the first reading starts.
    public var historyID: String?
    /// The first reading: how many messages the mailbox holds, how many are read, when it ended.
    public var total: Int
    public var done: Int
    public var finishedAt: Date?
    public var lastSyncAt: Date?
    public var lastError: String?
    /// How the mailbox signs: its name and Gmail's signature (HTML), read from Gmail's settings.
    public var senderName: String?
    public var signature: String?

    public init(account: String, historyID: String? = nil, total: Int = 0, done: Int = 0, finishedAt: Date? = nil, lastSyncAt: Date? = nil,
                lastError: String? = nil, senderName: String? = nil, signature: String? = nil) {
        self.account = account.lowercased()
        self.historyID = historyID
        self.total = total
        self.done = done
        self.finishedAt = finishedAt
        self.lastSyncAt = lastSyncAt
        self.lastError = lastError
        self.senderName = senderName
        self.signature = signature
    }
}

/// What Paul does to a thread. Never a send: a send is never a row (14/11).
public enum MailGestureKind: String, Codable, Sendable, CaseIterable {
    case archive, unarchive, markRead, markUnread, trash, untrash, spam, notSpam

    /// Gmail's labels the gesture adds and removes.
    public var add: [String] {
        switch self {
        case .unarchive, .untrash, .notSpam: ["INBOX"]
        case .markUnread: ["UNREAD"]
        case .trash: ["TRASH"]
        case .spam: ["SPAM"]
        case .archive, .markRead: []
        }
    }

    public var remove: [String] {
        switch self {
        case .archive, .trash, .spam: ["INBOX"]
        case .markRead: ["UNREAD"]
        case .untrash: ["TRASH"]
        case .notSpam: ["SPAM"]
        case .unarchive, .markUnread: []
        }
    }

    /// What undoes it.
    public var inverse: MailGestureKind {
        switch self {
        case .archive: .unarchive
        case .unarchive: .archive
        case .markRead: .markUnread
        case .markUnread: .markRead
        case .trash: .untrash
        case .untrash: .trash
        case .spam: .notSpam
        case .notSpam: .spam
        }
    }

    func apply(to labels: [String]) -> [String] {
        var result = labels.filter { !remove.contains($0) }
        for label in add where !result.contains(label) { result.append(label) }
        return result
    }
}

/// A gesture waiting to reach Gmail. It names its messages: a reply that came meanwhile is never carried along.
public struct MailGestureRow: Codable, Equatable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "mail_outbox"

    public var id: Int64?
    public var account: String
    public var threadKey: String
    public var kind: MailGestureKind
    public var messageIDs: [String]
    public var attempts: Int
    public var error: String?
    public var createdAt: Date

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// What Paul said once about a sender, kept for the next mails.
public struct MailSenderRow: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "mail_sender"

    public var address: String
    /// Kept for the bases of 0.12: « personnes » is now said by `tab`.
    public var principal: Bool
    /// Its remote images show without asking.
    public var images: Bool
    public var createdAt: Date
    /// The tab Paul chose for its mails (`personnes`, `notifications`; `newsletters` from 0.13 reads as
    /// Notifications), whatever Gmail's category.
    public var tab: String?
    /// The case Paul last chose for one of its threads (`MailFiling.rawValue`), for the threads to come.
    public var filing: String? = nil
}

/// A draft an agent dropped (step « Agents »): its text, and for a new mail its people. For a reply the app
/// works out who it goes to, never the agent. Nothing here reaches Gmail or sends.
public struct MailAgentDraftRow: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "mail_agent_draft"

    /// How the agent wrote its text (16/11): plain, or the little markdown the app turns into simple HTML.
    public enum Format: String, Codable, Sendable {
        case plain, markdown
    }

    public var id: String
    /// `new`, `reply` or `replyAll`.
    public var mode: MailDraftRow.Mode
    public var account: String?
    public var threadKey: String?
    public var to: [MailAddress]
    public var cc: [MailAddress]
    public var subject: String
    public var body: String
    public var createdAt: Date
    /// The files Paul asked the agent to join (16/11), copied by `polhub mcp` into the drop's own folder
    /// (`MailFiles.agentFolder`); the app moves them into the draft's.
    public var files: [MailDraftFile]
    public var format: Format
    /// A change to a draft the agents prepared (17/11), by its identifier, instead of a new one: only what is given
    /// (text, subject, people, files) replaces what the draft has. The app applies it, never to Paul's own drafts.
    public var replaces: String?
    /// With `replaces`: the draft goes.
    public var discard: Bool
    /// With `replaces`: the version of the draft the agent saw (its `updatedAt`). Retouched by Paul since, the app
    /// changes nothing (17/11).
    public var basedOn: Date?

    public init(id: String = UUID().uuidString.lowercased(), mode: MailDraftRow.Mode, account: String? = nil, threadKey: String? = nil,
                to: [MailAddress] = [], cc: [MailAddress] = [], subject: String = "", body: String, createdAt: Date,
                files: [MailDraftFile] = [], format: Format = .plain, replaces: String? = nil, discard: Bool = false, basedOn: Date? = nil) {
        self.id = id
        self.mode = mode
        self.account = account?.lowercased()
        self.threadKey = threadKey
        self.to = to
        self.cc = cc
        self.subject = subject
        self.body = body
        self.createdAt = createdAt
        self.files = files
        self.format = format
        self.replaces = replaces
        self.discard = discard
        self.basedOn = basedOn
    }
}

/// Paul's case for one thread (step « Ranger »): never recomputed.
public struct MailFilingRow: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "mail_filing"

    public var threadKey: String
    /// `MailFiling.rawValue`.
    public var value: String
    public var createdAt: Date

    public init(threadKey: String, value: String, createdAt: Date) {
        self.threadKey = threadKey
        self.value = value
        self.createdAt = createdAt
    }
}

/// A mail Paul writes (14/11, step « Écrire »): kept on the Mac first, then in Gmail's drafts. Never a send:
/// sending is Paul's click, held ten seconds in memory.
public struct MailDraftRow: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "mail_draft"

    public enum Mode: String, Codable, Sendable, CaseIterable {
        case new, reply, replyAll, forward
    }

    /// Who wrote it: Paul in Polhub, Paul elsewhere (a draft found in Gmail), or an agent (step « Agents »).
    public enum Origin: String, Codable, Sendable {
        case paul, gmail, agent
    }

    public var id: String
    public var account: String
    public var mode: Mode
    /// The thread answered or forwarded; `nil` for a new mail.
    public var threadKey: String?
    /// The message answered or forwarded (`account|messageID`).
    public var replyToKey: String?
    public var to: [MailAddress]
    public var cc: [MailAddress]
    public var bcc: [MailAddress]
    public var subject: String
    /// What Paul writes, as text.
    public var body: String
    /// An agent's formatted text (16/11), made by the app from its markdown: it leaves instead of the HTML of `body`,
    /// which stays its plain version (the text part). `nil` for every draft Paul writes.
    public var bodyHTML: String?
    /// The message answered or forwarded, below Paul's text, as Gmail quotes it.
    public var quoteHTML: String?
    public var quoteText: String?
    public var inReplyTo: String?
    public var references: String?
    /// Gmail's signature of the account goes below the text.
    public var signature: Bool
    public var files: [MailDraftFile]
    public var gmailDraftID: String?
    public var gmailMessageID: String?
    public var origin: Origin
    /// The version Gmail holds; `nil` before the first push.
    public var pushedAt: Date?
    public var lastError: String?
    public var createdAt: Date
    public var updatedAt: Date
    /// Gmail's copy went its own way: nothing more goes to Gmail and nothing leaves until Paul chooses.
    public var conflict: Conflict?
    /// When an agent last gave this draft its text (17/11): changed later, Paul retouched it, and an agent rereads it
    /// before changing it again.
    public var agentVersionAt: Date?

    /// What happened to Gmail's copy of a draft (review of 14/11): sent or deleted elsewhere, or changed on
    /// another device. Polhub never makes it again nor overwrites it on its own.
    public enum Conflict: String, Codable, Sendable, Error, CustomStringConvertible {
        case absent, modifie

        public var description: String {
            switch self {
            case .absent: "ce brouillon n'est plus dans Gmail : envoyé ou supprimé ailleurs ?"
            case .modifie: "ce brouillon a été modifié dans Gmail, sur un autre appareil"
            }
        }
    }

    public init(id: String = UUID().uuidString.lowercased(), account: String, mode: Mode, threadKey: String? = nil, replyToKey: String? = nil,
                to: [MailAddress] = [], cc: [MailAddress] = [], bcc: [MailAddress] = [], subject: String = "", body: String = "", bodyHTML: String? = nil,
                quoteHTML: String? = nil, quoteText: String? = nil, inReplyTo: String? = nil, references: String? = nil, signature: Bool = true,
                files: [MailDraftFile] = [], gmailDraftID: String? = nil, gmailMessageID: String? = nil, origin: Origin = .paul,
                pushedAt: Date? = nil, lastError: String? = nil, createdAt: Date, updatedAt: Date? = nil, conflict: Conflict? = nil,
                agentVersionAt: Date? = nil) {
        self.id = id
        self.account = account.lowercased()
        self.mode = mode
        self.threadKey = threadKey
        self.replyToKey = replyToKey
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
        self.bodyHTML = bodyHTML
        self.quoteHTML = quoteHTML
        self.quoteText = quoteText
        self.inReplyTo = inReplyTo
        self.references = references
        self.signature = signature
        self.files = files
        self.gmailDraftID = gmailDraftID
        self.gmailMessageID = gmailMessageID
        self.origin = origin
        self.pushedAt = pushedAt
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.conflict = conflict
        self.agentVersionAt = agentVersionAt
    }

    /// An agent's draft Paul changed since the agent last gave it its text (17/11).
    public var retouchedByPaul: Bool {
        origin == .agent && updatedAt > (agentVersionAt ?? .distantPast)
    }

    /// Something to send: someone to send it to, and words or a file.
    public var isSendable: Bool {
        !(to + cc + bcc).isEmpty && (!body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !files.isEmpty || quoteHTML != nil)
    }

    /// Changed since Gmail last took it.
    public var needsPush: Bool { pushedAt.map { $0 < updatedAt } ?? true }
}

/// A file joined to a draft: copied beside it on the Mac, so the draft never depends on where it came from.
public struct MailDraftFile: Codable, Equatable, Hashable, Sendable {
    public var filename: String
    public var mimeType: String
    public var size: Int

    public init(filename: String, mimeType: String, size: Int) {
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
    }
}

/// A sender who writes on his own (a list Paul could leave): how much, how to leave, what waits in the inbox.
public struct MailSubscription: Equatable, Identifiable, Sendable {
    public var sender: MailAddress
    public var count: Int
    public var unread: Int
    public var lastAt: Date
    public var listUnsubscribe: String?
    public var listUnsubscribePost: String?
    public var authenticated: Bool
    /// Its threads still in the inbox.
    public var inboxThreads: [String]

    public var id: String { sender.email }
}
