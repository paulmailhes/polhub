import Foundation

/// An event an agent asks for (`rendez_vous` of `polhub mcp`, 16/11). The helper has no network: it leaves the
/// request in `Agenda/demandes`, posts `AgentEventFiles.signal`, and waits for the app's answer in `Agenda/reponses`.
/// The app makes the event with the editor's code, never with a guest, marked « préparé par un agent ».
public struct AgentEventRequest: Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var start: Date
    /// The end asked; else `minutes` after the start; else the length of new events in Réglages › Calendrier.
    public var end: Date?
    public var minutes: Int?
    public var meet: Bool
    /// The agenda, by its account's address; `nil`: the default agenda of Réglages › Calendrier.
    public var account: String?
    public var notes: String
    public var projectID: UUID?
    public var createdAt: Date

    public init(id: UUID = UUID(), title: String, start: Date, end: Date? = nil, minutes: Int? = nil, meet: Bool = false, account: String? = nil,
                notes: String = "", projectID: UUID? = nil, createdAt: Date) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.minutes = minutes
        self.meet = meet
        self.account = account
        self.notes = notes
        self.projectID = projectID
        self.createdAt = createdAt
    }
}

/// The app's answer: the event made, or why it was not.
public struct AgentEventResult: Codable, Equatable, Sendable {
    public var eventID: String?
    public var account: String?
    public var title: String?
    public var start: Date?
    public var end: Date?
    public var meetCode: String?
    /// Why nothing was made, in French, for the agent.
    public var error: String?

    public init(eventID: String? = nil, account: String? = nil, title: String? = nil, start: Date? = nil, end: Date? = nil, meetCode: String? = nil,
                error: String? = nil) {
        self.eventID = eventID
        self.account = account
        self.title = title
        self.start = start
        self.end = end
        self.meetCode = meetCode
        self.error = error
    }

    public static func made(_ event: CalendarEventRow) -> AgentEventResult {
        AgentEventResult(eventID: event.eventID, account: event.account, title: event.title, start: event.startAt, end: event.endAt, meetCode: event.meetCode)
    }

    public static func refused(_ reason: String) -> AgentEventResult {
        AgentEventResult(error: reason)
    }
}

/// Where the agents' events wait for the app, and where its answers wait for the helper: beside the base.
public struct AgentEventFiles: Sendable {
    /// The signal the helper posts after a request: the app serves it at once.
    public static let signal = "fr.paulmailhes.polhub.rendez-vous-demande"
    /// Older than this, a request is answered « too old » and never made: its agent stopped waiting long ago, and
    /// was told nothing was made.
    public static let maximumAge: TimeInterval = 120
    /// An answer nobody came for is let go after this.
    static let answerAge: TimeInterval = 600

    public let requests: URL
    public let answers: URL

    public init(root: URL) {
        let folder = root.appending(path: "Agenda", directoryHint: .isDirectory)
        requests = folder.appending(path: "demandes", directoryHint: .isDirectory)
        answers = folder.appending(path: "reponses", directoryHint: .isDirectory)
    }

    // MARK: - The helper's side

    /// Leaves a request for the app.
    public func request(_ request: AgentEventRequest) throws {
        try FileManager.default.createDirectory(at: requests, withIntermediateDirectories: true)
        try JSONEncoder().encode(request).write(to: file(requests, request.id), options: .atomic)
    }

    /// The app's answer to this request, once it is there (then removed).
    public func result(_ id: UUID) -> AgentEventResult? {
        let url = file(answers, id)
        guard let data = try? Data(contentsOf: url), let result = try? JSONDecoder().decode(AgentEventResult.self, from: data) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return result
    }

    /// Takes a request back that the app has not taken yet: `true` when it was still waiting, so nothing will be made.
    public func withdraw(_ id: UUID) -> Bool {
        (try? FileManager.default.removeItem(at: file(requests, id))) != nil
    }

    // MARK: - The app's side

    /// A request taken by the app: `nil` when its file could not be read.
    public struct Pending: Sendable {
        public let id: UUID
        public let request: AgentEventRequest?
    }

    /// The requests waiting, the oldest first, each taken (its file removed) as it is listed: a request the helper
    /// took back meanwhile is not served, and none is served twice. A file that is not a request goes.
    public func take() -> [Pending] {
        let files = (try? FileManager.default.contentsOfDirectory(at: requests, includingPropertiesForKeys: [.creationDateKey])) ?? []
        func created(_ url: URL) -> Date { (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast }
        return files.sorted { created($0) < created($1) }.compactMap { url in
            let data = try? Data(contentsOf: url)
            guard (try? FileManager.default.removeItem(at: url)) != nil else { return nil }
            guard url.pathExtension == "json", let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { return nil }
            return Pending(id: id, request: data.flatMap { try? JSONDecoder().decode(AgentEventRequest.self, from: $0) })
        }
    }

    /// The app answers a request; the answers nobody came for go.
    public func answer(_ result: AgentEventResult, id: UUID, now: Date = Date()) {
        try? FileManager.default.createDirectory(at: answers, withIntermediateDirectories: true)
        for old in (try? FileManager.default.contentsOfDirectory(at: answers, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        where ((try? old.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < now.addingTimeInterval(-Self.answerAge) {
            try? FileManager.default.removeItem(at: old)
        }
        try? JSONEncoder().encode(result).write(to: file(answers, id), options: .atomic)
    }

    func file(_ folder: URL, _ id: UUID) -> URL {
        folder.appending(path: "\(id.uuidString.lowercased()).json")
    }
}
