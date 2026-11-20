import Agenda
import MailFormat
import Persistence
import HubDesign
import ProjectsUI
import SwiftUI

// The people where Paul works (15/11): suggestions as he types, chips with their small menu, the row of a
// thread's people. Never a trip to the Contacts page.

/// Someone's initials, with what they are to Paul in a small badge: in the project (its color and a check), a
/// contact (a grey check), or to add (« + »).
struct PersonAvatar: View {
    let initials: String
    let tint: Color
    var badge: PersonBadge = .none
    var size: CGFloat = 28

    var body: some View {
        Avatar(initials, size: size, tint: tint)
            .overlay(alignment: .bottomTrailing) {
                let side = max(11, size * 0.4)
                PersonBadgeMark(badge: badge, size: side)
                    .background(Circle().fill(Color(nsColor: .windowBackgroundColor)).padding(-1.5).opacity(badge == .none ? 0 : 1))
                    .offset(x: side * 0.4, y: side * 0.3)
            }
    }
}

/// The mark of a badge alone: a check in the project's color, a grey check, a « + ». The symbol changes in place.
struct PersonBadgeMark: View {
    let badge: PersonBadge
    var size: CGFloat = 12

    private var symbol: (name: String, color: Color)? {
        switch badge {
        case .member(let color): ("checkmark.circle.fill", color)
        case .contact: ("checkmark.circle.fill", Color(nsColor: .systemGray))
        case .add: ("plus.circle.fill", Color(nsColor: .systemGray))
        case .none: nil
        }
    }

    var body: some View {
        Image(systemName: symbol?.name ?? "circle.fill")
            .font(.system(size: size, weight: .bold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, symbol?.color ?? .clear)
            .contentTransition(.symbolEffect(.replace))
            .opacity(symbol == nil ? 0 : 1)
            .animation(Motion.standard, value: symbol?.name)
    }
}

extension PersonBadge {
    /// What the badge says, under the pointer: someone in a project is « Dans « P » » (lot 10, 20/11).
    func help(project: String?) -> String {
        switch self {
        case .member: project.map { "Dans « \($0) »" } ?? "Contact"
        case .contact: "Contact"
        case .add: project.map { "Pas encore dans « \($0) »" } ?? "Pas encore un contact"
        case .none: ""
        }
    }
}

// MARK: - Suggestions

extension FocusedValues {
    /// A mail being written has the keyboard: a thread's bare arrows leave its fields alone (15/11).
    @Entry var writingMail: Bool?
}

/// ↑ and ↓ move among the suggestions, ↩ or ⇥ take the one lit, Échap closes them (15/11, as Gmail). With no
/// suggestion, the keys keep their usual sense.
struct SuggestionKeys: ViewModifier {
    let count: Int
    @Binding var highlighted: Int
    @Binding var moved: Bool
    @Binding var dismissed: Bool
    let accept: () -> Void

    /// The line lit after a move, kept inside the list.
    nonisolated static func next(_ current: Int, step: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(current + step, 0), count - 1)
    }

    func body(content: Content) -> some View {
        content
            .onKeyPress(.downArrow) { move(1) }
            .onKeyPress(.upArrow) { move(-1) }
            .onKeyPress(.tab) {
                guard count > 0 else { return .ignored }
                accept()
                return .handled
            }
            .onKeyPress(.escape) {
                guard count > 0 else { return .ignored }
                dismissed = true
                return .handled
            }
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard count > 0 else { return .ignored }
        highlighted = Self.next(highlighted, step: step, count: count)
        moved = true
        return .handled
    }
}

extension View {
    func suggestionKeys(count: Int, highlighted: Binding<Int>, moved: Binding<Bool>, dismissed: Binding<Bool>, accept: @escaping () -> Void) -> some View {
        modifier(SuggestionKeys(count: count, highlighted: highlighted, moved: moved, dismissed: dismissed, accept: accept))
    }
}

/// What ↩ or ⇥ takes: the line lit; but a whole address typed stays as typed, unless Paul moved to a line or the
/// line is that very address.
enum SuggestionChoice {
    static func accepted(typed: String, matches: [PersonSuggestion], highlighted: Int, moved: Bool) -> MailAddress? {
        guard matches.indices.contains(highlighted) else { return nil }
        let chosen = matches[highlighted]
        let typed = typed.trimmingCharacters(in: .whitespaces).lowercased()
        return moved || !MIMEBuilder.isValid(typed) || chosen.address.email == typed ? chosen.address : nil
    }
}

/// One suggestion: the avatar, the name and the address, the company; the project in its color.
struct PersonSuggestionRow: View {
    let person: PersonSuggestion
    let project: ProjectRow?
    let highlighted: Bool

