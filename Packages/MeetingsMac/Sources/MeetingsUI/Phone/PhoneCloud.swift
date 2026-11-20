import AppKit
import CryptoKit
import Foundation
import HubCloud
import HubDesign
import HubLink

/// The copy in iCloud (20/11, lot 1 of « Polhub sans le Mac »): the Mac copies into the user's iCloud what the iPhone
/// shows (the projects, the meetings, the agenda, Colin's thread), the mails apart, which stay at Google. The iPhone
/// reads it when the Mac does not answer. Only what changed is written, every two minutes and before the Mac sleeps.
@MainActor public final class PhoneCloud: ObservableObject {
    static let enabledKey = "icloud.copie"
    /// The fingerprint of each answer copied, by its key: what is unchanged is not written again.
    static let hashesKey = "icloud.copies"
    /// The fingerprint of each meeting in the list when its detail was copied: a long transcript is not read again.
    static let meetingsKey = "icloud.reunions"
    static let lastKey = "icloud.derniereCopie"
    /// Where the Mac stopped reading the iPhone's requests.
    static let requestsKey = "icloud.demandes"
    static let interval: Duration = .seconds(120)
    /// The meetings copied with their detail: those the iPhone lists.
    static let meetingCount = 50

    enum Texts {
        static let signedOut = "Ce Mac n'est connecté à aucun compte iCloud : rien n'est copié."
        static let failed = "iCloud ne répond pas : la copie reprendra seule."
        static func refused(_ count: Int, _ reason: String) -> String {
            "iCloud refuse \(count == 1 ? "une copie" : "\(count) copies") : \(reason)"
        }
    }

    let api: PhoneAPI
    let drive: (any CloudDrive)?
    let defaults: UserDefaults
    let now: () -> Date
    @Published public private(set) var lastCopy: Date?
    @Published public private(set) var problem: String?
    private var loop: Task<Void, Never>?
    private var sleeping: NSObjectProtocol?
    private var copying = false

    init(api: PhoneAPI, drive: (any CloudDrive)?, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.api = api
        self.drive = drive
        self.defaults = defaults
        self.now = now
        lastCopy = defaults.object(forKey: Self.lastKey) as? Date
    }

