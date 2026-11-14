import Domain
import Persistence
import PolhubDesign
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

/// The Kanban: one column per status (done ones in the list), large cards moved by dragging (14/11).
struct BoardView: View {
    @ObservedObject var library: ProjectLibrary
    let projects: [ProjectRow]
    /// « + » of a column: the creation window, with that status.
    let create: (ProjectStatus) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Space.l) {
                ForEach(ProjectViews.columns(projects, includeDone: false)) { column in
                    ColumnView(column: column, library: library, create: create)
                }
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.m)
            .padding(.bottom, Space.l)
        }
        .scrollIndicators(.automatic)
    }
}

struct ColumnView: View {
    let column: BoardColumn
    @ObservedObject var library: ProjectLibrary
    let create: (ProjectStatus) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                ColorDot(column.color.swiftUI, size: 10)
                Text(column.title.capitalizedFirst).font(.headline)
                Text("\(column.projects.count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button { create(column.status) } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("Nouveau projet dans « \(column.title) »")
            }
            .padding(.horizontal, Space.xs)
            ScrollView(.vertical) {
                LazyVStack(spacing: Space.m) {
                    ForEach(column.projects) { project in
                        ProjectCard(project: project, lastMeeting: ProjectViews.lastMeeting(project, appMeeting: library.lastAppMeetings[project.id]))
                            .onTapGesture { library.selected = project.id }
                            .draggable(project.id.uuidString)
                            .dropDestination(for: String.self) { items, _ in
                                drop(items, before: project.id)
                            }
                    }
                }
                .padding(.bottom, 60)
            }
            .scrollIndicators(.never)
        }
        .padding(Space.m)
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(column.color.swiftUI.opacity(targeted ? 0.16 : 0.06), in: RoundedRectangle(cornerRadius: Radius.card + 4, style: .continuous))
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

/// One project on the board: icon and name, client, due date, the next thing to do, the last meeting.
struct ProjectCard: View {
    let project: ProjectRow
    var lastMeeting: Date?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .top, spacing: Space.s) {
                if let icon = project.icon, icon.count <= 2 { Text(icon).font(.title2) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name).font(.headline).lineLimit(2)
                    if let client = project.client { Text(client).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
            if let todo = project.todo, !todo.isEmpty {
                Text(todo).font(.callout).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            let due = ProjectViews.dueLabel(project.dueDate, today: Date())
            if due != nil || lastMeeting != nil {
                HStack(spacing: Space.s) {
                    if let due { Chip(due, systemImage: "calendar", tint: dueColor(due)) }
                    if let lastMeeting {
                        Chip(lastMeeting.formatted(.relative(presentation: .named).locale(Locale(identifier: "fr_FR"))), systemImage: "waveform")
                    }
                }
            }
        }
        .padding(Space.m + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: Radius.card - 2, style: .continuous))
        .overlay(alignment: .leading) {
            if let hex = ProjectViews.cardHex(project.color) {
                Capsule().fill(Color(hex: hex)).frame(width: 4).padding(.vertical, Space.m)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Radius.card - 2, style: .continuous).strokeBorder(Surface.stroke))
        .shadow(color: .black.opacity(hovering ? 0.12 : 0.05), radius: hovering ? 8 : 2, y: hovering ? 3 : 1)
        .scaleEffect(hovering ? 1.01 : 1)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
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

