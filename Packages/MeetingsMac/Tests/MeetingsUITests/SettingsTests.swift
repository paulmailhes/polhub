import Foundation
import Persistence
import PolhubDesign
import Testing
@testable import MeetingsUI

/// Réglages, lot 7 of the plan of 19/11: the families in the sidebar's order, Diagnostic and Journal as lines of Général,
/// one line of help per setting (the detail behind « ⓘ »), one width, the reminders in a menu, and the guards of Général
/// for the Diagnostic's relaunch.
@MainActor @Suite struct SettingsTests {
    // MARK: - The families

    /// The families follow the sidebar, from the top (Colin is the Accueil's), then the whole app's: Comptes Google,
    /// Notifications, Mises à jour, Général.
    @Test func theFamiliesFollowTheSidebar() {
        let all = SettingsPane.families(hasAgenda: true, hasProjects: true, hasMails: true, hasInspiration: true)
        #expect(all == [[.colin, .projects, .meetings, .calendar, .mails, .inspiration], [.accounts, .iphone, .notifications, .updates, .general]])
        #expect(all[0].map(\.section) == SidebarItem.visible(hasProjects: true, hasAgenda: true, hasMails: true, hasInspiration: true))
        #expect(SettingsPane.families(hasAgenda: true, hasProjects: true)
            == [[.projects, .meetings, .calendar], [.accounts, .iphone, .notifications, .updates, .general]])
        #expect(SettingsPane.families(hasAgenda: false, hasProjects: false) == [[.meetings], [.iphone, .notifications, .updates, .general]])
        // Paul finds a family by its color: none shared within a group.
        for group in all { #expect(Set(group.map(\.tint)).count == group.count) }
    }

    /// Diagnostic and Journal are no families any more: two lines of Général, which says so.
    @Test func diagnosticAndJournalAreLinesOfGeneral() {
        let all = SettingsPane.families(hasAgenda: true, hasProjects: true, hasMails: true, hasInspiration: true).flatMap { $0 }
        #expect(!all.contains(.diagnostic) && !all.contains(.journal))
        #expect(SettingsPane.general.lines == [.diagnostic, .journal])
        #expect(SettingsPane.diagnostic.parent == .general && SettingsPane.journal.parent == .general)
        #expect(SettingsPane.allCases.filter { $0.parent != nil } == [.diagnostic, .journal])
        #expect(SettingsPane.general.subtitle.contains("diagnostic") && SettingsPane.general.subtitle.contains("journal"))
    }

    /// The ‹ of a line of Général goes back where it was opened from: Général, the page that asked for the Diagnostic,
    /// or, opened first thing (the first launch), Général.
    @Test func aLineOfGeneralClosesBackToGeneral() {
        let router = WindowRouter()
        router.openSettings(nil)
        router.settle()
        router.clearHistory()
        router.settingsPane = .general
        router.settle()
        router.settingsPane = .diagnostic
        router.settle()
        router.closeSettings()
        #expect(router.section == .settings && router.settingsPane == .general)
        router.settingsPane = .journal
        router.settle()
        router.closeSettings()
        #expect(router.section == .settings && router.settingsPane == .general)
        // A family closes back on the families, as before.
        router.closeSettings()
        #expect(router.section == .settings && router.settingsPane == nil)
        // The Diagnostic asked from another page (Coup d'œil's « Diagnostic… », an alert): back there.
        router.section = .projects
        router.settle()
        router.openDiagnostic()
        router.settle()
        router.closeSettings()
        #expect(router.section == .projects)

        let launch = WindowRouter()
        launch.openDiagnostic()
        launch.settle()
        launch.clearHistory()
        launch.closeSettings()
        #expect(launch.section == .settings && launch.settingsPane == .general)
    }

    // MARK: - The reminders, in a menu

    @Test func theRemindersAreAMenu() {
        #expect(ReminderMenu.title([10]) == "Rappel : 10 min avant")
        #expect(ReminderMenu.title([10, 1]) == "Rappels : 10 et 1 min avant")
        #expect(ReminderMenu.title([1, 30, 10]) == "Rappels : 30, 10 et 1 min avant")
        #expect(ReminderMenu.title([]) == "Rappel : aucun")
        // The row's word on the left, the menu's on the right, as the pickers of the page.
        #expect(ReminderMenu.label([10]) == "Rappel" && ReminderMenu.label([10, 1]) == "Rappels")
        #expect(ReminderMenu.value([1, 10]) == "10 et 1 min avant" && ReminderMenu.value([]) == "aucun")
        #expect(ReminderMenu.choices == Preferences.Default.reminderChoices)
        #expect(ReminderMenu.item(15) == "15 min avant")
        // Each choice of the menu is ticked or not, several at once.
        #expect(ReminderMenu.toggled("10,1", 1) == "10")
        #expect(ReminderMenu.toggled("10", 30) == "30,10")
        #expect(ReminderMenu.toggled("", 5) == "5")
    }

