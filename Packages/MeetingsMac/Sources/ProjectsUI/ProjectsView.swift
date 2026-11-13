import Domain
import Persistence
import SwiftUI
import VaultImport

public enum ProjectsMode: String, CaseIterable, Identifiable, Sendable {
    case board = "Kanban"
    case all = "Tous"
    case table = "Tableau"
    case handIn = "À rendre"
    case watch = "À surveiller"

    public var id: String { rawValue }
}

/// The « Projets » section: the views of `Projets.base`, the page of a project, the import.
public struct ProjectsView: View {
    @ObservedObject var library: ProjectLibrary
    @State private var mode: ProjectsMode = .board
    /// What the vault holds, read before anything is replaced (review, minor 10).
    @State private var pending: VaultSnapshot?
    @State private var reading = false
    @State private var importAfterChoosing = false
    @State private var choosingVault = false
    @State private var report: String?
    @State private var importError: String?

    public init(library: ProjectLibrary) {
        self.library = library
    }

    public var body: some View {
        Group {
            if !library.loaded {
                ProgressView()
            } else if let project = library.project(library.selected) {
                ProjectPage(project: project, library: library).id(project.id)
            } else if library.projects.isEmpty {
                ContentUnavailableView {
                    Label("Aucun projet", systemImage: "square.grid.3x2")
                } description: {
                    Text("Ramène tes projets d'Obsidian : l'app lit ton coffre, sans jamais y écrire.")
                } actions: {
                    Button("Importer depuis Obsidian") { startImport() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(reading)
                }
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Picker("Vue", selection: $mode) {
                            ForEach(ProjectsMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        Spacer(minLength: 8)
                        Menu {
                            Button("Importer depuis Obsidian…") { startImport() }
                            Button("Choisir le dossier du coffre…") { choosingVault = true }
                        } label: { Image(systemName: "ellipsis.circle") }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    Divider()
                    switch mode {
                    case .board: BoardView(library: library, includeDone: false)
                    case .all: BoardView(library: library, includeDone: true)
                    case .table: AllProjectsTable(library: library)
                    case .handIn: HandInTable(library: library)
                    case .watch: WatchTable(library: library)
                    }
                }
            }
        }
        .overlay {
            if reading {
                ProgressView("Lecture du coffre…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .confirmationDialog(
            "Remplacer les \(library.projects.count) projets de l'app par les \(pending?.projects.count ?? 0) du coffre ?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
        ) {
            Button("Remplacer", role: .destructive) { if let pending { apply(pending) } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Ce qui a été modifié dans l'app sera perdu, y compris les actions, notes et journaux écrits par Claude Code. Obsidian n'est pas touché.")
        }
        .fileImporter(isPresented: $choosingVault, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                library.vaultPath = url.path(percentEncoded: false)
                if importAfterChoosing { startImport() }
            }
            importAfterChoosing = false
        }
        .alert("Import terminé", isPresented: Binding(get: { report != nil }, set: { if !$0 { report = nil } })) {
            Button("OK") {}
        } message: { Text(report ?? "") }
        .alert("L'import n'a pas pu se faire", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("Choisir le dossier du coffre…") { choosingVault = true }
            Button("OK", role: .cancel) {}
        } message: { Text(importError ?? "") }
    }

    private func startImport() {
        // The first time, the vault's folder is chosen; the import starts right after.
        guard library.vaultPath != nil else {
            choosingVault = true
            importAfterChoosing = true
            return
        }
        reading = true
        Task {
            defer { reading = false }
            do {
                let snapshot = try await library.readVault()
                if snapshot.projects.isEmpty {
                    importError = "\(ImportError.emptyVault)"
                } else if library.projects.isEmpty {
                    apply(snapshot)
                } else {
                    pending = snapshot
                }
            } catch {
                importError = "\(error)"
            }
        }
    }

    private func apply(_ snapshot: VaultSnapshot) {
        do {
            let result = try library.apply(snapshot)
            report = ([result.summary] + result.warnings).joined(separator: "\n")
        } catch {
            importError = "\(error)"
        }
    }
}
