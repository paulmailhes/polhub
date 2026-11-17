import Foundation
import PolhubDesign
import Testing
@testable import MeetingsUI

@MainActor @Suite struct ColinProbeControlTests {
    /// Holds a check until it is released.
    @MainActor final class Gate {
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var isOpen = false
        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func release() {
            isOpen = true
            waiters.forEach { $0.resume() }
            waiters = []
        }
    }

    /// What the app's runner of probes would be told, and what its probe would conclude.
    @MainActor final class Runner {
        var accounts: [String] = []
        var finish: (@MainActor (String?) -> Void)?
        /// Why the runner cannot start; `nil`: it starts.
        var refusal: String?
        var stops = 0
        var quiet = true
        var gate: Gate?
        /// The report the probe leaves; `nil`: none (it was stopped before its end).
        var verdict: Bool? = true
        var reason: String?
        /// Whether all was quiet at the very moment the probe was started.
        var quietAtStart: Bool?
    }

    static let home = URL(fileURLWithPath: "/Users/essai", isDirectory: true)

    func defaults() -> UserDefaults {
        let name = "colin-sonde-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func control(_ runner: Runner, defaults: UserDefaults? = nil, verdict: Bool? = true, reason: String? = nil,
                 exists: Bool = true, isAccount: Bool = true, uptime: TimeInterval = 86_400, lastWake: Date? = nil,
                 settle: Duration = .seconds(300), rest: Duration = .zero) -> ColinProbeControl {
        runner.verdict = verdict
        runner.reason = reason
        return ColinProbeControl(defaults: defaults ?? self.defaults(), home: Self.home, isQuiet: {
            await runner.gate?.wait()
            return runner.quiet
        }, start: { account, onFinish in
            if let refusal = runner.refusal { return refusal }
            runner.quietAtStart = runner.quiet
            runner.accounts.append(account)
            runner.finish = onFinish
            return nil
        }, stop: { runner.stops += 1 }, report: { runner.verdict.map { (ok: $0, reason: runner.reason) } },
        folderExists: { _ in exists }, isAccount: { _ in isAccount }, uptime: { uptime }, lastWake: { lastWake },
        watchEvery: .milliseconds(20), settleAfterWake: settle, restAfterFinish: rest)
    }

    static let meeting = "Arrêtée : une réunion ou une transcription commence. Relance la sonde après."

    @Test func duringAMeetingTheProbeIsRefused() async {
        let runner = Runner()
        runner.quiet = false
        let control = control(runner)
        await control.launch()
        #expect(control.phase == .refused("Pas pendant une réunion ni une transcription."))
        #expect(control.message == "Pas pendant une réunion ni une transcription.")
        #expect(runner.accounts.isEmpty)
    }

    @Test func aMissingAccountFolderIsRefused() async {
        let runner = Runner()
        let control = control(runner, exists: false)
        control.choose("/tmp/compte-disparu")
        await control.launch()
        #expect(control.phase == .refused("Ce dossier de compte n'existe plus."))
        #expect(runner.accounts.isEmpty)
    }

    @Test func aFolderThatIsNoAccountIsRefused() async {
        // Any folder can be chosen in the panel: Claude Code would write its own files in it.
        let runner = Runner()
        let control = control(runner, isAccount: false)
        control.choose("/tmp/pas-un-compte")
        await control.launch()
        #expect(control.phase == .refused("Ce dossier n'est pas celui d'un compte Claude."))
        #expect(runner.accounts.isEmpty)
    }

    @Test func claudeCodesOwnAccountNeedsNoFolder() async {
        let runner = Runner()
        let control = control(runner, exists: false, isAccount: false)
        await control.launch()
        #expect(control.phase == .running)
        #expect(runner.accounts == [""])
    }

    @Test func aLaunchGoesFromRunningToDoneWithItsVerdict() async {
        let runner = Runner()
        let control = control(runner)
        #expect(control.phase == .idle && control.message == nil)
        await control.launch()
        #expect(control.phase == .running)
        #expect(control.message == "La sonde tourne. Tu peux continuer à travailler.")
        #expect(runner.accounts == [""])
        runner.finish?(nil)
        #expect(control.phase == .done(true))
        #expect(control.message == "Terminé : Claude Code a répondu. Le relevé est enregistré.")
    }

    @Test func aPointToLookAtIsSaidSo() async {
        let runner = Runner()
        let control = control(runner, verdict: false)
        await control.launch()
        runner.finish?(nil)
        #expect(control.phase == .done(false))
        #expect(control.message == "Terminé : un point est à regarder. Le relevé est enregistré.")
    }

