import Agenda
import AppKit
import Domain
import Persistence
import ProjectsUI
import PolhubDesign
import SwiftUI
import Updates

/// The sidebar keeps the work; the app's own pages (diagnostic, journal) live in Réglages (Paul, 13/11).
public enum SidebarItem: String, Hashable, Sendable {
    case home, projects, meetings, calendar, mails, contacts, inspiration, settings

    var title: String {
        switch self {
        case .home: "Accueil"
        case .projects: "Projets"
        case .meetings: "Réunions"
        case .calendar: "Calendrier"
        case .mails: "Mails"
        case .contacts: "Contacts"
        case .inspiration: "Inspiration"
        case .settings: "Réglages"
        }
    }

    /// Its icon in the sidebar, from Phosphor (Paul, 15/11: « des icônes beaucoup mieux »).
    var appIcon: AppIcon {
        switch self {
        case .home: .home
        case .projects: .projects
        case .meetings: .meetings
        case .calendar: .calendar
        case .mails: .mails
        case .contacts: .contacts
        case .inspiration: .inspiration
        case .settings: .settings
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .projects: "square.grid.3x2.fill"
        case .meetings: "waveform"
        case .calendar: "calendar"
        case .mails: "envelope.fill"
        case .contacts: "person.2.fill"
        case .inspiration: "lightbulb.fill"
        case .settings: "gearshape.fill"
        }
    }

    /// One color per section, as in Mail's and the Finder's sidebar; the same as its family in Réglages (15/11).
    var tint: String {
        switch self {
        case .home: Palette.teal
        case .projects: Palette.blue
        case .meetings: Palette.violet
        case .calendar: Palette.orange
        case .mails: Palette.pink
        case .contacts: Palette.green
        case .inspiration: Palette.yellow
        case .settings: Palette.gray
        }
    }

    /// The work; Réglages sits apart, at the bottom of the sidebar (Paul, 14/11). Accueil, Calendrier and
    /// Contacts need the agenda (13/11). « Inspiration » comes last, after Contacts (16/11).
    static func visible(hasProjects: Bool, hasAgenda: Bool, hasMails: Bool = false, hasInspiration: Bool = false) -> [SidebarItem] {
        [hasAgenda ? .home : nil, hasProjects ? .projects : nil, .meetings, hasAgenda ? .calendar : nil, hasMails ? .mails : nil,
         hasAgenda ? .contacts : nil, hasInspiration ? .inspiration : nil].compactMap { $0 }
    }
}

/// The families of Réglages, entered one by one, as in Apple's settings (Paul, 14/11). Every new feature puts
/// its settings in its family.
public enum SettingsPane: String, Hashable, Sendable, CaseIterable {
    case general, notifications, accounts, calendar, mails, colin, projects, meetings, inspiration, updates, diagnostic, journal

    public var title: String {
        switch self {
        case .general: "Général"
        case .notifications: "Notifications"
        case .accounts: "Comptes Google"
        case .calendar: "Calendrier"
        case .mails: "Mails"
        case .colin: "Colin"
        case .projects: "Projets"
        case .meetings: "Réunions"
        case .inspiration: "Inspiration"
        case .updates: "Mises à jour"
        case .diagnostic: "Diagnostic"
        case .journal: "Journal"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape.fill"
        case .notifications: "bell.badge.fill"
        case .accounts: "person.crop.circle.fill"
        case .calendar: "calendar"
        case .mails: "envelope.fill"
        case .colin: "sparkles"
        case .projects: "square.grid.3x2.fill"
        case .meetings: "waveform"
        case .inspiration: "lightbulb.fill"
        case .updates: "arrow.down.circle.fill"
        case .diagnostic: "stethoscope"
        case .journal: "list.bullet.rectangle.fill"
        }
    }

    var tint: String {
        switch self {
        case .general: Palette.gray
        case .notifications: Palette.red
        case .accounts: Palette.teal
        case .calendar: Palette.orange
        case .mails: Palette.pink
        case .colin: Palette.green
        case .projects: Palette.blue
        case .meetings: Palette.violet
        case .inspiration: Palette.yellow
        case .updates: Palette.gray
        case .diagnostic: Palette.green
        case .journal: Palette.brown
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Ouverture à la session, barre des menus"
        case .notifications: "Rappels de rendez-vous, nouveaux rendez-vous, comptes rendus"
        case .accounts: "Comptes, couleurs, accès à l'agenda et aux mails"
        case .calendar: "Nouveaux rendez-vous, affichage"
        case .mails: "Images distantes"
        case .colin: "Ce que Colin signale sur l'Accueil"
        case .projects: "Taille des cartes du Kanban"
        case .meetings: "Comptes rendus, langue des transcriptions"
        case .inspiration: "Pages LinkedIn, collecte, catégories"
        case .updates: "Version installée, installation automatique"
        case .diagnostic: "Autorisations, micro, Dia"
        case .journal: "Ce que l'app a fait et vu"
        }
    }

