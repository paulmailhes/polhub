import Agenda
import Domain
import Foundation
import Persistence
import Testing
@testable import MeetingsUI

/// 15/11: who Paul writes to, found as he types; the people of a thread; a person put in a project and taken back.
@Suite struct PeopleIndexTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)

    func contact(_ name: String, _ email: String, company: String? = nil) -> ContactRow {
        ContactRow(name: name, email: email, company: company, createdAt: now)
    }

    func names(_ found: [PersonSuggestion]) -> [String] { found.map(\.address.display) }

    /// What begins with the letters comes before what only contains them, however often Paul writes to the second.
    @Test func whatBeginsWithTheLettersComesFirst() {
        let index = PeopleIndex(contacts: [contact("Camille Lamarre", "camille@studio.exemple"), contact("Marc Durand", "marc@atelier.exemple")],
                                correspondents: ["camille@studio.exemple": MailCorrespondent(sent: 40, lastAt: now)], now: now)
        #expect(names(index.search("mar")) == ["Marc Durand", "Camille Lamarre"])
        // A first name, a last name, the address, the company, the domain: each word may be begun.
        #expect(names(index.search("dur")) == ["Marc Durand"])
        #expect(names(index.search("atel")) == ["Marc Durand"])
        // Accents and case do not count; every word typed must be found.
        #expect(names(index.search("CAMI lam")) == ["Camille Lamarre"])
        #expect(index.search("camille marc").isEmpty)
    }

    /// Among equals, the people Paul writes to often and lately come first; then his contacts; then by name.
    @Test func thePeoplePaulWritesToComeFirst() {
        let index = PeopleIndex(contacts: [contact("Camélia Abadie", "camelia@exemple.fr"), contact("Camille Martin", "camille@studio.exemple")],
                                correspondents: [
                                    "camille@studio.exemple": MailCorrespondent(name: "Camille M.", sent: 12, lastAt: now.addingTimeInterval(-3 * 86_400)),
                                    "cameron@exemple.net": MailCorrespondent(name: "Cameron Lee", sent: 1, lastAt: now.addingTimeInterval(-400 * 86_400)),
                                ],
                                senders: [MailAddress(name: "Camelot Studio", email: "contact@camelot.exemple")], now: now)
        #expect(names(index.search("cam")) == ["Camille Martin", "Cameron Lee", "Camélia Abadie", "Camelot Studio"])
        // A contact keeps Paul's spelling of the name; someone he wrote to, the name of his last mail.
        #expect(index.search("cameron").first?.address == MailAddress(name: "Cameron Lee", email: "cameron@exemple.net"))
        #expect(index.search("cameron").first?.isContact == false && index.search("camille").first?.isContact == true)
    }

    /// Robots, Paul himself and a second copy of an address never show; at most eight people.
    @Test func robotsPaulAndDuplicatesAreLeftOut() {
        let many = (1...12).map { contact("Lou \($0)", "lou\($0)@exemple.fr") }
        let index = PeopleIndex(contacts: many + [contact("Lou Bernard", "Lou@Studio.exemple")],
                                correspondents: ["lou@studio.exemple": MailCorrespondent(name: "Lou B.", sent: 3, lastAt: now),
                                                 "moi@exemple.fr": MailCorrespondent(sent: 9, lastAt: now)],
                                senders: [MailAddress(name: "Lou", email: "lou@studio.exemple"), MailAddress(name: "Outil", email: "no-reply@outil.exemple"),
                                          MailAddress(name: "Lettre", email: "newsletter@lettre.exemple")],
                                mine: ["moi@exemple.fr"], now: now)
        let found = index.search("lou")
        #expect(found.count == PeopleIndex.limit)
        #expect(found.first?.address == MailAddress(name: "Lou Bernard", email: "lou@studio.exemple"))
        #expect(found.filter { $0.address.email == "lou@studio.exemple" }.count == 1)
        #expect(index.search("no").isEmpty && index.search("newsletter").isEmpty && index.search("moi").isEmpty)
        // An address already chosen is not offered again.
        #expect(!index.search("lou", excluding: ["Lou@studio.exemple"]).contains { $0.address.email == "lou@studio.exemple" })
    }

    /// The company shows; the people of the thread's project come first among equals.
    @Test func theProjectsPeopleComeFirst() {
        let project = UUID()
        let index = PeopleIndex(contacts: [contact("Jules Durand", "jules@exemple.fr"), contact("Julie Roche", "julie@exemple-studio.fr")],
                                projects: ["julie@exemple-studio.fr": [project]], now: now)
        #expect(names(index.search("jul")) == ["Jules Durand", "Julie Roche"])
        #expect(names(index.search("jul", project: project)) == ["Julie Roche", "Jules Durand"])
        #expect(index.search("julie").first?.company == "Exemple Studio" && index.search("julie").first?.projectIDs == [project])
        #expect(index.search("julie").first?.initials == "JR")
    }

    @Test func theKeysStayInsideTheListAndAWholeAddressStaysAsTyped() {
        #expect(SuggestionKeys.next(0, step: -1, count: 3) == 0)
        #expect(SuggestionKeys.next(1, step: 1, count: 3) == 2)
        #expect(SuggestionKeys.next(2, step: 1, count: 3) == 2)
        let camille = PersonSuggestion(address: MailAddress(name: "Camille", email: "camille@studio.exemple"), initials: "C", company: nil,
                                       projectIDs: [], isContact: true)
        #expect(SuggestionChoice.accepted(typed: "cam", matches: [camille], highlighted: 0, moved: false) == camille.address)
        #expect(SuggestionChoice.accepted(typed: "camille@autre.exemple", matches: [camille], highlighted: 0, moved: false) == nil)
        #expect(SuggestionChoice.accepted(typed: "camille@autre.exemple", matches: [camille], highlighted: 0, moved: true) == camille.address)
        #expect(SuggestionChoice.accepted(typed: "Camille@Studio.exemple", matches: [camille], highlighted: 0, moved: false) == camille.address)
        #expect(SuggestionChoice.accepted(typed: "cam", matches: [], highlighted: 0, moved: false) == nil)
    }

    /// The thread's people: who wrote, then To and Cc, once each; never Paul, a robot, a colleague of his own domain.
    @Test func thePeopleOfAThread() {
        let account = "paul@atelier-nord.exemple"
        let rules = MailFilingRules(mine: [account, "paul.perso@gmail.com"])
        let message = MailMessageRow(account: account, messageID: "m1", threadID: "t1", date: now,
                                     sender: MailAddress(name: "Camille Martin", email: "camille@studio.exemple"),
                                     to: [MailAddress(name: "Paul", email: account), MailAddress(email: "lou@studio.exemple")],
                                     cc: [MailAddress(name: "Jules", email: "jules@atelier-nord.exemple"), MailAddress(email: "no-reply@outil.exemple"),
                                          MailAddress(name: "Lou Bernard", email: "LOU@studio.exemple"), MailAddress(email: "pas-une-adresse")],
                                     subject: "Maquette", snippet: "", labels: ["INBOX"])
        let people = ThreadPeople.list(senders: [MailAddress(name: "Camille Martin", email: "camille@studio.exemple"), MailAddress(email: account)],
                                       messages: [message], rules: rules, mine: [account])
        #expect(people == [MailAddress(name: "Camille Martin", email: "camille@studio.exemple"), MailAddress(name: "Lou Bernard", email: "lou@studio.exemple")])
    }

    @Test func theUndoLineSaysWhoJoined() {
        let camille = MailAddress(name: "Camille Martin", email: "camille@studio.exemple")
        let lou = MailAddress(name: "Lou Bernard", email: "lou@studio.exemple")
        #expect(PeopleStyle.addedText([camille], project: "Site vitrine") == "Camille Martin rejoint « Site vitrine ».")
        #expect(PeopleStyle.addedText([camille, lou], project: "Site vitrine") == "Camille et Lou rejoignent « Site vitrine ».")
        #expect(PeopleStyle.addedText([camille, lou, camille, lou], project: nil) == "4 personnes sont dans tes contacts.")
    }
}

