import Foundation
import LocalServer
import Notifications
import Persistence
import PolhubDesign
import PolhubLink

/// Réglages › iPhone (20/11): the switch that opens Polhub to Paul's iPhone, the address the iPhone reaches, the QR
/// code that pairs one, and the iPhones paired. The server listens on the Mac's loopback only; `tailscale serve`
/// publishes it on Paul's tailnet.
@MainActor
public final class PhoneAccess: ObservableObject {
    static let enabledKey = "iphone.acces"
    /// The notifications on the iPhone (20/11), on unless switched off.
    static let notificationsKey = "iphone.notifications"
    static let addressKey = "iphone.adresse"
    /// The command that publishes the server on the tailnet, once, by Paul: the Tailscale app's own command line, which
    /// the Terminal does not know by its short name (measured on 20/11).
    public static let serveCommand = "/Applications/Tailscale.app/Contents/MacOS/Tailscale serve --bg --https=\(LinkAPI.publishedPort) http://127.0.0.1:\(LinkAPI.port)"
    /// Where the Tailscale app keeps its command line.
    nonisolated static let tailscale = URL(fileURLWithPath: "/Applications/Tailscale.app/Contents/MacOS/Tailscale")

    @Published public private(set) var running = false
    @Published public private(set) var problem: String?
    @Published public private(set) var devices: [PhoneDevice] = []
    /// The QR code's link while it waits to be scanned.
    @Published public private(set) var pairing: (link: URL, until: Date)?
    /// Whether `tailscale serve` publishes the server; nil until read.
    @Published public private(set) var published: Bool?
    @Published public var address: String {
        didSet { defaults.set(address, forKey: Self.addressKey) }
    }

    public var enabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Self.enabledKey)
            if newValue {
                Task {
                    await start()
                    await readTailscale()
                }
            } else {
                stop()
            }
        }
    }

    let store: PhoneDevices
    let api: PhoneAPI
    let push: PhonePush

    public var notifies: Bool {
        get { defaults.object(forKey: Self.notificationsKey) as? Bool ?? true }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Self.notificationsKey)
        }
    }

    /// Whether the push key is found: without it, nothing reaches the iPhone.
    public var hasPushKey: Bool { push.key != nil }

    /// What the Mac notifies, on the iPhone too.
    public func notify(_ notice: PlannedNotice) async {
        guard enabled, notifies else { return }
        await push.send(notice)
    }

    /// The reminders before the events, at their time.
    public func plan(_ reminders: [PlannedNotice]) {
        push.plan(enabled && notifies ? reminders : [])
    }
    private let defaults: UserDefaults
    private var server: HTTPServer?
    private let port: UInt16

    public init(database: AppDatabase, agenda: AgendaLibrary?, mails: MailLibrary?, colin: ColinThread? = nil, appVersion: String,
                defaults: UserDefaults = .standard, port: UInt16 = LinkAPI.port) {
        self.defaults = defaults
        self.port = port
        store = PhoneDevices(defaults: defaults)
        api = PhoneAPI(devices: store, database: database, agenda: agenda, mails: mails, colin: colin, appVersion: appVersion)
        push = PhonePush(devices: store, defaults: defaults)
        address = defaults.string(forKey: Self.addressKey) ?? ""
        devices = store.all
    }

    /// At launch: listens if Paul switched it on.
    public func resume() async {
        if enabled { await start() }
    }

    func start() async {
        guard server == nil else { return }
        let api = self.api
        let server = HTTPServer(port: port) { request in await api.respond(request) }
        do {
            _ = try await server.start()
            self.server = server
            running = true
            problem = nil
        } catch {
            server.stop()
            running = false
            problem = "Polhub n'a pas pu ouvrir l'accès : le port \(port) est déjà pris par une autre app. Quitte-la, puis rallume l'accès."
        }
    }

    func stop() {
        server?.stop()
        server = nil
        running = false
        pairing = nil
    }

    /// A QR code for a new iPhone, valid ten minutes. Without an address, Tailscale is asked first.
    public func pair() async {
        if Self.base(address) == nil { await readTailscale() }
        guard let base = Self.base(address) else {
            problem = "Polhub n'a pas trouvé l'adresse du Mac sur Tailscale : colle-la dans « Adresse » (https://…:8443)."
            return
        }
        problem = nil
        let (_, token) = store.pair()
        pairing = (LinkAPI.pairingURL(address: base, token: token), Date().addingTimeInterval(PhoneDevices.pairingLifetime))
        devices = store.all
    }

    public func endPairing() {
        pairing = nil
        devices = store.all
    }

    public func remove(_ device: PhoneDevice) {
        store.remove(device.id)
        devices = store.all
    }

    /// The devices again, once the iPhone made its first request.
    public func refresh() {
        devices = store.all
        if let pairing, pairing.until < Date() { self.pairing = nil }
    }

    /// The address typed, as a URL the iPhone can use: HTTPS, or HTTP on the loopback (the simulator).
    static func base(_ address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.host != nil else { return nil }
        let loopback = url.host == "127.0.0.1" || url.host == "localhost"
        return url.scheme == "https" || (url.scheme == "http" && loopback) ? url : nil
    }

    // MARK: - Tailscale

    /// Reads the address `tailscale serve` publishes (else the Mac's name on the tailnet), and whether it publishes the
    /// server.
    public func readTailscale() async {
        let serve = await Self.run(["serve", "status", "--json"])
        published = serve.map { $0.contains("127.0.0.1:\(port)") }
        guard Self.base(address) == nil else { return }
        if let published = Self.publishedAddress(serve) {
            address = published
        } else if let name = Self.dnsName(await Self.run(["status", "--json"])) {
            address = "https://\(name):\(LinkAPI.publishedPort)"
        }
    }

    /// « https://mac.exemple.ts.net:8443 »: the address `tailscale serve` publishes the server at.
    static func publishedAddress(_ json: String?, port: UInt16 = LinkAPI.port) -> String? {
        guard let data = json?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let web = object["Web"] as? [String: Any] else { return nil }
        let host = web.first { _, value in
            guard let handlers = (value as? [String: Any])?["Handlers"] as? [String: Any] else { return false }
            return handlers.values.contains { (($0 as? [String: Any])?["Proxy"] as? String)?.contains("127.0.0.1:\(port)") == true }
        }?.key
        return host.map { "https://\($0)" }
    }

    /// The Mac's name on the tailnet (`Self.DNSName`), without its final dot.
    static func dnsName(_ json: String?) -> String? {
        guard let data = json?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let me = object["Self"] as? [String: Any], let name = me["DNSName"] as? String, !name.isEmpty else { return nil }
        return name.hasSuffix(".") ? String(name.dropLast()) : name
    }

    /// The Tailscale command line, read only; nil when it is not installed, fails or does not answer within five seconds.
    /// Launched from an app, the Tailscale app's binary may start as the app itself unless told it is its command line
    /// (`TAILSCALE_BE_CLI`, measured on 20/11: the address stayed empty).
    nonisolated static func run(_ arguments: [String]) async -> String? {
        await Task.detached {
            guard FileManager.default.isExecutableFile(atPath: tailscale.path) else { return nil }
            let process = Process()
            process.executableURL = tailscale
            process.arguments = arguments
            process.environment = ProcessInfo.processInfo.environment.merging(["TAILSCALE_BE_CLI": "1"]) { _, new in new }
            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()
            process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch { return nil }
            let deadline = DispatchTime.now() + 5
            DispatchQueue.global().asyncAfter(deadline: deadline) { if process.isRunning { process.terminate() } }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
        }.value
    }
}
