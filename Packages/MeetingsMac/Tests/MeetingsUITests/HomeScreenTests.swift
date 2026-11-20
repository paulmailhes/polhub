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

    func waitUntil(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        for _ in 0..<300 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
        #expect(condition(), sourceLocation: sourceLocation)
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
        // « À faire » (0.36.0): Maison Leroy six days late, with its task; Atelier Dupont due today, set by Paul (a change
        // of Colin's would show in his thread too).
        var late = leroy
        late.dueDate = ago(6)
        late.todo = "Envoyer les plans du rez-de-chaussée"
        late.client = "Leroy & fils"
        try projects.saveChanges(from: leroy, to: late, at: ago(3))
        // 0.37.0: what is left to do on Maison Leroy, shown when its line unfolds.
        try projects.saveAction(ActionRow(projectID: leroy.id, text: "Relire le devis de l'électricien", position: 1, createdAt: ago(5)))
        try projects.saveAction(ActionRow(projectID: leroy.id, text: "Demander les photos du chantier", position: 2, createdAt: ago(5)))
        _ = try projects.setDue(dupont.id, to: CalendarView.calendar.startOfDay(for: now), journal: nil, at: ago(2))
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
            // Cabinet Martin's next call: « Livré » proposes it (one with Anne would hush « Anne ne répond plus »).
            event("e4", "Point Cabinet Martin", start: now.addingTimeInterval(3 * 86_400), minutes: 30, project: martin.id),
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
        try projects.edit(KanbanEdit(projectID: nord.id, status: .priorite1, todo: "Attend le retour de Marc", dueDate: nil,
                                     journal: "Mail envoyé à Marc le 18 nov.", reason: "Après ton mail à Marc, 9:50", source: "mail:capture"),
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
        #expect(colin.briefing.last?.text.hasSuffix("2 projets ont bougé.") == true)
        let router = WindowRouter()
        router.section = .home
        let window = MainWindowView(library: library, projects: ProjectLibrary(store: projects, meetings: meetingStore), agenda: agenda, mails: mails, colin: colin,
                                    router: router, paths: AppPaths(root: root, logs: root)) { EmptyView() }
        let live = ProcessInfo.processInfo.environment["POLHUB_LIVE"] != nil
        // The page alone on the window's ground, at the widths the window gives it: what an offscreen drawing shows
        // faithfully, in the dark too.
        // Two invented Claude accounts, as Vigie would say them (0.36.0).
        let accounts = ClaudeAccountsModel(accounts: [
            ClaudeAccount(id: "travail", label: "Travail", isDefault: true, connected: true,
                          usage: .init(session: .init(pct: 82, resetsAt: now.addingTimeInterval(5_400)),
                                       week: .init(pct: 71, resetsAt: now.addingTimeInterval(4 * 86_400), fullAt: now.addingTimeInterval(1.6 * 86_400)),
                                       weekModel: nil, observedAt: now)),
            ClaudeAccount(id: "perso", label: "Perso", isDefault: false, connected: true,
                          usage: .init(session: nil, week: .init(pct: 12, resetsAt: now.addingTimeInterval(4 * 86_400), fullAt: nil), weekModel: nil, observedAt: now)),
        ])
        let page = HomeView(agenda: agenda, mails: mails, colin: colin, router: router, accounts: accounts).background(Color(nsColor: .windowBackgroundColor))
        let narrow = MainWindowView<EmptyView>.minimumWidth - MainWindowView<EmptyView>.sidebarWidth
        for dark in [false, true] {
            let suffix = dark ? "-sombre" : ""
            try await LiveWindow.capture(page, to: output.appending(path: "accueil-page\(suffix).png"), size: NSSize(width: 928, height: 1_050), dark: dark)
            try await LiveWindow.capture(page, to: output.appending(path: "accueil-page-etroit\(suffix).png"), size: NSSize(width: narrow, height: 860), dark: dark)
            // The whole window, with its glass: only on screen.
            guard live else { continue }
            try await LiveWindow.capture(window, to: output.appending(path: "accueil\(suffix).png"), size: NSSize(width: 1_180, height: 760), dark: dark)
            try await LiveWindow.capture(window, to: output.appending(path: "accueil-etroit\(suffix).png"),
                                         size: NSSize(width: MainWindowView<EmptyView>.minimumWidth, height: 900), dark: dark)
        }

        // « Voir »: what moved without Paul, each with « Annuler ».
        try await LiveWindow.capture(ChangesSheet(colin: colin, router: router).background(Color(nsColor: .windowBackgroundColor)),
                                     to: output.appending(path: "accueil-point-voir.png"), size: NSSize(width: 620, height: 420))

        // « Relire » : the answer to Claire opens under her thread, over the Accueil.
        let draft = try #require(mails.drafts.first { $0.origin == .agent })
        mails.open(draft) { router.homeMail = $0 }
        #expect(router.homeMail == MailThreadRow.key(account: Self.me, threadID: "c") && router.section == .home)
        try await LiveWindow.capture(page, to: output.appending(path: "accueil-relire.png"), size: NSSize(width: 928, height: 700))
        router.homeMail = nil

        // 0.37.0: a line of « À faire » unfolded on what is to do.
        let todoLibrary = TodoLibrary(database: database)
        try await waitUntil { (todoLibrary.openActions[leroy.id]?.count ?? 0) == 3 }
        try await LiveWindow.capture(TodoCard(todo: todoLibrary, agenda: agenda, router: router, opened: leroy.id).padding(Space.l)
                                        .frame(width: HomeLayout.dayMinimumWidth + 2 * Space.l).background(Color(nsColor: .windowBackgroundColor)),
                                     to: output.appending(path: "accueil-a-faire-ouvert.png"), size: NSSize(width: HomeLayout.dayMinimumWidth + 2 * Space.l, height: 560))

        // Lot 5 (19/11): a line under the pointer in each list — its action on the place kept for it, nothing else moved —,
        // the late line of « À faire » among them.
        let marc = try #require(colin.review.first { $0.kind == .reply })
        for dark in [false, true] {
            try await LiveWindow.capture(VStack(spacing: Space.l) {
                ReviewCard(colin: colin, agenda: agenda, mails: mails, router: router, thresholds: colin.thresholds, hovered: marc.id)
                TodoCard(todo: todoLibrary, agenda: agenda, router: router, hovered: leroy.id)
            }
            .padding(Space.l).frame(width: HomeLayout.dayMinimumWidth + 2 * Space.l).background(Color(nsColor: .windowBackgroundColor)),
            to: output.appending(path: "accueil-survol\(dark ? "-sombre" : "").png"), size: NSSize(width: HomeLayout.dayMinimumWidth + 2 * Space.l, height: 760),
            dark: dark)
        }

        // The evening (0.36.0): from the hour set, nothing left today, the Accueil shows tomorrow.
        let evening = try AppDatabase.inMemory()
        let eveningCalendar = CalendarStore(evening)
        try eveningCalendar.addAccount(email: Self.me, at: ago(400))
        let tomorrow = try #require(CalendarView.calendar.date(byAdding: .day, value: 1, to: CalendarView.calendar.startOfDay(for: now)))
        try eveningCalendar.applyGoogle(account: Self.me, changed: [
            event("t1", "Point Cabinet Martin", start: tomorrow.addingTimeInterval(9.5 * 3_600), minutes: 30, meet: "abc-defg-hij"),
            event("t2", "Atelier Dupont", start: tomorrow.addingTimeInterval(16.5 * 3_600), minutes: 60),
        ], cancelled: [], at: now)
        let eveningAgenda = AgendaLibrary(database: evening)
        let eveningColin = ColinLibrary(agenda: eveningAgenda, mails: nil, defaults: try #require(UserDefaults(suiteName: "accueil-\(UUID().uuidString)")),
                                        settle: .milliseconds(30))
        eveningColin.seen()
        try await waitUntil { eveningColin.briefingAt != nil && eveningAgenda.shown.count == 2 }
        let switchHour = UserDefaults.standard.object(forKey: Preferences.Key.homeTomorrowFrom)
        UserDefaults.standard.set(0, forKey: Preferences.Key.homeTomorrowFrom)
        try await LiveWindow.capture(HomeView(agenda: eveningAgenda, mails: nil, colin: eveningColin, router: router).background(Color(nsColor: .windowBackgroundColor)),
                                     to: output.appending(path: "accueil-soir.png"), size: NSSize(width: 928, height: 700))
        UserDefaults.standard.set(switchHour, forKey: Preferences.Key.homeTomorrowFrom)

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
        // The Accueil's pass (18/11): an answer keeps what Colin did, where he did it, and how long he worked.
        try colinStore.add(ColinMessageRow(author: .colin, text: "Je regarde le projet et ses mails.\n\nClaire attend la maquette v2, à livrer jeudi. Le devis est parti lundi, sans réponse.",
                                           createdAt: ago(1).addingTimeInterval(20), costUSD: 0.04,
                                           steps: [ColinStep(id: "s1", tool: "contexte", arguments: ["projet": "Cabinet Martin"], state: .done, position: 0),
                                                   ColinStep(id: "s2", tool: "mails", arguments: ["projet": "Cabinet Martin"], state: .done, position: 35),
                                                   ColinStep(id: "s3", tool: "mail", arguments: ["quel": "c"], state: .done, position: 35),
                                                   ColinStep(id: "s4", tool: "mail", arguments: ["quel": "a"], state: .done, position: 35)],
                                           durationMs: 9_400))
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
                        : [.initialized(good), .assistant(text: "", tools: ["mcp__polhub__mails"], calls: [ClaudeToolCall(id: "t1", name: "mcp__polhub__mails", arguments: [:])]), .textDelta("Marc t'a écrit lundi ") ] + (hanging ? [] : [])
                })
            }
            let work = root.appending(path: "colin-travail", directoryHint: .isDirectory)
            let setup = ColinSetup(binary: URL(fileURLWithPath: "/usr/bin/true"), helper: URL(fileURLWithPath: "/usr/bin/true"),
                                   base: URL(fileURLWithPath: "/tmp/essai.sqlite"), account: nil, work: work)
            return ColinThread(database: database, runner: ColinRunner(launcher: launcher, setup: { setup }), defaults: defaults, isBusy: { busy })
        }
        func colinThreadOn(_ base: AppDatabase) throws -> ColinThread {
            let defaults = try #require(UserDefaults(suiteName: "accueil-colin-\(UUID().uuidString)"))
            defaults.set(true, forKey: Preferences.Key.colinOn)
            return ColinThread(database: base, runner: nil, defaults: defaults)
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
        // The Accueil's pass (18/11): the bar with a long dictation, and with the day's suggestions.
        running.draft = "Prépare une relance pour Anne : la maquette est prête,\nles plans du rez-de-chaussée suivent jeudi,\net je peux passer la voir lundi.\nGarde un ton simple."
        // The round to send, full of ink, in the dark too (lot 5, 19/11).
        for dark in [false, true] {
            try await LiveWindow.capture(colinPage(running), to: output.appending(path: "accueil-barre-longue\(dark ? "-sombre" : "").png"),
                                         size: NSSize(width: 928, height: 760), dark: dark)
        }
        let blank = try AppDatabase.inMemory()
        let fresh = try colinThreadOn(blank)
        try await LiveWindow.capture(ColinComposer(thread: fresh, suggestions: ["Qui attend ma réponse ?", "Où on en est sur Cabinet Martin ?", "Sur quoi je me lance demain ?"])
                                        .padding(Space.xl).background(Color(nsColor: .windowBackgroundColor)),
                                     to: output.appending(path: "accueil-barre-suggestions.png"), size: NSSize(width: 760, height: 180))
        running.draft = "Et Maison Leroy ?"
        running.send()
        try await waitUntil { !running.streaming.isEmpty }
        try await LiveWindow.capture(colinPage(running), to: output.appending(path: "accueil-colin-reponse.png"), size: NSSize(width: 928, height: 760))
        running.turnOff()
        try await waitUntil { running.status == .off }
        // « Allumer Colin », in the dark too, and in a narrow window, where its sentence opens the thread (lot 5, 19/11).
        for dark in [false, true] {
            try await LiveWindow.capture(colinPage(running), to: output.appending(path: "accueil-colin-arret\(dark ? "-sombre" : "").png"),
                                         size: NSSize(width: 928, height: 760), dark: dark)
        }
        try await LiveWindow.capture(colinPage(running), to: output.appending(path: "accueil-colin-arret-etroit.png"), size: NSSize(width: narrow, height: 900))
        let calling = try colinThread(on: true, busy: true, hanging: false)
        calling.draft = "Prépare la relance d'Anne"
        calling.send()
        try await waitUntil { calling.status == .waitingCall }
        try await LiveWindow.capture(colinPage(calling), to: output.appending(path: "accueil-colin-call.png"), size: NSSize(width: 928, height: 760))
        // 19/11: a project Colin created when asked, put forward with « Ouvrir le projet » and « Annuler ».
        let colinWrites = ProjectStore(database).signed(.colin)
        let vlog = try colinWrites.addProject(name: "Vlog 2", status: .priorite1, at: Date())
        var given = vlog
        given.client = "Studio Nord"
        given.dueDate = Date().addingTimeInterval(14 * 86_400)
        try colinWrites.saveChanges(from: vlog, to: given, at: Date())
        let made = try colinThreadOn(database)
        try await waitUntil { made.changes.contains { ChangeText.isCreation($0) } }
        for dark in [false, true] {
            try await LiveWindow.capture(colinPage(made), to: output.appending(path: "accueil-colin-projet-cree\(dark ? "-sombre" : "").png"),
                                         size: NSSize(width: 928, height: 760), dark: dark)
        }
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

        // Lot 5 (19/11): a Meet in eight minutes — « Rejoindre », the Accueil's one full button — wide and narrow, light and
        // dark, beside the whole thread. Added last: the captures above keep their day.
        try calendar.applyGoogle(account: Self.me, changed: [
            event("e5", "Revue des maquettes", start: Date().addingTimeInterval(8 * 60), minutes: 30, meet: "klm-nopq-rst", project: leroy.id),
        ], cancelled: [], at: Date())
        try calendar.setProject(eventID: CalendarEventRow.key(account: Self.me, eventID: "e5"), projectID: leroy.id, origin: .paul)
        try await waitUntil { agenda.shown.contains { $0.eventID == "e5" && $0.projectID == leroy.id } }
        let whole = try colinThreadOn(database)
        try await waitUntil { whole.messages.count >= 4 }
        for dark in [false, true] {
            let suffix = dark ? "-sombre" : ""
            try await LiveWindow.capture(colinPage(whole), to: output.appending(path: "accueil-rejoindre\(suffix).png"), size: NSSize(width: 928, height: 760), dark: dark)
            try await LiveWindow.capture(colinPage(whole), to: output.appending(path: "accueil-rejoindre-etroit\(suffix).png"),
                                         size: NSSize(width: narrow, height: 900), dark: dark)
            // The narrow window: a click on the bar's head opens the thread over the day, in an opaque panel.
            try await LiveWindow.capture(HomeView(agenda: agenda, mails: mails, colin: colin, thread: whole, router: router, threadOpen: true)
                                            .background(Color(nsColor: .windowBackgroundColor)),
                                         to: output.appending(path: "accueil-fil-etroit\(suffix).png"), size: NSSize(width: narrow, height: 900), dark: dark)
        }

        // Lot 5 (19/11): Colin out of order (Claude Code not connected) — his header says so, never « en marche ». Last: its
        // question and failed answer join the thread.
        let brokenDefaults = try #require(UserDefaults(suiteName: "accueil-colin-\(UUID().uuidString)"))
        brokenDefaults.set(true, forKey: Preferences.Key.colinOn)
        let connected = ClaudeInit(model: "claude-opus-5-5", permissionMode: "dontAsk", apiKeySource: "none", tools: ColinTool.allowed, servers: ["polhub": "connected"])
        let notLoggedIn = FakeLauncher { _, _ in
            FakeSession(onSend: { _, rank in
                rank == 1 ? [.initialized(connected), .result(ClaudeResult(isError: true, text: "Not logged in · Please run /login"))] : []
            })
        }
        let brokenSetup = ColinSetup(binary: URL(fileURLWithPath: "/usr/bin/true"), helper: URL(fileURLWithPath: "/usr/bin/true"),
                                     base: URL(fileURLWithPath: "/tmp/essai.sqlite"), account: nil, work: root.appending(path: "colin-panne", directoryHint: .isDirectory))
        let broken = ColinThread(database: database, runner: ColinRunner(launcher: notLoggedIn, setup: { brokenSetup }), defaults: brokenDefaults)
        broken.draft = "Où on en est sur Studio Nord ?"
        broken.send()
        try await waitUntil { if case .broken = broken.status { return true } else { return false } }
        try await LiveWindow.capture(colinPage(broken), to: output.appending(path: "accueil-colin-panne.png"), size: NSSize(width: 928, height: 760))
        try await LiveWindow.capture(colinPage(broken), to: output.appending(path: "accueil-colin-panne-etroit.png"), size: NSSize(width: narrow, height: 900))
    }
}
