import Agenda
import Persistence
import PolhubDesign
import SwiftUI

/// The guests of an event, in its card (15/11): who is a contact, who is in the event's project, and the click to
/// change it without leaving the calendar. « Lier les invités à « P » » when some are missing from the project.
struct EventGuests: View {
    let event: CalendarEventRow
    @ObservedObject var agenda: AgendaLibrary
    @ObservedObject var router: WindowRouter
    let close: () -> Void

    struct Guest: Identifiable {
        let attendee: Attendee
        var id: String { attendee.email }
    }

    /// The guests who are not Paul, under any of his accounts.
    nonisolated static func guests(of event: CalendarEventRow, mine: Set<String>) -> [Attendee] {
        event.guests.filter { !mine.contains($0.email) }
    }

    /// « Invités · 5 », « Invités · 5 · 3 dans « Site vitrine » ».
    nonisolated static func title(count: Int, members: Int, project: String?) -> String {
        guard let project, members > 0 else { return "Invités · \(count)" }
        return "Invités · \(count) · \(members) dans « \(project) »"
    }

    var body: some View {
        let guests = Self.guests(of: event, mine: Set(agenda.accounts.map(\.email)))
        let project = agenda.projects.first { $0.id == event.projectID }
        let links = guests.map { agenda.link(of: $0.email, project: project?.id) }
        let newcomers = project == nil ? [] : zip(guests, links).filter { $0.1 == .contact || $0.1 == .stranger }.map(\.0)
        if !guests.isEmpty {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(Self.title(count: guests.count, members: links.filter { $0 == .member }.count, project: project?.name))
                    .font(.meta.weight(.semibold)).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                ShowMoreList(guests.map(Guest.init), limit: 8) { guest in
                    GuestRow(guest: guest.attendee, project: project, agenda: agenda, router: router, close: close)
                }
                if let project, !newcomers.isEmpty {
                    Button {
                        withAnimation(Motion.standard) {
                            _ = try? agenda.add(newcomers.map(GuestRow.person(agenda)), to: project.id, respectRemoval: true)
                        }
                        Task { await agenda.runLinks() }
                    } label: {
                        Label("Lier les invités à « \(project.name) »", systemImage: "person.2.badge.plus")
                    }
                    .buttonStyle(.secondary)
                    .controlSize(.small)
                    .help(newcomers.map(GuestRow.person(agenda)).map(\.display).joined(separator: ", "))
                    .padding(.top, Space.xs)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(Motion.standard, value: newcomers.count)
        }
    }
}

/// A guest: the avatar, the name, the company, the answer, and on the right, in words, where they stand
/// (Paul, 15/11: the marks alone were a riddle, and a « − » read as « remove from the meeting »): « Dans « P » »,
/// or a button « Ajouter au projet » / « Ajouter aux contacts ». Taking someone out of a project is in their menu,
/// on a click, never under the pointer.
struct GuestRow: View {
    let guest: Attendee
    let project: ProjectRow?
    @ObservedObject var agenda: AgendaLibrary
    @ObservedObject var router: WindowRouter
    let close: () -> Void

    /// A guest as the mails know people: the contact's name, else Google's, else one read in the address.
    static func person(_ agenda: AgendaLibrary) -> (Attendee) -> MailAddress {
        { guest in MailAddress(name: agenda.contact(email: guest.email)?.name ?? Linker.name(for: guest), email: guest.email) }
    }

    private func add(_ person: MailAddress) {
        _ = try? agenda.add([person], to: project?.id, respectRemoval: false)
        Task { await agenda.runLinks() }
    }

    private func remove(_ person: MailAddress) {
        guard let id = project?.id else { return }
        _ = try? agenda.remove(person, from: id)
        Task { await agenda.runLinks() }
    }

    var body: some View {
        let contact = agenda.contact(email: guest.email)
        let person = Self.person(agenda)(guest)
        let link = agenda.link(of: guest.email, project: project?.id)
        let write: (() -> Void)? = agenda.mails.map { mails in { [router] in
            close()
            mails.write(to: person, router: router)
        } }
        let items = PersonMenuItems(person: person, link: link, project: project, add: { add(person) }, remove: { remove(person) }, write: write)
        HStack(spacing: Space.s) {
            Menu { items } label: {
                HStack(spacing: Space.s) {
                    PersonAvatar(initials: contact?.initials.nonEmpty ?? PeopleIndex.initials(name: person.name, email: guest.email),
                                 tint: MailText.tint(for: guest.email), badge: .none, size: 28)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: Space.xs) {
                            Text(person.display).font(.rowBody).foregroundStyle(.primary).lineLimit(1)
                            answer
                        }
                        if let company = contact?.company ?? Linker.company(forEmail: guest.email) {
                            Text(company).font(.meta).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("\(guest.email) — cliquer pour ses gestes")
            standing(link, person: person)
        }
        .padding(.vertical, 2)
        .hoverRow(radius: Radius.control, inset: Space.xs)
        .contextMenu { items }
    }

    /// Where the guest stands, said in words.
    @ViewBuilder
    private func standing(_ link: PersonLink, person: MailAddress) -> some View {
        if let project {
            if link == .member {
                // Neutral, the project's color in its dot: an identity never colors a text (lot 8, 19/11).
                Chip("Dans « \(project.name) »", dot: PeopleStyle.color(of: project))
                    .help("Contact lié au projet « \(project.name) »")
            } else {
                // A gesture to make, at the app's accent (design system v2, 19/11).
                Button { add(person) } label: { Label("Ajouter au projet", systemImage: "plus") }
                    .buttonStyle(.hover(.capsule))
                    .font(.meta.weight(.medium))
                    .foregroundStyle(Tint.accent)
                    .help(link == .stranger ? "En faire un contact du projet « \(project.name) »" : "Lier ce contact au projet « \(project.name) »")
            }
        } else if link == .stranger {
            Button { add(person) } label: { Label("Ajouter aux contacts", systemImage: "plus") }
                .buttonStyle(.hover(.capsule))
                .font(.meta.weight(.medium))
                .foregroundStyle(Tint.accent)
        } else {
            Chip("Contact", systemImage: "person.crop.circle.badge.checkmark")
        }
    }

    @ViewBuilder
    private var answer: some View {
        switch guest.response {
        case "declined": Image(systemName: "xmark.circle").font(.meta).foregroundStyle(.secondary).help("A refusé")
        // Accepted: the color of « done » (design system v2, 19/11).
        case "accepted": Image(systemName: "hand.thumbsup.fill").font(.meta).foregroundStyle(Tint.done).help("A accepté l'invitation")
        case "tentative": Image(systemName: "questionmark.circle").font(.meta).foregroundStyle(.secondary).help("Peut-être")
        default: EmptyView()
        }
    }
}

extension String {
    /// `nil` for an empty text.
    var nonEmpty: String? { isEmpty ? nil : self }
}
