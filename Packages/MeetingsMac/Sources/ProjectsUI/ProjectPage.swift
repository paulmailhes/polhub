import Domain
import Persistence
import PolhubDesign
import SwiftUI

/// The page of one project (14/11): who and what, the next step, the actions, the journal and the notes; on
/// the side its details, contacts, meetings and coming events. Most of it fills itself (meetings, Claude
/// Code); every field stays editable.
struct ProjectPage: View {
    let project: ProjectRow
    @ObservedObject var library: ProjectLibrary
    /// Set when the page floats over the board: it closes itself, the window's toolbar stays the board's.
    var close: (() -> Void)?

    @State private var draft: ProjectRow
    @State private var actions: [ActionRow] = []
    @State private var journal: [ProjectJournalRow] = []
    @State private var meetings: [MeetingRow] = []
    @State private var contacts: [ContactRow] = []
    @State private var events: [CalendarEventRow] = []
    @State private var newAction = ""
    @State private var newEntryTitle = ""
    @State private var newEntryBody = ""
    @State private var editingNotes = false
    @State private var showingDone = false
    @State private var choosingFolder = false
    /// Two columns when the page is wide enough: decided from its width, not from its texts' (review of 14/11).
    @State private var wide = true

    init(project: ProjectRow, library: ProjectLibrary, close: (() -> Void)? = nil) {
        self.project = project
        self.library = library
        self.close = close
        _draft = State(initialValue: project)
    }

