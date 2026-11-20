import Foundation
import Testing
@testable import MeetingDetection

@MainActor final class Counter { var n = 0 }
@MainActor final class Recorder { var sources: [String] = [] }

@MainActor @Suite struct DiaAdapterTests {
    // Review Focus 2 : Dia absent → aucun événement envoyé (cela le lancerait).
    @Test func notRunningNeverRunsScript() async {
        let calls = Counter()
        let a = DiaAdapter(isRunning: { false }, runScript: { @MainActor _ in calls.n += 1; return .success("") })
        #expect(await a.meetTabs() == .browserNotRunning)
        #expect(calls.n == 0)
    }

    @Test func mapsScriptFailures() async {
        func adapter(_ code: Int) -> DiaAdapter {
            DiaAdapter(isRunning: { true }, runScript: { _ in .failure(ScriptFailure(code: code, message: "x")) })
        }
        #expect(await adapter(-1743).meetTabs() == .permissionDenied)
        #expect(await adapter(-600).meetTabs() == .browserNotRunning)
        #expect(await adapter(-1728).meetTabs() == .failed(code: -1728, message: "x"))
    }

    @Test func runsTheScriptOfTheChosenVariantAndParsesItsOutput() async {
        let recorder = Recorder()
        let raw = ["w", "t", "false", "true", "false", "https://meet.google.com/abc-defg-hij", "Meet"].joined(separator: "\u{1F}") + "\u{1E}"
        let whose = DiaAdapter(variant: .whose, isRunning: { true }, runScript: { @MainActor in recorder.sources.append($0); return .success(raw) })
        let loop = DiaAdapter(variant: .loop, isRunning: { true }, runScript: { @MainActor in recorder.sources.append($0); return .success(raw) })
        #expect(await whose.meetTabs() == .tabs(DiaTabParser.parse(raw)))
        #expect(await loop.meetTabs() == .tabs(DiaTabParser.parse(raw)))
        let sources = recorder.sources
        #expect(sources.count == 2 && sources[0] != sources[1])
        #expect(sources[0].contains("whose URL contains \"meet.google.com\""))
        #expect(!sources[1].contains("whose"))
        #expect(sources.allSatisfy { $0.contains("application id \"company.thebrowser.dia\"") })
    }
}

@MainActor @Suite struct DiaScriptTests {
    // Compile seulement : aucun événement n'est envoyé à Dia, aucune autorisation n'est en jeu.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/Applications/Dia.app")))
    func bothVariantsCompileAgainstDiaDictionary() throws {
        for variant in [DiaAdapter.Variant.whose, .loop] {
            let script = try #require(NSAppleScript(source: DiaAdapter.source(for: variant)))
            var error: NSDictionary?
            let compiled = script.compileAndReturnError(&error)
            #expect(compiled, "variante \(variant.rawValue) : \(error ?? [:])")
        }
    }
}

/// A page's title is chosen by its author (audit of 19/11): with the two separators in it, it could forge a Meet tab
/// in front. The script turns them into spaces before hub reads them. Run by AppleScript itself, without Dia.
@MainActor @Suite struct DiaTitleTests {
    @Test func theSeparatorsOfATitleBecomeSpaces() throws {
        let source = DiaAdapter.cleaner + "\nreturn my clean(\"Point\" & (character id 30) & \"w9\" & (character id 31) & \"t9\")"
        let script = try #require(NSAppleScript(source: source))
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        #expect(error == nil && result.stringValue == "Point w9 t9", "\(error ?? [:])")
    }

    @Test func bothVariantsCleanTheTitle() {
        for variant in [DiaAdapter.Variant.whose, .loop] {
            let source = DiaAdapter.source(for: variant)
            #expect(source.contains("(my clean(title of t)) & rs") && !source.contains("(title of t) & rs") && source.contains(DiaAdapter.cleaner))
        }
    }
}

@MainActor @Suite struct DiaWindowGuardTests {
    let fs = "\u{1F}", rs = "\u{1E}"
    var tab: String { ["w1", "t1", "false", "true", "false", "https://meet.google.com/abc-defg-hij", "Meet"].joined(separator: fs) + rs }
    var windowOK: String { "+" + rs }
    var windowFailed: String { ["!", "-1728", "Impossible d'obtenir tabs"].joined(separator: fs) + rs }

