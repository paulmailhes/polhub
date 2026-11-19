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

    /// A client's thread where a colleague of Paul's own domain answered last, filed by hand: the thread takes its
    /// case, but nothing is kept for the colleague, who writes about everything; the banner says the thread alone
    /// (audit of 19/11).
    @Test func filingAThreadAColleagueAnsweredLastKeepsNothingForHim() async throws {
        let database = try AppDatabase.inMemory()
        try CalendarStore(database).addAccount(email: account, at: Date())
        let project = try ProjectStore(database).addProject(name: "Site vitrine", status: .priorite1, at: Date())
        let store = MailStore(database)
        let lea = MailAddress(name: "Léa Petit", email: "lea@exemple.fr")
        try store.apply(account: account, upserts: [
            MailMessageRow(account: account, messageID: "m1", threadID: "t1", date: Date().addingTimeInterval(-600),
                           sender: MailAddress(name: "Lou Bernard", email: "lou@studio.exemple"), subject: "Une question", snippet: "", labels: ["INBOX", "CATEGORY_PERSONAL"]),
            MailMessageRow(account: account, messageID: "m2", threadID: "t1", date: Date(), sender: lea, subject: "Re: Une question", snippet: "",
                           labels: ["INBOX", "CATEGORY_PERSONAL"]),
            MailMessageRow(account: account, messageID: "m3", threadID: "t2", date: Date(), sender: lea, subject: "Déjeuner vendredi", snippet: "",
                           labels: ["INBOX", "CATEGORY_PERSONAL"]),
        ])
        let root = FileManager.default.temporaryDirectory.appending(path: "ranger-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let mails = MailLibrary(agenda: AgendaLibrary(database: database), root: root, defaults: UserDefaults(suiteName: "ranger-\(UUID().uuidString)")!)
        let filed = try #require(try store.thread(MailThreadRow.key(account: account, threadID: "t1")))
        let lunch = try #require(try store.thread(MailThreadRow.key(account: account, threadID: "t2")))
        try await waitUntil { !mails.rules.mine.isEmpty }
        #expect(filed.lastSender == lea.email)

        mails.file(filed, as: .project(project.id))
        try await waitUntil { mails.filing(of: filed)?.filing == .project(project.id) }
        #expect(try store.filingRules().senders[lea.email] == nil)
        #expect(mails.filing(of: lunch) == nil)
        #expect(mails.undoable?.text == "Rangé dans « Site vitrine » : 1 fil")
    }

    /// 15/11: several ticked threads in one project. Every thread takes the case; only people's threads (a person
    /// of Gmail's « Principale », a thread Paul wrote in) make their sender a contact; one « Annuler » takes all back.
    @Test func filingSeveralThreadsLinksOnlyPeopleAndUndoesAtOnce() async throws {
        let database = try AppDatabase.inMemory()
        try CalendarStore(database).addAccount(email: account, at: Date())
        let project = try ProjectStore(database).addProject(name: "Site vitrine", status: .priorite1, at: Date())
        let store = MailStore(database)
        try store.apply(account: account, upserts: [
            MailMessageRow(account: account, messageID: "m1", threadID: "t1", date: Date(), sender: MailAddress(name: "Lou Bernard", email: "lou@studio.exemple"),
                           subject: "Une question", snippet: "", labels: ["INBOX", "CATEGORY_PERSONAL"]),
            // A letter: automatic, its sender must not become a contact (its images would load, its next mails follow).
            MailMessageRow(account: account, messageID: "m2", threadID: "t2", date: Date(), sender: MailAddress(name: "La Lettre", email: "lettre@lettre.exemple"),
                           subject: "Le numéro d'hiver", snippet: "", labels: ["INBOX", "CATEGORY_PROMOTIONS"]),
            // Paul wrote in this one: a person, although Gmail calls it a notification.
            MailMessageRow(account: account, messageID: "m3", threadID: "t3", date: Date(), sender: MailAddress(email: account), to: [MailAddress(email: "support@outil.exemple")],
                           subject: "Mon compte", snippet: "", labels: ["SENT"]),
            MailMessageRow(account: account, messageID: "m4", threadID: "t3", date: Date().addingTimeInterval(60), sender: MailAddress(name: "Sam Support", email: "support@outil.exemple"),
                           subject: "Re: Mon compte", snippet: "", labels: ["INBOX", "CATEGORY_UPDATES"]),
        ])
        let root = FileManager.default.temporaryDirectory.appending(path: "ranger-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let mails = MailLibrary(agenda: AgendaLibrary(database: database), root: root, defaults: UserDefaults(suiteName: "ranger-\(UUID().uuidString)")!)
        let threads = try ["t1", "t2", "t3"].map { try #require(try store.thread(MailThreadRow.key(account: account, threadID: $0))) }
        try await waitUntil { !mails.rules.mine.isEmpty }

        mails.file(threads, as: .project(project.id))
        try await waitUntil { threads.allSatisfy { mails.filing(of: $0)?.filing == .project(project.id) } }
        let contacts = try ContactStore(database).contacts().compactMap(\.email).sorted()
        #expect(contacts == ["lou@studio.exemple", "support@outil.exemple"])
        #expect(try ContactStore(database).links().count == 2)
        #expect(mails.undoable?.text == "Rangés dans « Site vitrine » : 3 fils")
        // Every thread's sender follows, the letter's too: its next mails go to the project.
        #expect(try Set(store.filingRules().senders.keys) == ["lou@studio.exemple", "lettre@lettre.exemple", "support@outil.exemple"])

        mails.undo()
        try await waitUntil { threads.allSatisfy { mails.filing(of: $0)?.filing != .project(project.id) } }
        #expect(try ContactStore(database).contacts().isEmpty && ContactStore(database).links().isEmpty)
        #expect(try store.filingRules().senders.isEmpty && store.filingRules().choices.isEmpty)
        #expect(MailLibrary.filedText(.payments, project: nil, count: 1) == "Rangé dans Paiements : 1 fil")
        #expect(MailLibrary.filedText(.none, project: nil, count: 4) == "Sans case : 4 fils")
    }

    /// Someone Paul removed from a project stays out when several threads go there at once, like the other
    /// gestures on many people; one thread filed by hand still brings them back.
    @Test func filingSeveralThreadsLeavesRemovedPeopleOut() async throws {
        let database = try AppDatabase.inMemory()
        try CalendarStore(database).addAccount(email: account, at: Date())
        let project = try ProjectStore(database).addProject(name: "Site vitrine", status: .priorite1, at: Date())
        let contacts = ContactStore(database)
        let lou = try contacts.upsert(email: "lou@studio.exemple", name: "Lou Bernard", company: nil, at: Date())
        try contacts.exclude(contactID: lou.id, projectID: project.id, at: Date())
        let store = MailStore(database)
        try store.apply(account: account, upserts: [
            MailMessageRow(account: account, messageID: "m1", threadID: "t1", date: Date(), sender: MailAddress(name: "Lou Bernard", email: "lou@studio.exemple"),
                           subject: "Une question", snippet: "", labels: ["INBOX", "CATEGORY_PERSONAL"]),
            MailMessageRow(account: account, messageID: "m2", threadID: "t2", date: Date(), sender: MailAddress(name: "Jules Martin", email: "jules@atelier.exemple"),
                           subject: "Le devis", snippet: "", labels: ["INBOX", "CATEGORY_PERSONAL"]),
        ])
        let root = FileManager.default.temporaryDirectory.appending(path: "ranger-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let mails = MailLibrary(agenda: AgendaLibrary(database: database), root: root, defaults: UserDefaults(suiteName: "ranger-\(UUID().uuidString)")!)
        let threads = try ["t1", "t2"].map { try #require(try store.thread(MailThreadRow.key(account: account, threadID: $0))) }
        try await waitUntil { !mails.rules.mine.isEmpty }

        mails.file(threads, as: .project(project.id))
        try await waitUntil { threads.allSatisfy { mails.filing(of: $0)?.filing == .project(project.id) } }
        let links = try contacts.links().filter { $0.projectID == project.id }
        #expect(links.first { $0.contactID == lou.id }?.excluded == true)
        #expect(links.filter { !$0.excluded }.count == 1)

        mails.undo()
        try await waitUntil { threads.allSatisfy { mails.filing(of: $0)?.filing != .project(project.id) } }
        #expect(try contacts.links().first { $0.contactID == lou.id }?.excluded == true)
        #expect(try contacts.contact(email: "lou@studio.exemple") != nil)

        mails.file(threads[0], as: .project(project.id))
        try await waitUntil { mails.filing(of: threads[0])?.filing == .project(project.id) }
        #expect(try contacts.links().first { $0.contactID == lou.id }?.excluded == false)
    }

    /// The menu of several threads ticks the case only when they all share it.
    @Test func theMenuTicksTheCaseTheThreadsShare() {
        let site = UUID()
        #expect(MailFilingMenu.shared([.project(site), .project(site)]) == .project(site))
        #expect(MailFilingMenu.shared([.project(site), .perso]) == nil)
        #expect(MailFilingMenu.shared([.project(site), nil]) == nil)
        #expect(MailFilingMenu.shared([]) == nil)
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
