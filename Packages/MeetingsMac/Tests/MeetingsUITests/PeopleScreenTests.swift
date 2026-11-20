import AppKit
import Agenda
import Domain
import Foundation
import Mail
import MailFormat
import Persistence
import HubDesign
import ProjectsUI
import SwiftUI
import Testing
@testable import MeetingsUI

/// The people where Paul works (15/11), with made-up people: `HUB_SNAPSHOTS=<dossier> swift test --filter
/// PeopleScreenTests` (add `HUB_LIVE=1` for the glass). Nothing of them is kept in the repository.
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["HUB_SNAPSHOTS"] != nil))
struct PeopleScreenTests {
    @Test func thePeopleScreens() async throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["HUB_SNAPSHOTS"]), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appending(path: "personnes \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase.inMemory()
        let account = "paul@atelier-nord.exemple"
        try CalendarStore(database).addAccount(email: account, at: Date())
        try CalendarStore(database).setGrantedScopes(email: account, scopes: "openid https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/gmail.modify")
        var site = try ProjectStore(database).addProject(name: "Site vitrine", status: .priorite1, at: Date())
        site.color = "blue"
        try ProjectStore(database).save(site, at: Date())
        let contacts = ContactStore(database)
        let camille = try contacts.upsert(email: "camille.martin@exemple-studio.fr", name: "Camille Martin", company: "Exemple Studio", at: Date())
        try contacts.include(contactID: camille.id, projectID: site.id, at: Date())
        let nina = try contacts.upsert(email: "nina.roche@exemple-studio.fr", name: "Nina Roche", company: nil, at: Date())
        try contacts.exclude(contactID: nina.id, projectID: site.id, at: Date())
        let store = MailStore(database)
        let files = MailFiles(root: root)
        var message = MailMessageRow(account: account, messageID: "m1", threadID: "t1", date: Date().addingTimeInterval(-3_600),
                                     sender: MailAddress(name: "Camille Martin", email: "camille.martin@exemple-studio.fr"),
                                     to: [MailAddress(name: "Paul", email: account), MailAddress(name: "Lou Bernard", email: "lou@exemple-studio.fr")],
                                     cc: [MailAddress(name: "Nina Roche", email: "nina.roche@exemple-studio.fr"),
                                          MailAddress(name: "Jules Durand", email: "jules@atelier-nord.exemple"),
                                          MailAddress(name: "Marc Petit", email: "marc.petit@exemple.fr")],
                                     subject: "Maquette v2 du site", snippet: "Voici la deuxième version.", labels: ["INBOX", "CATEGORY_PERSONAL"],
                                     authenticated: true, hasBody: true, bodyIsHTML: true)
        let url = files.body(of: message)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("<p>Bonjour,</p><p>Voici la deuxième version de la maquette.</p><p>Camille</p>".utf8).write(to: url)
        message.labels.append("UNREAD")
        let sent = MailMessageRow(account: account, messageID: "s1", threadID: "t9", date: Date().addingTimeInterval(-86_400),
                                  sender: MailAddress(name: "Paul", email: account), to: [MailAddress(name: "Camille Martin", email: "camille.martin@exemple-studio.fr")],
                                  subject: "Point", snippet: "", labels: ["SENT"])
        try store.apply(account: account, upserts: [message, sent])
        try store.file(threadKey: MailThreadRow.key(account: account, threadID: "t1"), as: .project(site.id), at: Date())
        let event = CalendarEventRow(account: account, eventID: "e1", title: "Atelier maquette", startAt: Date().addingTimeInterval(7_200),
                                     endAt: Date().addingTimeInterval(10_800), meetCode: "abc-defg-hij",
                                     attendees: [Attendee(email: account, response: "accepted", isSelf: true),
                                                 Attendee(email: "camille.martin@exemple-studio.fr", name: "Camille Martin", response: "accepted"),
                                                 Attendee(email: "nina.roche@exemple-studio.fr", name: "Nina Roche"),
                                                 Attendee(email: "lou@exemple-studio.fr", name: "Lou Bernard", response: "declined")],
                                     projectID: site.id, projectOrigin: .paul, updatedAt: Date())
        try CalendarStore(database).applyGoogle(account: account, changed: [event], cancelled: [], at: Date())

        let agenda = AgendaLibrary(database: database)
        let mails = MailLibrary(agenda: agenda, root: root, defaults: UserDefaults(suiteName: "personnes-\(UUID().uuidString)")!)
        let projects = ProjectLibrary(store: ProjectStore(database), meetings: MeetingStore(database))
        let library = MeetingLibrary(store: MeetingStore(database))
        let router = WindowRouter()
        router.section = .mails
        try await Task.sleep(for: .milliseconds(600))
        UserDefaults.standard.set(true, forKey: Preferences.Key.floatingPages)
        router.mailSelection = MailThreadRow.key(account: account, threadID: "t1")
        for dark in [false, true] {
            try await LiveWindow.capture(MainWindowView(library: library, projects: projects, agenda: agenda, mails: mails, router: router,
                                                        paths: AppPaths(root: root, logs: root)) { EmptyView() },
                                         to: output.appending(path: dark ? "personnes-fil-sombre.png" : "personnes-fil.png"),
                                         size: NSSize(width: 1_180, height: 780), dark: dark, wait: .milliseconds(2_000))
        }
        let shown = try #require(agenda.shown.first)
        try await LiveWindow.capture(EventPopover(event: shown, agenda: agenda, router: router, edit: {}, close: {}).background(Color(nsColor: .windowBackgroundColor)),
                                     to: output.appending(path: "personnes-rendez-vous.png"), size: NSSize(width: 320, height: 560))
        var highlighted = 1
        let suggestions = PersonSuggestionList(matches: mails.suggestions(for: "e"), highlighted: Binding(get: { highlighted }, set: { highlighted = $0 }),
                                               project: { person in agenda.projects.first { person.projectIDs.contains($0.id) } }, choose: { _ in })
            .padding(Space.l).frame(width: 560).background(Color(nsColor: .windowBackgroundColor))
        try await LiveWindow.capture(suggestions, to: output.appending(path: "personnes-suggestions.png"), size: NSSize(width: 560, height: 420))
    }
}
