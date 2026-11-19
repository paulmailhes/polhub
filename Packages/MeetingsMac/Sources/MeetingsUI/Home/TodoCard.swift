import Colin
import Persistence
import PolhubDesign
import SwiftUI

/// « À faire » (0.36.0, in a card 0.37.0): the projects where it is Paul's turn and those whose deadline is close,
/// grouped by day, the late first. A line: the project and its client, when in words — the late in red (`Tint.late`,
/// design system v2, 19/11) —, the task of the moment under it. A click unfolds it on what is to do (the task, every
/// action left, « Ouvrir le projet »).
/// « Reporter » and « Livré »: always on a late line or an unfolded one, at the hover on the other dated ones; « Livré »
/// proposes the project's next call as the new deadline; « Annuler » for a few seconds at the head of the card.
struct TodoCard: View {
    @ObservedObject var todo: TodoLibrary
    @ObservedObject var agenda: AgendaLibrary
    @ObservedObject var router: WindowRouter
    var limit = 6
    @State private var expanded = false
    @State private var hovered: UUID?
    /// The line unfolded, one at a time.
    @State private var open: UUID?
    /// The line whose « Choisir une date… » is open, and the day picked.
    @State private var picking: UUID?
    @State private var picked = Date()

    init(todo: TodoLibrary, agenda: AgendaLibrary, router: WindowRouter, limit: Int = 6, opened: UUID? = nil) {
        self.todo = todo
        self.agenda = agenda
        self.router = router
        self.limit = limit
        _open = State(initialValue: opened)
    }

    private var calendar: Calendar { CalendarView.calendar }
    /// The room the two buttons take at the end of a late line.
    private static let actionsWidth: CGFloat = 150
    /// The actions shown in an unfolded line, before « + N autres ».
    private static let actionsShown = 8

    var body: some View {
        // The days pass: « demain » becomes « aujourd'hui », a deadline becomes late.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let lines = todo.lines(projects: agenda.projects, events: agenda.shown)
            let folded = TodoRules.visible(lines, limit: limit, expanded: false)
            let shown = expanded ? lines : folded.shown
            let groups = TodoRules.Group.allCases.filter { group in shown.contains { $0.group == group } }
            // A line that left the list (delivered, moved) is no longer open.
            let unfolded = lines.contains { $0.id == open } ? open : nil
            HomeCard("À faire", count: lines.isEmpty ? nil : lines.count) {
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
                    let inGroup = shown.filter { $0.group == group }
                    VStack(alignment: .leading, spacing: Space.xs) {
                        if groups.count > 1 {
                            HomeGroupLabel(text: TodoRules.title(group)).padding(.top, group == groups.first ? 0 : Space.s)
                        }
                        ForEach(inGroup) { line in
                            row(line, now: context.date, unfolded: unfolded == line.id).homeRow(first: line.id == inGroup.first?.id)
                        }
                    }
                }
                ShowMoreButton(hidden: folded.hidden, expanded: $expanded)
            }
            .animation(Motion.standard, value: lines)
            .animation(Motion.standard, value: open)
            .animation(Motion.quick, value: todo.settled)
        }
    }

    private func row(_ line: TodoRules.Line, now: Date, unfolded: Bool) -> some View {
        let late = line.group == .late
        let dated = line.due != nil
        let hoverActions = dated && !late && !unfolded && hovered == line.id
        let when = TodoRules.when(line, now: now, calendar: calendar)
        return VStack(alignment: .leading, spacing: Space.s) {
            RowButton(action: { open = unfolded ? nil : line.id }) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(unfolded ? 90 : 0))
                        Text("\(Text(line.name).foregroundStyle(.primary).fontWeight(.medium))\(Text(line.client.map { " · \($0)" } ?? "").foregroundStyle(.secondary))")
                            .font(.rowTitle)
                            .lineLimit(1)
                        Spacer(minLength: Space.s)
                        if let when {
                            Text(when)
                                .font(.meta.monospacedDigit())
                                .fontWeight(late ? .semibold : .regular)
                                // « depuis 6 j »: late, in red (design system v2, 19/11).
                                .foregroundStyle(late ? AnyShapeStyle(Tint.late) : AnyShapeStyle(.secondary))
                                .lineLimit(1)
                                // At the hover, the buttons take its place.
                                .opacity(hoverActions ? 0 : 1)
                        }
                    }
                    if !unfolded, line.detail != nil || late {
                        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                            Text(line.detail ?? " ").font(.meta).foregroundStyle(.secondary).lineLimit(1)
                            Spacer(minLength: 0)
                            if late { Color.clear.frame(width: Self.actionsWidth, height: 1) }
                        }
                        .padding(.leading, 17)
                    }
                }
            }
            .overlay(alignment: late ? .bottomTrailing : .topTrailing) {
                if dated, !unfolded {
                    actions(line)
                        .opacity(late || hoverActions ? 1 : 0)
                        .allowsHitTesting(late || hoverActions)
                }
            }
            .onHover { inside in hovered = inside ? line.id : (hovered == line.id ? nil : hovered) }
            .help(unfolded ? "Replier" : "Voir ce qu'il y a à faire")
            if unfolded { details(line) }
        }
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

    /// What is to do, the line unfolded: the task of the moment, every action left, then the gestures.
    private func details(_ line: TodoRules.Line) -> some View {
        let task = agenda.projects.first { $0.id == line.id }?.todo?.trimmingCharacters(in: .whitespacesAndNewlines)
        let left = todo.openActions[line.id] ?? []
        return VStack(alignment: .leading, spacing: Space.s) {
            if let task, !task.isEmpty {
                Text("\(Text("Tâche · ").foregroundStyle(.secondary))\(Text(task))").font(.rowBody)
            }
            if left.isEmpty {
                Text("Aucune action en cours.").font(.meta).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(left.prefix(Self.actionsShown).enumerated()), id: \.offset) { _, action in
                        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                            Circle().fill(.tertiary).frame(width: 4, height: 4).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
                            Text(action).font(.rowBody).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if left.count > Self.actionsShown {
                        Text("+ \(left.count - Self.actionsShown) autres").font(.meta).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: Space.s) {
                TextButton("Ouvrir le projet", quiet: true) { router.openProject(line.id) }
                Spacer(minLength: Space.s)
                if line.due != nil { actions(line) }
            }
        }
        .padding(.leading, 17)
        .padding(.bottom, Space.xs)
        .transition(.opacity)
    }

    /// « Reporter » (its choices, then « Choisir une date… ») and « Livré » (with the next call, a menu).
    private func actions(_ line: TodoRules.Line) -> some View {
        HStack(spacing: Space.xs) {
            Menu {
                let choices = TodoRules.postpone(due: line.due, now: Date(), calendar: calendar)
                ForEach(choices, id: \.date) { choice in
                    Button(choice.label) { todo.postpone(line, to: choice) }
                }
                if !choices.isEmpty { Divider() }
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
            if let next = TodoRules.nextCall(line.id, events: agenda.shown, now: Date()) {
                Menu {
                    Button(TodoRules.deliveredNext(next, now: Date(), calendar: calendar)) { todo.deliver(line, next: next) }
                    Button("Livré, sans échéance") { todo.deliver(line) }
                } label: {
                    Text("Livré")
                }
                .menuStyle(.button)
                .buttonStyle(.subtle)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Noter la livraison au journal, puis le prochain call ou aucune échéance")
            } else {
                Button("Livré") { todo.deliver(line) }
                    .buttonStyle(.subtle)
                    .fixedSize()
                    .help("Effacer l'échéance de \(line.name) et le noter au journal")
            }
        }
    }
}
