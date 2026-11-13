import Domain
import Persistence
import SwiftUI

/// The page of one project: its properties, actions, journal, notes and meetings.
struct ProjectPage: View {
    let project: ProjectRow
    @ObservedObject var library: ProjectLibrary

    @State private var draft: ProjectRow
    @State private var actions: [ActionRow] = []
    @State private var journal: [ProjectJournalRow] = []
    @State private var meetings: [MeetingRow] = []
    @State private var newAction = ""
    @State private var newEntryTitle = ""
    @State private var newEntryBody = ""
    @State private var editingNotes = false

    init(project: ProjectRow, library: ProjectLibrary) {
        self.project = project
        self.library = library
        _draft = State(initialValue: project)
    }

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Button { library.selected = nil } label: { Label("Projets", systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                header
                section("Actions") { actionsView }
                section("Journal") { journalView }
                section("Notes") { notesView }
                section("Réunions") { meetingsView }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: reload)
        .onChange(of: draft) { _, changed in
            if changed != project { library.save(changed) }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("", text: optional(\.icon), prompt: Text("○").foregroundStyle(.tertiary))
                    .frame(width: 32).textFieldStyle(.plain).font(.title2)
                    .help("Icône du projet : un emoji")
                TextField("Nom", text: $draft.name).font(.title.bold()).textFieldStyle(.plain)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Statut").foregroundStyle(.secondary)
                    Picker("Statut", selection: $draft.status) {
                        ForEach(ProjectStatus.boardOrder, id: \.self) { Text($0.label.capitalizedFirst).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                GridRow {
                    Text("Client").foregroundStyle(.secondary)
                    TextField("Client", text: optional(\.client)).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                }
                GridRow {
                    Text("Échéance").foregroundStyle(.secondary)
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { draft.dueDate != nil },
                            set: { draft.dueDate = $0 ? (draft.dueDate ?? Date()) : nil }
                        )).labelsHidden()
                        if draft.dueDate != nil {
                            DatePicker("", selection: Binding(get: { draft.dueDate ?? Date() }, set: { draft.dueDate = $0 }),
                                       displayedComponents: .date).labelsHidden()
                            if let label = ProjectViews.dueLabel(draft.dueDate, today: Date()) {
                                Text(label).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                GridRow {
                    Text("To do").foregroundStyle(.secondary)
                    TextField("La prochaine chose à faire", text: optional(\.todo)).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Couleur").foregroundStyle(.secondary)
                    // The plugin's French names; a value already in the note (hex, English) stays offered.
                    Picker("Couleur", selection: optional(\.color)) {
                        Text("Aucune").tag("")
                        ForEach(colorOptions, id: \.self) { name in
                            Label { Text(name.capitalizedFirst) } icon: {
                                Image(systemName: "circle.fill").foregroundStyle(Color(hex: ProjectViews.cardHex(name) ?? "#999999"))
                            }
                            .tag(name)
                        }
                    }
                    .labelsHidden().fixedSize()
                }
                if !draft.contacts.isEmpty {
                    GridRow {
                        Text("Contacts").foregroundStyle(.secondary)
                        Text(draft.contacts.joined(separator: ", ")).textSelection(.enabled)
                    }
                }
                if let folder = draft.codeFolder {
                    GridRow {
                        Text("Dossier").foregroundStyle(.secondary)
                        Text(folder).font(.callout.monospaced()).textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var colorOptions: [String] {
        guard let current = draft.color, !current.isEmpty, !ProjectViews.colorChoices.contains(current) else { return ProjectViews.colorChoices }
        return ProjectViews.colorChoices + [current]
    }

    /// A text field on an optional property: empty means none.
    private func optional(_ keyPath: WritableKeyPath<ProjectRow, String?>) -> Binding<String> {
        Binding(get: { draft[keyPath: keyPath] ?? "" }, set: { draft[keyPath: keyPath] = $0.isEmpty ? nil : $0 })
    }

    // MARK: - Sections

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.bold())
            content()
        }
    }

    private var actionsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(actions) { action in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Toggle("", isOn: Binding(get: { action.done }, set: { done in
                        var changed = action
                        changed.done = done
                        changed.updatedAt = Date()
                        try? library.store.saveAction(changed)
                        reload()
                    }))
                    .toggleStyle(.checkbox).labelsHidden()
                    Text(action.text).strikethrough(action.done).foregroundStyle(action.done ? .secondary : .primary)
                    if let added = action.addedOn {
                        Text(Self.day.string(from: added)).font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .contextMenu {
                    Button("Supprimer l'action", role: .destructive) {
                        try? library.store.deleteAction(id: action.id)
                        reload()
                    }
                }
            }
            TextField("Nouvelle action", text: $newAction)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    let text = newAction.trimmingCharacters(in: .whitespaces)
                    guard !text.isEmpty else { return }
                    let position = (actions.map(\.position).max() ?? -1) + 1
                    try? library.store.saveAction(ActionRow(projectID: project.id, text: text, addedOn: Date(), position: position, createdAt: Date()))
                    newAction = ""
                    reload()
                }
        }
    }

    private var journalView: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Ce qui a été fait aujourd'hui", text: $newEntryTitle).textFieldStyle(.roundedBorder)
                if !newEntryTitle.isEmpty {
                    TextEditor(text: $newEntryBody).font(.body).frame(minHeight: 60)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    Button("Ajouter au journal") {
                        try? library.store.addJournal(ProjectJournalRow(projectID: project.id, date: Date(), title: newEntryTitle,
                                                                        body: newEntryBody, createdAt: Date()))
                        newEntryTitle = ""
                        newEntryBody = ""
                        reload()
                    }
                }
            }
            ForEach(journal) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Self.day.string(from: entry.date)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        Text(entry.title).font(.callout.weight(.semibold))
                    }
                    if !entry.body.isEmpty { MarkdownView(text: entry.body).font(.callout) }
                }
            }
        }
    }

    private var notesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Button(editingNotes ? "Terminé" : "Modifier") { editingNotes.toggle() }
            }
            if editingNotes {
                TextEditor(text: $draft.notes).font(.body.monospaced()).frame(minHeight: 180)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            } else if draft.notes.isEmpty {
                Text("Aucune note.").foregroundStyle(.secondary)
            } else {
                MarkdownView(text: draft.notes)
            }
        }
    }

    private var meetingsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(meetings) { meeting in
                Button {
                    library.openMeeting?(meeting.id)
                } label: {
                    HStack {
                        Text(meeting.startedAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                        Text(meeting.title)
                    }
                }
                .buttonStyle(.link)
            }
            if meetings.isEmpty {
                Text("Aucune réunion rangée ici. Dans la fiche d'une réunion, choisis ce projet.").foregroundStyle(.secondary)
            }
            if let imported = draft.lastMeetingImported {
                Text("Dernière réunion dans Obsidian : \(Self.day.string(from: imported))").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func reload() {
        actions = (try? library.store.actions(projectID: project.id)) ?? []
        journal = (try? library.store.journal(projectID: project.id)) ?? []
        meetings = (try? library.store.meetings(projectID: project.id)) ?? []
    }
}