/// The gestures on people go through ContactStore, and « Annuler » takes back exactly what they did.
@MainActor
@Suite struct PeopleGestureTests {
    let account = "moi@exemple.fr"

    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
        #expect(condition())
    }

    @Test func addingPeopleAndUndoingIt() async throws {
        let database = try AppDatabase.inMemory()
        try CalendarStore(database).addAccount(email: account, at: Date())
        let project = try ProjectStore(database).addProject(name: "Site vitrine", status: .priorite1, at: Date())
        let contacts = ContactStore(database)
        let known = try contacts.upsert(email: "camille@studio.exemple", name: "Camille Martin", company: "Studio", at: Date())
        let removed = try contacts.upsert(email: "nina@studio.exemple", name: "Nina Roche", company: nil, at: Date())
        try contacts.exclude(contactID: removed.id, projectID: project.id, at: Date())
        let agenda = AgendaLibrary(database: database)
        try await waitUntil { !agenda.accounts.isEmpty && agenda.contacts.count == 2 && agenda.links.count == 1 }
        #expect(agenda.link(of: "camille@studio.exemple", project: project.id) == .contact)
        #expect(agenda.link(of: "nina@studio.exemple", project: project.id) == .removed)
        #expect(agenda.link(of: "lou@studio.exemple", project: project.id) == .stranger)

        let people = [MailAddress(name: "Camille", email: "camille@studio.exemple"), MailAddress(name: "Nina", email: "nina@studio.exemple"),
                      MailAddress(name: "Lou Bernard", email: "lou@studio.exemple"), MailAddress(email: account), MailAddress(email: "no-reply@outil.exemple")]
        let change = try agenda.add(people, to: project.id, respectRemoval: true)
        // Camille and Lou join; Nina stays out, as Paul left her; Paul and the robot are never contacts.
        #expect(change.people.map(\.email) == ["camille@studio.exemple", "lou@studio.exemple"])
        #expect(Set(try contacts.contacts(projectID: project.id).map(\.email)) == ["camille@studio.exemple", "lou@studio.exemple"])
        let lou = try #require(try contacts.contact(email: "lou@studio.exemple"))
        #expect(lou.name == "Lou Bernard" && lou.company == "Studio")
        try await waitUntil { agenda.link(of: "lou@studio.exemple", project: project.id) == .member }

        change.undo()
        // What the gesture made goes, what was there stays.
        #expect(try contacts.contact(email: "lou@studio.exemple") == nil)
        #expect(try contacts.contact(email: "camille@studio.exemple")?.id == known.id)
        #expect(try contacts.links().map(\.contactID) == [removed.id] && contacts.links().first?.excluded == true)

        // One person chosen by Paul comes back into the project he took her out of; « Retirer » puts her out again.
        let nina = try agenda.add([MailAddress(email: "nina@studio.exemple")], to: project.id, respectRemoval: false)
        #expect(try nina.people.map(\.email) == ["nina@studio.exemple"] && contacts.contacts(projectID: project.id).map(\.id) == [removed.id])
        let out = try agenda.remove(MailAddress(email: "nina@studio.exemple"), from: project.id)
        #expect(try contacts.contacts(projectID: project.id).isEmpty)
        out.undo()
        #expect(try contacts.contacts(projectID: project.id).map(\.id) == [removed.id])
        nina.undo()
        #expect(try contacts.links().first?.excluded == true)

        // Without a project: only the strangers become contacts.
        let plain = try agenda.add([MailAddress(email: "camille@studio.exemple"), MailAddress(name: "Jo", email: "jo@exemple.fr")], to: nil, respectRemoval: true)
        #expect(try plain.people.map(\.email) == ["jo@exemple.fr"] && contacts.links().count == 1)
    }

    /// From a thread: « Ajouter N au projet » takes the people missing, says it, and one « Annuler » takes it back.
    @Test func aThreadsPeopleJoinItsProjectWithOneAnnuler() async throws {
        let database = try AppDatabase.inMemory()
        try CalendarStore(database).addAccount(email: account, at: Date())
        let project = try ProjectStore(database).addProject(name: "Site vitrine", status: .priorite1, at: Date())
        let store = MailStore(database)
        let message = MailMessageRow(account: account, messageID: "m1", threadID: "t1", date: Date(),
                                     sender: MailAddress(name: "Camille Martin", email: "camille@studio.exemple"),
                                     to: [MailAddress(email: account)], cc: [MailAddress(name: "Lou Bernard", email: "lou@studio.exemple")],
                                     subject: "Maquette", snippet: "", labels: ["INBOX", "CATEGORY_PERSONAL"])
        try store.apply(account: account, upserts: [message])
        let root = FileManager.default.temporaryDirectory.appending(path: "personnes-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let agenda = AgendaLibrary(database: database)
        let mails = MailLibrary(agenda: agenda, root: root, defaults: UserDefaults(suiteName: "personnes-\(UUID().uuidString)")!)
        let thread = try #require(try store.thread(MailThreadRow.key(account: account, threadID: "t1")))
        try await waitUntil { !mails.rules.mine.isEmpty && !agenda.accounts.isEmpty && !agenda.projects.isEmpty }
        #expect(agenda.mails === mails)

        let people = mails.people(of: thread, messages: [message])
        #expect(people.map(\.email) == ["camille@studio.exemple", "lou@studio.exemple"])
        #expect(mails.newcomers(people, project: project.id) == people)
        mails.add(mails.newcomers(people, project: project.id), to: project.id, respectRemoval: true)
        #expect(mails.undoable?.text == "Camille et Lou rejoignent « Site vitrine ».")
        try await waitUntil { mails.newcomers(people, project: project.id).isEmpty }
        // The people Paul wrote to and the contacts are suggested, Lou too now.
        #expect(mails.suggestions(for: "lou").map(\.address.email) == ["lou@studio.exemple"])

        mails.undo()
        try await waitUntil { mails.newcomers(people, project: project.id).count == 2 }
        #expect(try ContactStore(database).contacts().isEmpty)
    }
}
