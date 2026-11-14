import Agenda
import PolhubDesign
import ProjectsUI
import SwiftUI
import Updates

/// Réglages, as Apple's (Paul, 14/11): the families first; each is entered, with a way back. Every new feature
/// puts its settings in its family (docs/design-system.md).
struct SettingsPage<Diagnostic: View, Journal: View>: View {
    @ObservedObject var router: WindowRouter
    let updates: UpdateService?
    let projects: ProjectLibrary?
    let agenda: AgendaLibrary?
    @ObservedObject var library: MeetingLibrary
    let diagnostic: Diagnostic
    let journal: Journal

    init(router: WindowRouter, updates: UpdateService?, projects: ProjectLibrary?, agenda: AgendaLibrary? = nil, library: MeetingLibrary,
         @ViewBuilder diagnostic: () -> Diagnostic, @ViewBuilder journal: () -> Journal) {
        self.router = router
        self.updates = updates
        self.projects = projects
        self.agenda = agenda
        self.library = library
        self.diagnostic = diagnostic()
        self.journal = journal()
    }

    var body: some View {
        Group {
            if let pane = router.settingsPane {
                content(pane)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button { router.settingsPane = nil } label: { Label("Réglages", systemImage: "chevron.left") }
                                .help("Revenir aux réglages")
                        }
                    }
                    .windowTitle(pane.title, subtitle: "Réglages")
            } else {
                families.windowTitle("Réglages")
            }
        }
    }

    private var families: some View {
        Form {
            ForEach(Array(SettingsPane.families(hasAgenda: agenda != nil, hasProjects: projects != nil).enumerated()), id: \.offset) { _, group in
                Section {
                    ForEach(group, id: \.self) { pane in
                        Button { router.settingsPane = pane } label: { SettingsRow(pane: pane) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func content(_ pane: SettingsPane) -> some View {
        switch pane {
        case .calendar:
            if let agenda { CalendarSettingsPane(agenda: agenda) }
        case .projects:
            ProjectsSettingsPane()
        case .meetings:
            MeetingsSettingsPane(library: library)
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
        }
    }
}

/// A family of Réglages: its icon in a colored square, its name, what it holds.
struct SettingsRow: View {
    let pane: SettingsPane

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: pane.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color(hex: pane.tint), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(pane.title)
                Text(pane.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// Réglages › Projets.
struct ProjectsSettingsPane: View {
    @AppStorage(Preferences.Key.cardSize) private var cardSize = CardSize.medium.rawValue

    var body: some View {
        Form {
            Section("Kanban") {
                Picker("Taille des cartes", selection: $cardSize) {
                    ForEach(CardSize.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640)
    }
}

/// Réglages › Réunions.
struct MeetingsSettingsPane: View {
    @ObservedObject var library: MeetingLibrary
    @AppStorage(Preferences.Key.summariesEnabled) private var summaries = true
    @AppStorage(Preferences.Key.transcriptionLanguage) private var language = Preferences.Default.transcriptionLanguage

    var body: some View {
        Form {
            Section {
                Toggle("Comptes rendus automatiques", isOn: $summaries)
                Text(library.summaryUnavailable ?? "Écrits sur le Mac par le modèle d'Apple, après la transcription, jamais pendant une réunion.")
                    .font(.caption).foregroundStyle(library.summaryUnavailable == nil ? Color.secondary : .orange)
            }
            Section("Transcription") {
                Picker("Langue des réunions", selection: $language) {
                    Text("Français").tag("fr")
                    Text("Anglais").tag("en")
                    Text("Détectée par le moteur").tag("auto")
                }
                Text("Pour les prochaines réunions ; « Retranscrire », dans une réunion, en change une seule.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640)
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

