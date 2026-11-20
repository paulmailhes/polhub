import Domain
import Persistence
import ProjectsUI
import PolhubDesign
import Summarization
import SwiftUI

/// Contacts (15/11): the people of the calendars, the mails and the old vault, those Paul crossed lately first. Paul
/// rarely comes on purpose: he lands from a mail or a meeting, and the page says in a glance who the person is,
/// their projects, and the mails, meetings and events with them.
struct ContactsView: View {
    @ObservedObject var agenda: AgendaLibrary
    @ObservedObject var router: WindowRouter
    @State private var query = ""
    /// The last mail of each address and the last meeting of each contact, read away from the main thread.
    @State private var lastMails: [String: Date] = [:]
    @State private var lastMeetings: [UUID: Date] = [:]

    /// As the meetings' list (13/11).
    static let listWidth: CGFloat = 300
    /// No one chosen: what to do (lot 8, 19/11). It counted « N contacts, venus de tes agendas, de tes mails et de l'ancien
    /// coffre », a vault gone on 16/11.
    static let noneChosen = (title: "Aucun contact choisi", text: "Choisis un contact dans la liste.")

    var body: some View {
        let now = Date()
        let projects = ContactsModel.projects(links: agenda.linkIndex, projects: agenda.projects)
        let last = lastContacts(now: now)
        let sections = visibleSections(projects: projects, last: last, now: now)
        HStack(spacing: 0) {
            list(sections, projects: projects, last: last, now: now)
                .frame(width: Self.listWidth)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The sidebar's word; never the name the page writes large (lot 4, 19/11).
        .windowTitle("Contacts")
        // « Chercher » and what is found, as every page says it (lot 10, 20/11); the fields searched are said when
        // nothing answers.
        .searchable(text: $query, placement: .toolbar, prompt: "Chercher un contact")
        .task(id: agenda.contacts.map(\.email)) { await loadActivity() }
        .onAppear { openFirst(sections) }
        .onChange(of: agenda.contacts.isEmpty) { _, _ in openFirst(visibleSections(projects: projects, last: last, now: now)) }
    }

    private var selected: ContactRow? {
        router.contactSelection.flatMap { id in agenda.contacts.first { $0.id == id } }
    }

    private func visibleSections(projects: [UUID: [ProjectRow]], last: [UUID: LastContact], now: Date) -> [ContactsModel.Section] {
        let shown = agenda.contacts.filter { ContactsModel.matches($0, projects: (projects[$0.id] ?? []).map(\.name), query: query) }
        return ContactsModel.sections(shown, last: last, now: now)
    }

    /// The last mail, meeting or event with each contact.
    private func lastContacts(now: Date) -> [UUID: LastContact] {
        let events = ContactsModel.lastEvents(agenda.shown, now: now)
        var result: [UUID: LastContact] = [:]
        for contact in agenda.contacts {
            let email = contact.email ?? ""
            result[contact.id] = ContactsModel.last(mail: lastMails[email], meeting: lastMeetings[contact.id], event: events[email])
        }
        return result
    }

    private func loadActivity() async {
        let database = agenda.database
        let emails = Set(agenda.contacts.compactMap(\.email))
        let found = await Task.detached(priority: .userInitiated) {
            ((try? MailStore(database).lastExchanges(with: emails)) ?? [:], (try? ContactStore(database).lastMeetings()) ?? [:])
        }.value
        lastMails = found.0
        lastMeetings = found.1
    }

    /// Nothing chosen, or a contact gone: the first of the list opens, as the newest meeting does (13/11).
    private func openFirst(_ sections: [ContactsModel.Section]) {
        guard selected == nil, let first = sections.first?.contacts.first else { return }
        router.contactSelection = first.id
    }

    // MARK: - The list

    @ViewBuilder
    private func list(_ sections: [ContactsModel.Section], projects: [UUID: [ProjectRow]], last: [UUID: LastContact], now: Date) -> some View {
        if agenda.contacts.isEmpty {
            // An empty page: « Aucun … », then how it fills, in fifteen words at most (lot 10, 20/11).
            ContentUnavailableView {
                Label("Aucun contact", systemImage: "person.2")
            } description: {
                Text("Ils arrivent seuls de tes agendas, et d'un clic depuis un mail ou un rendez-vous.")
            }
        } else if sections.isEmpty {
            // Polhub's words, no longer the system's (« vous ») (lot 10, 20/11): what was searched, what is searched in, and
            // the gesture that empties the search. The typography laid around what Paul typed, never inside it.
            ContentUnavailableView {
                Label(Words.typeset("Aucun résultat pour « ") + query + Words.typeset(" »"), systemImage: "magnifyingglass")
            } description: {
                Text("La recherche porte sur le nom, l'adresse, l'entreprise et les projets.")
            } actions: {
                // No glass in the content: a secondary action (design system v2, 19/11).
                Button("Effacer la recherche") { query = "" }
                    .buttonStyle(.secondary)
            }
        } else {
            List(selection: $router.contactSelection) {
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.contacts) { contact in
                            ContactListRow(contact: contact, projects: projects[contact.id] ?? [], last: last[contact.id], now: now)
                                .tag(contact.id)
                                .contextMenu { menu(contact) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func menu(_ contact: ContactRow) -> some View {
        if let email = contact.email, !email.isEmpty {
            if let mails = agenda.mails {
                Button("Écrire", systemImage: "square.and.pencil") { mails.write(to: MailAddress(name: contact.name, email: email), router: router) }
            }
            Button("Copier l'adresse", systemImage: "doc.on.doc") { MailLibrary.copy(email) }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let contact = selected {
            ContactPage(contact: contact, agenda: agenda, router: router).id(contact.id)
        } else if !agenda.contacts.isEmpty {
            ContentUnavailableView(Self.noneChosen.title, systemImage: "person.2", description: Text(Self.noneChosen.text))
        }
    }
}

/// One contact in the list: the avatar in the person's color, the name, the company, the projects in their colors;
/// at the end, when Paul and they last crossed, and how.
struct ContactListRow: View {
    let contact: ContactRow
    let projects: [ProjectRow]
    let last: LastContact?
    let now: Date

    /// The projects shown on the row; the others are « +N ».
    static let chips = 2

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Avatar(ContactsModel.initials(contact), size: 36, tint: ContactsModel.tint(contact))
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(contact.name).font(.rowTitle.weight(.medium)).lineLimit(1)
                    Spacer(minLength: 0)
                    if let last {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Image(systemName: last.kind.symbol).font(.system(size: 10, weight: .medium))
                            Text(ContactsModel.when(last.date, now: now)).font(.meta.monospacedDigit())
                        }
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .help(ContactsModel.lastText(last, now: now))
                    }
                }
                if let detail = ContactsModel.detail(contact) {
                    Text(detail).font(.meta).foregroundStyle(.secondary).lineLimit(1)
                }
                if !projects.isEmpty {
                    HStack(spacing: Space.xs) {
                        ForEach(projects.prefix(Self.chips)) { project in
                            // Neutral, the project's color in its dot: an identity never colors a text (lot 8, 19/11).
                            Chip(project.name, dot: ProjectViews.tint(project))
                        }
                        if projects.count > Self.chips {
                            Chip("+" + Words.number(projects.count - Self.chips)).fixedSize()
                                .help(projects.dropFirst(Self.chips).map(\.name).joined(separator: ", "))
                        }
                    }
                    .padding(.top, 3)
                }
            }
        }
        .padding(.vertical, Space.xs + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A native list keeps its selection; the row answers the pointer too (15/11).
        .hoverRow(inset: Space.s)
    }
}

// MARK: - A contact's page

/// One contact (15/11): who, their projects (added and removed in place), the mails, the events and the meetings
/// with them, their details and notes, always editable. Every list says how many, then « Voir les N autres ».
struct ContactPage: View {
    @ObservedObject var agenda: AgendaLibrary
    @ObservedObject var router: WindowRouter
    /// What Paul types; `saved` is what the base holds.
    @State private var contact: ContactRow
    @State private var saved: ContactRow
    @State private var meetings: [MeetingRow] = []
    /// The first sentence of each meeting's summary.
    @State private var summaries: [UUID: String] = [:]
    @State private var mails: [MailThreadRow] = []
    @State private var saving: Task<Void, Never>?
    /// Why the address typed was not kept (audit of 19/11): the base holds one contact per address.
    @State private var addressRefused: String?
    @State private var copied = false
    /// The width of the page's content: two columns when wide enough (as a project's page), the header's buttons
    /// under the name when narrow.
    @State private var width: CGFloat = 700

    init(contact: ContactRow, agenda: AgendaLibrary, router: WindowRouter) {
        self.agenda = agenda
        self.router = router
        _contact = State(initialValue: contact)
        _saved = State(initialValue: contact)
    }

    /// The rows of a card before « Voir les N autres ».
    static let rows = 5
    /// The side column, in two columns.
    static let sideWidth: CGFloat = 300
    /// From this width of content, two columns.
    static let twoColumns: CGFloat = 820
    /// Under this width, the header's buttons go under the name.
    static let narrow: CGFloat = 560

    private var email: String? { saved.email.flatMap { $0.isEmpty ? nil : $0 } }
    private var person: MailAddress? { email.map { MailAddress(name: saved.name, email: $0) } }
    private var projects: [ProjectRow] { ContactsModel.projects(of: saved.id, links: agenda.linkIndex, projects: agenda.projects) }
    private var firstName: String { saved.name.split(separator: " ").first.map(String.init) ?? saved.name }

    var body: some View {
        let now = Date()
        let events = ContactsModel.events(agenda.shown, of: email, now: now)
        Page {
            header(now: now, events: events)
            Group {
                // Sixteen points between two cards, as everywhere (lot 8, 19/11).
                if width >= Self.twoColumns {
                    HStack(alignment: .top, spacing: Space.xl) {
                        VStack(alignment: .leading, spacing: PageMetrics.cardGap) {
                            mailsCard
                            eventsCard(events, now: now)
                            meetingsCard(now: now)
                        }
                        .frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: PageMetrics.cardGap) {
                            projectsCard
                            detailsCard
                            notesCard
                        }
                        .frame(width: Self.sideWidth)
                    }
                } else {
                    VStack(alignment: .leading, spacing: PageMetrics.cardGap) {
                        projectsCard
                        mailsCard
                        eventsCard(events, now: now)
                        meetingsCard(now: now)
                        detailsCard
                        notesCard
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }
        .onAppear(perform: reload)
        .onChange(of: contact) { _, _ in scheduleSave() }
        .onDisappear(perform: save)
    }

    // MARK: Header

    /// The avatar, the name (editable), the company and the address; when Paul and they last crossed, and the
    /// next event; « Écrire » and the address to copy.
    private func header(now: Date, events: (coming: [CalendarEventRow], past: [CalendarEventRow])) -> some View {
        let narrow = width < Self.narrow
        return VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .center, spacing: Space.l) {
                Avatar(ContactsModel.initials(saved), size: narrow ? 56 : 72, tint: ContactsModel.tint(saved))
                VStack(alignment: .leading, spacing: Space.xs) {
                    // The large title of an object open, 26 points, as a project's and a meeting's (lot 8, 19/11); whole in
                    // its height, never cut by the row (lot 3's review: cut in the dark).
                    TextField("Nom", text: $contact.name)
                        .font(.largeTitle.weight(.bold))
                        .textFieldStyle(.plain)
                        .fixedSize(horizontal: false, vertical: true)
                        .onSubmit(save)
                    let line = [saved.company, email].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                    if !line.isEmpty {
                        Text(line).font(.rowBody).foregroundStyle(.secondary).lineLimit(narrow ? 2 : 1).textSelection(.enabled)
                    }
                    if !narrow { glance(now: now, events: events).padding(.top, Space.xs) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !narrow { actions }
            }
            if narrow {
                glance(now: now, events: events)
                actions
            }
        }
    }

    /// Two chips: the last time Paul and they crossed, the next event; a click opens it.
    @ViewBuilder
    private func glance(now: Date, events: (coming: [CalendarEventRow], past: [CalendarEventRow])) -> some View {
        let pastEvent = events.past.first { event in event.attendees.first { $0.email == email }?.response != "declined" }
        let last = ContactsModel.last(mail: mails.first?.lastMessageAt, meeting: meetings.first?.startedAt, event: pastEvent?.startAt)
        let next = events.coming.first
        if last != nil || next != nil {
            // The chips go to the next line rather than shorten.
            FlowLayout(spacing: Space.s) {
                if let last {
                    Button {
                        switch last.kind {
                        case .mail: if let thread = mails.first { router.openMail(thread.id) }
                        case .meeting: if let meeting = meetings.first { router.open(meetingID: meeting.id, at: nil) }
                        case .event: if let pastEvent { router.openEvent(pastEvent.id) }
                        }
                    } label: {
                        Chip(ContactsModel.lastText(last, now: now), systemImage: last.kind.symbol)
                    }
                    .buttonStyle(.hover(.capsule))
                    .help(last.kind == .mail ? "Ouvrir le fil" : last.kind == .meeting ? "Ouvrir la réunion" : "Ouvrir le rendez-vous")
                }
                if let next {
                    Button { router.openEvent(next.id) } label: {
                        // Neutral, as the chip beside it: an account's color on a button goes (design system v2, 19/11); it
                        // read as a state, a red account as an alert. The account's dot stays on the event's row.
                        Chip(ContactsModel.nextText(next, now: now), systemImage: "calendar")
                    }
                    .buttonStyle(.hover(.capsule))
                    .help(next.title)
                }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if let person {
            HStack(spacing: Space.s) {
                if let mails = agenda.mails {
                    Button { mails.write(to: person, router: router) } label: {
                        Label("Écrire", systemImage: "square.and.pencil")
                    }
                    // The page's principal action; no glass in the content (design system v2, 19/11).
                    .buttonStyle(.primary)
                    .controlSize(.large)
                    // A verb and its object (lot 10, 20/11).
                    .help("Écrire à \(person.email)")
                }
                Button {
                    MailLibrary.copy(person.email)
                    withAnimation(Motion.quick) { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        withAnimation(Motion.quick) { copied = false }
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 18)
                }
                // A secondary action beside the principal one: a thin outline, no glass (design system v2, 19/11).
                .buttonStyle(.secondary)
                .controlSize(.large)
                .help(copied ? "Adresse copiée" : "Copier l'adresse")
                .accessibilityLabel("Copier l'adresse")
            }
            .fixedSize()
        }
    }

    // MARK: Cards

    /// The projects in their colors: a click opens one, « × » takes the contact out of it (it stays out), « Ajouter »
    /// puts them in another.
    private var projectsCard: some View {
        Card {
            SectionTitle("Projets", systemImage: "square.grid.3x2", count: projects.count) { addProject }
            if projects.isEmpty {
                EmptyLine("Dans aucun projet.")
            } else {
                FlowLayout(spacing: Space.s) {
                    ForEach(projects) { project in
                        ContactProjectChip(project: project, open: { router.openProject(project.id) },
                                           remove: { withAnimation(Motion.standard) { agenda.remove(contact: saved, from: project.id) } })
                    }
                }
                .animation(Motion.standard, value: projects.map(\.id))
            }
        }
    }

    private var addProject: some View {
        let available = agenda.projects.filter { project in project.status != .termine && !projects.contains { $0.id == project.id } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return Menu {
            ForEach(available) { project in
                Button(project.name) { withAnimation(Motion.standard) { agenda.add(contact: saved, to: project.id) } }
            }
        } label: {
            Label("Ajouter", systemImage: "plus")
                .font(.meta.weight(.medium))
                // A gesture to make, as `TextButton`: the accent, ink (design system v2, 19/11).
                .foregroundStyle(Tint.accent)
                .padding(.horizontal, Space.s).padding(.vertical, 3)
        }
        .menuStyle(.button)
        .buttonStyle(.hover(.capsule))
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.trailing, -Space.s)
        .disabled(available.isEmpty)
        .help(available.isEmpty ? "Déjà dans tous les projets en cours" : "Ajouter à un projet")
    }

    /// The threads they took part in, the most recent first; a click opens the thread in Mails. Only with the mails.
    @ViewBuilder
    private var mailsCard: some View {
        if agenda.mails != nil {
            Card {
                SectionTitle("Mails", systemImage: "envelope", count: mails.count)
                if mails.isEmpty { EmptyLine(email == nil ? "Pas d'adresse : aucun mail à montrer." : "Aucun mail échangé.") }
                ShowMoreList(mails, limit: Self.rows) { thread in
                    RowButton(action: { router.openMail(thread.id) }) {
                        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                                    Text(thread.subject).font(.rowBody.weight(thread.unread ? .semibold : .medium)).foregroundStyle(.primary).lineLimit(1)
                                    if thread.messageCount > 1 {
                                        Text(Words.number(thread.messageCount)).font(.meta.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                }
                                if !thread.snippet.isEmpty {
                                    Text(thread.snippet).font(.meta).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: Space.s)
                            Text(MailText.date(thread.lastMessageAt)).font(.meta.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    /// The events to come first, then the past ones; a click opens the event in Calendrier.
    private func eventsCard(_ events: (coming: [CalendarEventRow], past: [CalendarEventRow]), now: Date) -> some View {
        let all = events.coming + events.past
        return Card {
            SectionTitle("Rendez-vous", systemImage: "calendar", count: all.count)
            if all.isEmpty { EmptyLine(email == nil ? "Pas d'adresse : aucun rendez-vous à montrer." : "Aucun rendez-vous.") }
            ShowMoreList(all, limit: Self.rows) { event in
                let coming = event.endAt > now
                RowButton(action: { router.openEvent(event.id) }) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                        ColorDot(agenda.color(for: event.account), size: 8).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title).font(.rowBody.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                            Text(ContactsModel.eventWhen(event, now: now)).font(.meta.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: Space.s)
                        // Neutral: the account's color stays in its dot, at the start of the row; on a chip it read as
                        // a state (design system v2, 19/11).
                        if coming { Chip(event.startAt <= now ? "En cours" : "À venir") }
                    }
                }
            }
        }
    }

    /// The recorded meetings they took part in, each with the first sentence of its summary; a click opens it.
    private func meetingsCard(now: Date) -> some View {
        Card {
            SectionTitle("Réunions", systemImage: "waveform", count: meetings.count)
            if meetings.isEmpty { EmptyLine("Aucune réunion enregistrée.") }
            ShowMoreList(meetings, limit: Self.rows) { meeting in
                RowButton(action: { router.open(meetingID: meeting.id, at: nil) }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meeting.title).font(.rowBody.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                        Text(ContactsModel.meetingWhen(meeting, now: now)).font(.meta.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                        if let line = summaries[meeting.id] {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                // A mark that informs, nothing to click: grey (design system v2, 19/11).
                                Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                                Text(line).font(.meta).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
    }

    /// The company, the address and the phone, written in place.
    private var detailsCard: some View {
        Card {
            SectionTitle("Coordonnées", systemImage: "person.text.rectangle")
            field("Entreprise", text: optional(\.company))
            // « Adresse », as everywhere else, never « E-mail » (lot 10, 20/11).
            field("Adresse", text: Binding(get: { contact.email ?? "" }, set: {
                contact.email = $0.isEmpty ? nil : $0.lowercased()
                addressRefused = nil
            }))
            if let addressRefused {
                // A problem in one line: the icon of attention, the sentence in the text's color (design system v2, 19/11).
                ErrorLine(addressRefused).font(.meta).frame(maxWidth: .infinity, alignment: .trailing)
            }
            field("Téléphone", text: optional(\.phone))
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        LabeledContent {
            TextField(title, text: text, prompt: Text("—"))
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
                .onSubmit(save)
        } label: {
            Text(title).foregroundStyle(.secondary)
        }
        .font(.rowBody)
    }

    private var notesCard: some View {
        Card {
            SectionTitle("Notes", systemImage: "note.text")
            TextField("Ce qu'il faut savoir de \(firstName)", text: $contact.notes, axis: .vertical)
                .font(.rowBody)
                .textFieldStyle(.plain)
                .lineLimit(2...12)
        }
    }

    // MARK: Data

    private func optional(_ keyPath: WritableKeyPath<ContactRow, String?>) -> Binding<String> {
        Binding(get: { contact[keyPath: keyPath] ?? "" }, set: { contact[keyPath: keyPath] = $0.isEmpty ? nil : $0 })
    }

    /// What Paul types is kept a moment after he stops, and when he leaves the page.
    private func scheduleSave() {
        saving?.cancel()
        saving = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func save() {
        saving?.cancel()
        var clean = contact
        clean.name = clean.name.trimmingCharacters(in: .whitespaces)
        // A name left empty keeps the one before: a contact always has one.
        if clean.name.isEmpty { clean.name = saved.name }
        guard clean != saved else { return }
        let addressChanged = clean.email != saved.email
        do {
            try agenda.save(clean)
        } catch {
            // Nothing the base refused is taken as saved (audit of 19/11): the address goes back to the one it holds, the
            // rest is saved at the next pass, and the page says why.
            if addressChanged {
                let owner = clean.email.flatMap { agenda.contact(email: $0) }.flatMap { $0.id == clean.id ? nil : $0 }
                if let owner {
                    addressRefused = "Cette adresse est déjà celle de « \(owner.name) »."
                } else {
                    // What failed, why when Polhub knows it, what to do; the system's text to the journal (lot 10, 20/11).
                    let problem = Words.problem("Cette adresse n'a pas pu être enregistrée", error)
                    addressRefused = problem.sentence
                    agenda.database.journal(problem)
                }
                contact.email = saved.email
            }
            return
        }
        saved = clean
        if addressChanged { reload() }
    }

    private func reload() {
        meetings = agenda.meetings(of: saved)
        let store = MeetingStore(agenda.database)
        summaries = meetings.reduce(into: [:]) { lines, meeting in
            lines[meeting.id] = ((try? store.summary(meetingID: meeting.id)) ?? nil).flatMap { SummaryText.overview($0) }
        }
        guard agenda.mails != nil, let email else {
            mails = []
            return
        }
        let database = agenda.database
        Task {
            let found = await Task.detached(priority: .userInitiated) { (try? MailStore(database).threads(with: email)) ?? [] }.value
            mails = found
        }
    }
}

/// A project on a contact's page: its dot in its color, its name in the text's (lot 8, 19/11: an identity never colors a
/// text); a click opens it, « × » takes the contact out of it.
struct ContactProjectChip: View {
    let project: ProjectRow
    let open: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: open) {
                HStack(spacing: 6) {
                    ColorDot(ProjectViews.tint(project), size: 8)
                    Text(project.name).font(.meta.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                }
                .padding(.leading, Space.m - 2).padding(.trailing, Space.xs).padding(.vertical, 5)
            }
            .buttonStyle(.hover(.capsule))
            .help("Ouvrir « \(project.name) »")
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 22, height: 22)
            }
            .buttonStyle(.hover(.circle))
            .foregroundStyle(.secondary)
            .padding(.trailing, 3)
            // A verb and its object, without a period; the same words for VoiceOver (lot 10, 20/11).
            .help("Retirer de « \(project.name) »")
            .accessibilityLabel("Retirer de « \(project.name) »")
        }
        .background(Surface.fill, in: Capsule())
        .overlay(Capsule().strokeBorder(Surface.stroke))
        .fixedSize()
    }
}

/// Chips that wrap to the next line.
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