    @Test func separatesTabsWindowFailuresAndWindowsReadWithoutTrouble() {
        let out = DiaTabParser.parseDetailed(windowOK + tab + windowOK + windowFailed)
        #expect(out.tabs.map(\.tabID) == ["t1"])
        #expect(out.windowsRead == 2)
        #expect(out.windowFailures == [ScriptFailure(code: -1728, message: "Impossible d'obtenir tabs")])
        #expect(DiaTabParser.parse(windowOK + tab + windowFailed).map(\.tabID) == ["t1"])
    }

    func adapter(returning raw: String) -> DiaAdapter {
        DiaAdapter(isRunning: { true }, runScript: { _ in .success(raw) })
    }

    // One odd window (picture-in-picture, settings…) must not blind the whole reading.
    @Test func oneWindowThatFailsLeavesTheOthersReadable() async {
        let result = await adapter(returning: tab + windowOK + windowFailed).meetTabs()
        #expect(result == .partial(tabs: DiaTabParser.parse(tab), failures: [ScriptFailure(code: -1728, message: "Impossible d'obtenir tabs")]))
    }

    @Test func everyWindowFailingIsAFailureNotAnEmptyReading() async {
        #expect(await adapter(returning: windowFailed + windowFailed).meetTabs() == .failed(code: -1728, message: "Impossible d'obtenir tabs"))
    }

    @Test func noWindowAtAllIsAnEmptyReading() async {
        #expect(await adapter(returning: "").meetTabs() == .tabs([]))
    }

    // Dia quit between the check and the event: the script itself refuses to wake it up.
    @Test func theScriptRefusesToRelaunchDia() async {
        #expect(await adapter(returning: DiaTabParser.notRunningSentinel).meetTabs() == .browserNotRunning)
        for variant in [DiaAdapter.Variant.whose, .loop] {
            let source = DiaAdapter.source(for: variant)
            #expect(source.contains("is not running then return \"\(DiaTabParser.notRunningSentinel)\""))
            #expect(source.contains("on error errorMessage number errorNumber") && source.contains("end try"))
        }
    }

    // Review Focus 2 : un Dia en train de démarrer ou de quitter n'est pas « là ».
    @Test func aBrowserStillLaunchingOrQuittingDoesNotCountAsRunning() {
        #expect(DiaAdapter.isUsable(finishedLaunching: true, terminated: false))
        #expect(!DiaAdapter.isUsable(finishedLaunching: false, terminated: false))
        #expect(!DiaAdapter.isUsable(finishedLaunching: true, terminated: true))
    }
}

@MainActor @Suite struct DiaForeignTabTests {
    // An address that merely mentions meet.google.com (a search, a mail) is not a Meet tab: neither its
    // address nor its title may leave the adapter.
    @Test func onlyTabsHostedByMeetAreReturned() async {
        let fs = "\u{1F}", rs = "\u{1E}"
        func record(_ id: String, _ url: String, _ title: String) -> String {
            ["w", id, "false", "false", "false", url, title].joined(separator: fs) + rs
        }
        let raw = record("t1", "https://meet.google.com/abc-defg-hij", "Point hebdo")
            + record("t2", "https://www.google.com/search?q=meet.google.com", "meet.google.com - Recherche")
            + record("t3", "https://mail.google.com/mail/u/0/#search/meet.google.com", "Boîte de réception")
            + record("t4", "https://meet.google.com/landing", "Google Meet")
        let adapter = DiaAdapter(isRunning: { true }, runScript: { _ in .success(raw + "+" + rs) })
        guard case .tabs(let tabs) = await adapter.meetTabs() else {
            Issue.record("lecture attendue")
            return
        }
        #expect(tabs.map(\.tabID) == ["t1", "t4"])
    }
}

@Suite struct OsascriptRunnerTests {
    // Mesure d'entrée de l'étape 1 : lire les onglets hors du fil principal, par osascript.
    @Test func readsTheAppleEventErrorFromOsascript() {
        #expect(OsascriptRunner.failure(stderr: "51:60: execution error: Not authorized to send Apple events to Dia. (-1743)\n", status: 1).code == -1743)
        #expect(OsascriptRunner.failure(stderr: "execution error: Dia got an error: Connection is invalid. (-609)", status: 1).code == -609)
        #expect(OsascriptRunner.failure(stderr: "garbage", status: 1).code == -1)
    }
}
