import Foundation
import Notifications
import Persistence
import LocalServer
import Mail
import HubLink
import Testing
@testable import MeetingsUI

/// The number on hub's icon (Paul, 20/11: « un nombre de notifications qui mélangent un peu les mails et tout »),
/// in the Dock and on the iPhone; a mail deleted by a swipe on the iPhone. Every name here is invented.
@MainActor @Suite struct PhoneBadgeTests {
    func notice(_ kind: PlannedNotice.Kind, seen: Bool) -> InboxNotice {
        InboxNotice(PlannedNotice(id: UUID().uuidString, fireDate: Date(), title: "hub", body: "…", eventID: nil, meetCode: nil,
                                  account: nil, kind: kind), at: Date(), seen: seen)
    }

    /// The unread mails of the main tab, and what hub told and Paul did not see yet: a mail's notice is already
    /// counted by its mail.
    @Test func theBadgeMixesTheUnreadMailsAndTheNoticesNotSeen() {
        let notices = [notice(.summary, seen: false), notice(.draft, seen: false), notice(.mail, seen: false), notice(.reminder, seen: true)]
        #expect(AppBadge.count(unreadMails: 3, notices: notices) == 5)
        #expect(AppBadge.count(unreadMails: 0, notices: []) == 0)
        #expect(AppBadge.label(0) == nil && AppBadge.label(7) == "7" && AppBadge.label(120) == "99+")
    }

    @Test func eachPushCarriesTheNumberAndOneCanCarryItAlone() throws {
        let notice = PlannedNotice(id: "mail|a", fireDate: Date(), title: "Camille Martin", body: "Bonjour", eventID: nil, meetCode: nil,
                                   account: nil, threadKey: "moi@exemple.fr|a", kind: .mail)
        let payload = try #require(try JSONSerialization.jsonObject(with: PhonePush.payload(notice, badge: 4, key: nil)) as? [String: Any])
        #expect((payload["aps"] as? [String: Any])?["badge"] as? Int == 4)
        let alone = try #require(try JSONSerialization.jsonObject(with: PhonePush.badgePayload(2)) as? [String: Any])
        #expect(alone as NSDictionary == ["aps": ["badge": 2]] as NSDictionary)
    }

    /// 20/11 : Apple ne lit plus rien d'un mail. Avec la clé de l'iPhone, le contenu part chiffré ; sans elle (une app
    /// d'avant), seulement « Nouveau mail ».
    @Test func applePassesOnlyWhatItCannotRead() throws {
        let notice = PlannedNotice(id: "mail|a", fireDate: Date(), title: "Camille Martin", body: "Bonjour, voici le devis", eventID: nil,
                                   meetCode: nil, account: nil, threadKey: "moi@exemple.fr|a", kind: .mail, subtitle: "Devis du site")
        let key = PushSeal.newKey()
        let data = PhonePush.payload(notice, badge: 1, key: key)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("Camille") && !text.contains("Devis") && !text.contains("Bonjour"))
        let payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let aps = try #require(payload["aps"] as? [String: Any])
        #expect(aps["mutable-content"] as? Int == 1)
        #expect((aps["alert"] as? [String: String])?["body"] == "Nouveau mail")
        let sealed = try #require(payload["hub"] as? String)
        #expect(PushSeal.open(sealed, key: key) == PushContent(title: "Camille Martin", subtitle: "Devis du site", body: "Bonjour, voici le devis"))
        let plain = PhonePush.payload(notice, badge: 1, key: nil)
        let without = String(decoding: plain, as: UTF8.self)
        #expect(!without.contains("Camille") && without.contains("Nouveau mail"))
        #expect((try JSONSerialization.jsonObject(with: plain) as? [String: Any])?["hub"] == nil)
    }

    @Test func theMacKeepsTheKeyTheIPhoneGives() throws {
        let devices = PhoneDevices(defaults: try #require(UserDefaults(suiteName: "cles-\(UUID().uuidString)")))
        let id = UUID()
        let key = PushSeal.newKey()
        devices.setCloudPushToken("0a1b", name: "iPhone", id: id, key: key, at: Date())
        #expect(devices.all.first?.pushKey == key)
        #expect(PhonePush.targets(devices.all).first?.key == key)
    }

    @Test func aSwipeOnTheIPhoneDeletesTheThreadOnTheMac() async throws {
        let database = try AppDatabase.inMemory()
        let calendar = CalendarStore(database)
        try calendar.addAccount(email: "moi@exemple.fr", at: Date())
        try calendar.setGrantedScopes(email: "moi@exemple.fr", scopes: "openid https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/gmail.modify")
        let root = FileManager.default.temporaryDirectory.appending(path: "geste-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = try #require(UserDefaults(suiteName: "geste-\(UUID().uuidString)"))
        let mails = MailLibrary(agenda: AgendaLibrary(database: database), root: root, defaults: suite, flavor: .prod,
                                send: { [silent = SilentGmail()] _ in silent.send }, vault: MemoryScheduleVault())
        for _ in 0..<150 where mails.accounts.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        try mails.store.apply(account: "moi@exemple.fr", upserts: [
            MailMessageRow(account: "moi@exemple.fr", messageID: "m1", threadID: "t1", date: Date(),
                           sender: MailAddress(name: "Camille Martin", email: "camille@studio.exemple"), to: [MailAddress(email: "moi@exemple.fr")],
                           subject: "Maquette", snippet: "Bonjour", labels: ["INBOX", "UNREAD", "CATEGORY_PERSONAL"]),
        ])
        let key = "moi@exemple.fr|t1"
        for _ in 0..<150 where !mails.inbox.contains(where: { $0.id == key }) { try await Task.sleep(for: .milliseconds(20)) }
        #expect(mails.inbox.contains { $0.id == key })
        let devices = PhoneDevices(defaults: suite)
        let (_, token) = devices.pair()
        let api = PhoneAPI(devices: devices, database: database, agenda: nil, mails: mails, appVersion: "0.57.0")
        func gesture(_ kind: String) async throws -> HTTPResponse {
            await api.respond(HTTPRequest(method: "POST", path: LinkAPI.Path.gesture, headers: ["authorization": LinkAPI.bearer(token)],
                                          body: try LinkAPI.encoder.encode(LinkGesture(thread: key, kind: kind))))
        }
        // The thread comes with the Mac's reading script, which folds signatures, and each message's first words.
        let read = await api.respond(HTTPRequest(method: "GET", path: LinkAPI.Path.thread, query: ["fil": key],
                                                 headers: ["authorization": LinkAPI.bearer(token)]))
        let detail = try LinkAPI.decoder.decode(LinkThreadDetail.self, from: read.body)
        #expect(detail.reader == MailHTML.readerScript && detail.messages.first?.snippet == "Bonjour")
        #expect(try await gesture("envoler").status == 409)
        let done = try await gesture(LinkGesture.trash)
        for _ in 0..<150 where mails.inbox.contains(where: { $0.id == key }) { try await Task.sleep(for: .milliseconds(20)) }
        #expect(done.status == 200 && !mails.inbox.contains { $0.id == key })
    }
}