    @Test func theReasonIsSaidWhenTheProbeKnowsIt() async {
        let sentences = [
            "introuvable": "Terminé : Claude Code est introuvable sur ce Mac. Le relevé est enregistré.",
            "pas-connecte": "Terminé : Claude Code n'est pas connecté sur ce compte. Le relevé est enregistré.",
            "limite-atteinte": "Terminé : ton compte Claude a atteint sa limite. Le relevé est enregistré.",
            "sans-reponse": "Terminé : Claude Code n'a pas répondu. Le relevé est enregistré.",
            "lancement-impossible": "Terminé : Claude Code n'a pas pu se lancer. Le relevé est enregistré.",
            "isolation": "Terminé : Claude Code a chargé plus que ce que Polhub lui demande. Le relevé est enregistré.",
            "isolation-inconnue": "Terminé : Polhub n'a pas pu vérifier ce que Claude Code a chargé. Le relevé est enregistré.",
            "erreur": "Terminé : Claude Code a répondu par une erreur dès le premier lancement. Le relevé est enregistré.",
            "une-raison-inconnue": "Terminé : un point est à regarder. Le relevé est enregistré.",
        ]
        for (reason, sentence) in sentences {
            let runner = Runner()
            let control = control(runner, verdict: false, reason: reason)
            await control.launch()
            runner.finish?(nil)
            #expect(control.message == sentence, "\(reason)")
        }
    }

    @Test func aProbeWithoutAReportStoppedBeforeItsEnd() async {
        let runner = Runner()
        let control = control(runner, verdict: nil)
        await control.launch()
        runner.finish?(nil)
        #expect(control.phase == .done(nil))
        #expect(control.message == "La sonde s'est arrêtée avant la fin.")
    }

    @Test func whatTheRunnerRefusesIsSaid() async {
        let runner = Runner()
        runner.refusal = "Une autre sonde tourne déjà."
        let control = control(runner)
        await control.launch()
        #expect(control.phase == .refused("Une autre sonde tourne déjà."))
        // Whatever the runner says: a trace that cannot be written is not « another probe ».
        runner.refusal = "Impossible d'écrire la trace."
        await control.launch()
        #expect(control.phase == .refused("Impossible d'écrire la trace."))
        #expect(runner.accounts.isEmpty)
    }

    @Test func aProblemOfTheRunIsShown() async {
        // The trace could no longer be written: the run stopped, and says why.
        let runner = Runner()
        let control = control(runner, verdict: nil)
        await control.launch()
        runner.finish?("La trace n'a plus pu être écrite, la mesure s'est arrêtée.")
        #expect(control.phase == .done(nil))
        #expect(control.message == "La trace n'a plus pu être écrite, la mesure s'est arrêtée.")
    }

    @Test func aSecondLaunchWhileItRunsDoesNothing() async {
        let runner = Runner()
        let control = control(runner)
        await control.launch()
        await control.launch()
        #expect(runner.accounts.count == 1)
    }

    @Test func aSecondClickDuringTheCheckDoesNothing() async {
        // A double click: the second arrives while the first still checks that no meeting is on.
        let runner = Runner()
        let gate = Gate()
        runner.gate = gate
        let control = control(runner)
        async let first: Void = control.launch()
        async let second: Void = control.launch()
        for _ in 0..<10 { await Task.yield() }
        gate.release()
        _ = await (first, second)
        #expect(runner.accounts.count == 1)
        #expect(control.phase == .running)
    }

    @Test func aClickRightAfterTheEndDoesNothing() async throws {
        // The second click of a double click on « Arrêter » lands on « Lancer », which took its place.
        let runner = Runner()
        let control = control(runner, rest: .milliseconds(150))
        await control.launch()
        control.stopByHand()
        runner.verdict = nil
        runner.finish?(nil)
        await control.launch()
        #expect(runner.accounts.count == 1)
        #expect(control.message == "Arrêtée.")
        try await Task.sleep(for: .milliseconds(200))
        runner.verdict = true
        await control.launch()
        #expect(runner.accounts.count == 2)
        #expect(control.phase == .running)
    }

    // MARK: - What stops a probe under way

    @Test func aMeetingThatBeginsStopsTheProbe() async throws {
        let runner = Runner()
        let control = control(runner, verdict: nil)
        await control.launch()
        runner.quiet = false
        for _ in 0..<100 where runner.stops == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(runner.stops == 1)
        runner.finish?(nil)
        #expect(control.phase == .done(nil))
        #expect(control.message == Self.meeting)
    }

