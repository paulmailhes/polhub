import Domain
import Persistence
import PolhubDesign
import SwiftUI

/// The Kanban: Priorité 1, Priorité 2, En pause, then Terminé at the right in compact cards (15/11); cards moved
/// by dragging.
struct BoardView: View {
    @ObservedObject var library: ProjectLibrary
    let projects: [ProjectRow]
    /// « + » of a column: the creation window, with that status.
    let create: (ProjectStatus) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Space.l) {
                ForEach(ProjectViews.columns(projects)) { column in
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
    @AppStorage(Preferences.Key.cardSize) private var sizeName = CardSize.medium.rawValue
    private var size: CardSize { ProjectViews.cardSize(column.status, chosen: CardSize(stored: sizeName)) }

    var body: some View {
        let color = ProjectViews.statusColor(column.status)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s) {
                ColorDot(color, size: 10)
                Text(column.title).font(.headline)
                Text("\(column.projects.count)").font(.meta.monospacedDigit()).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if column.status != .termine {
                    IconButton("plus", help: "Nouveau projet dans « \(column.title) »", size: 13) { create(column.status) }
                }
            }
            .frame(minHeight: 32)
            .padding(.leading, Space.xs)
            ScrollView(.vertical) {
                LazyVStack(spacing: size.isCompact ? Space.s : Space.m) {
                    ForEach(column.projects) { project in
                        ProjectCard(project: project, size: size,
                                    lastMeeting: ProjectViews.lastMeeting(project, appMeeting: library.lastAppMeetings[project.id]))
                            .onTapGesture { library.selected = project.id }
                            // Opened from VoiceOver and the keyboard too (correctifs, 15/11).
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { library.selected = project.id }
                            .draggable(project.id.uuidString)
                            .dropDestination(for: String.self) { items, _ in
                                drop(items, before: project.id)
                            }
                    }
                }
                // Room for the hovered card's shadow and growth, inside the scroll view that clips: above the first
                // card (the room under the column's title) and on both sides (the column's margins), so the lift is
                // never cut (correctifs, 15/11).
                .padding(.horizontal, Space.m)
                .padding(.top, Space.m + 2)
                .padding(.bottom, 60)
            }
            .padding(.horizontal, -Space.m)
            .scrollIndicators(.never)
        }
        .padding(Space.m)
        .frame(width: size.columnWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(color.opacity(targeted ? 0.12 : 0.04), in: RoundedRectangle(cornerRadius: Radius.card + 4, style: .continuous))
        .animation(Motion.quick, value: targeted)
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

/// One project on the board, in its color (15/11): its logo, name and client; normal cards add the next thing to
/// do, the due date and the last meeting.
struct ProjectCard: View {
    let project: ProjectRow
    let size: CardSize
    var lastMeeting: Date?
    @Environment(\.colorScheme) private var scheme

    static let radius = Radius.card - 2

    var body: some View {
        let tint = ProjectViews.tint(project)
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: size.isCompact ? .center : .top, spacing: Space.s + 2) {
                ProjectLogo(project, size: size.logoSize)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name).font(.rowTitle.weight(.semibold)).lineLimit(size.isCompact ? 1 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let client = project.client, !client.isEmpty {
                        Text(client).font(.meta).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            if !size.isCompact {
                if let todo = project.todo, !todo.isEmpty {
                    Text(todo).font(.rowBody).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                chips
            }
        }
        .padding(.vertical, size.padding)
        .padding(.leading, size.padding + 3)
        .padding(.trailing, size.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .leading) {
                Color(nsColor: .windowBackgroundColor)
                tint.opacity(scheme == .dark ? 0.22 : 0.14)
                // The stronger stripe of its color, along the left edge.
                tint.frame(width: 4)
            }
            .clipShape(shape)
        }
        .cardHover(radius: Self.radius)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var chips: some View {
        let due = ProjectViews.dueLabel(project.dueDate, today: Date())
        if due != nil || lastMeeting != nil {
            let dueChip = due.map { Chip($0, systemImage: "calendar", tint: dueColor($0)) }
            let meetingChip = lastMeeting.map { Chip(ProjectViews.meetingLabel($0, now: Date()), systemImage: "waveform") }
            // Side by side when they fit, else one under the other.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s) {
                    dueChip
                    meetingChip
                }
                VStack(alignment: .leading, spacing: Space.xs) {
                    dueChip
                    meetingChip
                }
            }
        }
    }

    private func dueColor(_ label: String) -> Color {
        label.hasPrefix("En retard") ? .red : label == "Aujourd'hui" ? .orange : .secondary
    }
}

extension String {
    /// « rouge » → « Rouge ».
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
