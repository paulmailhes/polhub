import AppKit
import Agenda
import Notifications
import PolhubDesign
import ProjectsUI
import SwiftUI
import Updates

/// Réglages, as Apple's (Paul, 14/11): the families first; each is entered, with a way back. Every new feature
/// puts its settings in its family (docs/design-system.md). Lot 7 (19/11): the families in the sidebar's order, one
/// width (640) for every page, each under the toolbar.
struct SettingsPage<Diagnostic: View, Journal: View>: View {
    @ObservedObject var router: WindowRouter
    let updates: UpdateService?
    let projects: ProjectLibrary?
    let agenda: AgendaLibrary?
    let mails: MailLibrary?
    let inspiration: InspirationLibrary?
    private var hasMails: Bool { mails != nil }
    @ObservedObject var library: MeetingLibrary
    let notifications: NotificationHub?
    let startup: StartupControl?
    /// Colin's bar and the account of his probe (18/11), for Réglages › Colin.
    let colinThread: ColinThread?
    let colinProbe: ColinProbeControl?
    let diagnostic: Diagnostic
    let journal: Journal

    init(router: WindowRouter, updates: UpdateService?, projects: ProjectLibrary?, agenda: AgendaLibrary? = nil, mails: MailLibrary? = nil,
         inspiration: InspirationLibrary? = nil, library: MeetingLibrary,
         notifications: NotificationHub? = nil, startup: StartupControl? = nil, colinThread: ColinThread? = nil, colinProbe: ColinProbeControl? = nil,
         @ViewBuilder diagnostic: () -> Diagnostic, @ViewBuilder journal: () -> Journal) {
        self.colinThread = colinThread
        self.colinProbe = colinProbe
        self.notifications = notifications
        self.startup = startup
        self.router = router
        self.updates = updates
        self.projects = projects
        self.agenda = agenda
        self.mails = mails
        self.inspiration = inspiration
        self.library = library
        self.diagnostic = diagnostic()
        self.journal = journal()
    }

    var body: some View {
        Group {
            if let pane = router.settingsPane {
                content(pane)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    // Under the toolbar, as every page (lot 7, 19/11): touching it, the form drew a box of its own width there.
                    .belowToolbar()
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            // Back where the family was opened from: the families, or Mails for « Réglages des mails… »
                            // (lot 4, 19/11); a line of Général, back on Général (lot 7, 19/11).
                            Button { router.closeSettings() } label: { Label("Réglages", systemImage: "chevron.left") }
                                .help(router.returnHelp)
                        }
                    }
                    .onExitCommand { router.closeSettings() }
                    // The sidebar's word, then the family: where Paul is in it (lot 4, 19/11).
                    .windowTitle("Réglages", subtitle: pane.title)
            } else {
                families.windowTitle("Réglages")
            }
        }
        // The Diagnostic's relaunch goes through Général's switch, and its guards (lot 7, 19/11).
        .environment(\.startupControl, startup)
    }

    private var families: some View {
        Form {
            ForEach(Array(SettingsPane.families(hasAgenda: agenda != nil, hasProjects: projects != nil, hasMails: hasMails,
                                                             hasInspiration: inspiration != nil).enumerated()), id: \.offset) { _, group in
                Section {
                    ForEach(group, id: \.self) { pane in
                        Button { router.settingsPane = pane } label: { SettingsRow(pane: pane) }
                            .buttonStyle(.row(radius: Radius.control, inset: Space.s))
                    }
                }
            }
        }
        .settingsForm()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .belowToolbar()
    }

    @ViewBuilder
    private func content(_ pane: SettingsPane) -> some View {
        switch pane {
        case .general:
            GeneralSettingsPane(startup: startup) { router.settingsPane = $0 }
        case .notifications:
            NotificationsSettingsPane(hub: notifications)
        case .accounts:
            if let agenda { AccountsSettingsPane(agenda: agenda) }
        case .calendar:
            if let agenda { CalendarSettingsPane(agenda: agenda) }
        case .mails:
            MailSettingsPane(mails: mails)
        case .colin:
            ColinSettingsPane(thread: colinThread, probe: colinProbe)
        case .projects:
            ProjectsSettingsPane()
        case .meetings:
            MeetingsSettingsPane(library: library)
        case .inspiration:
            if let inspiration { InspirationSettingsPane(library: inspiration, router: router) }
        case .updates:
            if let updates {
                UpdatesSettingsView(updates: updates)
            } else {
                // An empty state says « Aucun … » (lot 10, 20/11).
                ContentUnavailableView("Aucune mise à jour", systemImage: "arrow.down.circle",
                                       description: Text("La version de développement ne se met jamais à jour."))
            }
        case .diagnostic:
            diagnostic.frame(maxWidth: SettingsMetrics.width)
        case .journal:
            journal.frame(maxWidth: SettingsMetrics.width)
        }
    }
}

