import Agenda
import AppKit
import Combine
import Foundation
import MailFormat
import Persistence
import PolhubDesign
import ProjectsUI
import SwiftUI

// Contacts without the Contacts page (Paul, 15/11: he never opens it): who Paul writes to and invites, found as
// he types; who in a thread or an event is in its project, and a click to change it, where he is.

/// Someone Paul may write to or invite: a contact, someone he wrote to, someone who wrote to him.
struct PersonSuggestion: Identifiable, Equatable, Sendable {
    /// The name as Paul spelled it (a contact's), else as the mails gave it.
    var address: MailAddress
    var initials: String
    var company: String?
    /// The projects the person is in, links Paul removed left out.
    var projectIDs: Set<UUID>
    var isContact: Bool

    var id: String { address.email }
}

/// Where someone stands for a project (15/11).
enum PersonLink: Equatable, Sendable {
    /// A contact in the project.
    case member
    /// A contact Paul took out of the project: no gesture on many people puts them back.
    case removed
    /// A contact, not in the project (or no project).
    case contact
    /// Not a contact yet.
    case stranger
}

/// Everyone Paul may write to, ranked as he types (15/11): what begins with the letters typed first (a first
/// name, a last name, the address, the company), then what only contains them; among them, the people he writes
/// to most and lately. Built once, searched at each key.
struct PeopleIndex: Sendable {
    struct Entry: Sendable {
        var person: PersonSuggestion
        /// Words a typed word may begin: the name's, the address's pieces, the domain's, the company's, and the
        /// whole address.
        var words: [String]
        /// All of it, for a word found inside another.
        var text: String
        var boost: Double
    }

    private(set) var entries: [Entry]

    static let limit = 8

