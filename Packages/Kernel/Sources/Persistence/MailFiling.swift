import Foundation
import GRDB

/// The two tabs of the list (Paul, 15/11): what people wrote; what services and lists send on their own. The
/// newsletters joined the notifications: their case (Newsletters) still says which they are.
public enum MailTab: String, Hashable, Sendable, CaseIterable {
    case personnes, notifications

    /// Tolerant: « newsletters », the third tab of 0.13 to 0.16 that a sender may still hold in `mail_sender.tab`,
    /// reads as Notifications. No migration rewrites it.
    public init?(rawValue: String) {
        switch rawValue {
        case "personnes": self = .personnes
        case "notifications", "newsletters": self = .notifications
        default: return nil
        }
    }

    public var title: String {
        switch self {
        case .personnes: "Personnes"
        case .notifications: "Notifications"
        }
    }

    /// What the tab holds, said where Paul sees it.
    public var explanation: String {
        switch self {
        case .personnes: "Les mails écrits par des personnes : clients, collègues, proches."
        // « newsletter », never « lettre d'information » (lot 10, 20/11).
        case .notifications: "Ce que des services et des listes envoient tout seuls : reçus, alertes, rappels, newsletters, promotions. Rien n'y attend de réponse."
        }
    }

    /// Gmail's category of a mail: its « Notifications », « Promotions » and « Réseaux sociaux » are automatic;
    /// everything else (« Principale », « Forums », none) is people.
    public static func of(category: String?) -> MailTab {
        switch category {
        case "updates", "promotions", "social": .notifications
        default: .personnes
        }
    }
}

/// « La case » of a thread (plan of 14/11, step « Ranger »): a project, or Perso, Newsletters, Paiements,
/// Services. Polhub only: no label is made in Gmail. `none` is Paul saying the thread has no case.
public enum MailFiling: Hashable, Sendable {
    case project(UUID)
    case perso, newsletters, payments, services
    case none

    public init?(rawValue: String) {
        switch rawValue {
        case "perso": self = .perso
        case "newsletters": self = .newsletters
        case "paiements": self = .payments
        case "services": self = .services
        case "aucune": self = .none
        default:
            guard rawValue.hasPrefix("projet:"), let id = UUID(uuidString: String(rawValue.dropFirst("projet:".count))) else { return nil }
            self = .project(id)
        }
    }

    public var rawValue: String {
        switch self {
        case .project(let id): "projet:\(id.uuidString.lowercased())"
        case .perso: "perso"
        case .newsletters: "newsletters"
        case .payments: "paiements"
        case .services: "services"
        case .none: "aucune"
        }
    }

    /// The tab the case puts its thread in: a project and Perso are people's.
    public var tab: MailTab {
        switch self {
        case .project, .perso, .none: .personnes
        case .newsletters, .payments, .services: .notifications
        }
    }

    public var projectID: UUID? {
        if case .project(let id) = self { id } else { nil }
    }

    /// The word on the chip; a project's is its name, `none` has none.
    public var title: String? {
        switch self {
        case .project, .none: nil
        case .perso: "Perso"
        case .newsletters: "Newsletters"
        case .payments: "Paiements"
        case .services: "Services"
        }
    }

    /// The cases that are not projects, in the menu's order.
    public static let categories: [MailFiling] = [.perso, .newsletters, .payments, .services]
}

/// Why a thread has its case: said by the chip.
public enum MailFilingOrigin: String, Sendable {
    case paul, sender, contacts, domain, signals

    public var explanation: String {
        switch self {
        case .paul: "Rangé par toi"
        case .sender: "Comme les autres mails de cet expéditeur"
        case .contacts: "L'expéditeur est un contact du projet"
        case .domain: "Même domaine que les contacts du projet"
        case .signals: "Mail automatique"
        }
    }
}

/// Mailboxes of everyone: no company to read in them.
public enum PublicMailDomains {
    public static let all: Set<String> = [
        "gmail.com", "googlemail.com", "outlook.com", "outlook.fr", "hotmail.com", "hotmail.fr", "live.com", "live.fr", "msn.com",
        "icloud.com", "me.com", "mac.com", "yahoo.com", "yahoo.fr", "orange.fr", "wanadoo.fr", "free.fr", "sfr.fr", "laposte.net",
        "gmx.fr", "gmx.com", "proton.me", "protonmail.com", "aol.com", "bbox.fr", "neuf.fr", "numericable.fr",
        // Second review of 14/11: the other countries' Gmail, Outlook and Yahoo, the mailboxes of privacy, of Belgium and Switzerland.
        "gmail.fr", "outlook.be", "outlook.ch", "hotmail.be", "hotmail.ch", "live.be", "yahoo.be", "yahoo.ch", "ymail.com", "rocketmail.com",
        "gmx.de", "gmx.net", "gmx.ch", "web.de", "pm.me", "protonmail.ch", "fastmail.com", "fastmail.fm", "zoho.com", "zohomail.eu",
        "tutanota.com", "tuta.io", "mail.com", "yandex.com", "yandex.ru", "skynet.be", "telenet.be", "proximus.be", "bluewin.ch",
        "sunrise.ch", "aliceadsl.fr", "club-internet.fr", "voila.fr", "cegetel.net", "dbmail.com", "hey.com", "duck.com",
    ]

