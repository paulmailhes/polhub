import Colin
import Persistence
import PolhubDesign
import SwiftUI

/// « À faire » (0.36.0, 18/11): the projects where it is Paul's turn and those whose deadline is close, grouped by day,
/// the late first. A line: the project and its client, when in words — the late in the accent —, the task of the moment
/// under it. « Reporter » and « Livré »: always on a late line, at the hover on the other dated ones; « Annuler » for a
/// few seconds at the head of the list.
struct TodoCard: View {
    @ObservedObject var todo: TodoLibrary
    @ObservedObject var agenda: AgendaLibrary
    @ObservedObject var router: WindowRouter
    var limit = 6
    @State private var expanded = false
    @State private var hovered: UUID?
    /// The line whose « Choisir une date… » is open, and the day picked.
    @State private var picking: UUID?
    @State private var picked = Date()

    private var calendar: Calendar { CalendarView.calendar }
    /// The room the two buttons take at the end of a line.
    private static let actionsWidth: CGFloat = 150

    var body: some View {
        // The days pass: « demain » becomes « aujourd'hui », a deadline becomes late.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let lines = todo.lines(projects: agenda.projects, events: agenda.shown)
            let folded = TodoRules.visible(lines, limit: limit, expanded: false)
            let shown = expanded ? lines : folded.shown
            let groups = TodoRules.Group.allCases.filter { group in shown.contains { $0.group == group } }
            VStack(alignment: .leading, spacing: Space.s) {
                HomeSectionHeader(title: "À faire", count: lines.isEmpty ? nil : lines.count)
                if let settled = todo.settled {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text(settled.text).font(.rowBody).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: Space.s)
                        TextButton("Annuler", quiet: true) { todo.undoSettled() }
                    }
                    .transition(.opacity)
                }
                if lines.isEmpty {
                    EmptyLine("Rien à faire.")
                }
                ForEach(groups, id: \.self) { group in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        if groups.count > 1 {
                            Text(TodoRules.title(group)).font(.meta).foregroundStyle(.secondary).padding(.top, Space.xs)
                        }
                        ForEach(shown.filter { $0.group == group }) { line in row(line, now: context.date) }
                    }
                }
                ShowMoreButton(hidden: folded.hidden, expanded: $expanded)
            }
            .animation(Motion.standard, value: lines)
            .animation(Motion.quick, value: todo.settled)
        }
    }

    private func row(_ line: TodoRules.Line, now: Date) -> some View {
        let late = line.group == .late
        let dated = line.due != nil
        let showsActions = dated && (late || hovered == line.id)
        let when = TodoRules.when(line, now: now, calendar: calendar)
        return RowButton(action: { router.openProject(line.id) }) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text("\(Text(line.name).foregroundStyle(.primary))\(Text(line.client.map { " · \($0)" } ?? "").foregroundStyle(.secondary))")
                        .font(.rowTitle)
                        .lineLimit(1)
                    Spacer(minLength: Space.s)
                    if let when {
                        Text(when)
                            .font(.meta.monospacedDigit())
                            .fontWeight(late ? .semibold : .regular)
                            .foregroundStyle(late ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                            // At the hover, the buttons take its place; a late line keeps it, its buttons are under it.
                            .opacity(!late && showsActions ? 0 : 1)
                    }
                }
                if line.detail != nil || late {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text(line.detail ?? " ").font(.meta).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                        if late { Color.clear.frame(width: Self.actionsWidth, height: 1) }
                    }
                }
            }
        }
        .overlay(alignment: late ? .bottomTrailing : .topTrailing) {
            if dated {
                actions(line)
                    .opacity(showsActions ? 1 : 0)
                    .allowsHitTesting(showsActions)
            }
        }
        .onHover { inside in hovered = inside ? line.id : (hovered == line.id ? nil : hovered) }
        .popover(isPresented: Binding(get: { picking == line.id }, set: { if !$0 { picking = nil } }), arrowEdge: .leading) {
            VStack(alignment: .trailing, spacing: Space.s) {
                DatePicker("Reporter au", selection: $picked, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                Button("Reporter") {
                    todo.postpone(line, to: picked)
                    picking = nil
                }
                .buttonStyle(.glassProminent)
            }
            .padding(Space.m)
        }
    }

    /// « Reporter » (its choices, then « Choisir une date… ») and « Livré ».
    private func actions(_ line: TodoRules.Line) -> some View {
        HStack(spacing: Space.xs) {
            Menu {
                ForEach(TodoRules.postpone(due: line.due, now: Date(), calendar: calendar), id: \.date) { choice in
                    Button(choice.label) { todo.postpone(line, to: choice) }
                }
                Divider()
                Button("Choisir une date…") {
                    picked = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(Date(), line.due ?? Date()))) ?? Date()
                    picking = line.id
                }
            } label: {
                Text("Reporter")
            }
            .menuStyle(.button)
            .buttonStyle(.subtle)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Reporter l'échéance de \(line.name)")
            Button("Livré") { todo.deliver(line) }
                .buttonStyle(.subtle)
                .fixedSize()
                .help("Effacer l'échéance de \(line.name) et le noter au journal")
        }
    }
}
