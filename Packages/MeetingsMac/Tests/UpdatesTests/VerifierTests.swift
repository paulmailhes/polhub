import Foundation
import Testing
@testable import Updates

@Suite struct VerifierTests {
    let info: [String: Any] = ["CFBundleIdentifier": "fr.paulmailhes.polhub", "CFBundleShortVersionString": "0.3.1"]
    let expected = SemanticVersion("0.3.1")!

    @Test func theRightVersionPasses() {
        #expect(Verifier.check(info: info, expected: expected) == nil)
    }

    @Test func anOlderOrDifferentVersionIsRefused() {
        var older = info
        older["CFBundleShortVersionString"] = "0.3.0"
        #expect(Verifier.check(info: older, expected: expected) == .wrongVersion)
        var other = info
        other["CFBundleIdentifier"] = "fr.paulmailhes.autre"
        #expect(Verifier.check(info: other, expected: expected) == .wrongIdentifier)
    }

    /// An app signed by anyone else (here: signed on the spot, without a certificate) never passes, even
    /// with the right identifier (review, critical 1: the check is Apple's, not a reading of codesign's text).
    @Test func anAppSignedByAnyoneElseIsRefused() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "faux \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = folder.appending(path: "Polhub.app", directoryHint: .isDirectory)
        let macOS = app.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: macOS.appending(path: "Polhub"))
        let plist: NSDictionary = ["CFBundleIdentifier": "fr.paulmailhes.polhub", "CFBundleExecutable": "Polhub",
                                   "CFBundleShortVersionString": "0.3.1", "CFBundlePackageType": "APPL"]
        plist.write(to: app.appending(path: "Contents/Info.plist"), atomically: true)
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--sign", "-", "--identifier", "fr.paulmailhes.polhub", app.path(percentEncoded: false)]
        try sign.run()
        sign.waitUntilExit()
        #expect(sign.terminationStatus == 0)
        #expect(Verifier.signatureError(app: app) == .wrongTeam)
        #expect(Verifier.signatureError(app: URL(fileURLWithPath: "/System/Applications/Calculator.app")) == .wrongTeam)
    }

    static let built = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../../../build/Polhub.app").standardizedFileURL

    /// Only after `make app`: a Polhub signed with the author's Developer ID passes.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: VerifierTests.built.path(percentEncoded: false))))
    func aBuiltPolhubPasses() {
        #expect(Verifier.signatureError(app: Self.built) == nil)
    }

    // Revue, important 1 : l'archive est inspectée avant d'être ouverte.
    @Test func anArchiveWithLinksOrEscapingPathsIsRefused() {
        let good = """
        drwxr-xr-x  2.1 unx        0 bx stor 26-Nov-13 18:00 Polhub.app/
        -rwxr-xr-x  2.1 unx   912432 bX defN 26-Nov-13 18:00 Polhub.app/Contents/MacOS/Polhub
        2 files, 912432 bytes uncompressed, 400000 bytes compressed:  56.2%
        """
        #expect(ArchiveCheck.problem(listing: good) == nil)
        #expect(ArchiveCheck.problem(listing: good.replacingOccurrences(of: "-rwxr-xr-x", with: "lrwxr-xr-x")) != nil)
        #expect(ArchiveCheck.problem(listing: good.replacingOccurrences(of: "Polhub.app/Contents/MacOS/Polhub", with: "Polhub.app/../../.zshrc")) != nil)
        #expect(ArchiveCheck.problem(listing: good.replacingOccurrences(of: "Polhub.app/Contents/MacOS/Polhub", with: "/Users/x/evil")) != nil)
        #expect(ArchiveCheck.problem(listing: good.replacingOccurrences(of: "912432 bytes uncompressed", with: "5000000000 bytes uncompressed")) != nil)
        #expect(ArchiveCheck.problem(listing: good.replacingOccurrences(of: "Polhub.app/Contents", with: "Autre.app/Contents")) != nil)
    }
}

/// The swap script, run for real in a temporary folder: success, then a new version that never starts.
@Suite struct SwapScriptTests {
    struct Layout {
        let root: URL
        var installed: URL { root.appending(path: "Applications/Polhub.app", directoryHint: .isDirectory) }
        var newApp: URL { root.appending(path: "maj/Polhub.app", directoryHint: .isDirectory) }
        var keep: URL { root.appending(path: "Ancienne version", directoryHint: .isDirectory) }
        var signal: URL { root.appending(path: "lancement.txt") }
        var log: URL { root.appending(path: "Logs/mise-a-jour.log") }
    }