    public static func domain(of email: String) -> String? {
        email.lowercased().split(separator: "@").last.map(String.init).flatMap { $0.contains(".") ? $0 : nil }
    }
}

/// A project's name in a text, as whole words: one project only, or none.
public enum ProjectNames {
    public static func named(in title: String, projects: [(id: UUID, name: String)]) -> UUID? {
        let words = tokens(title)
        let found = Set(projects.filter { project in
            let name = tokens(project.name)
            guard !name.isEmpty, name.joined().count >= 3, name.count <= words.count else { return false }
            return (0...(words.count - name.count)).contains { Array(words[$0..<$0 + name.count]) == name }
        }.map(\.id))
        return found.count == 1 ? found.first : nil
    }

    public static func tokens(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
}

/// The case of a thread, by one cascade of rules from the surest to the least sure; the first that answers
/// wins (plan of 14/11):
/// 1. Paul's choice on this thread, never recomputed;
/// 2. the case he chose last for this sender;
/// 3. the senders are contacts of one project (of several: the one the subject names); people in copy never
///    count, so a stranger cannot put his mail in a project by copying a contact;
/// 4. the sender's domain, neither everyone's nor Paul's, when its contacts share one project;
/// 5. a thread Paul never wrote in, automatic: Newsletters (Gmail's Promotions and Réseaux sociaux, or a sender
///    Paul once put in the old Newsletters tab), Paiements or Services;
/// 6. else no case. Perso is never guessed.
/// A contact, someone Paul wrote to, a thread he wrote in: never hidden among the automatic mails.
public struct MailFilingRules: Sendable {
    public var choices: [String: MailFiling]
    public var senders: [String: MailSenderRow]
    public var contactProjects: [String: Set<UUID>]
    public var contacts: Set<String>
    public var projects: [(id: UUID, name: String)]

    /// A case that still names something: a project of the list, or any other case.
    func exists(_ filing: MailFiling) -> Bool {
        guard let id = filing.projectID else { return true }
        return projects.contains { $0.id == id }
    }
    public var mine: Set<String>
    public var correspondents: Set<String>
    /// The people Paul wrote to, how often and when last (15/11): what ranks the suggestions.
    public var correspondentStats: [String: MailCorrespondent] = [:]
    /// The projects Paul took each address out of (15/11).
    public var excludedProjects: [String: Set<UUID>] = [:]
    private var domainProjects: [String: Set<UUID>] = [:]
    private var myDomains: Set<String> = []
    /// Paul's domains that are only his (not gmail.com and the like).
    private var myOwnDomains: Set<String> { myDomains.subtracting(PublicMailDomains.all) }

    public init(choices: [String: MailFiling] = [:], senders: [String: MailSenderRow] = [:], contactProjects: [String: Set<UUID>] = [:],
                contacts: Set<String> = [], projects: [(id: UUID, name: String)] = [], mine: Set<String> = [], correspondents: Set<String> = []) {
        self.choices = choices
        self.senders = senders
        self.contactProjects = Dictionary(contactProjects.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { $0.union($1) })
        self.contacts = Set(contacts.map { $0.lowercased() })
        self.projects = projects
        self.mine = Set(mine.map { $0.lowercased() })
        self.correspondents = Set(correspondents.map { $0.lowercased() })
        myDomains = Set(self.mine.compactMap(PublicMailDomains.domain(of:)))
        for (email, ids) in self.contactProjects {
            guard let domain = PublicMailDomains.domain(of: email), !PublicMailDomains.all.contains(domain), !myDomains.contains(domain) else { continue }
            domainProjects[domain, default: []].formUnion(ids)
        }
    }

    public static let empty = MailFilingRules()

