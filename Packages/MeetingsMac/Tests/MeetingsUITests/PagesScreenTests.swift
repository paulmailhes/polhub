import AppKit
import Agenda
import Domain
import Foundation
import Mail
import MailFormat
import Persistence
import PolhubDesign
@testable import ProjectsUI
import SwiftUI
import Testing
@testable import MeetingsUI

/// The pages of lot 8 (19/11): Projets (Kanban, Liste, a project's page), Réunions (the list and a meeting), Calendrier
/// (the week and an event's bubble), Contacts, Inspiration (the grid and an item), in light and dark. Every person,
/// project, meeting and mail here is made up; each project has its color chosen, so that two runs compare. Not part of
/// `make check`: `POLHUB_LIVE=1 POLHUB_SNAPSHOTS=<dossier> swift test --filter PagesScreenTests` (live: glass and toolbar).
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"] != nil), .serialized)
struct PagesScreenTests {
    @MainActor struct World {
        let root: URL
        let database: AppDatabase
        let agenda: AgendaLibrary
        let mails: MailLibrary
        let projects: ProjectLibrary
        let library: MeetingLibrary
        let inspiration: InspirationLibrary
        let inspirationWorld: InspirationTestWorld
        let project: ProjectRow
        let meeting: MeetingRow
        let camille: ContactRow
        let router = WindowRouter()

        var paths: AppPaths { AppPaths(root: root, logs: root.appending(path: "logs")) }

        func window() -> some View {
            MainWindowView(library: library, projects: projects, agenda: agenda, mails: mails, inspiration: inspiration,
                           router: router, paths: paths) { EmptyView() }
        }

