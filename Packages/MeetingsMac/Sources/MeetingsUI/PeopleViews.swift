import Agenda
import MailFormat
import Persistence
import PolhubDesign
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

    private var symbol: (name: String, color: Color)? {
        switch badge {
        case .member(let color): ("checkmark.circle.fill", color)
        case .contact: ("checkmark.circle.fill", Color(nsColor: .systemGray))
        case .add: ("plus.circle.fill", Color(nsColor: .systemGray))
        case .none: nil
        }
    }

    var body: some View {
        Avatar(initials, size: size, tint: tint)
            .overlay(alignment: .bottomTrailing) {
                let side = max(11, size * 0.44)
                Image(systemName: symbol?.name ?? "circle.fill")
                    .font(.system(size: side, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, symbol?.color ?? .clear)
                    .background(Circle().fill(Color(nsColor: .windowBackgroundColor)).padding(-1.5))
                    .contentTransition(.symbolEffect(.replace))
                    .opacity(symbol == nil ? 0 : 1)
                    .offset(x: side * 0.22, y: side * 0.22)
                    .animation(Motion.standard, value: symbol?.name)
            }
    }
}

extension PersonBadge {
    /// What the badge says, under the pointer.
    func help(project: String?) -> String {
        switch self {
        case .member: project.map { "Contact de « \($0) »" } ?? "Contact"
        case .contact: "Contact"
        case .add: project.map { "Pas encore dans « \($0) »" } ?? "Pas encore un contact"
        case .none: ""
        }
    }
}

// MARK: - Suggestions

/// ↑ and ↓ move among the suggestions, ↩ or ⇥ take the one lit, Échap closes them (15/11, as Gmail). With no
/// suggestion, the keys keep their usual sense.
struct SuggestionKeys: ViewModifier {
    let count: Int
    @Binding var highlighted: Int
    @Binding var moved: Bool
    @Binding var dismissed: Bool
    let accept: () -> Void

    /// The line lit after a move, kept inside the list.
    static func next(_ current: Int, step: Int, count: Int) -> Int {
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
        .hoverRow(selected: highlighted, radius: Radius.small)
    }
}

/// The suggestions under a field, in a small sheet of glass as the app's menus; the pointer lights a line as the
/// arrows do.
struct PersonSuggestionList: View {
    let matches: [PersonSuggestion]
    @Binding var highlighted: Int
    let project: (PersonSuggestion) -> ProjectRow?
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
        .padding(Space.xs)
        .frame(maxWidth: 520, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
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
            HStack(spacing: 6) {
                PersonAvatar(initials: PeopleIndex.initials(name: person.name, email: person.email), tint: MailText.tint(for: person.email),
                             badge: badge, size: 22)
                Text(PeopleStyle.firstName(person)).font(.meta).foregroundStyle(.primary).lineLimit(1)
            }
            .padding(.leading, 3).padding(.trailing, Space.s).padding(.vertical, 3)
            .background(Surface.fill, in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .hoverRow(radius: 14)
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
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .hoverRow(radius: 14)
                    .help("Les autres personnes du fil")
                }
                if let project, !newcomers.isEmpty {
                    Button {
                        withAnimation(Motion.standard) { mails.add(newcomers, to: project.id, respectRemoval: true) }
                    } label: {
                        Label("Ajouter \(newcomers.count) au projet « \(project.name) »", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .help(newcomers.map(\.display).joined(separator: ", "))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(Motion.standard, value: newcomers.count)
        }
    }
}
