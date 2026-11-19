import AppKit
import Colin
import Persistence
import PolhubDesign
import SwiftUI

// The pieces of Colin's thread (the Accueil's pass, 18/11): Paul's bubble, the days, an answer with its actions in
// its text, the cards of what it changed or prepared, its foot. Nothing here is glass: the thread is content.

/// The width of the thread's reading column, at most.
enum ThreadMetrics {
    static let column: CGFloat = 680
    /// Room always left beside Paul's bubble: it never takes the whole column.
    static let bubbleGap: CGFloat = 140
    static let turn: CGFloat = Space.xl
    static let inTurn: CGFloat = 10
}

// MARK: - Paul

struct PaulBubble: View {
    let message: ColinMessageRow
    let calendar: Calendar

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: ThreadMetrics.bubbleGap)
            Text(message.text)
                .font(.rowTitle)
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Surface.bubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .help(Briefing.dayLabel(message.createdAt, now: Date(), calendar: calendar))
        }
    }
}

/// « Aujourd'hui », between two thin lines.
struct DaySeparator: View {
    let day: String

    var body: some View {
        HStack(spacing: Space.m) {
            Rectangle().fill(Surface.stroke).frame(height: 1)
            Text(day).font(.meta.weight(.semibold)).foregroundStyle(.secondary).fixedSize()
            Rectangle().fill(Surface.stroke).frame(height: 1)
        }
    }
}

// MARK: - Text that writes itself

/// The words of each pace, and when they came: they fade in over a fifth of a second from their own arrival (final
/// review, 18/11).
enum FreshText {
    static let fade: TimeInterval = 0.2
    /// How long after the last arrival the view empties its list, which stops its timeline.
    static let settles: TimeInterval = 0.25

    /// The arrivals still fading in.
    static func fading(_ arrivals: [Arrival], now: Date) -> [Arrival] {
        arrivals.filter { now.timeIntervalSince($0.at) < fade }
    }

    struct Arrival: Equatable {
        var offset: Int
        var at: Date
    }

    struct Segment: Equatable {
        var range: Range<Int>
        var opacity: Double
    }

    /// The text cut by arrival: what came more than a fade ago is settled (opacity 1).
    static func segments(count: Int, arrivals: [Arrival], now: Date) -> [Segment] {
        let fresh = arrivals.filter { now.timeIntervalSince($0.at) < fade && $0.offset < count }.sorted { $0.offset < $1.offset }
        var segments: [Segment] = []
        let settled = fresh.first?.offset ?? count
        if settled > 0 { segments.append(Segment(range: 0..<settled, opacity: 1)) }
        for (index, arrival) in fresh.enumerated() {
            let end = index + 1 < fresh.count ? fresh[index + 1].offset : count
            guard end > arrival.offset else { continue }
            let opacity = max(0, min(1, now.timeIntervalSince(arrival.at) / fade))
            segments.append(Segment(range: arrival.offset..<end, opacity: (opacity * 100).rounded() / 100))
        }
        return segments
    }
}

/// The opacity of a run of words still fading in.
struct FreshWords: TextAttribute {
    var opacity: Double
}

/// The words still fading in are drawn at their opacity; the others stay still.
struct FreshRenderer: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                if let fresh = run[FreshWords.self] {
                    var faded = context
                    faded.opacity = fresh.opacity
                    faded.draw(run)
                } else {
                    context.draw(run)
                }
            }
        }
    }
}

/// Colin's text, 15 on 22. While it is written, each pace's words fade in over a fifth of a second from their arrival.
struct AnswerText: View {
    let text: String
    var writing = false
    @State private var arrivals: [FreshText.Arrival] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: arrivals.isEmpty)) { context in
            content(now: context.date)
        }
        .font(.rowTitle)
        .lineSpacing(4)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: text) { before, now in
            let date = Date()
            arrivals = FreshText.fading(arrivals, now: date)
            guard writing, !reduceMotion, now.hasPrefix(before), now.count > before.count else {
                arrivals = []
                return
            }
            arrivals.append(FreshText.Arrival(offset: before.count, at: date))
        }
        // The last words have faded in: the list empties and the timeline stops (19/11: it was emptied only when the
        // text changed, so the animation ran on at the screen's rate for as long as the answer showed).
        .task(id: arrivals.last?.at) {
            guard !arrivals.isEmpty else { return }
            try? await Task.sleep(for: .seconds(FreshText.settles))
            guard !Task.isCancelled else { return }
            arrivals = FreshText.fading(arrivals, now: Date())
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let segments = FreshText.segments(count: text.count, arrivals: arrivals, now: now)
        if writing, segments.count > 1 {
            let characters = Array(text)
            segments.reduce(Text(verbatim: "")) { said, segment in
                let piece = String(characters[segment.range])
                let part = segment.opacity >= 1 ? Text(ColinAnswer.inline(piece)) : Text(piece).customAttribute(FreshWords(opacity: segment.opacity))
                return Text("\(said)\(part)")
            }
            .textRenderer(FreshRenderer())
        } else {
            Text(ColinAnswer.inline(text))
        }
    }
}

