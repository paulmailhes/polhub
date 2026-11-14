import AppKit
import Domain
import Foundation
import Persistence
import SwiftUI
import Testing
@testable import MeetingsUI
import ProjectsUI
import Updates

/// Draws the window off screen, at a few widths, into PNG files to look at. Not part of `make check`:
/// `POLHUB_SNAPSHOTS=<dossier> swift test --filter WindowSnapshotTests`.
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"] != nil))
struct WindowSnapshotTests {
    @Test func theMeetingsSectionAtSeveralWidths() async throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"]), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appending(path: "fenêtre \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root, logs: root.appending(path: "logs"))
        let database = try AppDatabase.inMemory()
        let store = MeetingStore(database)
        let start = Date().addingTimeInterval(-3_600)
        let row = MeetingRow(createdAt: start, status: .ended, source: .dia, candidateKey: "t/a",
                             title: "RDV de Cadrage : un client avec un titre assez long pour la liste", startedAt: start,
                             endedAt: start.addingTimeInterval(2_860), transcribedAt: start.addingTimeInterval(3_100))
        try store.save(row)
        try TranscriptStore(database).replaceUtterances(meetingID: row.id, (0..<12).map { index in
            UtteranceRow(meetingID: row.id, speaker: index % 2 == 0 ? .autres : .moi, startMs: index * 20_000, endMs: index * 20_000 + 15_000,
                         text: String(repeating: "Une phrase de la réunion qui continue assez longtemps. ", count: index % 3 + 1), doubtful: index == 5)
        })
        try SummaryStore(database).finish(meetingID: row.id, summary: "## Résumé\n\nLe client valide la refonte ; la maquette de l'accueil part vendredi.\n\n## Décisions\n\n- Garder WordPress.\n- Une page par expertise.",
                                          actions: [ActionRow(text: "Envoyer la maquette (vendredi)", owner: "Moi", position: 0, createdAt: start),
                                                    ActionRow(text: "Rassembler les photos", owner: "Camille", position: 1, createdAt: start)], at: start)
        let library = MeetingLibrary(store: store)
        let router = WindowRouter()
        router.section = .meetings
        router.selection = row.id
        try await Task.sleep(for: .milliseconds(300))

        func measure(_ name: String, _ view: some View) {
            let host = NSHostingView(rootView: view)
            print("mesure \(name) : \(Int(host.fittingSize.width)) de large au moins")
        }
        measure("liste", MeetingListView(library: library, selection: .constant(row.id)))
        measure("fiche", MeetingDetailView(row: row, store: store, paths: paths, transcripts: library.transcripts, queue: nil,
                                           job: nil, meetingActive: false, router: router))
        measure("en-tête de transcription", TranscriptHeader(status: .done(doubtful: true), meetingID: row.id, queue: nil))
        measure("répliques", DialogueParagraphs(lines: try TranscriptStore(database).utterances(meetingID: row.id), current: nil, seek: { _ in }))
        measure("ligne de liste", MeetingRowView(row: row, now: Date(), badge: "Transcription 50 %"))

        for width in [860.0, 1_000, 1_280] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 700), styleMask: [.titled, .resizable, .closable],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = NSHostingView(rootView: MainWindowView(library: library, router: router, paths: paths) { EmptyView() })
            window.setContentSize(NSSize(width: width, height: 700))
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(500))
            window.layoutIfNeeded()
            let view = try #require(window.contentView)
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: output.appending(path: "fenetre-\(Int(width)).png"))
            print("fenêtre \(Int(width)) : contenu \(Int(view.fittingSize.width)) × \(Int(view.fittingSize.height)), fenêtre \(Int(window.frame.width))")
            window.close()
        }
    }

    @Test func theProjectsBoard() async throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"]), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appending(path: "kanban \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase.inMemory()
        let store = ProjectStore(database)
        let samples: [(String, ProjectStatus, String?, Int?, String?)] = [
            ("Site vitrine", .idee, "Freelance", nil, nil), ("Refonte site", .priorite1, "Atelier Nord", -2, "Envoyer la maquette de l'accueil"),
            ("Identité", .priorite1, "Studio Sud", 0, "Valider la typographie"), ("Studio photo", .priorite2, "Atelier Nord", 6, "Relancer pour les contenus"),
            ("Landing", .priorite3, "Atelier Nord", 12, "Préparer le cadrage"), ("Agence", .enAttente, "Atelier Nord", nil, nil),
        ]
        for (name, status, client, due, todo) in samples {
            var project = try store.addProject(name: name, status: status, at: Date())
            project.client = client
            project.dueDate = due.map { Date().addingTimeInterval(Double($0) * 86_400) }
            project.todo = todo
            project.color = name == "Identité" ? "purple" : nil
            try store.save(project, at: Date())
        }
        let library = MeetingLibrary(store: MeetingStore(database))
        let projects = ProjectLibrary(store: store, meetings: MeetingStore(database), defaults: UserDefaults(suiteName: "kanban-\(UUID().uuidString)")!)
        let router = WindowRouter()
        router.section = .projects
        try await Task.sleep(for: .milliseconds(300))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_400, height: 640), styleMask: [.titled, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: MainWindowView(library: library, projects: projects, router: router,
                                                                   paths: AppPaths(root: root, logs: root)) { EmptyView() })
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        window.layoutIfNeeded()
        let view = try #require(window.contentView)
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appending(path: "kanban.png"))
    }

    @Test func theProjectPage() async throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"]), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let database = try AppDatabase.inMemory()
        let store = ProjectStore(database)
        var project = try store.addProject(name: "Refonte site", status: .priorite1, at: Date())
        project.client = "Atelier Nord"
        project.todo = "Envoyer la maquette de l'accueil"
        project.dueDate = Date().addingTimeInterval(3 * 86_400)
        project.contacts = ["Camille Exemple"]
        project.notes = "> [!info]- Contexte\n> Studio de création.\n\n## Rendez-vous\n- **6 nov.** — Premier échange, voir la [page](https://exemple.fr).\n  - budget à confirmer\n- [ ] Lire la fiche"
        project.lastMeetingImported = Date().addingTimeInterval(-8 * 86_400)
        try store.save(project, at: Date())
        try store.saveAction(ActionRow(projectID: project.id, text: "Lire la fiche du client", addedOn: Date(), position: 0, createdAt: Date()))
        try store.saveAction(ActionRow(projectID: project.id, text: "Envoyer le devis", done: true, addedOn: Date(), position: 1, createdAt: Date()))
        try store.addJournal(ProjectJournalRow(projectID: project.id, date: Date(), title: "Maquette envoyée", body: "- Deux pages.\n- Retour attendu lundi.", createdAt: Date()))
        let projects = ProjectLibrary(store: store, meetings: MeetingStore(database), defaults: UserDefaults(suiteName: "page-\(UUID().uuidString)")!)
        try await Task.sleep(for: .milliseconds(300))
        projects.selected = project.id
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 1_100), styleMask: [.titled, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: ProjectsView(library: projects))
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        window.layoutIfNeeded()
        let view = try #require(window.contentView)
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appending(path: "projet.png"))
    }

    /// Réglages and its tabs: Mises à jour, Diagnostic, Journal.
    @Test func theSettingsPage() async throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"]), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appending(path: "réglages \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase.inMemory()
        let store = MeetingStore(database)
        try store.addJournal(JournalEntry(createdAt: Date(), kind: .info, message: "Polhub mis à jour : 0.3.0 → 0.3.1."))
        let library = MeetingLibrary(store: store)
        let projects = ProjectLibrary(store: ProjectStore(database), meetings: store, defaults: UserDefaults(suiteName: "réglages-\(UUID().uuidString)")!)
        let updates = UpdateService(current: SemanticVersion("0.3.1")!, fetch: { Data("[]".utf8) }, isIdle: { true },
                                    defaults: UserDefaults(suiteName: "maj-\(UUID().uuidString)")!)
        let router = WindowRouter()
        router.section = .settings
        try await Task.sleep(for: .milliseconds(300))
        for tab in [SettingsTab.updates, .diagnostic, .journal] {
            router.settingsTab = tab
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_000, height: 560), styleMask: [.titled, .resizable],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = NSHostingView(rootView: MainWindowView(library: library, projects: projects, updates: updates, router: router,
                                                                       paths: AppPaths(root: root, logs: root)) {
                Text("Le diagnostic de l'app").padding()
            })
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(500))
            window.layoutIfNeeded()
            let view = try #require(window.contentView)
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appending(path: "reglages-\(tab.rawValue).png"))
            window.close()
        }
    }

    /// Accueil, Calendrier and Contacts, with made-up data (13/11).
    @Test func theAgendaScreens() async throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"]), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appending(path: "agenda \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase.inMemory()
        let projectStore = ProjectStore(database)
        var alpha = try projectStore.addProject(name: "Atelier Nord", status: .priorite1, at: Date())
        alpha.color = "bleu"
        alpha.todo = "Envoyer la maquette"
        try projectStore.save(alpha, at: Date())
        var beta = try projectStore.addProject(name: "Site vitrine", status: .priorite2, at: Date())
        beta.color = "vert"
        try projectStore.save(beta, at: Date())
        let calendar = CalendarStore(database)
        try calendar.addAccount(email: "moi@exemple.fr", at: Date())
        let monday = CalendarView.monday(of: .now)
        func at(_ day: Int, _ hour: Double) -> Date { monday.addingTimeInterval(Double(day) * 86_400 + hour * 3_600) }
        let guests = [Attendee(email: "camille.martin@exemple-studio.fr", name: "Camille Martin"), Attendee(email: "jules@atelier-nord.fr"),
                      Attendee(email: "moi@exemple.fr", isSelf: true)]
        try calendar.applyGoogle(account: "moi@exemple.fr", changed: [
            CalendarEventRow(account: "moi@exemple.fr", eventID: "a", title: "Atelier maquette", startAt: at(0, 10), endAt: at(0, 11), meetCode: "abc-defg-hij", attendees: guests, updatedAt: Date()),
            CalendarEventRow(account: "moi@exemple.fr", eventID: "b", title: "Point hebdo", startAt: at(0, 10.5), endAt: at(0, 11.5), updatedAt: Date()),
            CalendarEventRow(account: "moi@exemple.fr", eventID: "c", title: "Revue Site vitrine", startAt: at(2, 14), endAt: at(2, 15), attendees: guests, updatedAt: Date()),
            CalendarEventRow(account: "moi@exemple.fr", eventID: "d", title: "Déjeuner", startAt: at(3, 12.5), endAt: at(3, 13.5), updatedAt: Date()),
            CalendarEventRow(account: "moi@exemple.fr", eventID: "e", title: "Férié", startAt: at(4, 0), endAt: at(5, 0), allDay: true, updatedAt: Date()),
        ], cancelled: [], at: Date())
        // 14/11: three accounts in their colors, and an invitation present in two of them.
        try calendar.addAccount(email: "perso@gmail.com", at: Date().addingTimeInterval(1))
        try calendar.addAccount(email: "paul@atelier-nord.fr", at: Date().addingTimeInterval(2))
        try calendar.applyGoogle(account: "perso@gmail.com", changed: [
            CalendarEventRow(account: "perso@gmail.com", eventID: "f", title: "Dentiste", startAt: at(1, 9), endAt: at(1, 9.75), updatedAt: Date()),
            CalendarEventRow(account: "perso@gmail.com", eventID: "c", title: "Revue Site vitrine", startAt: at(2, 14), endAt: at(2, 15), attendees: guests, updatedAt: Date()),
        ], cancelled: [], at: Date())
        try calendar.applyGoogle(account: "paul@atelier-nord.fr", changed: [
            CalendarEventRow(account: "paul@atelier-nord.fr", eventID: "g", title: "Atelier Nord · sprint", startAt: at(1, 14), endAt: at(1, 16),
                             meetCode: "xyz-abcd-efg", organizer: "paul@atelier-nord.fr", updatedAt: Date()),
            CalendarEventRow(account: "paul@atelier-nord.fr", eventID: "h", title: "Point client", startAt: at(3, 9.5), endAt: at(3, 10), updatedAt: Date()),
            CalendarEventRow(account: "paul@atelier-nord.fr", eventID: "i", title: "Atelier Nord · revue des maquettes", startAt: Date().addingTimeInterval(1_200),
                             endAt: Date().addingTimeInterval(4_800), meetCode: "qrs-tuvw-xyz", organizer: "paul@atelier-nord.fr", updatedAt: Date()),
        ], cancelled: [], at: Date())
        try calendar.setProject(eventID: CalendarEventRow.key(account: "moi@exemple.fr", eventID: "a"), projectID: alpha.id, origin: .invites)
        try calendar.setProject(eventID: CalendarEventRow.key(account: "moi@exemple.fr", eventID: "c"), projectID: beta.id, origin: .titre)
        let contacts = ContactStore(database)
        let camille = try contacts.upsert(email: "camille.martin@exemple-studio.fr", name: "Camille Martin", company: "Exemple Studio", at: Date())
        try contacts.link(contactID: camille.id, projectID: alpha.id, origin: .agenda, at: Date())
        try contacts.upsert(email: "jules@atelier-nord.fr", name: "Jules", company: "Atelier Nord", at: Date())
        let library = MeetingLibrary(store: MeetingStore(database))
        let projects = ProjectLibrary(store: projectStore, meetings: MeetingStore(database), defaults: UserDefaults(suiteName: "agenda-\(UUID().uuidString)")!)
        let agenda = AgendaLibrary(database: database)
        let router = WindowRouter()
        try await Task.sleep(for: .milliseconds(400))
        for (section, name) in [(SidebarItem.home, "accueil"), (.calendar, "calendrier"), (.contacts, "contacts")] {
            router.section = section
            if section == .contacts { router.contactSelection = camille.id }
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_280, height: 760), styleMask: [.titled, .resizable],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = NSHostingView(rootView: MainWindowView(library: library, projects: projects, agenda: agenda, router: router,
                                                                       paths: AppPaths(root: root, logs: root)) { EmptyView() })
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(600))
            window.layoutIfNeeded()
            let view = try #require(window.contentView)
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appending(path: "\(name).png"))
            window.close()
        }
    }
}
