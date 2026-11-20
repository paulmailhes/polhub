import Foundation

/// Downloads a release, checks it, and hands over to the swap script.
public struct Installer: Sendable {
    public static let maxArchiveBytes: Int64 = 200 * 1_024 * 1_024
    public static let agent = "fr.paulmailhes.polhub.relance"
    /// The app an archive holds: its name since 20/11, then its name before.
    public static let appNames = ["hub.app", "Polhub.app"]

    public enum InstallError: Error, CustomStringConvertible {
        case download(String)
        case tooBig
        case noApp
        case refused(VerificationError)
        case launch(String)

        public var description: String {
            switch self {
            case .download(let reason): "le téléchargement a échoué (\(reason))"
            case .tooBig: "l'archive est anormalement grosse"
            case .noApp: "l'archive ne contient pas Polhub.app"
            case .refused(let error): "\(error)"
            case .launch(let reason): "l'installation ne démarre pas (\(reason))"
            }
        }
    }

    /// The app being replaced: the one running, when it runs from an `.app`.
    public let installed: URL
    public let keepOld: URL
    public let log: URL
    /// The file the new version writes once it has started (see `LaunchSignal`).
    public let signal: URL

    public init(
        installed: URL = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main.bundleURL : URL(fileURLWithPath: "/Applications/Polhub.app"),
        keepOld: URL = URL.applicationSupportDirectory.appending(path: "Polhub/Ancienne version", directoryHint: .isDirectory),
        log: URL = URL.libraryDirectory.appending(path: "Logs/Polhub/mise-a-jour.log"),
        signal: URL = LaunchSignal.file
    ) {
        self.installed = installed
        self.keepOld = keepOld
        self.log = log
        self.signal = signal
    }

