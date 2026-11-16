import Domain
import Foundation
import Persistence
import Testing
@testable import Agenda
@testable import GoogleKit

/// The events the agents ask for (Paul's item 5, 16/11): the app makes them with the editor's code, in the agenda asked
/// or the default one, never with a guest, marked « préparé par un agent »; a request it cannot serve is answered with
/// its reason. Google is a fake here, as in the other calendar tests.
@Suite struct AgentEventMakerTests {
    static let now = ISO8601DateFormatter().date(from: "2026-11-16T08:00:00Z")!
    let paris = TimeZone(identifier: "Europe/Paris")!

    /// What Polhub sent to Google, and Google's answer.
    final class FakeGoogle: @unchecked Sendable {
        private let lock = NSLock()
        private var sent: [(account: String, request: URLRequest)] = []
        let failure: (any Error)?

        init(failure: (any Error)? = nil) { self.failure = failure }

        var requests: [(account: String, request: URLRequest)] { lock.withLock { sent } }

        /// Google's event, from what was sent: its title and times, a Meet when one was asked.
        func send(_ account: String, _ build: @Sendable (String) -> URLRequest) throws -> Data {
            let request = build("jeton")
            lock.withLock { sent.append((account, request)) }
            if let failure { throw failure }
            let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]) ?? [:]
            var event: [String: Any] = ["id": "agent\(requests.count)", "status": "confirmed", "summary": body["summary"] ?? "",
                                        "start": body["start"] ?? [:], "end": body["end"] ?? [:], "organizer": ["email": account, "self": true]]
            if body["conferenceData"] != nil { event["hangoutLink"] = "https://meet.google.com/xyz-abcd-efg" }
            return try JSONSerialization.data(withJSONObject: event)
        }
    }

    struct Fixture {
        let database: AppDatabase
        let root: URL
        let atelier: ProjectRow
        var files: AgentEventFiles { AgentEventFiles(root: root) }

        init() throws {
            database = try AppDatabase.inMemory()
            root = FileManager.default.temporaryDirectory.appending(path: "rendez-vous-\(UUID().uuidString)", directoryHint: .isDirectory)
            try CalendarStore(database).addAccount(email: "moi@gmail.com", at: AgentEventMakerTests.now.addingTimeInterval(-86_400))
            try CalendarStore(database).addAccount(email: "paul@exemple.fr", at: AgentEventMakerTests.now)
            atelier = try ProjectStore(database).addProject(name: "Atelier Nord", status: .priorite1, at: AgentEventMakerTests.now)
        }
    }

    func maker(_ fixture: Fixture, _ google: FakeGoogle, flavor: AppFlavor = .prod,
               settings: AgentEventMaker.Settings = .init(defaultAccount: nil, lastAccount: nil, minutes: 45)) -> AgentEventMaker {
        AgentEventMaker(database: fixture.database, root: fixture.root, flavor: flavor, send: { account, build in try google.send(account, build) },
                        settings: { settings }, timeZone: paris, now: { Self.now })
    }

    func body(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func anEventIsMadeFromARequestWithoutAnyGuest() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let google = FakeGoogle()
        let request = AgentEventRequest(title: "Point devis", start: ISO8601DateFormatter().date(from: "2026-11-17T09:00:00Z")!,
                                        end: ISO8601DateFormatter().date(from: "2026-11-17T10:30:00Z")!, meet: true, account: "paul@exemple.fr",
                                        notes: "Relire le devis.", projectID: fixture.atelier.id, createdAt: Self.now)
        try fixture.files.request(request)
        let made = await maker(fixture, google).serve()
        #expect(made.map(\.eventID) == ["agent1"])
        let sent = try #require(google.requests.first)
        #expect(google.requests.count == 1 && sent.account == "paul@exemple.fr" && sent.request.httpMethod == "POST")
        let json = try body(sent.request)
        #expect(json["summary"] as? String == "Point devis")
        #expect(json["description"] as? String == "Relire le devis.\n\n" + AgentEventMaker.mark)
        #expect((json["start"] as? [String: String]) == ["dateTime": "2026-11-17T10:00:00+01:00", "timeZone": "Europe/Paris"])
        #expect((json["end"] as? [String: String]) == ["dateTime": "2026-11-17T11:30:00+01:00", "timeZone": "Europe/Paris"])
        // Never a guest: Google invites nobody.
        #expect(json["attendees"] == nil)
        let create = (json["conferenceData"] as? [String: Any])?["createRequest"] as? [String: Any]
        #expect(create?["requestId"] as? String == request.id.uuidString)
        // The event is in the base at once, filed in its project as Paul's own filing.
        let row = try #require(try CalendarStore(fixture.database).event(id: "paul@exemple.fr|agent1"))
        #expect(row.title == "Point devis" && row.meetCode == "xyz-abcd-efg" && row.projectID == fixture.atelier.id && row.projectOrigin == .paul)
        // The answer waits for the helper; the request is gone.
        let result = try #require(fixture.files.result(request.id))
        #expect(result == .made(row) && result.error == nil)
        #expect(fixture.files.take().isEmpty)
    }

    /// Réglages › Calendrier: the default agenda and the length of new events; else a work agenda rather than the
    /// personal one, as the editor does.
    @Test func theAgendaAndTheLengthComeFromTheSettings() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let start = ISO8601DateFormatter().date(from: "2026-11-17T09:00:00Z")!
        let google = FakeGoogle()
        try fixture.files.request(AgentEventRequest(title: "Sans réglage", start: start, createdAt: Self.now))
        _ = await maker(fixture, google).serve()
        #expect(google.requests.last?.account == "paul@exemple.fr")
        #expect((try body(try #require(google.requests.last?.request))["end"] as? [String: String])?["dateTime"] == "2026-11-17T10:45:00+01:00")
        try fixture.files.request(AgentEventRequest(title: "Agenda perso", start: start, minutes: 30, createdAt: Self.now))
        _ = await maker(fixture, google, settings: .init(defaultAccount: "moi@gmail.com", lastAccount: "paul@exemple.fr", minutes: 45)).serve()
        #expect(google.requests.last?.account == "moi@gmail.com")
        #expect((try body(try #require(google.requests.last?.request))["end"] as? [String: String])?["dateTime"] == "2026-11-17T10:30:00+01:00")
        // A default agenda that is no longer connected: the last one used.
        try fixture.files.request(AgentEventRequest(title: "Dernier utilisé", start: start, createdAt: Self.now))
        _ = await maker(fixture, google, settings: .init(defaultAccount: "parti@exemple.fr", lastAccount: "moi@gmail.com", minutes: 45)).serve()
        #expect(google.requests.last?.account == "moi@gmail.com")
    }

    @Test func aBadRequestIsDroppedWithItsReason() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let start = ISO8601DateFormatter().date(from: "2026-11-17T09:00:00Z")!
        let unknown = AgentEventRequest(title: "Ailleurs", start: start, account: "autre@exemple.fr", createdAt: Self.now)
        let backwards = AgentEventRequest(title: "À l'envers", start: start, end: start.addingTimeInterval(-60), createdAt: Self.now)
        let old = AgentEventRequest(title: "Trop tard", start: start, createdAt: Self.now.addingTimeInterval(-600))
        let untitled = AgentEventRequest(title: "  ", start: start, createdAt: Self.now)
        for request in [unknown, backwards, old, untitled] { try fixture.files.request(request) }
        let unreadable = UUID()
        try Data("pas une demande".utf8).write(to: fixture.files.requests.appending(path: "\(unreadable.uuidString.lowercased()).json"))
        let google = FakeGoogle()
        #expect(await maker(fixture, google).serve().isEmpty)
        #expect(google.requests.isEmpty)
        #expect(fixture.files.result(unknown.id)?.error?.contains("autre@exemple.fr") == true)
        #expect(fixture.files.result(backwards.id)?.error?.contains("avant") == true)
        #expect(fixture.files.result(old.id)?.error?.contains("trop ancienne") == true)
        #expect(fixture.files.result(untitled.id)?.error?.contains("titre") == true)
        #expect(fixture.files.result(unreadable)?.error?.contains("illisible") == true)
        #expect(try fixture.files.take().isEmpty && CalendarStore(fixture.database).allEvents().isEmpty)
        // Google refuses: its reason, in French.
        let refusing = FakeGoogle(failure: GoogleError.needsWrite)
        let asked = AgentEventRequest(title: "Lecture seule", start: start, account: "paul@exemple.fr", createdAt: Self.now)
        try fixture.files.request(asked)
        #expect(await maker(fixture, refusing).serve().isEmpty)
        #expect(refusing.requests.count == 1 && fixture.files.result(asked.id)?.error == GoogleError.needsWrite.description)
        // Offline: said plainly, not as the system's error; a cut connection says the event may exist.
        let offline = AgentEventRequest(title: "Hors ligne", start: start, createdAt: Self.now)
        try fixture.files.request(offline)
        _ = await maker(fixture, FakeGoogle(failure: URLError(.notConnectedToInternet))).serve()
        #expect(fixture.files.result(offline.id)?.error?.contains("hors ligne") == true)
        let cut = AgentEventRequest(title: "Coupé", start: start, createdAt: Self.now)
        try fixture.files.request(cut)
        _ = await maker(fixture, FakeGoogle(failure: URLError(.timedOut))).serve()
        #expect(fixture.files.result(cut.id)?.error?.contains("`agenda`") == true)
    }

    /// The development build never writes to Google.
    @Test func theDevelopmentBuildNeverWrites() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let request = AgentEventRequest(title: "Essai", start: ISO8601DateFormatter().date(from: "2026-11-17T09:00:00Z")!, createdAt: Self.now)
        try fixture.files.request(request)
        let google = FakeGoogle()
        #expect(await maker(fixture, google, flavor: .dev).serve().isEmpty)
        #expect(google.requests.isEmpty && fixture.files.result(request.id)?.error?.contains("développement") == true)
    }
}
