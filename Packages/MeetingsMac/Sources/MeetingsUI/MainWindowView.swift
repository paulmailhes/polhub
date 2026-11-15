import Agenda
import Domain
import Persistence
import ProjectsUI
import PolhubDesign
import SwiftUI
import Updates

/// The sidebar keeps the work; the app's own pages (diagnostic, journal) live in Réglages (Paul, 13/11).
public enum SidebarItem: String, Hashable, Sendable {
    case home, projects, meetings, calendar, mails, contacts, settings

    var title: String {
        switch self {
        case .home: "Accueil"
        case .projects: "Projets"
        case .meetings: "Réunions"
        case .calendar: "Calendrier"
        case .mails: "Mails"
        case .contacts: "Contacts"
        case .settings: "Réglages"
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
        case .settings: Palette.gray
        }
    }

    /// The work; Réglages sits apart, at the bottom of the sidebar (Paul, 14/11). Accueil, Calendrier and
    /// Contacts need the agenda (13/11).
    static func visible(hasProjects: Bool, hasAgenda: Bool, hasMails: Bool = false) -> [SidebarItem] {
        [hasAgenda ? .home : nil, hasProjects ? .projects : nil, .meetings, hasAgenda ? .calendar : nil, hasMails ? .mails : nil,
         hasAgenda ? .contacts : nil].compactMap { $0 }
    }
}

/// The families of Réglages, entered one by one, as in Apple's settings (Paul, 14/11). Every new feature puts
/// its settings in its family.
public enum SettingsPane: String, Hashable, Sendable, CaseIterable {
    case general, notifications, accounts, calendar, mails, projects, meetings, updates, diagnostic, journal

    public var title: String {
        switch self {
        case .general: "Général"
        case .notifications: "Notifications"
        case .accounts: "Comptes Google"
        case .calendar: "Calendrier"
        case .mails: "Mails"
        case .projects: "Projets"
        case .meetings: "Réunions"
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
        case .projects: "square.grid.3x2.fill"
        case .meetings: "waveform"
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
        case .projects: Palette.blue
        case .meetings: Palette.violet
        case .updates: Palette.gray
        case .diagnostic: Palette.green
        case .journal: Palette.brown
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Ouverture à la session"
        case .notifications: "Rappels de rendez-vous, nouveaux rendez-vous, comptes rendus"
        case .accounts: "Comptes, couleurs, accès à l'agenda et aux mails"
        case .calendar: "Nouveaux rendez-vous, affichage"
        case .mails: "Images distantes"
        case .projects: "Taille des cartes du Kanban"
        case .meetings: "Comptes rendus, langue des transcriptions"
        case .updates: "Version installée, installation automatique"
        case .diagnostic: "Autorisations, micro, Dia"
        case .journal: "Ce que l'app a fait et vu"
        }
    }

    /// The whole app first, then Paul's tools, then the app's own pages.
    static func families(hasAgenda: Bool, hasProjects: Bool, hasMails: Bool = false) -> [[SettingsPane]] {
        [[.general, .notifications],
         [hasAgenda ? .accounts : nil, hasAgenda ? .calendar : nil, hasMails ? .mails : nil, hasProjects ? .projects : nil, .meetings].compactMap { $0 },
         [.updates, .diagnostic, .journal]]
    }
}

/// Where the window is: the app sets it to open a meeting from the menu.
@MainActor
public final class WindowRouter: ObservableObject {
    @Published public var section: SidebarItem = .projects
    @Published public var selection: UUID?
    /// A moment to play in the selected meeting, asked by the search.
    @Published public var seekRequest: (meetingID: UUID, seconds: Double)?
    @Published public var query = ""
    /// The family of Réglages entered; `nil` for the list of families.
    @Published public var settingsPane: SettingsPane?
    @Published public var contactSelection: UUID?
    /// An event Accueil asked Calendrier to open (14/11).
    @Published public var eventSelection: String?
    /// A project Accueil asked Projets to open (review of 14/11).
    @Published public var projectSelection: UUID?
    /// The thread open in Mails (`account|threadID`); `nil` for the list (14/11).
    @Published public var mailSelection: String?

    public init() {}

    public func openContact(_ id: UUID) {
        section = .contacts
        contactSelection = id
    }

    /// The menu's « Diagnostic… », the first launch and the alerts.
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
}

/// Polhub's window: the projects, the meetings, and Réglages (updates, diagnostic, journal, vault).
public struct MainWindowView<Diagnostic: View>: View {
    /// The sidebar, the 300-point list and a detail of 360 points at least.
    public static var minimumWidth: CGFloat { 860 }
    /// Fixed (Paul, 15/11): the smallest width that shows « Boîte de réception » with a two-digit count, and
    /// « Tous les messages », whole at the large row size.
    static var sidebarWidth: CGFloat { 252 }

    @ObservedObject var library: MeetingLibrary
    let projects: ProjectLibrary?
    let agenda: AgendaLibrary?
    let mails: MailLibrary?
    let updates: UpdateService?
    let notifications: NotificationHub?
    let startup: StartupControl?
    @ObservedObject var router: WindowRouter
    let paths: AppPaths
    let diagnostic: Diagnostic
    @State private var columns: NavigationSplitViewVisibility = .all

    public init(
        library: MeetingLibrary, projects: ProjectLibrary? = nil, agenda: AgendaLibrary? = nil, mails: MailLibrary? = nil,
        updates: UpdateService? = nil, notifications: NotificationHub? = nil, startup: StartupControl? = nil, router: WindowRouter,
        paths: AppPaths, @ViewBuilder diagnostic: () -> Diagnostic
    ) {
        self.notifications = notifications
        self.startup = startup
        self.library = library
        self.projects = projects
        self.agenda = agenda
        self.mails = mails
        self.updates = updates
        self.router = router
        self.paths = paths
        self.diagnostic = diagnostic()
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            Sidebar(router: router, library: library, agenda: agenda, mails: mails,
                    items: SidebarItem.visible(hasProjects: projects != nil, hasAgenda: agenda != nil, hasMails: mails != nil))
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
                if let agenda { HomeView(agenda: agenda, library: library, router: router) }
            case .calendar:
                if let agenda { CalendarView(agenda: agenda, router: router) }
            case .contacts:
                if let agenda { ContactsView(agenda: agenda, router: router) }
            case .mails:
                if let mails { MailSectionView(mails: mails, router: router) }
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
                    .frame(width: 300)
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
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                }
                .windowTitle("Réunions", subtitle: router.selection.flatMap { library.row($0)?.title } ?? "")
                .searchable(text: $router.query, placement: .toolbar, prompt: "Chercher dans les transcriptions")
            case .settings:
                SettingsPage(router: router, updates: updates, projects: projects, agenda: agenda, mails: mails, library: library,
                             notifications: notifications, startup: startup) {
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
