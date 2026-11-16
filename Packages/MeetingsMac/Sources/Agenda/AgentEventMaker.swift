import Domain
import Foundation
import GoogleKit
import Persistence

/// The events the agents ask for (`rendez_vous`, Paul's item 5, 16/11). `polhub mcp` has no network: it leaves a
/// request (`AgentEventFiles`) and the app makes the event with the editor's own code (`CalendarWrite.insertRequest`),
/// in the agenda asked or Paul's default one, never with a guest (Google then invites nobody), marked « préparé par
/// un agent » in its description. Each request is answered, made or refused with its reason. The development build
/// never writes to Google.
public struct AgentEventMaker: Sendable {
    /// Sends a request to Google under an account: the agenda's session in the app, a fake in the tests.
    public typealias Send = @Sendable (_ account: String, _ build: @escaping @Sendable (String) -> URLRequest) async throws -> Data

    /// Réglages › Calendrier, read at each pass: the default agenda, the length of new events; and the last agenda
    /// the editor used.
    public struct Settings: Sendable {
        public var defaultAccount: String?
        public var lastAccount: String?
        public var minutes: Int

        public init(defaultAccount: String?, lastAccount: String?, minutes: Int) {
            self.defaultAccount = defaultAccount
            self.lastAccount = lastAccount
            self.minutes = minutes
        }
    }

    /// The last line of the description of an event an agent made.
    public static let mark = "— Préparé par un agent dans Polhub."

    struct Refusal: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    let database: AppDatabase
    let files: AgentEventFiles
    let flavor: AppFlavor
    let send: Send
    let settings: @Sendable () -> Settings
    let timeZone: TimeZone
    let now: @Sendable () -> Date

    public init(database: AppDatabase, root: URL, flavor: AppFlavor = .current, send: @escaping Send, settings: @escaping @Sendable () -> Settings,
                timeZone: TimeZone = .current, now: @escaping @Sendable () -> Date = Date.init) {
        self.database = database
        files = AgentEventFiles(root: root)
        self.flavor = flavor
        self.send = send
        self.settings = settings
        self.timeZone = timeZone
        self.now = now
    }

    /// Every request waiting, the oldest first, each answered; the events made.
    public func serve() async -> [CalendarEventRow] {
        var made: [CalendarEventRow] = []
        for pending in files.take() {
            let result: AgentEventResult
            do {
                guard let request = pending.request else { throw Refusal("demande illisible") }
                let event = try await make(request)
                made.append(event)
                result = .made(event)
            } catch let error as URLError {
                result = .refused(Self.reason(error))
            } catch {
                result = .refused("\(error)")
            }
            files.answer(result, id: pending.id, now: now())
        }
        return made
    }

    func make(_ request: AgentEventRequest) async throws -> CalendarEventRow {
        guard flavor == .prod else { throw Refusal("la version de développement de Polhub n'écrit jamais dans un vrai agenda") }
        guard now().timeIntervalSince(request.createdAt) <= AgentEventFiles.maximumAge else {
            throw Refusal("demande trop ancienne : l'agent n'attendait plus la réponse")
        }
        let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw Refusal("il manque le titre") }
        let store = CalendarStore(database)
        let account = try agenda(request.account, among: try store.accounts().map(\.email))
        let end = request.end ?? request.start.addingTimeInterval(TimeInterval((request.minutes ?? settings().minutes) * 60))
        guard end > request.start else { throw Refusal("la fin tombe avant le début") }
        guard end.timeIntervalSince(request.start) <= 86_400 else { throw Refusal("un rendez-vous dure 24 heures au plus") }
        let notes = request.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = EventDraft(title: title, start: request.start, end: end, notes: notes.isEmpty ? Self.mark : notes + "\n\n" + Self.mark,
                               guests: [], addMeet: request.meet)
        let requestID = request.id.uuidString, zone = timeZone
        let data = try await send(account) { token in
            CalendarWrite.insertRequest(accessToken: token, draft: draft, timeZone: zone, requestID: requestID)
        }
        guard let event = try CalendarWrite.event(from: data, account: account) else { throw GoogleError.badAnswer }
        try store.applyGoogle(account: account, changed: [event], cancelled: [], at: now())
        // Filed as Paul's own gesture: he asked for it, and the loop never moves it.
        if let projectID = request.projectID, try ProjectStore(database).project(id: projectID) != nil {
            try store.setProject(googleEventID: event.eventID, projectID: projectID, origin: .paul)
        }
        return try store.event(id: event.id) ?? event
    }

    /// Google out of reach: nothing was made; a connection cut once the request left: the event may exist.
    static func reason(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
            "Polhub est hors ligne : Google n'a pas pu être joint"
        default:
            "la connexion à Google s'est coupée : le rendez-vous a peut-être été créé, regarde `agenda` dans un instant avant de redemander"
        }
    }

    /// The agenda asked, if it is one of Paul's; else the default one, the last used, a work agenda rather than the
    /// personal one, the first (as the editor chooses).
    func agenda(_ asked: String?, among accounts: [String]) throws -> String {
        guard !accounts.isEmpty else { throw Refusal("aucun agenda Google n'est connecté à Polhub") }
        if let asked = asked?.trimmingCharacters(in: .whitespaces).lowercased(), !asked.isEmpty {
            guard accounts.contains(asked) else { throw Refusal("« \(asked) » n'est pas un agenda connecté à Polhub (\(accounts.joined(separator: ", ")))") }
            return asked
        }
        let settings = settings()
        if let chosen = [settings.defaultAccount, settings.lastAccount].compactMap({ $0?.lowercased() }).first(where: accounts.contains) { return chosen }
        return accounts.first { AccountStyle.label(for: $0) != "Perso" } ?? accounts[0]
    }
}