extension WindowRouter {
    /// The ‹ and Échap of a page of Réglages (lot 7, 19/11). A line of Général (the Diagnostic, the Journal) goes one step
    /// back, where it was opened from: Général, or the page that asked for the Diagnostic; opened first thing (the first
    /// launch), Général. A family goes back where it was opened from (`close()`), the families at the least.
    func closeSettings() {
        if let parent = settingsPane?.parent {
            if canGoBack { goBack() } else { settingsPane = parent }
            return
        }
        if !close() { settingsPane = nil }
    }
}

extension EnvironmentValues {
    /// The relaunch's control, for the Diagnostic's line (lot 7, 19/11): the same switch and the same guards as Général's.
    @Entry var startupControl: StartupControl? = nil
}

/// A family of Réglages: its icon in a colored square, its name, what it holds.
struct SettingsRow: View {
    let pane: SettingsPane

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: pane.icon)
                .font(.meta.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color(hex: pane.tint), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(pane.title).font(.rowBody.weight(.medium))
                Text(pane.subtitle).font(.meta).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, Space.xs)
        .contentShape(Rectangle())
    }
}

/// The words of Réglages' pages (lot 7, 19/11): a help of one line under each setting that needs one, the long detail
/// behind « ⓘ ». Colin, Mails, Inspiration and Projets keep theirs beside their page.
enum SettingsText {
    // Général
    static let startup = "Ouvrir Polhub à l'ouverture de session"
    static let startupHelp = "Il se relance aussi tout seul s'il s'arrête."
    static let startupDetail = "Polhub reste dans la barre des menus quand sa fenêtre est fermée : les réunions s'enregistrent et les notifications arrivent."
    static let floating = "Ouvrir un mail ou un projet"
    static let floatingHelp = "En fenêtre flottante, la liste reste visible derrière."
    // « Visio »: a rendez-vous with a Google Meet link, never « un Meet » (lot 10, 20/11).
    static let meetMinutes = "Minutes avant une visio dans la barre des menus"
    static let meetMinutesHelp = "« 8 min » à côté du logo, dans le quart d'heure avant une visio."

    // Notifications
    static let reminders = "Rappels avant un rendez-vous"
    static let remindersHelp = "Un clic sur un rappel rejoint la visio avec le bon compte."
    static let remindersDetail = "La visio s'ouvre dans Dia, où la réunion s'enregistre. Les rappels arrivent même si Polhub est fermé."
    static let card = "Carte qui reste à l'écran avant une visio"
    static let cardHelp = "En haut à droite, jusqu'à ce que tu rejoignes ou la fermes, dix minutes après le début au plus."
    static let unrecorded = "Visio commencée sans enregistrement"
    static let unrecordedHelp = "Cinq minutes après le début d'une visio, si rien n'enregistre."
    static let mailNotices = "Nouveau mail dans la Boîte de réception"
    static let mailNoticesHelp = "Jamais pour le dossier Notifications, ni pendant la première lecture d'une boîte."
    static let draftReady = "Un brouillon est prêt"
    static let draftReadyHelp = "Quand un agent a préparé un mail ; un clic ouvre l'Accueil, sur le brouillon à relire."

    // Réunions
    static let summaries = "Comptes rendus automatiques"
    // « L'IA d'Apple », never « le modèle » (lot 10, 20/11).
    static let summariesHelp = "Écrits sur le Mac par l'IA d'Apple, après la transcription, jamais pendant une réunion."
    static let language = "Langue des réunions"
    static let languageHelp = "Pour les prochaines réunions ; « Retranscrire » en change une seule."

    // Mises à jour
    static let autoInstall = "Installer automatiquement les mises à jour"
    static let autoInstallHelp = "Jamais pendant une réunion ni une transcription : elle attend que tout soit au repos."

    // Calendrier
    // « Google Meet » names the service (lot 10, 20/11).
    static let eventMeetHelp = "Chaque nouveau rendez-vous reçoit un lien Google Meet."
    static let dayStartHelp = "La semaine s'ouvre sur cette heure."
    static let tomorrowHelp = "Une fois fini ton dernier rendez-vous du jour."

