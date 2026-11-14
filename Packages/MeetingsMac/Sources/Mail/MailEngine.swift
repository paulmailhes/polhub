import Domain
import Foundation
import GoogleKit
import MailFormat
import Persistence

/// Keeps the copy of each mailbox in step with Gmail (14/11): a first reading of everything, the most recent
/// first, then « what is new since last time » every 30 seconds. Paul's gestures leave first, each naming its
/// messages. A send never goes through here.
public actor MailEngine {
    public typealias SendFor = @Sendable (String) -> MailProbe.Send

    /// How many messages one pass of the first reading takes.
    public static let slice = 20

    let store: MailStore
    public nonisolated let files: MailFiles
    let sendFor: SendFor
    let flavor: AppFlavor
    let now: @Sendable () -> Date
    let pause: @Sendable (TimeInterval) async -> Void
    /// The mails that just arrived in an inbox, for the notifications.
    let onNew: @Sendable ([MailMessageRow]) -> Void
    private var pacers: [String: GmailPacer] = [:]
    private var loops: [String: Task<Void, Never>] = [:]
    /// The first reading: the messages still to read, the most recent first.
    private var backlog: [String: [String]] = [:]
    private var lastHistory: [String: Date] = [:]
    private var kicked: Set<String> = []
    private var foreground = true

    public init(database: AppDatabase, root: URL, sendFor: @escaping SendFor, flavor: AppFlavor = .current,
                now: @escaping @Sendable () -> Date = { Date() },
                pause: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) },
                onNew: @escaping @Sendable ([MailMessageRow]) -> Void = { _ in }) {
        self.store = MailStore(database)
        self.files = MailFiles(root: root)
        self.sendFor = sendFor
        self.flavor = flavor
        self.now = now
        self.pause = pause
        self.onNew = onNew
    }

    // MARK: - Following the mailboxes

    /// The mailboxes to follow from now on: those that granted the mails. The others stop, and a mailbox whose
    /// account is gone loses its files.
    public func follow(accounts: [String]) {
        let wanted = Set(accounts.map { $0.lowercased() })
        for (account, loop) in loops where !wanted.contains(account) {
            loop.cancel()
            loops[account] = nil
            backlog[account] = nil
        }
        if let existing = try? CalendarStore(store.database).accounts().map(\.email) { files.keepOnly(accounts: existing) }
        for account in wanted where loops[account] == nil {
            loops[account] = Task {
                self.repairCharsets(account)
                await self.run(account)
            }
        }
    }

    /// Once per mailbox: the bodies kept before 14/11 in the wrong character set are put right, on the Mac,
    /// without reading them again from Gmail.
    func repairCharsets(_ account: String) {
        let folder = files.folder(account: account), mark = folder.appending(path: ".jeux-de-caracteres-2")
        guard !FileManager.default.fileExists(atPath: mark.path(percentEncoded: false)),
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) else { return }
        for name in names where name.hasSuffix(".html") || name.hasSuffix(".txt") {
            let url = folder.appending(path: name)
            guard let text = try? String(contentsOf: url, encoding: .utf8), let fixed = MailParser.repaired(text) else { continue }
            try? Data(fixed.utf8).write(to: url, options: .atomic)
        }
        try? Data().write(to: mark)
    }

    /// App in front: Gmail is asked every 30 seconds; behind, every minute.
    public func setForeground(_ on: Bool) {
        foreground = on
    }

    /// Ends the wait of a mailbox: something is to be sent or read now.
    public func kick(_ account: String) {
        kicked.insert(account.lowercased())
    }

    private func run(_ account: String) async {
        await readIdentity(account)
        while !Task.isCancelled {
            if await step(account) { continue }
            var waited = 0.0
            while waited < (foreground ? 30 : 60), !Task.isCancelled, !kicked.contains(account) {
                await pause(1)
                waited += 1
            }
            kicked.remove(account)
        }
    }

    private func pacer(_ account: String) -> GmailPacer {
        if let pacer = pacers[account] { return pacer }
        // Most of Gmail's 6 000 units a minute; the rest stays for what Paul does meanwhile.
        let pacer = GmailPacer(unitsPerMinute: 4_500, now: now, sleep: pause)
        pacers[account] = pacer
        return pacer
    }

    private func get<T: Decodable & Sendable>(_ type: T.Type, _ account: String, cost: Int,
                                              _ build: @escaping @Sendable (String) -> URLRequest) async throws -> T {
        await pacer(account).take(cost)
        return try GmailAPI.decode(type, from: try await sendFor(account)(build))
    }

    // MARK: - One pass

    /// One pass for a mailbox: the gestures first, then a slice of the first reading or what is new. Returns
    /// `true` when more work waits right now.
    @discardableResult
    public func step(_ account: String) async -> Bool {
        let account = account.lowercased()
        do {
            try await sendGestures(account)
            var cursor = try store.cursor(account: account) ?? MailCursorRow(account: account)
            if cursor.historyID == nil {
                // The point to resume from is taken before the reading: what arrives meanwhile is not missed.
                let profile = try await get(GmailAPI.Profile.self, account, cost: GmailAPI.Cost.profile) { GmailAPI.profileRequest(accessToken: $0) }
                cursor.historyID = profile.historyId
                try store.save(cursor)
            }
            guard cursor.finishedAt == nil else {
                try await history(account)
                return false
            }
            if backlog[account] == nil {
                let known = try store.knownMessageIDs(account: account)
                let all = try await listIDs(account)
                backlog[account] = all.filter { !known.contains($0) }
                cursor.total = all.count
                cursor.done = all.count - (backlog[account]?.count ?? 0)
            }
            let ids = Array((backlog[account] ?? []).prefix(Self.slice))
            if !ids.isEmpty {
                try keep(try await fetch(ids, account: account), account: account)
                backlog[account]?.removeFirst(ids.count)
                cursor.done += ids.count
            }
            let finished = backlog[account]?.isEmpty ?? true
            if finished {
                cursor.finishedAt = now()
                backlog[account] = nil
            }
            cursor.lastSyncAt = now()
            cursor.lastError = nil
            try store.save(cursor)
            // A long first reading still hears the new mails, every 30 seconds.
            if finished || lastHistory[account].map({ now().timeIntervalSince($0) >= 30 }) ?? true { try await history(account) }
            return !finished
        } catch GoogleError.rateLimited {
            return false
        } catch {
            if var cursor = try? store.cursor(account: account) {
                cursor.lastError = "\(error)"
                try? store.save(cursor)
            }
            return false
        }
    }

    /// Every message id of a mailbox (or of one label), the most recent first. Spam and trash are left out.
    private func listIDs(_ account: String, labelIDs: [String] = []) async throws -> [String] {
        var ids: [String] = [], token: String?
        repeat {
            let pageToken = token
            let page = try await get(GmailAPI.IDPage.self, account, cost: GmailAPI.Cost.messageList) {
                GmailAPI.messagesRequest(accessToken: $0, labelIDs: labelIDs, pageToken: pageToken)
            }
            ids += page.ids
            token = page.nextPageToken
        } while token != nil
        return ids
    }

    /// Reads these messages whole, four at a time. A message Gmail no longer has is simply left out.
    private func fetch(_ ids: [String], account: String) async throws -> [ParsedMail] {
        let pacer = pacer(account), send = sendFor(account)
        return try await withThrowingTaskGroup(of: ParsedMail?.self) { group in
            var remaining = ids[...]
            var mails: [ParsedMail] = []
            func add() {
                guard let id = remaining.popFirst() else { return }
                group.addTask {
                    await pacer.take(GmailAPI.Cost.full)
                    do {
                        let data = try await send { GmailAPI.messageRequest(accessToken: $0, id: id, format: .full) }
                        return MailParser.parse(try GmailAPI.decode(GmailAPI.Message.self, from: data), account: account)
                    } catch GoogleError.notFound {
                        return nil
                    }
                }
            }
            for _ in 0..<4 { add() }
            while let mail = try await group.next() {
                if let mail { mails.append(mail) }
                add()
            }
            return mails
        }
    }

    /// Bodies and small images go to their files, the rows to the base. Spam is never kept.
    private func keep(_ mails: [ParsedMail], account: String) throws {
        var rows: [MailMessageRow] = []
        for mail in mails where !mail.row.labels.contains("SPAM") {
            if let body = mail.body { try files.write(Data(body.utf8), to: files.body(of: mail.row)) }
            for attachment in mail.row.attachments {
                if let data = mail.inline[attachment.partID] { try files.write(data, to: files.attachment(attachment, of: mail.row)) }
            }
            rows.append(mail.row)
        }
        try store.apply(account: account, upserts: rows)
    }

    /// What changed since the cursor. A message that vanished meanwhile is ignored; only a cursor Gmail forgot
    /// starts everything again.
    private func history(_ account: String) async throws {
        guard var cursor = try store.cursor(account: account), let start = cursor.historyID else { return }
        lastHistory[account] = now()
        var added: Set<String> = [], relabeled: Set<String> = [], deleted: Set<String> = [], token: String?, newest: String?
        do {
            repeat {
                let pageToken = token
                let page = try await get(GmailAPI.HistoryPage.self, account, cost: GmailAPI.Cost.history) {
                    GmailAPI.historyRequest(accessToken: $0, startHistoryID: start, pageToken: pageToken, maxResults: 500)
                }
                for record in page.history ?? [] {
                    for change in record.messagesAdded ?? [] where !(change.message.labelIds ?? []).contains("SPAM") { added.insert(change.message.id) }
                    for change in (record.labelsAdded ?? []) + (record.labelsRemoved ?? []) { relabeled.insert(change.message.id) }
                    for change in record.messagesDeleted ?? [] { deleted.insert(change.message.id) }
                }
                newest = page.historyId ?? newest
                token = page.nextPageToken
            } while token != nil
        } catch GoogleError.notFound {
            try await resync(account)
            return
        }
        let known = try store.knownMessageIDs(account: account)
        let toRead = added.union(relabeled.filter { !known.contains($0) }).subtracting(deleted)
        let mails = toRead.isEmpty ? [] : try await fetch(Array(toRead), account: account)
        try keep(mails, account: account)
        var labels: [String: [String]] = [:]
        for id in relabeled where known.contains(id) && !added.contains(id) && !deleted.contains(id) {
            do {
                let message = try await get(GmailAPI.Message.self, account, cost: GmailAPI.Cost.metadata) {
                    GmailAPI.messageRequest(accessToken: $0, id: id, format: .minimal)
                }
                labels[id] = message.labelIds ?? []
            } catch GoogleError.notFound {
                deleted.insert(id)
            }
        }
        if !labels.isEmpty || !deleted.isEmpty { try store.apply(account: account, labels: labels, removed: Array(deleted)) }
        // The first reading may have saved the cursor meanwhile: only the point to resume from changes here.
        cursor = try store.cursor(account: account) ?? cursor
        cursor.historyID = newest ?? start
        cursor.lastSyncAt = now()
        cursor.lastError = nil
        try store.save(cursor)
        let arrived = mails.map(\.row).filter { added.contains($0.messageID) && $0.labels.contains("INBOX") && $0.isUnread && !$0.labels.contains("SENT") }
        if !arrived.isEmpty { onNew(arrived) }
    }

    /// Gmail forgot the cursor (the Mac stayed closed a long time): the copy is put square again. What Gmail no
    /// longer lists goes, what is new is read, and the inbox and the unread are set from Gmail's own lists.
    private func resync(_ account: String) async throws {
        let profile = try await get(GmailAPI.Profile.self, account, cost: GmailAPI.Cost.profile) { GmailAPI.profileRequest(accessToken: $0) }
        let all = try await listIDs(account)
        let inbox = Set(try await listIDs(account, labelIDs: ["INBOX"])), unread = Set(try await listIDs(account, labelIDs: ["UNREAD"]))
        let listed = Set(all)
        var labels: [String: [String]] = [:]
        let current = try store.labels(account: account)
        for (id, old) in current where listed.contains(id) {
            var fresh = old.filter { $0 != "INBOX" && $0 != "UNREAD" && $0 != "TRASH" }
            if inbox.contains(id) { fresh.append("INBOX") }
            if unread.contains(id) { fresh.append("UNREAD") }
            if Set(fresh) != Set(old) { labels[id] = fresh }
        }
        try store.apply(account: account, labels: labels, removed: current.keys.filter { !listed.contains($0) })
        let missing = all.filter { current[$0] == nil }
        backlog[account] = missing
        try store.save(MailCursorRow(account: account, historyID: profile.historyId, total: all.count, done: all.count - missing.count,
                                     finishedAt: missing.isEmpty ? now() : nil, lastSyncAt: now()))
    }

    // MARK: - Paul's gestures

    /// The gesture changes the copy at once and leaves for Gmail at the next pass, asked for right away.
    @discardableResult
    public func perform(_ kind: MailGestureKind, threadKey: String) throws -> MailGestureRow? {
        guard flavor == .prod else { throw GoogleError.readOnlyBuild }
        let gesture = try store.enqueue(kind, threadKey: threadKey, at: now())
        if let gesture { kick(gesture.account) }
        return gesture
    }

    /// Undoing is the inverse gesture on the very same messages.
    public func undo(_ gesture: MailGestureRow) throws {
        guard flavor == .prod else { throw GoogleError.readOnlyBuild }
        try store.enqueue(gesture.kind.inverse, threadKey: gesture.threadKey, messageIDs: gesture.messageIDs, at: now())
        kick(gesture.account)
    }

    /// Sends the waiting gestures in order. A passing failure keeps them all; a final refusal (the message is
    /// gone) drops that one in silence.
    private func sendGestures(_ account: String) async throws {
        let send = sendFor(account), pacer = pacer(account)
        for gesture in try store.pendingGestures(account: account) {
            guard let id = gesture.id else { continue }
            do {
                if gesture.kind == .untrash {
                    for messageID in gesture.messageIDs {
                        await pacer.take(GmailAPI.Cost.untrash)
                        do { _ = try await send { GmailAPI.untrashRequest(accessToken: $0, id: messageID) } } catch GoogleError.notFound {}
                    }
                }
                await pacer.take(GmailAPI.Cost.batchModify)
                let ids = gesture.messageIDs, add = gesture.kind.add, remove = gesture.kind == .untrash ? [] : gesture.kind.remove
                _ = try await send { GmailAPI.batchModifyRequest(accessToken: $0, ids: ids, add: add, remove: remove) }
                try store.finish(gestureID: id)
            } catch let error as GoogleError {
                switch error {
                case .notFound, .http(400..<500):
                    try store.finish(gestureID: id)
                default:
                    try store.retryLater(gestureID: id, error: "\(error)")
                    throw error
                }
            }
        }
    }

    // MARK: - Reading a message

    /// The body of a message: from its file, or read from Gmail when it is not there yet.
    public func body(of message: MailMessageRow) async throws -> String {
        if message.hasBody, let data = try? Data(contentsOf: files.body(of: message)) { return String(decoding: data, as: UTF8.self) }
        let mails = try await fetch([message.messageID], account: message.account)
        try keep(mails, account: message.account)
        return mails.first?.body ?? ""
    }

    /// A file of a message, downloaded once. macOS marks it as coming from a mail.
    public func file(_ attachment: MailAttachment, of message: MailMessageRow) async throws -> URL {
        let url = files.attachment(attachment, of: message)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { return url }
        func bytes(_ attachmentID: String) async throws -> Data {
            let messageID = message.messageID
            let body = try await get(GmailAPI.Body.self, message.account, cost: GmailAPI.Cost.attachment) {
                GmailAPI.attachmentRequest(accessToken: $0, messageID: messageID, attachmentID: attachmentID)
            }
            guard let bytes = body.bytes else { throw GoogleError.badAnswer }
            return bytes
        }
        let data: Data
        do {
            guard let attachmentID = attachment.attachmentID else { throw GoogleError.notFound }
            data = try await bytes(attachmentID)
        } catch {
            // Gmail's attachment ids do not last: read the message again and take the fresh one.
            guard let fresh = try await fetch([message.messageID], account: message.account).first?.row.attachments
                .first(where: { $0.partID == attachment.partID })?.attachmentID else { throw error }
            data = try await bytes(fresh)
        }
        try files.write(data, to: url, quarantine: !attachment.inline)
        return url
    }

    /// Paul's search, sent to Gmail as he typed it. Returns the threads found, known or just read.
    public func search(_ query: String, accounts: [String]) async throws -> [String] {
        var keys: [String] = []
        for account in accounts.map({ $0.lowercased() }) {
            let page = try await get(GmailAPI.IDPage.self, account, cost: GmailAPI.Cost.threadList) {
                GmailAPI.threadsRequest(accessToken: $0, query: query, maxResults: 25)
            }
            for id in page.ids {
                let key = MailThreadRow.key(account: account, threadID: id)
                if try store.thread(key) == nil {
                    let thread = try await get(GmailAPI.Thread.self, account, cost: GmailAPI.Cost.thread) {
                        GmailAPI.threadRequest(accessToken: $0, id: id, format: .full)
                    }
                    try keep((thread.messages ?? []).map { MailParser.parse($0, account: account) }, account: account)
                }
                keys.append(key)
            }
        }
        return keys
    }

    // MARK: - Writing (step « Écrire », 14/11)

    /// The name and Gmail's signature of a mailbox, read once a launch: the drafts sign as Gmail would.
    func readIdentity(_ account: String) async {
        guard let list = try? await get(GmailAPI.SendAsList.self, account, cost: GmailAPI.Cost.sendAs, { GmailAPI.sendAsRequest(accessToken: $0) }),
              let identity = list.sendAs?.first(where: { $0.sendAsEmail.lowercased() == account }) ?? list.sendAs?.first(where: { $0.isPrimary == true })
        else { return }
        var cursor = (try? store.cursor(account: account)) ?? MailCursorRow(account: account)
        cursor.senderName = identity.displayName.flatMap { $0.isEmpty ? nil : $0 }
        cursor.signature = identity.signature.flatMap { $0.isEmpty ? nil : $0 }
        try? store.save(cursor)
    }

    /// What a reply needs of the message it answers: its people, its thread's headers, its body.
    public func replySource(for message: MailMessageRow) async throws -> ReplySource {
        let headers = try await get(GmailAPI.Message.self, message.account, cost: GmailAPI.Cost.metadata) {
            GmailAPI.messageRequest(accessToken: $0, id: message.messageID, format: .metadata, headers: ["Reply-To", "References", "Message-ID"])
        }.payload
        let body = try await self.body(of: message)
        return ReplySource(from: message.sender, replyTo: MailParser.addresses(headers?.header("Reply-To")), to: message.to, cc: message.cc,
                           date: message.date, subject: message.subject, messageID: headers?.header("Message-ID") ?? message.rfcMessageID,
                           references: headers?.header("References"), body: body, isHTML: message.bodyIsHTML)
    }

    /// The draft as it leaves: Paul's text, the mailbox's signature, the quoted message, the files.
    func outgoing(_ draft: MailDraftRow) throws -> OutgoingMail {
        let cursor = try store.cursor(account: draft.account)
        let signature = draft.signature ? cursor?.signature : nil
        let folder = files.draftFolder(draft)
        let attached = try draft.files.map { file in
            OutgoingFile(filename: file.filename, mimeType: file.mimeType, data: try Data(contentsOf: folder.appending(path: file.filename)))
        }
        return OutgoingMail(from: MailAddress(name: cursor?.senderName, email: draft.account), to: draft.to, cc: draft.cc, bcc: draft.bcc,
                            subject: draft.subject, text: ReplyBuilder.text(body: draft.body, signature: signature, quote: draft.quoteText),
                            html: ReplyBuilder.html(body: draft.body, signature: signature, quote: draft.quoteHTML),
                            inReplyTo: draft.inReplyTo, references: draft.references, files: attached, date: now())
    }

    /// Gives Gmail the draft's latest version: created the first time, replaced after. A draft deleted in
    /// Gmail meanwhile is created again.
    @discardableResult
    public func push(_ draftID: String) async throws -> MailDraftRow {
        guard flavor == .prod else { throw GoogleError.readOnlyBuild }
        guard let draft = try store.draft(draftID) else { throw GoogleError.notFound }
        let version = draft.updatedAt
        let raw = try MIMEBuilder.build(try outgoing(draft), draft: true)
        let threadID = draft.threadKey.map { String($0.dropFirst(draft.account.count + 1)) }
        func upload(_ existing: String?) async throws -> GmailAPI.Draft {
            try await get(GmailAPI.Draft.self, draft.account, cost: existing == nil ? GmailAPI.Cost.draftCreate : GmailAPI.Cost.draftUpdate) {
                GmailAPI.draftUploadRequest(accessToken: $0, draftID: existing, raw: raw, threadID: threadID)
            }
        }
        let answer: GmailAPI.Draft
        do {
            answer = try await upload(draft.gmailDraftID)
        } catch GoogleError.notFound where draft.gmailDraftID != nil {
            answer = try await upload(nil)
        }
        try store.markPushed(draftID: draftID, gmailDraftID: answer.id, gmailMessageID: answer.message?.id, version: version, at: now())
        return try store.draft(draftID) ?? draft
    }

    /// Sends what Gmail holds of the draft, after giving it the latest version. Only Paul's click leads here:
    /// nothing in the base ever asks for a send.
    public func send(_ draftID: String) async throws {
        guard flavor == .prod else { throw GoogleError.readOnlyBuild }
        guard var draft = try store.draft(draftID) else { throw GoogleError.notFound }
        _ = try MIMEBuilder.build(try outgoing(draft))
        if draft.needsPush || draft.gmailDraftID == nil { draft = try await push(draftID) }
        guard let gmailDraftID = draft.gmailDraftID else { throw GoogleError.badAnswer }
        do {
            await pacer(draft.account).take(GmailAPI.Cost.draftSend)
            _ = try await sendFor(draft.account)({ GmailAPI.draftSendRequest(accessToken: $0, draftID: gmailDraftID) })
        } catch GoogleError.notFound {
            throw GoogleError.refused("Gmail n'a plus ce brouillon : regarde dans Envoyés s'il est déjà parti")
        }
        try store.deleteDraft(draftID)
        try? FileManager.default.removeItem(at: files.draftFolder(draft))
        kick(draft.account)
    }

    /// The draft goes, here and in Gmail.
    public func discard(_ draftID: String) async throws {
        guard let draft = try store.draft(draftID) else { return }
        if flavor == .prod, let gmailDraftID = draft.gmailDraftID {
            do {
                await pacer(draft.account).take(GmailAPI.Cost.draftDelete)
                _ = try await sendFor(draft.account)({ GmailAPI.draftDeleteRequest(accessToken: $0, draftID: gmailDraftID) })
            } catch GoogleError.notFound {}
        }
        try store.deleteDraft(draftID)
        try? FileManager.default.removeItem(at: files.draftFolder(draft))
        kick(draft.account)
    }

    /// A draft written in Gmail (the phone, the web), taken up in Polhub: its text, its people, its files.
    public func resume(gmailDraft message: MailMessageRow) async throws -> MailDraftRow {
        var gmailDraftID: String?, token: String?
        repeat {
            let pageToken = token
            let page = try await get(GmailAPI.DraftList.self, message.account, cost: GmailAPI.Cost.draftList) {
                GmailAPI.draftsRequest(accessToken: $0, pageToken: pageToken)
            }
            gmailDraftID = page.drafts?.first { $0.message?.id == message.messageID }?.id
            token = page.nextPageToken
        } while gmailDraftID == nil && token != nil
        guard let gmailDraftID else { throw GoogleError.notFound }
        let headers = try await get(GmailAPI.Message.self, message.account, cost: GmailAPI.Cost.metadata) {
            GmailAPI.messageRequest(accessToken: $0, id: message.messageID, format: .metadata, headers: ["Bcc", "In-Reply-To", "References"])
        }.payload
        let body = try await self.body(of: message)
        let others = try store.messages(threadKey: message.threadKey).filter { $0.id != message.id }
        var draft = MailDraftRow(account: message.account, mode: others.isEmpty ? .new : .reply, threadKey: others.isEmpty ? nil : message.threadKey,
                                 to: message.to, cc: message.cc, bcc: MailParser.addresses(headers?.header("Bcc")), subject: message.subject == "(sans objet)" ? "" : message.subject,
                                 body: message.bodyIsHTML ? HTMLText.plain(body) : body, inReplyTo: headers?.header("In-Reply-To"),
                                 references: headers?.header("References"), signature: false, gmailDraftID: gmailDraftID,
                                 gmailMessageID: message.messageID, origin: .gmail, createdAt: message.date, updatedAt: now())
        // Gmail holds it as it is: nothing goes back until Paul changes it (its formatting would be lost).
        draft.pushedAt = draft.updatedAt
        let folder = files.draftFolder(draft)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for attachment in message.files {
            let source = try await file(attachment, of: message)
            let target = folder.appending(path: AttachmentSafety.cleanName(attachment.filename))
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: source, to: target)
            draft.files.append(MailDraftFile(filename: target.lastPathComponent, mimeType: attachment.mimeType, size: attachment.size))
        }
        try store.saveDraft(draft)
        return draft
    }
}