    @Test func aMeetingToldAtOnceStopsTheProbe() async {
        // The app says it the moment the pop-up shows, without waiting for the next look.
        let runner = Runner()
        let control = control(runner, verdict: nil)
        await control.launch()
        control.meetingBegan()
        #expect(runner.stops == 1)
        control.meetingBegan()
        #expect(runner.stops == 1)
        runner.finish?(nil)
        #expect(control.phase == .done(nil))
        #expect(control.message == Self.meeting)
    }

    @Test func aMeetingToldWhenNothingRunsDoesNothing() {
        let runner = Runner()
        let control = control(runner)
        control.meetingBegan()
        control.stopByHand()
        control.macWillSleep()
        #expect(runner.stops == 0)
        #expect(control.phase == .idle)
    }

    @Test func stoppedByHandItSaysSo() async {
        let runner = Runner()
        let control = control(runner, verdict: nil)
        await control.launch()
        control.stopByHand()
        control.stopByHand()
        #expect(runner.stops == 1)
        // Until the probe has really ended, it still runs.
        #expect(control.phase == .running)
        runner.finish?(nil)
        #expect(control.phase == .done(nil))
        #expect(control.message == "Arrêtée.")
    }

    @Test func theFirstReasonOfAStopIsTheOneSaid() async {
        // « Arrêter », then a meeting begins before the probe has ended: it was stopped by hand.
        let runner = Runner()
        let control = control(runner, verdict: nil)
        await control.launch()
        control.stopByHand()
        control.meetingBegan()
        control.macWillSleep()
        #expect(runner.stops == 1)
        runner.finish?(nil)
        #expect(control.message == "Arrêtée.")
    }

    @Test func nothingWaitsBetweenTheCheckAndTheStart() async {
        // A meeting that begins right after the check must find the probe started, and stop it: it cannot slip in
        // between. The start follows the check with nothing awaited.
        let runner = Runner()
        runner.gate = nil
        let control = ColinProbeControl(defaults: defaults(), home: Self.home, isQuiet: {
            // The meeting begins as soon as anything else gets to run.
            Task { @MainActor in runner.quiet = false }
            return runner.quiet
        }, start: { _, onFinish in
            runner.quietAtStart = runner.quiet
            runner.finish = onFinish
            return nil
        }, stop: { runner.stops += 1 }, report: { nil }, folderExists: { _ in true }, isAccount: { _ in true },
        uptime: { 86_400 }, lastWake: { nil }, watchEvery: .seconds(30))
        control.choose("/Users/essai/comptes/second")
        await control.launch()
        #expect(runner.quietAtStart == true)
        #expect(control.phase == .running)
    }

    @Test func aMacThatGoesToSleepStopsTheProbe() async {
        let runner = Runner()
        let control = control(runner, verdict: nil)
        await control.launch()
        control.macWillSleep()
        #expect(runner.stops == 1)
        runner.finish?(nil)
        #expect(control.message == "Arrêtée : le Mac s'est mis en veille.")
    }

    @Test func aProbeThatReachedItsEndKeepsItsReportEvenWhenAStopWasAsked() async {
        // The meeting began as the probe was writing its report: the report is there, and is shown.
        let runner = Runner()
        let control = control(runner, verdict: true)
        await control.launch()
        control.meetingBegan()
        runner.finish?(nil)
        #expect(control.phase == .done(true))
        #expect(control.message == "Terminé : Claude Code a répondu. Le relevé est enregistré.")
    }

    @Test func aProbeRunsAgainAfterOneThatAMeetingStopped() async {
        let runner = Runner()
        let control = control(runner, verdict: nil)
        await control.launch()
        control.meetingBegan()
        runner.finish?(nil)
        #expect(control.message == Self.meeting)
        // The meeting is over: the next probe goes to its end, and nothing of the first stop is left.
        runner.verdict = true
        await control.launch()
        #expect(control.phase == .running)
        #expect(runner.accounts.count == 2)
        runner.finish?(nil)
        #expect(control.phase == .done(true))
        #expect(control.message == "Terminé : Claude Code a répondu. Le relevé est enregistré.")
        // And a third one, with no report and no stop asked, is not said stopped by a meeting.
        runner.verdict = nil
        await control.launch()
        runner.finish?(nil)
        #expect(control.message == "La sonde s'est arrêtée avant la fin.")
    }

    // MARK: - Right after the Mac starts or wakes

