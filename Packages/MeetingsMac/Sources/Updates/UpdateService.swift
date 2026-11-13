import Foundation

public protocol UpdateInstalling: Sendable {
    func prepare(_ release: Release) async throws -> URL
    func launch(newApp: URL) throws
}

extension Installer: UpdateInstalling {}

/// Checks GitHub every hour and installs a newer version on its own, only when no meeting and no
/// transcription is going on (the same approach as the author's other apps).
@MainActor
public final class UpdateService: ObservableObject {
    public enum State: Equatable, Sendable {
        case idle, checking, downloading, waitingForIdle, installing
        case failed(String)
    }

    public static let autoKey = "updates.autoInstall"
    public static let checkInterval: TimeInterval = 3_600
    /// A failed installation is tried again an hour later, not at every tick.
    public static let retryAfter: TimeInterval = 3_600

    @Published public private(set) var newer: [Release] = []
    @Published public private(set) var lastCheck: Date?
    @Published public private(set) var state: State = .idle
    @Published public var autoInstall: Bool {
        didSet { defaults.set(autoInstall, forKey: Self.autoKey) }
    }
    public let current: SemanticVersion

    private let fetch: @Sendable () async throws -> Data
    private let installer: any UpdateInstalling
    private let isIdle: @MainActor () async -> Bool
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let quit: @MainActor () -> Void
    private var lastFailure: Date?
    private var busy = false

    public init(
        current: SemanticVersion, fetch: @escaping @Sendable () async throws -> Data = UpdateService.fetchFromGitHub,
        installer: any UpdateInstalling = Installer(), isIdle: @escaping @MainActor () async -> Bool, defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = Date.init, quit: @escaping @MainActor () -> Void = { exit(0) }
    ) {
        self.current = current
        self.fetch = fetch
        self.installer = installer
        self.isIdle = isIdle
        self.defaults = defaults
        self.now = now
        self.quit = quit
        autoInstall = defaults.object(forKey: Self.autoKey) as? Bool ?? true
    }

    public var latest: Release? { newer.first }

    /// The public list of versions; no token: the repository is public.
    public static let fetchFromGitHub: @Sendable () async throws -> Data = {
        var request = URLRequest(url: Releases.listURL, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Polhub", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    public func check() async {
        guard !busy else { return }
        state = .checking
        do {
            newer = Releases.newer(than: current, in: try Releases.parse(try await fetch()))
            state = .idle
        } catch {
            state = .failed("GitHub ne répond pas : la vérification reprendra dans une heure.")
        }
        lastCheck = now()
    }

    /// « Mettre à jour maintenant », or the automatic installation: waits for a quiet moment.
    public func installNow() async {
        guard !busy, let release = latest else { return }
        guard await isIdle() else {
            state = .waitingForIdle
            return
        }
        busy = true
        defer { busy = false }
        state = .downloading
        do {
            let app = try await installer.prepare(release)
            // A meeting may have started during the download.
            guard await isIdle() else {
                state = .waitingForIdle
                return
            }
            state = .installing
            try installer.launch(newApp: app)
            quit()
        } catch {
            lastFailure = now()
            state = .failed("La mise à jour \(release.version) n'a pas pu s'installer : \(error). Nouvel essai dans une heure.")
        }
    }

    /// Called every few minutes: checks once an hour, then installs when allowed and quiet.
    public func tick() async {
        if lastCheck.map({ now().timeIntervalSince($0) >= Self.checkInterval }) ?? true {
            await check()
        }
        guard latest != nil, autoInstall || state == .waitingForIdle else { return }
        if let failure = lastFailure, now().timeIntervalSince(failure) < Self.retryAfter { return }
        await installNow()
    }

    /// The sentence the screen shows for a state, if any.
    public static func text(_ state: State) -> String? {
        switch state {
        case .idle: nil
        case .checking: "Vérification…"
        case .downloading: "Téléchargement de la nouvelle version…"
        case .waitingForIdle: "La mise à jour s'installera à la fin de la réunion ou de la transcription en cours."
        case .installing: "Installation : Polhub va se relancer."
        case .failed(let message): message
        }
    }

    /// The line of the journal at the first launch of a new version.
    public static func upgradeNote(previous: String?, current: String) -> String? {
        guard let previous, previous != current else { return nil }
        return "Polhub mis à jour : \(previous) → \(current)."
    }
}
