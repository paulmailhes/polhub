import CryptoKit
import Foundation
import Notifications

/// Polhub's notifications on the iPhone (20/11): what the Mac notifies — new mails, new events, a summary ready, a
/// mail that did not leave — and the reminders before an event, sent by Apple's push service to every paired iPhone,
/// while the Mac is awake. The key is the team's (Réglages › iPhone says whether it is found); it never leaves the Mac.
@MainActor
final class PhonePush {
    /// The team of Polhub's apps; the topic of the iPhone app.
    static let team = "CQ43U6XX4Z"
    static let topic = "fr.paulmailhes.polhub.ios"
    /// Where the key's file is, and its identifier: set once, in the preferences.
    static let keyPathKey = "iphone.apns.cle"
    static let keyIDKey = "iphone.apns.id"

    let devices: PhoneDevices
    let defaults: UserDefaults
    let session: URLSession
    private var token: (value: String, at: Date)?
    /// The reminders waiting for their time.
    private var reminders: [String: Task<Void, Never>] = [:]

    init(devices: PhoneDevices, defaults: UserDefaults, session: URLSession = .shared) {
        self.devices = devices
        self.defaults = defaults
        self.session = session
    }

    /// The push key, when its file is readable.
    var key: (id: String, signing: P256.Signing.PrivateKey)? {
        guard let path = defaults.string(forKey: Self.keyPathKey), let id = defaults.string(forKey: Self.keyIDKey),
              let pem = try? String(contentsOfFile: path, encoding: .utf8), let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) else {
            return nil
        }
        return (id, key)
    }

    /// The provider token Apple asks for, made again every 40 minutes (Apple refuses it after an hour).
    func providerToken(now: Date = Date()) -> String? {
        if let token, now.timeIntervalSince(token.at) < 40 * 60 { return token.value }
        guard let key else { return nil }
        let made = Self.jwt(keyID: key.id, team: Self.team, key: key.signing, now: now)
        token = (made, now)
        return made
    }

    static func jwt(keyID: String, team: String, key: P256.Signing.PrivateKey, now: Date) -> String {
        func b64u(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let head = b64u(Data(#"{"alg":"ES256","kid":"\#(keyID)"}"#.utf8))
        let claims = b64u(Data(#"{"iss":"\#(team)","iat":\#(Int(now.timeIntervalSince1970))}"#.utf8))
        let signature = (try? key.signature(for: Data("\(head).\(claims)".utf8)))?.rawRepresentation ?? Data()
        return "\(head).\(claims).\(b64u(signature))"
    }

    /// What Apple receives: the title and the body, and what to open on a touch (the thread, the event).
    static func payload(_ notice: PlannedNotice) -> Data {
        var aps: [String: Any] = ["alert": ["title": notice.title, "body": notice.body], "sound": "default"]
        if let thread = notice.threadKey { aps["thread-id"] = thread }
        var payload: [String: Any] = ["aps": aps]
        if let thread = notice.threadKey { payload["fil"] = thread }
        if let event = notice.eventID { payload["rendez-vous"] = event }
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    /// Sent now to every paired iPhone; a token Apple no longer knows is forgotten.
    func send(_ notice: PlannedNotice) async {
        let targets = devices.all.compactMap { device in device.pushToken.map { (device.id, $0) } }
        guard !targets.isEmpty, let token = providerToken() else { return }
        let body = Self.payload(notice)
        for (id, device) in targets {
            guard let url = URL(string: "https://api.push.apple.com/3/device/\(device)") else { continue }
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue(Self.topic, forHTTPHeaderField: "apns-topic")
            request.setValue("alert", forHTTPHeaderField: "apns-push-type")
            request.setValue(String(notice.id.prefix(64)).addingPercentEncoding(withAllowedCharacters: .alphanumerics), forHTTPHeaderField: "apns-collapse-id")
            guard let (_, response) = try? await session.data(for: request) else { continue }
            if [400, 410].contains((response as? HTTPURLResponse)?.statusCode) { devices.setPushToken(nil, for: id) }
        }
    }

    /// The reminders before the events, each sent at its time while the Mac is awake; one too late (the Mac slept) is
    /// dropped.
    func plan(_ notices: [PlannedNotice], now: Date = Date()) {
        let wanted = Dictionary(notices.filter { $0.fireDate > now && $0.fireDate < now.addingTimeInterval(36 * 3_600) }.map { ($0.id, $0) },
                                uniquingKeysWith: { first, _ in first })
        for (id, task) in reminders where wanted[id] == nil {
            task.cancel()
            reminders[id] = nil
        }
        for (id, notice) in wanted where reminders[id] == nil {
            reminders[id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, notice.fireDate.timeIntervalSinceNow)))
                guard !Task.isCancelled, let self, Date().timeIntervalSince(notice.fireDate) < 120 else { return }
                await self.send(notice)
                self.reminders[id] = nil
            }
        }
    }
}