    /// The whole app first, then Paul's tools, then the app's own pages. Colin comes with the mails: what he signals
    /// is read in them.
    static func families(hasAgenda: Bool, hasProjects: Bool, hasMails: Bool = false, hasInspiration: Bool = false) -> [[SettingsPane]] {
        [[.general, .notifications],
         [hasAgenda ? .accounts : nil, hasAgenda ? .calendar : nil, hasMails ? .mails : nil, hasMails ? .colin : nil,
          hasProjects ? .projects : nil, .meetings, hasInspiration ? .inspiration : nil].compactMap { $0 },
         [.updates, .diagnostic, .journal]]
    }
}

/// Where the window is: the app sets it to open a meeting from the menu.
@MainActor
public final class WindowRouter: ObservableObject {
    @Published public var section: SidebarItem = .projects { didSet { moved() } }
    @Published public var selection: UUID? { didSet { moved() } }
    /// A moment to play in the selected meeting, asked by the search.
    @Published public var seekRequest: (meetingID: UUID, seconds: Double)?
    @Published public var query = ""
    /// The family of Réglages entered; `nil` for the list of families.
    @Published public var settingsPane: SettingsPane? { didSet { moved() } }
    @Published public var contactSelection: UUID? { didSet { moved() } }
    /// An event Accueil asked Calendrier to open (14/11).
    @Published public var eventSelection: String?
    /// A project Accueil asked Projets to open (review of 14/11).
    @Published public var projectSelection: UUID?
    /// The thread open in Mails (`account|threadID`); `nil` for the list (14/11).
    @Published public var mailSelection: String? { didSet { moved() } }
    /// The thread open over the Accueil (18/11: « Relire », « Ouvrir »): its own, the one of Mails stays as it is.
    @Published public var homeMail: String? { didSet { moved() } }
    /// A new event asked for (« Coup d'œil », Calendrier's « + »): Calendrier opens its editor, then clears it. A new
    /// value per request, so that two requests in a row open two editors.
    @Published public var newEventRequest: UUID?
    /// The notifications' panel asked for: the sidebar's bell opens it once on screen, then clears it.
    @Published public var notificationsRequested = false
    /// The page of « Inspiration » shown (Websites, Branding, Mock-ups), and the item open over it (16/11).
    @Published public var inspirationPage: InspirationKind = .website { didSet { moved() } }
    @Published public var inspirationItem: UUID? { didSet { moved() } }

    public init() {}

    /// A place of the window, for what opens it from outside (« Coup d'œil », the notifications).
    public enum Place: Equatable, Sendable {
        case section(SidebarItem)
        case meeting(UUID)
        case event(String)
        /// A thread (`account|threadID`), or nil for the inbox's list.
        case mail(String?)
        /// A family of Réglages, or nil for the list of families.
        case settings(SettingsPane?)
        /// The notifications' panel, under the sidebar's bell.
        case notifications
        /// Calendrier, with the editor of a new event open.
        case newEvent
        /// A page of « Inspiration », and one of its items open (16/11).
        case inspiration(InspirationKind, item: UUID? = nil)
    }

    /// Goes there; the app then shows the window.
    public func go(to place: Place) {
        switch place {
        case .section(let item): section = item
        case .meeting(let id): open(meetingID: id, at: nil)
        case .event(let id): openEvent(id)
        case .mail(let key): openMail(key)
        case .settings(let pane): openSettings(pane)
        case .notifications: openNotifications()
        case .newEvent: newEvent()
        case .inspiration(let kind, let item): openInspiration(kind, item: item)
        }
    }

    /// A page of « Inspiration », from its grid or on one of its items.
    public func openInspiration(_ kind: InspirationKind, item: UUID? = nil) {
        section = .inspiration
        inspirationPage = kind
        inspirationItem = item
    }

    /// Calendrier, its editor open on a new event.
    public func newEvent() {
        section = .calendar
        newEventRequest = UUID()
    }

    /// The notifications' panel, under the sidebar's bell (the page shown stays).
    public func openNotifications() {
        notificationsRequested = true
    }

