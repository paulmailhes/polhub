import Domain
import Foundation
import LocalServer
import Mail
import Persistence
import PolhubDesign
import PolhubLink

/// What Polhub on the Mac answers Polhub on the iPhone (20/11): the same mails, folders, calendar, projects and
/// meetings as the window, in JSON. Every request carries the token of a paired iPhone; read only in this version.
@MainActor
final class PhoneAPI {
    let devices: PhoneDevices
    let database: AppDatabase
    let agenda: AgendaLibrary?
    let mails: MailLibrary?
    let appVersion: String
    let now: () -> Date

    init(devices: PhoneDevices, database: AppDatabase, agenda: AgendaLibrary?, mails: MailLibrary?, appVersion: String,
         now: @escaping () -> Date = Date.init) {
        self.devices = devices
        self.database = database
        self.agenda = agenda
        self.mails = mails
        self.appVersion = appVersion
        self.now = now
    }

    /// The only method of this version: it reads.
    static let read = "GET"

    /// The message of a token the Mac does not know.
    static let notPaired = "Cet iPhone n'est plus relié au Mac : relie-le de nouveau depuis Réglages › iPhone sur le Mac."

    func respond(_ request: HTTPRequest) async -> HTTPResponse {
        guard let device = devices.device(for: LinkAPI.token(fromAuthorization: request.header(LinkAPI.authorization)), now: now()) else {
            return Self.error(Self.notPaired, status: 401)
        }
        guard request.method == Self.read else { return Self.error("Cette demande n'existe pas.", status: 405) }
        do {
            switch request.path {
            case LinkAPI.Path.status:
                return try Self.json(LinkStatus(appVersion: appVersion, device: device.name))
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
            default:
                return Self.error("Cette demande n'existe pas.", status: 404)
            }
        } catch let error as LinkError {
            return Self.error(error.message, status: 404)
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
        let project: String? = if case .project(let id)? = mails?.filing(of: thread)?.filing { mails?.project(id)?.name } else { nil }
        return LinkThread(id: thread.id, account: thread.account, subject: thread.subject.isEmpty ? Words.noSubject : thread.subject,
                          people: MailText.names(thread, mine: mails?.mine ?? []), snippet: thread.snippet, date: thread.lastMessageAt,
                          unread: thread.unread, messages: thread.messageCount, hasFiles: thread.hasAttachment, project: project)
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
                                        authenticated: message.authenticated))
        }
        if row.unread { mails.markRead(row) }
        var thread = link(row)
        thread.unread = false
        return LinkThreadDetail(thread: thread, messages: messages)
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