    var body: some View {
        HStack(spacing: Space.m) {
            PersonAvatar(initials: person.initials, tint: MailText.tint(for: person.address.email), badge: person.isContact ? .contact : .none, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(person.address.name ?? person.address.email).font(.rowBody.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                Text([person.address.name == nil ? nil : person.address.email, person.company].compactMap { $0 }.joined(separator: " · "))
                    .font(.meta).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: Space.s)
            if let project { Chip(project.name, tint: PeopleStyle.color(of: project)) }
        }
        .padding(.horizontal, Space.s).padding(.vertical, 5)
        .hoverRow(selected: highlighted, radius: Radius.control)
    }
}

/// The suggestions under a field, in a small sheet of glass as the app's menus; the pointer lights a line as the
/// arrows do.
struct PersonSuggestionList: View {
    let matches: [PersonSuggestion]
    @Binding var highlighted: Int
    let project: (PersonSuggestion) -> ProjectRow?
    /// Glass under a mail's field; none in a form, already on its own surface.
    var glass = true
    let choose: (PersonSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(matches.enumerated()), id: \.element.id) { index, person in
                Button { choose(person) } label: {
                    PersonSuggestionRow(person: person, project: project(person), highlighted: index == highlighted)
                }
                .buttonStyle(.plain)
                .onHover { if $0 { highlighted = index } }
            }
        }
        .padding(glass ? Space.xs : 0)
        .frame(maxWidth: 520, alignment: .leading)
        .glassEffect(glass ? .regular : .identity, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .animation(Motion.quick, value: highlighted)
    }
}

// MARK: - A person's small menu

/// The menu of a person, where Paul is (15/11): in or out of the project, a contact, a mail, the address.
struct PersonMenuItems: View {
    let person: MailAddress
    let link: PersonLink
    let project: ProjectRow?
    /// Into the project, or among the contacts without one.
    let add: () -> Void
    let remove: () -> Void
    var write: (() -> Void)?

    var body: some View {
        Section(person.email) {
            // « Ajouter à « P » », « Retirer de « P » », as everywhere (lot 10, 20/11).
            if let project {
                if link == .member {
                    Button("Retirer de « \(project.name) »", systemImage: "minus.circle", action: remove)
                } else {
                    Button("Ajouter à « \(project.name) »", systemImage: "plus.circle", action: add)
                }
            } else if link == .stranger {
                Button("Ajouter aux contacts", systemImage: "person.crop.circle.badge.plus", action: add)
            }
        }
        if let write { Button("Écrire", systemImage: "square.and.pencil", action: write) }
        Button("Copier l'adresse", systemImage: "doc.on.doc") { MailLibrary.copy(person.email) }
    }
}

/// A person on a chip: avatar and first name; a click opens their menu.
struct PersonChip<Items: View>: View {
    let person: MailAddress
    let badge: PersonBadge
    let help: String
    @ViewBuilder let items: () -> Items

    var body: some View {
        Menu { items() } label: {
            // On a chip the mark follows the name: on so small an avatar it would hide the initials.
            HStack(spacing: 6) {
                Avatar(PeopleIndex.initials(name: person.name, email: person.email), size: 22, tint: MailText.tint(for: person.email))
                Text(PeopleStyle.firstName(person)).font(.meta).foregroundStyle(.primary).lineLimit(1)
                PersonBadgeMark(badge: badge, size: 13)
            }
            .padding(.leading, 3).padding(.trailing, Space.s - 2).padding(.vertical, 3)
            .background(Surface.fill, in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.hover(.capsule))
        .menuIndicator(.hidden)
        .fixedSize()
        .help("\(person.display) · \(person.email)\(help.isEmpty ? "" : " · \(help)")")
    }
}

extension MailLibrary {
    /// The chip of someone in the mails, for a thread's project.
    @ViewBuilder
    func chip(_ person: MailAddress, project: ProjectRow?, router: WindowRouter?, contacts: Bool = false) -> some View {
        let badge = agenda.badge(of: person.email, project: project?.id, contacts: contacts)
        PersonChip(person: person, badge: badge, help: badge.help(project: project?.name)) { [self] in
            self.menu(person, project: project, router: router)
        }
    }

