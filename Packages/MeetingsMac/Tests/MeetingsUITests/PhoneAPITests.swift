import Domain
import Foundation
import CryptoKit
import LocalServer
import Notifications
import Mail
import Persistence
import HubLink
import Testing
@testable import MeetingsUI

/// hub on the iPhone (20/11): the Mac answers a paired iPhone only, in JSON. Every name here is invented.
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

    /// 20/11 : le statut dit les add-ons installés du Mac ; l'iPhone n'en montre que les onglets.
    @Test func theStatusSaysTheAddOns() async throws {
        let database = try AppDatabase.inMemory()
        let devices = PhoneDevices(defaults: try defaults())
        let (_, token) = devices.pair()
        let api = PhoneAPI(devices: devices, database: database, agenda: nil, mails: nil, appVersion: "0.59.0", addOns: { [.meetings] })
        let answer = await get(api, LinkAPI.Path.status, token: token)
        let status = try LinkAPI.decoder.decode(LinkStatus.self, from: answer.body)
        #expect(status.addOns == ["reunions"])
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
        #expect(try LinkAPI.decoder.decode(LinkStatus.self, from: answer.body) == LinkStatus(appVersion: "0.51.0", device: "iPhone", addOns: AddOn.allCases.map(\.rawValue)))
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

    /// Lot 3 (20/11): a mail written on the iPhone leaves from the Mac, with its delay and « Annuler ».
    @Test func aNewMailLeavesWithItsDelayAndComesBack() async throws {
        let database = try AppDatabase.inMemory()
        let calendar = CalendarStore(database)
        try calendar.addAccount(email: "moi@exemple.fr", at: Date())
        try calendar.setGrantedScopes(email: "moi@exemple.fr", scopes: "openid https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/gmail.modify")
        let root = FileManager.default.temporaryDirectory.appending(path: "iphone-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = try defaults()
        let mails = MailLibrary(agenda: AgendaLibrary(database: database), root: root, defaults: suite, flavor: .prod,
                                send: { [silent = SilentGmail()] _ in silent.send }, vault: MemoryScheduleVault())
        for _ in 0..<150 where mails.accounts.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        let devices = PhoneDevices(defaults: suite)
        let (_, token) = devices.pair()
        let api = PhoneAPI(devices: devices, database: database, agenda: nil, mails: mails, appVersion: "0.52.0")
        func post(_ path: String, _ body: some Encodable) async throws -> HTTPResponse {
            await api.respond(HTTPRequest(method: "POST", path: path, headers: ["authorization": LinkAPI.bearer(token)],
                                          body: try LinkAPI.encoder.encode(body)))
        }
        let nobody = try await post(LinkAPI.Path.newMail, LinkNewMail(account: nil, to: [], cc: [], subject: "Devis", text: "Bonjour"))
        let refusal = try LinkAPI.decoder.decode(LinkError.self, from: nobody.body)
        #expect(nobody.status == 409 && refusal.message == "Ajoute un destinataire.")
        let sent = try await post(LinkAPI.Path.newMail, LinkNewMail(account: nil, to: ["jules@exemple.fr"], cc: [], subject: "Devis", text: "Bonjour"))
        let sending = try LinkAPI.decoder.decode(LinkSending.self, from: sent.body)
        #expect(sent.status == 200 && sending.subject == "Devis" && mails.sending?.draftID == sending.draftID)
        let back = try await post(LinkAPI.Path.cancel, LinkCancel(draftID: sending.draftID))
        #expect(back.status == 200 && mails.sending == nil)
        // Without Colin on this Mac, a question says so.
        let question = try await post(LinkAPI.Path.colin, LinkQuestion(text: "Où on en est ?"))
        #expect(question.status == 409)
    }

    /// 20/11: the iPhone gives its push token; a notice goes to Apple with what to open on a touch.
    @Test func theIPhonesPushTokenIsKeptAndANoticeSaysItsThread() async throws {
        let (api, token, _) = try api()
        let hex = String(repeating: "ab", count: 32)
        let answer = await api.respond(HTTPRequest(method: "POST", path: LinkAPI.Path.push, headers: ["authorization": LinkAPI.bearer(token)],
                                                   body: try LinkAPI.encoder.encode(LinkPushToken(token: hex))))
        #expect(answer.status == 200 && api.devices.all.first?.pushToken == hex)
        let notice = PlannedNotice(id: "mail|moi@exemple.fr|a|1", fireDate: Date(), title: "Camille Martin", body: "Maquette v2 du site",
                                   eventID: nil, meetCode: nil, account: nil, threadKey: "moi@exemple.fr|a", kind: .mail)
        let payload = try #require(try JSONSerialization.jsonObject(with: PhonePush.payload(notice)) as? [String: Any])
        #expect(payload["fil"] as? String == "moi@exemple.fr|a")
        #expect(((payload["aps"] as? [String: Any])?["alert"] as? [String: String])?["title"] == "Camille Martin")
    }

    @Test func theProviderTokenIsSignedByTheKey() throws {
        let key = P256.Signing.PrivateKey()
        let jwt = PhonePush.jwt(keyID: "ABC123", team: "TEAM", key: key, now: Date(timeIntervalSince1970: 1_790_000_000))
        let parts = jwt.split(separator: ".").map(String.init)
        #expect(parts.count == 3)
        func data(_ text: String) -> Data? {
            var base = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while base.count % 4 != 0 { base += "=" }
            return Data(base64Encoded: base)
        }
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: try #require(data(parts[2])))
        #expect(key.publicKey.isValidSignature(signature, for: Data("\(parts[0]).\(parts[1])".utf8)))
        #expect(String(decoding: try #require(data(parts[1])), as: UTF8.self) == #"{"iss":"TEAM","iat":1790000000}"#)
    }

    @Test func theAddressMustBeHTTPS() {
        #expect(PhoneAccess.base("https://mac.exemple.ts.net:8443") != nil)
        #expect(PhoneAccess.base("http://mac.exemple.ts.net:8443") == nil)
        #expect(PhoneAccess.base("http://127.0.0.1:8790") != nil)
        #expect(PhoneAccess.base("mac") == nil)
    }

    /// 20/11: the address `tailscale serve` publishes, read from its own answer.
    @Test func thePublishedAddressIsReadFromTailscaleServe() {
        let serve = #"{"TCP": {"8443": {"HTTPS": true}}, "Web": {"mac.exemple.ts.net:8443": {"Handlers": {"/": {"Proxy": "http://127.0.0.1:8790"}}}}}"#
        #expect(PhoneAccess.publishedAddress(serve) == "https://mac.exemple.ts.net:8443")
        #expect(PhoneAccess.publishedAddress(serve, port: 8791) == nil)
        #expect(PhoneAccess.publishedAddress(#"{"TCP": {}}"#) == nil && PhoneAccess.publishedAddress(nil) == nil)
    }

    @Test func theMacsNameIsReadFromTailscale() {
        #expect(PhoneAccess.dnsName(#"{"Self": {"DNSName": "mac.exemple.ts.net."}}"#) == "mac.exemple.ts.net")
        #expect(PhoneAccess.dnsName("pas du json") == nil && PhoneAccess.dnsName(nil) == nil)
    }
}