        func clean() {
            inspirationWorld.clean()
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func output() throws -> URL {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"]), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        return output
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    }

    /// The settings these pages read, as the app's defaults: a capture never depends on what another suite left.
    private func defaults() {
        let standard = UserDefaults.standard
        standard.set(true, forKey: Preferences.Key.floatingPages)
        standard.set(CardSize.medium.rawValue, forKey: Preferences.Key.cardSize)
        standard.set(true, forKey: Preferences.Key.showWeekend)
        standard.set(Preferences.Default.dayStartHour, forKey: Preferences.Key.dayStartHour)
    }

    private func world() async throws -> World {
        defaults()
        let root = FileManager.default.temporaryDirectory.appending(path: "pages \(UUID().uuidString)", directoryHint: .isDirectory)
        let database = try AppDatabase.inMemory()
        let now = Date()
        let day: TimeInterval = 86_400

        // Two accounts, their mails allowed.
        let calendar = CalendarStore(database)
        let both = "openid https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/gmail.modify"
        for (index, email) in ["moi@exemple.fr", "perso@exemple.net"].enumerated() {
            try calendar.addAccount(email: email, at: now.addingTimeInterval(Double(index)))
            try calendar.setGrantedScopes(email: email, scopes: both)
        }

        // The projects, one per color of the vault's palette, over the four columns; « noir » too, the darkest.
        let projectStore = ProjectStore(database)
        let samples: [(name: String, status: ProjectStatus, client: String?, due: Int?, todo: String?, color: String)] = [
            ("Refonte site", .priorite1, "Atelier Nord", -2, "Envoyer la maquette de l'accueil", "bleu"),
            ("Identité", .priorite1, "Studio Sud", 0, "Valider la typographie", "violet"),
            ("Studio photo", .priorite2, "Atelier Nord", 6, "Relancer pour les contenus", "vert"),
            ("Landing", .priorite2, "Atelier Nord", 12, "Préparer le cadrage", "orange"),
            ("Site vitrine", .enPause, "Freelance", nil, nil, "rose"),
            ("Agence", .enPause, "Atelier Nord", nil, nil, "marron"),
            ("Catalogue", .enPause, "Maison Exemple", nil, "Attendre les photos", "noir"),
            ("Ancien site", .termine, "Studio Sud", nil, nil, "cyan"),
            ("Carte de vœux", .termine, nil, nil, nil, "jaune"),
        ]
        var made: [String: ProjectRow] = [:]
        for sample in samples {
            var project = try projectStore.addProject(name: sample.name, status: sample.status, at: now)
            project.client = sample.client
            project.dueDate = sample.due.map { now.addingTimeInterval(Double($0) * day) }
            project.todo = sample.todo
            project.color = sample.color
            project.lastMeetingImported = sample.name == "Refonte site" ? now.addingTimeInterval(-21 * day) : nil
            try projectStore.save(project, at: now)
            made[sample.name] = project
        }
        var project = try #require(made["Refonte site"])
        project.notes = "> [!info]- Contexte\n> Studio de création, deux associés.\n\n## Rendez-vous\n- **6 nov.** — Premier échange, voir la [page](https://exemple.fr).\n- [ ] Lire la fiche"
        try projectStore.save(project, at: now)
        for (index, text) in ["Lire la fiche du client", "Préparer le devis", "Envoyer les accès"].enumerated() {
            try projectStore.saveAction(ActionRow(projectID: project.id, text: text, addedOn: now, position: Double(index), createdAt: now))
        }
        try projectStore.addJournal(ProjectJournalRow(projectID: project.id, date: now, title: "Maquette envoyée",
                                                      body: "- Deux pages.\n- Retour attendu lundi.", createdAt: now))

        // The people.
        let contacts = ContactStore(database)
        let camille = try contacts.upsert(email: "camille.martin@exemple-studio.fr", name: "Camille Martin", company: "Exemple Studio", at: now)
        let jules = try contacts.upsert(email: "jules@atelier-nord.fr", name: "Jules Durand", company: "Atelier Nord", at: now)
        let nina = try contacts.upsert(email: "nina.roche@exemple.net", name: "Nina Roche", company: nil, at: now)
        try contacts.include(contactID: camille.id, projectID: project.id, at: now)
        try contacts.include(contactID: camille.id, projectID: try #require(made["Identité"]).id, at: now)
        try contacts.include(contactID: jules.id, projectID: project.id, at: now)

        // The meetings: one heard yesterday, its summary and its dialogue, its audio missing (no folder); two older.
        let meetingStore = MeetingStore(database)
        let start = now.addingTimeInterval(-day)
        let meeting = MeetingRow(createdAt: start, status: .ended, source: .dia, candidateKey: "t/revue", title: "Revue des maquettes",
                                 startedAt: start, endedAt: start.addingTimeInterval(2_700), transcribedAt: start.addingTimeInterval(3_000))
        try meetingStore.save(meeting)
        try projectStore.setProject(meetingID: meeting.id, projectID: project.id)
        try TranscriptStore(database).replaceUtterances(meetingID: meeting.id, (0..<10).map { index in
            UtteranceRow(meetingID: meeting.id, speaker: index % 2 == 0 ? .autres : .moi, startMs: index * 24_000, endMs: index * 24_000 + 20_000,
                         text: String(repeating: "Une phrase de la revue, qui continue un peu. ", count: index % 3 + 1), doubtful: index == 3)
        })
        try SummaryStore(database).finish(meetingID: meeting.id,
                                          summary: "## Résumé\n\nLe client valide la maquette de l'accueil ; la page Contact reste à revoir.\n\n## Points clés\n\n- Les photos de l'équipe arrivent jeudi.\n- Le blog attendra la deuxième version.\n\n## Décisions\n\n- Une page par expertise.",
                                          actions: [ActionRow(text: "Envoyer la maquette (vendredi)", owner: "Moi", position: 0, createdAt: start),
                                                    ActionRow(text: "Rassembler les photos", owner: "Camille", position: 1, createdAt: start)],
                                          at: start)
        try contacts.setParticipants(meetingID: meeting.id, contactIDs: [camille.id, jules.id])
        for (index, (title, days, status)) in [("Point hebdo", 2.0, MeetingStatus.ended), ("Cadrage du catalogue", 5, .interrupted)].enumerated() {
            let begun = now.addingTimeInterval(-days * day)
            let older = MeetingRow(createdAt: begun, status: status, source: .dia, candidateKey: "t/\(index)", title: title, startedAt: begun,
                                   endedAt: begun.addingTimeInterval(1_800))
            try meetingStore.save(older)
            if index == 0 { try meetingStore.setSummary(meetingID: older.id, summary: "## Résumé\n\nLe planning de décembre est validé.") }
        }

        // The week shown: from eight in the morning on Monday, an event a day, one over the whole day.
        let monday = CalendarView.monday(of: now)
        func at(_ day: Int, _ hour: Double) -> Date { monday.addingTimeInterval(Double(day) * 86_400 + hour * 3_600) }
        let guests = [Attendee(email: "moi@exemple.fr", response: "accepted", isSelf: true),
                      Attendee(email: camille.email!, name: "Camille Martin", response: "accepted"), Attendee(email: jules.email!, name: "Jules Durand")]
        try calendar.applyGoogle(account: "moi@exemple.fr", changed: [
            CalendarEventRow(account: "moi@exemple.fr", eventID: "lundi", title: "Café avec Nina", startAt: at(0, 8), endAt: at(0, 9), updatedAt: now),
            CalendarEventRow(account: "moi@exemple.fr", eventID: "atelier", title: "Atelier maquette", startAt: at(1, 10), endAt: at(1, 11),
                             meetCode: "abc-defg-hij", organizer: "moi@exemple.fr", attendees: guests, updatedAt: now),
            CalendarEventRow(account: "moi@exemple.fr", eventID: "revue", title: "Revue Refonte site", startAt: at(2, 14), endAt: at(2, 15),
                             meetCode: "klm-nopq-rst", organizer: "moi@exemple.fr", attendees: guests, updatedAt: now),
            CalendarEventRow(account: "moi@exemple.fr", eventID: "salon", title: "Salon du design", startAt: at(2, 0), endAt: at(3, 0), allDay: true,
                             updatedAt: now),
            CalendarEventRow(account: "moi@exemple.fr", eventID: "photo", title: "Revue Studio photo", startAt: now.addingTimeInterval(day + 3_600),
                             endAt: now.addingTimeInterval(day + 7_200), meetCode: "uvw-xyza-bcd", attendees: guests, updatedAt: now),
        ], cancelled: [], at: now)
        try calendar.applyGoogle(account: "perso@exemple.net", changed: [
            CalendarEventRow(account: "perso@exemple.net", eventID: "dentiste", title: "Dentiste", startAt: at(3, 9), endAt: at(3, 9.75), updatedAt: now),
            CalendarEventRow(account: "perso@exemple.net", eventID: "diner", title: "Dîner", startAt: at(4, 19.5), endAt: at(4, 21), updatedAt: now),
        ], cancelled: [], at: now)
        for (id, name) in [("atelier", "Refonte site"), ("revue", "Refonte site"), ("photo", "Studio photo")] {
            try calendar.setProject(eventID: CalendarEventRow.key(account: "moi@exemple.fr", eventID: id), projectID: try #require(made[name]).id,
                                    origin: .titre)
        }

        // Camille's mails.
        let store = MailStore(database)
        let me = MailAddress(name: "Paul", email: "moi@exemple.fr")
        let from = MailAddress(name: "Camille Martin", email: camille.email!)
        func mail(_ id: String, days: Double, sender: MailAddress, to: [MailAddress], subject: String, snippet: String) -> MailMessageRow {
            MailMessageRow(account: "moi@exemple.fr", messageID: id, threadID: "t-\(id)", date: now.addingTimeInterval(-days * day), sender: sender, to: to,
                           subject: subject, snippet: snippet, labels: sender == me ? ["SENT"] : ["INBOX", "CATEGORY_PERSONAL"])
        }
        try store.apply(account: "moi@exemple.fr", upserts: [
            mail("1", days: 0.2, sender: from, to: [me], subject: "Maquette v2 du site", snippet: "Voici la deuxième version, avec la page Contact revue."),
            mail("2", days: 1.5, sender: me, to: [from], subject: "Devis signé", snippet: "Merci, je lance la production lundi."),
            mail("3", days: 6, sender: from, to: [me], subject: "Photos de l'équipe", snippet: "Les photos arrivent jeudi."),
            mail("4", days: 9, sender: MailAddress(name: "Nina Roche", email: nina.email!), to: [me], subject: "Textes de l'accueil", snippet: "Voici les textes relus."),
        ])

        let agenda = AgendaLibrary(database: database)
        let mails = MailLibrary(agenda: agenda, root: root, defaults: try #require(UserDefaults(suiteName: "pages-\(UUID().uuidString)")))
        let inspirationWorld = try InspirationTestWorld(name: "pages")
        try inspirationWorld.fill()
        let inspiration = inspirationWorld.library()
        let projects = ProjectLibrary(store: projectStore, meetings: meetingStore)
        let world = World(root: root, database: database, agenda: agenda, mails: mails, projects: projects,
                          library: MeetingLibrary(store: meetingStore), inspiration: inspiration, inspirationWorld: inspirationWorld,
                          project: project, meeting: meeting, camille: camille)
        try await waitUntil { mails.accounts.count == 2 && inspiration.loaded.count == 3 && projects.loaded && !agenda.shown.isEmpty }
        try await Task.sleep(for: .milliseconds(400))
        return world
    }

    private func capture(_ view: some View, _ name: String, size: NSSize = NSSize(width: 1_280, height: 860),
                         wait: Duration = .milliseconds(2_000)) async throws {
        for dark in [false, true] {
            try await LiveWindow.capture(view, to: try output().appending(path: "\(name)\(dark ? "-sombre" : "").png"), size: size, dark: dark, wait: wait)
        }
    }

    /// Projets: the Kanban, the list, a project's page over the board.
    @Test func theProjects() async throws {
        let world = try await world()
        defer { world.clean() }
        world.router.section = .projects
        try await capture(world.window(), "projets-kanban", size: NSSize(width: 1_440, height: 860))
        try await capture(ProjectListView(library: world.projects, projects: world.projects.projects), "projets-liste",
                          size: NSSize(width: 1_200, height: 520))
        world.projects.selected = world.project.id
        try await capture(world.window(), "projets-projet", size: NSSize(width: 1_280, height: 900), wait: .milliseconds(2_500))
        world.projects.selected = nil
    }

    /// Réunions: the list and a meeting whose audio cannot be read; at the window's narrowest too.
    @Test func theMeetings() async throws {
        let world = try await world()
        defer { world.clean() }
        world.router.open(meetingID: world.meeting.id, at: nil)
        try await capture(world.window(), "reunions", wait: .milliseconds(2_500))
        try await LiveWindow.capture(world.window(), to: try output().appending(path: "reunions-etroit.png"),
                                     size: NSSize(width: MainWindowView<EmptyView>.minimumWidth, height: 860), wait: .milliseconds(2_500))
        // « Détails » unfolded: the system's own text, under Polhub's sentence (lot 8).
        let problem = AudioProblem(CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: "/Reunions/exemple/meeting.json"]))
        try await capture(AudioProblemLine(problem: problem, open: true).padding(PageMetrics.horizontal).frame(width: 760, alignment: .leading)
                            .background(Color(nsColor: .windowBackgroundColor)),
                          "reunions-erreur-details", size: NSSize(width: 760, height: 160))
    }

    /// Calendrier: the week, its first hour at the top; an event's bubble.
    @Test func theCalendar() async throws {
        let world = try await world()
        defer { world.clean() }
        world.router.section = .calendar
        try await capture(world.window(), "calendrier", wait: .milliseconds(2_500))
        let event = try #require(world.agenda.shown.first { $0.eventID == "atelier" })
        try await capture(EventPopover(event: event, agenda: world.agenda, router: world.router, edit: {}, close: {})
                            .background(Color(nsColor: .windowBackgroundColor)),
                          "calendrier-bulle", size: NSSize(width: 320, height: 640))
    }

    /// Contacts: the list and Camille's page.
    @Test func theContacts() async throws {
        let world = try await world()
        defer { world.clean() }
        world.router.section = .contacts
        world.router.contactSelection = world.camille.id
        try await capture(world.window(), "contacts", wait: .milliseconds(2_500))
    }

    /// Inspiration: the grid of the sites, a post open.
    @Test func theInspiration() async throws {
        let world = try await world()
        defer { world.clean() }
        world.router.openInspiration(.website)
        try await capture(world.window(), "inspiration", wait: .milliseconds(2_500))
        let post = try #require(world.inspiration.items(.branding).first { $0.title == "Fondation Exemple" })
        world.router.openInspiration(.branding, item: post.id)
        try await capture(world.window(), "inspiration-fiche", wait: .milliseconds(2_500))
    }
}