    // Comptes Google
    static let colorHelp = "La couleur d'un compte marque ses rendez-vous dans le Calendrier et l'Accueil."
    static let mailGrantDetail = "« Autoriser les mails » ouvre la page de Google ; l'agenda du compte reste connecté quoi que tu répondes."
    /// Each color of an account by its name, the swatch's bubble and VoiceOver's word, as a project's (lot 10, 20/11:
    /// « Prendre cette couleur » and « Couleur 3 sur 8 » before).
    static let accountColors: [String: String] = Dictionary([
        (AccountStyle.violet, "Violet"), (AccountStyle.green, "Vert"), (AccountStyle.orange, "Orange"), (AccountStyle.blue, "Bleu"),
        (AccountStyle.pink, "Rose"), (AccountStyle.teal, "Sarcelle"), (AccountStyle.red, "Rouge"), (AccountStyle.gray, "Gris"),
    ], uniquingKeysWith: { first, _ in first })

    /// Every help of these pages, for their test: one line each, two on screen at most.
    static let helps = [startupHelp, floatingHelp, meetMinutesHelp, remindersHelp, cardHelp, unrecordedHelp, mailNoticesHelp, draftReadyHelp,
                        summariesHelp, languageHelp, autoInstallHelp, eventMeetHelp, dayStartHelp, tomorrowHelp, colorHelp]
    static let details = [startupDetail, remindersDetail, mailGrantDetail]
}

/// Réglages › Général: the session, how a mail or a project opens, the menu bar; then the Diagnostic and the Journal,
/// one line each (lot 7, 19/11: no families of their own any more).
struct GeneralSettingsPane: View {
    let startup: StartupControl?
    /// Opens a line of Général: the Diagnostic, the Journal.
    var open: (SettingsPane) -> Void = { _ in }
    @AppStorage(Preferences.Key.floatingPages) private var floating = true
    @AppStorage(Preferences.Key.menuBarMeetMinutes) private var meetMinutes = true

    var body: some View {
        Form {
            Section {
                if let startup {
                    StartupToggle(startup: startup)
                } else {
                    Text("La version de développement ne s'ouvre pas à la session.").foregroundStyle(.secondary)
                }
                SettingRow(SettingsText.floating, help: SettingsText.floatingHelp) {
                    Picker(SettingsText.floating, selection: $floating) {
                        Text("En fenêtre flottante").tag(true)
                        Text("En pleine page").tag(false)
                    }
                }
                SettingRow(SettingsText.meetMinutes, help: SettingsText.meetMinutesHelp) {
                    Toggle(SettingsText.meetMinutes, isOn: $meetMinutes)
                }
            }
            Section {
                ForEach(SettingsPane.general.lines, id: \.self) { line in
                    Button { open(line) } label: { SettingsRow(pane: line) }
                        .buttonStyle(.row(radius: Radius.control, inset: Space.s))
                }
            }
        }
        .settingsForm()
    }
}

/// « Ouvrir Polhub à l'ouverture de session », in Général: its help, and what holds it back (`ErrorLine`) in its place.
struct StartupToggle: View {
    @ObservedObject var startup: StartupControl

    var body: some View {
        SettingRow(SettingsText.startup, help: SettingsText.startupHelp, detail: SettingsText.startupDetail, problem: startup.message) {
            StartupSwitch(startup: startup, title: SettingsText.startup)
        }
    }
}

/// What a switch of the relaunch gets (lot 7, 19/11): the same answer in Général and in the Diagnostic.
enum StartupAnswer: Equatable {
    /// A meeting is on: the switch waits for its end (`StartupControl.message` says so).
    case wait
    /// Turning it off stops Polhub: asked first.
    case confirmOff
    /// Turning it on hands this copy over to macOS, whose window closes: asked first.
    case confirmOn
    /// Done at once.
    case done
}

extension StartupControl {
    /// The one way to switch the relaunch (review of 14/11; lot 7, 19/11: the Diagnostic's switch went round it): it waits
    /// for the end of a meeting, asks before stopping Polhub or handing it over, and turns it on at once otherwise.
    func ask(_ on: Bool) -> StartupAnswer {
        guard canChange() else { return .wait }
        if !on { return .confirmOff }
        if handsOver { return .confirmOn }
        set(true)
        return .done
    }
}

/// The switch of the relaunch and its two questions: the same in Général and in the Diagnostic (lot 7, 19/11), so that
/// neither goes round the guards.
struct StartupSwitch: View {
    @ObservedObject var startup: StartupControl
    let title: String
    @State private var confirmingOff = false
    @State private var confirmingOn = false

