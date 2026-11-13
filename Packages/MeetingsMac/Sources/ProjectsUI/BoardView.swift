import Domain
import Persistence
import SwiftUI

extension BoardColor {
    var swiftUI: Color {
        switch self {
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .cyan: .cyan
        case .green: .green
        case .gray: .gray
        }
    }
}

/// The kanban: one column per status, cards moved by dragging.
struct BoardView: View {
    @ObservedObject var library: ProjectLibrary
    let includeDone: Bool

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(ProjectViews.columns(library.projects, includeDone: includeDone)) { column in
                    ColumnView(column: column, library: library)
                }
            }
            .padding(16)
        }
    }
}

struct ColumnView: View {
    let column: BoardColumn
    @ObservedObject var library: ProjectLibrary
    @State private var adding = false
    @State private var newName = ""
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(column.color.swiftUI).frame(width: 9, height: 9)
                Text(column.title.capitalizedFirst).font(.headline)
                Text("\(column.projects.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { adding = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("Nouveau projet dans « \(column.title) »")
            }
            if adding {
                TextField("Nom du projet", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        library.add(name: newName, status: column.status)
                        newName = ""
                        adding = false
                    }
                    .onExitCommand { adding = false; newName = "" }
            }
            ScrollView(.vertical) {
                LazyVStack(spacing: 8) {
                    ForEach(column.projects) { project in
                        ProjectCard(project: project)
                            .onTapGesture { library.selected = project.id }
                            .draggable(project.id.uuidString)
                            .dropDestination(for: String.self) { items, _ in
                                drop(items, before: project.id)
                            }
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .padding(10)
        .frame(width: 250)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(column.color.swiftUI.opacity(targeted ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 10))
        .dropDestination(for: String.self) { items, _ in
            drop(items, before: nil)
        } isTargeted: { targeted = $0 }
    }

    private func drop(_ items: [String], before target: UUID?) -> Bool {
        guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
        let before = target.flatMap { ProjectViews.dropBefore(dragged: id, onto: $0, column: column.projects.map(\.id)) }
        library.move(id, to: column.status, before: target == nil ? nil : before)
        return true
    }
}

/// One project on the board: icon, name, client, due date, the next thing to do.
struct ProjectCard: View {
    let project: ProjectRow

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let icon = project.icon, icon.count <= 2 { Text(icon) }
                Text(project.name).font(.body.weight(.semibold)).lineLimit(2)
            }
            HStack(spacing: 6) {
                if let client = project.client { Text(client).font(.caption).foregroundStyle(.secondary) }
                if let label = ProjectViews.dueLabel(project.dueDate, today: Date()) {
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .foregroundStyle(dueColor(label))
                        .background(dueColor(label).opacity(0.14), in: Capsule())
                }
            }
            if let todo = project.todo, !todo.isEmpty {
                Text(todo).font(.callout).foregroundStyle(.secondary).lineLimit(3)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            if let hex = ProjectViews.cardHex(project.color) {
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: hex)).frame(width: 3).padding(.vertical, 6)
            }
        }
        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        .contentShape(Rectangle())
    }

    private func dueColor(_ label: String) -> Color {
        label.hasPrefix("En retard") ? .red : label == "Aujourd'hui" ? .orange : .secondary
    }
}

extension String {
    /// « priorité 1 » → « Priorité 1 »: the vault writes its statuses in lower case.
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

extension Color {
    /// `#RRGGBB`.
    init(hex: String) {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
