import AppKit
import Domain
import Foundation
import Notifications
import Persistence
import Pipeline
import PolhubDesign
import ProjectsUI
import SwiftUI
import Testing
import Updates
@testable import MeetingsUI

/// The menu bar's logo in each state, and « Coup d'œil », with made-up meetings, events and mails (15/11):
/// `POLHUB_LIVE=1 POLHUB_SNAPSHOTS=<dossier> swift test --filter CoupDoeilScreenTests`. Nothing of them is kept in the
/// repository.
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"] != nil), .serialized)
struct CoupDoeilScreenTests {
    private var output: URL {
        get throws {
            let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"]), isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
    }

    @Test func theLogoInEachState() async throws {
        let output = try output
        let now = Date()
        let states: [(String, MenuBarLabel)] = [
            ("Repos", MenuBarLabel.make(status: .idle, now: now)),
            ("Avant un Meet", MenuBarLabel.make(status: .idle, now: now, minutesToMeet: 8)),
            ("Menacé", MenuBarLabel.make(status: .idle, now: now, danger: true)),
            ("Suspendue", MenuBarLabel.make(status: .paused(until: now), now: now)),
            ("Suspendue, menacé", MenuBarLabel.make(status: .paused(until: now), now: now, danger: true)),
            ("Détectée", MenuBarLabel.make(status: .prompting(title: "Point"), now: now, promptDeadline: now.addingTimeInterval(6.5))),
            ("Enregistre", MenuBarLabel.make(status: .recording(title: "Point", since: now.addingTimeInterval(-767)), now: now)),
            ("Fin ?", MenuBarLabel.make(status: .presumedEnded(title: "Point"), now: now)),
            ("Développement", MenuBarLabel.make(status: .idle, now: now, isDevelopment: true)),
        ]
        for dark in [false, true] {
            try await LiveWindow.capture(LogoSheet(states: states).environment(\.colorScheme, dark ? .dark : .light),
                                         to: output.appending(path: "logo-\(dark ? "sombre" : "clair").png"),
                                         size: NSSize(width: 960, height: 860), dark: dark)
        }
    }

    /// Each state of the panel, light and dark, on made-up data: a Sunday of November at the hour each state needs.
    @Test func thePanelInEachState() async throws {
        let output = try output
        let world = try await PanelWorld()
        let cases: [(String, Date, (PanelWorld) async throws -> Void)] = [
            ("repos", world.at(15, 22), { _ in }),
            ("reunion-dans-8-min", world.at(16, 22), { _ in }),
            ("reunion-detectee", world.at(16, 31), { world in
                world.app.status = .prompting(title: "Revue de maquettes")
                world.app.setPromptDeadline(Date().addingTimeInterval(8))
                world.app.setMeetCode(PanelWorld.meetCode)
            }),
            ("enregistrement", world.at(16, 44), { world in try await world.recording() }),
            ("fin-presumee", world.at(17, 6), { world in try await world.presumedEnd() }),
            ("compte-rendu-en-cours", world.at(17, 12), { world in try await world.transcribing() }),
            ("resume-pret", world.at(17, 22), { world in try await world.summaryReady() }),
            ("mails-en-attente", world.at(15, 22), { world in try await world.unreadMails() }),
            ("suspendue", world.at(15, 22), { world in world.app.pausedUntil = world.at(16, 50) }),
            // The update stays from here on: it is never reset.
            ("a-regler", world.at(15, 22), { world in try await world.troubles() }),
            // Everything at once: past the height cap, only the mails' list scrolls.
            ("tout-a-la-fois", world.at(15, 22), { world in
                try await world.troubles()
                world.app.raise(.diskLow(freeGB: 9))
                try await world.unreadMails()
            }),
        ]
        for (name, now, setUp) in cases {
            try await world.reset()
            try await setUp(world)
            try await Task.sleep(for: .milliseconds(400))
            for dark in [false, true] {
                try await PanelWindow.capture(MenuBarPanel(context: world.context).environment(\.panelNow, now),
                                              to: output.appending(path: "panneau-\(name)-\(dark ? "sombre" : "clair").png"), dark: dark)
            }
        }
        // Before the libraries are ready, and the development build.
        let early = AppModel()
        early.detectionOn = true
        try await PanelWindow.capture(MenuBarPanel(context: CoupDoeilContext(app: early, router: WindowRouter())).environment(\.panelNow, world.at(15, 22)),
                                      to: output.appending(path: "panneau-au-lancement-clair.png"), dark: false)
        let development = AppModel(isDevelopment: true)
        let context = CoupDoeilContext(app: development, router: WindowRouter())
        context.attach(library: world.library, agenda: world.agenda, mails: world.mails, projects: world.projects, projectLogos: nil,
                       notifications: nil, updates: nil)
        try await world.reset()
        try await PanelWindow.capture(MenuBarPanel(context: context).environment(\.panelNow, world.at(15, 22)),
                                      to: output.appending(path: "panneau-developpement-clair.png"), dark: false)
    }

    @Test func theGeneralSettings() async throws {
        let output = try output
        try await LiveWindow.capture(GeneralSettingsPane(startup: nil).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top),
                                     to: output.appending(path: "reglages-general.png"), size: NSSize(width: 700, height: 420))
    }
}

