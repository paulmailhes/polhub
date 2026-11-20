import Domain
import Persistence
import PolhubDesign
import SwiftUI

/// Paul keeps the Kanban and a list he can sort and search (14/11).
public enum ProjectsMode: String, CaseIterable, Identifiable, Sendable {
    case board = "Kanban"
    case list = "Liste"

    public var id: String { rawValue }
}

/// The « Projets » section: the Kanban, the list, the page of a project, the creation window.
public struct ProjectsView: View {
    @ObservedObject var library: ProjectLibrary
    @State private var mode: ProjectsMode = .board
    @State private var query = ""
    /// The status of the column whose « + » was clicked; the creation window is open while it is set.
    @State private var creating: ProjectStatus?
    /// A project opens over the board, which stays in sight (Réglages › Général, 14/11).
    @AppStorage(Preferences.Key.floatingPages) private var floating = true

    public init(library: ProjectLibrary) {
        self.library = library
    }

    public var body: some View {
        Group {
            if !library.loaded {
                ProgressView()
            } else if !floating, let project = library.project(library.selected) {
                ProjectPage(project: project, library: library).id(project.id)
            } else if library.projects.isEmpty {
                ContentUnavailableView {
                    Label("Aucun projet", systemImage: "square.grid.3x2")
                } description: {
                    // « kanban » in a sentence, the French typography laid (lot 10, 20/11).
                    Text(Words.typeset("Crée ton premier projet : il prendra place dans le kanban."))
                } actions: {
                    // The screen's one action: the principal button, no glass in the content (design system v2, 19/11); a verb,
                    // as the « + » says it (lot 10, 20/11).
                    Button("Créer un projet") { creating = .priorite1 }
                        .buttonStyle(.primary)
                        .controlSize(.large)
                }
            } else {
                let shown = ProjectViews.matching(library.projects, query)
                Group {
                    switch mode {
                    case .board: BoardView(library: library, projects: shown) { creating = $0 }
                    case .list: ProjectListView(library: library, projects: shown)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker("Vue", selection: $mode) {
                            ForEach(ProjectsMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    ToolbarItem(placement: .primaryAction) {
                        // A verb and its object, and ⌘N, which does the same (`WindowKeys`) (lot 10, 20/11).
                        Button { creating = .priorite1 } label: { Label("Créer un projet", systemImage: "plus") }
                            .help(Words.help("Créer un projet", .command("n")))
                    }
                }
                .searchable(text: $query, placement: .toolbar, prompt: "Chercher un projet")
            }
        }
        .overlay {
            if floating, let project = library.project(library.selected) {
                // ✕, Échap and a click beside go back where the project was opened from (lot 4, 19/11).
                FloatingPanel(close: library.closePage) {
                    ProjectPage(project: project, library: library, close: library.closePage).id(project.id)
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: library.selected)
        // The sidebar's word; never the project's name, written large in its page (lot 4, 19/11).
        .windowTitle("Projets")
        // ⌘N, as the « + » (lot 4, 19/11).
        .onChange(of: library.newRequest) { _, request in
            guard request != nil else { return }
            library.newRequest = nil
            creating = .priorite1
        }
        .sheet(item: $creating) { status in
            NewProjectSheet(status: status) { draft in
                if let project = library.create(draft) { library.selected = project.id }
            }
        }
    }
}

extension ProjectStatus: @retroactive Identifiable {
    public var id: String { rawValue }
}
