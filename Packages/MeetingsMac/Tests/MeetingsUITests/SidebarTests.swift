import Foundation
import Testing
@testable import MeetingsUI

/// The sidebar keeps the work (Projets, Réunions); the app's own pages live in Réglages (Paul, 13/11).
@MainActor @Suite struct SidebarTests {
    @Test func theSidebarHasTheWorkThenReglages() {
        #expect(SidebarItem.visible(hasProjects: true, hasAgenda: true) == [.home, .projects, .meetings, .calendar, .contacts, .settings])
        #expect(SidebarItem.visible(hasProjects: true, hasAgenda: true).map(\.title)
            == ["Accueil", "Projets", "Réunions", "Calendrier", "Contacts", "Réglages"])
        #expect(SidebarItem.visible(hasProjects: false, hasAgenda: false) == [.meetings, .settings])
    }

    @Test func diagnosticAndJournalLiveInSettings() {
        // 14/11: the vault's import left with Obsidian, and its tab with it.
        #expect(SettingsTab.visible(hasProjects: true).map(\.title) == ["Mises à jour", "Diagnostic", "Journal"])
        #expect(SettingsTab.visible(hasProjects: false) == [.updates, .diagnostic, .journal])
    }

    @Test func openingTheDiagnosticShowsItsTabInSettings() {
        let router = WindowRouter()
        router.openDiagnostic()
        #expect(router.section == .settings)
        #expect(router.settingsTab == .diagnostic)
    }

    /// Events of a day that overlap share the column's width (13/11).
    @Test func overlappingEventsSitSideBySide() {
        let day = Date(timeIntervalSince1970: 1_794_562_920)
        func at(_ hour: Double, _ minutes: Double) -> (start: Date, end: Date) {
            (day.addingTimeInterval(hour * 3_600), day.addingTimeInterval(hour * 3_600 + minutes * 60))
        }
        let slots = DayLayout.place([at(0, 60), at(0.5, 60), at(2, 30), at(1, 30)])
        #expect(slots.map(\.column) == [0, 1, 0, 0])
        #expect(slots.map(\.columns) == [2, 2, 1, 2])
    }
}
