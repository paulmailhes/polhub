import Colin
import Domain
import Foundation
import LocalServer
import Mail
import Persistence
import HubDesign
import HubLink

/// What hub on the Mac answers hub on the iPhone (20/11): the same mails, folders, calendar, projects and
/// meetings as the window, in JSON. Every request carries the token of a paired iPhone; read only in this version.
@MainActor
final class PhoneAPI {
    let devices: PhoneDevices
    let database: AppDatabase
    let agenda: AgendaLibrary?
    let mails: MailLibrary?
    /// Colin's thread, the Accueil's (lot 3, 20/11).
    let colin: ColinThread?
    /// The number on hub's icon (20/11), set by the app.
    var badge: (@MainActor () -> Int)?
    let appVersion: String
    let now: () -> Date

    init(devices: PhoneDevices, database: AppDatabase, agenda: AgendaLibrary?, mails: MailLibrary?, colin: ColinThread? = nil, appVersion: String,
         now: @escaping () -> Date = Date.init) {
        self.devices = devices
        self.database = database
        self.agenda = agenda
        self.mails = mails
        self.colin = colin
        self.appVersion = appVersion
        self.now = now
    }

    /// To read; to write (lot 3, 20/11).
    static let read = "GET"
    static let write = "POST"

    /// The message of a token the Mac does not know.
    static let notPaired = "Cet iPhone n'est plus relié au Mac : relie-le de nouveau depuis Réglages › iPhone sur le Mac."

    func respond(_ request: HTTPRequest) async -> HTTPResponse {
        guard let device = devices.device(for: LinkAPI.token(fromAuthorization: request.header(LinkAPI.authorization)), now: now()) else {
            return Self.error(Self.notPaired, status: 401)
        }
        do {
            if request.method == Self.write { return try await written(request, device: device) }
            guard request.method == Self.read else { return Self.error("Cette demande n'existe pas.", status: 405) }
            switch request.path {
            case LinkAPI.Path.status:
                return try Self.json(LinkStatus(appVersion: appVersion, device: device.name, badge: badge?()))
            case LinkAPI.Path.folders:
                return try Self.json(try folders())
            case LinkAPI.Path.threads:
                return try Self.json(try threads(in: request.query["dossier"] ?? "inbox", limit: Int(request.query["limite"] ?? "") ?? 100))
            case LinkAPI.Path.thread:
                return try Self.json(try await thread(request.query["fil"] ?? "", dark: request.query["sombre"] == "1"))
            case LinkAPI.Path.file:
                return try await file(message: request.query["message"] ?? "", part: request.query["piece"] ?? "")
            case LinkAPI.Path.events:
                return try Self.json(try events(from: Self.day(request.query["du"]), to: Self.day(request.query["au"])))
            case LinkAPI.Path.projects:
                return try Self.json(try projects())
            case LinkAPI.Path.project:
                return try Self.json(try project(request.query["id"] ?? ""))
            case LinkAPI.Path.meetings:
                return try Self.json(try meetings(limit: Int(request.query["limite"] ?? "") ?? 50))
            case LinkAPI.Path.meeting:
                return try Self.json(try meeting(request.query["id"] ?? ""))
            case LinkAPI.Path.accounts:
                return try Self.json(mails?.accounts.map(\.email) ?? [])
            case LinkAPI.Path.sending:
                return try Self.json(sending())
            case LinkAPI.Path.colin:
                return try Self.json(try colinThread())
            default:
                return Self.error("Cette demande n'existe pas.", status: 404)
            }
        } catch let error as LinkError {
            // A thing that is not there, or a mail that cannot leave as it is.
            return Self.error(error.message, status: request.method == Self.write ? 409 : 404)
        } catch {
            return Self.error("Le Mac n'a pas pu répondre. Réessaie dans un instant.", status: 503)
        }
    }

    // MARK: - Mails

    /// The folders the iPhone shows, in the Mac's order.
    static let folderOrder: [MailFolder] = [.inbox, .notifications, .sent, .all]

    func folders() throws -> [LinkFolder] {
        guard let mails else { return [] }
        return Self.folderOrder.map { folder in
            let unread = switch folder {
            case .inbox: mails.unread(in: .personnes)
            case .notifications: mails.unread(in: .notifications)
            default: 0
            }
            return LinkFolder(id: folder.rawValue, title: folder.title, unread: unread)
        }
    }

    func threads(in folder: String, limit: Int) throws -> [LinkThread] {
        guard let mails else { return [] }
        guard let folder = MailFolder(rawValue: folder), Self.folderOrder.contains(folder) else { throw LinkError("Ce dossier n'existe pas.") }
        let rows: [MailThreadRow] = switch folder {
        case .inbox: mails.inbox.filter { mails.tab(of: $0) == .personnes }
        case .notifications: mails.inbox.filter { mails.tab(of: $0) == .notifications }
        case .sent: mails.sent
        default: mails.all
        }
        return rows.prefix(max(1, min(limit, 500))).map(link)
    }

