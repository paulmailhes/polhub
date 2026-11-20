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
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: macOS.appending(path: "hub"))
        let plist: NSDictionary = ["CFBundleIdentifier": "fr.paulmailhes.polhub", "CFBundleExecutable": "hub",
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

    /// Apple's notarization is required too (audit of 19/11): a version published without it never installs itself.
    /// Measured on 19/11: the installed version and the last one built meet it. Not measured: a Developer ID app never
    /// notarized (none on this Mac); Apple's requirement language says it fails.
    @Test func theRequirementAsksForAppleNotarization() {
        #expect(Verifier.requirement().hasSuffix(" and notarized"))
    }

    static let built = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../../../build/hub.app").standardizedFileURL

    /// Only after `make app`: a hub signed with the author's Developer ID passes.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: VerifierTests.built.path(percentEncoded: false))))
    func aBuiltHubPasses() {
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

extension VerifierTests {
    /// 20/11 : l'archive de la 0.58.0 contient hub.app ; une archive qui mêle deux apps, ou une autre, est refusée.
    @Test func anArchiveOfTheRenamedAppPasses() {
        let renamed = """
        drwxr-xr-x  2.1 unx        0 bx stor 26-Nov-21 09:00 hub.app/
        -rwxr-xr-x  2.1 unx   912432 bX defN 26-Nov-21 09:00 hub.app/Contents/MacOS/hub
        2 files, 912432 bytes uncompressed, 400000 bytes compressed:  56.2%
        """
        #expect(ArchiveCheck.problem(listing: renamed) == nil)
        let mixed = renamed.replacingOccurrences(of: "hub.app/Contents/MacOS/hub", with: "Polhub.app/Contents/MacOS/Polhub")
        #expect(ArchiveCheck.problem(listing: mixed) != nil)
        #expect(ArchiveCheck.problem(listing: renamed.replacingOccurrences(of: "hub.app/", with: "Autre.app/")) != nil)
        #expect(Installer.appNames == ["hub.app", "Polhub.app"])
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

    /// Run from a file, as the app does: its text is not in the command line `pgrep` reads.
    func run(_ script: String) throws -> Int32 {
        let file = FileManager.default.temporaryDirectory.appending(path: "echange-\(UUID().uuidString).sh")
        try script.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [file.path(percentEncoded: false)]
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
                                     startTimeout: 3, failedKey: nil, verify: "true")
        #expect(try run(script) == 0)
        #expect(try installedVersion(layout) == "0.3.1")
        let kept = try FileManager.default.contentsOfDirectory(atPath: layout.keep.path(percentEncoded: false))
        #expect(kept == ["hub-board-precedente.zip"])
    }

    @Test func aVersionThatNeverStartsIsRolledBack() throws {
        let layout = try layout()
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let script = SwapScript.make(newApp: layout.newApp, installed: layout.installed, keepOld: layout.keep, version: "0.3.1",
                                     signal: layout.signal, log: layout.log, pid: 999_999, processName: "polhub-test-absent",
                                     start: "true", startTimeout: 2, failedKey: nil, verify: "true")
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
                                     startTimeout: 3, failedKey: nil, register: "echo >> \(SwapScript.quote(marks.path(percentEncoded: false)))", verify: "true")
        #expect(try run(script) == 0)
        let installed = layout.installed.path(percentEncoded: false)
        let written = (try? String(contentsOf: marks, encoding: .utf8)) ?? ""
        #expect(written.contains(installed.hasSuffix("/") ? String(installed.dropLast()) : installed), "écrit : \(written)")
        #expect(SwapScript.launchServicesRegister.hasSuffix("LaunchServices.framework/Support/lsregister -f"))
    }

    /// The copy is checked again where it lands, and nothing is started that the author did not sign (audit of
    /// 19/11): a version swapped in the temporary folder after its check is put back to the old one, which starts.
    @Test func aCopyThatIsNotTheCheckedOneIsRolledBack() throws {
        let layout = try layout()
        defer { try? FileManager.default.removeItem(at: layout.root) }
        // The test's own check: an app is « signed » when it holds this mark; the new one lost it on the way.
        try "signée".write(to: layout.installed.appending(path: "Contents/signature"), atomically: true, encoding: .utf8)
        let checker = layout.root.appending(path: "verifier.sh")
        try "#!/bin/bash\ntest -f \"$1/Contents/signature\"\n".write(to: checker, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: checker.path(percentEncoded: false))
        let started = layout.root.appending(path: "lancees.txt")
        let script = SwapScript.make(newApp: layout.newApp, installed: layout.installed, keepOld: layout.keep, version: "0.3.1",
                                     signal: layout.signal, log: layout.log, pid: 999_999, processName: "polhub-test-absent",
                                     start: "cat \(SwapScript.quote(layout.installed.appending(path: "Contents/version").path(percentEncoded: false))) >> \(SwapScript.quote(started.path(percentEncoded: false)))",
                                     startTimeout: 2, failedKey: nil, verify: SwapScript.quote(checker.path(percentEncoded: false)))
        #expect(try run(script) != 0)
        #expect(try installedVersion(layout) == "0.3.0")
        #expect(try String(contentsOf: layout.log, encoding: .utf8).contains("pas signée par l'auteur"))
        // Only the old version, signed, was started.
        #expect(try String(contentsOf: started, encoding: .utf8) == "0.3.0")
    }

    /// The real check is Apple's: the author's Developer ID, hub, and Apple's notarization.
    @Test func theRealCheckIsTheVerifiersRequirement() {
        #expect(SwapScript.signatureCheck.hasPrefix("/usr/bin/codesign --verify --strict --deep -R "))
        #expect(SwapScript.signatureCheck.contains(Verifier.requirement()))
    }

    /// A real program called `name` in `folder`/Contents/MacOS, running until the test stops it. Built here: macOS
    /// kills a copy of a system program, and a script would be called `sh`.
    func program(named name: String, at folder: URL) throws -> Process {
        let directory = folder.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let binary = directory.appending(path: name)
        let source = folder.appending(path: "attente.c")
        try "#include <unistd.h>\nint main(void) { sleep(30); return 0; }\n".write(to: source, atomically: true, encoding: .utf8)
        let build = Process()
        build.executableURL = URL(fileURLWithPath: "/usr/bin/cc")
        build.arguments = [source.path(percentEncoded: false), "-o", binary.path(percentEncoded: false)]
        try build.run()
        build.waitUntilExit()
        let process = Process()
        process.executableURL = binary
        try process.run()
        Thread.sleep(forTimeInterval: 0.3)
        return process
    }

    /// 20/11: the iPhone app in the simulator is called hub too; the swap took it for another copy, gave up, and
    /// left Paul without hub. Only a copy of the installed app counts.
    @Test func aProgramOfTheSameNameElsewhereDoesNotStopTheSwap() throws {
        let layout = try layout()
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let name = "pt\(UUID().uuidString.prefix(8))"
        let other = try program(named: name, at: layout.root.appending(path: "Simulateur/Polhub.app", directoryHint: .isDirectory))
        defer { other.terminate() }
        let script = SwapScript.make(newApp: layout.newApp, installed: layout.installed, keepOld: layout.keep, version: "0.3.1",
                                     signal: layout.signal, log: layout.log, pid: 999_999, processName: name,
                                     start: "echo 0.3.1 > \(SwapScript.quote(layout.signal.path(percentEncoded: false)))",
                                     startTimeout: 3, failedKey: nil, verify: "true", waitSteps: 5)
        #expect(try run(script) == 0)
        #expect(try installedVersion(layout) == "0.3.1")
    }

    /// When a copy of the installed app does run, nothing is changed, but hub is started again all the same.
    @Test func anotherCopyOfTheInstalledAppStopsTheSwapButPolhubStartsAgain() throws {
        let layout = try layout()
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let name = "pt\(UUID().uuidString.prefix(8))"
        let other = try program(named: name, at: layout.installed)
        defer { other.terminate() }
        let started = layout.root.appending(path: "lancees.txt")
        let script = SwapScript.make(newApp: layout.newApp, installed: layout.installed, keepOld: layout.keep, version: "0.3.1",
                                     signal: layout.signal, log: layout.log, pid: 999_999, processName: name,
                                     start: "echo lancée >> \(SwapScript.quote(started.path(percentEncoded: false)))",
                                     startTimeout: 2, failedKey: nil, verify: "true", waitSteps: 5)
        #expect(try run(script) != 0)
        #expect(try installedVersion(layout) == "0.3.0")
        #expect(try String(contentsOf: layout.log, encoding: .utf8).contains("une autre copie tourne encore"))
        #expect((try? String(contentsOf: started, encoding: .utf8)) == "lancée\n")
    }

    /// 20/11 : la 0.58.0 s'appelle hub.app. Elle prend sa place à côté, l'ancienne app est mise de côté puis retirée.
    @Test func aRenamedSwapInstallsTheNewNameAndRemovesTheOld() throws {
        let layout = try layout()
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let (newApp, target) = try renamed(layout)
        let script = SwapScript.make(newApp: newApp, installed: layout.installed, target: target, keepOld: layout.keep, version: "0.3.1",
                                     signal: layout.signal, log: layout.log, pid: 999_999, processName: "polhub-test-absent",
                                     newProcessName: "hub-test-absent",
                                     start: "echo 0.3.1 > \(SwapScript.quote(layout.signal.path(percentEncoded: false)))",
                                     startTimeout: 3, failedKey: nil, verify: "true")
        #expect(try run(script) == 0)
        #expect(try String(contentsOf: target.appending(path: "Contents/version"), encoding: .utf8) == "0.3.1")
        #expect(!FileManager.default.fileExists(atPath: layout.installed.path(percentEncoded: false)))
        #expect(try FileManager.default.contentsOfDirectory(atPath: layout.keep.path(percentEncoded: false)) == ["hub-board-precedente.zip"])
    }

    /// A renamed version that never starts: the old app comes back under its own name, the new one is taken away.
    @Test func aRenamedSwapThatDoesNotStartGivesTheOldAppBack() throws {
        let layout = try layout()
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let (newApp, target) = try renamed(layout)
        let script = SwapScript.make(newApp: newApp, installed: layout.installed, target: target, keepOld: layout.keep, version: "0.3.1",
                                     signal: layout.signal, log: layout.log, pid: 999_999, processName: "polhub-test-absent",
                                     newProcessName: "hub-test-absent", start: "true", startTimeout: 1, failedKey: nil, verify: "true")
        #expect(try run(script) != 0)
        #expect(try installedVersion(layout) == "0.3.0")
        #expect(!FileManager.default.fileExists(atPath: target.path(percentEncoded: false)))
        #expect(try String(contentsOf: layout.log, encoding: .utf8).contains("retour à l'ancienne version"))
    }

    /// The new version under its new name, `maj/hub.app`, and where it goes, `Applications/hub.app`.
    func renamed(_ layout: Layout) throws -> (URL, URL) {
        let newApp = layout.root.appending(path: "maj/hub.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: newApp.appending(path: "Contents"), withIntermediateDirectories: true)
        try "0.3.1".write(to: newApp.appending(path: "Contents/version"), atomically: true, encoding: .utf8)
        return (newApp, layout.root.appending(path: "Applications/hub.app", directoryHint: .isDirectory))
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