/// A made-up Polhub for the panel: two Google accounts, three events this Sunday, two projects in Priorité 2, a meeting
/// of yesterday with its summary, mails of people, two notifications not seen. Each state changes a little of it.
@MainActor
final class PanelWorld {
    static let meetCode = "abc-defg-hij"
    let database: AppDatabase
    let root: URL
    let app = AppModel()
    let router = WindowRouter()
    let agenda: AgendaLibrary
    let mails: MailLibrary
    let library: MeetingLibrary
    let projects: ProjectLibrary
    let hub: NotificationHub
    let updates: UpdateService
    let context: CoupDoeilContext
    let refonte: ProjectRow
    let yesterday: MeetingRow
    private var today: MeetingRow?
    let calendar = PanelModel.calendar

    static let work = "paul@atelier-nord.fr"
    static let personal = "paul.exemple@gmail.com"

    init() async throws {
        database = try AppDatabase.inMemory()
        root = FileManager.default.temporaryDirectory.appending(path: "coup d'œil \(UUID().uuidString)", directoryHint: .isDirectory)
        let scopes = "openid https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/gmail.modify"
        let calendarStore = CalendarStore(database)
        for (index, email) in [Self.work, Self.personal].enumerated() {
            try calendarStore.addAccount(email: email, at: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)))
            try calendarStore.setGrantedScopes(email: email, scopes: scopes)
        }
        let projectStore = ProjectStore(database)
        var refonte = try projectStore.addProject(name: "Refonte du site", status: .priorite2, at: Date())
        refonte.color = "blue"
        try projectStore.save(refonte, at: Date())
        self.refonte = refonte
        _ = try projectStore.addProject(name: "Studio photo", status: .priorite2, at: Date())
        _ = try projectStore.addProject(name: "Identité", status: .priorite1, at: Date())
        let meetingStore = MeetingStore(database)
        let start = Calendar.current.date(byAdding: .day, value: -1, to: Self.date(10, 0))!
        yesterday = MeetingRow(createdAt: start, status: .ended, source: .dia, candidateKey: "t/hier", title: "Point équipe", startedAt: start,
                               endedAt: start.addingTimeInterval(2_700), transcribedAt: start.addingTimeInterval(3_300))
        try meetingStore.save(yesterday)
        try SummaryStore(database).finish(meetingID: yesterday.id, summary: "## Résumé\n\nLe planning tient ; la recette commence lundi.",
                                          actions: [], at: start.addingTimeInterval(3_600))
        agenda = AgendaLibrary(database: database)
        mails = MailLibrary(agenda: agenda, root: root, defaults: UserDefaults(suiteName: "coup-doeil-\(UUID().uuidString)")!)
        library = MeetingLibrary(store: meetingStore)
        projects = ProjectLibrary(store: projectStore, meetings: meetingStore, defaults: UserDefaults(suiteName: "coup-doeil-p-\(UUID().uuidString)")!)
        let inbox = NotificationInbox(file: nil)
        for (id, title) in [("n1", "Compte rendu prêt"), ("n2", "Nouveau rendez-vous")] {
            inbox.record(PlannedNotice(id: id, fireDate: Date(), title: title, body: "Exemple", eventID: nil, meetCode: nil, account: nil, kind: .newEvent),
                         at: Date())
        }
        hub = NotificationHub(agenda: agenda, client: SilentNotifications(), inbox: inbox)
        let releases = Data("""
        [{"tag_name": "v0.18.0", "draft": false, "prerelease": false, "body": "Coup d'œil.", "published_at": "2026-11-15T09:00:00Z",
          "assets": [{"name": "Polhub.zip", "browser_download_url": "https://github.com/paulmailhes/polhub/releases/download/v0.18.0/Polhub.zip"}]}]
        """.utf8)
        updates = UpdateService(current: SemanticVersion("0.17.2")!, fetch: { releases }, isIdle: { false },
                                defaults: UserDefaults(suiteName: "coup-doeil-maj-\(UUID().uuidString)")!)
        context = CoupDoeilContext(app: app, router: router)
        context.attach(library: library, agenda: agenda, mails: mails, projects: projects, projectLogos: nil, notifications: hub, updates: updates)
        app.detectionOn = true
        try saveEvents()
        try await Task.sleep(for: .milliseconds(400))
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// Today at that time: the captures' Sunday is the day they are made.
    static func date(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }

    func at(_ hour: Int, _ minute: Int) -> Date { Self.date(hour, minute) }

    private func saveEvents() throws {
        let guests = [Attendee(email: "camille.martin@exemple-studio.fr", name: "Camille Martin", response: "accepted"),
                      Attendee(email: "julien@exemple-studio.fr", response: "accepted"), Attendee(email: "lea@exemple-studio.fr", response: "tentative"),
                      Attendee(email: Self.work, response: "accepted", isSelf: true)]
        let events = [
            CalendarEventRow(account: Self.work, eventID: "revue", title: "Revue de maquettes", startAt: at(16, 30), endAt: at(17, 0),
                             meetCode: Self.meetCode, attendees: guests, projectID: refonte.id, projectOrigin: .paul, updatedAt: Date()),
            CalendarEventRow(account: Self.personal, eventID: "hugo", title: "Appel Hugo", startAt: at(18, 30), endAt: at(19, 0),
                             meetCode: "klm-nopq-rst", attendees: [Attendee(email: Self.personal, response: "accepted", isSelf: true)], updatedAt: Date()),
            CalendarEventRow(account: Self.personal, eventID: "dejeuner", title: "Déjeuner", startAt: at(12, 30), endAt: at(13, 30), updatedAt: Date()),
        ]
        try CalendarStore(database).applyGoogle(account: Self.work, changed: events.filter { $0.account == Self.work }, cancelled: [], at: Date())
        try CalendarStore(database).applyGoogle(account: Self.personal, changed: events.filter { $0.account == Self.personal }, cancelled: [], at: Date())
    }

    /// Back to rest: no meeting, no alert, no mail, no error, no update.
    func reset() async throws {
        app.status = .idle
        app.setPromptDeadline(nil)
        app.setMeetCode(nil)
        app.pausedUntil = nil
        for kind in AppAlert.Kind.allCases { app.resolve(kind) }
        if let today { try MeetingStore(database).softDelete(id: today.id, at: Date()) }
        today = nil
        try MailStore(database).apply(account: Self.work, removed: ["m1", "m2", "m3", "m4", "m5"])
        try CalendarStore(database).recordSync(email: Self.work, syncToken: nil, error: nil, at: Date())
    }

    func recording() async throws {
        let since = Date().addingTimeInterval(-767)
        var row = MeetingRow(createdAt: since, status: .recording, source: .dia, candidateKey: "t/\(Self.meetCode)", meetCode: Self.meetCode,
                             title: "Revue de maquettes", startedAt: since)
        row.projectID = refonte.id
        try MeetingStore(database).save(row)
        today = row
        app.status = .recording(title: "Revue de maquettes", since: since)
        app.setMeetCode(Self.meetCode)
        try await unreadMails()
    }

    func presumedEnd() async throws {
        let since = at(16, 31)
        let row = MeetingRow(createdAt: since, status: .presumedEnded, source: .dia, candidateKey: "t/\(Self.meetCode)", meetCode: Self.meetCode,
                             title: "Revue de maquettes", startedAt: since, presumedEndAt: at(17, 4))
        try MeetingStore(database).save(row)
        today = row
        app.status = .presumedEnded(title: "Revue de maquettes")
        app.setMeetCode(Self.meetCode)
    }

    private func endedMeeting(transcribed: Bool) throws -> MeetingRow {
        let row = MeetingRow(createdAt: at(16, 30), status: .ended, source: .dia, candidateKey: "t/\(Self.meetCode)", meetCode: Self.meetCode,
                             title: "Revue de maquettes", startedAt: at(16, 30), endedAt: at(17, 8), transcribedAt: transcribed ? at(17, 14) : nil,
                             projectID: refonte.id)
        try MeetingStore(database).save(row)
        today = row
        return row
    }

    func transcribing() async throws {
        let row = try endedMeeting(transcribed: false)
        try TranscriptStore(database).save(JobRow(meetingID: row.id, state: .running, language: "fr", progress: 0.58, createdAt: at(17, 8),
                                                 startedAt: at(17, 9)))
    }

    func summaryReady() async throws {
        let row = try endedMeeting(transcribed: true)
        try TranscriptStore(database).save(JobRow(meetingID: row.id, state: .done, language: "fr", progress: 1, createdAt: at(17, 8), finishedAt: at(17, 14)))
        try SummaryStore(database).finish(meetingID: row.id, summary: "## Résumé\n\nMaquettes validées ; reste la page tarifs, à livrer jeudi. Camille envoie les photos lundi.",
                                          actions: [], at: at(17, 18))
    }

    /// Five unread mails of people: Camille's are filed in « Refonte du site », Julien is a contact, the others strangers.
    func unreadMails() async throws {
        let contacts = ContactStore(database)
        let camille = try contacts.upsert(email: "camille.martin@exemple-studio.fr", name: "Camille Martin", company: nil, at: Date())
        try contacts.link(contactID: camille.id, projectID: refonte.id, origin: .paul, at: Date())
        _ = try contacts.upsert(email: "julien.dupont@exemple.fr", name: "Julien Dupont", company: nil, at: Date())
        func mail(_ id: String, _ name: String, _ email: String, _ subject: String, hours: Double) -> MailMessageRow {
            MailMessageRow(account: Self.work, messageID: id, threadID: id, date: at(15, 22).addingTimeInterval(-hours * 3_600),
                           sender: MailAddress(name: name, email: email), to: [MailAddress(email: Self.work)], subject: subject,
                           snippet: "Bonjour Paul,", labels: ["INBOX", "UNREAD", "CATEGORY_PERSONAL"])
        }
        try MailStore(database).apply(account: Self.work, upserts: [
            mail("m1", "Camille Martin", "camille.martin@exemple-studio.fr", "Devis révisé pour la refonte", hours: 4.67),
            mail("m2", "Julien Dupont", "julien.dupont@exemple.fr", "Re: Accès au serveur de test", hours: 6.1),
            mail("m3", "Léa Bernard", "lea.bernard@exemple.fr", "Photos du tournage", hours: 22),
            mail("m4", "Nina Roche", "nina.roche@exemple.fr", "Une question sur la facture", hours: 30),
            mail("m5", "Hugo Petit", "hugo.petit@exemple.fr", "On se voit jeudi ?", hours: 50),
        ])
    }

    /// Dia's tabs unreadable, the work account to reconnect, a version that waits for a quiet moment.
    func troubles() async throws {
        app.raise(.tabsUnreadable)
        try CalendarStore(database).recordSync(email: Self.work, syncToken: nil, error: "la connexion à ce compte a expiré : reconnecte-le", at: Date())
        await updates.check()
        await updates.installNow()
    }
}