    func link(_ thread: MailThreadRow) -> LinkThread {
        let project: ProjectRow? = if case .project(let id)? = mails?.filing(of: thread)?.filing { mails?.project(id) } else { nil }
        return LinkThread(id: thread.id, account: thread.account, subject: thread.subject.isEmpty ? Words.noSubject : thread.subject,
                          people: MailText.names(thread, mine: mails?.mine ?? []), snippet: thread.snippet, date: thread.lastMessageAt,
                          unread: thread.unread, messages: thread.messageCount, hasFiles: thread.hasAttachment, project: project?.name,
                          projectColor: project?.color, sender: thread.lastSender ?? thread.senders.last?.email)
    }

    /// A thread whole, its bodies as the Mac shows them (made safe, without remote images); read once opened, as on the
    /// Mac.
    func thread(_ key: String, dark: Bool) async throws -> LinkThreadDetail {
        guard let mails, let row = try mails.store.thread(key) else { throw LinkError("Ce fil n'existe plus.") }
        var messages: [LinkMessage] = []
        for message in try mails.store.messages(threadKey: key) {
            let body = (try? await mails.engine.read(message)) ?? (text: message.snippet, isHTML: false)
            let html = MailHTML.document(body: body.text, isHTML: body.isHTML, images: false, collapseQuote: true, dark: dark)
            messages.append(LinkMessage(id: message.id, from: message.sender.map(Self.person), to: message.to.map(Self.person),
                                        cc: message.cc.map(Self.person), date: message.date, html: html,
                                        files: message.files.map { LinkFile(id: $0.partID, name: $0.filename, mimeType: $0.mimeType, size: $0.size) },
                                        authenticated: message.authenticated, snippet: message.snippet))
        }
        if row.unread { mails.markRead(row) }
        var thread = link(row)
        thread.unread = false
        return LinkThreadDetail(thread: thread, messages: messages, reader: MailHTML.readerScript)
    }

    func file(message key: String, part: String) async throws -> HTTPResponse {
        guard let mails, let message = try mails.store.message(key), let attachment = message.files.first(where: { $0.partID == part }) else {
            throw LinkError("Cette pièce jointe n'existe plus.")
        }
        let url = try await mails.engine.file(attachment, of: message)
        return .file(try Data(contentsOf: url), type: attachment.mimeType, name: attachment.filename)
    }

    static func person(_ address: MailAddress) -> LinkPerson {
        LinkPerson(name: address.name, email: address.email)
    }

    // MARK: - Writing (lot 3, 20/11)

