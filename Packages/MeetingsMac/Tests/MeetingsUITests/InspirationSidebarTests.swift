import AppKit
import Agenda
import Foundation
import Persistence
import PolhubDesign
import SwiftUI
import Testing
@testable import MeetingsUI

/// « Inspiration » in the window (16/11): its place in the sidebar, after Contacts, open on its three pages as Mails
/// on its folders; its family in Réglages; the router's places, for what opens a page or an item from outside.
@MainActor @Suite struct InspirationSidebarTests {
    @Test func inspirationComesAfterContacts() {
        #expect(SidebarItem.visible(hasProjects: true, hasAgenda: true, hasMails: true, hasInspiration: true)
                == [.home, .projects, .meetings, .calendar, .mails, .contacts, .inspiration])
        #expect(SidebarItem.visible(hasProjects: true, hasAgenda: true) == [.home, .projects, .meetings, .calendar, .contacts])
        #expect(SidebarItem.inspiration.title == "Inspiration")
        #expect(SidebarItem.inspiration.appIcon == .inspiration)
        // ⌘1 to ⌘6 stay the pages they were.
        #expect(PanelModel.pages == [.home, .projects, .meetings, .calendar, .mails, .contacts])
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

    /// The page shown is lit when « Inspiration » is open, « Inspiration » itself when closed.
    @Test func theSidebarLightsThePageShown() {
        #expect(SidebarRow.selected(section: .inspiration, folder: .inbox, mailsOpen: true, page: .branding, inspirationOpen: true) == .inspiration(.branding))
        #expect(SidebarRow.selected(section: .inspiration, folder: .inbox, mailsOpen: true, page: .branding, inspirationOpen: false) == .section(.inspiration))
        #expect(SidebarRow.selected(section: .mails, folder: .sent, mailsOpen: true, page: .branding, inspirationOpen: true) == .mail(.sent))
        #expect(SidebarRow.selected(section: .settings, folder: nil, mailsOpen: true, page: .mockup) == nil)
    }

    /// Réglages › Inspiration: a family of its own, after Réunions, with Paul's tools.
    @Test func reglagesHasAnInspirationFamily() {
        let families = SettingsPane.families(hasAgenda: true, hasProjects: true, hasMails: true, hasInspiration: true)
        #expect(families[1] == [.accounts, .calendar, .mails, .projects, .meetings, .inspiration])
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

    /// Réglages lines up with the rows above when « Inspiration » is the only group that opens.
    @Test func reglagesLinesUpWithInspirationOpen() async throws {
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
        let starts = SidebarAlignmentTests.rowStarts(in: host)
        let work = try #require(starts.first?.first)
        #expect(starts.count == 1)
        // The pages under it come after « Inspiration », in the list.
        #expect((starts.first?.count ?? 0) >= 7)
        let footer = SidebarFooterMetrics.listInset + SidebarFooterMetrics.rowPadding + SidebarFooterMetrics.outlineIndent
        #expect(footer - work == 4)
    }
}