    func layout() throws -> Layout {
        let layout = Layout(root: FileManager.default.temporaryDirectory.appending(path: "échange \(UUID().uuidString)", directoryHint: .isDirectory))
        for (app, version) in [(layout.installed, "0.3.0"), (layout.newApp, "0.3.1")] {
            try FileManager.default.createDirectory(at: app.appending(path: "Contents"), withIntermediateDirectories: true)
            try version.write(to: app.appending(path: "Contents/version"), atomically: true, encoding: .utf8)
        }
        return layout
    }

    func run(_ script: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    func installedVersion(_ layout: Layout) throws -> String {
        try String(contentsOf: layout.installed.appending(path: "Contents/version"), encoding: .utf8)
    }

    @Test func aGoodVersionReplacesTheOldOneWhichIsKeptAside() throws {
        let layout = try layout()
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let script = SwapScript.make(newApp: layout.newApp, installed: layout.installed, keepOld: layout.keep, version: "0.3.1",
                                     signal: layout.signal, log: layout.log, pid: 999_999, processName: "polhub-test-absent",
                                     start: "echo 0.3.1 > \(SwapScript.quote(layout.signal.path(percentEncoded: false)))",
                                     startTimeout: 3, failedKey: nil)
        #expect(try run(script) == 0)
        #expect(try installedVersion(layout) == "0.3.1")
        let kept = try FileManager.default.contentsOfDirectory(atPath: layout.keep.path(percentEncoded: false))
        #expect(kept == ["Polhub-precedente.zip"])
    }

    @Test func aVersionThatNeverStartsIsRolledBack() throws {
        let layout = try layout()
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let script = SwapScript.make(newApp: layout.newApp, installed: layout.installed, keepOld: layout.keep, version: "0.3.1",
                                     signal: layout.signal, log: layout.log, pid: 999_999, processName: "polhub-test-absent",
                                     start: "true", startTimeout: 2, failedKey: nil)
        #expect(try run(script) != 0)
        #expect(try installedVersion(layout) == "0.3.0")
        let log = try String(contentsOf: layout.log, encoding: .utf8)
        #expect(log.contains("retour à l'ancienne version"))
    }

    /// 14/11: the swapped app is registered again, so the Dock and the Finder show its new icon at once.
    @Test func theNewVersionIsRegisteredWithLaunchServices() throws {
        let layout = try layout()
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let marks = layout.root.appending(path: "enregistrement.txt")
        let script = SwapScript.make(newApp: layout.newApp, installed: layout.installed, keepOld: layout.keep, version: "0.3.1",
                                     signal: layout.signal, log: layout.log, pid: 999_999, processName: "polhub-test-absent",
                                     start: "echo 0.3.1 > \(SwapScript.quote(layout.signal.path(percentEncoded: false)))",
                                     startTimeout: 3, failedKey: nil, register: "echo >> \(SwapScript.quote(marks.path(percentEncoded: false)))")
        #expect(try run(script) == 0)
        let installed = layout.installed.path(percentEncoded: false)
        let written = (try? String(contentsOf: marks, encoding: .utf8)) ?? ""
        #expect(written.contains(installed.hasSuffix("/") ? String(installed.dropLast()) : installed), "écrit : \(written)")
        #expect(SwapScript.launchServicesRegister.hasSuffix("LaunchServices.framework/Support/lsregister -f"))
    }

    @Test func quotesSurviveAnyPath() {
        #expect(SwapScript.quote("l'app") == #"'l'\''app'"#)
    }
}

/// 14/11: macOS caches an app's icon by the date of its folder; an update keeps the old folder's date, so the
/// Dock showed the icon of a version without one. The app refreshes it when its folder is older than its program.
@Suite struct BundleFreshnessTests {
    @Test func aFolderOlderThanItsProgramIsRefreshed() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "fraicheur-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appending(path: "Essai.app", directoryHint: .isDirectory)
        let program = app.appending(path: "Contents/MacOS/Essai")
        try FileManager.default.createDirectory(at: program.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: program)
        let old = Date(timeIntervalSince1970: 1_790_000_000), new = Date(timeIntervalSince1970: 1_794_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: app.path(percentEncoded: false))
        try FileManager.default.setAttributes([.modificationDate: new], ofItemAtPath: program.path(percentEncoded: false))
        #expect(BundleFreshness.refreshIfStale(bundle: app, executable: program, now: new.addingTimeInterval(60)))
        let date = try #require(try FileManager.default.attributesOfItem(atPath: app.path(percentEncoded: false))[.modificationDate] as? Date)
        #expect(date >= new)
        #expect(!BundleFreshness.refreshIfStale(bundle: app, executable: program, now: new.addingTimeInterval(120)))
    }
}
