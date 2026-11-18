import AppKit
import Domain
import Foundation
import Persistence
import PolhubDesign
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
        try SummaryStore(database).finish(meetingID: row.id, summary: "## Résumé\n\nLe client valide la refonte ; la maquette de l'accueil part vendredi.\n\n## Points clés\n\n- Le blog attendra la deuxième version.\n- Les photos de l'équipe manquent encore.\n\n## Décisions\n\n- Garder WordPress.\n- Une page par expertise.",
                                          actions: [ActionRow(text: "Envoyer la maquette (vendredi)", owner: "Moi", position: 0, createdAt: start),
                                                    ActionRow(text: "Rassembler les photos", owner: "Camille", position: 1, createdAt: start)], at: start)
        // 15/11: the participants open their small menu in place, as in the mails.
        try CalendarStore(database).addAccount(email: "moi@exemple.fr", at: Date())
        let contacts = ContactStore(database)
        let guests = try [("camille.martin@exemple-studio.fr", "Camille Martin"), ("jules@atelier-nord.fr", "Jules Durand")].map { email, name in
            try contacts.upsert(email: email, name: name, company: nil, at: Date())
        }
        try contacts.setParticipants(meetingID: row.id, contactIDs: guests.map(\.id))
        let agenda = AgendaLibrary(database: database)
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
        measure("répliques", DialogueParagraphs(paragraphs: TranscriptModel.paragraphs(try TranscriptStore(database).utterances(meetingID: row.id)), seek: { _ in }))
        measure("ligne de liste", MeetingRowView(row: row, now: Date(), badge: "Transcription 50 %", project: "Refonte du site",
                                                 summary: .init(text: "Le client valide la refonte ; la maquette de l'accueil part vendredi.", kind: .ready)))

        for width in [860.0, 1_280] {
            try await LiveWindow.capture(MainWindowView(library: library, agenda: agenda, router: router, paths: paths) { EmptyView() },
                                         to: output.appending(path: "fenetre-\(Int(width)).png"), size: NSSize(width: width, height: 760))
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
            ("Site vitrine", .enPause, "Freelance", nil, nil), ("Refonte site", .priorite1, "Atelier Nord", -2, "Envoyer la maquette de l'accueil"),
            ("Identité", .priorite1, "Studio Sud", 0, "Valider la typographie"), ("Studio photo", .priorite2, "Atelier Nord", 6, "Relancer pour les contenus"),
            ("Landing", .priorite2, "Atelier Nord", 12, "Préparer le cadrage"), ("Agence", .enPause, "Atelier Nord", nil, nil),
            ("Ancien site", .termine, "Studio Sud", nil, nil), ("Carte de vœux", .termine, nil, nil, nil),
        ]
        for (name, status, client, due, todo) in samples {
            var project = try store.addProject(name: name, status: status, at: Date())
            project.client = client
            project.dueDate = due.map { Date().addingTimeInterval(Double($0) * 86_400) }
            project.todo = todo
            project.color = name == "Identité" ? "purple" : nil
            // 15/11: « Réunion il y a 3 semaines », in words.
            project.lastMeetingImported = name == "Refonte site" ? Date().addingTimeInterval(-21 * 86_400) : nil
            try store.save(project, at: Date())
        }
        let library = MeetingLibrary(store: MeetingStore(database))
        let projects = ProjectLibrary(store: store, meetings: MeetingStore(database))
        let router = WindowRouter()
        router.section = .projects
        try await Task.sleep(for: .milliseconds(300))
        try await LiveWindow.capture(MainWindowView(library: library, projects: projects, router: router,
                                                    paths: AppPaths(root: root, logs: root)) { EmptyView() },
                                     to: output.appending(path: "kanban.png"), size: NSSize(width: 1_440, height: 760))
        router.section = .projects
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
        // 15/11: five actions, then « Voir les N autres »; three entries of the journal, two plain lines each.
        for index in 2..<9 {
            try store.saveAction(ActionRow(projectID: project.id, text: "Action ouverte \(index)", addedOn: Date(), position: Double(index), createdAt: Date()))
        }
        try store.addJournal(ProjectJournalRow(projectID: project.id, date: Date(), title: "Maquette envoyée", body: "- Deux pages.\n- Retour attendu lundi.", createdAt: Date()))
        for day in 1...4 {
            try store.addJournal(ProjectJournalRow(projectID: project.id, date: Date().addingTimeInterval(Double(-day) * 86_400), title: "Étape \(day)",
                                                   body: "## Fait\n- Une **chose** faite, avec un [lien](https://exemple.fr).\n- Une autre, plus longue, qui prend la place d'une deuxième ligne entière pour voir la coupe.",
                                                   createdAt: Date()))
        }
        let meetings = MeetingStore(database)
        for day in 1...6 {
            let start = Date().addingTimeInterval(Double(-day) * 86_400)
            let meeting = MeetingRow(createdAt: start, status: .ended, source: .dia, candidateKey: "t/\(day)", title: "Point \(day)", startedAt: start,
                                     endedAt: start.addingTimeInterval(1_800))
            try meetings.save(meeting)
            try store.setProject(meetingID: meeting.id, projectID: project.id)
            if day == 1 { try meetings.setSummary(meetingID: meeting.id, summary: "## Résumé\n\nLe client valide la maquette ; la page Contact reste à revoir.") }
        }
        let projects = ProjectLibrary(store: store, meetings: meetings)
        let quiet = UserDefaults(suiteName: "logos-\(UUID().uuidString)")!
        quiet.set(false, forKey: Preferences.Key.projectLogos)
        let folder = FileManager.default.temporaryDirectory.appending(path: "logos \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let logos = ProjectLogos(folder: folder, database: nil, defaults: quiet)
        logos.setSite("exemple.fr", for: project.id)
        try await Task.sleep(for: .milliseconds(300))
        projects.selected = project.id
        UserDefaults.standard.set(false, forKey: Preferences.Key.floatingPages)
        try await LiveWindow.capture(ProjectsView(library: projects).environment(\.projectLogos, logos), to: output.appending(path: "projet.png"),
                                     size: NSSize(width: 1_200, height: 1_100))
        try await LiveWindow.capture(ProjectsView(library: projects).environment(\.projectLogos, logos), to: output.appending(path: "projet-sombre.png"),
                                     size: NSSize(width: 1_200, height: 1_100), dark: true)
        // 14/11: the page floats over the board, which stays in sight.
        UserDefaults.standard.set(true, forKey: Preferences.Key.floatingPages)
        try await LiveWindow.capture(ProjectsView(library: projects), to: output.appending(path: "projet-flottant.png"), size: NSSize(width: 1_200, height: 900))
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
        let projects = ProjectLibrary(store: ProjectStore(database), meetings: store)
        let updates = UpdateService(current: SemanticVersion("0.3.1")!, fetch: { Data("[]".utf8) }, isIdle: { true },
                                    defaults: UserDefaults(suiteName: "maj-\(UUID().uuidString)")!)
        let router = WindowRouter()
        router.section = .settings
        try await Task.sleep(for: .milliseconds(300))
        for tab in [SettingsPane?.none, .general, .notifications, .colin, .updates, .projects, .meetings, .diagnostic, .journal] {
            router.settingsPane = tab
            try await LiveWindow.capture(MainWindowView(library: library, projects: projects, updates: updates, router: router,
                                                        paths: AppPaths(root: root, logs: root)) { Text("Le diagnostic de l'app").padding() },
                                         to: output.appending(path: "reglages-\(tab?.rawValue ?? "familles").png"), size: NSSize(width: 1_000, height: 600))
        }
        // 16/11: Réglages › Projets in the dark too (the vault's folder gone).
        router.settingsPane = .projects
        try await LiveWindow.capture(MainWindowView(library: library, projects: projects, updates: updates, router: router,
                                                    paths: AppPaths(root: root, logs: root)) { EmptyView() },
                                     to: output.appending(path: "reglages-projects-sombre.png"), size: NSSize(width: 1_000, height: 600), dark: true)
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
        // 15/11: Accueil shows six projects in priorité 1, then « Voir les N autres ».
        for name in ["Studio photo", "Identité", "Landing", "Agence", "Catalogue", "Boutique", "Carte de vœux"] {
            try projectStore.addProject(name: name, status: .priorite1, at: Date())
        }
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
        // 15/11: Accueil's latest meetings show the first line of their summary.
        let meetingStore = MeetingStore(database)
        for (index, title) in ["Point hebdo", "Cadrage du site vitrine", "Revue des maquettes"].enumerated() {
            let start = Date().addingTimeInterval(Double(-index - 1) * 86_400)
            let meeting = MeetingRow(createdAt: start, status: .ended, source: .dia, candidateKey: "t/\(index)", title: title, startedAt: start,
                                     endedAt: start.addingTimeInterval(1_800))
            try meetingStore.save(meeting)
            if index == 0 { try projectStore.setProject(meetingID: meeting.id, projectID: alpha.id) }
            if index < 2 {
                try meetingStore.setSummary(meetingID: meeting.id, summary: "## Résumé\n\nLe client valide la maquette de l'accueil ; la page Contact reste à revoir avant vendredi.")
            }
        }
        let library = MeetingLibrary(store: meetingStore)
        let projects = ProjectLibrary(store: projectStore, meetings: MeetingStore(database))
        let agenda = AgendaLibrary(database: database)
        let router = WindowRouter()
        try await Task.sleep(for: .milliseconds(400))
        for (section, name) in [(SidebarItem.home, "accueil"), (.calendar, "calendrier"), (.contacts, "contacts")] {
            router.section = section
            if section == .contacts { router.contactSelection = camille.id }
            try await LiveWindow.capture(MainWindowView(library: library, projects: projects, agenda: agenda, router: router,
                                                        paths: AppPaths(root: root, logs: root)) { EmptyView() },
                                         to: output.appending(path: "\(name).png"))
        }
        // 18/11: at the window's smallest width, the lists of the Accueil come above Colin's column (the Accueil with
        // its mails and its lines is in `HomeScreenTests`).
        router.section = .home
        try await LiveWindow.capture(MainWindowView(library: library, projects: projects, agenda: agenda, router: router,
                                                    paths: AppPaths(root: root, logs: root)) { EmptyView() },
                                     to: output.appending(path: "accueil-etroit.png"), size: NSSize(width: MainWindowView<EmptyView>.minimumWidth, height: 780))
        // 14/11: Réglages › Comptes Google, one mailbox authorized, two still to authorize.
        try calendar.setGrantedScopes(email: "moi@exemple.fr", scopes: "openid https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/gmail.modify")
        try await Task.sleep(for: .milliseconds(300))
        router.section = .settings
        // 16/11: Réglages › Calendrier in the dark too.
        for (pane, dark) in [(SettingsPane.accounts, false), (.calendar, false), (.calendar, true)] {
            router.settingsPane = pane
            try await LiveWindow.capture(MainWindowView(library: library, projects: projects, agenda: agenda, router: router,
                                                        paths: AppPaths(root: root, logs: root)) { EmptyView() },
                                         to: output.appending(path: "reglages-\(pane.rawValue)\(dark ? "-sombre" : "").png"),
                                         size: NSSize(width: 1_000, height: 860), dark: dark)
        }
    }
    /// Contacts (15/11): the list by last exchange, and a contact's page with its projects, mails, events and
    /// meetings, in light and dark, narrow and wide. Every person here is made up.
    @Test func theContactsSection() async throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"]), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appending(path: "contacts \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase.inMemory()
        let account = "paul@atelier-nord.exemple"
        let calendar = CalendarStore(database)
        try calendar.addAccount(email: account, at: Date())
        try calendar.setGrantedScopes(email: account, scopes: "openid https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/gmail.modify")
        let projectStore = ProjectStore(database)
        var projects: [String: ProjectRow] = [:]
        for (name, color) in [("Site vitrine", "blue"), ("Identité", "purple"), ("Catalogue", "orange"), ("Atelier Nord", "green")] {
            var project = try projectStore.addProject(name: name, status: .priorite1, at: Date())
            project.color = color
            try projectStore.save(project, at: Date())
            projects[name] = project
        }
        let contacts = ContactStore(database)
        func person(_ name: String, _ email: String, _ company: String?, in names: [String] = []) throws -> ContactRow {
            let contact = try contacts.upsert(email: email, name: name, company: company, at: Date())
            for name in names { try contacts.include(contactID: contact.id, projectID: try #require(projects[name]).id, at: Date()) }
            return contact
        }
        var camille = try person("Camille Martin", "camille.martin@exemple-studio.fr", "Exemple Studio", in: ["Site vitrine", "Identité", "Catalogue"])
        camille.phone = "06 12 34 56 78"
        camille.notes = "Préfère un appel le matin. Valide les maquettes avec son associé le jeudi."
        try contacts.save(camille, at: Date())
        let jules = try person("Jules Durand", "jules@atelier-nord.fr", "Atelier Nord", in: ["Atelier Nord"])
        let nina = try person("Nina Roche", "nina.roche@exemple-studio.fr", "Exemple Studio", in: ["Site vitrine"])
        let lou = try person("Lou Bernard", "lou@studio-sud.exemple", "Studio Sud")
        try person("Marc Petit", "marc.petit@exemple.fr", nil)
        let sarah = try person("Sarah Lambert", "sarah@maison-lumiere.exemple", "Maison Lumière", in: ["Catalogue"])
        let hugo = try person("Hugo Moreau", "hugo.moreau@agence-orbe.exemple", "Agence Orbe", in: ["Identité"])
        try person("Inès Garnier", "ines@garnier-conseil.exemple", nil)

        // The mails: seven threads with Camille (five shown, then « Voir les 2 autres »), one each with Nina and Sarah.
        let me = MailAddress(name: "Paul", email: account)
        func mail(_ id: String, days: Double, from: MailAddress, to: [MailAddress], subject: String, snippet: String, unread: Bool = false) -> MailMessageRow {
            let sent = from.email == account
            return MailMessageRow(account: account, messageID: id, threadID: "t-\(id)", date: Date().addingTimeInterval(-days * 86_400), sender: from, to: to,
                                  subject: subject, snippet: snippet,
                                  labels: sent ? ["SENT"] : ["INBOX", "CATEGORY_PERSONAL"] + (unread ? ["UNREAD"] : []))
        }
        let camilleMail = MailAddress(name: "Camille Martin", email: camille.email!)
        try MailStore(database).apply(account: account, upserts: [
            mail("1", days: 0.1, from: camilleMail, to: [me], subject: "Maquette v2 du site", snippet: "Voici la deuxième version, avec la page Contact revue.", unread: true),
            mail("2", days: 1.2, from: me, to: [camilleMail], subject: "Devis signé", snippet: "Merci, je lance la production lundi."),
            mail("3", days: 4, from: camilleMail, to: [me], subject: "Photos de l'équipe", snippet: "Les photos arrivent jeudi, en haute définition."),
            mail("4", days: 9, from: camilleMail, to: [me], subject: "Retours sur la typographie", snippet: "On garde la deuxième proposition, un peu plus serrée."),
            mail("5", days: 15, from: me, to: [camilleMail], subject: "Planning de novembre", snippet: "Je te propose trois créneaux pour la revue."),
            mail("6", days: 26, from: camilleMail, to: [me], subject: "Accès au serveur", snippet: "Les identifiants sont dans le coffre partagé."),
            mail("7", days: 40, from: camilleMail, to: [me], subject: "Premier échange", snippet: "Ravie de travailler avec toi sur ce projet."),
            mail("8", days: 10, from: MailAddress(name: "Nina Roche", email: nina.email!), to: [me], subject: "Textes de l'accueil", snippet: "Voici les textes relus."),
            mail("9", days: 95, from: me, to: [MailAddress(name: "Sarah Lambert", email: sarah.email!)], subject: "Catalogue 2027", snippet: "Le chemin de fer en pièce jointe."),
        ])

        // The meetings, each with the first sentence of its summary.
        let meetingStore = MeetingStore(database)
        for (index, (title, days, people)) in [("Revue des maquettes", 2.0, [camille.id, jules.id]), ("Cadrage du catalogue", 12, [camille.id]),
                                                ("Atelier identité", 0.05, [hugo.id]), ("Premier rendez-vous", 38, [camille.id])].enumerated() {
            let start = Date().addingTimeInterval(-days * 86_400)
            let meeting = MeetingRow(createdAt: start, status: .ended, source: .dia, candidateKey: "t/\(index)", title: title, startedAt: start,
                                     endedAt: start.addingTimeInterval(2_700))
            try meetingStore.save(meeting)
            try contacts.setParticipants(meetingID: meeting.id, contactIDs: people)
            if index < 2 {
                try meetingStore.setSummary(meetingID: meeting.id, summary: "## Résumé\n\nLe client valide la maquette de l'accueil ; la page Contact reste à revoir avant vendredi.")
            }
        }

        // The events: one tomorrow, the others past.
        let guests = { (emails: [String]) in [Attendee(email: account, response: "accepted", isSelf: true)] + emails.map { Attendee(email: $0, response: "accepted") } }
        let today = Calendar.current.startOfDay(for: Date())
        func at(_ day: Double, _ hour: Double) -> Date { today.addingTimeInterval(day * 86_400 + hour * 3_600) }
        try calendar.applyGoogle(account: account, changed: [
            CalendarEventRow(account: account, eventID: "e1", title: "Atelier maquette", startAt: at(1, 14), endAt: at(1, 15), meetCode: "abc-defg-hij",
                             attendees: guests([camille.email!, nina.email!]), updatedAt: Date()),
            CalendarEventRow(account: account, eventID: "e2", title: "Revue des maquettes", startAt: at(-2, 10), endAt: at(-2, 11),
                             attendees: guests([camille.email!, jules.email!]), updatedAt: Date()),
            CalendarEventRow(account: account, eventID: "e3", title: "Point hebdo", startAt: at(-7, 9.5), endAt: at(-7, 10), attendees: guests([camille.email!]), updatedAt: Date()),
            CalendarEventRow(account: account, eventID: "e4", title: "Cadrage du catalogue", startAt: at(-12, 15), endAt: at(-12, 16), attendees: guests([camille.email!]), updatedAt: Date()),
            CalendarEventRow(account: account, eventID: "e5", title: "Déjeuner Studio Sud", startAt: at(-20, 12.5), endAt: at(-20, 14), attendees: guests([lou.email!]), updatedAt: Date()),
        ], cancelled: [], at: Date())

        let agenda = AgendaLibrary(database: database)
        let mails = MailLibrary(agenda: agenda, root: root, defaults: UserDefaults(suiteName: "contacts-\(UUID().uuidString)")!)
        let library = MeetingLibrary(store: meetingStore)
        let projectLibrary = ProjectLibrary(store: projectStore, meetings: meetingStore)
        let router = WindowRouter()
        router.section = .contacts
        router.contactSelection = camille.id
        try await Task.sleep(for: .milliseconds(600))
        func window() -> some View {
            MainWindowView(library: library, projects: projectLibrary, agenda: agenda, mails: mails, router: router, paths: AppPaths(root: root, logs: root)) { EmptyView() }
        }
        for dark in [false, true] {
            try await LiveWindow.capture(window(), to: output.appending(path: dark ? "contacts-page-sombre.png" : "contacts-page.png"),
                                         size: NSSize(width: 1_280, height: 860), dark: dark, wait: .milliseconds(2_000))
        }
        try await LiveWindow.capture(window(), to: output.appending(path: "contacts-large.png"), size: NSSize(width: 1_680, height: 980), wait: .milliseconds(2_000))
        router.contactSelection = jules.id
        try await LiveWindow.capture(window(), to: output.appending(path: "contacts-jules.png"),
                                     size: NSSize(width: MainWindowView<EmptyView>.minimumWidth, height: 780), wait: .milliseconds(2_000))
    }

    /// The event editor (14/11).
    @Test func theEventEditor() async throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"]), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let database = try AppDatabase.inMemory()
        try CalendarStore(database).addAccount(email: "paul@atelier-nord.fr", at: Date())
        try ContactStore(database).upsert(email: "camille.martin@exemple-studio.fr", name: "Camille Martin", company: "Exemple Studio", at: Date())
        let agenda = AgendaLibrary(database: database)
        try await Task.sleep(for: .milliseconds(300))
        let event = CalendarEventRow(account: "paul@atelier-nord.fr", eventID: "e", title: "Revue des maquettes", startAt: Date(), endAt: Date().addingTimeInterval(3_600),
                                     meetCode: "abc-defg-hij", location: "Atelier", organizer: "paul@atelier-nord.fr",
                                     attendees: [Attendee(email: "camille.martin@exemple-studio.fr", response: "accepted")], updatedAt: Date())
        try await LiveWindow.capture(EventEditor(agenda: agenda, request: EditorRequest(event: event)), to: output.appending(path: "editeur.png"),
                                     size: NSSize(width: 520, height: 680))
    }
}

/// A window as the app makes it. With `POLHUB_LIVE=1`, it is shown on screen and captured by the system, glass
/// and toolbar included (14/11: the offscreen drawing leaves them out); otherwise it is drawn offscreen.
@MainActor
enum LiveWindow {
    static func capture(_ view: some View, to file: URL, size: NSSize = NSSize(width: 1_280, height: 780), dark: Bool = false,
                        wait: Duration = .milliseconds(1_500)) async throws {
        let live = ProcessInfo.processInfo.environment["POLHUB_LIVE"] != nil
        let host = NSHostingController(rootView: view)
        host.sceneBridgingOptions = [.title, .toolbars]
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        defer { window.close() }
        if live {
            _ = NSApplication.shared
            window.setFrameTopLeftPoint(NSPoint(x: 40, y: (NSScreen.main?.visibleFrame.maxY ?? 900) - 20))
            window.orderFrontRegardless()
            try await Task.sleep(for: wait)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-l", "\(window.windowNumber)", "-o", "-x", file.path]
            try process.run()
            process.waitUntilExit()
        } else {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(600))
            window.layoutIfNeeded()
            let content = try #require(window.contentView)
            let bitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: file)
        }
    }
}
