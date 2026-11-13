import Testing
@testable import MeetingsUI

/// The sidebar keeps the work (Projets, Réunions); the app's own pages live in Réglages (Paul, 13/11).
@MainActor @Suite struct SidebarTests {
    @Test func theSidebarKeepsProjectsMeetingsAndSettings() {
        #expect(SidebarItem.visible(hasProjects: true) == [.projects, .meetings, .settings])
        #expect(SidebarItem.visible(hasProjects: true).map(\.title) == ["Projets", "Réunions", "Réglages"])
        #expect(SidebarItem.visible(hasProjects: false) == [.meetings, .settings])
    }

    @Test func diagnosticAndJournalLiveInSettings() {
        #expect(SettingsTab.visible(hasProjects: true).map(\.title) == ["Mises à jour", "Diagnostic", "Journal", "Projets"])
        #expect(SettingsTab.visible(hasProjects: false) == [.updates, .diagnostic, .journal])
    }

    @Test func openingTheDiagnosticShowsItsTabInSettings() {
        let router = WindowRouter()
        router.openDiagnostic()
        #expect(router.section == .settings)
        #expect(router.settingsTab == .diagnostic)
    }
}