    /// What a POST asks: a reply, a new mail, a call back, a question for Colin, a change undone.
    func written(_ request: HTTPRequest, device: PhoneDevice) async throws -> HTTPResponse {
        func body<Value: Decodable>(_ type: Value.Type) throws -> Value {
            guard let value = try? LinkAPI.decoder.decode(type, from: request.body) else { throw LinkError("Cette demande est illisible.") }
            return value
        }
        switch request.path {
        case LinkAPI.Path.reply:
            return try Self.json(try await reply(try body(LinkReply.self)))
        case LinkAPI.Path.newMail:
            return try Self.json(try newMail(try body(LinkNewMail.self)))
        case LinkAPI.Path.cancel:
            let cancel = try body(LinkCancel.self)
            if let mails, mails.sending?.draftID == cancel.draftID { mails.cancelSend(quietly: true) }
            return try Self.json(sending())
        case LinkAPI.Path.colin:
            let question = try body(LinkQuestion.self)
            guard let colin else { throw LinkError("Colin n'est pas sur ce Mac.") }
            let text = question.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw LinkError("La question est vide.") }
            guard !colin.isAnswering else { throw LinkError("Colin répond déjà : attends la fin de sa réponse.") }
            colin.draft = text
            colin.send()
            return try Self.json(try colinThread())
        case LinkAPI.Path.gesture:
            // A swipe on the iPhone (20/11): the Mac's own gesture, sent to Gmail as it does for its own.
            let gesture = try body(LinkGesture.self)
            let kind: MailGestureKind? = switch gesture.kind {
            case LinkGesture.trash: .trash
            case LinkGesture.archive: .archive
            case LinkGesture.read: .markRead
            case LinkGesture.unread: .markUnread
            default: nil
            }
            guard let kind else { throw LinkError("Ce geste n'existe pas.") }
            guard let mails, let row = try mails.store.thread(gesture.thread) else { throw LinkError("Ce fil n'existe plus.") }
            mails.perform(kind, on: row, undoable: false)
            return try Self.json(LinkStatus(appVersion: appVersion, device: device.name, badge: badge?()))
        case LinkAPI.Path.push:
            let push = try body(LinkPushToken.self)
            let token = push.token.filter(\.isHexDigit)
            guard token.count >= 32 else { throw LinkError("Ce jeton de notifications est illisible.") }
            devices.setPushToken(token, for: device.id)
            return try Self.json(LinkStatus(appVersion: appVersion, device: device.name, badge: badge?()))
        case LinkAPI.Path.colinUndo:
            let undo = try body(LinkUndo.self)
            guard let colin, let line = colin.changes.first(where: { $0.id == undo.id }) else { throw LinkError("Ce changement n'existe plus.") }
            colin.undo(line)
            return try Self.json(try colinThread())
        default:
            return Self.error("Cette demande n'existe pas.", status: 404)
        }
    }

    /// The mail leaving, while it can be called back.
    func sending() -> LinkSending? {
        mails?.sending.map { LinkSending(draftID: $0.draftID, subject: $0.subject, at: $0.at, leaving: $0.leaving) }
    }

    /// A reply under the thread's last message, written as on the Mac (its people, its quote, its signature), then sent
    /// with the delay of Réglages › Mails.
    func reply(_ reply: LinkReply) async throws -> LinkSending {
        guard let mails, let thread = try mails.store.thread(reply.thread), let last = try mails.store.messages(threadKey: reply.thread).last else {
            throw LinkError("Ce fil n'existe plus.")
        }
        guard !reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LinkError("La réponse est vide.") }
        guard let draftID = await mails.startReply(reply.all ? .replyAll : .reply, to: last, in: thread) else {
            throw LinkError(mails.message ?? "La réponse n'a pas pu être préparée.")
        }
        mails.edit(draftID) { $0.body = reply.text }
        return try send(draftID)
    }

    func newMail(_ mail: LinkNewMail) throws -> LinkSending {
        guard let mails else { throw LinkError("Les mails ne sont pas sur ce Mac.") }
        let accounts = mails.accounts.map(\.email)
        guard let account = mail.account.flatMap({ accounts.contains($0) ? $0 : nil }) ?? accounts.first else {
            throw LinkError("Aucune boîte mail n'est reliée au Mac.")
        }
        func people(_ list: [String]) -> [MailAddress] {
            list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.map { MailAddress(name: nil, email: $0) }
        }
        let draft = MailDraftRow(account: account, mode: .new, to: people(mail.to), cc: people(mail.cc), subject: mail.subject, body: mail.text,
                                 createdAt: now())
        try mails.store.saveDraft(draft)
        return try send(draft.id)
    }

    /// Sent as on the Mac; what stops it (no one to write to, a bad address) said in hub's words.
    func send(_ draftID: String) throws -> LinkSending {
        guard let mails else { throw LinkError("Les mails ne sont pas sur ce Mac.") }
        if let other = mails.sending, other.draftID != draftID { throw LinkError("Un autre mail part en ce moment : réessaie dans quelques secondes.") }
        mails.send(draftID)
        guard let sending = sending(), sending.draftID == draftID else {
            throw LinkError(mails.message ?? "Le mail n'est pas parti : il t'attend dans Brouillons sur le Mac.")
        }
        return sending
    }

    // MARK: - Colin (lot 3, 20/11)

    func colinThread() throws -> LinkColin {
        guard let colin else { throw LinkError("Colin n'est pas sur ce Mac.") }
        let state = ColinState(colin.status, answering: colin.isAnswering)
        let problem: String? = if case .broken(let sentence) = colin.status { sentence } else { nil }
        let calendar = Words.calendar
        let messages = colin.messages.suffix(60).map { message in
            LinkColinMessage(id: message.id, fromPaul: message.author == .paul, text: message.text, state: message.state.rawValue,
                             date: message.createdAt)
        }
        let changes = colin.changes.suffix(30).map { line in
            LinkChange(id: line.id, project: line.projectName, at: line.at, note: ChangeText.note(line), created: ChangeText.isCreation(line),
                       fields: ChangeText.fields(line, calendar: calendar).map { LinkChangeField(label: $0.label, before: $0.before, after: $0.after) },
                       undone: line.undoneAt != nil)
        }
        return LinkColin(state: state.label, answering: colin.isAnswering, streaming: colin.visible, problem: problem, messages: Array(messages),
                         changes: Array(changes))
    }

    // MARK: - Calendar

    /// From yesterday to two weeks ahead by default; never more than the Mac's copy (60 days).
    func events(from: Date?, to: Date?) throws -> [LinkEvent] {
        let calendar = Words.calendar
        let today = calendar.startOfDay(for: now())
        let start = from ?? calendar.date(byAdding: .day, value: -1, to: today)!
        let end = to ?? calendar.date(byAdding: .day, value: 15, to: today)!
        let store = CalendarStore(database)
        let colors = Dictionary((try store.accounts()).map { ($0.email, $0.color) }, uniquingKeysWith: { first, _ in first })
        let names = projectNames()
        return try store.events(from: start, to: end).map { event in
            link(event, color: colors[event.account] ?? nil, project: event.projectID.flatMap { names[$0] })
        }
    }

    func link(_ event: CalendarEventRow, color: String?, project: String?) -> LinkEvent {
        LinkEvent(id: event.id, title: event.title.isEmpty ? CalendarEventRow.untitledTitle : event.title, start: event.startAt, end: event.endAt,
                  allDay: event.allDay, account: event.account, color: color,
                  meet: event.meetCode.flatMap { URL(string: "https://meet.google.com/\($0)") }, location: event.location, project: project)
    }

    // MARK: - Projects

    func projectNames() -> [UUID: String] {
        Dictionary(((try? ProjectStore(database).projects()) ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// The board's columns in their order, each in its own order; the trash apart.
    func projects() throws -> [LinkProject] {
        let rows = try ProjectStore(database).projects().filter { $0.deletedAt == nil }
        return ProjectStatus.boardOrder.flatMap { status in
            rows.filter { $0.status == status }.sorted { $0.kanbanOrder < $1.kanbanOrder }.map(Self.link)
        }
    }

    static func link(_ project: ProjectRow) -> LinkProject {
        LinkProject(id: project.id, name: project.name, status: project.status.rawValue, client: project.client, due: project.dueDate,
                    task: project.todo, color: project.color)
    }

    func project(_ id: String) throws -> LinkProjectDetail {
        let store = ProjectStore(database)
        guard let uuid = UUID(uuidString: id), let row = try store.project(id: uuid), row.deletedAt == nil else {
            throw LinkError("Ce projet n'existe plus.")
        }
        let actions = try store.actions(projectID: uuid).sorted { $0.position < $1.position }
            .map { LinkAction(id: $0.id, text: $0.text, done: $0.done, due: $0.dueDate) }
        let journal = try store.journal(projectID: uuid).sorted { $0.date > $1.date }
            .map { LinkJournalEntry(id: $0.id, date: $0.date, title: $0.title, text: $0.body) }
        let calendar = CalendarStore(database)
        let colors = Dictionary((try calendar.accounts()).map { ($0.email, $0.color) }, uniquingKeysWith: { first, _ in first })
        let events = try calendar.events(projectID: uuid).filter { $0.endAt >= now() }.sorted { $0.startAt < $1.startAt }.prefix(10)
            .map { link($0, color: colors[$0.account] ?? nil, project: row.name) }
        return LinkProjectDetail(project: Self.link(row), notes: row.notes, actions: actions, journal: journal, events: Array(events))
    }

    // MARK: - Meetings

    func meetings(limit: Int) throws -> [LinkMeeting] {
        let store = MeetingStore(database)
        let names = projectNames()
        return try store.recent(limit: max(1, min(limit, 200))).filter { $0.deletedAt == nil }.map { row in
            try link(row, project: row.projectID.flatMap { names[$0] }, hasSummary: !(try store.summary(meetingID: row.id) ?? "").isEmpty)
        }
    }

    func link(_ row: MeetingRow, project: String?, hasSummary: Bool) throws -> LinkMeeting {
        LinkMeeting(id: row.id, title: row.title, start: row.startedAt, seconds: row.endedAt.map { Int($0.timeIntervalSince(row.startedAt)) },
                    project: project, hasSummary: hasSummary)
    }

    func meeting(_ id: String) throws -> LinkMeetingDetail {
        let store = MeetingStore(database)
        guard let uuid = UUID(uuidString: id), let row = try store.meeting(id: uuid), row.deletedAt == nil else {
            throw LinkError("Cette réunion n'existe plus.")
        }
        let summary = try store.summary(meetingID: uuid).flatMap { $0.isEmpty ? nil : $0 }
        let turns = try TranscriptStore(database).utterances(meetingID: uuid)
            .map { LinkTurn(speaker: $0.speaker.label, start: $0.startMs / 1_000, text: $0.text, doubtful: $0.doubtful) }
        let project = row.projectID.flatMap { projectNames()[$0] }
        return LinkMeetingDetail(meeting: try link(row, project: project, hasSummary: summary != nil), summary: summary, turns: turns)
    }

    // MARK: - Answers

    static func json(_ value: some Encodable) throws -> HTTPResponse {
        .json(try LinkAPI.encoder.encode(value))
    }

    static func error(_ message: String, status: Int) -> HTTPResponse {
        .json((try? LinkAPI.encoder.encode(LinkError(message))) ?? Data(), status: status)
    }

    /// « 2026-11-20 »: a day, from its midnight on the Mac.
    static func day(_ text: String?, calendar: Calendar = Words.calendar) -> Date? {
        let parts = (text ?? "").split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