/// The panel in a window of its own size, as the menu bar shows it: glass behind, rounded. With `POLHUB_LIVE=1`, on
/// screen and captured by the system.
@MainActor
enum PanelWindow {
    static func capture(_ view: some View, to file: URL, dark: Bool) async throws {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        // Drawn as in a key window (the menu bar's is, when open), without taking the focus from the Mac.
        let framed = view
            .environment(\.controlActiveState, .key)
            .background(PanelGround())
            .clipShape(shape)
            .padding(24)
        let host = NSHostingController(rootView: framed)
        host.sizingOptions = [.preferredContentSize]
        let window = KeyPanelWindow(contentViewController: host)
        window.styleMask = [.borderless]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        defer { window.close() }
        guard ProcessInfo.processInfo.environment["POLHUB_LIVE"] != nil else { return }
        window.setFrameTopLeftPoint(NSPoint(x: 40, y: (NSScreen.main?.visibleFrame.maxY ?? 900) - 20))
        // Never key nor active: a key typed meanwhile must not reach the panel (J would open the made-up Meet in Dia).
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(1_400))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-l", "\(window.windowNumber)", "-o", "-x", file.path]
        try process.run()
        process.waitUntilExit()
    }
}

/// A window without a frame that can still be key.
private final class KeyPanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// The menu bar's window ground, as near as a test window gets: the system's menu material, behind the window.
private struct PanelGround: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Each state at its real size on a strip like the menu bar's, then six times larger.
private struct LogoSheet: View {
    let states: [(String, MenuBarLabel)]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(spacing: Space.l) {
                ForEach(states.indices, id: \.self) { index in
                    label(states[index].1).fixedSize()
                }
            }
            .padding(.horizontal, Space.m)
            .frame(height: 24)
            .background(Color.primary.opacity(0.06))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(440), alignment: .leading), count: 2), alignment: .leading, spacing: Space.l) {
                ForEach(states.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack(spacing: 24) {
                            icon(states[index].1)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 108, height: 96)
                            if let text = states[index].1.text {
                                Text(text).font(.system(size: 13 * 6)).monospacedDigit().lineLimit(1).fixedSize()
                            }
                        }
                        .frame(height: 96)
                        .background(Color.primary.opacity(0.04))
                        Text(states[index].0).font(.meta).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func icon(_ label: MenuBarLabel) -> Image {
        let image = label.image
        return image.isTemplate ? Image(nsImage: image).renderingMode(.template) : Image(nsImage: image)
    }

    private func label(_ label: MenuBarLabel) -> some View {
        HStack(spacing: 4) {
            icon(label)
            if let text = label.text { Text(text).font(.system(size: 13)).monospacedDigit() }
        }
    }
}
