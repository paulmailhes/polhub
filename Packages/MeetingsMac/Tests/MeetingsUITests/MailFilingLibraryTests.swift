import Agenda
import Domain
import Foundation
import Persistence
import Testing
@testable import MeetingsUI

/// Step « Ranger » (14/11): Paul files a thread; its sender follows, becomes a contact of the project, and one
/// « Annuler » takes it all back.
@MainActor
@Suite struct MailFilingLibraryTests {
    let account = "moi@exemple.fr"

    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
        #expect(condition())
    }

    @Test func filingInAProjectMakesAContactAndAnnulerUndoesIt() async throws {
        let database = try AppDatabase.inMemory()
        try CalendarStore(database).addAccount(email: account, at: Date())
        let project = try ProjectStore(database).addProject(name: "Site vitrine", status: .priorite1, at: Date())
        let store = MailStore(database)
        let message = MailMessageRow(account: account, messageID: "m1", threadID: "t1", date: Date(), sender: MailAddress(name: "Lou Bernard", email: "lou@studio.exemple"),
                                     subject: "Une question", snippet: "Bonjour", labels: ["INBOX", "CATEGORY_PERSONAL"])
        try store.apply(account: account, upserts: [message])
        let root = FileManager.default.temporaryDirectory.appending(path: "ranger-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let agenda = AgendaLibrary(database: database)
        let mails = MailLibrary(agenda: agenda, root: root, defaults: UserDefaults(suiteName: "ranger-\(UUID().uuidString)")!)
        let thread = try #require(try store.thread(MailThreadRow.key(account: account, threadID: "t1")))
        try await waitUntil { !mails.rules.mine.isEmpty }
        #expect(mails.filing(of: thread) == nil)

        mails.file(thread, as: .project(project.id))
        try await waitUntil { mails.filing(of: thread)?.filing == .project(project.id) }
        let contact = try #require(try ContactStore(database).contact(email: "lou@studio.exemple"))
        let links = try ContactStore(database).links()
        #expect(contact.name == "Lou Bernard" && links.map(\.projectID) == [project.id])
        #expect(mails.undoable?.text == "Rangé dans « Site vitrine » : les prochains mails de Lou Bernard suivront.")
        #expect(try store.threads(filedIn: project.id).map(\.id) == [thread.id])

        mails.undo()
        try await waitUntil { mails.filing(of: thread) == nil }
        #expect(try ContactStore(database).contact(email: "lou@studio.exemple") == nil)
        #expect(try store.filingRules().senders.isEmpty)
    }

    /// A robot's address is filed, never made a contact; « Aucune case » keeps the thread with the people.
    @Test func aRobotIsNeverAContact() async throws {
        let database = try AppDatabase.inMemory()
        try CalendarStore(database).addAccount(email: account, at: Date())
        let project = try ProjectStore(database).addProject(name: "Site vitrine", status: .priorite1, at: Date())
        let store = MailStore(database)
        try store.apply(account: account, upserts: [
            MailMessageRow(account: account, messageID: "m1", threadID: "t1", date: Date(), sender: MailAddress(email: "no-reply@outil.exemple"),
                           subject: "Rapport", snippet: "", labels: ["INBOX", "CATEGORY_UPDATES"]),
        ])
        let root = FileManager.default.temporaryDirectory.appending(path: "ranger-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let mails = MailLibrary(agenda: AgendaLibrary(database: database), root: root, defaults: UserDefaults(suiteName: "ranger-\(UUID().uuidString)")!)
        let thread = try #require(try store.thread(MailThreadRow.key(account: account, threadID: "t1")))
        try await waitUntil { !mails.rules.mine.isEmpty }
        #expect(mails.tab(of: thread) == .notifications)
        mails.file(thread, as: .project(project.id))
        try await waitUntil { mails.filing(of: thread)?.filing == .project(project.id) }
        #expect(try ContactStore(database).contacts().isEmpty)
        #expect(mails.tab(of: thread) == .personnes)
        mails.file(thread, as: .none)
        try await waitUntil { mails.filing(of: thread)?.filing == MailFiling.none }
        #expect(mails.tab(of: thread) == .personnes)
    }
}
