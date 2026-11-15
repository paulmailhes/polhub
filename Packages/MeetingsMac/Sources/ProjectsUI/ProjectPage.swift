import AppKit
import Domain
import Persistence
import PolhubDesign
import Summarization
import SwiftUI
import UniformTypeIdentifiers

/// The page of one project (14/11): who and what, the next step, the actions, the journal and the notes; on
/// the side its details, contacts, meetings and coming events. Most of it fills itself (meetings, Claude
/// Code); every field stays editable. Every list shows a few rows, then « Voir les N autres » (15/11).
struct ProjectPage: View {
    let project: ProjectRow
    @ObservedObject var library: ProjectLibrary
    /// Set when the page floats over the board: it closes itself, the window's toolbar stays the board's.
    var close: (() -> Void)?

    @State private var draft: ProjectRow
    @State private var actions: [ActionRow] = []
    @State private var journal: [ProjectJournalRow] = []
    @State private var meetings: [MeetingRow] = []
    /// The first sentence of each meeting's summary.
    @State private var summaries: [UUID: String] = [:]
    @State private var contacts: [ContactRow] = []
    @State private var events: [CalendarEventRow] = []
    @State private var mails: [MailThreadRow] = []
    @State private var newAction = ""
    @State private var newEntryTitle = ""
    @State private var newEntryBody = ""
    @State private var addingEntry = false
    /// The journal entries unfolded to their full text.
    @State private var openEntries: Set<UUID> = []
    @State private var editingNotes = false
    @State private var showingDone = false
    /// The actions Paul added or ticked on this page: they stay in sight past the first five.
    @State private var touchedActions: Set<UUID> = []
    @State private var choosingFolder = false
    /// Two columns when the page is wide enough: decided from its width, not from its texts' (review of 14/11).
    @State private var wide = true
    @Environment(\.projectLogos) private var logos

    init(project: ProjectRow, library: ProjectLibrary, close: (() -> Void)? = nil) {
        self.project = project
        self.library = library
        self.close = close
        _draft = State(initialValue: project)
    }

    static let locale = Locale(identifier: "fr_FR")
    /// The rows of a side card before « Voir les N autres ».
    static let sideRows = 5