    public func openContact(_ id: UUID) {
        section = .contacts
        contactSelection = id
    }

    public func openProject(_ id: UUID) {
        section = .projects
        projectSelection = id
    }

    public func openEvent(_ id: String) {
        section = .calendar
        eventSelection = id
    }

    public func openMail(_ threadKey: String?) {
        section = .mails
        mailSelection = threadKey
    }

    /// The menu's « Diagnostic… », the first launch and the alerts.
    public func openDiagnostic() {
        openSettings(.diagnostic)
    }

    public func openSettings(_ pane: SettingsPane?) {
        section = .settings
        settingsPane = pane
    }

    public func open(meetingID: UUID, at seconds: Double?) {
        section = .meetings
        selection = meetingID
        seekRequest = seconds.map { (meetingID, $0) }
    }

    // MARK: - « Précédent », « Suivant »

    /// Where the window is, for « Précédent » and « Suivant » (Paul, 16/11: « je fais retour sur les pages internet,
    /// sur n'importe quoi »): the section and what is open in it. The open project and the mails' folder are kept by
    /// their libraries, which tell the router (`projectChanged`, `mailFolderChanged`) and are asked them back.
    struct Location: Equatable {
        var section: SidebarItem
        var meeting: UUID?
        var mail: String?
        var mailFolder: MailFolder
        var settingsPane: SettingsPane?
        var contact: UUID?
        var project: UUID?
        var inspirationPage: InspirationKind
        var inspirationItem: UUID?
        var homeMail: String?
    }

    /// The steps kept behind: a long morning of clicks.
    static let depth = 100

    public var restoreProject: ((UUID?) -> Void)?
    public var restoreMailFolder: ((MailFolder) -> Void)?
    private var project: UUID?
    private var mailFolder: MailFolder = .inbox
    private var back: [Location] = []
    private var forward: [Location] = []
    /// The place the window is at, as last settled; at first, the router's own defaults.
    private var current = Location(section: .projects, meeting: nil, mail: nil, mailFolder: .inbox, settingsPane: nil, contact: nil,
                                   project: nil, inspirationPage: .website, inspirationItem: nil)
    private var restoring = false
    private var pending = false

    public var canGoBack: Bool { !back.isEmpty || (pending && location != current) }
    public var canGoForward: Bool { !forward.isEmpty }

    var location: Location {
        Location(section: section, meeting: selection, mail: mailSelection, mailFolder: mailFolder, settingsPane: settingsPane,
                 contact: contactSelection, project: project, inspirationPage: inspirationPage, inspirationItem: inspirationItem, homeMail: homeMail)
    }

    /// Projets opened a project, or went back to the grid.
    public func projectChanged(_ id: UUID?) {
        guard project != id else { return }
        project = id
        moved()
    }

    /// Mails showed another folder.
    public func mailFolderChanged(_ folder: MailFolder) {
        guard mailFolder != folder else { return }
        mailFolder = folder
        moved()
    }

    /// The changes of one gesture (a section and what opens in it) make one step: kept at the end of the turn.
    private func moved() {
        guard !restoring, !pending else { return }
        pending = true
        DispatchQueue.main.async { [weak self] in self?.settle() }
    }

    /// The place reached becomes a step; what was ahead goes. A list choosing its first row by itself only refines
    /// the place.
    func settle() {
        pending = false
        let now = location
        guard now != current else { return }
        if Self.refines(now, current) {
            current = now
            return
        }
        back.append(current)
        if back.count > Self.depth { back.removeFirst(back.count - Self.depth) }
        forward.removeAll()
        current = now
    }

    /// The meetings' and the contacts' lists choose a row when none is: the same place, refined.
    static func refines(_ now: Location, _ before: Location) -> Bool {
        var filled = before
        if before.meeting == nil { filled.meeting = now.meeting }
        if before.contact == nil { filled.contact = now.contact }
        return filled == now
    }

    /// The window opens: where it is now is the start, nothing behind (the launch's « Accueil » is no step back).
    public func clearHistory() {
        pending = false
        back.removeAll()
        forward.removeAll()
        current = location
    }

    /// The mouse's « Précédent », ⌘[, the trackpad's swipe to the right.
    public func goBack() {
        settle()
        guard let previous = back.popLast() else { return }
        forward.append(current)
        restore(previous)
    }

    /// The mouse's « Suivant », ⌘], the swipe to the left.
    public func goForward() {
        settle()
        guard let next = forward.popLast() else { return }
        back.append(current)
        restore(next)
    }