// MARK: - What Colin does

/// One action of Colin's, in his text: in the present with its icon beating while it runs, in the past once done;
/// several reads in a row open on what they read.
struct StepRow: View {
    let group: StepGroup
    let subject: (ColinStep) -> StepSubject
    @State private var open = false

    private var details: [String] {
        group.steps.compactMap { step in
            let said = subject(step)
            return said.title ?? said.project ?? step.arguments["texte"]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Button {
                if !group.running, details.count > 1 { withAnimation(Motion.quick) { open.toggle() } }
            } label: {
                HStack(spacing: Space.s) {
                    Image(systemName: ColinStepText.symbol(group.tool))
                        .font(.system(size: 12, weight: .medium))
                        .symbolEffect(.pulse, isActive: group.running)
                        .foregroundStyle(group.failed ? Color.red : Color.secondary)
                        .frame(width: 16)
                    Text(verbatim: group.running ? ColinStepText.present(group, subject: subject) : ColinStepText.past(group, subject: subject))
                        .font(.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !group.running, details.count > 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(open ? 90 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(details.enumerated()), id: \.offset) { _, detail in
                        Text(verbatim: detail).font(.meta).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                .padding(.leading, 24)
            }
        }
    }
}

/// « Réfléchit… », before the first word or the first action.
struct ThinkingRow: View {
    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "sparkle").font(.system(size: 12, weight: .medium)).symbolEffect(.pulse, isActive: true)
                .foregroundStyle(.secondary).frame(width: 16)
            Text("Réfléchit…").font(.meta).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Cards

/// The frame of a card in the thread: a thin line, no glass.
private struct ThreadCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) { content }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Surface.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Surface.stroke) }
    }
}

/// What a change did to a project: its name, why or by whom, a line by field before → after, and « Annuler ».
struct ChangeCard: View {
    let line: ProjectChangeLine
    let outcome: UndoOutcome?
    var calendar: Calendar = CalendarView.calendar
    /// Who made it and when, for a change that is not Colin's own in his answer.
    var byline: String?
    /// « Ouvrir le projet », on a project created (19/11).
    var open: (() -> Void)?
    let undo: () -> Void

    private var undone: Bool { outcome != nil || line.undoneAt != nil }

    var body: some View {
        ThreadCard {
            if ChangeText.isCreation(line) { creation } else { header }
            fieldLines
        }
    }

    /// A project created, put forward (19/11): « Nouveau projet », its name in large, « Ouvrir le projet » and « Annuler ».
    private var creation: some View {
        HStack(alignment: .center, spacing: Space.m) {
            Image(systemName: "folder.badge.plus").font(.system(size: 18, weight: .medium)).foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: said ?? "Nouveau projet").font(.meta).foregroundStyle(.secondary).lineLimit(1)
                Text(verbatim: line.projectName).font(.rowTitle.weight(.semibold)).lineLimit(2)
            }
            .opacity(undone ? 0.5 : 1)
            Spacer(minLength: Space.s)
            if !undone {
                if let open { Button("Ouvrir le projet", action: open).buttonStyle(.subtle) }
                Button("Annuler", action: undo).buttonStyle(.subtle)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Image(systemName: "checklist").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text(verbatim: line.projectName).font(.meta.weight(.semibold))
            if let said { Text(verbatim: said).font(.meta).foregroundStyle(.secondary).lineLimit(1) }
            Spacer(minLength: Space.s)
            if !undone { Button("Annuler", action: undo).buttonStyle(.subtle) }
        }
    }

    private var fieldLines: some View {
        ForEach(Array(ChangeText.fields(line, calendar: calendar).enumerated()), id: \.offset) { _, field in
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(verbatim: field.label).font(.meta).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                if let before = field.before {
                    Text(verbatim: before).font(.meta).foregroundStyle(.secondary).lineLimit(1)
                    Image(systemName: "arrow.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                }
                Text(verbatim: field.after ?? "retiré").font(.meta.weight(.medium)).lineLimit(2)
            }
            .opacity(undone ? 0.5 : 1)
        }
    }

    /// Once undone, what « Annuler » did; else who made it, or why.
    private var said: String? {
        if let outcome { return ChangeText.undone(outcome) }
        if line.undoneAt != nil { return ChangeText.undone(.undone) }
        return byline ?? ChangeText.note(line)
    }
}

