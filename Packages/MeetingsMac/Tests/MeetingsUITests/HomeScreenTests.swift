import Agenda
import AppKit
import Colin
import Domain
import Foundation
import Mail
import Persistence
import PolhubDesign
import ProjectsUI
import SwiftUI
import Testing
@testable import MeetingsUI

/// The new Accueil with made-up data (18/11): `POLHUB_LIVE=1 POLHUB_SNAPSHOTS=<dossier hors du dépôt> swift test --filter
/// HomeScreenTests`. Wide and at the window's smallest width, light and dark. Nothing of it is kept in the repository;
/// every name, address and subject is invented.
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"] != nil))
struct HomeScreenTests {
    static let me = "moi@exemple.fr"

    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
        #expect(condition())
    }

    @Test func theHome() async throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"]), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appending(path: "accueil \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

        let database = try AppDatabase.inMemory()
        let calendar = CalendarStore(database)
        try calendar.addAccount(email: Self.me, at: ago(400))
        try calendar.setGrantedScopes(email: Self.me, scopes: "openid https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/gmail.modify")

        // Three projects where it is Paul's turn, one to deliver in two days; a fourth waiting for its client.
        let projects = ProjectStore(database)
        var martin = try projects.addProject(name: "Cabinet Martin", status: .priorite2, at: ago(100))
        let original = martin
        martin.dueDate = now.addingTimeInterval(2 * 86_400)
        try projects.saveChanges(from: original, to: martin, at: ago(3))
        let nord = try projects.addProject(name: "Studio Nord", status: .priorite2, at: ago(90))
        let leroy = try projects.addProject(name: "Maison Leroy", status: .priorite2, at: ago(80))
        let dupont = try projects.addProject(name: "Atelier Dupont", status: .priorite1, at: ago(70))
        let contacts = ContactStore(database)
        for (name, email, project) in [("Claire Morel", "claire@cabinet-martin.exemple", martin.id), ("Marc Dubois", "marc@studio-nord.exemple", nord.id),
                                       ("Anne Leroy", "anne@maison-leroy.exemple", leroy.id)] {
            let contact = try contacts.upsert(email: email, name: name, company: nil, at: ago(60))
            try contacts.link(contactID: contact.id, projectID: project, origin: .paul, at: ago(60))
        }

        // The mails: Marc waits for four days, Anne is silent for nine, Claire wrote last evening.
        let store = MailStore(database)
        func received(_ id: String, thread: String, from: String, name: String, subject: String, at date: Date) -> MailMessageRow {
            MailMessageRow(account: Self.me, messageID: id, threadID: thread, date: date, sender: MailAddress(name: name, email: from), to: [MailAddress(email: Self.me)],
                           subject: subject, snippet: "", labels: ["INBOX", "CATEGORY_PERSONAL"])
        }
        func sent(_ id: String, thread: String, to: String, subject: String, at date: Date) -> MailMessageRow {
            MailMessageRow(account: Self.me, messageID: id, threadID: thread, date: date, sender: MailAddress(name: "Moi", email: Self.me), to: [MailAddress(email: to)],
                           subject: subject, snippet: "", labels: ["SENT"])
        }
        try store.apply(account: Self.me, upserts: [
            sent("m1", thread: "m", to: "marc@studio-nord.exemple", subject: "Page d'accueil", at: ago(12)),
            received("m2", thread: "m", from: "marc@studio-nord.exemple", name: "Marc Dubois", subject: "Page d'accueil", at: ago(4.2)),
            received("a1", thread: "a", from: "anne@maison-leroy.exemple", name: "Anne Leroy", subject: "Plans du rez-de-chaussée", at: ago(15)),
            sent("a2", thread: "a", to: "anne@maison-leroy.exemple", subject: "Plans du rez-de-chaussée", at: ago(9.3)),
            sent("c1", thread: "c", to: "claire@cabinet-martin.exemple", subject: "Devis d'avril", at: ago(6)),
            received("c2", thread: "c", from: "claire@cabinet-martin.exemple", name: "Claire Morel", subject: "Devis d'avril", at: ago(0.3)),
        ])
        // An agent prepared the answer to Claire.
        try store.saveDraft(MailDraftRow(account: Self.me, mode: .reply, threadKey: MailThreadRow.key(account: Self.me, threadID: "c"),
                                         to: [MailAddress(name: "Claire Morel", email: "claire@cabinet-martin.exemple")], subject: "Re: Devis d'avril",
                                         body: "Bonjour Claire, voici le devis corrigé.", signature: false, origin: .agent, createdAt: ago(0.05)))

        // The day: a Meet in forty minutes, a point later; a meeting of the day before yesterday, in no project.
        func event(_ id: String, _ title: String, start: Date, minutes: Double, meet: String? = nil, project: UUID? = nil) -> CalendarEventRow {
            CalendarEventRow(account: Self.me, eventID: id, title: title, startAt: start, endAt: start.addingTimeInterval(minutes * 60), meetCode: meet,
                             attendees: [Attendee(email: Self.me, response: "accepted", isSelf: true)], projectID: project, projectOrigin: project == nil ? nil : .paul,
                             updatedAt: now)
        }
        let past = event("e0", "Appel découverte", start: ago(2), minutes: 45)
        try calendar.applyGoogle(account: Self.me, changed: [
            event("e1", "Atelier Dupont", start: now.addingTimeInterval(40 * 60), minutes: 60, meet: "abc-defg-hij", project: dupont.id),
            event("e2", "Point Studio Nord", start: now.addingTimeInterval(3.5 * 3_600), minutes: 30, project: nord.id),
            event("e3", "Déjeuner équipe", start: now.addingTimeInterval(26 * 3_600), minutes: 60),
            past,
        ], cancelled: [], at: now)
        try calendar.setProject(eventID: CalendarEventRow.key(account: Self.me, eventID: "e1"), projectID: dupont.id, origin: .paul)
        try calendar.setProject(eventID: CalendarEventRow.key(account: Self.me, eventID: "e2"), projectID: nord.id, origin: .paul)
        let recorded = MeetingRow(createdAt: past.startAt, status: .ended, source: .dia, candidateKey: "t/e0", title: past.title, startedAt: past.startAt,
                                  endedAt: past.endAt)
        try MeetingStore(database).save(recorded)
        try calendar.setMeeting(eventID: past.id, meetingID: recorded.id)

        // Paul was last there yesterday at 19:40: « Le point » says what came since.
        let suite = try #require(UserDefaults(suiteName: "accueil-\(UUID().uuidString)"))
        let paris = CalendarView.calendar
        let yesterday = try #require(paris.date(bySettingHour: 19, minute: 40, second: 0, of: ago(1)))
        suite.set(try JSONEncoder().encode(Presence.State(lastSeen: yesterday, since: nil, preparedAt: yesterday)), forKey: Preferences.Key.colinPresence)
        // Step 3 (18/11): since then, one of Colin's rules after a mail of Paul's, and a session that wrote in a project.
        try projects.edit(KanbanEdit(projectID: nord.id, status: .priorite1, todo: "En attente retour de Marc", dueDate: nil,
                                     journal: "Mail envoyé à Marc le 18/11", reason: "Après ton mail à Marc, 9:50", source: "mail:capture"),
                          by: .colin, at: now.addingTimeInterval(-3_570))
        let session = projects.signed(.agent)
        try session.saveAction(ActionRow(projectID: leroy.id, text: "Envoyer les plans du rez-de-chaussée", position: 9, createdAt: now.addingTimeInterval(-7_200)))
        try session.addJournal(ProjectJournalRow(projectID: leroy.id, date: now.addingTimeInterval(-7_200), title: "Plans revus avec l'architecte", body: "",
                                                 createdAt: now.addingTimeInterval(-7_200)))

        let meetingStore = MeetingStore(database)
        let library = MeetingLibrary(store: meetingStore)
        let agenda = AgendaLibrary(database: database)
        let gmail = SilentGmail()
        let mails = MailLibrary(agenda: agenda, root: root, defaults: suite, flavor: .prod, send: { _ in gmail.send }, vault: MemoryScheduleVault())
        try await waitUntil { mails.accounts.count == 1 }
        let colin = ColinLibrary(agenda: agenda, mails: mails, defaults: suite, settle: .milliseconds(30))
        colin.seen()
        try await waitUntil { colin.briefingAt != nil && colin.review.count == 4 && colin.briefingChanges.count == 2 }
        #expect(colin.briefing.last?.hasSuffix("2 projets ont bougé.") == true)
        let router = WindowRouter()
        router.section = .home
        let window = MainWindowView(library: library, projects: ProjectLibrary(store: projects, meetings: meetingStore), agenda: agenda, mails: mails, colin: colin,
                                    router: router, paths: AppPaths(root: root, logs: root)) { EmptyView() }
        let live = ProcessInfo.processInfo.environment["POLHUB_LIVE"] != nil
        // The page alone on the window's ground, at the widths the window gives it: what an offscreen drawing shows
        // faithfully, in the dark too.
        let page = HomeView(agenda: agenda, mails: mails, colin: colin, router: router).background(Color(nsColor: .windowBackgroundColor))
        let narrow = MainWindowView<EmptyView>.minimumWidth - MainWindowView<EmptyView>.sidebarWidth
        for dark in [false, true] {
            let suffix = dark ? "-sombre" : ""
            try await LiveWindow.capture(page, to: output.appending(path: "accueil-page\(suffix).png"), size: NSSize(width: 928, height: 700), dark: dark)
            try await LiveWindow.capture(page, to: output.appending(path: "accueil-page-etroit\(suffix).png"), size: NSSize(width: narrow, height: 860), dark: dark)
            // The whole window, with its glass: only on screen.
            guard live else { continue }
            try await LiveWindow.capture(window, to: output.appending(path: "accueil\(suffix).png"), size: NSSize(width: 1_180, height: 760), dark: dark)
            try await LiveWindow.capture(window, to: output.appending(path: "accueil-etroit\(suffix).png"),
                                         size: NSSize(width: MainWindowView<EmptyView>.minimumWidth, height: 900), dark: dark)
        }

        // « Voir »: what moved without Paul, each with « Annuler ».
        try await LiveWindow.capture(ChangesSheet(colin: colin).background(Color(nsColor: .windowBackgroundColor)),
                                     to: output.appending(path: "accueil-point-voir.png"), size: NSSize(width: 620, height: 420))

        // « Relire » : the answer to Claire opens under her thread, over the Accueil.
        let draft = try #require(mails.drafts.first { $0.origin == .agent })
        mails.open(draft) { router.homeMail = $0 }
        #expect(router.homeMail == MailThreadRow.key(account: Self.me, threadID: "c") && router.section == .home)
        try await LiveWindow.capture(page, to: output.appending(path: "accueil-relire.png"), size: NSSize(width: 928, height: 700))
        router.homeMail = nil

        // Nothing waits, nothing left today: the lists say so.
        let empty = try AppDatabase.inMemory()
        try CalendarStore(empty).addAccount(email: Self.me, at: ago(400))
        let quiet = AgendaLibrary(database: empty)
        let calm = ColinLibrary(agenda: quiet, mails: nil, defaults: try #require(UserDefaults(suiteName: "accueil-\(UUID().uuidString)")), settle: .milliseconds(30))
        calm.seen()
        try await waitUntil { calm.briefingAt != nil }
        let bare = MainWindowView(library: MeetingLibrary(store: MeetingStore(empty)), agenda: quiet, colin: calm, router: router,
                                  paths: AppPaths(root: root, logs: root)) { EmptyView() }
        try await LiveWindow.capture(bare, to: output.appending(path: "accueil-vide.png"), size: NSSize(width: 1_180, height: 760))
        _ = window

        // Colin's bar and thread (18/11): an invented exchange, then each state of the bar. Claude Code is a script.
        let colinStore = ColinStore(database)
        let asked = now.addingTimeInterval(-3_600)
        try colinStore.add(ColinMessageRow(author: .paul, text: "Où on en est sur Cabinet Martin ?", createdAt: ago(1)))
        try colinStore.add(ColinMessageRow(author: .colin, text: "Claire attend la maquette v2, à livrer jeudi. Le devis est parti lundi, sans réponse.",
                                           createdAt: ago(1).addingTimeInterval(20), costUSD: 0.04))
        try colinStore.add(ColinMessageRow(author: .paul, text: "Écris-moi un WhatsApp pour Marc : je lui envoie la maquette ce soir.", createdAt: asked))
        try colinStore.add(ColinMessageRow(author: .colin, text: """
            Voilà, court et à ton ton.
            ```message
            Salut Marc, je t'envoie la maquette ce soir. Bonne journée !
            ```
            ```retenir
            Marc préfère WhatsApp au mail.
            ```
            """, createdAt: asked.addingTimeInterval(15), costUSD: 0.03))
        func colinThread(on: Bool, busy: Bool, hanging: Bool) throws -> ColinThread {
            let defaults = try #require(UserDefaults(suiteName: "accueil-colin-\(UUID().uuidString)"))
            defaults.set(on, forKey: Preferences.Key.colinOn)
            let good = ClaudeInit(model: "claude-opus-5-5", permissionMode: "dontAsk", apiKeySource: "none", tools: ColinTool.allowed, servers: ["polhub": "connected"])
            let launcher = FakeLauncher { _, _ in
                FakeSession(onSend: { _, rank in
                    rank == 1 ? [.initialized(good), .result(ClaudeResult(text: "prêt"))]
                        : [.initialized(good), .assistant(text: "", tools: ["mcp__polhub__mails"]), .textDelta("Marc t'a écrit lundi ") ] + (hanging ? [] : [])
                })
            }
            let work = root.appending(path: "colin-travail", directoryHint: .isDirectory)
            let setup = ColinSetup(binary: URL(fileURLWithPath: "/usr/bin/true"), helper: URL(fileURLWithPath: "/usr/bin/true"),
                                   base: URL(fileURLWithPath: "/tmp/essai.sqlite"), account: nil, work: work)
            return ColinThread(database: database, runner: ColinRunner(launcher: launcher, setup: { setup }), defaults: defaults, isBusy: { busy })
        }
        let running = try colinThread(on: true, busy: false, hanging: false)
        try await waitUntil { running.messages.count == 4 && running.changes.count == 1 }
        func colinPage(_ thread: ColinThread) -> some View {
            HomeView(agenda: agenda, mails: mails, colin: colin, thread: thread, router: router).background(Color(nsColor: .windowBackgroundColor))
        }
        for dark in [false, true] {
            let suffix = dark ? "-sombre" : ""
            try await LiveWindow.capture(colinPage(running), to: output.appending(path: "accueil-colin\(suffix).png"), size: NSSize(width: 928, height: 760), dark: dark)
            try await LiveWindow.capture(colinPage(running), to: output.appending(path: "accueil-colin-etroit\(suffix).png"), size: NSSize(width: narrow, height: 900), dark: dark)
        }
        // Réglages › Colin, with what Colin knows.
        try running.saveKnowledge("Écrire court, à mon ton.\nMon lien de rendez-vous : https://exemple.fr/rdv")
        try await LiveWindow.capture(ColinSettingsPane(thread: running, probe: nil).background(Color(nsColor: .windowBackgroundColor)),
                                     to: output.appending(path: "reglages-colin-barre.png"), size: NSSize(width: 700, height: 860))
        running.draft = "Et Maison Leroy ?"
        running.send()
        try await waitUntil { !running.streaming.isEmpty }
        try await LiveWindow.capture(colinPage(running), to: output.appending(path: "accueil-colin-reponse.png"), size: NSSize(width: 928, height: 760))
        running.turnOff()
        try await waitUntil { running.status == .off }
        try await LiveWindow.capture(colinPage(running), to: output.appending(path: "accueil-colin-arret.png"), size: NSSize(width: 928, height: 760))
        let calling = try colinThread(on: true, busy: true, hanging: false)
        calling.draft = "Prépare la relance d'Anne"
        calling.send()
        try await waitUntil { calling.status == .waitingCall }
        try await LiveWindow.capture(colinPage(calling), to: output.appending(path: "accueil-colin-call.png"), size: NSSize(width: 928, height: 760))
        if live {
            let windowed = MainWindowView(library: library, projects: ProjectLibrary(store: projects, meetings: meetingStore), agenda: agenda, mails: mails, colin: colin,
                                          thread: try colinThread(on: true, busy: false, hanging: false), router: router, paths: AppPaths(root: root, logs: root)) { EmptyView() }
            for dark in [false, true] {
                try await LiveWindow.capture(windowed, to: output.appending(path: "accueil-colin-fenetre\(dark ? "-sombre" : "").png"),
                                             size: NSSize(width: 1_180, height: 760), dark: dark)
            }
            try await LiveWindow.capture(windowed, to: output.appending(path: "accueil-colin-fenetre-etroite.png"),
                                         size: NSSize(width: MainWindowView<EmptyView>.minimumWidth, height: 900))
        }
    }
}
