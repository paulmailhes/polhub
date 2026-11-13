import ProjectsUI
import SwiftUI
import Updates

/// Réglages : the updates, and the vault the projects are imported from.
struct SettingsView: View {
    @ObservedObject var updates: UpdateService
    let projects: ProjectLibrary?
    @State private var choosingVault = false
    @State private var vaultPath: String?

    var body: some View {
        Form {
            Section("Mises à jour") {
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
                    Text("Transcriptor est à jour.").foregroundStyle(.secondary)
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
            if let projects {
                Section("Projets") {
                    LabeledContent("Coffre Obsidian", value: vaultPath ?? "pas encore choisi")
                    Button("Choisir le dossier du coffre…") { choosingVault = true }
                    Text("L'import lit ce dossier sans jamais y écrire.").font(.caption).foregroundStyle(.secondary)
                }
                .onAppear { vaultPath = projects.vaultPath }
                .fileImporter(isPresented: $choosingVault, allowedContentTypes: [.folder]) { result in
                    if case .success(let url) = result {
                        projects.vaultPath = url.path(percentEncoded: false)
                        vaultPath = projects.vaultPath
                    }
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
