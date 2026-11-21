import Foundation
import Persistence
import HubDesign
import Testing
@testable import MeetingsUI

/// The sidebar keeps the work (Projets, Réunions); the app's own pages live in Réglages (Paul, 13/11).
@MainActor @Suite struct SidebarTests {
    /// 14/11: Réglages sits at the bottom of the sidebar, apart from the work; Contacts with it (lot 4, 19/11).
    @Test func theSidebarHasTheWorkAndReglagesApart() {
        #expect(SidebarItem.visible(hasProjects: true, hasAgenda: true) == [.home, .projects, .meetings, .calendar])
        #expect(SidebarItem.visible(hasProjects: true, hasAgenda: true).map(\.title) == ["Accueil", "Projets", "Réunions", "Calendrier"])
        #expect(SidebarItem.footer(hasAgenda: true).map(\.title) == ["Contacts", "Réglages"])
        #expect(SidebarItem.visible(hasProjects: false, hasAgenda: false) == [.meetings])
        #expect(SidebarItem.settings.title == "Réglages")
    }

    /// 15/11: a color and a symbol per section, as Mail's and the Finder's; the color of its family in Réglages.
    @Test func eachSectionHasItsColorAndItsSymbol() {
        let all: [SidebarItem] = [.home, .projects, .meetings, .calendar, .mails, .contacts, .settings]
        #expect(Set(all.map(\.tint)).count == all.count)
        #expect(Set(all.map(\.icon)).count == all.count)
        #expect(SidebarItem.calendar.tint == SettingsPane.calendar.tint && SidebarItem.mails.tint == SettingsPane.mails.tint)
        #expect(SidebarItem.projects.tint == SettingsPane.projects.tint && SidebarItem.meetings.tint == SettingsPane.meetings.tint)
        #expect(SidebarItem.settings.tint == SettingsPane.general.tint)
        #expect(SidebarItem.home.tint == Palette.teal && SidebarItem.contacts.tint == Palette.green)
    }

    /// The row lit: the folder under « Mails » open, « Mails » when closed, none above Réglages (which has its
    /// own row at the bottom).
    @Test func theSidebarLightsTheRightRow() {
        #expect(SidebarRow.selected(section: .mails, folder: .sent, mailsOpen: true) == .mail(.sent))
        #expect(SidebarRow.selected(section: .mails, folder: .sent, mailsOpen: false) == .section(.mails))
        #expect(SidebarRow.selected(section: .mails, folder: nil, mailsOpen: true) == .section(.mails))
        #expect(SidebarRow.selected(section: .calendar, folder: .inbox, mailsOpen: true) == .section(.calendar))
        #expect(SidebarRow.selected(section: .settings, folder: .inbox, mailsOpen: true) == nil)
    }