    @ViewBuilder
    func menu(_ person: MailAddress, project: ProjectRow?, router: WindowRouter?) -> some View {
        PersonMenuItems(person: person, link: agenda.link(of: person.email, project: project?.id), project: project,
                        add: { [weak self] in self?.add([person], to: project?.id, respectRemoval: false) },
                        remove: { [weak self] in if let id = project?.id { self?.remove(person, from: id) } },
                        write: { [weak self] in self?.write(to: person, router: router) })
    }
}

// MARK: - The people of a thread

/// Under a thread's subject (15/11): its people, a check for those of its project, « + » for the others; and,
/// when some are missing from the project, « Ajouter N au projet « P » » in one click (with « Annuler »).
struct ThreadPeopleRow: View {
    let thread: MailThreadRow
    let messages: [MailMessageRow]
    @ObservedObject var mails: MailLibrary
    @ObservedObject var agenda: AgendaLibrary
    let router: WindowRouter?

    static let shown = 6

    init(thread: MailThreadRow, messages: [MailMessageRow], mails: MailLibrary, router: WindowRouter?) {
        self.thread = thread
        self.messages = messages
        self.mails = mails
        self.agenda = mails.agenda
        self.router = router
    }

    var body: some View {
        let people = mails.people(of: thread, messages: messages)
        let project = mails.project(mails.filing(of: thread)?.filing.projectID)
        let newcomers = project.map { mails.newcomers(people, project: $0.id) } ?? []
        if !people.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(people.prefix(Self.shown), id: \.email) { person in
                    mails.chip(person, project: project, router: router)
                }
                if people.count > Self.shown {
                    Menu {
                        ForEach(people.dropFirst(Self.shown), id: \.email) { person in
                            Menu(person.display) { mails.menu(person, project: project, router: router) }
                        }
                    } label: {
                        Text("+\(people.count - Self.shown)").font(.meta.weight(.medium)).foregroundStyle(.secondary)
                            .padding(.horizontal, Space.s).padding(.vertical, 5)
                            .background(Surface.fill, in: Capsule())
                    }
                    .menuStyle(.button)
                    .buttonStyle(.hover(.capsule))
                    .menuIndicator(.hidden)
                    .fixedSize()
                    // A verb first (lot 10, 20/11).
                    .help("Voir les autres personnes du fil")
                }
                if let project, !newcomers.isEmpty {
                    Button {
                        withAnimation(Motion.standard) { mails.add(newcomers, to: project.id, respectRemoval: true) }
                    } label: {
                        // « Ajouter Claire à « P » », « Ajouter les 3 à « P » »: never « Ajouter 1 au projet » (lot 10, 20/11).
                        Label(Words.typeset(newcomers.count == 1 ? "Ajouter \(PeopleStyle.firstName(newcomers[0])) à « \(project.name) »"
                                                                 : "Ajouter les \(Words.number(newcomers.count)) à « \(project.name) »"),
                              systemImage: "person.badge.plus")
                    }
                    // No glass in the content: a secondary action (design system v2, 19/11).
                    .buttonStyle(.secondary)
                    .controlSize(.small)
                    .help(newcomers.map(\.display).joined(separator: ", "))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(Motion.standard, value: newcomers.count)
        }
    }
}

// MARK: - A message's people

/// The sender of a message: a check when a contact, in the color of the thread's project when in it.
struct MessagePersonAvatar: View {
    let person: MailAddress?
    let initials: String
    let tint: Color
    let project: UUID?
    @ObservedObject var agenda: AgendaLibrary

    var body: some View {
        let badge = person.map { agenda.badge(of: $0.email, project: project) } ?? PersonBadge.none
        // A stranger has nothing at rest: « + » shows by the name under the pointer.
        let shown = badge == .add ? PersonBadge.none : badge
        PersonAvatar(initials: initials, tint: tint, badge: shown, size: 40)
            .help(shown.help(project: agenda.projects.first { $0.id == project }?.name))
    }
}

/// « + » by a sender's name, under the pointer: into the thread's project, or among the contacts. Always laid
/// out, so nothing moves when it shows.
struct MessageAddButton: View {
    let person: MailAddress
    let project: UUID?
    let mails: MailLibrary
    let visible: Bool
    @ObservedObject var agenda: AgendaLibrary

    init(person: MailAddress, project: UUID?, mails: MailLibrary, visible: Bool) {
        self.person = person
        self.project = project
        self.mails = mails
        self.visible = visible
        self.agenda = mails.agenda
    }

    var body: some View {
        let link = agenda.link(of: person.email, project: project)
        let name = mails.project(project)?.name
        let title: String? = project != nil ? (link == .member ? nil : "Ajouter à « \(name ?? "le projet") »")
            : (link == .stranger ? "Ajouter aux contacts" : nil)
        if let title {
            Button { mails.add([person], to: project, respectRemoval: false) } label: {
                Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 14)).frame(width: 24, height: 24)
            }
            .buttonStyle(.hover(.circle))
            .foregroundStyle(.secondary)
            .help(title)
            .accessibilityLabel(title)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .animation(Motion.quick, value: visible)
        }
    }
}