    /// The release's app, downloaded, looked at, unpacked and checked; nothing is changed on the Mac yet.
    public func prepare(_ release: Release) async throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "polhub-maj-\(release.version)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let (downloaded, response) = try await download(release.archiveURL)
            if response.expectedContentLength > Self.maxArchiveBytes { throw InstallError.tooBig }
            // The tools block: they run away from the caller's thread (review, minor 5).
            return try await Task.detached(priority: .utility) {
                try self.check(downloaded, in: folder, release: release)
            }.value
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    private func download(_ url: URL) async throws -> (URL, URLResponse) {
        do {
            let (file, response) = try await URLSession.shared.download(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw InstallError.download("réponse \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            return (file, response)
        } catch let error as InstallError {
            throw error
        } catch {
            throw InstallError.download(error.localizedDescription)
        }
    }

    private func check(_ downloaded: URL, in folder: URL, release: Release) throws -> URL {
        let size = (try? FileManager.default.attributesOfItem(atPath: downloaded.path(percentEncoded: false))[.size] as? Int64) ?? 0
        guard size <= Self.maxArchiveBytes else { throw InstallError.tooBig }
        let archive = folder.appending(path: Releases.archiveName)
        try FileManager.default.moveItem(at: downloaded, to: archive)
        let listing = run("/usr/bin/zipinfo", [archive.path(percentEncoded: false)])
        guard listing.status == 0 else { throw InstallError.refused(.unsafeArchive("illisible")) }
        if let problem = ArchiveCheck.problem(listing: listing.output) { throw InstallError.refused(.unsafeArchive(problem)) }
        guard run("/usr/bin/ditto", ["-x", "-k", archive.path(percentEncoded: false), folder.path(percentEncoded: false)]).status == 0 else {
            throw InstallError.noApp
        }
        guard let app = Self.appNames.lazy.map({ folder.appending(path: $0, directoryHint: .isDirectory) })
            .first(where: { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }) else { throw InstallError.noApp }
        if let error = Verifier.signatureError(app: app) { throw InstallError.refused(error) }
        if let error = Verifier.check(info: Verifier.signedInfo(app: app), expected: release.version) { throw InstallError.refused(error) }
        return app
    }

    /// Writes the swap script and starts it in a session of its own, with default signal handling, nothing
    /// inherited from the app; the caller then quits the app.
    public func launch(newApp: URL, version: SemanticVersion) throws {
        // 20/11: the new version may carry another name (Polhub.app → hub.app); it goes beside the installed one, which is
        // taken away. The relaunch agent still names the installed app: the new one is opened by its path.
        let target = installed.deletingLastPathComponent().appending(path: newApp.lastPathComponent, directoryHint: .isDirectory)
        let renamed = SwapScript.path(target) != SwapScript.path(installed)
        let restart = "launchctl kickstart -k gui/\(getuid())/\(Self.agent) 2>/dev/null || open \(SwapScript.quote(SwapScript.path(installed)))"
        let processName = Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String ?? "Polhub"
        let newProcessName = Verifier.signedInfo(app: newApp)["CFBundleExecutable"] as? String ?? processName
        let script = SwapScript.make(
            newApp: newApp, installed: installed, target: target, keepOld: keepOld, version: version.description, signal: signal, log: log,
            pid: getpid(), processName: processName, newProcessName: newProcessName,
            start: renamed ? "open \(SwapScript.quote(SwapScript.path(target)))" : restart, startOld: restart,
            startTimeout: 30, failedKey: UpdateService.failedVersionKey,
            register: SwapScript.launchServicesRegister, verify: SwapScript.signatureCheck
        )
        let file = newApp.deletingLastPathComponent().appending(path: "echange.sh")
        try script.write(to: file, atomically: true, encoding: .utf8)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var all = sigset_t(), none = sigset_t()
        sigfillset(&all)
        sigemptyset(&none)
        posix_spawnattr_setsigdefault(&attributes, &all)
        posix_spawnattr_setsigmask(&attributes, &none)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        for descriptor: Int32 in [0, 1, 2] {
            posix_spawn_file_actions_addopen(&actions, descriptor, "/dev/null", descriptor == 0 ? O_RDONLY : O_WRONLY, 0)
        }
        var pid: pid_t = 0
        let arguments = ["/bin/bash", file.path(percentEncoded: false)]
        var argv = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        let status = posix_spawn(&pid, "/bin/bash", &actions, &attributes, &argv, environ)
        guard status == 0 else { throw InstallError.launch(String(cString: strerror(status))) }
    }

    /// Runs a tool; standard output and error together.
    func run(_ tool: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

/// Written by the app once it has really started: the swap script waits for it (review, important 3).
public enum LaunchSignal {
    public static var file: URL { URL.applicationSupportDirectory.appending(path: "Polhub/lancement.txt") }

    public static func write(version: String) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? version.write(to: file, atomically: true, encoding: .utf8)
    }
}

/// macOS caches an app's icon by the date of its folder; an update keeps the old folder's date (the archive keeps
/// the build's), so the Dock showed the icon of a version that had none (14/11). The app refreshes the date of its
/// folder when it is older than its program.
public enum BundleFreshness {
    /// `true` when the folder's date was refreshed.
    @discardableResult
    public static func refreshIfStale(bundle: URL, executable: URL, now: Date = Date()) -> Bool {
        let manager = FileManager.default
        guard let folder = (try? manager.attributesOfItem(atPath: bundle.path(percentEncoded: false)))?[.modificationDate] as? Date,
              let program = (try? manager.attributesOfItem(atPath: executable.path(percentEncoded: false)))?[.modificationDate] as? Date,
              folder < program else { return false }
        return (try? manager.setAttributes([.modificationDate: now], ofItemAtPath: bundle.path(percentEncoded: false))) != nil
    }
}

/// An installation that failed, in Paul's words, for `Words.problem` (lot 10, 20/11): the reason without the system's
/// text, which `description` keeps for the log.
extension Installer.InstallError: LocalizedError {
    public var failureReason: String? {
        switch self {
        case .download: "le téléchargement a échoué"
        case .launch: "l'installation ne démarre pas"
        case .tooBig, .noApp, .refused: description
        }
    }
}
