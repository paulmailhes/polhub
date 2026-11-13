import ProjectsUI
import SwiftUI
import Updates

/// Réglages : a row of tabs, then the updates, the diagnostic, the journal or the vault.
struct SettingsPage<Diagnostic: View, Journal: View>: View {
    @Binding var tab: SettingsTab
    let updates: UpdateService?
    let projects: ProjectLibrary?
    let diagnostic: Diagnostic
    let journal: Journal

    init(tab: Binding<SettingsTab>, updates: UpdateService?, projects: ProjectLibrary?,
         @ViewBuilder diagnostic: () -> Diagnostic, @ViewBuilder journal: () -> Journal) {
        _tab = tab
        self.updates = updates
        self.projects = projects
        self.diagnostic = diagnostic()
        self.journal = journal()
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Réglages", selection: $tab) {
                ForEach(SettingsTab.visible(hasProjects: projects != nil), id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(12)
            Divider()
            Group {
                switch tab {
                case .updates:
                    if let updates {
                        UpdatesSettingsView(updates: updates)
                    } else {
                        ContentUnavailableView("Pas de mise à jour", systemImage: "arrow.down.circle",
                                               description: Text("La version de développement ne se met jamais à jour."))
                    }
                case .diagnostic:
                    diagnostic
                case .journal:
                    journal
                case .projects:
                    if let projects { VaultSettingsView(projects: projects) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

/// Réglages › Mises à jour.
struct UpdatesSettingsView: View {
    @ObservedObject var updates: UpdateService

    var body: some View {
        Form {
            Section {
                LabeledContent("Version installée", value: updates.current.description)
                LabeledContent("Dernière vérification", value: updates.lastCheck.map {
                    $0.formatted(date: .abbreviated, time: .shortened)
                } ?? "pas encore")
                Toggle("Installer automatiquement les mises à jour", isOn: $updates.autoInstall)
                Text("Jamais pendant une réunion ni une transcription : elle attend que tout soit au repos.")
                    .font(.caption).foregroundStyle(.secondary)
                if let text = UpdateService.text(updates.state) {
                    Text(text).foregroundStyle(stateColor)
                }
                HStack {
                    Button("Vérifier maintenant") { Task { await updates.check() } }
                    if let latest = updates.latest {
                        Button("Mettre à jour vers \(latest.version.description)") { Task { await updates.installNow() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
                if updates.newer.isEmpty, updates.lastCheck != nil, updates.state == .idle {
                    Text("Polhub est à jour.").foregroundStyle(.secondary)
                }
                ForEach(updates.newer, id: \.version) { release in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Version \(release.version.description)").font(.headline)
                        Text(release.notes.isEmpty ? "Pas de description." : release.notes)
                            .font(.callout).textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640)
    }

    private var stateColor: Color {
        if case .failed = updates.state { return .orange }
        return .secondary
    }
}

/// Réglages › Projets : the vault the projects are imported from.
struct VaultSettingsView: View {
    let projects: ProjectLibrary
    @State private var choosingVault = false
    @State private var vaultPath: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Coffre Obsidian", value: vaultPath ?? "pas encore choisi")
                Button("Choisir le dossier du coffre…") { choosingVault = true }
                Text("L'import lit ce dossier sans jamais y écrire.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640)
        .onAppear { vaultPath = projects.vaultPath }
        .fileImporter(isPresented: $choosingVault, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                projects.vaultPath = url.path(percentEncoded: false)
                vaultPath = projects.vaultPath
            }
        }
    }
}
