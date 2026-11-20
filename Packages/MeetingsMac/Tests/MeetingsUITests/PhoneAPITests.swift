import Domain
import Foundation
import LocalServer
import Persistence
import PolhubLink
import Testing
@testable import MeetingsUI

/// Polhub on the iPhone (20/11): the Mac answers a paired iPhone only, in JSON. Every name here is invented.
@MainActor @Suite struct PhoneAPITests {
    func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "iphone-\(UUID().uuidString)"))
    }

    @Test func aTokenWorksOnceScannedAndUntilRemoved() throws {
        let devices = PhoneDevices(defaults: try defaults())
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let (device, token) = devices.pair(now: start)
        #expect(devices.device(for: "autre", now: start) == nil && devices.device(for: nil, now: start) == nil)
        #expect(devices.device(for: token, now: start.addingTimeInterval(60))?.id == device.id)
        // Scanned in time: it stays valid long after.
        #expect(devices.device(for: token, now: start.addingTimeInterval(30 * 86_400)) != nil)
        devices.remove(device.id)
        #expect(devices.device(for: token, now: start.addingTimeInterval(30 * 86_400)) == nil)
    }

    @Test func aCodeNotScannedInTimeIsForgotten() throws {
        let devices = PhoneDevices(defaults: try defaults())
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let (_, token) = devices.pair(now: start)
        #expect(devices.device(for: token, now: start.addingTimeInterval(11 * 60)) == nil)
        // A new code forgets the old one waiting.
        _ = devices.pair(now: start.addingTimeInterval(12 * 60))
        #expect(devices.all.count == 1)
    }

    @Test func onlyTheTokensFingerprintIsKept() throws {
        let suite = try defaults()
        let (_, token) = PhoneDevices(defaults: suite).pair()
        let stored = String(decoding: try #require(suite.data(forKey: PhoneDevices.key)), as: UTF8.self)
        #expect(!stored.contains(token) && stored.contains(PhoneDevices.hash(token)))
    }

    func api() throws -> (PhoneAPI, String, AppDatabase) {
        let database = try AppDatabase.inMemory()
        let devices = PhoneDevices(defaults: try defaults())
        let (_, token) = devices.pair()
        return (PhoneAPI(devices: devices, database: database, agenda: nil, mails: nil, appVersion: "0.51.0"), token, database)
    }

    func get(_ api: PhoneAPI, _ path: String, token: String?, query: [String: String] = [:]) async -> HTTPResponse {
        var headers: [String: String] = [:]
        if let token { headers["authorization"] = LinkAPI.bearer(token) }
        return await api.respond(HTTPRequest(method: "GET", path: path, query: query, headers: headers))
    }

    @Test func nothingIsReadWithoutAPairedToken() async throws {
        let (api, _, _) = try api()
        for token in [nil, "inconnu"] {
            let refused = await get(api, LinkAPI.Path.projects, token: token)
            #expect(refused.status == 401)
            #expect(try LinkAPI.decoder.decode(LinkError.self, from: refused.body).message == PhoneAPI.notPaired)
        }
    }

    @Test func theMacSaysWhoItIs() async throws {
        let (api, token, _) = try api()
        let answer = await get(api, LinkAPI.Path.status, token: token)
        #expect(answer.status == 200)
        #expect(try LinkAPI.decoder.decode(LinkStatus.self, from: answer.body) == LinkStatus(appVersion: "0.51.0", device: "iPhone"))
        #expect(await get(api, "/v1/inconnu", token: token).status == 404)
        #expect(await api.respond(HTTPRequest(method: "DELETE", path: LinkAPI.Path.status, headers: ["authorization": LinkAPI.bearer(token)])).status == 405)
    }

    @Test func theProjectsComeInTheBoardsOrder() async throws {
        let (api, token, database) = try api()
        let store = ProjectStore(database)
        let now = Date()
        let paused = try store.addProject(name: "Atelier Nord", status: .enPause, at: now)
        let urgent = try store.addProject(name: "Site vitrine", status: .priorite2, at: now)
        try store.saveAction(ActionRow(projectID: urgent.id, text: "Envoyer le devis", position: 1, createdAt: now))
        try store.addJournal(ProjectJournalRow(projectID: urgent.id, date: now, title: "Maquette validée", body: "", createdAt: now))
        let list = try LinkAPI.decoder.decode([LinkProject].self, from: await get(api, LinkAPI.Path.projects, token: token).body)
        #expect(list.map(\.name) == ["Site vitrine", "Atelier Nord"] && list.first?.status == "priorité 2")
        let detail = try LinkAPI.decoder.decode(LinkProjectDetail.self,
                                                from: await get(api, LinkAPI.Path.project, token: token, query: ["id": urgent.id.uuidString]).body)
        #expect(detail.actions.map(\.text) == ["Envoyer le devis"] && detail.journal.map(\.title) == ["Maquette validée"])
        let gone = await get(api, LinkAPI.Path.project, token: token, query: ["id": UUID().uuidString])
        #expect(gone.status == 404 && paused.name == "Atelier Nord")
    }

    @Test func aMeetingComesWithItsSummaryAndItsDialogue() async throws {
        let (api, token, database) = try api()
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let meeting = MeetingRow(createdAt: start, status: .ended, source: .dia, candidateKey: "k", title: "Point hebdo", startedAt: start,
                                 endedAt: start.addingTimeInterval(1_800))
        let store = MeetingStore(database)
        try store.save(meeting)
        try store.setSummary(meetingID: meeting.id, summary: "## Décisions\n- Lancer la maquette")
        let list = try LinkAPI.decoder.decode([LinkMeeting].self, from: await get(api, LinkAPI.Path.meetings, token: token).body)
        #expect(list.map(\.title) == ["Point hebdo"] && list.first?.seconds == 1_800 && list.first?.hasSummary == true)
        let detail = try LinkAPI.decoder.decode(LinkMeetingDetail.self,
                                                from: await get(api, LinkAPI.Path.meeting, token: token, query: ["id": meeting.id.uuidString]).body)
        #expect(detail.summary?.contains("Lancer la maquette") == true && detail.turns.isEmpty)
    }

    @Test func withoutMailsTheFoldersAreEmpty() async throws {
        let (api, token, _) = try api()
        #expect(try LinkAPI.decoder.decode([LinkFolder].self, from: await get(api, LinkAPI.Path.folders, token: token).body).isEmpty)
    }

    @Test func aDayStartsAtTheMacsMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        let day = try #require(PhoneAPI.day("2026-11-20", calendar: calendar))
        #expect(calendar.dateComponents([.year, .month, .day, .hour], from: day) == DateComponents(year: 2026, month: 11, day: 20, hour: 0))
        #expect(PhoneAPI.day("20/11/2026") == nil && PhoneAPI.day(nil) == nil)
    }

    /// From end to end: a real request on the loopback, as `tailscale serve` passes it on.
    @Test func theServerAnswersOverHTTP() async throws {
        let (api, token, _) = try api()
        let server = HTTPServer(port: 0) { request in await api.respond(request) }
        let port = try await server.start()
        defer { server.stop() }
        var request = URLRequest(url: try #require(URL(string: "http://127.0.0.1:\(port)\(LinkAPI.Path.status)")))
        request.setValue(LinkAPI.bearer(token), forHTTPHeaderField: LinkAPI.authorization)
        let (data, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(try LinkAPI.decoder.decode(LinkStatus.self, from: data).appVersion == "0.51.0")
        let (_, refused) = try await URLSession.shared.data(from: try #require(URL(string: "http://127.0.0.1:\(port)\(LinkAPI.Path.status)")))
        #expect((refused as? HTTPURLResponse)?.statusCode == 401)
    }

    @Test func theAddressMustBeHTTPS() {
        #expect(PhoneAccess.base("https://mac.exemple.ts.net:8443") != nil)
        #expect(PhoneAccess.base("http://mac.exemple.ts.net:8443") == nil)
        #expect(PhoneAccess.base("http://127.0.0.1:8790") != nil)
        #expect(PhoneAccess.base("mac") == nil)
    }

    @Test func theMacsNameIsReadFromTailscale() {
        #expect(PhoneAccess.dnsName(#"{"Self": {"DNSName": "mac.exemple.ts.net."}}"#) == "mac.exemple.ts.net")
        #expect(PhoneAccess.dnsName("pas du json") == nil && PhoneAccess.dnsName(nil) == nil)
    }
}