    var body: some View {
        // The dialogs hang on the switch itself (review of 14/11: on an EmptyView in a Form they never showed).
        Toggle(title, isOn: Binding(get: { startup.isOn }, set: { on in
            switch startup.ask(on) {
            case .confirmOff: confirmingOff = true
            case .confirmOn: confirmingOn = true
            case .wait, .done: break
            }
        }))
        .confirmationDialog("Ne plus ouvrir Polhub à l'ouverture de session ?", isPresented: $confirmingOff) {
            Button("Ne plus l'ouvrir", role: .destructive) { startup.set(false) }
        } message: {
            // French typography, laid at display (lot 10, 20/11).
            Text(Words.typeset("Polhub se ferme aussitôt et ne se relance plus seul après un arrêt : les réunions ne s'enregistrent que s'il est ouvert. Tu le rouvres depuis Applications."))
        }
        .confirmationDialog("Ouvrir Polhub à l'ouverture de session ?", isPresented: $confirmingOn) {
            Button("Ouvrir à la session") { startup.set(true) }
        } message: {
            Text(Words.typeset("macOS prend Polhub sous sa garde : cette fenêtre se ferme, rouvre-la par l'icône de la barre des menus."))
        }
    }
}

/// The minutes of the reminders, in a menu (lot 7, 19/11): « Rappel : 10 min avant ▾ », several ticked at once, in
/// place of a row of pills.
enum ReminderMenu {
    static var choices: [Int] { Preferences.Default.reminderChoices }

    /// « 15 min avant »: the length by `Words` (lot 10, 20/11).
    static func item(_ minute: Int) -> String { Words.duration(minute * 60) + " avant" }

    /// « Rappel : 10 min avant », « Rappels : 30, 10 et 1 min avant », « Rappel : aucun ».
    static func title(_ minutes: [Int]) -> String {
        "\(label(minutes)) : \(value(minutes))"
    }

    /// The row's word: « Rappel », « Rappels » for several, accorded by `Words` (lot 10, 20/11).
    static func label(_ minutes: [Int]) -> String {
        Words.plural(Set(minutes).count, "Rappel")
    }

    /// The menu's word: « 10 min avant », « 30, 10 et 1 min avant », « aucun ».
    static func value(_ minutes: [Int]) -> String {
        let sorted = Array(Set(minutes)).sorted(by: >)
        guard let last = sorted.last else { return "aucun" }
        guard sorted.count > 1 else { return "\(last) min avant" }
        return sorted.dropLast().map(String.init).joined(separator: ", ") + " et \(last) min avant"
    }

    /// The stored minutes with this one ticked, or no longer.
    static func toggled(_ text: String, _ minute: Int) -> String {
        var minutes = Set(Preferences.minutes(text))
        if minutes.contains(minute) { minutes.remove(minute) } else { minutes.insert(minute) }
        return Preferences.minutesText(Array(minutes))
    }
}

/// Réglages › Notifications (Paul, 14/11): what Polhub announces, and when.
struct NotificationsSettingsPane: View {
    let hub: NotificationHub?
    @AppStorage(Preferences.Key.reminders) private var reminders = true
    @AppStorage(Preferences.Key.reminderMinutes) private var minutesText = Preferences.Default.reminderMinutes
    @AppStorage(Preferences.Key.remindersMeetOnly) private var meetOnly = false
    @AppStorage(Preferences.Key.meetingCard) private var meetingCard = true
    @AppStorage(Preferences.Key.meetingCardMinutes) private var meetingCardMinutes = Preferences.Default.meetingCardMinutes
    @AppStorage(Preferences.Key.newEvents) private var newEvents = true
    @AppStorage(Preferences.Key.unrecorded) private var unrecorded = true
    @AppStorage(Preferences.Key.summaryReady) private var summaryReady = true
    @AppStorage(Preferences.Key.mailNotices) private var mailNotices = true
    @AppStorage(Preferences.Key.mailNoticesProjects) private var mailNoticesProjects = false
    @AppStorage(Preferences.Key.colinDraftNotice) private var draftReady = true
    @AppStorage(Preferences.Key.sound) private var sound = true

