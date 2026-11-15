import Domain
import Persistence
import PolhubDesign
import SwiftUI

/// The window that creates a project, with all its fields (Paul, 14/11); opened by « + ».
struct NewProjectSheet: View {
    let create: (ProjectRow) -> Void
    @State private var draft: ProjectRow
    @State private var hasDue = false
    @State private var choosingFolder = false
    @Environment(\.dismiss) private var dismiss

    init(status: ProjectStatus, create: @escaping (ProjectRow) -> Void) {
        self.create = create
        _draft = State(initialValue: ProjectRow(name: "", status: status, createdAt: Date()))
    }

    private var named: Bool { !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(spacing: Space.m) {
                        TextField("", text: text(\.icon), prompt: Text("◌").foregroundStyle(.tertiary))
                            .font(.largeTitle)
                            .frame(width: 52)
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.plain)
                            .help("Une icône : un emoji")
                        TextField("Nom du projet", text: $draft.name)
                            .font(.title2.weight(.semibold))
                            .textFieldStyle(.plain)
                    }
                    Picker("Statut", selection: $draft.status) {
                        ForEach(ProjectStatus.allCases, id: \.self) {
                            Text($0.title).tag($0)
                        }
                    }
                    TextField("Client", text: text(\.client))
                    TextField("Prochaine étape", text: text(\.todo), prompt: Text("La prochaine chose à faire"))
                    Toggle("Échéance", isOn: $hasDue)
                        // The date shown is the one saved, even untouched (review of 14/11).
                        .onChange(of: hasDue) { _, on in draft.dueDate = on ? (draft.dueDate ?? Calendar.current.startOfDay(for: Date())) : nil }
                    if hasDue {
                        DatePicker("Date", selection: Binding(get: { draft.dueDate ?? Date() }, set: { draft.dueDate = $0 }),
                                   displayedComponents: .date)
                    }
                }
                Section("Couleur") {
                    ColorChoices(selection: text(\.color))
                }
                Section("Liens") {
                    HStack {
                        TextField("Dossier de code", text: text(\.codeFolder), prompt: Text("Pour que Claude Code reconnaisse le projet"))
                        Button("Choisir…") { choosingFolder = true }
                    }
                    TextField("GitHub", text: text(\.github), prompt: Text("https://github.com/…"))
                    TextField("Notion", text: text(\.notion), prompt: Text("https://www.notion.so/…"))
                }
                Section("Notes") {
                    TextEditor(text: $draft.notes).frame(minHeight: 90).font(.body)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Créer le projet") {
                    if !hasDue { draft.dueDate = nil }
                    create(draft)
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!named)
            }
            .padding(Space.l)
        }
        .frame(width: 520, height: 640)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { draft.codeFolder = url.path(percentEncoded: false) }
        }
    }

    /// A text field on an optional property: empty means none.
    private func text(_ keyPath: WritableKeyPath<ProjectRow, String?>) -> Binding<String> {
        Binding(get: { draft[keyPath: keyPath] ?? "" }, set: { draft[keyPath: keyPath] = $0.isEmpty ? nil : $0 })
    }
}

/// The project colors, as swatches; « » for none.
struct ColorChoices: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 22, maximum: 22), spacing: Space.s)], alignment: .leading, spacing: Space.s) {
            swatch(nil)
            ForEach(ProjectViews.colorChoices, id: \.self) { swatch($0) }
        }
    }

    private func swatch(_ name: String?) -> some View {
        let chosen = (name ?? "") == selection
        return Button { selection = name ?? "" } label: {
            Circle()
                .fill(name.flatMap(ProjectViews.cardHex).map(Color.init(hex:)) ?? Color.secondary.opacity(0.15))
                .frame(width: 22, height: 22)
                .overlay {
                    if chosen {
                        Image(systemName: name == nil ? "xmark" : "checkmark").font(.caption.bold())
                            .foregroundStyle(name == nil ? Color.secondary : .white)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(name?.capitalizedFirst ?? "Aucune")
    }
}