    var body: some View {
        Page {
            header
            nextStep
            Group {
                if wide {
                    HStack(alignment: .top, spacing: Space.xl) {
                        main.frame(maxWidth: .infinity)
                        side.frame(width: 320)
                    }
                } else {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        main
                        side
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { wide = $0 >= 760 }
        }
        .overlay(alignment: .topTrailing) {
            if let close { PanelCloseButton(action: close).padding(Space.l) }
        }
        .toolbar {
            if close == nil {
                ToolbarItem(placement: .navigation) {
                    Button { library.selected = nil } label: { Label("Projets", systemImage: "chevron.left") }
                        .help("Revenir aux projets")
                }
            }
        }
        .onAppear(perform: reload)
        .onChange(of: draft) { previous, changed in
            // Only what Paul just changed: a note a session wrote meanwhile stays (review, Important 7).
            if changed != previous { library.save(from: previous, to: changed) }
        }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { draft.codeFolder = url.path(percentEncoded: false) }
        }
    }

    // MARK: - Header

    /// The logo (an image dropped on it wins), the name, the status, the due date, the client (15/11).
    private var header: some View {
        HStack(alignment: .center, spacing: Space.l) {
            if let logos {
                ProjectLogoEditor(project: draft, logos: logos)
            } else {
                ProjectLogo(draft, size: 48)
            }
            VStack(alignment: .leading, spacing: Space.s) {
                TextField("Nom", text: $draft.name)
                    .font(.largeTitle.weight(.bold))
                    .textFieldStyle(.plain)
                HStack(spacing: Space.s) {
                    Menu {
                        ForEach(ProjectStatus.allCases, id: \.self) { status in
                            Button(status.title) { draft.status = status }
                        }
                    } label: {
                        Chip(draft.status.title, systemImage: "circle.fill", tint: ProjectViews.statusColor(draft.status))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.hover(.capsule))
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Changer le statut")
                    if let label = ProjectViews.dueLabel(draft.dueDate, today: Date()) {
                        Chip(label, systemImage: "calendar", tint: label.hasPrefix("En retard") ? .red : label == "Aujourd'hui" ? .orange : nil)
                    }
                    if let client = draft.client, !client.isEmpty { Chip(client, systemImage: "building.2") }
                }
            }
        }
        .padding(.trailing, close == nil ? 0 : 44)
    }

    private var nextStep: some View {
        HStack(spacing: Space.m) {
            Image(systemName: "arrow.forward.circle.fill").font(.title2).foregroundStyle(ProjectViews.tint(draft))
            TextField("La prochaine chose à faire", text: optional(\.todo), axis: .vertical)
                .font(.title3)
                .textFieldStyle(.plain)
        }
        .padding(Space.l)
        .cardSurface(fill: ProjectViews.tint(draft).opacity(0.08))
    }

    // MARK: - Main column

    private var main: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            actionsCard
            journalCard
            Card {
                SectionTitle("Notes", systemImage: "note.text") {
                    TextButton(editingNotes ? "Terminé" : "Modifier") { editingNotes.toggle() }
                }
                if editingNotes {
                    TextEditor(text: $draft.notes).font(.body).frame(minHeight: 200)
                        .overlay(RoundedRectangle(cornerRadius: Radius.small, style: .continuous).stroke(Surface.stroke))
                } else if draft.notes.isEmpty {
                    EmptyLine("Aucune note.")
                } else {
                    MarkdownView(text: draft.notes)
                }
            }
        }
    }

    /// The open actions first, five of them, then « Voir les N autres »; the done ones on request, in their own list
    /// below. An action Paul just added or ticked shows even past the first five (correctifs, 15/11).
    private var actionsCard: some View {
        Card {
            let open = actions.filter { !$0.done }
            let done = actions.filter(\.done)
            SectionTitle("Actions", systemImage: "checklist", count: open.count) {
                if !done.isEmpty {
                    TextButton(showingDone ? "Masquer les faites" : "Voir les faites") {
                        withAnimation(Motion.standard) { showingDone.toggle() }
                    }
                }
            }
            if open.isEmpty { EmptyLine("Aucune action en cours.") }
            ShowMoreList(open, limit: 5, alwaysShown: touchedActions) { action in actionRow(action) }
            if showingDone, !done.isEmpty {
                ShowMoreList(done, limit: 5, alwaysShown: touchedActions) { action in actionRow(action) }
                    .padding(.top, Space.xs)
                    .transition(.opacity)
            }
            TextField("Nouvelle action", text: $newAction)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addAction)
        }
    }

    private func actionRow(_ action: ActionRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Toggle(isOn: Binding(get: { action.done }, set: { done in
                var changed = action
                changed.done = done
                changed.updatedAt = Date()
                try? library.store.saveAction(changed)
                touchedActions.insert(action.id)
                reload()
            })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.text).font(.rowBody).strikethrough(action.done).foregroundStyle(action.done ? .secondary : .primary)
                    let detail = [action.owner, action.meetingID != nil ? "d'une réunion" : nil,
                                  action.addedOn?.formatted(.dateTime.day().month(.abbreviated).locale(Self.locale))].compactMap { $0 }
                    if !detail.isEmpty { Text(detail.joined(separator: " · ")).font(.tag).foregroundStyle(.secondary) }
                }
            }
            .toggleStyle(.checkbox)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .hoverRow(inset: Space.s)
        .contextMenu {
            if let meetingID = action.meetingID {
                Button("Ouvrir la réunion") { library.openMeeting?(meetingID) }
            }
            Button("Supprimer l'action", role: .destructive) {
                try? library.store.deleteAction(id: action.id)
                reload()
            }
        }
    }

    /// The three latest entries, each a title and two plain lines; a click unfolds one (15/11).
    private var journalCard: some View {
        Card {
            SectionTitle("Journal", systemImage: "book.closed", count: journal.count) {
                IconButton(addingEntry ? "xmark" : "plus", help: addingEntry ? "Ne pas ajouter" : "Ajouter au journal", size: 13) {
                    withAnimation(Motion.standard) { addingEntry.toggle() }
                }
            }
            if addingEntry {
                VStack(alignment: .leading, spacing: Space.s) {
                    TextField("Ce qui a été fait aujourd'hui", text: $newEntryTitle).textFieldStyle(.roundedBorder)
                    TextEditor(text: $newEntryBody).font(.body).frame(minHeight: 70)
                        .overlay(RoundedRectangle(cornerRadius: Radius.small, style: .continuous).stroke(Surface.stroke))
                    Button("Ajouter au journal", action: addEntry).buttonStyle(.glass)
                        .disabled(newEntryTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .transition(.opacity)
            }
            if journal.isEmpty && !addingEntry { EmptyLine("Rien encore : les sessions de Claude Code y écrivent ce qu'elles font.") }
            ShowMoreList(journal, limit: 3) { entry in journalRow(entry) }
        }
    }

    private func journalRow(_ entry: ProjectJournalRow) -> some View {
        let open = openEntries.contains(entry.id)
        return VStack(alignment: .leading, spacing: Space.xs) {
            Button {
                guard !entry.body.isEmpty else { return }
                withAnimation(Motion.standard) {
                    if open { openEntries.remove(entry.id) } else { openEntries.insert(entry.id) }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text(entry.date.formatted(.dateTime.day().month(.abbreviated).locale(Self.locale)))
                            .font(.meta.monospacedDigit()).foregroundStyle(.secondary).frame(width: 58, alignment: .leading)
                        Text(entry.title).font(.rowTitle.weight(.semibold)).foregroundStyle(.primary).lineLimit(open ? nil : 1)
                        Spacer(minLength: 0)
                        if !entry.body.isEmpty {
                            Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(open ? 180 : 0))
                        }
                    }
                    if !open, !entry.body.isEmpty {
                        Text(ProjectViews.excerpt(entry.body)).font(.rowBody).foregroundStyle(.secondary).lineLimit(2)
                            .multilineTextAlignment(.leading).padding(.leading, 66)
                    }
                }
                .padding(.vertical, Space.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.row(inset: Space.s))
            if open {
                MarkdownView(text: entry.body).font(.rowBody).padding(.leading, 66).padding(.bottom, Space.xs)
                    .transition(.opacity)
            }
        }
    }

    private func addAction() {
        let text = newAction.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let position = (actions.map(\.position).max() ?? -1) + 1
        let action = ActionRow(projectID: project.id, text: text, addedOn: Date(), position: position, createdAt: Date())
        try? library.store.saveAction(action)
        touchedActions.insert(action.id)
        newAction = ""
        reload()
    }

    private func addEntry() {
        let title = newEntryTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        try? library.store.addJournal(ProjectJournalRow(projectID: project.id, date: Date(), title: title, body: newEntryBody, createdAt: Date()))
        newEntryTitle = ""
        newEntryBody = ""
        withAnimation(Motion.standard) { addingEntry = false }
        reload()
    }

    // MARK: - Side column

    private var side: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Card {
                SectionTitle("Infos", systemImage: "info.circle")
                LabeledContent("Client") {
                    TextField("", text: optional(\.client), prompt: Text("—")).multilineTextAlignment(.trailing).textFieldStyle(.plain)
                }
                LabeledContent("Échéance") {
                    HStack(spacing: Space.xs) {
                        if draft.dueDate != nil {
                            DatePicker("", selection: Binding(get: { draft.dueDate ?? Date() }, set: { draft.dueDate = $0 }), displayedComponents: .date)
                                .labelsHidden()
                            IconButton("xmark.circle.fill", help: "Sans échéance", size: 13) { draft.dueDate = nil }
                        } else {
                            TextButton("Ajouter") { draft.dueDate = Date() }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if let logos { SiteField(projectID: project.id, logos: logos) }
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Couleur").foregroundStyle(.secondary)
                    ColorChoices(selection: optional(\.color))
                }
                LabeledContent("Dossier") {
                    TextButton(draft.codeFolder.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Choisir…") { choosingFolder = true }
                        .help(draft.codeFolder ?? "Le dossier de code, pour que Claude Code reconnaisse le projet")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if let github = draft.github.flatMap(URL.init(string:)) { Link("GitHub", destination: github) }
                if let notion = draft.notion.flatMap(URL.init(string:)) { Link("Notion", destination: notion) }
            }
            Card {
                SectionTitle("Contacts", systemImage: "person.2", count: contacts.count)
                if contacts.isEmpty { EmptyLine("Les invités de ses rendez-vous arrivent ici tout seuls.") }
                ShowMoreList(contacts, limit: Self.sideRows) { contact in
                    RowButton(action: { library.openContact?(contact.id) }) {
                        HStack(spacing: Space.s) {
                            Avatar(contact.initials, size: 28)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(contact.name).font(.rowBody).foregroundStyle(.primary).lineLimit(1)
                                if let company = contact.company { Text(company).font(.meta).foregroundStyle(.secondary).lineLimit(1) }
                            }
                        }
                    }
                }
            }
            Card {
                SectionTitle("Réunions", systemImage: "waveform", count: meetings.count)
                if meetings.isEmpty { EmptyLine("Ses réunions enregistrées arrivent ici toutes seules.") }
                ShowMoreList(meetings, limit: Self.sideRows) { meeting in
                    RowButton(action: { library.openMeeting?(meeting.id) }) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(meeting.title).font(.rowBody.weight(.medium)).lineLimit(1).foregroundStyle(.primary)
                            Text(meeting.startedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Self.locale)))
                                .font(.meta).foregroundStyle(.secondary)
                            if let line = summaries[meeting.id] {
                                Text(line).font(.meta).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
            }
            if !mails.isEmpty {
                Card {
                    SectionTitle("Mails", systemImage: "envelope", count: mails.count)
                    ShowMoreList(mails, limit: Self.sideRows) { thread in
                        RowButton(action: { library.openMail?(thread.id) }) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(thread.subject).font(.rowBody).fontWeight(thread.unread ? .semibold : .regular).lineLimit(1)
                                    .foregroundStyle(.primary)
                                Text("\(thread.senders.last { $0.email.lowercased() == thread.lastSender }?.display ?? thread.lastSender ?? "Moi") · "
                                     + thread.lastMessageAt.formatted(.dateTime.day().month(.abbreviated).locale(Self.locale)))
                                    .font(.meta).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
            if !events.isEmpty {
                Card {
                    SectionTitle("Prochains rendez-vous", systemImage: "calendar", count: events.count)
                    ShowMoreList(events, limit: Self.sideRows) { event in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title).font(.rowBody).lineLimit(1)
                            Text(event.startAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute().locale(Self.locale)))
                                .font(.meta).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, Space.xs)
                    }
                }
            }
        }
    }

    /// A text field on an optional property: empty means none.
    private func optional(_ keyPath: WritableKeyPath<ProjectRow, String?>) -> Binding<String> {
        Binding(get: { draft[keyPath: keyPath] ?? "" }, set: { draft[keyPath: keyPath] = $0.isEmpty ? nil : $0 })
    }

    private func reload() {
        actions = (try? library.store.actions(projectID: project.id)) ?? []
        journal = (try? library.store.journal(projectID: project.id)) ?? []
        meetings = (try? library.store.meetings(projectID: project.id)) ?? []
        summaries = meetings.reduce(into: [:]) { lines, meeting in
            lines[meeting.id] = ((try? library.meetings.summary(meetingID: meeting.id)) ?? nil).flatMap { SummaryText.overview($0) }
        }
        contacts = (try? ContactStore(library.store.database).contacts(projectID: project.id)) ?? []
        mails = (try? MailStore(library.store.database).threads(filedIn: project.id)) ?? []
        events = ((try? CalendarStore(library.store.database).events(projectID: project.id)) ?? [])
            .filter { $0.endAt > Date() }
            .reduce(into: [CalendarEventRow]()) { seen, event in if !seen.contains(where: { $0.eventID == event.eventID }) { seen.append(event) } }
    }
}

/// The logo of the page's header, 48 points: an image dropped on it becomes the project's logo; a click offers
/// to choose one, to take it back, to ask the site again (15/11).
struct ProjectLogoEditor: View {
    let project: ProjectRow
    @ObservedObject var logos: ProjectLogos
    @State private var targeted = false
    @State private var choosing = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 48 * 0.22 + 4, style: .continuous)
        Menu {
            Button("Choisir une image…") { choosing = true }
            if logos.hasOwnImage(project.id) {
                Button("Retirer l'image") { logos.removeImage(for: project.id) }
            }
            if let site = logos.site(for: project.id) {
                Divider()
                if !logos.hasOwnImage(project.id) {
                    Button("Rafraîchir le logo") { logos.refresh(project) }
                }
                if let url = URL(string: "https://\(site.domain)/") {
                    Button("Ouvrir \(site.domain)") { NSWorkspace.shared.open(url) }
                }
            }
        } label: {
            ProjectLogo(project, size: 48).padding(4)
        }
        .menuStyle(.button)
        .buttonStyle(.hover(.rounded))
        .menuIndicator(.hidden)
        .fixedSize()
        .overlay {
            shape.strokeBorder(Color.accentColor, lineWidth: 2).opacity(targeted ? 1 : 0)
        }
        .animation(Motion.quick, value: targeted)
        // A file only, read away from the main thread: a web address from a browser is refused (correctifs, 15/11).
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, url.isFileURL else { return false }
            Task { await logos.setImage(from: url, for: project.id) }
            return true
        } isTargeted: { targeted = $0 }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { Task { await logos.setImage(from: url, for: project.id) } }
        }
        .help("Le logo du projet : glisse une image dessus, ou clique pour en choisir une")
    }
}

