import Foundation
import Testing
@testable import Persistence

/// Step « Ranger » (14/11): the case of a thread, by one cascade of rules, the surest first.
@Suite struct MailFilingTests {
    let site = UUID(), logo = UUID()
    let mine: Set<String> = ["moi@exemple.fr", "moi@atelier.exemple"]

    func thread(_ id: String = "t1", senders: [String], subject: String = "Maquette v2", category: String? = "personal", paulWrote: Bool = false,
                last: String? = nil) -> MailThreadRow {
        MailThreadRow(id: "moi@exemple.fr|\(id)", account: "moi@exemple.fr", threadID: id, subject: subject, snippet: "", senders: senders.map { MailAddress(email: $0) },
                      lastMessageAt: Date(), messageCount: senders.count, unread: true, inInbox: true, hidden: false, hasAttachment: false,
                      category: category, lastSender: last ?? senders.last { !mine.contains($0) }, paulWrote: paulWrote)
    }

    var rules: MailFilingRules {
        MailFilingRules(contactProjects: ["camille@studio.exemple": [site], "jules@studio.exemple": [site, logo], "nina.fictive.polhub@gmail.com": [logo]],
                        contacts: ["camille@studio.exemple", "jules@studio.exemple", "nina.fictive.polhub@gmail.com", "lea@exemple.org"],
                        projects: [(site, "Site vitrine"), (logo, "Logo")], mine: mine, correspondents: ["marc@exemple.net"])
    }

    @Test func paulsChoiceWinsThenWhatHeSaidOfTheSender() {
        var rules = rules
        rules.choices = ["moi@exemple.fr|t1": .perso]
        #expect(rules.filing(of: thread(senders: ["camille@studio.exemple"]))! == (.perso, .paul))
        rules.choices = [:]
        rules.senders = ["camille@studio.exemple": MailSenderRow(address: "camille@studio.exemple", principal: false, images: false, createdAt: Date(), tab: nil, filing: "projet:\(logo.uuidString.lowercased())")]
        #expect(rules.filing(of: thread(senders: ["camille@studio.exemple"]))! == (.project(logo), .sender))
    }

    @Test func aContactOfOneProjectFilesTheThread() {
        #expect(rules.filing(of: thread(senders: ["camille@studio.exemple", "moi@exemple.fr"]))! == (.project(site), .contacts))
        // Jules is in two projects: the subject names one, or there is no case.
        #expect(rules.filing(of: thread(senders: ["jules@studio.exemple"], subject: "Le logo, version 3"))! == (.project(logo), .contacts))
        #expect(rules.filing(of: thread(senders: ["jules@studio.exemple"], subject: "Point de la semaine")) == nil)
        // A contact who writes from Promotions is still a person.
        #expect(rules.tab(of: thread(senders: ["camille@studio.exemple"], category: "promotions")) == .personnes)
    }

    @Test func theDomainAnswersOnlyForPeopleAndNeverForEveryonesMailbox() {
        // A colleague of Camille's, never seen: the studio's domain has one project... once Jules is set aside.
        var rules = MailFilingRules(contactProjects: ["camille@studio.exemple": [site]], projects: [(site, "Site vitrine")], mine: mine)
        #expect(rules.filing(of: thread(senders: ["paul.r@studio.exemple"]))! == (.project(site), .domain))
        // The studio's newsletter stays with the newsletters.
        #expect(rules.filing(of: thread(senders: ["lettre@studio.exemple"], category: "promotions"))! == (.newsletters, .signals))
        // Everyone's mailboxes and Paul's own domain say nothing.
        rules = MailFilingRules(contactProjects: ["nina.fictive.polhub@gmail.com": [logo], "alex@atelier.exemple": [logo]], projects: [(logo, "Logo")], mine: mine)
        #expect(rules.filing(of: thread(senders: ["inconnu.fictif.polhub@gmail.com"])) == nil)
        #expect(rules.filing(of: thread(senders: ["stagiaire@atelier.exemple"])) == nil)
    }

    @Test func automaticMailIsSortedAndPersoIsNeverGuessed() {
        #expect(rules.filing(of: thread(senders: ["recus@paiements.exemple"], subject: "Votre reçu n° 1042", category: "updates"))! == (.payments, .signals))
        #expect(rules.filing(of: thread(senders: ["notifications@mail.stripe.com"], subject: "Virement", category: "updates"))! == (.payments, .signals))
        #expect(rules.filing(of: thread(senders: ["alertes@banque.exemple"], subject: "Connexion à votre compte", category: "updates"))! == (.services, .signals))
        #expect(rules.filing(of: thread(senders: ["lettre@design.exemple"], category: "promotions"))! == (.newsletters, .signals))
        // A thread Paul wrote in is a person's, whatever Gmail says; an unknown person gets no case.
        #expect(rules.filing(of: thread(senders: ["support@outil.exemple", "moi@exemple.fr"], category: "updates", paulWrote: true)) == nil)
        #expect(rules.tab(of: thread(senders: ["support@outil.exemple"], category: "updates", paulWrote: true)) == .personnes)
        #expect(rules.filing(of: thread(senders: ["anne@exemple.org"])) == nil)
    }

    /// Never a person hidden among the automatic mails: a contact, someone Paul wrote to.
    @Test func knownPeopleStayWithThePeople() {
        #expect(rules.tab(of: thread(senders: ["marc@exemple.net"], category: "updates")) == .personnes)
        #expect(rules.tab(of: thread(senders: ["lea@exemple.org"], category: "social")) == .personnes)
        #expect(rules.tab(of: thread(senders: ["inconnu@exemple.org"], category: "social")) == .newsletters)
    }

    @Test func aCaseReadsBackAsItWasWritten() {
        for filing in [MailFiling.project(site), .perso, .newsletters, .payments, .services, .none] {
            #expect(MailFiling(rawValue: filing.rawValue) == filing)
        }
        #expect(MailFiling(rawValue: "projet:pas-un-uuid") == nil && MailFiling(rawValue: "") == nil)
    }
}
