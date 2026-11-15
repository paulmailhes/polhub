import Domain
import Foundation
import GoogleKit
import Persistence
import Testing
@testable import Mail
import MailFormat

/// A mailbox of Gmail's, faked in memory: it answers the engine's requests and remembers what it was asked.
final class FakeGmail: @unchecked Sendable {
    struct Mail {
        var thread: String
        var labels: [String]
        var from = "Camille Martin <camille@exemple.fr>"
        var subject = "Maquette v2"
        var minutes = 0.0
        var to = "moi@exemple.fr"
        var replyTo: String?
        var references: String?
        var body: String?
    }

    struct StoredDraft {
        var raw: String
        var threadID: String?
        var messageID: String
    }

    private let lock = NSLock()
    private var mails: [String: Mail] = [:]
    private var order: [String] = []
    private var records: [String] = []
    private var cursor = 100
    private var log: [String] = []
    /// Each request with its query, as `GET /messages?labelIds=SPAM&…`.
    private var asked: [String] = []
    /// Gmail forgot every cursor older than now.
    private var forgot = false
    /// Status to answer the next label changes with (429, 404…), once.
    private var nextModifyStatus: Int?
    private var draftStore: [String: StoredDraft] = [:]
    private var draftCounter = 0
    var signature = "<b>Moi</b> · Studio Exemple"
    /// Gmail takes this long to answer a draft's upload, after it made the draft: a connection cut meanwhile
    /// leaves a draft Polhub never heard of.
    private var slowUpload: Duration?
    func answerUploadsAfter(_ delay: Duration?) { lock.withLock { slowUpload = delay } }
    /// The draft changed in Gmail, on the phone: a new message under the same draft.
    func editInGmail(_ id: String) {
        lock.withLock {
            draftCounter += 1
            draftStore[id]?.messageID = "tel\(draftCounter)"
            draftStore[id]?.raw = "modifié sur le téléphone"
        }
    }

    var drafts: [String: StoredDraft] { lock.withLock { draftStore } }
    func addGmailDraft(id: String, messageID: String, thread: String) {
        lock.withLock { draftStore[id] = StoredDraft(raw: "", threadID: thread, messageID: messageID) }
    }

    var calls: [String] { lock.withLock { log } }
    var queries: [String] { lock.withLock { asked } }
    func labels(_ id: String) -> [String]? { lock.withLock { mails[id]?.labels } }
    func forgetCursors() { lock.withLock { forgot = true } }
    func failNextModify(_ status: Int) { lock.withLock { nextModifyStatus = status } }

