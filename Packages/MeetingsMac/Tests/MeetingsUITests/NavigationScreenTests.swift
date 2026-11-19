import AppKit
import Agenda
import Domain
import Foundation
import Mail
import MailFormat
import Notifications
import Persistence
import PolhubDesign
import ProjectsUI
import SwiftUI
import Testing
@testable import MeetingsUI

/// The window's frame (lot 4, 19/11): the sidebar, the bar of the mails' list, the panels and their ✕, the titles,
/// the links between objects. Every person, project and mail here is made up. Not part of `make check`:
/// `POLHUB_LIVE=1 POLHUB_SNAPSHOTS=<dossier> swift test --filter NavigationScreenTests` (live: glass and toolbar).
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"] != nil), .serialized)
struct NavigationScreenTests {
    /// A made-up world: three mailboxes, a project with a meeting and an event, two notifications not seen yet, the
    /// three pages of « Inspiration ».
    @MainActor struct World {
        let root: URL
        let database: AppDatabase
        let agenda: AgendaLibrary
        let mails: MailLibrary
        let projects: ProjectLibrary
        let library: MeetingLibrary
        let hub: NotificationHub
        let inspiration: InspirationLibrary
        let inspirationWorld: InspirationTestWorld
        let project: ProjectRow
        let meeting: MeetingRow
        let router = WindowRouter()

