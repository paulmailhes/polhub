import Domain
import Persistence
import ProjectsUI
import PolhubDesign
import SwiftUI
import Updates

/// The sidebar keeps the work; the app's own pages (diagnostic, journal) live in Réglages (Paul, 13/11).
public enum SidebarItem: String, Hashable, Sendable {
    case home, projects, meetings, calendar, contacts, settings

    var title: String {
        switch self {
        case .home: "Accueil"
        case .projects: "Projets"
        case .meetings: "Réunions"
        case .calendar: "Calendrier"
        case .contacts: "Contacts"
        case .settings: "Réglages"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .projects: "square.grid.3x2"
        case .meetings: "waveform"
        case .calendar: "calendar"
        case .contacts: "person.2"
        case .settings: "gearshape"
        }
    }

    /// Réglages is always there: it no longer depends on the update service being ready (13/11). Accueil,
    /// Calendrier and Contacts need the agenda (13/11).
    static func visible(hasProjects: Bool, hasAgenda: Bool) -> [SidebarItem] {
        [hasAgenda ? .home : nil, hasProjects ? .projects : nil, .meetings, hasAgenda ? .calendar : nil, hasAgenda ? .contacts : nil, .settings]
            .compactMap { $0 }
    }
}

/// The tabs of Réglages.
public enum SettingsTab: String, Hashable, Sendable, CaseIterable {
    case updates, diagnostic, journal

    var title: String {
        switch self {
        case .updates: "Mises à jour"
        case .diagnostic: "Diagnostic"
        case .journal: "Journal"
        }
    }

    /// The vault's import is gone with Obsidian (Paul, 14/11).
    static func visible(hasProjects: Bool) -> [SettingsTab] {
        allCases
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
    @Published public var settingsTab: SettingsTab = .updates
    @Published public var contactSelection: UUID?
    /// An event Accueil asked Calendrier to open (14/11).
    @Published public var eventSelection: String?
    /// A project Accueil asked Projets to open (review of 14/11).
    @Published public var projectSelection: UUID?

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

    public func openDiagnostic() {
        section = .settings
        settingsTab = .diagnostic
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

    @ObservedObject var library: MeetingLibrary
    let projects: ProjectLibrary?
    let agenda: AgendaLibrary?
    let updates: UpdateService?
    @ObservedObject var router: WindowRouter
    let paths: AppPaths
    let diagnostic: Diagnostic
    @State private var columns: NavigationSplitViewVisibility = .all

    public init(
        library: MeetingLibrary, projects: ProjectLibrary? = nil, agenda: AgendaLibrary? = nil, updates: UpdateService? = nil, router: WindowRouter,
        paths: AppPaths, @ViewBuilder diagnostic: () -> Diagnostic
    ) {
        self.library = library
        self.projects = projects
        self.agenda = agenda
        self.updates = updates
        self.router = router
        self.paths = paths
        self.diagnostic = diagnostic()
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            List(selection: $router.section) {
                ForEach(SidebarItem.visible(hasProjects: projects != nil, hasAgenda: agenda != nil), id: \.self) { item in
                    Label(item.title, systemImage: item.icon).tag(item)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
            // The window is made by hand: SwiftUI does not add this button there. It keeps a toolbar on every
            // page, so the window's buttons never move and nothing sticks to the top (Paul, 14/11).
            .toolbar {
                ToolbarItem {
                    Button {
                        withAnimation { columns = columns == .detailOnly ? .all : .detailOnly }
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
            case .projects:
                if let projects {
                    ProjectsView(library: projects)
                        .onAppear {
                            projects.openMeeting = { [weak router] id in router?.open(meetingID: id, at: nil) }
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
                            MeetingListView(library: library, selection: $router.selection)
                        }
                    }
                    .frame(width: 300)
                    Divider()
                    Group {
                        if let id = router.selection, let row = library.rows.first(where: { $0.id == id }) {
                            MeetingDetailView(row: row, store: library.store, paths: paths, transcripts: library.transcripts,
                                              projects: projects?.projects ?? [],
                                              queue: library.queue, summaries: library.summaries, summaryUnavailable: library.summaryUnavailable,
                                              job: library.jobs[row.id], meetingActive: library.meetingActive,
                                              router: router)
                                .id(id)
                        } else {
                            ContentUnavailableView("Aucune réunion choisie", systemImage: "waveform",
                                                   description: Text("Choisis une réunion dans la liste."))
                        }
                    }
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                }
                .windowTitle("Réunions", subtitle: router.selection.flatMap { id in library.rows.first { $0.id == id }?.title } ?? "")
                .searchable(text: $router.query, placement: .toolbar, prompt: "Chercher dans les transcriptions")
            case .settings:
                SettingsPage(tab: $router.settingsTab, updates: updates, projects: projects, agenda: agenda) {
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

struct MeetingListView: View {
    @ObservedObject var library: MeetingLibrary
    @Binding var selection: UUID?

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
                                MeetingRowView(row: row, now: context.date, badge: TranscriptModel.badge(library.jobs[row.id])).tag(row.id)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct MeetingRowView: View {
    let row: MeetingRow
    let now: Date
    var badge: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.body.weight(.medium)).lineLimit(1)
                Text("\(row.startedAt.formatted(date: .omitted, time: .shortened)) · \(MeetingListModel.durationText(row, now: now))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if row.status.isUnfinished {
                Badge(text: "En cours", color: .red)
            } else if row.status == .interrupted {
                Badge(text: "Interrompue", color: .orange)
            }
            if let badge, !row.status.isUnfinished {
                Badge(text: badge, color: badge == "Échec" || badge == "À vérifier" ? .orange : .secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}
