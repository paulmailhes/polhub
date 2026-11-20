import AppKit
import Domain
import Persistence
import HubDesign
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
    /// The copy the base just gave the page (`onChange(of: project)`): not to be written back as Paul's change.
    @State private var reported: ProjectRow?
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
    @FocusState private var notesFocused: Bool
    @State private var confirmingDelete = false
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
                    // Sixteen points between two cards, as everywhere (lot 8, 19/11).
                    VStack(alignment: .leading, spacing: PageMetrics.cardGap) {
                        main
                        side
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { wide = $0 >= 760 }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: Space.s) {
                projectMenu
                if let close { PanelCloseButton(action: close) }
            }
            .padding(Space.l)
        }
        .confirmationDialog("Supprimer « \(draft.name) » ?", isPresented: $confirmingDelete) {
            Button("Supprimer le projet", role: .destructive) { library.trash(draft.id); close?() }
        } message: {
            // « kanban » in a sentence, « Kanban » only as the tab's title (lot 10, 20/11).
            Text("Le projet quitte le kanban et les listes. Ses réunions, ses mails et ses contacts restent.")
        }
        .toolbar {
            if close == nil {
                ToolbarItem(placement: .navigation) {
                    // Back where the project was opened from, the Accueil included (lot 4, 19/11); the bubble by `Words`
                    // (lot 10, 20/11).
                    Button { library.closePage() } label: { Label("Projets", systemImage: "chevron.left") }
                        .help(library.returnHelp?() ?? Words.help("Revenir à Projets", .escape))
                }
            }
        }
        // Échap goes back too, as from a page floating (lot 4, 19/11).
        .onExitCommand(perform: close == nil ? { library.closePage() } : nil)
        .onAppear(perform: reload)
        .onChange(of: project) { old, new in
            // A session changed the project meanwhile (`projet`, 16/11): what Paul is not changing shows at once, and
            // his next keystroke no longer writes the old notes over the new ones (review of 16/11).
            let shown = ProjectViews.reported(from: old, to: new, onto: draft)
            if shown != draft {
                reported = shown
                draft = shown
            }
            contacts = (try? ContactStore(library.store.database).contacts(projectID: project.id)) ?? []
            journal = (try? library.store.journal(projectID: project.id)) ?? []
        }
        .onChange(of: draft) { previous, changed in
            // What the base just said is no change of Paul's: nothing to write back.
            let fromBase = changed == reported
            reported = nil
            if fromBase { return }
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
                        // Neutral with its dot, « Terminé » in the color of what is done (lot 8, 19/11).
                        StatusChip(status: draft.status)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.hover(.capsule))
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Changer le statut")
                    // The color from the days left, never from the words (lot 10, 20/11).
                    if let due = ProjectViews.dueState(draft.dueDate, today: Date()) {
                        Chip(due.label, systemImage: "calendar", tint: due.role?.color)
                    }
                    if let client = draft.client, !client.isEmpty { Chip(client, systemImage: "building.2") }
                }
            }
        }
        .padding(.trailing, close == nil ? 44 : 88)
    }

    /// « … » at the top right (Paul, 15/11): what is done to the project itself.
    private var projectMenu: some View {
        Menu {
            Menu("Statut") {
                ForEach(ProjectStatus.allCases, id: \.self) { status in
                    Button { draft.status = status } label: {
                        if draft.status == status { Label(status.title, systemImage: "checkmark") } else { Text(status.title) }
                    }
                }
            }
            if let folder = draft.codeFolder, !folder.isEmpty {
                // In a Finder window, whatever the folder is: an app given as a folder is shown, never launched (audit of 19/11).
                Button("Ouvrir le dossier de code") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder) }
            }
            Button(draft.codeFolder?.isEmpty == false ? "Changer de dossier de code…" : "Choisir un dossier de code…") { choosingFolder = true }
            Button("Copier le nom") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(draft.name, forType: .string)
            }
            Divider()
            Button("Supprimer le projet…", role: .destructive) { confirmingDelete = true }
        } label: {
            Image(systemName: "ellipsis").font(.body.weight(.semibold)).frame(width: 28, height: 28)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        // Neutral glass, whatever the tint around (measured on 19/11: a tinted glass button looks like a principal one).
        .tint(nil)
        .menuIndicator(.hidden)
        .fixedSize()
        // The bubble of every « … » menu, and the same words for VoiceOver (lot 10, 20/11).
        .help(Words.moreActions)
        .accessibilityLabel(Words.moreActions)
    }

    /// The task of the moment, the page's first line, in neutral colors: a red or green project must not look like
    /// a problem or a success here (Paul, 15/11).
    private var nextStep: some View {
        HStack(spacing: Space.m) {
            Image(systemName: "arrow.forward.circle.fill").font(.title2).foregroundStyle(.secondary)
            // The field's one name, « tâche du moment », said as Paul says it (lot 10, 20/11).
            TextField("Ce que tu fais en ce moment sur ce projet", text: optional(\.todo), axis: .vertical)
                .font(.title3.weight(.medium))
                .textFieldStyle(.plain)
        }
        .padding(Space.l)
        .cardSurface(fill: Surface.raised)
    }

    // MARK: - Main column

    private var main: some View {
        VStack(alignment: .leading, spacing: PageMetrics.cardGap) {
            notesCard
            actionsCard
            journalCard
        }
    }

    /// Paul's own notes, first (15/11: « ce qui va m'intéresser le plus »). A click writes in them, as in Obsidian;
    /// no « Modifier »: they are saved as he types and read again once he clicks elsewhere.
    private var notesCard: some View {
        Card {
            SectionTitle("Notes", systemImage: "note.text")
            if editingNotes {
                TextEditor(text: $draft.notes)
                    .font(.system(size: TextSize.reading))
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 180)
                    .focused($notesFocused)
                    .onChange(of: notesFocused) { _, focused in if !focused { editingNotes = false } }
                    .onExitCommand { notesFocused = false }
            } else {
                Group {
                    if draft.notes.isEmpty {
                        Text("Écris tes notes ici…").font(.rowBody).foregroundStyle(.tertiary)
                    } else {
                        MarkdownView(text: draft.notes)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture {
                    editingNotes = true
                    DispatchQueue.main.async { notesFocused = true }
                }
                .pointerStyle(.horizontalText)
                // What it does, never the gesture (lot 10, 20/11).
                .help("Écrire les notes")
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
                    // What is hidden, shown or hidden: « Afficher » and « Masquer », a pair (lot 10, 20/11).
                    TextButton(showingDone ? "Masquer les faites" : "Afficher les faites") {
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
                    // The day by `Words`, its year when it is not this one (lot 10, 20/11).
                    let detail = [action.owner, action.meetingID != nil ? "d'une réunion" : nil,
                                  action.addedOn.map { Words.shortDate($0, now: Date()) }].compactMap { $0 }
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
                // « Annuler » closes without doing anything (lot 10, 20/11).
                IconButton(addingEntry ? "xmark" : "plus", help: addingEntry ? "Annuler" : "Ajouter au journal", size: 13) {
                    withAnimation(Motion.standard) { addingEntry.toggle() }
                }
            }
            if addingEntry {
                VStack(alignment: .leading, spacing: Space.s) {
                    TextField("Ce qui a été fait aujourd'hui", text: $newEntryTitle).textFieldStyle(.roundedBorder)
                    TextEditor(text: $newEntryBody).font(.body).frame(minHeight: 70)
                        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).stroke(Surface.stroke))
                    // No glass in the content: a secondary action (design system v2, 19/11).
                    Button("Ajouter au journal", action: addEntry).buttonStyle(.secondary)
                        .disabled(newEntryTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .transition(.opacity)
            }
            // How it fills, as the side cards say it (lot 10, 20/11).
            if journal.isEmpty && !addingEntry { EmptyLine("Les sessions de Claude Code écrivent ici ce qu'elles font.") }
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
                        // The day by `Words`, its year when it is not this one (lot 10, 20/11).
                        Text(Words.shortDate(entry.date, now: Date()))
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
        VStack(alignment: .leading, spacing: PageMetrics.cardGap) {
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
                            // A verb and its object, never a name on a gesture (lot 10, 20/11).
                            IconButton("xmark.circle.fill", help: "Retirer l'échéance", size: 13) { draft.dueDate = nil }
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
                    // The whole path when one is chosen; else what the button does, and why (lot 10, 20/11).
                    TextButton(draft.codeFolder.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Choisir…") { choosingFolder = true }
                        .help(draft.codeFolder ?? Words.help("Choisir le dossier de code", detail: "Claude Code reconnaît le projet"))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                // A link reads by its underline, in the accent's ink, no longer by its color (design system v2, 19/11).
                if let github = draft.github.flatMap(URL.init(string:)) {
                    Link(destination: github) { Text("GitHub").underline().foregroundStyle(Tint.accent) }
                }
                if let notion = draft.notion.flatMap(URL.init(string:)) {
                    Link(destination: notion) { Text("Notion").underline().foregroundStyle(Tint.accent) }
                }
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
                            // A meta with its hour, by `Words`: « hier 14:00 », « lun. 9:30 », « 12 nov. 14:00 » (lot 10, 20/11).
                            Text(Words.shortMoment(meeting.startedAt, now: Date()))
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
                                // The day by `Words`, its year when it is not this one (lot 10, 20/11).
                                Text("\(thread.senders.last { $0.email.lowercased() == thread.lastSender }?.display ?? thread.lastSender ?? "Moi") · "
                                     + Words.shortDate(thread.lastMessageAt, now: Date()))
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
                        // An event leads to itself, in Calendrier, as the meetings and the mails do (lot 4, 19/11).
                        RowButton(action: { library.openEvent?(event.id) }) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.title).font(.rowBody).lineLimit(1).foregroundStyle(.primary)
                                // A meta with its hour, by `Words`: « demain 9:00 », « jeu. 14:00 », « 24 nov. 14:00 »; a whole
                                // day, « demain, toute la journée », no longer « 00:00 » (lot 10, 20/11).
                                Text(event.allDay ? Words.shortDay(event.startAt, now: Date()) + ", " + Words.allDay
                                                  : Words.shortMoment(event.startAt, now: Date()))
                                    .font(.meta).foregroundStyle(.secondary)
                            }
                        }
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
        // Around an image: the radius inside a card (design system v2, 19/11).
        let shape = RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
        Menu {
            Button("Choisir une image…") { choosing = true }
            if logos.hasOwnImage(project.id) {
                Button("Retirer l'image") { logos.removeImage(for: project.id) }
            }
            if let site = logos.site(for: project.id) {
                Divider()
                if !logos.hasOwnImage(project.id) {
                    // « Actualiser » reads again what comes from outside (lot 10, 20/11).
                    Button("Actualiser le logo") { logos.refresh(project) }
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
            // Where a drop lands, as what is chosen: the accent, ink (design system v2, 19/11).
            shape.strokeBorder(Tint.accent, lineWidth: 2).opacity(targeted ? 1 : 0)
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
        // What it does, never the gesture; the same words for VoiceOver (lot 10, 20/11).
        .help("Changer le logo")
        .accessibilityLabel("Changer le logo")
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
        // One line, without a period (lot 10, 20/11): « (deviné) » and the ✕'s bubble say the rest.
        .help("Le site du client, d'où hub prend son logo")
    }

    private func save() {
        guard editing else { return }
        editing = false
        logos.setSite(text, for: projectID)
    }
}