    /// - Parameters:
    ///   - correspondents: the people Paul wrote to, how often and when last.
    ///   - senders: who wrote to him (the people's tab of the inbox).
    ///   - projects: each address's projects, removed links left out.
    init(contacts: [ContactRow], correspondents: [String: MailCorrespondent] = [:], senders: [MailAddress] = [],
         projects: [String: Set<UUID>] = [:], mine: Set<String> = [], now: Date = Date()) {
        var people: [String: (name: String?, contact: ContactRow?)] = [:]
        var order: [String] = []
        func meet(_ email: String, name: String?, contact: ContactRow? = nil) {
            let email = email.lowercased()
            guard email.contains("@"), !mine.contains(email), !MailLibrary.isRobot(email) else { return }
            let name = name.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty || $0.lowercased() == email ? nil : $0 }
            if var known = people[email] {
                // A contact's name is Paul's spelling; otherwise the first name the mails gave stays.
                if known.contact == nil, let contact { known.contact = contact; known.name = name ?? known.name }
                if known.name == nil { known.name = name }
                people[email] = known
            } else {
                people[email] = (name, contact)
                order.append(email)
            }
        }
        for contact in contacts where contact.deletedAt == nil {
            if let email = contact.email { meet(email, name: contact.name, contact: contact) }
        }
        for (email, stats) in correspondents.sorted(by: { $0.key < $1.key }) { meet(email, name: stats.name) }
        for sender in senders { meet(sender.email, name: sender.name) }
        entries = order.compactMap { email in
            guard let found = people[email] else { return nil }
            let address = MailAddress(name: found.name, email: email)
            let company = found.contact?.company ?? Linker.company(forEmail: email)
            let person = PersonSuggestion(address: address, initials: Self.initials(name: found.name, email: email), company: company,
                                          projectIDs: projects[email] ?? [], isContact: found.contact != nil)
            let local = String(email.split(separator: "@").first ?? "")
            let domain = PublicMailDomains.domain(of: email) ?? ""
            let words = Self.words(found.name ?? "") + Self.words(local) + Self.words(domain) + Self.words(company ?? "") + [Self.fold(email)]
            let text = Self.fold([found.name ?? "", email, company ?? ""].joined(separator: " "))
            return Entry(person: person, words: words, text: text,
                         boost: Self.boost(correspondents[email], isContact: found.contact != nil, now: now))
        }
    }

    /// The people Paul writes to most, and lately, come first; a contact a little before a stranger.
    static func boost(_ stats: MailCorrespondent?, isContact: Bool, now: Date) -> Double {
        var boost = isContact ? 5.0 : 0
        if let stats, stats.sent > 0 {
            boost += min(40, 12 * log2(1 + Double(stats.sent)))
            let days = now.timeIntervalSince(stats.lastAt) / 86_400
            if days <= 30 { boost += 25 } else if days <= 180 { boost += 10 }
        }
        return boost
    }

    /// Up to eight people for what Paul typed; `excluding` the addresses already chosen. The people of
    /// `project` come first among equals.
    func search(_ typed: String, excluding: Set<String> = [], project: UUID? = nil, limit: Int = PeopleIndex.limit) -> [PersonSuggestion] {
        let tokens = Self.fold(typed).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return [] }
        let excluded = Set(excluding.map { $0.lowercased() })
        var found: [(entry: Entry, begins: Bool, score: Double)] = []
        for entry in entries where !excluded.contains(entry.person.address.email) {
            var begins = true
            var matches = true
            for token in tokens {
                if entry.words.contains(where: { $0.hasPrefix(token) }) { continue }
                // A word found inside another, from two letters: « mar » in « Lamarre ».
                if token.count >= 2, entry.text.contains(token) { begins = false; continue }
                matches = false
                break
            }
            guard matches else { continue }
            let inProject = project.map { entry.person.projectIDs.contains($0) } ?? false
            found.append((entry, begins, entry.boost + (inProject ? 30 : 0)))
        }
        found.sort { left, right in
            if left.begins != right.begins { return left.begins }
            if left.score != right.score { return left.score > right.score }
            return left.entry.person.address.display.localizedStandardCompare(right.entry.person.address.display) == .orderedAscending
        }
        return found.prefix(limit).map(\.entry.person)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    static func words(_ text: String) -> [String] {
        fold(text).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// « Camille Martin » → « CM »; without a name, the address's first letter.
    static func initials(name: String?, email: String) -> String {
        let words = (name ?? "").replacing(#/\s*\(.*?\)/#, with: "").split(separator: " ").filter { $0.count > 1 }
        let initials = words.prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
        return initials.isEmpty ? String(email.prefix(1)).uppercased() : initials
    }
}

/// The people of an open thread (15/11): who wrote, then who was in To and Cc; never Paul, a robot, a colleague
/// of Paul's own domain (he writes about every project), an address that is not one.
enum ThreadPeople {
    static func list(senders: [MailAddress], messages: [MailMessageRow], rules: MailFilingRules, mine: Set<String>) -> [MailAddress] {
        var people: [MailAddress] = []
        let everyone = senders + messages.flatMap { [$0.sender].compactMap { $0 } + $0.to + $0.cc }
        for person in everyone {
            let email = person.email.lowercased()
            guard !mine.contains(email), !rules.mine.contains(email), !MailLibrary.isRobot(email), !rules.isColleague(email),
                  MIMEBuilder.isValid(email) else { continue }
            if let index = people.firstIndex(where: { $0.email == email }) {
                if people[index].name == nil, let name = person.name { people[index].name = name }
            } else {
                people.append(MailAddress(name: person.name, email: email))
            }
        }
        return people
    }
}

/// Paul's gesture on people (15/11): who changed, and what takes it all back.
struct PeopleChange {
    var people: [MailAddress]
    var undo: () -> Void
}

/// The look of a person for a project: in it (its color and a check), a contact (a grey check), or to add (« + »).
enum PersonBadge: Equatable {
    case member(Color)
    case contact
    case add
    case none
}

/// How Paul's projects show with people.
enum PeopleStyle {
    /// A project's color, as its chip in the mails and its card on the board; grey without a project, never the accent
    /// (design system v2, 19/11).
    static func color(of project: ProjectRow?) -> Color {
        project.map(ProjectViews.tint) ?? .secondary
    }

    /// The first name, for a chip: « Camille » for « Camille Martin », the address's start without a name.
    static func firstName(_ person: MailAddress) -> String {
        if let name = person.name, let first = name.split(separator: " ").first { return String(first) }
        return String(person.email.split(separator: "@").first ?? Substring(person.email))
    }

    /// « Camille rejoint « Site vitrine » », « 3 personnes rejoignent… », « … est dans tes contacts ».
    static func addedText(_ people: [MailAddress], project: String?) -> String {
        let one = people.count == 1
        let names = people.map(firstName)
        let who = one ? people[0].display
            : (people.count <= 3 ? names.dropLast().joined(separator: ", ") + " et " + (names.last ?? "") : "\(people.count) personnes")
        if let project { return "\(who) \(one ? "rejoint" : "rejoignent") « \(project) »." }
        return one ? "\(who) est dans tes contacts." : "\(who) sont dans tes contacts."
    }
}

// MARK: - The links, for the calendar and the mails

extension AgendaLibrary {
    /// Where someone stands for a project; without a project, a contact or not.
    func link(of email: String, project: UUID?) -> PersonLink {
        guard let contact = contact(email: email) else { return .stranger }
        guard let project else { return .contact }
        switch linkIndex[contact.id]?[project] {
        case false?: return .member
        case true?: return .removed
        case nil: return .contact
        }
    }

    /// Each address's projects, removed links left out.
    var projectsByEmail: [String: Set<UUID>] {
        var result: [String: Set<UUID>] = [:]
        for contact in contacts {
            guard let email = contact.email, let links = linkIndex[contact.id] else { continue }
            let ids = Set(links.filter { !$0.value }.keys)
            if !ids.isEmpty { result[email] = ids }
        }
        return result
    }

    /// The badge of a person for a project: in it, a contact (when `contacts` says so), or to add.
    func badge(of email: String, project: UUID?, contacts: Bool = true) -> PersonBadge {
        switch link(of: email, project: project) {
        case .member: return .member(PeopleStyle.color(of: projects.first { $0.id == project }))
        case .contact, .removed: return contacts || project == nil ? .contact : .add
        case .stranger: return .add
        }
    }

    /// Each person a contact (named as the mail or the invitation names them, the company read in the address),
    /// and in the project when there is one. `respectRemoval`: someone Paul took out of the project stays out
    /// (the gestures on many people). Paul and robots are skipped. Nothing that was already so counts.
    func add(_ people: [MailAddress], to projectID: UUID?, respectRemoval: Bool, at date: Date = Date()) throws -> PeopleChange {
        let store = ContactStore(database)
        let mine = Set(accounts.map(\.email))
        var changed: [MailAddress] = []
        var takeBack: [() -> Void] = []
        var seen: Set<String> = []
        for person in people {
            let email = person.email.lowercased()
            guard seen.insert(email).inserted, !mine.contains(email), !MailLibrary.isRobot(email), MIMEBuilder.isValid(email) else { continue }
            let known = try store.contact(email: email)
            let before = try known.flatMap { contact in try store.links().first { $0.contactID == contact.id && $0.projectID == projectID } }
            if respectRemoval, before?.excluded == true { continue }
            let isNew = known == nil || known?.deletedAt != nil
            let alreadyIn = projectID == nil || before?.excluded == false
            if !isNew && alreadyIn { continue }
            let name = person.name ?? Linker.name(for: Attendee(email: email))
            let contact = try store.upsert(email: email, name: name, company: Linker.company(forEmail: email), at: date)
            if let projectID, !alreadyIn { try store.include(contactID: contact.id, projectID: projectID, at: date) }
            changed.append(MailAddress(name: known?.name ?? person.name, email: email))
            takeBack.append {
                if known == nil {
                    try? store.delete(contactID: contact.id)
                    return
                }
                if let known, known.deletedAt != nil { try? store.save(known, at: Date()) }
                guard let projectID, !alreadyIn else { return }
                if before == nil {
                    try? store.unlink(contactID: contact.id, projectID: projectID)
                } else {
                    try? store.exclude(contactID: contact.id, projectID: projectID, at: Date())
                }
            }
        }
        return PeopleChange(people: changed, undo: { takeBack.reversed().forEach { $0() } })
    }

    /// Paul takes someone out of a project: they stay out. Nothing when they were not in it.
    func remove(_ person: MailAddress, from projectID: UUID, at date: Date = Date()) throws -> PeopleChange {
        let store = ContactStore(database)
        guard let contact = try store.contact(email: person.email),
              let before = try store.links().first(where: { $0.contactID == contact.id && $0.projectID == projectID }), !before.excluded else {
            return PeopleChange(people: [], undo: {})
        }
        try store.exclude(contactID: contact.id, projectID: projectID, at: date)
        return PeopleChange(people: [MailAddress(name: contact.name, email: person.email.lowercased())], undo: {
            if before.origin == .paul {
                try? store.include(contactID: contact.id, projectID: projectID, at: Date())
            } else {
                // Back as it was: the automatic link it had, not one of Paul's.
                try? store.unlink(contactID: contact.id, projectID: projectID)
                try? store.link(contactID: contact.id, projectID: projectID, origin: before.origin, at: before.createdAt)
            }
        })
    }
}

// MARK: - The mails' side

/// Rebuilt on the next search after a change of the contacts, their projects, the rules or the inbox.
@MainActor
final class PeopleDirectory {
    private weak var mails: MailLibrary?
    private var index: PeopleIndex?
    private var cancellables: Set<AnyCancellable> = []

    init(mails: MailLibrary) {
        self.mails = mails
        let forget: (Any) -> Void = { [weak self] _ in self?.index = nil }
        mails.$rules.sink(receiveValue: forget).store(in: &cancellables)
        mails.$inbox.sink(receiveValue: forget).store(in: &cancellables)
        mails.agenda.$contacts.sink(receiveValue: forget).store(in: &cancellables)
        mails.agenda.$links.sink(receiveValue: forget).store(in: &cancellables)
        mails.agenda.$accounts.sink(receiveValue: forget).store(in: &cancellables)
    }

    var current: PeopleIndex {
        if let index { return index }
        guard let mails else { return PeopleIndex(contacts: []) }
        let built = PeopleIndex(contacts: mails.agenda.contacts, correspondents: mails.rules.correspondentStats,
                                senders: mails.inbox.filter { mails.rules.baseTab(of: $0) == .personnes }.flatMap(\.senders),
                                projects: mails.agenda.projectsByEmail, mine: mails.mine)
        index = built
        return built
    }
}

extension MailLibrary {
    /// Who Paul writes to, matching what he types: up to eight, the people of `project` first among equals.
    func suggestions(for text: String, excluding: Set<String> = [], project: UUID? = nil) -> [PersonSuggestion] {
        people.current.search(text, excluding: excluding, project: project)
    }

    /// The people of an open thread, as its row shows them.
    func people(of thread: MailThreadRow, messages: [MailMessageRow]) -> [MailAddress] {
        ThreadPeople.list(senders: thread.senders, messages: messages, rules: rules, mine: mine)
    }

    /// Those « Ajouter N au projet » takes: neither in the project nor taken out of it by Paul.
    func newcomers(_ people: [MailAddress], project: UUID) -> [MailAddress] {
        people.filter { person in
            let link = agenda.link(of: person.email, project: project)
            return link == .contact || link == .stranger
        }
    }

    /// People made contacts and put in the project, with one « Annuler ». One person chosen by Paul comes back
    /// into a project he took them out of; several never do.
    func add(_ people: [MailAddress], to projectID: UUID?, respectRemoval: Bool? = nil) {
        do {
            let change = try agenda.add(people, to: projectID, respectRemoval: respectRemoval ?? (people.count > 1))
            guard !change.people.isEmpty else { return }
            offerUndo(PeopleStyle.addedText(change.people, project: project(projectID)?.name), restore: change.undo)
        } catch {
            message = "Impossible d'ajouter au projet : \(error)"
        }
    }

    /// « Retirer de « P » », with its « Annuler ».
    func remove(_ person: MailAddress, from projectID: UUID) {
        do {
            let change = try agenda.remove(person, from: projectID)
            guard let who = change.people.first else { return }
            offerUndo("\(who.display) n'est plus dans « \(project(projectID)?.name ?? "le projet") ».", restore: change.undo)
        } catch {
            message = "Impossible de retirer du projet : \(error)"
        }
    }

    /// « Écrire »: a new mail to this person, over Mails; the mail being written is kept first.
    func write(to person: MailAddress, router: WindowRouter?) {
        closeComposer()
        newMail()
        if let id = composing { edit(id) { $0.to = [person] } }
        router?.section = .mails
    }

    /// « Copier l'adresse ».
    static func copy(_ email: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(email, forType: .string)
    }
}