    private func restore(_ place: Location) {
        restoring = true
        defer { restoring = false }
        section = place.section
        selection = place.meeting
        mailSelection = place.mail
        homeMail = place.homeMail
        settingsPane = place.settingsPane
        contactSelection = place.contact
        inspirationPage = place.inspirationPage
        inspirationItem = place.inspirationItem
        project = place.project
        restoreProject?(place.project)
        mailFolder = place.mailFolder
        restoreMailFolder?(place.mailFolder)
        current = place
        pending = false
    }
}

/// What goes back and what goes forward (Paul, 16/11): the mouse's side buttons, ⌘[ and ⌘] (by where they are on the
/// keyboard, as Safari, whatever its layout), ⌘← and ⌘→ outside a text being written, the trackpad's swipe.
public enum NavigationInput {
    public enum Direction: Equatable, Sendable { case back, forward }

    public enum Gesture: Equatable {
        case mouse(button: Int)
        case key(code: UInt16, modifiers: NSEvent.ModifierFlags, editingText: Bool)
        case swipe(deltaX: CGFloat)
    }

    static let leftBracket: UInt16 = 33, rightBracket: UInt16 = 30, leftArrow: UInt16 = 123, rightArrow: UInt16 = 124

    public static func direction(_ gesture: Gesture) -> Direction? {
        switch gesture {
        case .mouse(let button):
            return button == 3 ? .back : button == 4 ? .forward : nil
        case .key(let code, let modifiers, let editingText):
            guard modifiers.intersection([.command, .option, .control, .shift]) == .command else { return nil }
            switch code {
            case leftBracket: return .back
            case rightBracket: return .forward
            case leftArrow: return editingText ? nil : .back
            case rightArrow: return editingText ? nil : .forward
            default: return nil
            }
        case .swipe(let deltaX):
            return deltaX > 0 ? .back : deltaX < 0 ? .forward : nil
        }
    }

    /// An event of the window, read.
    public static func direction(of event: NSEvent, editingText: Bool) -> Direction? {
        switch event.type {
        case .otherMouseDown: direction(.mouse(button: event.buttonNumber))
        case .keyDown: direction(.key(code: event.keyCode, modifiers: event.modifierFlags, editingText: editingText))
        case .swipe: direction(.swipe(deltaX: event.deltaX))
        default: nil
        }
    }
}

/// Polhub's window: the projects, the meetings, and Réglages (updates, diagnostic, journal).
public struct MainWindowView<Diagnostic: View>: View {
    /// The sidebar, the meetings' list, its divider and the smallest meeting page: derived from them, so that the
    /// narrowest window never squeezes the sidebar nor cuts the page (correctifs, 15/11: 860 had become too narrow).
    public static var minimumWidth: CGFloat { sidebarWidth + meetingListWidth + 1 + meetingPageMinimumWidth }
    /// Fixed (Paul, 15/11): the smallest width that shows « Boîte de réception » with a two-digit count, and
    /// « Tous les messages », whole at the large row size.
    static var sidebarWidth: CGFloat { 252 }
    /// The list of the meetings, fixed (13/11).
    static var meetingListWidth: CGFloat { 300 }
    /// A meeting's page, at its narrowest.
    static var meetingPageMinimumWidth: CGFloat { 360 }

    @ObservedObject var library: MeetingLibrary
    let projects: ProjectLibrary?
    let agenda: AgendaLibrary?
    let mails: MailLibrary?
    /// What the Accueil knows (18/11), kept by the app whether the window shows or not.
    let colin: ColinLibrary?
    let inspiration: InspirationLibrary?
    let updates: UpdateService?
    let notifications: NotificationHub?
    let startup: StartupControl?
    @ObservedObject var router: WindowRouter
    let paths: AppPaths
    let diagnostic: Diagnostic
    @State private var columns: NavigationSplitViewVisibility = .all