/// À and Cc in a message's details: each person a chip with its menu; Paul as « moi ».
struct MessagePeople: View {
    let people: [MailAddress]
    let mine: Set<String>
    let project: UUID?
    let mails: MailLibrary
    @ObservedObject var agenda: AgendaLibrary

    init(people: [MailAddress], mine: Set<String>, project: UUID?, mails: MailLibrary) {
        self.people = people
        self.mine = mine
        self.project = project
        self.mails = mails
        self.agenda = mails.agenda
    }

    var body: some View {
        let project = mails.project(project)
        FlowLayout(spacing: 4) {
            ForEach(people, id: \.email) { person in
                if mine.contains(person.email) {
                    Text("moi").padding(.horizontal, Space.s).padding(.vertical, 3).background(Surface.fill, in: Capsule()).help(person.email)
                } else {
                    mails.chip(person, project: project, router: nil, contacts: true)
                }
            }
        }
    }
}

// MARK: - A meeting's people

/// The participants of a meeting, on its page (15/11): the same chips and small menu as in the mails and the
/// calendar, for the meeting's project. Never a trip to the Contacts page.
@MainActor
enum MeetingPeople {
    /// A participant as the mails know people: Paul's spelling of the name.
    static func person(_ contact: ContactRow, email: String) -> MailAddress {
        MailAddress(name: contact.name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : contact.name, email: email.lowercased())
    }

    /// In the meeting's project (its color), to add to it (« + »); a contact when the meeting has no project.
    static func badge(of person: MailAddress, project: UUID?, agenda: AgendaLibrary) -> PersonBadge {
        agenda.badge(of: person.email, project: project, contacts: false)
    }

    /// « Ajouter à « P » » or « Retirer de « P » », « Écrire », « Copier l'adresse ».
    static func items(_ person: MailAddress, project: ProjectRow?, agenda: AgendaLibrary, router: WindowRouter) -> PersonMenuItems {
        let write: (() -> Void)? = agenda.mails.map { mails in { [weak mails, weak router] in mails?.write(to: person, router: router) } }
        return PersonMenuItems(person: person, link: agenda.link(of: person.email, project: project?.id), project: project,
                               add: {
                                   _ = try? agenda.add([person], to: project?.id, respectRemoval: false)
                                   Task { await agenda.runLinks() }
                               },
                               remove: {
                                   guard let id = project?.id else { return }
                                   _ = try? agenda.remove(person, from: id)
                                   Task { await agenda.runLinks() }
                               },
                               write: write)
    }
}

/// A participant on a chip: their small menu when the agenda is there and they have an address; else the name.
struct MeetingPersonChip: View {
    static let shown = 6

    let contact: ContactRow
    let project: ProjectRow?
    let agenda: AgendaLibrary?
    let router: WindowRouter

    var body: some View {
        if let agenda, let email = contact.email, !email.isEmpty {
            Observing(agenda) { agenda in
                let person = MeetingPeople.person(contact, email: email)
                let badge = MeetingPeople.badge(of: person, project: project?.id, agenda: agenda)
                PersonChip(person: person, badge: badge, help: badge.help(project: project?.name)) {
                    MeetingPeople.items(person, project: project, agenda: agenda, router: router)
                }
            }
        } else {
            HStack(spacing: 6) {
                Avatar(contact.initials, size: 22, tint: MailText.tint(for: contact.email ?? contact.name))
                Text(contact.name).font(.meta).lineLimit(1)
            }
            .padding(.leading, 3).padding(.trailing, Space.s).padding(.vertical, 3)
            .background(Surface.fill, in: Capsule())
            .help(contact.name)
        }
    }
}

/// « +3 »: the other participants, each with their small menu.
struct MeetingMorePeople: View {
    let people: [ContactRow]
    let project: ProjectRow?
    let agenda: AgendaLibrary?
    let router: WindowRouter

    var body: some View {
        Menu {
            ForEach(people) { contact in
                if let agenda, let email = contact.email, !email.isEmpty {
                    Menu(contact.name) { MeetingPeople.items(MeetingPeople.person(contact, email: email), project: project, agenda: agenda, router: router) }
                } else {
                    Text(contact.name)
                }
            }
        } label: {
            Text("+\(people.count)").font(.meta.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, Space.s).padding(.vertical, 5)
                .background(Surface.fill, in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.hover(.capsule))
        .menuIndicator(.hidden)
        .fixedSize()
        .help(people.map(\.name).joined(separator: ", "))
    }
}
