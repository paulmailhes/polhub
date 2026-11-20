import Foundation
import LocalServer
import Persistence
import PolhubDesign
import PolhubLink

/// Réglages › iPhone (20/11): the switch that opens Polhub to Paul's iPhone, the address the iPhone reaches, the QR
/// code that pairs one, and the iPhones paired. The server listens on the Mac's loopback only; `tailscale serve`
/// publishes it on Paul's tailnet.
@MainActor
public final class PhoneAccess: ObservableObject {
    static let enabledKey = "iphone.acces"
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
            if newValue { Task { await start() } } else { stop() }
        }
    }

    let store: PhoneDevices
    let api: PhoneAPI
    private let defaults: UserDefaults
    private var server: HTTPServer?
    private let port: UInt16

    public init(database: AppDatabase, agenda: AgendaLibrary?, mails: MailLibrary?, appVersion: String, defaults: UserDefaults = .standard,
                port: UInt16 = LinkAPI.port) {
        self.defaults = defaults
        self.port = port
        store = PhoneDevices(defaults: defaults)
        api = PhoneAPI(devices: store, database: database, agenda: agenda, mails: mails, appVersion: appVersion)
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

    /// A QR code for a new iPhone, valid ten minutes; nil without an address.
    public func pair() {
        guard let base = Self.base(address) else {
            problem = "Indique d'abord l'adresse du Mac sur ton réseau Tailscale."
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

    /// Reads the Mac's name on the tailnet, for the address, and whether `tailscale serve` publishes the server.
    public func readTailscale() async {
        let status = await Self.run(["status", "--json"])
        let serve = await Self.run(["serve", "status", "--json"])
        if address.isEmpty, let name = Self.dnsName(status) {
            address = "https://\(name):\(LinkAPI.publishedPort)"
        }
        published = serve.map { $0.contains("127.0.0.1:\(LinkAPI.port)") }
    }

    /// The Mac's name on the tailnet (`Self.DNSName`), without its final dot.
    static func dnsName(_ json: String?) -> String? {
        guard let data = json?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let me = object["Self"] as? [String: Any], let name = me["DNSName"] as? String, !name.isEmpty else { return nil }
        return name.hasSuffix(".") ? String(name.dropLast()) : name
    }

    /// The Tailscale command line, read only; nil when it is not installed or fails.
    nonisolated static func run(_ arguments: [String]) async -> String? {
        await Task.detached {
            guard FileManager.default.isExecutableFile(atPath: tailscale.path) else { return nil }
            let process = Process()
            process.executableURL = tailscale
            process.arguments = arguments
            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()
            do { try process.run() } catch { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
        }.value
    }
}
