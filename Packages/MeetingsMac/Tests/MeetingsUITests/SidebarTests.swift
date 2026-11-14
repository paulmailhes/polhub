import Foundation
import PolhubDesign
import Testing
@testable import MeetingsUI

/// The sidebar keeps the work (Projets, Réunions); the app's own pages live in Réglages (Paul, 13/11).
@MainActor @Suite struct SidebarTests {
    /// 14/11: Réglages sits at the bottom of the sidebar, apart from the work.
    @Test func theSidebarHasTheWorkAndReglagesApart() {
        #expect(SidebarItem.visible(hasProjects: true, hasAgenda: true) == [.home, .projects, .meetings, .calendar, .contacts])
        #expect(SidebarItem.visible(hasProjects: true, hasAgenda: true).map(\.title) == ["Accueil", "Projets", "Réunions", "Calendrier", "Contacts"])
        #expect(SidebarItem.visible(hasProjects: false, hasAgenda: false) == [.meetings])
        #expect(SidebarItem.settings.title == "Réglages")
    }

    /// 14/11: Réglages opens on its families, as Apple's; each family is entered.
    @Test func reglagesListsItsFamilies() {
        let families = SettingsPane.families(hasAgenda: true, hasProjects: true)
        #expect(families.map { $0.map(\.title) } == [["Calendrier", "Projets", "Réunions"], ["Mises à jour", "Diagnostic", "Journal"]])
        #expect(SettingsPane.families(hasAgenda: false, hasProjects: false).map { $0.map(\.title) } == [["Réunions"], ["Mises à jour", "Diagnostic", "Journal"]])
    }

    @Test func openingTheDiagnosticEntersItsFamily() {
        let router = WindowRouter()
        router.openDiagnostic()
        #expect(router.section == .settings && router.settingsPane == .diagnostic)
        router.openSettings(.calendar)
        #expect(router.section == .settings && router.settingsPane == .calendar)
    }

    /// The settings and their defaults: one place for every module (14/11).
    @Test func settingsHaveSensibleDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "réglages-\(UUID().uuidString)"))
        let settings = Preferences(defaults: defaults)
        #expect(settings.cardSize == .medium && settings.eventMinutes == 60 && settings.eventMeet && settings.showWeekend)
        #expect(settings.dayStartHour == 8 && settings.summariesEnabled && settings.transcriptionLanguage == "fr" && settings.defaultAccount == nil)
        defaults.set("small", forKey: Preferences.Key.cardSize)
        defaults.set("auto", forKey: Preferences.Key.transcriptionLanguage)
        #expect(settings.cardSize == .small && settings.transcriptionLanguage == nil)
        #expect(CardSize.small.columnWidth < CardSize.medium.columnWidth && CardSize.medium.columnWidth < CardSize.large.columnWidth)
        #expect(CardSize.large.columnWidth == 300 && CardSize.medium.columnWidth < 300)
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