    static let unsettled = "Le Mac vient de démarrer ou de se réveiller : réessaie dans quelques minutes."

    @Test func rightAfterTheMacWakesNothingIsLaunched() async throws {
        let runner = Runner()
        let control = control(runner, settle: .milliseconds(150))
        control.macWoke()
        await control.launch()
        #expect(control.phase == .refused(Self.unsettled))
        #expect(runner.accounts.isEmpty)
        try await Task.sleep(for: .milliseconds(200))
        await control.launch()
        #expect(control.phase == .running)
    }

    @Test func aPolhubOpenedAfterTheMacWokeStillWaits() async {
        // Opened, or updated and relaunched, after the wake: it did not see the wake happen. The system says when.
        let runner = Runner()
        let fresh = control(runner, lastWake: Date().addingTimeInterval(-60))
        await fresh.launch()
        #expect(fresh.phase == .refused(Self.unsettled))
        #expect(runner.accounts.isEmpty)
        // An hour after the wake, or on a Mac that has not slept since it started: it runs.
        let later = control(runner, lastWake: Date().addingTimeInterval(-3_600))
        await later.launch()
        #expect(later.phase == .running)
        let never = control(Runner(), lastWake: nil)
        await never.launch()
        #expect(never.phase == .running)
    }

    @Test func theSystemTellsWhenTheMacLastWoke() {
        // When the Mac has slept since it started, its last wake is in the past, and no older than its uptime.
        guard let wake = ColinProbeControl.systemLastWake() else { return }
        let since = Date().timeIntervalSince(wake)
        #expect(since >= 0)
        #expect(since <= ProcessInfo.processInfo.systemUptime + 60)
    }

    @Test func theDelaysAreTheOnesOfTheDesign() {
        // Five minutes after a start or a wake; a look every three seconds; a second of rest after the end.
        #expect(ColinProbeControl.settling == .seconds(300))
        #expect(ColinProbeControl.watchPace == .seconds(3))
        #expect(ColinProbeControl.rest == .seconds(1))
    }

    @Test func rightAfterTheMacStartsNothingIsLaunched() async {
        let runner = Runner()
        let control = control(runner, uptime: 120)
        await control.launch()
        #expect(control.phase == .refused(Self.unsettled))
        #expect(runner.accounts.isEmpty)
    }

    // MARK: - The account's folder

    @Test func theChosenFolderIsKeptAndShownShort() {
        let defaults = defaults()
        let control = control(Runner(), defaults: defaults)
        #expect(control.accountLabel == "Le compte de Claude Code")
        control.choose("/Users/essai/comptes/second/")
        #expect(defaults.string(forKey: Preferences.Key.colinAccount) == "/Users/essai/comptes/second")
        #expect(control.accountLabel == "comptes/second")
        #expect(self.control(Runner(), defaults: defaults).accountFolder == "/Users/essai/comptes/second")
        control.choose(nil)
        #expect(control.accountLabel == "Le compte de Claude Code")
        #expect((defaults.string(forKey: Preferences.Key.colinAccount) ?? "").isEmpty)
    }

    @Test func theChosenFolderGoesToTheProbe() async {
        let runner = Runner()
        let control = control(runner)
        control.choose("/Users/essai/comptes/second")
        await control.launch()
        #expect(runner.accounts == ["/Users/essai/comptes/second"])
    }

    @Test func claudeCodesOwnFolderChosenByHandIsItsOwnAccount() {
        // Given as a folder, Claude Code's own would name another account (measured on 17/11).
        let defaults = defaults()
        let control = control(Runner(), defaults: defaults)
        control.choose("/Users/essai/.claude/")
        #expect(control.accountFolder.isEmpty)
        #expect(control.accountLabel == "Le compte de Claude Code")
        #expect((defaults.string(forKey: Preferences.Key.colinAccount) ?? "").isEmpty)
    }

    @Test func theUsersOwnFolderAndTheRootAreRefused() async {
        // Claude Code keeps a file of its own in the user's folder: it would pass for an account, and Claude Code
        // would then write everything there.
        let personal = "Choisis le dossier d'un compte Claude, pas ton dossier personnel."
        let defaults = defaults()
        let runner = Runner()
        let control = control(runner, defaults: defaults)
        control.choose("/Users/essai/comptes/second")
        for folder in ["/Users/essai", "/Users/essai/", "/", "/Users/essai/comptes/.."] {
            control.choose(folder)
            #expect(control.phase == .refused(personal), "\(folder)")
            // The folder chosen before stays.
            #expect(control.accountFolder == "/Users/essai/comptes/second", "\(folder)")
        }
        // A folder kept by an older version is refused at the launch too.
        defaults.set("/Users/essai", forKey: Preferences.Key.colinAccount)
        let kept = self.control(runner, defaults: defaults)
        await kept.launch()
        #expect(kept.phase == .refused(personal))
        #expect(runner.accounts.isEmpty)
    }

