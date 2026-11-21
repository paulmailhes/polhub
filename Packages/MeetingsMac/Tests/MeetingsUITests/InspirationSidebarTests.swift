import AppKit
import Agenda
import Foundation
import Persistence
import HubDesign
import SwiftUI
import Testing
@testable import MeetingsUI

/// « Inspiration » in the window (16/11): its place in the sidebar, after Mails, on one row (lot 4, 19/11: its three pages
/// in its toolbar); its family in Réglages; the router's places, for what opens a page or an item from outside.
@MainActor @Suite struct InspirationSidebarTests {
    /// Lot 4, 19/11: after Mails, Contacts gone down to Réglages; ⌘6 is Inspiration, ⌘7 Contacts.
    @Test func inspirationComesAfterMails() {
        #expect(SidebarItem.visible(hasProjects: true, hasAgenda: true, hasMails: true, hasInspiration: true)
                == [.home, .projects, .meetings, .calendar, .mails, .inspiration])
        #expect(SidebarItem.visible(hasProjects: true, hasAgenda: true) == [.home, .projects, .meetings, .calendar])
        #expect(SidebarItem.inspiration.title == "Inspiration")
        #expect(SidebarItem.inspiration.appIcon == .inspiration)
        #expect(PanelModel.pages == [.home, .projects, .meetings, .calendar, .mails, .inspiration, .contacts])
    }

    /// Its own color, the same in the sidebar and in Réglages, and its own icon.
    @Test func inspirationHasItsColorAndItsIcon() {
        let all: [SidebarItem] = [.home, .projects, .meetings, .calendar, .mails, .contacts, .inspiration, .settings]
        #expect(Set(all.map(\.tint)).count == all.count)
        #expect(Set(all.map(\.icon)).count == all.count)
        #expect(Set(all.map(\.appIcon)).count == all.count)
        #expect(SidebarItem.inspiration.tint == SettingsPane.inspiration.tint)
        #expect(SidebarItem.inspiration.tint == Palette.yellow)
    }

    /// « Inspiration » is lit whatever its page (lot 4, 19/11: the pages are in its toolbar).
    @Test func theSidebarLightsInspiration() {
        #expect(SidebarRow.selected(section: .inspiration, folder: .inbox, mailsOpen: true) == .section(.inspiration))
        #expect(SidebarRow.selected(section: .mails, folder: .sent, mailsOpen: true) == .mail(.sent))
        #expect(SidebarRow.selected(section: .settings, folder: nil, mailsOpen: true) == nil)
    }

    /// Réglages › Inspiration: a family of its own, after Mails, as in the sidebar (lot 7, 19/11).
    @Test func reglagesHasAnInspirationFamily() {
        let families = SettingsPane.families(hasAgenda: true, hasProjects: true, hasMails: true, hasInspiration: true)
        #expect(families[1] == [.colin, .projects, .meetings, .calendar, .mails, .inspiration, .iphone])
        #expect(SettingsPane.inspiration.title == "Inspiration")
        #expect(!SettingsPane.families(hasAgenda: true, hasProjects: true).flatMap { $0 }.contains(.inspiration))
    }

    /// A page, or an item on its page, from outside (a notification, later): the router goes there.
    @Test func theRouterOpensAPageOrAnItem() {
        let router = WindowRouter()
        let id = UUID()
        router.go(to: .inspiration(.branding, item: id))
        #expect(router.section == .inspiration && router.inspirationPage == .branding && router.inspirationItem == id)
        router.go(to: .inspiration(.mockup))
        #expect(router.inspirationPage == .mockup && router.inspirationItem == nil)
        router.go(to: .settings(.inspiration))
        #expect(router.section == .settings && router.settingsPane == .inspiration)
    }

    /// « Inspiration » on one row and no group that opens (lot 4, 19/11); no system list in the sidebar to light in the
    /// accent color (21/11).
    @Test func inspirationIsOneRowOfTheSidebar() async throws {
        let world = try InspirationTestWorld(name: "alignement-inspiration")
        defer { world.clean() }
        let database = try AppDatabase.inMemory()
        let agenda = AgendaLibrary(database: database)
        let inspiration = world.library()
        let library = MeetingLibrary(store: MeetingStore(database))
        let host = NSHostingView(rootView: MainWindowView(library: library, agenda: agenda, inspiration: inspiration, router: WindowRouter(),
                                                         paths: world.paths) { EmptyView() })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_100, height: 800), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        window.layoutIfNeeded()
        #expect(SidebarAlignmentTests.tables(in: host).filter { $0.minX < 200 }.isEmpty)
        // Accueil, Réunions, Calendrier, Inspiration: one row each.
        #expect(SidebarItem.visible(hasProjects: false, hasAgenda: true, hasInspiration: true) == [.home, .meetings, .calendar, .inspiration])
    }
}
