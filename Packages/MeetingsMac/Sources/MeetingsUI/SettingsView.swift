import AppKit
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
    let mails: MailLibrary?
    private var hasMails: Bool { mails != nil }
    @ObservedObject var library: MeetingLibrary
    let notifications: NotificationHub?
    let startup: StartupControl?
    let diagnostic: Diagnostic
    let journal: Journal

    init(router: WindowRouter, updates: UpdateService?, projects: ProjectLibrary?, agenda: AgendaLibrary? = nil, mails: MailLibrary? = nil, library: MeetingLibrary,
         notifications: NotificationHub? = nil, startup: StartupControl? = nil,
         @ViewBuilder diagnostic: () -> Diagnostic, @ViewBuilder journal: () -> Journal) {
        self.notifications = notifications
        self.startup = startup
        self.router = router
        self.updates = updates
        self.projects = projects
        self.agenda = agenda
        self.mails = mails
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
            ForEach(Array(SettingsPane.families(hasAgenda: agenda != nil, hasProjects: projects != nil, hasMails: hasMails).enumerated()), id: \.offset) { _, group in
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
        case .general:
            GeneralSettingsPane(startup: startup)
        case .notifications:
            NotificationsSettingsPane(hub: notifications)
        case .accounts:
            if let agenda { AccountsSettingsPane(agenda: agenda) }
        case .calendar:
            if let agenda { CalendarSettingsPane(agenda: agenda) }
        case .mails:
            MailSettingsPane(mails: mails)
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

/// Réglages › Général.
struct GeneralSettingsPane: View {
    let startup: StartupControl?
    @AppStorage(Preferences.Key.floatingPages) private var floating = true

    var body: some View {
        Form {
            Section {
                if let startup {
                    StartupToggle(startup: startup)
                } else {
                    Text("La version de développement ne s'ouvre pas à la session.").foregroundStyle(.secondary)
                }
            } footer: {
                Text("Polhub reste dans la barre des menus quand sa fenêtre est fermée : les réunions s'enregistrent et les notifications arrivent. Il se relance aussi tout seul s'il s'arrête.")
            }
            Section {
                Picker("Ouvrir un mail ou un projet", selection: $floating) {
                    Text("En fenêtre flottante").tag(true)
                    Text("En pleine page").tag(false)
                }
            } footer: {
                Text("En fenêtre flottante, la liste reste visible derrière ; Échap ou un clic à côté la referme.")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640)
    }
}

struct StartupToggle: View {
    @ObservedObject var startup: StartupControl
    @State private var confirmingOff = false
    @State private var confirmingOn = false

    var body: some View {
        // The dialogs hang on the switch itself (review of 14/11: on an EmptyView in a Form they never showed).
        Toggle("Ouvrir Polhub à l'ouverture de session", isOn: Binding(get: { startup.isOn }, set: { on in
            guard startup.canChange() else { return }
            if on {
                if startup.handsOver { confirmingOn = true } else { startup.set(true) }
            } else {
                confirmingOff = true
            }
        }))
        .confirmationDialog("Ne plus ouvrir Polhub à l'ouverture de session ?", isPresented: $confirmingOff) {
            Button("Ne plus l'ouvrir", role: .destructive) { startup.set(false) }
        } message: {
            Text("Polhub se ferme aussitôt et ne se relance plus seul après un arrêt : les réunions ne s'enregistrent que s'il est ouvert. Tu le rouvres depuis Applications.")
        }
        .confirmationDialog("Ouvrir Polhub à l'ouverture de session ?", isPresented: $confirmingOn) {
            Button("Ouvrir à la session") { startup.set(true) }
        } message: {
            Text("macOS prend Polhub sous sa garde : cette fenêtre se ferme, rouvre-la par l'icône de la barre des menus.")
        }
        if let message = startup.message { Text(message).font(.caption).foregroundStyle(.orange) }
    }
}

/// Réglages › Notifications (Paul, 14/11): what Polhub announces, and when. Mails and other kinds will join here.
struct NotificationsSettingsPane: View {
    let hub: NotificationHub?
    @AppStorage(Preferences.Key.reminders) private var reminders = true
    @AppStorage(Preferences.Key.reminderMinutes) private var minutesText = Preferences.Default.reminderMinutes
    @AppStorage(Preferences.Key.remindersMeetOnly) private var meetOnly = false
    @AppStorage(Preferences.Key.newEvents) private var newEvents = true
    @AppStorage(Preferences.Key.unrecorded) private var unrecorded = true
    @AppStorage(Preferences.Key.summaryReady) private var summaryReady = true
    @AppStorage(Preferences.Key.mailNotices) private var mailNotices = true
    @AppStorage(Preferences.Key.mailNoticesProjects) private var mailNoticesProjects = false
    @AppStorage(Preferences.Key.sound) private var sound = true

    var body: some View {
        Form {
            Section {
                Toggle("Rappels avant un rendez-vous", isOn: $reminders)
                if reminders {
                    LabeledContent("Quand") {
                        HStack(spacing: Space.xs) {
                            ForEach(Preferences.Default.reminderChoices, id: \.self) { minute in
                                let on = Preferences.minutes(minutesText).contains(minute)
                                if on {
                                    Button("\(minute) min") { toggle(minute) }.buttonStyle(.borderedProminent)
                                } else {
                                    Button("\(minute) min") { toggle(minute) }.buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                    Toggle("Seulement les rendez-vous avec une visio", isOn: $meetOnly)
                }
            } header: {
                Text("Calendrier")
            } footer: {
                Text("Un clic sur un rappel rejoint le Meet avec le bon compte, dans Dia, où la réunion s'enregistre. Les rappels arrivent même si Polhub est fermé.")
            }
            Section {
                Toggle("Nouveau rendez-vous dans tes agendas", isOn: $newEvents)
                Toggle("Réunion de l'agenda commencée sans enregistrement", isOn: $unrecorded)
            } footer: {
                Text("Cinq minutes après le début d'un rendez-vous avec Meet, si rien n'enregistre : de quoi ne rater aucune réunion.")
            }
            Section("Réunions") {
                Toggle("Compte rendu prêt", isOn: $summaryReady)
            }
            Section {
                Toggle("Nouveau mail dans l'onglet Personnes", isOn: $mailNotices)
                if mailNotices { Toggle("Seulement les mails de tes projets", isOn: $mailNoticesProjects) }
            } header: {
                Text("Mails")
            } footer: {
                Text("Jamais pour l'onglet Notifications (services, lettres d'information), ni pendant la première lecture d'une boîte. Un clic ouvre le fil.")
            }
            Section {
                Toggle("Son", isOn: $sound)
                if let hub { NotificationStatus(hub: hub) }
            } footer: {
                Text("Bientôt ici : les échéances des projets, le résumé du matin.")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640)
        .onChange(of: [reminders, meetOnly, sound]) { _, _ in replan() }
        .onChange(of: minutesText) { _, _ in replan() }
    }

    private func toggle(_ minute: Int) {
        var minutes = Set(Preferences.minutes(minutesText))
        if minutes.contains(minute) { minutes.remove(minute) } else { minutes.insert(minute) }
        minutesText = Preferences.minutesText(Array(minutes))
    }

    private func replan() {
        guard let hub else { return }
        Task { await hub.refresh() }
    }
}

struct NotificationStatus: View {
    @ObservedObject var hub: NotificationHub

    var body: some View {
        HStack {
            Text("Notifications \(hub.authorization.isEmpty ? "…" : hub.authorization)").foregroundStyle(.secondary)
            Spacer()
            if hub.authorization.hasPrefix("refusées") {
                Button("Ouvrir Réglages Système") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                }
            }
            Button("Envoyer un essai") { Task { await hub.test() } }
        }
        .task { await hub.readAuthorization() }
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

