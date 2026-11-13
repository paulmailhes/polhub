import Domain
import Persistence
import ProjectsUI
import SwiftUI
import Updates

public enum SidebarItem: String, Hashable, Sendable {
    case projects, meetings, journal, diagnostic, settings
}

/// Where the window is: the app sets it to open a meeting from the menu.
@MainActor
public final class WindowRouter: ObservableObject {
    @Published public var section: SidebarItem = .projects
    @Published public var selection: UUID?
    /// A moment to play in the selected meeting, asked by the search.
    @Published public var seekRequest: (meetingID: UUID, seconds: Double)?
    @Published public var query = ""

    public init() {}

    public func open(meetingID: UUID, at seconds: Double?) {
        section = .meetings
        selection = meetingID
        seekRequest = seconds.map { (meetingID, $0) }
    }
}

/// Transcriptor's window: the meetings, the journal, and (step 1, task 13) the diagnostic.
public struct MainWindowView<Diagnostic: View>: View {
    /// The sidebar, the 300-point list and a detail of 360 points at least.
    public static var minimumWidth: CGFloat { 860 }

    @ObservedObject var library: MeetingLibrary
    let projects: ProjectLibrary?
    let updates: UpdateService?
    @ObservedObject var router: WindowRouter
    let paths: AppPaths
    let diagnostic: Diagnostic

    public init(
        library: MeetingLibrary, projects: ProjectLibrary? = nil, updates: UpdateService? = nil, router: WindowRouter, paths: AppPaths,
        @ViewBuilder diagnostic: () -> Diagnostic
    ) {
        self.library = library
        self.projects = projects
        self.updates = updates
        self.router = router
        self.paths = paths
        self.diagnostic = diagnostic()
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $router.section) {
                if projects != nil {
                    Label("Projets", systemImage: "square.grid.3x2").tag(SidebarItem.projects)
                }
                Label("Réunions", systemImage: "waveform").tag(SidebarItem.meetings)
                Label("Journal", systemImage: "list.bullet.rectangle").tag(SidebarItem.journal)
                if Diagnostic.self != EmptyView.self {
                    Label("Diagnostic", systemImage: "stethoscope").tag(SidebarItem.diagnostic)
                }
                if updates != nil {
                    Label("Réglages", systemImage: "gearshape").tag(SidebarItem.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch router.section {
            case .projects:
                if let projects {
                    ProjectsView(library: projects)
                        .onAppear { projects.openMeeting = { [weak router] id in router?.open(meetingID: id, at: nil) } }
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
                                              queue: library.queue, job: library.jobs[row.id], meetingActive: library.meetingActive,
                                              router: router)
                                .id(id)
                        } else {
                            ContentUnavailableView("Aucune réunion choisie", systemImage: "waveform",
                                                   description: Text("Choisis une réunion dans la liste."))
                        }
                    }
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                }
            case .journal:
                JournalView(entries: library.journal)
            case .diagnostic:
                diagnostic
            case .settings:
                if let updates {
                    SettingsView(updates: updates, projects: projects)
                }
            }
        }
        .frame(minWidth: Self.minimumWidth, minHeight: 520)
        .searchable(text: $router.query, placement: .toolbar, prompt: "Chercher dans les transcriptions")
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
