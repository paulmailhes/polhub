import Foundation
import Testing
@testable import Persistence

/// 15/11: the people Paul wrote to, counted once per mail, and the projects he took people out of.
@Suite struct MailPeopleTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)
    let account = "moi@exemple.fr"

    func sent(_ id: String, days: Double, to: [MailAddress], cc: [MailAddress] = []) -> MailMessageRow {
        MailMessageRow(account: account, messageID: id, threadID: "t\(id)", date: now.addingTimeInterval(days * 86_400),
                       sender: MailAddress(name: "Moi", email: account), to: to, cc: cc, subject: "Point", snippet: "", labels: ["SENT"])
    }

    @Test func thePeoplePaulWroteToAreCountedWithTheirLastName() throws {
        let database = try AppDatabase.inMemory()
        try CalendarStore(database).addAccount(email: account, at: now)
        let mails = MailStore(database)
        try mails.apply(account: account, upserts: [
            sent("1", days: -40, to: [MailAddress(name: "camille@studio.exemple", email: "Camille@Studio.exemple")]),
            sent("2", days: -2, to: [MailAddress(name: "Camille Martin", email: "camille@studio.exemple")],
                 cc: [MailAddress(email: "jules@exemple.fr"), MailAddress(email: "camille@studio.exemple")]),
            sent("3", days: -10, to: [MailAddress(email: "camille@studio.exemple")]),
        ])
        let stats = try mails.correspondentStats()
        // Three mails to Camille, never twice for one mail; the name her address bore last, never the address itself.
        #expect(stats["camille@studio.exemple"] == MailCorrespondent(name: "Camille Martin", sent: 3, lastAt: now.addingTimeInterval(-2 * 86_400)))
        #expect(stats["jules@exemple.fr"] == MailCorrespondent(name: nil, sent: 1, lastAt: now.addingTimeInterval(-2 * 86_400)))
        let rules = try mails.filingRules()
        #expect(rules.correspondents == ["camille@studio.exemple", "jules@exemple.fr"] && rules.correspondentStats == stats)
    }

    /// A contact's page lists the threads the address took part in, and the list says when last: neither the trash,
    /// nor the spam, nor a draft counts.
    @Test func aContactsThreadsAndTheLastMailOfEachAddress() throws {
        let database = try AppDatabase.inMemory()
        try CalendarStore(database).addAccount(email: account, at: now)
        let mails = MailStore(database)
        let camille = MailAddress(name: "Camille Martin", email: "camille_martin@studio.exemple")
        func received(_ id: String, days: Double, from: MailAddress, labels: [String] = ["INBOX"]) -> MailMessageRow {
            MailMessageRow(account: account, messageID: id, threadID: "t\(id)", date: now.addingTimeInterval(days * 86_400), sender: from,
                           to: [MailAddress(name: "Moi", email: account)], subject: "Maquette", snippet: "", labels: labels)
        }
        try mails.apply(account: account, upserts: [
            received("1", days: -5, from: camille),
            sent("2", days: -2, to: [MailAddress(email: "jules@exemple.fr")], cc: [camille]),
            received("3", days: -1, from: MailAddress(email: "lou@studio.exemple"), labels: ["TRASH"]),
            sent("4", days: 0, to: [camille]).with(labels: ["DRAFT"]),
            // « _ » is a letter of the address, never a wildcard.
            received("5", days: -3, from: MailAddress(email: "camilleXmartin@studio.exemple")),
        ])
        #expect(try mails.threads(with: "Camille_Martin@Studio.exemple").map(\.threadID) == ["t2", "t1"])
        #expect(try mails.threads(with: "personne@exemple.fr").isEmpty)
        let last = try mails.lastExchanges()
        #expect(last["camille_martin@studio.exemple"] == now.addingTimeInterval(-2 * 86_400))
        #expect(last["jules@exemple.fr"] == now.addingTimeInterval(-2 * 86_400) && last["lou@studio.exemple"] == nil)
        #expect(try mails.lastExchanges(with: ["Camille_Martin@studio.exemple", "personne@exemple.fr"]) == ["camille_martin@studio.exemple": now.addingTimeInterval(-2 * 86_400)])
    }

    @Test func theRulesKnowWhomPaulTookOutOfAProject() throws {
        let database = try AppDatabase.inMemory()
        try CalendarStore(database).addAccount(email: account, at: now)
        let contacts = ContactStore(database)
        let project = try ProjectStore(database).addProject(name: "Site vitrine", status: .priorite1, at: now)
        let lou = try contacts.upsert(email: "lou@studio.exemple", name: "Lou", company: nil, at: now)
        let nina = try contacts.upsert(email: "nina@studio.exemple", name: "Nina", company: nil, at: now)
        try contacts.include(contactID: lou.id, projectID: project.id, at: now)
        try contacts.exclude(contactID: nina.id, projectID: project.id, at: now)
        let rules = try MailStore(database).filingRules()
        #expect(rules.contactProjects["lou@studio.exemple"] == [project.id] && rules.contactProjects["nina@studio.exemple"] == nil)
        #expect(rules.excludedProjects == ["nina@studio.exemple": [project.id]])
    }

    /// Paul's own domain is his company's: its people are colleagues; a public mailbox makes no one a colleague.
    @Test func aColleagueSharesOneOfPaulsOwnDomains() {
        let rules = MailFilingRules(mine: ["paul@atelier-nord.exemple", "paul.perso@gmail.com"])
        #expect(rules.isColleague("Jules@Atelier-Nord.exemple"))
        #expect(!rules.isColleague("paul@atelier-nord.exemple"))
        #expect(!rules.isColleague("ami@gmail.com"))
        #expect(!rules.isColleague("camille@studio.exemple"))
    }

    @Test func theLinksAreObserved() async throws {
        let database = try AppDatabase.inMemory()
        let contacts = ContactStore(database)
        let project = try ProjectStore(database).addProject(name: "Site vitrine", status: .priorite1, at: now)
        let lou = try contacts.upsert(email: "lou@studio.exemple", name: "Lou", company: nil, at: now)
        final class Box: @unchecked Sendable { var rows: [ContactProjectRow] = [] }
        let box = Box()
        let observation = contacts.observeLinks { box.rows = $0 }
        try contacts.include(contactID: lou.id, projectID: project.id, at: now)
        for _ in 0..<100 where box.rows.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(box.rows.map(\.contactID) == [lou.id] && box.rows.first?.excluded == false)
        observation.cancel()
    }
}

extension MailMessageRow {
    func with(labels: [String]) -> MailMessageRow {
        var copy = self
        copy.labels = labels
        return copy
    }
}
