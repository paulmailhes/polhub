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

/// The words that just came, marked for the renderer.
struct FreshWords: TextAttribute {}

/// The words that just came fade in; the others stay still.
struct FreshRenderer: TextRenderer, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                if run[FreshWords.self] != nil {
                    var faded = context
                    faded.opacity = progress
                    faded.draw(run)
                } else {
                    context.draw(run)
                }
            }
        }
    }
}

/// Colin's text, 15 on 22. While it is written, the new words fade in over a fifth of a second.
struct AnswerText: View {
    let text: String
    var writing = false
    @State private var settled = 0
    @State private var progress: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .font(.rowTitle)
            .lineSpacing(4)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: text) { before, now in
                guard writing, !reduceMotion, now.hasPrefix(before) else {
                    settled = now.count
                    progress = 1
                    return
                }
                settled = before.count
                progress = 0
                withAnimation(.easeOut(duration: 0.2)) { progress = 1 }
            }
    }

    @ViewBuilder
    private var content: some View {
        if writing, settled < text.count {
            let cut = text.index(text.startIndex, offsetBy: settled)
            Text("\(Text(ColinAnswer.inline(String(text[..<cut]))))\(Text(String(text[cut...])).customAttribute(FreshWords()))")
                .textRenderer(FreshRenderer(progress: progress))
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
    let undo: () -> Void

    private var undone: Bool { outcome != nil || line.undoneAt != nil }

    var body: some View {
        ThreadCard {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Image(systemName: "checklist").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Text(verbatim: line.projectName).font(.meta.weight(.semibold))
                if let said { Text(verbatim: said).font(.meta).foregroundStyle(.secondary).lineLimit(1) }
                Spacer(minLength: Space.s)
                if !undone { Button("Annuler", action: undo).buttonStyle(.subtle) }
            }
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
                ChangeCard(line: line, outcome: thread.outcomes[line.id], calendar: calendar) { thread.undo(line) }
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
                TextButton("Copier", quiet: true) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ColinThreadText.note(of: message).said, forType: .string)
                }
                if stopped { TextButton("Réessayer", quiet: true) { thread.retry(message) } }
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