    private static let locale = Locale(identifier: "fr_FR")

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

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .center, spacing: Space.m) {
                TextField("", text: optional(\.icon), prompt: Text("◌").foregroundStyle(.tertiary))
                    .font(.system(size: 34))
                    .frame(width: 52)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.plain)
                    .help("L'icône du projet : un emoji")
                TextField("Nom", text: $draft.name)
                    .font(.largeTitle.weight(.bold))
                    .textFieldStyle(.plain)
            }
            HStack(spacing: Space.s) {
                Menu {
                    ForEach([ProjectStatus.priorite1, .priorite2, .priorite3, .enAttente, .idee, .termine], id: \.self) { status in
                        Button(status.label.capitalizedFirst) { draft.status = status }
                    }
                } label: {
                    Chip(draft.status.label.capitalizedFirst, systemImage: "circle.fill", tint: ProjectViews.statusColor(draft.status))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
                if let label = ProjectViews.dueLabel(draft.dueDate, today: Date()) {
                    Chip(label, systemImage: "calendar", tint: label.hasPrefix("En retard") ? .red : label == "Aujourd'hui" ? .orange : nil)
                }
                if let client = draft.client, !client.isEmpty { Chip(client, systemImage: "building.2") }
            }
        }
    }

    private var nextStep: some View {
        HStack(spacing: Space.m) {
            Image(systemName: "arrow.forward.circle.fill").font(.title2).foregroundStyle(ProjectViews.statusColor(draft.status))
            TextField("La prochaine chose à faire", text: optional(\.todo), axis: .vertical)
                .font(.title3)
                .textFieldStyle(.plain)
        }
        .padding(Space.l)
        .cardSurface(fill: ProjectViews.statusColor(draft.status).opacity(0.08))
    }

    // MARK: - Main column

    private var main: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Card {
                SectionTitle("Actions", systemImage: "checklist", count: actions.filter { !$0.done }.count) {
                    if actions.contains(where: \.done) {
                        Button(showingDone ? "Masquer les faites" : "Voir les faites") { showingDone.toggle() }
                            .buttonStyle(.borderless).font(.callout)
                    }
                }
                ForEach(actions.filter { showingDone || !$0.done }) { action in actionRow(action) }
                TextField("Nouvelle action", text: $newAction)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addAction)
            }
            Card {
                SectionTitle("Journal", systemImage: "book.closed", count: journal.count)
                TextField("Ce qui a été fait aujourd'hui", text: $newEntryTitle).textFieldStyle(.roundedBorder)
                if !newEntryTitle.isEmpty {
                    TextEditor(text: $newEntryBody).font(.body).frame(minHeight: 70)
                        .overlay(RoundedRectangle(cornerRadius: Radius.small, style: .continuous).stroke(Surface.stroke))
                    Button("Ajouter au journal", action: addEntry).buttonStyle(.glass)
                }
                ForEach(journal.prefix(12)) { entry in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                            Text(entry.date.formatted(.dateTime.day().month(.abbreviated).locale(Self.locale)))
                                .font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                            Text(entry.title).font(.callout.weight(.semibold))
                        }
                        if !entry.body.isEmpty { MarkdownView(text: entry.body).font(.callout).padding(.leading, 72) }
                    }
                }
            }
            Card {
                SectionTitle("Notes", systemImage: "note.text") {
                    Button(editingNotes ? "Terminé" : "Modifier") { editingNotes.toggle() }.buttonStyle(.borderless).font(.callout)
                }
                if editingNotes {
                    TextEditor(text: $draft.notes).font(.body).frame(minHeight: 200)
                        .overlay(RoundedRectangle(cornerRadius: Radius.small, style: .continuous).stroke(Surface.stroke))
                } else if draft.notes.isEmpty {
                    Text("Aucune note.").foregroundStyle(.secondary)
                } else {
                    MarkdownView(text: draft.notes)
                }
            }
        }
    }

    private func actionRow(_ action: ActionRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Toggle(isOn: Binding(get: { action.done }, set: { done in
                var changed = action
                changed.done = done
                changed.updatedAt = Date()
                try? library.store.saveAction(changed)
                reload()
            })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.text).strikethrough(action.done).foregroundStyle(action.done ? .secondary : .primary)
                    let detail = [action.owner, action.meetingID != nil ? "d'une réunion" : nil,
                                  action.addedOn?.formatted(.dateTime.day().month(.abbreviated).locale(Self.locale))].compactMap { $0 }
                    if !detail.isEmpty { Text(detail.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .toggleStyle(.checkbox)
            Spacer()
        }
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

    private func addAction() {
        let text = newAction.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let position = (actions.map(\.position).max() ?? -1) + 1
        try? library.store.saveAction(ActionRow(projectID: project.id, text: text, addedOn: Date(), position: position, createdAt: Date()))
        newAction = ""
        reload()
    }

    private func addEntry() {
        try? library.store.addJournal(ProjectJournalRow(projectID: project.id, date: Date(), title: newEntryTitle, body: newEntryBody, createdAt: Date()))
        newEntryTitle = ""
        newEntryBody = ""
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
                            Button { draft.dueDate = nil } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.borderless).foregroundStyle(.secondary).help("Sans échéance")
                        } else {
                            Button("Ajouter") { draft.dueDate = Date() }.buttonStyle(.borderless)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Couleur").foregroundStyle(.secondary)
                    ColorChoices(selection: optional(\.color))
                }
                LabeledContent("Dossier") {
                    Button(draft.codeFolder.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Choisir…") { choosingFolder = true }
                        .buttonStyle(.borderless)
                        .help(draft.codeFolder ?? "Le dossier de code, pour que Claude Code reconnaisse le projet")
                }
                if let github = draft.github.flatMap(URL.init(string:)) { Link("GitHub", destination: github) }
                if let notion = draft.notion.flatMap(URL.init(string:)) { Link("Notion", destination: notion) }
            }
            Card {
                SectionTitle("Contacts", systemImage: "person.2", count: contacts.count)
                if contacts.isEmpty {
                    Text("Les invités de ses rendez-vous arrivent ici tout seuls.").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(contacts.prefix(10)) { contact in
                    Button { library.openContact?(contact.id) } label: {
                        HStack(spacing: Space.s) {
                            Avatar(contact.initials, size: 26)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(contact.name).foregroundStyle(.primary)
                                if let company = contact.company { Text(company).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Card {
                SectionTitle("Réunions", systemImage: "waveform", count: meetings.count)
                if meetings.isEmpty {
                    Text("Ses réunions enregistrées arrivent ici toutes seules.").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(meetings.prefix(8)) { meeting in
                    Button { library.openMeeting?(meeting.id) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(meeting.title).lineLimit(1).foregroundStyle(.primary)
                            Text(meeting.startedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Self.locale)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if !events.isEmpty {
                Card {
                    SectionTitle("Prochains rendez-vous", systemImage: "calendar", count: events.count)
                    ForEach(events.prefix(5)) { event in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title).lineLimit(1)
                            Text(event.startAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute().locale(Self.locale)))
                                .font(.caption).foregroundStyle(.secondary)
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
        contacts = (try? ContactStore(library.store.database).contacts(projectID: project.id)) ?? []
        events = ((try? CalendarStore(library.store.database).events(projectID: project.id)) ?? [])
            .filter { $0.endAt > Date() }
            .reduce(into: [CalendarEventRow]()) { seen, event in if !seen.contains(where: { $0.eventID == event.eventID }) { seen.append(event) } }
    }
}
