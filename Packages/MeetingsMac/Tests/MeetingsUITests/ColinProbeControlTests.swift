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

    /// What the app's runner of probes would be told.
    @MainActor final class Runner {
        var accounts: [String] = []
        var finish: (@MainActor (String?) -> Void)?
        var accepts = true
        var stops = 0
        var quiet = true
        var gate: Gate?
    }

    func defaults() -> UserDefaults {
        let name = "colin-sonde-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func control(_ runner: Runner, defaults: UserDefaults? = nil, verdict: Bool? = true, reason: String? = nil,
                 exists: Bool = true, isAccount: Bool = true) -> ColinProbeControl {
        ColinProbeControl(defaults: defaults ?? self.defaults(), isQuiet: {
            await runner.gate?.wait()
            return runner.quiet
        }, start: { account, onFinish in
            guard runner.accepts else { return false }
            runner.accounts.append(account)
            runner.finish = onFinish
            return true
        }, stop: { runner.stops += 1 }, report: { verdict.map { (ok: $0, reason: reason) } },
        folderExists: { _ in exists }, isAccount: { _ in isAccount }, watchEvery: .milliseconds(20))
    }

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
            "sans-reponse": "Terminé : Claude Code n'a pas répondu. Le relevé est enregistré.",
            "lancement-impossible": "Terminé : Claude Code n'a pas pu se lancer. Le relevé est enregistré.",
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

    @Test func aRunnerAlreadyBusyIsRefused() async {
        let runner = Runner()
        runner.accepts = false
        let control = control(runner)
        await control.launch()
        #expect(control.phase == .refused("Une autre sonde tourne déjà."))
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

    @Test func aMeetingThatBeginsStopsTheProbe() async throws {
        let runner = Runner()
        let control = control(runner, verdict: nil)
        await control.launch()
        runner.quiet = false
        for _ in 0..<100 where runner.stops == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(runner.stops == 1)
        runner.finish?(nil)
        #expect(control.phase == .done(nil))
        #expect(control.message == "Arrêtée : une réunion commence. Relance la sonde après.")
    }

    @Test func aMeetingToldAtOnceStopsTheProbe() async {
        // The app says it the moment the pop-up shows, without waiting for the next look.
        let runner = Runner()
        let control = control(runner)
        await control.launch()
        control.meetingBegan()
        #expect(runner.stops == 1)
        control.meetingBegan()
        #expect(runner.stops == 1)
        runner.finish?(nil)
        #expect(control.phase == .done(nil))
        #expect(control.message == "Arrêtée : une réunion commence. Relance la sonde après.")
    }

    @Test func aMeetingToldWhenNothingRunsDoesNothing() {
        let runner = Runner()
        let control = control(runner)
        control.meetingBegan()
        #expect(runner.stops == 0)
        #expect(control.phase == .idle)
    }

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
}
