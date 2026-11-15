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
        #expect(rules.tab(of: thread(senders: ["inconnu@exemple.org"], category: "social")) == .notifications)
    }

    /// 15/11: two tabs. The old Newsletters tab, still in `mail_sender.tab` for a sender moved there in 0.13,
    /// reads as Notifications, and his threads keep the Newsletters case.
    @Test func theNewslettersJoinTheNotificationsAndKeepTheirCase() {
        #expect(MailTab.allCases == [.personnes, .notifications])
        #expect(MailTab(rawValue: "newsletters") == .notifications && MailTab(rawValue: "personnes") == .personnes)
        #expect(MailTab(rawValue: "notifications") == .notifications && MailTab(rawValue: "principal") == nil)
        #expect(MailTab.of(category: "promotions") == .notifications && MailTab.of(category: "updates") == .notifications)
        #expect(MailTab.of(category: "forums") == .personnes && MailTab.of(category: nil) == .personnes)
        #expect(MailFiling.newsletters.tab == .notifications && MailFiling.payments.tab == .notifications)
        // A promotion: Notifications, case Newsletters.
        let letter = thread(senders: ["lettre@design.exemple"], category: "promotions")
        #expect(rules.tab(of: letter) == .notifications && rules.filing(of: letter)! == (.newsletters, .signals))
        // Moved to Newsletters in 0.13, although Gmail calls it a notification.
        var rules = rules
        rules.senders = ["club@lecture.exemple": MailSenderRow(address: "club@lecture.exemple", principal: false, images: false, createdAt: Date(), tab: "newsletters")]
        let club = thread(senders: ["club@lecture.exemple"], subject: "Le programme de décembre", category: "updates")
        #expect(rules.tab(of: club) == .notifications && rules.filing(of: club)! == (.newsletters, .signals))
        // Moved there too, but Gmail says « Principale »: still Notifications, as Paul chose.
        rules.senders["club@lecture.exemple"]?.tab = "newsletters"
        #expect(rules.tab(of: thread(senders: ["club@lecture.exemple"], category: "personal")) == .notifications)
        // Without that memory, an update is a service.
        #expect(rules.filing(of: thread(senders: ["alertes@outil.exemple"], subject: "Programme", category: "updates"))! == (.services, .signals))
    }

    /// Correctifs du 15/11 : un expéditeur que Paul avait mis dans « Notifications » en 0.16 garde ce choix, même
    /// quand Gmail range ses mails dans Promotions : ses factures restent des Paiements, pas des Newsletters.
    @Test func paulsNotificationsChoiceWinsOverGmailsPromotions() {
        var rules = rules
        rules.senders = ["factures@logiciel.exemple": MailSenderRow(address: "factures@logiciel.exemple", principal: false, images: false,
                                                                   createdAt: Date(), tab: "notifications")]
        let invoice = thread(senders: ["factures@logiciel.exemple"], subject: "Votre facture de novembre", category: "promotions")
        #expect(!rules.isNewsletter(invoice))
        #expect(rules.filing(of: invoice)! == (.payments, .signals))
        // Without Paul's choice, Gmail's Promotions still says Newsletters.
        rules.senders = [:]
        #expect(rules.filing(of: invoice)! == (.newsletters, .signals))
    }

    /// Second review of 14/11: a colleague of Paul's own domain, linked to one project, does not file every
    /// internal mail there; a contact taken out of a project does not come back by the domain.
    @Test func colleaguesAndRemovedContactsAreNotFiledByTheirLinks() {
        let rules = MailFilingRules(contactProjects: ["alex@atelier.exemple": [logo], "camille@studio.exemple": [site]],
                                    contacts: ["alex@atelier.exemple", "camille@studio.exemple", "jules@studio.exemple"],
                                    projects: [(site, "Site vitrine"), (logo, "Logo")], mine: mine)
        #expect(rules.filing(of: thread(senders: ["alex@atelier.exemple"], subject: "Déjeuner vendredi")) == nil)
        // Jules was taken out of « Site vitrine » (not linked any more) but works at the studio.
        #expect(rules.filing(of: thread(senders: ["jules@studio.exemple"])) == nil)
        // A stranger of the studio still goes there by the domain.
        #expect(rules.filing(of: thread(senders: ["lou@studio.exemple"]))! == (.project(site), .domain))
    }

    @Test func aCaseReadsBackAsItWasWritten() {
        for filing in [MailFiling.project(site), .perso, .newsletters, .payments, .services, .none] {
            #expect(MailFiling(rawValue: filing.rawValue) == filing)
        }
        #expect(MailFiling(rawValue: "projet:pas-un-uuid") == nil && MailFiling(rawValue: "") == nil)
    }
}