    // MARK: - The words

    /// One line of help per setting, never more than two on screen: the long detail goes behind « ⓘ ».
    @Test func everyHelpHoldsInTwoLines() {
        let helps = SettingsText.helps + ColinSettingsText.helps + MailSettingsText.helps + InspirationSettingsText.helps
        #expect(helps.count >= 20)
        for help in helps {
            #expect(help.count <= SettingHelp.longest, "\(help.count) caractères : « \(help) »")
            #expect(!help.contains("\n"))
        }
        // The details keep what the long footers said.
        #expect(ColinSettingsText.footer.contains("Jamais l'audio") && ColinSettingsText.kanban.contains("Annuler"))
        #expect(MailSettingsText.imagesDetail.contains("adresse IP"))
    }

    /// Security audit of 19/11, M6 and M8: what leaves the Mac, and what is no barrier, said where it is chosen.
    @Test func reglagesSaysWhatLeavesTheMacAndWhatIsNoBarrier() {
        // M6: « Les mails de tes projets » is a preference; a session with a terminal can change it.
        #expect(MailSettingsText.agentsHelp.contains("préférence, pas une barrière"))
        #expect(MailSettingsText.agentsHelp.contains("terminal"))
        // M8: Colin sends what he reads to Anthropic, to answer.
        #expect(ColinSettingsText.help.contains("Anthropic"))
        for read in ["mails", "transcriptions", "agenda"] { #expect(ColinSettingsText.help.contains(read)) }
    }

    /// No « onglet » left: Mails has folders (« Boîte de réception », « Notifications »).
    @Test func noTabLeftInReglages() {
        let words = SettingsText.helps + SettingsText.details + [SettingsText.mailNotices] + MailSettingsText.helps
            + MailSortingSections.steps + [MailSettingsText.rules]
        for text in words {
            #expect(!text.contains("onglet") && !text.contains("Personnes"), "« \(text) »")
        }
        #expect(SettingsText.mailNotices == "Nouveau mail dans la Boîte de réception")
        #expect(MailSortingSections.place(.personnes) == "la Boîte de réception" && MailSortingSections.place(.notifications) == "Automatiques")
    }

    // MARK: - The guards of Général, for the Diagnostic's relaunch too

    /// Turning the relaunch off or on waits for the end of a meeting, and asks first: the switch of Général and the one
    /// of the Diagnostic go through the same `StartupControl`.
    @Test func theRelaunchWaitsAndAsksWhereverItIsSwitched() {
        let written = Written()
        let busy = StartupControl(read: { true }, write: { written.values.append($0); return nil }, busy: { true })
        #expect(busy.ask(false) == .wait && busy.ask(true) == .wait)
        #expect(written.values.isEmpty && busy.message != nil)

        let quiet = StartupControl(read: { true }, write: { written.values.append($0); return nil })
        #expect(quiet.ask(false) == .confirmOff)
        #expect(written.values.isEmpty)
        let handing = StartupControl(read: { false }, write: { written.values.append($0); return nil }, handsOver: true)
        #expect(handing.ask(true) == .confirmOn)
        #expect(written.values.isEmpty)
        let plain = StartupControl(read: { false }, write: { written.values.append($0); return nil })
        #expect(plain.ask(true) == .done && written.values == [true])
    }

    // MARK: - One width

    /// Every page of Réglages takes the one width (640), its families' list included: no width written by hand.
    @Test func everyPageHasTheOneWidth() throws {
        #expect(SettingsMetrics.width == 640)
        let files = ["MeetingsUI/SettingsView.swift", "MeetingsUI/AccountsSettings.swift", "MeetingsUI/CalendarSettings.swift",
                     "MeetingsUI/ColinSettings.swift", "MeetingsUI/MailSettings.swift", "MeetingsUI/DiagnosticView.swift",
                     "MeetingsUI/Inspiration/InspirationSettings.swift", "ProjectsUI/ProjectsSettings.swift"]
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources")
        let pattern = try NSRegularExpression(pattern: #"maxWidth:\s*[0-9]"#)
        for file in files {
            let text = try String(contentsOf: sources.appending(path: file), encoding: .utf8)
            let found = pattern.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            #expect(found == 0, "\(file) : \(found) largeur(s) écrite(s) à la main")
        }
    }
}

private final class Written {
    var values: [Bool] = []
}
