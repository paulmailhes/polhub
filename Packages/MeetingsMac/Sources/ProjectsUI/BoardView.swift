import Domain
import Persistence
import PolhubDesign
import SwiftUI

/// The Kanban: Priorité 2 (the most urgent, Paul's scale), Priorité 1, En pause, then Terminé at the right; four
/// columns of one width that share the window (Paul, 15/11: « tout doit faire la même largeur, prends la place »);
/// cards moved by dragging.
struct BoardView: View {
    @ObservedObject var library: ProjectLibrary
    let projects: [ProjectRow]
    /// « + » of a column: the creation window, with that status.
    let create: (ProjectStatus) -> Void
    @AppStorage(Preferences.Key.cardSize) private var sizeName = CardSize.medium.rawValue

    var body: some View {
        let columns = ProjectViews.columns(projects)
        GeometryReader { geometry in
            let width = ProjectViews.columnWidth(available: geometry.size.width - 2 * Space.xl, count: columns.count,
                                                 spacing: Space.l, minimum: CardSize(stored: sizeName).columnWidth)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Space.l) {
                    ForEach(columns) { column in
                        ColumnView(column: column, library: library, width: width, create: create)
                    }
                }
                .padding(.horizontal, Space.xl)
                .padding(.top, Space.m)
                .padding(.bottom, Space.l)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .scrollIndicators(.automatic)
        }
    }
}

struct ColumnView: View {
    let column: BoardColumn
    @ObservedObject var library: ProjectLibrary
    let width: CGFloat
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
                                    lastMeeting: ProjectViews.lastMeeting(project, appMeeting: library.lastAppMeetings[project.id]),
                                    nextEvent: library.nextEvents[project.id])
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
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        // A panel: the card's radius (design system v2, 19/11). Its tint waits for the Kanban's own lot.
        .background(color.opacity(targeted ? 0.12 : 0.04), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
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

/// One project on the board, in its color: its logo and name; normal cards then show the next thing to do, the
/// most visible line (Paul, 15/11: « c'est le truc principal »), and in words the next meeting, the due date and
/// the last meeting. The client is left out: Paul knows it.
struct ProjectCard: View {
    let project: ProjectRow
    let size: CardSize
    var lastMeeting: Date?
    var nextEvent: Date?
    @Environment(\.colorScheme) private var scheme

    static let radius = Radius.card

    var body: some View {
        let tint = ProjectViews.tint(project)
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .center, spacing: Space.m) {
                ProjectLogo(project, size: size.logoSize)
                Text(project.name)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if !size.isCompact {
                if let todo = project.todo, !todo.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Image(systemName: "arrow.right.circle.fill").foregroundStyle(tint)
                        Text(todo).font(.rowTitle.weight(.medium)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Space.m).padding(.vertical, Space.s + 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(scheme == .dark ? 0.55 : 0.85),
                                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                }
                facts
            }
        }
        .padding(size.padding)
        .padding(.leading, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .leading) {
                Color(nsColor: .windowBackgroundColor)
                tint.opacity(scheme == .dark ? 0.22 : 0.13)
                // The stronger stripe of its color, along the left edge.
                tint.frame(width: 4)
            }
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(tint.opacity(0.18)))
        .cardHover(radius: Self.radius)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }

    /// The next meeting, the due date and the last meeting, one per line, in words.
    @ViewBuilder
    private var facts: some View {
        let now = Date()
        let due = ProjectViews.dueLabel(project.dueDate, today: now)
        if nextEvent != nil || due != nil || lastMeeting != nil {
            VStack(alignment: .leading, spacing: Space.xs + 2) {
                if let nextEvent {
                    fact(ProjectViews.nextEventLabel(nextEvent, now: now), icon: "calendar.badge.clock", tint: Color(hex: Palette.blue), strong: true)
                }
                if let due {
                    fact(due, icon: "flag", tint: ProjectViews.dueTint(due), strong: ProjectViews.dueTint(due) != nil)
                }
                if let lastMeeting {
                    fact(ProjectViews.meetingLabel(lastMeeting, now: now), icon: "waveform", tint: nil, strong: false)
                }
            }
        }
    }

    private func fact(_ text: String, icon: String, tint: Color?, strong: Bool) -> some View {
        Label {
            Text(text).font(.meta.weight(strong ? .semibold : .regular)).lineLimit(1)
        } icon: {
            Image(systemName: icon).font(.meta).frame(width: 16)
        }
        .foregroundStyle(tint ?? Color.secondary)
    }
}

extension String {
    /// « rouge » → « Rouge ».
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