    /// The thread's people: a thread Paul wrote in; a sender he placed; a contact or someone he wrote to;
    /// else Gmail's category.
    public func baseTab(of thread: MailThreadRow) -> MailTab {
        if thread.paulWrote { return .personnes }
        if let last = thread.lastSender?.lowercased() {
            if let chosen = senders[last]?.tab.flatMap(MailTab.init(rawValue:)) { return chosen }
            if isPerson(last) { return .personnes }
        }
        return MailTab.of(category: thread.category)
    }

    /// The tab the list shows the thread in: its case's, else its base.
    public func tab(of thread: MailThreadRow) -> MailTab {
        filing(of: thread)?.filing.tab ?? baseTab(of: thread)
    }

    public func filing(of thread: MailThreadRow) -> (filing: MailFiling, origin: MailFilingOrigin)? {
        // A project deleted since (15/11) is no case any more: its threads follow the rules again.
        if let choice = choices[thread.id], exists(choice) { return (choice, .paul) }
        // A colleague of Paul's own domain writes about everything: a case kept for him (a client's thread he answered
        // last, filed by Paul) files none of his other threads, no more than his links do (audit of 19/11).
        if let last = thread.lastSender?.lowercased(), !isColleague(last), let memory = senders[last]?.filing.flatMap(MailFiling.init(rawValue:)),
           exists(memory) {
            return (memory, .sender)
        }
        let others = thread.senders.map { $0.email.lowercased() }.filter { !mine.contains($0) }
        // A colleague of Paul's own domain writes about everything: his links say nothing of this thread.
        let outside = others.filter { PublicMailDomains.domain(of: $0).map { !myOwnDomains.contains($0) } ?? true }
        let linked = outside.compactMap { contactProjects[$0] }.reduce(into: Set<UUID>()) { $0.formUnion($1) }
        if linked.count == 1, let id = linked.first { return (.project(id), .contacts) }
        if linked.count > 1, let id = ProjectNames.named(in: thread.subject, projects: projects.filter { linked.contains($0.id) }) {
            return (.project(id), .contacts)
        }
        let base = baseTab(of: thread)
        // The domain speaks only for strangers: a contact Paul took out of a project stays out.
        if linked.isEmpty, base == .personnes, !others.contains(where: contacts.contains) {
            let domains = Set(others.compactMap(PublicMailDomains.domain(of:)))
            let found = domains.compactMap { domainProjects[$0] }.reduce(into: Set<UUID>()) { $0.formUnion($1) }
            if found.count == 1, let id = found.first { return (.project(id), .domain) }
        }
        if !thread.paulWrote, base == .notifications {
            if isNewsletter(thread) { return (.newsletters, .signals) }
            return (Self.isPayment(subject: thread.subject, sender: thread.lastSender) ? .payments : .services, .signals)
        }
        return nil
    }

    /// A letter or a promotion: a sender Paul put in the old Newsletters tab (0.13), who keeps that case now the
    /// tab is gone (15/11), or Gmail's Promotions and Réseaux sociaux. A sender Paul put in Notifications (0.16)
    /// keeps his choice over Gmail's category: Paiements or Services (correctifs, 15/11).
    public func isNewsletter(_ thread: MailThreadRow) -> Bool {
        switch thread.lastSender.flatMap({ senders[$0.lowercased()]?.tab }) {
        case "newsletters": true
        case "notifications": false
        default: ["promotions", "social"].contains(thread.category ?? "")
        }
    }

    /// A contact, or someone Paul wrote to.
    public func isPerson(_ email: String) -> Bool {
        let address = email.lowercased()
        return contacts.contains(address) || correspondents.contains(address) || contactProjects[address] != nil
    }

    static let paymentDomains: Set<String> = [
        "stripe.com", "paypal.com", "paypal.fr", "qonto.com", "sumup.com", "payplug.com", "mollie.com", "gocardless.com", "lydia-app.com",
        "paddle.com", "lemonsqueezy.com", "revolut.com", "wise.com", "shine.fr", "pennylane.com", "sumeria.eu",
    ]
    static let paymentWords: Set<String> = [
        "facture", "factures", "recu", "recus", "invoice", "invoices", "receipt", "receipts", "paiement", "paiements", "payment", "payments",
        "prelevement", "prelevements", "remboursement", "refund", "quittance", "echeance", "echeancier",
    ]

    /// An invoice, a receipt, a payment: said by the subject's words or by a payment provider's address.
    public static func isPayment(subject: String, sender: String?) -> Bool {
        if let domain = sender.flatMap(PublicMailDomains.domain(of:)),
           paymentDomains.contains(where: { domain == $0 || domain.hasSuffix(".\($0)") }) { return true }
        return ProjectNames.tokens(subject).contains(where: paymentWords.contains)
    }
}
