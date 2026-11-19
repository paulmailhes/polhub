import AppKit
import Agenda
import Domain
import Foundation
import Persistence
import PolhubDesign
import ProjectsUI
import SwiftUI
import Testing
import WebKit
@testable import MeetingsUI

/// The navigation (lot 4, 19/11): a short sidebar, « Fermer » that goes back where Paul came from, the window's keys,
/// the titles and the links between objects. Every person and project here is made up.
@MainActor @Suite struct NavigationTests {
    // MARK: - The sidebar

    /// The work, then Contacts and Réglages apart at the bottom; Inspiration on one row, after Mails.
    @Test func theSidebarListsTheWorkThenContactsAndReglages() {
        #expect(SidebarItem.visible(hasProjects: true, hasAgenda: true, hasMails: true, hasInspiration: true)
                == [.home, .projects, .meetings, .calendar, .mails, .inspiration])
        #expect(SidebarItem.footer(hasAgenda: true) == [.contacts, .settings])
        #expect(SidebarItem.footer(hasAgenda: false) == [.settings])
        #expect(SidebarItem.visible(hasProjects: false, hasAgenda: false) == [.meetings])
    }

    /// ⌘1 to ⌘7 follow the sidebar from top to bottom, Réglages apart (⌘,): the same in the window and in Coup d'œil,
    /// computed from the sidebar's list, never written by hand.
    @Test func theNumbersFollowTheSidebar() {
        let all = SidebarItem.numbered(hasProjects: true, hasAgenda: true, hasMails: true, hasInspiration: true)
        #expect(all == [.home, .projects, .meetings, .calendar, .mails, .inspiration, .contacts])
        #expect(PanelModel.pages == all)
        #expect(SidebarItem.home.shortcut == 1 && SidebarItem.calendar.shortcut == 4 && SidebarItem.mails.shortcut == 5)
        #expect(SidebarItem.inspiration.shortcut == 6 && SidebarItem.contacts.shortcut == 7 && SidebarItem.settings.shortcut == nil)
        #expect(SidebarItem.numbered(hasProjects: false, hasAgenda: false) == [.meetings])
    }

    /// Under Mails: Boîte de réception, Brouillons, Envoyés, then « Plus » and the six others; Programmés only while a
    /// mail waits there, as before.
    @Test func mailsShowsThreeFoldersThenPlus() {
        #expect(MailFolder.sidebar == [.inbox, .drafts, .sent])
        #expect(MailFolder.more == [.notifications, .subscriptions, .scheduled, .spam, .trash, .all])
        #expect(Set(MailFolder.sidebar + MailFolder.more) == Set(MailFolder.allCases))
        #expect(MailFolder.more(showingScheduled: false) == [.notifications, .subscriptions, .spam, .trash, .all])
        #expect(MailFolder.spam.isMore && !MailFolder.drafts.isMore)
    }

    /// « Plus » unfolds by itself on the folder shown: the folder open is always in sight.
    @Test func plusOpensOnTheFolderShown() {
        #expect(SidebarRow.moreOpen(stored: false, section: .mails, folder: .spam))
        #expect(!SidebarRow.moreOpen(stored: false, section: .mails, folder: .inbox))
        #expect(SidebarRow.moreOpen(stored: true, section: .mails, folder: .inbox))
        #expect(!SidebarRow.moreOpen(stored: false, section: .projects, folder: .spam))
    }

    /// Contacts and Réglages live at the bottom, apart from the list: no row of the list is lit for them. Inspiration
    /// is one row, whatever its page.
    @Test func theListLightsNoRowForTheBottom() {
        #expect(SidebarRow.selected(section: .contacts, folder: .inbox, mailsOpen: true) == nil)
        #expect(SidebarRow.selected(section: .settings, folder: .inbox, mailsOpen: true) == nil)
        #expect(SidebarRow.selected(section: .inspiration, folder: .inbox, mailsOpen: true) == .section(.inspiration))
        #expect(SidebarRow.selected(section: .mails, folder: .trash, mailsOpen: true) == .mail(.trash))
    }

    /// Thirteen rows at most, « Plus » folded: the list holds ten (Mails and its four), the bottom two. « Plus » shows
    /// the folder open in it.
    @Test func theSidebarHoldsThirteenRowsAtMost() async throws {
        let world = try await Self.mailWorld(name: "lignes")
        defer { world.clean() }
        let inspiration = try InspirationTestWorld(name: "lignes-inspiration")
        defer { inspiration.clean() }
        UserDefaults.standard.set(true, forKey: Preferences.Key.mailSidebarOpen)
        UserDefaults.standard.set(false, forKey: Preferences.Key.mailMoreOpen)
        let router = WindowRouter()
        router.section = .home
        let projects = ProjectLibrary(store: ProjectStore(world.database), meetings: MeetingStore(world.database))
        let host = NSHostingView(rootView: MainWindowView(library: MeetingLibrary(store: MeetingStore(world.database)), projects: projects,
                                                         agenda: world.agenda, mails: world.mails, inspiration: inspiration.library(), router: router,
                                                         paths: AppPaths(root: world.root, logs: world.root)) { EmptyView() })
        let window = Self.window(host)
        defer { window.close() }
        try await Self.settle(window)
        let rows = try #require(SidebarAlignmentTests.rowStarts(in: host).first).count
        #expect(rows == 10)
        #expect(rows + SidebarItem.footer(hasAgenda: true).count <= 13)
        world.mails.folder = .spam
        router.section = .mails
        try await Self.settle(window)
        // Notifications, Abonnements, Spam, Corbeille, Tous les messages: Programmés waits for a mail.
        #expect(try #require(SidebarAlignmentTests.rowStarts(in: host).first).count == 15)
    }

    /// 224 points, once the folders and the boxes left (Paul, 19/11: 252 took 28 % of a narrow window).
    @Test func theSidebarIsNarrower() {
        #expect(MainWindowView<EmptyView>.sidebarWidth == 224)
    }

    // MARK: - The boxes, in the list's bar

    /// « Boîtes » says when it hides one.
    @Test func theBoxesMenuSaysWhatItShows() {
        #expect(MailListBar.boxesTitle(shown: 3, total: 3) == "Boîtes")
        #expect(MailListBar.boxesTitle(shown: 2, total: 3) == "Boîtes : 2 sur 3")
    }

    /// The same effect as the sidebar's boxes: a box hidden leaves the list, shown again it comes back.
    @Test func theBoxesMenuHidesAndShowsABox() async throws {
        let world = try await Self.mailWorld(name: "boites")
        defer { world.clean() }
        MailListBar.show("perso@gmail.com", false, in: world.mails)
        #expect(world.mails.hidden == ["perso@gmail.com"])
        MailListBar.show("perso@gmail.com", true, in: world.mails)
        #expect(world.mails.hidden.isEmpty)
    }

    // MARK: - « Fermer, c'est revenir »

    /// An object opened from another section closes back there: the project opened from the Accueil, back to the
    /// Accueil; « Suivant » opens it again. No step is added.
    @Test func closingGoesBackWhereTheObjectWasOpenedFrom() {
        let router = WindowRouter()
        var restored: [UUID?] = []
        router.restoreProject = { restored.append($0) }
        router.section = .home
        router.settle()
        router.clearHistory()
        let project = UUID()
        router.openProject(project)
        router.projectChanged(project)
        router.settle()
        #expect(router.close())
        #expect(router.section == .home && restored.last == .some(nil))
        #expect(!router.canGoBack && router.canGoForward)
        router.goForward()
        #expect(router.section == .projects && restored.last == project)
    }

    /// « Ouvrir le projet » from the Accueil chooses the project in the same turn as the section, where the app keeps it:
    /// one step, so that closing it goes back to the Accueil, never to the board first.
    @Test func aProjectOpenedFromElsewhereIsOneStep() {
        let router = WindowRouter()
        // As the app: the project chosen in Projets is told back to the router.
        router.restoreProject = { [unowned router] id in router.projectChanged(id) }
        router.section = .home
        router.settle()
        router.clearHistory()
        router.openProject(UUID())
        router.settle()
        #expect(router.close())
        #expect(router.section == .home && !router.canGoBack)
    }

    /// Ten threads read are no twenty steps: closing a thread goes back to the list it was opened from, past its
    /// neighbours (↑ ↓), and adds nothing to the history.
    @Test func closingAThreadGoesBackToItsList() {
        let router = WindowRouter()
        router.section = .home
        router.settle()
        router.clearHistory()
        router.openMail(nil)
        router.settle()
        router.openMail("moi@exemple.fr|a")
        router.settle()
        router.mailSelection = "moi@exemple.fr|b"
        router.settle()
        #expect(router.close())
        #expect(router.section == .mails && router.mailSelection == nil)
        router.openMail("moi@exemple.fr|c")
        router.settle()
        #expect(router.close())
        #expect(router.section == .mails && router.mailSelection == nil)
        // One step back: the Accueil, the list's origin.
        router.goBack()
        #expect(router.section == .home && !router.canGoBack)
    }

    /// A thread opened from a contact closes back on the contact; Réglages des mails, back on Mails.
    @Test func closingGoesBackToAnotherSection() {
        let router = WindowRouter()
        let camille = UUID()
        router.openContact(camille)
        router.settle()
        router.clearHistory()
        router.openMail("moi@exemple.fr|a")
        router.settle()
        #expect(router.close())
        #expect(router.section == .contacts && router.contactSelection == camille)
        router.openMail(nil)
        router.settle()
        router.openSettings(.mails)
        router.settle()
        #expect(router.close())
        #expect(router.section == .mails && router.settingsPane == nil)
    }

    /// The thread read over the Accueil, a family of Réglages, an item of Inspiration: each closes back on its page.
    @Test func closingEachKindOfObject() {
        let router = WindowRouter()
        router.section = .home
        router.settle()
        router.clearHistory()
        router.homeMail = "moi@exemple.fr|a"
        router.settle()
        #expect(router.close())
        #expect(router.section == .home && router.homeMail == nil)
        router.openSettings(nil)
        router.settle()
        router.openSettings(.calendar)
        router.settle()
        #expect(router.close())
        #expect(router.section == .settings && router.settingsPane == nil)
        router.openInspiration(.branding)
        router.settle()
        router.openInspiration(.branding, item: UUID())
        router.settle()
        #expect(router.close())
        #expect(router.section == .inspiration && router.inspirationPage == .branding && router.inspirationItem == nil)
    }

    /// Opened first thing (a notification brought the window up on it), it closes in place: no step behind, none added.
    @Test func closingWhatOpenedFirstStaysInPlace() {
        let router = WindowRouter()
        router.openMail("moi@exemple.fr|a")
        router.settle()
        router.clearHistory()
        #expect(router.close())
        #expect(router.section == .mails && router.mailSelection == nil)
        #expect(!router.canGoBack && !router.canGoForward)
        // Nothing open: nothing to close.
        router.section = .calendar
        router.settle()
        #expect(!router.close())
        #expect(router.section == .calendar)
    }

    /// The way back says where it leads: « Revenir à l'Accueil (Échap) », « Revenir à Mails (Échap) ».
    @Test func theWayBackSaysWhereItLeads() {
        let router = WindowRouter()
        router.section = .home
        router.settle()
        router.clearHistory()
        router.openSettings(.mails)
        router.settle()
        #expect(router.returnHelp == "Revenir à l'Accueil (Échap)")
        router.openMail(nil)
        router.settle()
        router.openSettings(.mails)
        router.settle()
        #expect(router.returnHelp == "Revenir à Mails (Échap)")
        // Opened first thing: back to the page's own list.
        router.clearHistory()
        #expect(router.returnHelp == "Revenir à Réglages (Échap)")
    }

    // MARK: - The keys

    /// ⌘1 to ⌘9 by where the keys are (an AZERTY keyboard gives ⌘1 on the « & » key), ⌘, ⌘N ⌘F by what they write:
    /// none is a key of a text, so they work while writing. ⌘← ⌘→ stay the text's.
    @Test func theWindowsKeysAreRead() {
        typealias Input = NavigationInput
        #expect(Input.command(.key(code: 18, modifiers: .command, editingText: false)) == .section(1))
        #expect(Input.command(.key(code: 26, modifiers: .command, editingText: true)) == .section(7))
        #expect(Input.command(.key(code: 25, modifiers: .command, editingText: false)) == .section(9))
        #expect(Input.command(.key(code: 18, modifiers: [.command, .shift], editingText: false)) == nil)
        #expect(Input.command(.key(code: 18, modifiers: [], editingText: false)) == nil)
        #expect(Input.command(.key(code: 46, modifiers: .command, editingText: false, characters: ",")) == .settings)
        #expect(Input.command(.key(code: 45, modifiers: .command, editingText: true, characters: "n")) == .new)
        #expect(Input.command(.key(code: 3, modifiers: [.command, .capsLock], editingText: false, characters: "F")) == .search)
        #expect(Input.command(.key(code: 3, modifiers: [.command, .option], editingText: false, characters: "f")) == nil)
        #expect(Input.command(.key(code: 123, modifiers: .command, editingText: false)) == .back)
        #expect(Input.command(.key(code: 124, modifiers: .command, editingText: true)) == nil)
        #expect(Input.command(.key(code: 33, modifiers: .command, editingText: true)) == .back)
        #expect(Input.command(.mouse(button: 4)) == .forward)
        #expect(Input.command(.swipe(deltaX: 1)) == .back)
    }

    /// A mail's editor is a page made to be written in: ⌘← and ⌘→ are its line's start and end, never « Précédent ».
    /// A mail read is not written in: they still go back and forth there.
    @Test func aMailsEditorIsWriting() {
        let configuration = WKWebViewConfiguration()
        let editor = RichTextEditor.EditorWebView(frame: .zero, configuration: configuration)
        let inside = NSView()
        editor.addSubview(inside)
        #expect(NavigationInput.isEditing(NSTextView()))
        #expect(NavigationInput.isEditing(editor))
        #expect(NavigationInput.isEditing(inside))
        #expect(!NavigationInput.isEditing(WKWebView(frame: .zero, configuration: configuration)))
        #expect(!NavigationInput.isEditing(NSView()))
        #expect(!NavigationInput.isEditing(nil))
    }

    /// What the keys do: a section by its number (Mails from the top of its inbox, as its row), Réglages, the history;
    /// ⌘N is the page's « + », a new mail where the page has none.
    @Test func theKeysDoWhatTheySay() async throws {
        let world = try await Self.mailWorld(name: "touches")
        defer { world.clean() }
        let router = WindowRouter()
        let projects = ProjectLibrary(store: ProjectStore(world.database), meetings: MeetingStore(world.database))
        let keys = WindowKeys(router: router, mails: world.mails, projects: projects,
                              sections: SidebarItem.numbered(hasProjects: true, hasAgenda: true, hasMails: true, hasInspiration: true))
        #expect(keys.run(.section(2), in: nil))
        #expect(router.section == .projects)
        router.settle()
        world.mails.folder = .spam
        router.mailSelection = "moi@exemple.fr|a"
        #expect(keys.run(.section(5), in: nil))
        #expect(router.section == .mails && world.mails.folder == .inbox && router.mailSelection == nil)
        router.settle()
        #expect(keys.run(.section(7), in: nil) && router.section == .contacts)
        router.settle()
        #expect(!keys.run(.section(8), in: nil))
        #expect(keys.run(.settings, in: nil) && router.section == .settings && router.settingsPane == nil)
        router.settle()
        #expect(keys.run(.back, in: nil) && router.section == .contacts)
        // ⌘N: the « + » of Calendrier, of Projets, of Inspiration; a new mail elsewhere.
        router.section = .calendar
        #expect(keys.run(.new, in: nil) && router.newEventRequest != nil)
        router.section = .projects
        #expect(keys.run(.new, in: nil) && projects.newRequest != nil)
        router.openInspiration(.website, item: UUID())
        router.settle()
        #expect(keys.run(.new, in: nil) && router.addRequest != nil && router.inspirationItem == nil && router.section == .inspiration)
        router.section = .home
        #expect(keys.run(.new, in: nil) && world.mails.composing != nil)
        world.mails.closeComposer()
        // ⌘F without a window: nothing to search in.
        #expect(!keys.run(.search, in: nil))
    }

    /// ⌘F puts the caret in the page's search field, which `.searchable` puts in the window's toolbar; a page without one
    /// lets the key go.
    @Test func commandFFindsThePagesSearch() async throws {
        let world = try await Self.mailWorld(name: "chercher")
        defer { world.clean() }
        let router = WindowRouter()
        router.section = .meetings
        let host = NSHostingController(rootView: MainWindowView(library: MeetingLibrary(store: MeetingStore(world.database)), agenda: world.agenda,
                                                               router: router, paths: AppPaths(root: world.root, logs: world.root)) { EmptyView() })
        host.sceneBridgingOptions = [.title, .toolbars]
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 1_180, height: 720))
        window.isReleasedWhenClosed = false
        defer { window.close() }
        try await Self.settle(window)
        #expect(WindowKeys.focusSearch(in: window))
        router.section = .calendar
        try await Self.settle(window)
        #expect(!WindowKeys.focusSearch(in: window))
    }

    // MARK: - The titles

    /// The window's title is the sidebar's word; its subtitle says where Paul is in it (folder, week, family), never the
    /// name of what the page writes large.
    @Test func theTitleIsTheSidebarsWord() async throws {
        let world = try await Self.mailWorld(name: "titres")
        defer { world.clean() }
        let projectStore = ProjectStore(world.database)
        let project = try projectStore.addProject(name: "Site vitrine", status: .priorite1, at: Date())
        let meetingStore = MeetingStore(world.database)
        let start = Date().addingTimeInterval(-3_600)
        let meeting = MeetingRow(createdAt: start, status: .ended, source: .dia, candidateKey: "t/titre", title: "Revue des maquettes",
                                 startedAt: start, endedAt: start.addingTimeInterval(1_800))
        try meetingStore.save(meeting)
        let contact = try ContactStore(world.database).upsert(email: "camille.martin@exemple-studio.fr", name: "Camille Martin", company: nil, at: Date())
        let projects = ProjectLibrary(store: projectStore, meetings: meetingStore)
        let router = WindowRouter()
        let host = NSHostingView(rootView: MainWindowView(library: MeetingLibrary(store: meetingStore), projects: projects, agenda: world.agenda,
                                                         router: router, paths: AppPaths(root: world.root, logs: world.root)) { EmptyView() })
        let window = Self.window(host)
        defer { window.close() }
        func title() async throws -> String {
            try await Self.settle(window)
            return window.subtitle.isEmpty ? window.title : "\(window.title) · \(window.subtitle)"
        }
        router.open(meetingID: meeting.id, at: nil)
        #expect(try await title() == "Réunions")
        router.openContact(contact.id)
        #expect(try await title() == "Contacts")
        router.section = .projects
        projects.selected = project.id
        #expect(try await title() == "Projets")
        router.openSettings(.calendar)
        #expect(try await title() == "Réglages · Calendrier")
    }

    /// Inspiration: « Inspiration », then its page and what it shows.
    @Test func inspirationsTitleSaysItsPage() {
        #expect(InspirationPageView.subtitle(.website, shown: 12, total: 12) == "Websites · 12 sites")
        #expect(InspirationPageView.subtitle(.website, shown: 4, total: 212) == "Websites · 4 sites sur 212")
        #expect(InspirationPageView.subtitle(.mockup, shown: 0, total: 0) == "Mock-ups")
    }

    // MARK: - The links

    /// A project's coming events lead to their event, as its meetings, mails and contacts do.
    @Test func aProjectsEventsLeadToTheirEvent() async throws {
        let world = try await Self.mailWorld(name: "liens")
        defer { world.clean() }
        let projects = ProjectLibrary(store: ProjectStore(world.database), meetings: MeetingStore(world.database))
        let router = WindowRouter()
        router.section = .projects
        let host = NSHostingView(rootView: MainWindowView(library: MeetingLibrary(store: MeetingStore(world.database)), projects: projects,
                                                         agenda: world.agenda, router: router,
                                                         paths: AppPaths(root: world.root, logs: world.root)) { EmptyView() })
        let window = Self.window(host)
        defer { window.close() }
        try await Self.settle(window)
        let open = try #require(projects.openEvent)
        open("moi@exemple.fr|atelier")
        #expect(router.section == .calendar && router.eventSelection == "moi@exemple.fr|atelier")
    }

    /// A meeting's date leads to its event, when one carries it.
    @Test func aMeetingsDateLeadsToItsEvent() {
        let meeting = UUID()
        let start = Date()
        var linked = CalendarEventRow(account: "moi@exemple.fr", eventID: "revue", title: "Revue", startAt: start, endAt: start.addingTimeInterval(1_800),
                                      updatedAt: start)
        linked.meetingID = meeting
        let other = CalendarEventRow(account: "moi@exemple.fr", eventID: "autre", title: "Autre", startAt: start, endAt: start.addingTimeInterval(1_800),
                                     updatedAt: start)
        #expect(MeetingDetailView.event(of: meeting, in: [other, linked])?.eventID == "revue")
        #expect(MeetingDetailView.event(of: UUID(), in: [other, linked]) == nil)
    }

    // MARK: - Helpers

    /// A made-up world of two mailboxes with mails allowed.
    struct MailWorld {
        let root: URL
        let database: AppDatabase
        let agenda: AgendaLibrary
        let mails: MailLibrary

        func clean() { try? FileManager.default.removeItem(at: root) }
    }

    static func mailWorld(name: String) async throws -> MailWorld {
        let database = try AppDatabase.inMemory()
        let calendar = CalendarStore(database)
        for (index, email) in ["moi@exemple.fr", "perso@gmail.com"].enumerated() {
            try calendar.addAccount(email: email, at: Date().addingTimeInterval(Double(index)))
            try calendar.setGrantedScopes(email: email, scopes: "openid https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/gmail.modify")
        }
        let root = FileManager.default.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        let agenda = AgendaLibrary(database: database)
        let mails = MailLibrary(agenda: agenda, root: root, defaults: try #require(UserDefaults(suiteName: "\(name)-\(UUID().uuidString)")), flavor: .dev)
        for _ in 0..<100 where mails.accounts.count < 2 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(mails.accounts.count == 2)
        return MailWorld(root: root, database: database, agenda: agenda, mails: mails)
    }

    static func window(_ host: NSView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_180, height: 900), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        return window
    }

    static func settle(_ window: NSWindow) async throws {
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        window.layoutIfNeeded()
    }
}