    public init(
        library: MeetingLibrary, projects: ProjectLibrary? = nil, agenda: AgendaLibrary? = nil, mails: MailLibrary? = nil, colin: ColinLibrary? = nil,
        inspiration: InspirationLibrary? = nil, updates: UpdateService? = nil, notifications: NotificationHub? = nil,
        startup: StartupControl? = nil, router: WindowRouter, paths: AppPaths, @ViewBuilder diagnostic: () -> Diagnostic
    ) {
        self.notifications = notifications
        self.startup = startup
        self.library = library
        self.projects = projects
        self.agenda = agenda
        self.mails = mails
        // The app keeps its own; a window made without one (a capture, a test) gets one for its Accueil.
        self.colin = colin ?? agenda.map { ColinLibrary(agenda: $0, mails: mails) }
        self.inspiration = inspiration
        self.updates = updates
        self.router = router
        self.paths = paths
        self.diagnostic = diagnostic()
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            Sidebar(router: router, library: library, agenda: agenda, mails: mails, inspiration: inspiration,
                    items: SidebarItem.visible(hasProjects: projects != nil, hasAgenda: agenda != nil, hasMails: mails != nil,
                                               hasInspiration: inspiration != nil),
                    inbox: notifications?.inbox)
                // One width, always: a sidebar free to resize changed size from one section to the next (Paul, 15/11).
                .navigationSplitViewColumnWidth(Self.sidebarWidth)
                // The window is made by hand: SwiftUI does not add this button there. It keeps a toolbar on every
                // page, so the window's buttons never move and nothing sticks to the top (Paul, 14/11).
                .toolbar {
                    ToolbarItem {
                        Button {
                            withAnimation(Motion.standard) { columns = columns == .detailOnly ? .all : .detailOnly }
                        } label: {
                            Label("Barre latérale", systemImage: "sidebar.left")
                        }
                        .help("Afficher ou masquer la barre latérale")
                    }
                }
        } detail: {
            switch router.section {
            case .home:
                if let agenda, let colin { HomeView(agenda: agenda, mails: mails, colin: colin, router: router) }
            case .calendar:
                if let agenda { CalendarView(agenda: agenda, router: router) }
            case .contacts:
                if let agenda { ContactsView(agenda: agenda, router: router) }
            case .mails:
                if let mails { MailSectionView(mails: mails, router: router) }
            case .inspiration:
                if let inspiration { InspirationSectionView(library: inspiration, router: router) }
            case .projects:
                if let projects {
                    ProjectsView(library: projects)
                        .onAppear {
                            projects.openMeeting = { [weak router] id in router?.open(meetingID: id, at: nil) }
                            projects.openMail = { [weak router] key in router?.openMail(key) }
                            projects.openContact = { [weak router] id in router?.openContact(id) }
                            openAskedProject(projects)
                        }
                        .onChange(of: router.projectSelection) { _, _ in openAskedProject(projects) }
                } else {
                    ContentUnavailableView("Projets indisponibles", systemImage: "square.grid.3x2")
                }
            case .meetings:
                // A fixed list and a detail that wraps its text: a split view let the detail push the
                // window wider than the screen (13/11).
                HStack(spacing: 0) {
                    Group {
                        if SearchModel.shouldSearch(router.query) {
                            SearchResultsView(query: router.query, transcripts: library.transcripts) { id, seconds in
                                router.open(meetingID: id, at: seconds)
                            }
                        } else {
                            MeetingListView(library: library, selection: $router.selection, paths: paths, projects: projects?.projects ?? [])
                        }
                    }
                    .frame(width: Self.meetingListWidth)
                    Divider()
                    Group {
                        if let id = router.selection, let row = library.row(id) {
                            MeetingDetailView(row: row, store: library.store, paths: paths, transcripts: library.transcripts,
                                              projects: projects?.projects ?? [],
                                              queue: library.queue, summaries: library.summaries, summaryUnavailable: library.summaryUnavailable,
                                              summaryProgress: library.summaryProgress[row.id], job: library.jobs[row.id], meetingActive: library.meetingActive,
                                              router: router, agenda: agenda)
                                .id(id)
                        } else {
                            ContentUnavailableView("Aucune réunion choisie", systemImage: "waveform",
                                                   description: Text("Choisis une réunion dans la liste."))
                        }
                    }
                    .frame(minWidth: Self.meetingPageMinimumWidth, maxWidth: .infinity, maxHeight: .infinity)
                }
                .windowTitle("Réunions", subtitle: router.selection.flatMap { library.row($0)?.title } ?? "")
                .searchable(text: $router.query, placement: .toolbar, prompt: "Chercher dans les transcriptions")
            case .settings:
                SettingsPage(router: router, updates: updates, projects: projects, agenda: agenda, mails: mails, inspiration: inspiration,
                             library: library, notifications: notifications, startup: startup) {
                    diagnostic
                } journal: {
                    JournalView(entries: library.journal)
                }
            }
        }
        .frame(minWidth: Self.minimumWidth, minHeight: 520)
    }

    private func openAskedProject(_ projects: ProjectLibrary) {
        guard let id = router.projectSelection else { return }
        router.projectSelection = nil
        projects.selected = id

    }
}

