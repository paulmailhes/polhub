import Colin
import Persistence
import PolhubDesign
import SwiftUI

/// The gestures of a line of « À faire » (lot 5, 19/11), the same under the pointer and at the right click.
enum TodoText {
    /// « Reporter » and « Livré » come under the pointer on every dated line — a late one too —, in the place of its
    /// « quand »; an unfolded line shows them under its actions.
    static func hoverActions(dated: Bool, unfolded: Bool) -> Bool {
        dated && !unfolded
    }

    /// The right click: « Ouvrir le projet », then « Reporter » and « Livré » on a dated line.
    static func menu(dated: Bool) -> [String] {
        dated ? ["Ouvrir le projet", "Reporter", "Livré"] : ["Ouvrir le projet"]
    }
}

/// « À faire » (0.36.0, in a card 0.37.0): the projects where it is Paul's turn and those whose deadline is close,
/// grouped by day, the late first. A line: the project and its client, when in words — the late in red (`Tint.late`,
/// design system v2, 19/11) —, the task of the moment under it. A click unfolds it on what is to do (the task, every
/// action left, « Ouvrir le projet »).
/// « Reporter » and « Livré » (lot 5, 19/11): under the pointer on every dated line, in the place of its « quand », kept
/// for them at rest so that nothing moves; at the right click; under the actions of an unfolded line. « Livré » proposes
/// the project's next call as the new deadline; « Annuler » for a few seconds at the head of the card.
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
    /// The width of « Reporter » and « Livré », measured: the place kept for them at the end of a dated line.
    @State private var actionsWidth: CGFloat = 120

    /// `opened`, `hovered`: a line unfolded, a line under the pointer, for the captures.
    init(todo: TodoLibrary, agenda: AgendaLibrary, router: WindowRouter, limit: Int = 6, opened: UUID? = nil, hovered: UUID? = nil) {
        self.todo = todo
        self.agenda = agenda
        self.router = router
        self.limit = limit
        _open = State(initialValue: opened)
        _hovered = State(initialValue: hovered)
    }

    private var calendar: Calendar { CalendarView.calendar }
    /// The actions shown in an unfolded line, before « + 1 autre », « + N autres ».
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
        let place = TodoText.hoverActions(dated: dated, unfolded: unfolded)
        let shown = place && hovered == line.id
        let when = TodoRules.when(line, now: now, calendar: calendar)
        return VStack(alignment: .leading, spacing: Space.s) {
            RowButton(action: { open = unfolded ? nil : line.id }) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(unfolded ? 90 : 0))
                        Text("\(Text(line.name).foregroundStyle(.primary).fontWeight(.medium))\(Text(line.client.map { " · \($0)" } ?? "").foregroundStyle(.secondary))")
                            .font(.rowTitle)
                            .lineLimit(1)
                        Spacer(minLength: Space.s)
                        if when != nil || place {
                            Text(when ?? "")
                                .font(.meta.monospacedDigit())
                                .fontWeight(late ? .semibold : .regular)
                                // « depuis 6 j »: late, in red (design system v2, 19/11).
                                .foregroundStyle(late ? AnyShapeStyle(Tint.late) : AnyShapeStyle(.secondary))
                                .lineLimit(1)
                                // Under the pointer, the buttons take its place, kept for them at rest (lot 5, 19/11).
                                .opacity(shown ? 0 : 1)
                                .frame(minWidth: place ? actionsWidth : 0, alignment: .trailing)
                        }
                    }
                    if !unfolded, let detail = line.detail {
                        // The whole task: no room is kept for buttons under it any more (lot 5, 19/11).
                        Text(detail).font(.meta).foregroundStyle(.secondary).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 17)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if place {
                    actions(line)
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { actionsWidth = $0 }
                        // On the first line, where the « quand » is.
                        .padding(.top, Space.xs / 2)
                        .opacity(shown ? 1 : 0)
                        .allowsHitTesting(shown)
                        .animation(Motion.quick, value: shown)
                }
            }
            .onHover { inside in hovered = inside ? line.id : (hovered == line.id ? nil : hovered) }
            .contextMenu {
                // The same gestures at the right click (lot 5, 19/11): `TodoText.menu`.
                Button("Ouvrir le projet") { router.openProject(line.id) }
                if dated {
                    Menu("Reporter") { postponeItems(line) }
                    if TodoRules.nextCall(line.id, events: agenda.shown, now: Date()) != nil {
                        Menu("Livré") { deliverItems(line) }
                    } else {
                        Button("Livré") { todo.deliver(line) }
                    }
                }
            }
            // « Voir » unfolds in place, « Voir moins » folds back (lot 10, 20/11).
            .help(unfolded ? "Voir moins" : "Voir ce qu'il y a à faire")
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
                .buttonStyle(.primary)
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
                // The field's own name, « Tâche du moment », never « Tâche » alone (lot 10, 20/11).
                Text("\(Text("Tâche du moment · ").foregroundStyle(.secondary))\(Text(task))").font(.rowBody)
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
                        // « + 1 autre », « + 3 autres »: the word accords with its number (lot 10, 20/11).
                        Text("+ " + Words.count(left.count - Self.actionsShown, "autre")).font(.meta).foregroundStyle(.secondary)
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

    /// « Reporter » (its choices, then « Choisir une date… ») and « Livré » (with the next call, a menu): one outline,
    /// small, as every button of a line (lot 5, 19/11).
    private func actions(_ line: TodoRules.Line) -> some View {
        HStack(spacing: Space.xs) {
            Menu { postponeItems(line) } label: { Text("Reporter") }
                .menuStyle(.button)
                .buttonStyle(.secondary)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Reporter l'échéance \(Words.of(line.name))")
            if TodoRules.nextCall(line.id, events: agenda.shown, now: Date()) != nil {
                Menu { deliverItems(line) } label: { Text("Livré") }
                    .menuStyle(.button)
                    .buttonStyle(.secondary)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    // « Verbe + objet », 60 characters at most, « visio » (lot 10, 20/11).
                    .help("Noter la livraison, puis la prochaine visio")
            } else {
                Button("Livré") { todo.deliver(line) }
                    .buttonStyle(.secondary)
                    .fixedSize()
                    // An échéance is « retirée », never « effacée » (lot 10, 20/11).
                    .help("Noter la livraison et retirer l'échéance")
            }
        }
        .controlSize(.small)
    }

    /// « Demain », « Lundi », « Dans une semaine », then « Choisir une date… ».
    @ViewBuilder
    private func postponeItems(_ line: TodoRules.Line) -> some View {
        let choices = TodoRules.postpone(due: line.due, now: Date(), calendar: calendar)
        ForEach(choices, id: \.date) { choice in
            Button(choice.label) { todo.postpone(line, to: choice) }
        }
        if !choices.isEmpty { Divider() }
        Button("Choisir une date…") {
            picked = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(Date(), line.due ?? Date()))) ?? Date()
            picking = line.id
        }
    }

    /// « Livré »: with the project's next call, the call as the new deadline or none; else at once, no deadline left.
    @ViewBuilder
    private func deliverItems(_ line: TodoRules.Line) -> some View {
        if let next = TodoRules.nextCall(line.id, events: agenda.shown, now: Date()) {
            Button(TodoRules.deliveredNext(next, now: Date(), calendar: calendar)) { todo.deliver(line, next: next) }
            Button("Livré, sans échéance") { todo.deliver(line) }
        } else {
            Button("Livré") { todo.deliver(line) }
        }
    }
}
