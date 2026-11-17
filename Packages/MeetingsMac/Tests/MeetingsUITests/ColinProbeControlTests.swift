import Foundation
import PolhubDesign
import Testing
@testable import MeetingsUI

@MainActor @Suite struct ColinProbeControlTests {
    /// What the app's runner of probes would be told.
    final class Runner {
        var accounts: [String] = []
        var finish: (@MainActor (String?) -> Void)?
        var accepts = true
        var stops = 0
        var quiet = true
    }

    func defaults() -> UserDefaults {
        let name = "colin-sonde-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func control(_ runner: Runner, defaults: UserDefaults? = nil, verdict: Bool? = true, exists: Bool = true) -> ColinProbeControl {
        ColinProbeControl(defaults: defaults ?? self.defaults(), isQuiet: { runner.quiet }, start: { account, onFinish in
            guard runner.accepts else { return false }
            runner.accounts.append(account)
            runner.finish = onFinish
            return true
        }, stop: { runner.stops += 1 }, verdict: { verdict }, folderExists: { _ in exists }, watchEvery: .milliseconds(20))
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
