import Domain
import Persistence
import ProjectsUI
import PolhubDesign
import SwiftUI

/// Contacts: the people of the calendars and of the vault, their projects, meetings and events (13/11).
struct ContactsView: View {
    @ObservedObject var agenda: AgendaLibrary
    @ObservedObject var router: WindowRouter
    @State private var query = ""

    private var shown: [ContactRow] {
        let query = query.trimmingCharacters(in: .whitespaces)
        let sorted = agenda.contacts.sorted { Self.sortKey($0) < Self.sortKey($1) }
        guard !query.isEmpty else { return sorted }
        return sorted.filter { contact in
            [contact.name, contact.email ?? "", contact.company ?? ""].contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    /// By last name, as the vault's « Annuaire ».
    static func sortKey(_ contact: ContactRow) -> String {
        let words = contact.name.replacing(#/\s*\(.*?\)/#, with: "").split(separator: " ").filter { $0.count > 1 }
        return (words.last.map { String($0) } ?? contact.name).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if agenda.contacts.isEmpty {
                    empty
                } else {
                    List(shown, selection: $router.contactSelection) { contact in
                        HStack(spacing: Space.m) {
                            Avatar(contact.initials, tint: MailText.tint(for: contact.email ?? contact.name))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(contact.name).font(.rowTitle).lineLimit(1)
                                if let company = contact.company { Text(company).font(.meta).foregroundStyle(.secondary).lineLimit(1) }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, Space.xs)
                        // A native list keeps its selection; the row answers the pointer too (15/11).
                        .hoverRow(inset: Space.s)
                        .tag(contact.id)
                    }
                }
            }
            .frame(width: 300)
            Divider()
            if let id = router.contactSelection, let contact = agenda.contacts.first(where: { $0.id == id }) {
                ContactPage(contact: contact, agenda: agenda, router: router).id(id)
            } else {
                ContentUnavailableView("Aucun contact choisi", systemImage: "person.2",
                                       description: Text("\(agenda.contacts.count) contacts, venus de tes agendas et de ton coffre."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .windowTitle("Contacts")
        .searchable(text: $query, placement: .toolbar, prompt: "Chercher un contact")
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Text("Pas encore de contacts.").foregroundStyle(.secondary)
            Text("Ils viennent tout seuls des invités de tes agendas Google.").font(.callout)
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxHeight: .infinity)
    }
}

/// One contact: details, projects (removable, addable), meetings and events.
struct ContactPage: View {
    @State var contact: ContactRow
    @ObservedObject var agenda: AgendaLibrary
    @ObservedObject var router: WindowRouter
    @State private var projects: [ProjectRow] = []
    @State private var meetings: [MeetingRow] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                HStack(spacing: Space.l) {
                    Avatar(contact.initials, size: 56, tint: MailText.tint(for: contact.email ?? contact.name))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.name).font(.title2.bold())
                        if let company = contact.company { Text(company).foregroundStyle(.secondary) }
                    }
                }
                Form {
                    TextField("Nom", text: $contact.name)
                    TextField("Entreprise", text: Binding(get: { contact.company ?? "" }, set: { contact.company = $0.isEmpty ? nil : $0 }))
                    TextField("E-mail", text: Binding(get: { contact.email ?? "" }, set: { contact.email = $0.isEmpty ? nil : $0.lowercased() }))
                    TextField("Téléphone", text: Binding(get: { contact.phone ?? "" }, set: { contact.phone = $0.isEmpty ? nil : $0 }))
                    TextField("Notes", text: $contact.notes, axis: .vertical).lineLimit(2...6)
                }
                .formStyle(.grouped)
                .frame(maxWidth: 560)
                // A grouped form keeps 20 points around its card: the card lines up with the name above.
                .padding(.horizontal, -(Space.l + Space.xs))
                .onSubmit { agenda.save(contact) }
                .onDisappear { agenda.save(contact) }

                VStack(alignment: .leading, spacing: Space.s) {
                    SectionTitle("Projets", count: projects.count)
                    FlowRow(items: projects) { project in
                        HStack(spacing: Space.xs) {
                            ColorDot(ProjectViews.tint(project), size: 8)
                            Text(project.name).font(.meta).lineLimit(1)
                            Button {
                                agenda.remove(contact: contact, from: project.id)
                                reload()
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).frame(width: 20, height: 20)
                            }
                            .buttonStyle(.hover(.circle))
                            .foregroundStyle(.secondary)
                            .help("Retirer de ce projet : le lien ne reviendra pas tout seul.")
                        }
                        .padding(.leading, Space.m).padding(.trailing, Space.xs).padding(.vertical, 3)
                        .background(Surface.fill, in: Capsule())
                    }
                    Menu("Ajouter à un projet") {
                        ForEach(agenda.projects.filter { project in project.status != .termine && !projects.contains { $0.id == project.id } }
                            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { project in
                            Button(project.name) {
                                agenda.add(contact: contact, to: project.id)
                                reload()
                            }
                        }
                    }
                    .fixedSize()
                }

                if !meetings.isEmpty {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        SectionTitle("Réunions", count: meetings.count)
                        ShowMoreList(meetings, limit: 5) { meeting in
                            RowButton(action: { router.open(meetingID: meeting.id, at: nil) }) {
                                dated(meeting.startedAt, meeting.title)
                            }
                        }
                    }
                    .frame(maxWidth: 560, alignment: .leading)
                }
                let events = agenda.events(of: contact)
                if !events.isEmpty {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        SectionTitle("Rendez-vous", count: events.count)
                        // Every one of them behind « Voir les N autres »: never a list cut in silence (correctifs, 15/11).
                        ShowMoreList(events, limit: 5) { event in
                            RowButton(action: { router.openEvent(event.id) }) {
                                dated(event.startAt, event.title)
                            }
                        }
                    }
                    .frame(maxWidth: 560, alignment: .leading)
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: reload)
    }

    /// « 12 nov. 2026, 14:00 » then what it was.
    private func dated(_ date: Date, _ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Text(date.formatted(date: .abbreviated, time: .shortened)).font(.meta.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(title).font(.rowBody).foregroundStyle(.primary).lineLimit(1)
        }
    }

    private func reload() {
        projects = agenda.projects(of: contact)
        meetings = agenda.meetings(of: contact)
    }
}

/// Chips that wrap to the next line.
struct FlowRow<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        if items.isEmpty {
            EmptyLine("Aucun")
        } else {
            FlowLayout(spacing: 6) {
                ForEach(items) { content($0) }
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            line = max(line, size.height)
        }
        return CGSize(width: width, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += line + spacing; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