    /// A mail arrives (or was always there, `history: false`).
    func add(_ id: String, _ mail: Mail, history: Bool = true) {
        lock.withLock {
            mails[id] = mail
            order.insert(id, at: 0)
            if history { records.append(#"{"messagesAdded":[{"message":{"id":"\#(id)","threadId":"\#(mail.thread)","labelIds":\#(Self.json(mail.labels))}}]}"#) }
        }
    }

    /// Something else (the phone) changes labels or deletes a mail.
    func change(_ id: String, labels: [String]?, history: Bool = true) {
        lock.withLock {
            if let labels {
                mails[id]?.labels = labels
                if history { records.append(#"{"labelsRemoved":[{"message":{"id":"\#(id)","labelIds":\#(Self.json(labels))}}]}"#) }
            } else {
                mails[id] = nil
                order.removeAll { $0 == id }
                if history { records.append(#"{"messagesDeleted":[{"message":{"id":"\#(id)"}}]}"#) }
            }
        }
    }

    static func json(_ strings: [String]) -> String { "[" + strings.map { "\"\($0)\"" }.joined(separator: ",") + "]" }

    private func message(_ id: String, full: Bool, metadataHeaders: [String]? = nil) -> String? {
        guard let mail = mails[id] else { return nil }
        let date = Int((1_794_562_920 + mail.minutes * 60) * 1_000)
        var text = #"{"id":"\#(id)","threadId":"\#(mail.thread)","labelIds":\#(Self.json(mail.labels)),"snippet":"extrait \#(id)","internalDate":"\#(date)""#
        if !full, let names = metadataHeaders {
            // `format=metadata` with the headers asked for, and those only.
            var all = [("From", mail.from), ("To", mail.to), ("Subject", mail.subject), ("Message-ID", "<\(id)@exemple.fr>"),
                       ("Authentication-Results", "mx.google.com; dmarc=pass")]
            if let replyTo = mail.replyTo { all.append(("Reply-To", replyTo)) }
            if let references = mail.references { all.append(("References", references)) }
            let headers = all.filter { header in names.contains { $0.caseInsensitiveCompare(header.0) == .orderedSame } }
                .map { #"{"name":"\#($0.0)","value":"\#($0.1)"}"# }
            return text + #","payload":{"headers":[\#(headers.joined(separator: ","))]}}"#
        }
        if !full {
            var headers = [#"{"name":"Message-ID","value":"<\#(id)@exemple.fr>"}"#]
            if let replyTo = mail.replyTo { headers.append(#"{"name":"Reply-To","value":"\#(replyTo)"}"#) }
            if let references = mail.references { headers.append(#"{"name":"References","value":"\#(references)"}"#) }
            text += #","payload":{"headers":[\#(headers.joined(separator: ","))]}"#
        }
        if full {
            let html = Data((mail.body ?? "<p>Corps de \(id)</p>").utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            text += #","payload":{"mimeType":"text/html","filename":"","headers":[{"name":"From","value":"\#(mail.from)"},{"name":"To","value":"\#(mail.to)"},{"name":"Subject","value":"\#(mail.subject)"},{"name":"Authentication-Results","value":"mx.google.com; dmarc=pass"},{"name":"Content-Type","value":"text/html; charset=utf-8"}],"body":{"size":20,"data":"\#(html)"}}"#
        }
        return text + "}"
    }

    var send: MailProbe.Send {
        { [self] build in
            let request = build("jeton")
            let url = request.url!, path = url.path()
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
            let isUpload = path.hasPrefix("/upload/gmail/v1/users/me/drafts")
            let answer = try lock.withLock {
                log.append("\(request.httpMethod ?? "GET") \(path.replacingOccurrences(of: "/gmail/v1/users/me", with: ""))" + (value("format").map { " \($0)" } ?? ""))
                asked.append("\(request.httpMethod ?? "GET") \(path.replacingOccurrences(of: "/gmail/v1/users/me", with: ""))" + (url.query.map { "?\($0)" } ?? ""))
                if path.hasPrefix("/upload/gmail/v1/users/me/drafts") {
                    let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
                    let json = body.components(separatedBy: "\r\n\r\n")[1].components(separatedBy: "\r\n--")[0]
                    let raw = body.components(separatedBy: "Content-Type: message/rfc822\r\n\r\n")[1]
                    let metadata = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] ?? [:]
                    let thread = (metadata["message"] as? [String: Any])?["threadId"] as? String
                    let id: String
                    if request.httpMethod == "PUT" {
                        id = url.lastPathComponent
                        guard draftStore[id] != nil else { throw GmailAPI.error(status: 404, data: Data()) }
                    } else {
                        draftCounter += 1
                        id = "r\(draftCounter)"
                    }
                    draftCounter += 1
                    let messageID = "dm\(draftCounter)"
                    draftStore[id] = StoredDraft(raw: raw, threadID: thread, messageID: messageID)
                    return Data(#"{"id":"\#(id)","message":{"id":"\#(messageID)","threadId":"\#(thread ?? messageID)"}}"#.utf8)
                }
                if path.hasSuffix("/drafts/send") {
                    let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any] ?? [:]
                    guard let id = body["id"] as? String, let draft = draftStore.removeValue(forKey: id) else { throw GmailAPI.error(status: 404, data: Data()) }
                    let sent = "sent-\(draft.messageID)"
                    mails[sent] = Mail(thread: draft.threadID ?? sent, labels: ["SENT"], from: "Moi <moi@exemple.fr>", subject: "envoyé")
                    order.insert(sent, at: 0)
                    records.append(#"{"messagesAdded":[{"message":{"id":"\#(sent)","threadId":"\#(draft.threadID ?? sent)","labelIds":["SENT"]}}]}"#)
                    return Data(#"{"id":"\#(sent)"}"#.utf8)
                }
                if path.contains("/drafts/"), request.httpMethod == "GET" {
                    guard let draft = draftStore[url.lastPathComponent] else { throw GmailAPI.error(status: 404, data: Data()) }
                    return Data(#"{"id":"\#(url.lastPathComponent)","message":{"id":"\#(draft.messageID)"}}"#.utf8)
                }
                if path.contains("/drafts/"), request.httpMethod == "DELETE" {
                    guard draftStore.removeValue(forKey: url.lastPathComponent) != nil else { throw GmailAPI.error(status: 404, data: Data()) }
                    return Data()
                }
                if path.hasSuffix("/drafts") {
                    let items = draftStore.map { #"{"id":"\#($0.key)","message":{"id":"\#($0.value.messageID)"}}"# }
                    return Data(#"{"drafts":[\#(items.joined(separator: ","))]}"#.utf8)
                }
                if path.hasSuffix("/settings/sendAs") {
                    return Data(#"{"sendAs":[{"sendAsEmail":"moi@exemple.fr","displayName":"Moi Exemple","signature":"\#(signature)","isPrimary":true}]}"#.utf8)
                }
                if path.hasSuffix("/profile") {
                    return Data(#"{"emailAddress":"moi@exemple.fr","messagesTotal":\#(order.count),"threadsTotal":1,"historyId":"\#(cursor)"}"#.utf8)
                }
                if path.hasSuffix("/messages/batchModify") {
                    if let status = nextModifyStatus {
                        nextModifyStatus = nil
                        throw GmailAPI.error(status: status, data: Data())
                    }
                    let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any] ?? [:]
                    let add = body["addLabelIds"] as? [String] ?? [], remove = body["removeLabelIds"] as? [String] ?? []
                    for id in body["ids"] as? [String] ?? [] {
                        guard var mail = mails[id] else { continue }
                        mail.labels = mail.labels.filter { !remove.contains($0) } + add.filter { !mail.labels.contains($0) }
                        mails[id] = mail
                    }
                    return Data()
                }
                if path.hasSuffix("/untrash") {
                    let id = url.deletingLastPathComponent().lastPathComponent
                    mails[id]?.labels.removeAll { $0 == "TRASH" }
                    return Data(#"{"id":"\#(id)"}"#.utf8)
                }
                if path.hasSuffix("/messages") {
                    let labels = items.filter { $0.name == "labelIds" }.compactMap(\.value)
                    // As Gmail: the spam and the trash only when asked for (`includeSpamTrash`).
                    let aside = value("includeSpamTrash") == "true"
                    let ids = order.filter { id in
                        let mail = mails[id]!
                        return (aside || (!mail.labels.contains("TRASH") && !mail.labels.contains("SPAM"))) && labels.allSatisfy(mail.labels.contains)
                    }
                    .prefix(value("maxResults").flatMap(Int.init) ?? 500)
                    return Data(#"{"messages":[\#(ids.map { #"{"id":"\#($0)"}"# }.joined(separator: ","))]}"#.utf8)
                }
                if path.hasSuffix("/history") {
                    if forgot {
                        forgot = false
                        records = []
                        throw GmailAPI.error(status: 404, data: Data())
                    }
                    cursor += 1
                    defer { records = [] }
                    return Data(#"{"history":[\#(records.joined(separator: ","))],"historyId":"\#(cursor)"}"#.utf8)
                }
                if path.hasSuffix("/threads") {
                    let threads = Array(Set(order.compactMap { mails[$0]?.thread })).sorted()
                    return Data(#"{"threads":[\#(threads.map { #"{"id":"\#($0)"}"# }.joined(separator: ","))]}"#.utf8)
                }
                if path.contains("/threads/") {
                    let thread = url.lastPathComponent
                    let messages = order.filter { mails[$0]?.thread == thread }.compactMap { message($0, full: true) }
                    return Data(#"{"id":"\#(thread)","messages":[\#(messages.joined(separator: ","))]}"#.utf8)
                }
                if path.contains("/messages/") {
                    let headers = items.filter { $0.name == "metadataHeaders" }.compactMap(\.value)
                    guard let text = message(url.lastPathComponent, full: value("format") == "full",
                                             metadataHeaders: value("format") == "metadata" ? headers : nil) else { throw GmailAPI.error(status: 404, data: Data()) }
                    return Data(text.utf8)
                }
                throw GoogleError.http(599)
            }
            if isUpload, let delay = lock.withLock({ slowUpload }) { try await Task.sleep(for: delay) }
            return answer
        }
    }
}

/// 14/11, step « Lire »: the copy follows Gmail, and Paul's gestures reach it message by message.
@Suite struct MailEngineTests {
    let account = "moi@exemple.fr"

    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var date = Date(timeIntervalSince1970: 1_794_562_920)
        /// Each look at the clock is a minute later: the pacer never has to wait.
        var now: Date { lock.withLock { date += 61; return date } }
    }

    final class Arrivals: @unchecked Sendable {
        private let lock = NSLock()
        private var ids: [String] = []
        func add(_ rows: [MailMessageRow]) { lock.withLock { ids += rows.map(\.messageID) } }
        var all: [String] { lock.withLock { ids } }
    }

    func setUp(flavor: AppFlavor = .prod, arrivals: Arrivals = Arrivals()) throws -> (MailEngine, FakeGmail, MailStore, URL) {
        let database = try AppDatabase.inMemory()
        try CalendarStore(database).addAccount(email: account, at: Date(timeIntervalSince1970: 1_794_562_920))
        let gmail = FakeGmail(), clock = Clock()
        let root = FileManager.default.temporaryDirectory.appending(path: "mails-\(UUID().uuidString)", directoryHint: .isDirectory)
        let engine = MailEngine(database: database, root: root, sendFor: { _ in gmail.send }, flavor: flavor, now: { clock.now }, pause: { _ in },
                                onNew: { arrivals.add($0) })
        return (engine, gmail, MailStore(database), root)
    }

    func key(_ thread: String) -> String { MailThreadRow.key(account: account, threadID: thread) }

    @Test func theFirstReadingTakesEverythingTheMostRecentFirst() async throws {
        let (engine, gmail, store, root) = try setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 1...45 { gmail.add("m\(index)", .init(thread: "t\(index)", labels: ["INBOX", "UNREAD"], minutes: Double(index)), history: false) }
        #expect(await engine.step(account))
        var cursor = try #require(try store.cursor(account: account))
        #expect(cursor.total == 45 && cursor.done == 20 && cursor.finishedAt == nil && cursor.historyID != nil)
        // The most recent mails are there first.
        #expect(try store.inbox().first?.threadID == "t45" && store.inbox().count == 20)
        #expect(await engine.step(account))
        #expect(!(await engine.step(account)))
        cursor = try #require(try store.cursor(account: account))
        #expect(cursor.done == 45 && cursor.finishedAt != nil && cursor.lastError == nil)
        #expect(try store.inbox().count == 45)
        // The body is in its file, as the sender wrote it; the row says so.
        let message = try #require(try store.messages(threadKey: key("t7")).first)
        #expect(message.hasBody && message.bodyIsHTML && message.authenticated && message.sender?.email == "camille@exemple.fr")
        #expect(try String(contentsOf: engine.files.body(of: message), encoding: .utf8) == "<p>Corps de m7</p>")
        #expect(try await engine.body(of: message) == "<p>Corps de m7</p>")
        // Nothing is read twice once the first reading is over.
        let reads = gmail.calls.filter { $0.hasSuffix(" full") }.count
        #expect(reads == 45)
        await engine.step(account)
        #expect(gmail.calls.filter { $0.hasSuffix(" full") }.count == 45)
    }

    @Test func whatIsNewSinceLastTimeArrives() async throws {
        let arrivals = Arrivals()
        let (engine, gmail, store, root) = try setUp(arrivals: arrivals)
        defer { try? FileManager.default.removeItem(at: root) }
        gmail.add("m1", .init(thread: "t1", labels: ["INBOX", "UNREAD"]), history: false)
        gmail.add("m2", .init(thread: "t2", labels: ["INBOX"], minutes: 1), history: false)
        await engine.step(account)
        #expect(arrivals.all.isEmpty)
        // A reply arrives, the phone marks m1 read and deletes m2 for good.
        gmail.add("m3", .init(thread: "t1", labels: ["INBOX", "UNREAD"], minutes: 5))
        gmail.change("m1", labels: ["INBOX"])
        gmail.change("m2", labels: nil)
        let before = try #require(try store.cursor(account: account)?.historyID)
        await engine.step(account)
        let thread = try #require(try store.thread(key("t1")))
        #expect(thread.messageCount == 2 && thread.unread && thread.snippet == "extrait m3")
        #expect(try store.messages(threadKey: key("t1")).first?.isUnread == false)
        #expect(try store.thread(key("t2")) == nil)
        #expect(try store.cursor(account: account)?.historyID != before)
        // Only what just arrived in the inbox is announced, never the first reading.
        #expect(arrivals.all == ["m3"])
    }

    /// The Mac stayed closed for weeks: Gmail forgot the cursor. The inbox and the unread are set from Gmail's own
    /// lists, what it no longer has goes, and what is new is read.
    @Test func aForgottenCursorPutsTheCopySquareAgain() async throws {
        let (engine, gmail, store, root) = try setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        gmail.add("m1", .init(thread: "t1", labels: ["INBOX", "UNREAD"]), history: false)
        gmail.add("m2", .init(thread: "t2", labels: ["INBOX"], minutes: 1), history: false)
        await engine.step(account)
        gmail.change("m1", labels: ["CATEGORY_PERSONAL"], history: false)   // archived and read on the phone
        gmail.change("m2", labels: nil, history: false)
        gmail.add("m3", .init(thread: "t3", labels: ["INBOX", "UNREAD"], minutes: 9), history: false)
        gmail.forgetCursors()
        await engine.step(account)
        #expect(try store.thread(key("t1"))?.inInbox == false && store.thread(key("t1"))?.unread == false)
        #expect(try store.thread(key("t2")) == nil)
        await engine.step(account)
        #expect(try store.inbox().map(\.threadID) == ["t3"])
        #expect(try store.cursor(account: account)?.finishedAt != nil)
    }

    @Test func aGestureChangesTheCopyAtOnceAndReachesGmailByItsMessages() async throws {
        let (engine, gmail, store, root) = try setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        gmail.add("m1", .init(thread: "t1", labels: ["INBOX", "UNREAD"]), history: false)
        await engine.step(account)
        let gesture = try #require(try await engine.perform(.archive, threadKey: key("t1")))
        #expect(try store.inbox().isEmpty)
        // The client replies before the gesture left: the reply is not archived with the rest.
        gmail.add("m2", .init(thread: "t1", labels: ["INBOX", "UNREAD"], minutes: 3))
        await engine.step(account)
        #expect(gmail.labels("m1") == ["UNREAD"] && gmail.labels("m2") == ["INBOX", "UNREAD"])
        #expect(try store.pendingGestures(account: account).isEmpty)
        #expect(try store.inbox().first?.messageCount == 2)
        #expect(gesture.messageIDs == ["m1"])
        // Trash, then undo: the mails come back to the inbox.
        let trash = try #require(try await engine.perform(.trash, threadKey: key("t1")))
        await engine.step(account)
        #expect(gmail.labels("m1")?.contains("TRASH") == true && gmail.labels("m2")?.contains("INBOX") == false)
        try await engine.undo(trash)
        #expect(try store.inbox().count == 1)
        await engine.step(account)
        #expect(gmail.labels("m2")?.contains("TRASH") == false && gmail.labels("m2")?.contains("INBOX") == true)
        #expect(gmail.calls.filter { $0.hasSuffix("/untrash") }.count == 2)
    }

    @Test func aPassingRefusalKeepsTheGestureAFinalOneDropsIt() async throws {
        let (engine, gmail, store, root) = try setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        gmail.add("m1", .init(thread: "t1", labels: ["INBOX", "UNREAD"]), history: false)
        await engine.step(account)
        try await engine.perform(.markRead, threadKey: key("t1"))
        gmail.failNextModify(429)
        await engine.step(account)
        let waiting = try store.pendingGestures(account: account)
        #expect(waiting.count == 1 && waiting.first?.attempts == 1)
        #expect(try store.thread(key("t1"))?.unread == false)
        await engine.step(account)
        #expect(try store.pendingGestures(account: account).isEmpty && gmail.labels("m1") == ["INBOX"])
        // The message is gone at Gmail's: the gesture is dropped, nothing loops.
        try await engine.perform(.archive, threadKey: key("t1"))
        gmail.failNextModify(404)
        await engine.step(account)
        #expect(try store.pendingGestures(account: account).isEmpty)
    }

    /// The development build shares the key and the Keychain: it only ever reads the real mailboxes.
    @Test func theDevelopmentBuildMakesNoGesture() async throws {
        let (engine, gmail, store, root) = try setUp(flavor: .dev)
        defer { try? FileManager.default.removeItem(at: root) }
        gmail.add("m1", .init(thread: "t1", labels: ["INBOX", "UNREAD"]), history: false)
        await engine.step(account)
        await #expect(throws: GoogleError.readOnlyBuild) { try await engine.perform(.trash, threadKey: key("t1")) }
        #expect(try store.pendingGestures(account: account).isEmpty && store.inbox().count == 1)
        #expect(!gmail.calls.contains { $0.hasPrefix("POST") })
    }

    @Test func aSearchBringsThreadsTheCopyDidNotHave() async throws {
        let (engine, gmail, store, root) = try setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        gmail.add("m1", .init(thread: "t1", labels: ["INBOX"]), history: false)
        await engine.step(account)
        gmail.add("m9", .init(thread: "t9", labels: ["CATEGORY_PERSONAL"], subject: "Vieux devis"), history: false)
        let keys = try await engine.search("devis", accounts: [account])
        #expect(Set(keys) == [key("t1"), key("t9")])
        #expect(try store.threads(keys: keys).map(\.subject).sorted() == ["Maquette v2", "Vieux devis"])
        #expect(try store.inbox().count == 1)
    }

    /// 14/11: Gmail gives UTF-8 even when the part says iso-8859-1; a real Latin-1 body still reads right.
    @Test func accentsReadRightWhateverTheDeclaredSet() throws {
        let utf8 = Data("avec un accès limité à".utf8)
        #expect(MailParser.text(utf8, declared: "iso-8859-1") == "avec un accès limité à")
        let latin = "Réunion à 14 h".data(using: .isoLatin1)!
        #expect(MailParser.text(latin, declared: "iso-8859-1") == "Réunion à 14 h")
        #expect(MailParser.text(latin, declared: "utf-8") == "Réunion à 14 h")
        #expect(MailParser.text(Data([0x93, 0x6F, 0x6B, 0x94]), declared: "us-ascii") == "“ok”")
        // A body kept before the fix is put right, a sound one is left alone.
        let broken = String(data: utf8, encoding: .isoLatin1)!
        #expect(broken.contains("Ã¨") && MailParser.repaired(broken) == "avec un accès limité à")
        #expect(MailParser.repaired("avec un accès limité à") == nil)
        #expect(MailParser.repaired("rien à réparer : Ãtrange") == nil)
        // Encoded words in a header take the same road.
        #expect(MailParser.decodedWords("=?ISO-8859-1?Q?R=E9union?=") == "Réunion")
    }

    @Test func theBodiesKeptInTheWrongSetArePutRightOnce() async throws {
        let (engine, _, _, root) = try setUp()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = engine.files.folder(account: account)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let broken = String(data: Data("<p>accès limité</p>".utf8), encoding: .isoLatin1)!
        try Data(broken.utf8).write(to: folder.appending(path: "m1.html"))
        try Data("<p>déjà bon</p>".utf8).write(to: folder.appending(path: "m2.html"))
        await engine.repairCharsets(account)
        #expect(try String(contentsOf: folder.appending(path: "m1.html"), encoding: .utf8) == "<p>accès limité</p>")
        #expect(try String(contentsOf: folder.appending(path: "m2.html"), encoding: .utf8) == "<p>déjà bon</p>")
        // Done once: a body written afterwards is never touched again.
        try Data(broken.utf8).write(to: folder.appending(path: "m3.html"))
        await engine.repairCharsets(account)
        #expect(try String(contentsOf: folder.appending(path: "m3.html"), encoding: .utf8) == broken)
    }

    @Test func aMessageIsReadAsItsSenderWroteIt() throws {
        let html = Data(#"<html><body>Bonjour <img src="cid:logo@exemple"></body></html>"#.utf8).base64EncodedString()
        let png = Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString()
        let json = #"""
        {"id":"m1","threadId":"t1","labelIds":["INBOX","UNREAD"],"snippet":"L&#39;atelier &amp; la suite","internalDate":"1794562920000",
         "payload":{"mimeType":"multipart/mixed","headers":[
           {"name":"From","value":"\"Durand, Jules\" <Jules@Exemple.fr>"},
           {"name":"To","value":"moi@exemple.fr, =?UTF-8?Q?Camille_Mart=C3=ADn?= <camille@exemple.fr>"},
           {"name":"Subject","value":"=?UTF-8?B?UsOpdW5pb24=?= de lundi"},
           {"name":"Message-ID","value":"<abc@exemple.fr>"},
           {"name":"Authentication-Results","value":"mx.google.com; dkim=pass; dmarc=fail"},
           {"name":"List-Unsubscribe","value":"<https://exemple.fr/stop>"}],
          "parts":[
           {"partId":"0","mimeType":"text/html","filename":"","headers":[{"name":"Content-Type","value":"text/html; charset=utf-8"}],"body":{"size":40,"data":"\#(html)"}},
           {"partId":"1","mimeType":"image/png","filename":"logo.png","headers":[{"name":"Content-ID","value":"<logo@exemple>"}],"body":{"size":4,"data":"\#(png)"}},
           {"partId":"2","mimeType":"application/pdf","filename":"../../devis final.pdf","body":{"size":245000,"attachmentId":"a1"}}]}}
        """#
        let mail = MailParser.parse(try GmailAPI.decode(GmailAPI.Message.self, from: Data(json.utf8)), account: "Moi@Exemple.fr")
        #expect(mail.row.id == "moi@exemple.fr|m1" && mail.row.threadKey == "moi@exemple.fr|t1")
        #expect(mail.row.sender == MailAddress(name: "Durand, Jules", email: "jules@exemple.fr"))
        #expect(mail.row.to == [MailAddress(email: "moi@exemple.fr"), MailAddress(name: "Camille Martín", email: "camille@exemple.fr")])
        #expect(mail.row.subject == "Réunion de lundi" && mail.row.snippet == "L'atelier & la suite")
        #expect(mail.row.date == Date(timeIntervalSince1970: 1_794_562_920) && mail.row.rfcMessageID == "<abc@exemple.fr>")
        // Gmail did not confirm the sender: the row says so.
        #expect(!mail.row.authenticated && mail.row.listUnsubscribe == "<https://exemple.fr/stop>")
        #expect(mail.body == #"<html><body>Bonjour <img src="cid:logo@exemple"></body></html>"# && mail.row.bodyIsHTML)
        // The logo is shown by the HTML; the PDF is a file, under a name that cannot leave its folder.
        #expect(mail.row.attachments.map(\.inline) == [true, false] && mail.inline["1"] == Data([0x89, 0x50, 0x4E, 0x47]))
        #expect(mail.row.files.map(\.filename) == ["devis final.pdf"] && mail.row.files.first?.attachmentID == "a1")
        #expect(AttachmentSafety.canOpen(name: "devis final.pdf") && !AttachmentSafety.canOpen(name: "facture.pdf.html") && !AttachmentSafety.canOpen(name: "outil.dmg"))
        #expect(AttachmentSafety.cleanName(".caché") == "caché" && AttachmentSafety.cleanName("///") == "piece-jointe")
    }
}