    /// Calendrier counts what is left of the day: the event under way and those to come, neither whole days,
    /// nor declined ones, nor tomorrow's.
    @Test func calendrierCountsTheEventsLeftToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 10, minute: 0)))
        func event(_ id: String, _ startMinutes: Double, _ minutes: Double = 30, allDay: Bool = false, declined: Bool = false) -> CalendarEventRow {
            CalendarEventRow(account: "moi@exemple.fr", eventID: id, title: id, startAt: now.addingTimeInterval(startMinutes * 60),
                             endAt: now.addingTimeInterval((startMinutes + minutes) * 60), allDay: allDay,
                             attendees: [Attendee(email: "moi@exemple.fr", response: declined ? "declined" : "accepted", isSelf: true)], updatedAt: now)
        }
        let events = [event("fini", -90), event("en-cours", -10), event("plus-tard", 120), event("ce-soir", 600),
                      event("journee", -600, 24 * 60, allDay: true), event("refuse", 60, declined: true), event("demain", 24 * 60)]
        #expect(SidebarCounts.eventsLeftToday(events, now: now, calendar: calendar) == 3)
        #expect(SidebarCounts.eventsLeftToday([], now: now, calendar: calendar) == 0)
    }

    /// « Nouveau mail » twice: the blank mail of the first click goes, a single new one stays open, over Mails.
    @Test func nouveauMailNeverLeavesAnEmptyDraftBehind() async throws {
        let database = try AppDatabase.inMemory()
        let calendar = CalendarStore(database)
        try calendar.addAccount(email: "moi@exemple.fr", at: Date())
        try calendar.setGrantedScopes(email: "moi@exemple.fr",
                                      scopes: "openid https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/gmail.modify")
        let root = FileManager.default.temporaryDirectory.appending(path: "nouveau-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let agenda = AgendaLibrary(database: database)
        let mails = MailLibrary(agenda: agenda, root: root, defaults: try #require(UserDefaults(suiteName: "nouveau-\(UUID().uuidString)")), flavor: .dev)
        let router = WindowRouter()
        router.section = .projects
        try await waitUntil { !mails.accounts.isEmpty }

        mails.writeNewMail(router: router)
        let first = try #require(mails.composing)
        #expect(router.section == .mails)
        mails.writeNewMail(router: router)
        let second = try #require(mails.composing)
        #expect(first != second)
        let store = MailStore(database)
        try await waitUntil { (try? store.draft(first)) == nil }
        #expect(try store.draft(second) != nil)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
        #expect(condition())
    }

    /// 18/11: Réglages › Colin, only with the mails: what Colin signals comes from them. First since lot 7 (19/11): the
    /// families follow the sidebar, and Colin's is the Accueil's.
    @Test func reglagesHasAColinFamilyWithTheMails() {
        let families = SettingsPane.families(hasAgenda: true, hasProjects: true, hasMails: true)
        #expect(families[1] == [.colin, .projects, .meetings, .calendar, .mails, .iphone])
        #expect(SettingsPane.colin.title == "Colin")
        #expect(SettingsPane.colin.subtitle == "Marche, ce qu'il sait, ce qu'il signale")
        #expect(SettingsPane.colin.icon == "sparkles")
        #expect(!SettingsPane.families(hasAgenda: true, hasProjects: true).flatMap { $0 }.contains(.colin))
        // No two families of one group share their color: Paul finds them by it.
        for group in SettingsPane.families(hasAgenda: true, hasProjects: true, hasMails: true, hasInspiration: true) {
            #expect(Set(group.map(\.tint)).count == group.count)
        }
    }

    /// 14/11: Réglages opens on its families, as Apple's; each family is entered. Lot 7 (19/11): in the sidebar's order,
    /// then the whole app's; Diagnostic and Journal are lines of Général.
    @Test func reglagesListsItsFamilies() {
        let families = SettingsPane.families(hasAgenda: true, hasProjects: true)
        #expect(families.map { $0.map(\.title) } == [["Add-ons"], ["Projets", "Réunions", "Calendrier", "iPhone"], ["Comptes Google", "Diagnostic", "Général"]])
        #expect(SettingsPane.families(hasAgenda: false, hasProjects: false).map { $0.map(\.title) } == [["Add-ons"], ["Réunions", "iPhone"], ["Diagnostic", "Général"]])
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
    }

    /// Réglages › Projets (15/11): two sizes of cards, the old « large » reads as normal; the logos asked of
    /// the clients' sites, on by default.
    @Test func projectSettingsHaveSensibleDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "projets-\(UUID().uuidString)"))
        let settings = Preferences(defaults: defaults)
        #expect(settings.cardSize == .medium && settings.projectLogos)
        #expect(CardSize.allCases.map(\.title) == ["Normales", "Compactes"])
        #expect(CardSize.allCases.map(\.rawValue) == ["medium", "small"])
        #expect(CardSize.small.columnWidth < CardSize.medium.columnWidth && CardSize.small.isCompact && !CardSize.medium.isCompact)
        defaults.set("large", forKey: Preferences.Key.cardSize)
        #expect(settings.cardSize == .medium && CardSize(stored: "large") == .medium && CardSize(stored: nil) == .medium)
        defaults.set(false, forKey: Preferences.Key.projectLogos)
        #expect(!settings.projectLogos && Preferences.Key.projectLogos == "projets.logosEnLigne")
    }

    /// 14/11: notifications on by default, reminders ten minutes and one minute before.
    @Test func notificationSettingsHaveSensibleDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "notifications-\(UUID().uuidString)"))
        let settings = Preferences(defaults: defaults)
        #expect(settings.reminders && settings.reminderMinutes == [10, 1] && !settings.remindersMeetOnly)
        #expect(settings.newEvents && settings.unrecorded && settings.summaryReady && settings.sound)
        defaults.set("1, 30,x,10,10", forKey: Preferences.Key.reminderMinutes)
        #expect(settings.reminderMinutes == [30, 10, 1])
        #expect(Preferences.minutesText([1, 15]) == "15,1")
        #expect(SettingsPane.families(hasAgenda: true, hasProjects: true).last?.last == .general)
        #expect(!SettingsPane.allCases.map(\.rawValue).contains("notifications"))
    }

    /// 15/11, « comme Gmail »: the list's density, the days, the undo delay and what follows a gesture, in
    /// Réglages › Mails.
    @Test func mailSettingsHaveGmailsDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "mails-\(UUID().uuidString)"))
        let settings = Preferences(defaults: defaults)
        #expect(settings.mailDensity == .defaut && settings.mailDensity.showsFiles && !MailDensity.compacte.showsFiles)
        #expect(!settings.mailDays && settings.mailUndoSeconds == 10 && settings.mailAfterGesture == .suivant)
        defaults.set(30, forKey: Preferences.Key.mailUndoSeconds)
        defaults.set("liste", forKey: Preferences.Key.mailAfterGesture)
        #expect(settings.mailUndoSeconds == 30 && settings.mailAfterGesture == .liste)
        defaults.set(3, forKey: Preferences.Key.mailUndoSeconds)
        #expect(settings.mailUndoSeconds == 10)
        #expect(MailDensity.compacte.padding < MailDensity.defaut.padding)
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

    /// Audit of 19/11: a week past what hub reads of the agendas says so, as the agents are told (`AgendaDesk.gaps`): an
    /// empty week there is not a free one.
    @Test func aWeekPastTheCopySaysSo() throws {
        let read = Date(timeIntervalSince1970: 1_794_562_920)
        let accounts = [GoogleAccountRow(email: "moi@exemple.fr", addedAt: read, lastSyncAt: read)]
        let thisWeek = CalendarView.monday(of: read)
        let inTenWeeks = try #require(CalendarView.calendar.date(byAdding: .day, value: 70, to: thisWeek))
        #expect(CalendarView.copyNotice(weekStart: thisWeek, days: 7, accounts: accounts) == nil)
        let notice = try #require(CalendarView.copyNotice(weekStart: inTenWeeks, days: 7, accounts: accounts))
        #expect(notice.contains("Google Agenda"))
    }

    /// The week's lines (19/11): one device pixel wide, on a pixel, whatever the window's width. Half a point between
    /// two pixels faded away on a screen that is not Retina, the more as the window widened.
    @Test func gridLinesSitOnAPixel() {
        #expect(PixelGrid.line(at: 137.14, scale: 1) == 137.5)
        #expect(PixelGrid.line(at: 137.14, scale: 2) == 137.25)
        #expect(PixelGrid.line(at: 48, scale: 1) == 48.5)
        #expect(PixelGrid.line(at: 0, scale: 2) == 0.25)
        // A seventh of a width that does not divide: every line still falls on a pixel's middle.
        for day in 1..<7 {
            let x = PixelGrid.line(at: 1_017 * CGFloat(day) / 7, scale: 1)
            #expect(x - x.rounded(.down) == 0.5)
        }
    }
}
