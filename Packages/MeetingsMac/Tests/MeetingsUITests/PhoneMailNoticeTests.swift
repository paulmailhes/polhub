import Foundation
import Notifications
import Persistence
import HubCloud
import HubLink
import Testing
@testable import MeetingsUI

/// The mails on the iPhone (Paul, 20/11: « une notification pour tous les mails, un truc propre, comme si c'était Gmail
/// qui me l'affichait »): each new mail, its sender, its subject and its first words, grouped by thread. Invented names.
@MainActor @Suite struct PhoneMailNoticeTests {
    typealias Arrival = (threadKey: String, sender: String, subject: String, snippet: String)

    @Test func eachMailIsToldAsGmailWould() throws {
        let mails: [Arrival] = [("moi@exemple.fr|a", "Camille Martin", "Maquette v2", "Voici la nouvelle version du site."),
                                ("moi@exemple.fr|b", "Apple", "Ton reçu", "Merci pour ton achat.")]
        let notices = NotificationPlan.phoneMailNotices(mails, now: Date())
        #expect(notices.count == 2)
        #expect(notices[0].title == "Camille Martin" && notices[0].subtitle == "Maquette v2" && notices[0].body == "Voici la nouvelle version du site.")
        #expect(notices[1].threadKey == "moi@exemple.fr|b" && notices[1].kind == .mail)
        let payload = try #require(try JSONSerialization.jsonObject(with: PhonePush.payload(notices[0])) as? [String: Any])
        let alert = try #require((payload["aps"] as? [String: Any])?["alert"] as? [String: String])
        #expect(alert == ["title": "Camille Martin", "subtitle": "Maquette v2", "body": "Voici la nouvelle version du site."])
        #expect((payload["aps"] as? [String: Any])?["thread-id"] as? String == "moi@exemple.fr|a")
    }

    /// Back from a long time offline: the ten most recent, then one line for the rest, not a flood.
    @Test func aFloodIsCutAfterTen() {
        let mails: [Arrival] = (1...14).map { ("moi@exemple.fr|\($0)", "Personne \($0)", "Objet \($0)", "Texte \($0)") }
        let notices = NotificationPlan.phoneMailNotices(mails, now: Date())
        #expect(notices.count == 11)
        #expect(notices.last?.title == "4 autres nouveaux mails")
    }

    /// 20/11: the iPhone gives where to send its notifications through iCloud too, without Tailscale.
    @Test func theIPhonesNotificationsAddressComesThroughICloud() async throws {
        let defaults = try #require(UserDefaults(suiteName: "icloud-\(UUID().uuidString)"))
        let devices = PhoneDevices(defaults: defaults)
        let api = PhoneAPI(devices: devices, database: try AppDatabase.inMemory(), agenda: nil, mails: nil, appVersion: "0.56.0")
        let drive = PhoneCloudTests.MemoryDrive()
        let token = String(repeating: "cd", count: 32)
        let id = UUID()
        drive.ask(CloudRequest(key: "notifications-\(id.uuidString)", kind: CloudRequest.notifications,
                               data: try LinkAPI.encoder.encode(LinkPushToken(token: token, name: "iPhone de test")), date: Date()))
        let cloud = PhoneCloud(api: api, drive: drive, defaults: defaults)
        await cloud.copy()
        #expect(devices.all.contains { $0.pushToken == token && $0.name == "iPhone de test" })
        // Paired too, with the same address: one notification, not two.
        let (paired, _) = devices.pair()
        devices.setPushToken(token, for: paired.id)
        #expect(PhonePush.targets(devices.all).count == 1)
    }
}