        func window() -> some View {
            MainWindowView(library: library, projects: projects, agenda: agenda, mails: mails, inspiration: inspiration,
                           notifications: hub, router: router, paths: AppPaths(root: root, logs: root)) { EmptyView() }
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

    private func world() async throws -> World {
        let root = FileManager.default.temporaryDirectory.appending(path: "navigation \(UUID().uuidString)", directoryHint: .isDirectory)
        let database = try AppDatabase.inMemory()
        let calendar = CalendarStore(database)
        let both = "openid https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/gmail.modify"
        for (index, email) in ["moi@exemple.fr", "perso@gmail.com", "paul@atelier-nord.fr"].enumerated() {
            try calendar.addAccount(email: email, at: Date().addingTimeInterval(Double(index)))
            try calendar.setGrantedScopes(email: email, scopes: both)
        }
        let store = MailStore(database), files = MailFiles(root: root)
        func mail(_ id: String, _ account: String, from: MailAddress, subject: String, snippet: String, hours: Double, unread: Bool = false) throws -> MailMessageRow {
            let row = MailMessageRow(account: account, messageID: id, threadID: "t-\(id)", date: Date().addingTimeInterval(-hours * 3_600), sender: from,
                                     to: [MailAddress(email: account)], subject: subject, snippet: snippet,
                                     labels: ["INBOX", "CATEGORY_PERSONAL"] + (unread ? ["UNREAD"] : []), authenticated: true, hasBody: true, bodyIsHTML: true)
            let url = files.body(of: row)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("<p>\(snippet)</p><p>\(from.name ?? "")</p>".utf8).write(to: url)
            return row
        }
        let camille = MailAddress(name: "Camille Martin", email: "camille.martin@exemple-studio.fr")
        let jules = MailAddress(name: "Jules Durand", email: "jules@atelier-nord.fr")
        try store.apply(account: "moi@exemple.fr", upserts: [
            try mail("a1", "moi@exemple.fr", from: camille, subject: "Maquette v2 du site", snippet: "Voici la deuxième version, avec la page Contact revue.",
                     hours: 1, unread: true),
            try mail("a2", "moi@exemple.fr", from: camille, subject: "Photos de l'équipe", snippet: "Les photos arrivent jeudi.", hours: 30),
        ])
        try store.apply(account: "perso@gmail.com", upserts: [
            try mail("b1", "perso@gmail.com", from: MailAddress(name: "Nina Roche", email: "nina.roche@exemple.fr"), subject: "Photos du week-end",
                     snippet: "Je t'envoie les photos de dimanche.", hours: 20),
        ])
        try store.apply(account: "paul@atelier-nord.fr", upserts: [
            try mail("c1", "paul@atelier-nord.fr", from: jules, subject: "Devis signé", snippet: "Le client a signé, on peut lancer.", hours: 8, unread: true),
        ])
        // The project, its contact, its meeting and its next event.
        let projectStore = ProjectStore(database)
        var project = try projectStore.addProject(name: "Site vitrine", status: .priorite1, at: Date())
        project.color = "blue"
        project.client = "Exemple Studio"
        project.todo = "Envoyer la maquette de l'accueil"
        try projectStore.save(project, at: Date())
        let contact = try ContactStore(database).upsert(email: camille.email, name: "Camille Martin", company: "Exemple Studio", at: Date())
        try ContactStore(database).link(contactID: contact.id, projectID: project.id, origin: .paul, at: Date())
        let meetingStore = MeetingStore(database)
        let start = Date().addingTimeInterval(-26 * 3_600)
        let meeting = MeetingRow(createdAt: start, status: .ended, source: .dia, candidateKey: "t/revue", title: "Revue des maquettes", startedAt: start,
                                 endedAt: start.addingTimeInterval(2_700))
        try meetingStore.save(meeting)
        try projectStore.setProject(meetingID: meeting.id, projectID: project.id)
        try meetingStore.setSummary(meetingID: meeting.id, summary: "## Résumé\n\nLe client valide la maquette ; la page Contact reste à revoir.")
        try calendar.applyGoogle(account: "moi@exemple.fr", changed: [
            CalendarEventRow(account: "moi@exemple.fr", eventID: "revue", title: "Revue des maquettes", startAt: start, endAt: start.addingTimeInterval(2_700),
                             meetCode: "abc-defg-hij", updatedAt: Date()),
            CalendarEventRow(account: "moi@exemple.fr", eventID: "atelier", title: "Atelier contenus", startAt: Date().addingTimeInterval(2 * 86_400),
                             endAt: Date().addingTimeInterval(2 * 86_400 + 3_600), meetCode: "klm-nopq-rst", updatedAt: Date()),
        ], cancelled: [], at: Date())
        try calendar.setMeeting(eventID: CalendarEventRow.key(account: "moi@exemple.fr", eventID: "revue"), meetingID: meeting.id)
        for id in ["revue", "atelier"] {
            try calendar.setProject(eventID: CalendarEventRow.key(account: "moi@exemple.fr", eventID: id), projectID: project.id, origin: .titre)
        }
        let agenda = AgendaLibrary(database: database)
        // Gmail's spam and trash, empty: no capture reaches Google.
        let gmail = AsideGmail([])
        let mails = MailLibrary(agenda: agenda, root: root, defaults: try #require(UserDefaults(suiteName: "navigation-\(UUID().uuidString)")),
                                send: { gmail.send(for: $0) })
        let inbox = NotificationInbox(file: nil)
        for (id, title) in [("n1", "Compte rendu prêt"), ("n2", "Camille Martin")] {
            inbox.record(PlannedNotice(id: id, fireDate: Date(), title: title, body: "Exemple", eventID: nil, meetCode: nil, account: nil, kind: .newEvent),
                         at: Date())
        }
        let hub = NotificationHub(agenda: agenda, client: SilentNotifications(), inbox: inbox)
        let inspirationWorld = try InspirationTestWorld(name: "navigation")
        try inspirationWorld.fill()
        let inspiration = inspirationWorld.library()
        let world = World(root: root, database: database, agenda: agenda, mails: mails,
                          projects: ProjectLibrary(store: projectStore, meetings: meetingStore), library: MeetingLibrary(store: meetingStore), hub: hub,
                          inspiration: inspiration, inspirationWorld: inspirationWorld, project: project, meeting: meeting)
        try await waitUntil { mails.accounts.count == 3 && inspiration.loaded.count == 3 && world.projects.loaded }
        try await Task.sleep(for: .milliseconds(400))
        return world
    }

    private func capture(_ world: World, _ name: String, dark: Bool = false, width: CGFloat = 1_180, wait: Duration = .milliseconds(1_800)) async throws {
        try await LiveWindow.capture(world.window(), to: try output().appending(path: "\(name).png"), size: NSSize(width: width, height: 780), dark: dark,
                                     wait: wait)
    }

    /// The sidebar with its folders, the bar of the list, the bell, the panels' ✕: light and dark.
    @Test func theMailsAndTheirPanels() async throws {
        let world = try await world()
        defer { world.clean() }
        UserDefaults.standard.set(true, forKey: Preferences.Key.floatingPages)
        world.router.openMail(nil)
        try await capture(world, "nav-mails")
        try await capture(world, "nav-mails-sombre", dark: true)
        // A folder of the rarer ones: « Spam ».
        world.mails.folder = .spam
        try await waitUntil { !world.mails.readingAside }
        try await capture(world, "nav-mails-spam")
        world.mails.folder = .inbox
        // A mailbox hidden: the list says so.
        world.mails.hidden = ["perso@gmail.com"]
        try await capture(world, "nav-mails-boite-masquee")
        world.mails.hidden = []
        // A thread over the list, then a new mail: their ✕.
        world.router.openMail(MailThreadRow.key(account: "moi@exemple.fr", threadID: "t-a1"))
        try await capture(world, "nav-fil", wait: .milliseconds(2_200))
        try await capture(world, "nav-fil-sombre", dark: true, wait: .milliseconds(2_200))
        // In its page (Réglages › Général): the way back on the left, the folder in the title, never the subject.
        UserDefaults.standard.set(false, forKey: Preferences.Key.floatingPages)
        try await capture(world, "nav-fil-page", wait: .milliseconds(2_200))
        UserDefaults.standard.set(true, forKey: Preferences.Key.floatingPages)
        world.router.openMail(nil)
        world.mails.newMail()
        try await capture(world, "nav-nouveau-mail")
        world.mails.closeComposer()
        // The narrowest window.
        try await capture(world, "nav-etroit", width: MainWindowView<EmptyView>.minimumWidth)
    }

    /// The other sections: a project over the board, a meeting and its links, Inspiration's pages, Contacts, Réglages.
    @Test func theOtherSections() async throws {
        let world = try await world()
        defer { world.clean() }
        UserDefaults.standard.set(true, forKey: Preferences.Key.floatingPages)
        world.router.section = .projects
        world.projects.selected = world.project.id
        try await capture(world, "nav-projet", width: 1_280)
        world.projects.selected = nil
        world.router.open(meetingID: world.meeting.id, at: nil)
        try await capture(world, "nav-reunion", width: 1_280)
        world.router.openInspiration(.website)
        try await capture(world, "nav-inspiration", width: 1_280, wait: .milliseconds(2_500))
        try await capture(world, "nav-inspiration-sombre", dark: true, width: 1_280, wait: .milliseconds(2_500))
        let site = try #require(world.inspiration.items(.website).first)
        world.router.openInspiration(.website, item: site.id)
        try await capture(world, "nav-inspiration-fiche", width: 1_280, wait: .milliseconds(2_500))
        world.router.section = .contacts
        try await capture(world, "nav-contacts", width: 1_280)
        world.router.openSettings(.calendar)
        try await capture(world, "nav-reglages-famille", width: 1_280)
        try await capture(world, "nav-reglages-famille-sombre", dark: true, width: 1_280)
    }
}