    /// Réglages › iPhone, « Copie dans iCloud »: on unless Paul switched it off.
    public var enabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Self.enabledKey)
            if newValue { start() } else { stop() }
        }
    }

    /// At launch: a first copy shortly after, then every two minutes, and before the Mac sleeps.
    public func start() {
        guard enabled, drive != nil, loop == nil else { return }
        loop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            while !Task.isCancelled {
                guard let self else { return }
                await self.copy()
                try? await Task.sleep(for: Self.interval)
            }
        }
        sleeping = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.copy() }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        if let sleeping { NSWorkspace.shared.notificationCenter.removeObserver(sleeping) }
        sleeping = nil
    }

    /// What changed since the last copy is written; what the Mac no longer has is taken away.
    public func copy() async {
        guard enabled, let drive, !copying else { return }
        copying = true
        defer { copying = false }
        guard await drive.available() else {
            problem = Texts.signedOut
            return
        }
        await readRequests(drive)
        let plan = plan()
        var hashes = defaults.dictionary(forKey: Self.hashesKey) as? [String: String] ?? [:]
        let changed = plan.answers.filter { hashes[$0.key] != Self.hash($0.value) }
        let gone = hashes.keys.filter { plan.answers[$0] == nil && !plan.kept.contains($0) }
        let date = now()
        do {
            let refused = changed.isEmpty ? [:] : try await drive.save(changed.map { CloudCopy(key: $0.key, data: $0.value, date: date) })
            for (key, data) in changed where refused[key] == nil { hashes[key] = Self.hash(data) }
            try await drive.delete(gone)
            for key in gone { hashes[key] = nil }
            defaults.set(hashes, forKey: Self.hashesKey)
            // A meeting's detail refused is read again next time.
            var meetings = defaults.dictionary(forKey: Self.meetingsKey) as? [String: String] ?? [:]
            for (id, fingerprint) in plan.meetings where hashes[Self.meetingKey(id)] != nil { meetings[id] = fingerprint }
            defaults.set(meetings.filter { plan.meetings[$0.key] != nil }, forKey: Self.meetingsKey)
            if let reason = refused.values.first {
                problem = Texts.refused(refused.count, reason)
            } else {
                problem = nil
                lastCopy = date
                defaults.set(date, forKey: Self.lastKey)
            }
        } catch {
            problem = Texts.failed
        }
    }

    /// What the iPhone asked through iCloud: where to send its notifications, even when Tailscale never joined them.
    func readRequests(_ drive: any CloudDrive) async {
        var token = defaults.data(forKey: Self.requestsKey)
        while true {
            guard let page = try? await drive.requests(since: token) else { return }
            for request in page.requests where request.kind == CloudRequest.notifications {
                let prefix = CloudRequest.notifications + "-"
                guard request.key.hasPrefix(prefix), let id = UUID(uuidString: String(request.key.dropFirst(prefix.count))),
                      let push = try? LinkAPI.decoder.decode(LinkPushToken.self, from: request.data), !push.token.isEmpty else { continue }
                api.devices.setCloudPushToken(push.token, name: push.name ?? "iPhone", id: id, at: request.date)
            }
            token = page.token
            defaults.set(token, forKey: Self.requestsKey)
            if !page.more { return }
        }
    }

    struct Plan {
        var answers: [String: Data] = [:]
        /// Copied before and unchanged, not read again: kept in iCloud.
        var kept: Set<String> = []
        /// Each meeting's fingerprint in the list.
        var meetings: [String: String] = [:]
    }

    /// The answers the iPhone reads, as the Mac would give them: the mails apart.
    func plan() -> Plan {
        var plan = Plan()
        func put(_ key: String, _ value: (some Encodable)?) {
            if let value, let data = try? LinkAPI.encoder.encode(value) { plan.answers[key] = data }
        }
        put(LinkAPI.Path.status, LinkStatus(appVersion: api.appVersion, device: "iCloud", badge: api.badge?()))
        let projects = try? api.projects()
        put(LinkAPI.Path.projects, projects)
        for project in projects ?? [] {
            put(LinkAPI.key(LinkAPI.Path.project, query: ["id": project.id.uuidString]), try? api.project(project.id.uuidString))
        }
        let meetings = try? api.meetings(limit: Self.meetingCount)
        put(LinkAPI.Path.meetings, meetings)
        let copied = defaults.dictionary(forKey: Self.meetingsKey) as? [String: String] ?? [:]
        let hashes = defaults.dictionary(forKey: Self.hashesKey) as? [String: String] ?? [:]
        for meeting in meetings ?? [] {
            let id = meeting.id.uuidString
            guard let entry = try? LinkAPI.encoder.encode(meeting) else { continue }
            let fingerprint = Self.hash(entry)
            plan.meetings[id] = fingerprint
            if copied[id] == fingerprint, hashes[Self.meetingKey(id)] != nil {
                plan.kept.insert(Self.meetingKey(id))
            } else {
                put(Self.meetingKey(id), try? api.meeting(id))
            }
        }
        // A wide agenda: the iPhone cuts its two days in it.
        let calendar = Words.calendar
        let today = calendar.startOfDay(for: now())
        put(LinkAPI.Path.events, try? api.events(from: calendar.date(byAdding: .day, value: -7, to: today),
                                                  to: calendar.date(byAdding: .day, value: 45, to: today)))
        put(LinkAPI.Path.colin, try? api.colinThread())
        return plan
    }

    static func meetingKey(_ id: String) -> String { LinkAPI.key(LinkAPI.Path.meeting, query: ["id": id]) }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