/// The meetings by day, newest first: the newest opens by itself, a right click gives the usual gestures (15/11).
struct MeetingListView: View {
    @ObservedObject var library: MeetingLibrary
    @Binding var selection: UUID?
    var paths: AppPaths?
    var projects: [ProjectRow] = []
    @State private var deleting: MeetingRow?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let sections = MeetingListModel.sections(library.rows, now: context.date, calendar: .current)
            if sections.isEmpty {
                ContentUnavailableView("Aucune réunion", systemImage: "waveform",
                                       description: Text("Ouvre un Meet dans Dia : il s'enregistre tout seul."))
            } else {
                List(selection: $selection) {
                    ForEach(sections) { section in
                        Section(section.title) {
                            ForEach(section.rows) { row in
                                MeetingRowView(row: row, now: context.date, badge: TranscriptModel.badge(library.jobs[row.id]),
                                               project: projectName(row),
                                               summary: MeetingListModel.summaryLine(overview: library.overviews[row.id], job: library.summaryJobs[row.id]))
                                    .tag(row.id)
                                    .contextMenu { menu(row) }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { openNewest() }
        .onChange(of: library.rows) { previous, _ in openNewest(previous: previous) }
        .confirmationDialog("Supprimer « \(deleting?.title ?? "") » ?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting) { row in
            Button("Mettre à la Corbeille", role: .destructive) { delete(row) }
            Button("Annuler", role: .cancel) {}
        } message: { _ in
            Text("L'audio va à la Corbeille, d'où tu peux encore le récupérer.")
        }
    }

    private func projectName(_ row: MeetingRow) -> String? {
        row.projectID.flatMap { id in projects.first { $0.id == id }?.name }
    }

    /// Nothing chosen: the newest opens. The meeting chosen went to the Trash: its neighbour, from its page as from
    /// the list. One older than the list stays (correctifs, 15/11).
    private func openNewest(previous: [MeetingRow] = []) {
        let open = MeetingListModel.meetingToOpen(selection: selection, rows: library.rows, previous: previous, isGone: library.isGone)
        if open != selection { selection = open }
    }

    @ViewBuilder
    private func menu(_ row: MeetingRow) -> some View {
        Button("Ouvrir") { selection = row.id }
        Button("Refaire le compte rendu") {
            let summaries = library.summaries, id = row.id
            Task { await summaries?.redo(meetingID: id) }
        }
        .disabled(library.summaries == nil || row.source == .imported || row.status.isUnfinished || row.transcribedAt == nil
                  || library.summaryJobs[row.id]?.state == .running)
        if let paths {
            Divider()
            Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([paths.meetingFolder(row.id)]) }
                .disabled(row.source == .imported)
            Button("Supprimer…", role: .destructive) { deleting = row }
                .disabled(row.status.isUnfinished)
        }
    }

    private func delete(_ row: MeetingRow) {
        guard let paths else { return }
        if selection == row.id { selection = MeetingListModel.neighbor(of: row.id, in: library.rows) }
        library.moveToTrash(row, folder: paths.meetingFolder(row.id))
    }
}

/// One meeting: its title, when and how long (and its project), then its summary's first lines (15/11).
struct MeetingRowView: View {
    let row: MeetingRow
    let now: Date
    var badge: String?
    var project: String?
    var summary: MeetingListModel.SummaryLine?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(row.title).font(.rowTitle.weight(.medium)).lineLimit(1)
                Spacer(minLength: Space.xs)
                chips
            }
            Text(MeetingListModel.metaText(row, project: project, now: now))
                .font(.meta.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let summary {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: summary.kind == .failed ? "exclamationmark.triangle" : "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(summary.kind == .failed ? Color.orange : Color(hex: Palette.violet))
                        .symbolEffect(.pulse, isActive: summary.kind == .writing)
                    Text(summary.text)
                        .font(.rowBody)
                        .foregroundStyle(summary.kind == .failed ? Color.orange : .secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hoverRow(inset: Space.s)
    }

    @ViewBuilder
    private var chips: some View {
        if row.status.isUnfinished {
            Chip("En cours", systemImage: "record.circle", tint: .red)
        } else if row.status == .interrupted {
            Chip("Interrompue", tint: .orange)
        }
        if let badge, !row.status.isUnfinished {
            Chip(badge, tint: badge == "Échec" || badge == "À vérifier" ? .orange : nil)
        }
    }
}
