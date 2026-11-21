import Domain
import Foundation
import Testing
@testable import MeetingsUI

/// 20/11 : Réglages › Add-ons. Installer ou désinstaller enregistre le nouvel ensemble, puis relance hub ; jamais pendant
/// une réunion ; les phrases disent ce qui vient avec et ce qui part.
@MainActor @Suite struct AddOnControlTests {
    final class Calls {
        var relaunched = 0
        var prepared: [AddOn] = []
        var cleaned: [AddOn] = []
    }

    func control(_ installed: Set<AddOn>, busy: Bool = false, prepare: String? = nil) throws -> (AddOnControl, AddOnStore, Calls) {
        let store = AddOnStore(defaults: try #require(UserDefaults(suiteName: "addons-\(UUID().uuidString)")))
        store.save(installed)
        let calls = Calls()
        let control = AddOnControl(store: store, isBusy: { busy }, relaunch: { calls.relaunched += 1 },
                                   prepare: { addOn in calls.prepared.append(addOn); return prepare },
                                   cleanUp: { calls.cleaned.append($0) })
        return (control, store, calls)
    }

    @Test func nothingChangesDuringAMeeting() async throws {
        let (control, store, calls) = try control([], busy: true)
        await control.install(.inspiration)
        #expect(store.installed.isEmpty && control.installed.isEmpty)
        #expect(control.problem == AddOnTexts.busy)
        #expect(calls.relaunched == 0)
    }

    @Test func installingSavesThenRelaunches() async throws {
        let (control, store, calls) = try control([])
        await control.install(.colin)
        #expect(store.installed == [.colin, .mails, .calendar])
        #expect(calls.prepared == [.calendar, .mails, .colin] && calls.relaunched == 1)
    }

    /// A model that cannot be downloaded: nothing is installed, and why is said.
    @Test func aFailedPreparationInstallsNothing() async throws {
        let (control, store, calls) = try control([], prepare: "Le téléchargement a échoué.")
        await control.install(.meetings)
        #expect(store.installed.isEmpty && control.problem == "Le téléchargement a échoué." && calls.relaunched == 0)
    }

    @Test func uninstallingTakesTheDependentsAndCleansUp() async throws {
        let (control, store, calls) = try control(Set(AddOn.allCases))
        await control.uninstall(.calendar)
        #expect(store.installed == [.projects, .meetings, .dictation, .inspiration, .vigie, .iphone])
        #expect(calls.cleaned == [.calendar, .mails, .colin] && calls.relaunched == 1)
    }

    /// 21/11 : la Bienvenue installe plusieurs add-ons d'un coup, avec ce qu'il leur faut ; après la relance, le guide
    /// s'ouvre une fois, sur ceux à qui il manque quelque chose.
    @Test func severalAreInstalledAtOnceThenTheGuideOpensOnce() async throws {
        let (control, store, calls) = try control([.projects])
        await control.install([.dictation, .mails], welcome: true)
        #expect(store.installed == [.projects, .dictation, .calendar, .mails] && calls.relaunched == 1)
        #expect(calls.prepared == [.dictation, .calendar, .mails])
        // After the relaunch. No Google account yet: Calendrier and Mails wait; the Dictée has all it needs.
        let after = AddOnControl(store: store, isBusy: { false }, relaunch: {})
        after.openPendingGuide()
        #expect(after.showsGuide && after.guideIsWelcome && after.guide == [.calendar, .mails])
        let again = AddOnControl(store: store, isBusy: { false }, relaunch: {})
        again.openPendingGuide()
        #expect(!again.showsGuide)
    }

    @Test func anAddOnWithAllItNeedsOpensNoGuide() async throws {
        let (control, store, _) = try control([])
        await control.install(.projects)
        let after = AddOnControl(store: store, isBusy: { false }, relaunch: {})
        // No guide, but the window comes back on what was just installed (21/11, Paul: « ça m'a fermé la fenêtre »).
        #expect(after.openPendingGuide() == [.projects] && AddOn.projects.section == .projects)
        #expect(!after.showsGuide)
        // Once only.
        #expect(AddOnControl(store: store, isBusy: { false }, relaunch: {}).openPendingGuide().isEmpty)
    }

    @Test func aButtonThatLeavesThePageClosesTheGuide() throws {
        let (control, _, _) = try control(Set(AddOn.allCases))
        var done: [AddOnAction] = []
        control.perform = { done.append($0) }
        control.showsGuide = true
        control.settle(AddOnNeed("google", "Un compte Google", done: false, action: .connectGoogle, button: "Connecter un compte"))
        #expect(control.showsGuide && done == [.connectGoogle])
        control.settle(AddOnNeed("relie", "Un iPhone relié", done: false, action: .openPhone, button: "Relier un iPhone"))
        #expect(!control.showsGuide && done == [.connectGoogle, .openPhone])
        #expect(control.state(.projects) == .ready && control.state(.calendar) == .missing(1))
    }

    @Test func theConfirmationsSayWhoComesAndGoes() throws {
        let (empty, _, _) = try control([])
        #expect(empty.confirmation(installing: .colin) == "Colin a besoin de Mails et de Calendrier : ils s'installent aussi.")
        #expect(empty.confirmation(installing: .mails) == "Mails a besoin de Calendrier : il s'installe aussi.")
        #expect(empty.confirmation(installing: .projects) == nil)
        let (all, _, _) = try control(Set(AddOn.allCases))
        #expect(all.confirmation(uninstalling: .calendar) == "Désinstaller Calendrier désinstalle aussi Mails et Colin.")
        #expect(all.confirmation(uninstalling: .projects) == nil)
    }

    @Test func eachAddOnSaysWhatItDoesInOneLine() {
        #expect(AddOnTexts.summary(.projects) == "Le kanban et la page de chaque projet")
        #expect(AddOnTexts.summary(.meetings) == "Tes Meet enregistrés, transcrits et résumés")
        for addOn in AddOn.allCases {
            #expect(AddOnTexts.help(addOn).count <= 100, "\(addOn)")
        }
        #expect(AddOnTexts.busy == "Pas pendant une réunion : réessaie quand elle est finie.")
        #expect(AddOnTexts.keepsData == "Ses données restent : le réinstaller le remet comme avant.")
    }
}
