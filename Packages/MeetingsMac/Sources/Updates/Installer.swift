import Foundation

/// Downloads a release, checks its app, and hands over to the swap script.
public struct Installer: Sendable {
    public static let maxArchiveBytes: Int64 = 200 * 1_024 * 1_024
    public static let agent = "fr.paulmailhes.transcriptor.relance"

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
            case .noApp: "l'archive ne contient pas Transcriptor.app"
            case .refused(let error): "\(error)"
            case .launch(let reason): "l'installation ne démarre pas (\(reason))"
            }
        }
    }

    public let installed: URL
    public let keepOld: URL
    public let log: URL

    public init(installed: URL = URL(fileURLWithPath: "/Applications/Transcriptor.app"),
                keepOld: URL = URL.applicationSupportDirectory.appending(path: "Transcriptor/Ancienne version", directoryHint: .isDirectory),
                log: URL = URL.libraryDirectory.appending(path: "Logs/Transcriptor/mise-a-jour.log")) {
        self.installed = installed
        self.keepOld = keepOld
        self.log = log
    }

    /// The release's app, downloaded, unpacked and checked; nothing is changed on the Mac yet.
    public func prepare(_ release: Release) async throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "transcriptor-maj-\(release.version)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let downloaded: URL, response: URLResponse
        do {
            (downloaded, response) = try await URLSession.shared.download(from: release.archiveURL)
        } catch {
            throw InstallError.download(error.localizedDescription)
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw InstallError.download("réponse \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: downloaded.path(percentEncoded: false))[.size] as? Int64) ?? 0
        guard size <= Self.maxArchiveBytes else { throw InstallError.tooBig }
        let archive = folder.appending(path: Releases.archiveName)
        try FileManager.default.moveItem(at: downloaded, to: archive)
        guard run("/usr/bin/ditto", ["-x", "-k", archive.path(percentEncoded: false), folder.path(percentEncoded: false)]).status == 0 else {
            throw InstallError.noApp
        }
        let app = folder.appending(path: "Transcriptor.app", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: app.path(percentEncoded: false)) else { throw InstallError.noApp }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path(percentEncoded: false)]).status == 0 else {
            throw InstallError.refused(.invalidSignature)
        }
        let signature = run("/usr/bin/codesign", ["-dv", "--verbose=2", app.path(percentEncoded: false)]).output
        let info = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist")) as? [String: Any] ?? [:]
        if let error = Verifier.check(signature: signature, info: info, expected: release.version) {
            throw InstallError.refused(error)
        }
        return app
    }

    /// Writes the swap script and starts it in a session of its own; the caller then quits the app.
    public func launch(newApp: URL) throws {
        let script = SwapScript.make(newApp: newApp, installed: installed, keepOld: keepOld, agent: Self.agent, log: log,
                                     pid: getpid(), uid: getuid())
        let file = newApp.deletingLastPathComponent().appending(path: "echange.sh")
        try script.write(to: file, atomically: true, encoding: .utf8)
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))
        var pid: pid_t = 0
        let arguments = ["/bin/bash", file.path(percentEncoded: false)]
        var argv = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        let status = posix_spawn(&pid, "/bin/bash", nil, &attributes, &argv, environ)
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