    var body: some View {
        Form {
            Section {
                SettingRow(SettingsText.reminders, help: SettingsText.remindersHelp, detail: SettingsText.remindersDetail) {
                    Toggle(SettingsText.reminders, isOn: $reminders)
                }
                if reminders {
                    reminderMenu
                    // A visio is a rendez-vous with a Google Meet link: said once (lot 10, 20/11).
                    Toggle("Seulement les visios", isOn: $meetOnly)
                }
                SettingRow(SettingsText.card, help: SettingsText.cardHelp) {
                    Toggle(SettingsText.card, isOn: $meetingCard)
                }
                if meetingCard {
                    Picker("Quand", selection: $meetingCardMinutes) {
                        ForEach(Preferences.Default.meetingCardChoices, id: \.self) { minute in
                            // The length by `Words` (lot 10, 20/11).
                            Text(Words.duration(minute * 60) + " avant").tag(minute)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Calendrier")
            }
            Section {
                Toggle("Nouveau rendez-vous dans tes agendas", isOn: $newEvents)
                SettingRow(SettingsText.unrecorded, help: SettingsText.unrecordedHelp) {
                    Toggle(SettingsText.unrecorded, isOn: $unrecorded)
                }
            }
            Section("Réunions") {
                Toggle("Compte rendu prêt", isOn: $summaryReady)
            }
            Section {
                // The mails' folders, no tabs any more (lot 7, 19/11: « l'onglet Personnes » had gone).
                SettingRow(SettingsText.mailNotices, help: SettingsText.mailNoticesHelp) {
                    Toggle(SettingsText.mailNotices, isOn: $mailNotices)
                }
                if mailNotices { Toggle("Seulement les mails de tes projets", isOn: $mailNoticesProjects) }
            } header: {
                Text("Mails")
            }
            Section {
                SettingRow(SettingsText.draftReady, help: SettingsText.draftReadyHelp) {
                    Toggle(SettingsText.draftReady, isOn: $draftReady)
                }
            } header: {
                Text("Colin")
            }
            Section {
                Toggle("Son", isOn: $sound)
                if let hub { NotificationStatus(hub: hub) }
            }
        }
        .settingsForm()
        .onChange(of: [reminders, meetOnly, sound]) { _, _ in replan() }
        .onChange(of: minutesText) { _, _ in replan() }
    }

    /// « Rappels    10 et 1 min avant ▾ »: each minute ticked in the menu, several at once (lot 7, 19/11), the row read as
    /// the pickers of the page.
    private var reminderMenu: some View {
        let minutes = Preferences.minutes(minutesText)
        return LabeledContent {
            Menu {
                ForEach(ReminderMenu.choices, id: \.self) { minute in
                    Toggle(ReminderMenu.item(minute), isOn: Binding(get: { minutes.contains(minute) },
                                                                    set: { _ in minutesText = ReminderMenu.toggled(minutesText, minute) }))
                }
            } label: {
                Text(ReminderMenu.value(minutes))
            }
            .fixedSize()
            .accessibilityLabel(ReminderMenu.title(minutes))
        } label: {
            Text(ReminderMenu.label(minutes))
        }
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
            Text("Notifications \(hub.authorization?.text ?? "…")").foregroundStyle(.secondary)
            Spacer()
            // By the state, never by its words (lot 10, 20/11).
            if hub.authorization == .denied {
                Button("Ouvrir Réglages Système") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                }
            }
            Button("Envoyer un essai") { Task { await hub.test() } }
        }
        .task { await hub.readAuthorization() }
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
                // Why they cannot be written: a problem, said by `ErrorLine` in place of the help (design system v2, 19/11).
                SettingRow(SettingsText.summaries, help: SettingsText.summariesHelp, problem: library.summaryUnavailable) {
                    Toggle(SettingsText.summaries, isOn: $summaries)
                }
            }
            Section("Transcription") {
                SettingRow(SettingsText.language, help: SettingsText.languageHelp) {
                    Picker(SettingsText.language, selection: $language) {
                        Text("Français").tag("fr")
                        Text("Anglais").tag("en")
                        // No word of the code on screen: « le moteur » (lot 10, 20/11).
                        Text("Détection automatique").tag("auto")
                    }
                }
            }
        }
        .settingsForm()
    }
}

/// Réglages › Mises à jour.
struct UpdatesSettingsView: View {
    @ObservedObject var updates: UpdateService

    var body: some View {
        Form {
            Section {
                LabeledContent("Version installée", value: updates.current.description)
                // A meta: « 9:04 » today, « hier 9:04 », « 18 nov. 9:04 », by `Words` (lot 10, 20/11).
                LabeledContent("Dernière vérification", value: updates.lastCheck.map {
                    Words.shortMoment($0, now: Date())
                } ?? "pas encore")
                SettingRow(SettingsText.autoInstall, help: SettingsText.autoInstallHelp) {
                    Toggle(SettingsText.autoInstall, isOn: $updates.autoInstall)
                }
                if let text = UpdateService.text(updates.state) {
                    // A failure: said by `ErrorLine` (design system v2, 19/11); the other states in grey.
                    if case .failed = updates.state {
                        ErrorLine(text)
                    } else {
                        Text(text).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("Vérifier maintenant") { Task { await updates.check() } }
                    if let latest = updates.latest {
                        Button("Mettre à jour vers \(latest.version.description)") { Task { await updates.installNow() } }
                            .buttonStyle(.primary)
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
        .settingsForm()
    }
}