/// « Site : atelier-exemple.fr (deviné) », « Changer », and the cross that gives it back to the guess (15/11).
struct SiteField: View {
    let projectID: UUID
    @ObservedObject var logos: ProjectLogos
    @State private var editing = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let site = logos.site(for: projectID)
        let chosen = logos.entries[projectID].map { $0.source != .guessed } ?? false
        LabeledContent("Site") {
            if editing {
                TextField("", text: $text, prompt: Text(site?.domain ?? "exemple.fr"))
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(save)
                    .onExitCommand { editing = false }
                    .onChange(of: focused) { _, now in if !now { save() } }
            } else {
                HStack(spacing: Space.xs) {
                    if let site {
                        Text(site.domain).lineLimit(1).truncationMode(.middle)
                        if site.guessed { Text("(deviné)").foregroundStyle(.secondary) }
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                    TextButton(site == nil ? "Ajouter" : "Changer") {
                        // The site shown, guessed or not: Entrée keeps it, erasing it says « no site » (correctifs, 15/11).
                        text = site?.domain ?? ""
                        editing = true
                        focused = true
                    }
                    .padding(.leading, Space.xs)
                    if chosen, logos.entries[projectID]?.site != nil || logos.entries[projectID]?.source == .chosen {
                        IconButton("xmark.circle.fill", help: "Revenir au site deviné d'après ses contacts", size: 13) {
                            logos.clearSite(for: projectID)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .help("Le site du client : Polhub y prend son logo. Deviné d'après l'adresse de ses contacts, tant que tu n'en choisis pas un.")
    }

    private func save() {
        guard editing else { return }
        editing = false
        logos.setSite(text, for: projectID)
    }
}