/// A draft the answer prepared, still a draft: « Relire » opens it over the Accueil.
struct DraftCard: View {
    let draft: MailDraftRow
    let open: () -> Void

    var body: some View {
        ThreadCard {
            HStack(spacing: Space.s) {
                Image(systemName: "square.and.pencil").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Text(verbatim: "Brouillon prêt pour \(draft.to.first.map { ReviewRules.short($0.display) } ?? "toi")").font(.meta.weight(.semibold))
                Spacer(minLength: Space.s)
                Button("Relire", action: open).buttonStyle(.subtle)
            }
        }
    }
}

/// A message to copy (a WhatsApp, an SMS): its text, and « Copier », which says it copied.
struct CopyCard: View {
    let text: String
    @State private var copied = false

    var body: some View {
        ThreadCard {
            Text(text).font(.rowTitle).lineSpacing(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(copied ? "Copié" : "Copier") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                }
                .buttonStyle(.subtle)
            }
        }
    }
}

/// A thing to remember: « Garder » adds it to « Ce que Colin sait ».
struct KeepLine: View {
    let line: String
    let known: Bool
    let keep: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Image(systemName: "bookmark").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).frame(width: 16)
            Text(line).font(.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.s)
            if !known { Button("Garder", action: keep).buttonStyle(.subtle) }
        }
    }
}

// MARK: - An answer

/// One answer of Colin's, from its first word to its foot: the text with his actions in their places, the cards of
/// what he changed and prepared, how it ended, and its foot (how long he worked, « Copier », « Réessayer »).
struct ColinAnswerView: View {
    let message: ColinMessageRow
    @ObservedObject var thread: ColinThread
    let mails: MailLibrary?
    @ObservedObject var router: WindowRouter
    let changes: [ProjectChangeLine]
    let isLast: Bool
    let calendar: Calendar
    @State private var hovering = false
    @State private var copied = false

    private var writing: Bool { message.state == .answering }
    private var text: String { writing ? thread.visible : ColinThreadText.note(of: message).said }
    private var steps: [ColinStep] { writing ? thread.liveSteps : message.steps }

    var body: some View {
        VStack(alignment: .leading, spacing: ThreadMetrics.inTurn) {
            if writing, thread.visible.isEmpty, thread.liveSteps.isEmpty { ThinkingRow() }
            ForEach(Array(ColinThreadText.pieces(text, groups: ColinStepText.groups(steps)).enumerated()), id: \.offset) { index, piece in
                switch piece {
                case .text(let said):
                    let last = index == ColinThreadText.pieces(text, groups: ColinStepText.groups(steps)).count - 1
                    ForEach(Array(ColinAnswer.blocks(said, open: writing && last).enumerated()), id: \.offset) { _, block in
                        self.block(block, writing: writing && last)
                    }
                case .steps(let group):
                    StepRow(group: group, subject: thread.subject)
                }
            }
            ForEach(message.drafts, id: \.self) { id in
                if let mails, let draft = mails.drafts.first(where: { $0.id == id }) {
                    DraftCard(draft: draft) { mails.open(draft) { router.homeMail = $0 } }
                }
            }
            ForEach(changes) { line in
                ChangeCard(line: line, outcome: thread.outcomes[line.id], calendar: calendar, open: { router.openProject(line.projectID) }) { thread.undo(line) }
            }
            if !writing { foot }
        }
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private func block(_ block: ColinAnswer.Block, writing: Bool) -> some View {
        switch block {
        case .text(let said): AnswerText(text: said, writing: writing)
        case .message(let said): CopyCard(text: said)
        case .keep(let line): KeepLine(line: line, known: thread.knows(line)) { try? thread.keep(line) }
        }
    }

    /// How it ended, and what can be done with it.
    private var foot: some View {
        let (_, note) = ColinThreadText.note(of: message)
        let stopped = message.state == .interrupted || message.state == .failed
        return HStack(spacing: Space.m) {
            if let note { Text(note).font(.meta).foregroundStyle(.secondary) }
            if let duration = message.durationMs, !stopped { Text(ColinThreadText.worked(duration)).font(.meta).foregroundStyle(.tertiary) }
            if isLast || hovering {
                TextButton(copied ? "Copié" : "Copier", quiet: true) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ColinThreadText.plain(ColinThreadText.note(of: message).said), forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                }
                if stopped, thread.isOn { TextButton("Réessayer", quiet: true) { thread.retry(message) } }
            }
        }
        .frame(minHeight: 18)
    }
}

/// ↓: back to the end of the thread, when Paul went up to read.
struct JumpToEnd: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down").font(.system(size: 13, weight: .semibold)).frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .help("Revenir à la fin")
    }
}