    @Test func theAccountDoesNotChangeUnderAProbeThatRuns() async {
        let runner = Runner()
        let control = control(runner)
        control.choose("/Users/essai/comptes/second")
        await control.launch()
        control.choose("/Users/essai/comptes/troisieme")
        control.choose(nil)
        #expect(control.accountFolder == "/Users/essai/comptes/second")
        #expect(control.phase == .running)
    }

    @Test func choosingAnAccountClearsWhatWasSaid() async {
        let runner = Runner()
        runner.quiet = false
        let control = control(runner)
        await control.launch()
        #expect(control.message != nil)
        control.choose("/Users/essai/comptes/second")
        #expect(control.phase == .idle)
    }

    @Test func theChecksReadTheRealFolders() async throws {
        // No stand-in here: the control's own checks, on folders that exist.
        let manager = FileManager.default
        let home = manager.temporaryDirectory.appending(path: "sonde-colin-maison-\(UUID().uuidString)", directoryHint: .isDirectory)
        let own = home.appending(path: ".claude", directoryHint: .isDirectory)
        let account = home.appending(path: "comptes/second", directoryHint: .isDirectory)
        let plain = home.appending(path: "documents", directoryHint: .isDirectory)
        for folder in [own, account, plain] { try manager.createDirectory(at: folder, withIntermediateDirectories: true) }
        // As Claude Code does: its own account's file in the user's folder, each other account's in its folder.
        try Data("{}".utf8).write(to: home.appending(path: ".claude.json"))
        try Data("{}".utf8).write(to: account.appending(path: ".claude.json"))
        let link = home.appending(path: "raccourci")
        try manager.createSymbolicLink(at: link, withDestinationURL: own)
        defer { try? manager.removeItem(at: home) }

        let runner = Runner()
        let control = ColinProbeControl(defaults: defaults(), home: home, isQuiet: { true }, start: { account, onFinish in
            runner.accounts.append(account)
            runner.finish = onFinish
            return nil
        }, stop: {}, report: { (ok: true, reason: nil) }, uptime: { 86_400 }, lastWake: { nil }, restAfterFinish: .zero)

        control.choose(home.path(percentEncoded: false))
        #expect(control.phase == .refused("Choisis le dossier d'un compte Claude, pas ton dossier personnel."))
        control.choose(link.path(percentEncoded: false))
        #expect(control.accountFolder.isEmpty)
        // A link to the user's own folder is his folder all the same: at the choice, and for one kept from before.
        let toHome = manager.temporaryDirectory.appending(path: "sonde-colin-lien-\(UUID().uuidString)")
        try manager.createSymbolicLink(at: toHome, withDestinationURL: home)
        defer { try? manager.removeItem(at: toHome) }
        control.choose(toHome.path(percentEncoded: false))
        #expect(control.phase == .refused("Choisis le dossier d'un compte Claude, pas ton dossier personnel."))
        #expect(control.accountFolder.isEmpty)
        let kept = defaults()
        kept.set(toHome.path(percentEncoded: false), forKey: Preferences.Key.colinAccount)
        let old = ColinProbeControl(defaults: kept, home: home, isQuiet: { true }, start: { account, _ in
            runner.accounts.append(account)
            return nil
        }, stop: {}, report: { nil }, uptime: { 86_400 }, lastWake: { nil })
        await old.launch()
        #expect(old.phase == .refused("Choisis le dossier d'un compte Claude, pas ton dossier personnel."))
        #expect(runner.accounts.isEmpty)

        control.choose(plain.path(percentEncoded: false))
        await control.launch()
        #expect(control.phase == .refused("Ce dossier n'est pas celui d'un compte Claude."))

        control.choose(account.path(percentEncoded: false))
        await control.launch()
        #expect(control.phase == .running)
        #expect(runner.accounts.count == 1)
        #expect(runner.accounts.first?.hasSuffix("/comptes/second") == true)
        runner.finish?(nil)

        try manager.removeItem(at: account)
        await control.launch()
        #expect(control.phase == .refused("Ce dossier de compte n'existe plus."))
        #expect(runner.accounts.count == 1)
    }
}
