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
    /// Room always left beside Paul's bubble: it never takes the whole column. 64 points in a panel of 420 (lot 5, 19/11).
    static let bubbleGap: CGFloat = 64
    static let turn: CGFloat = Space.xl
    static let inTurn: CGFloat = 10
    /// The fade at the top of the thread, under the line of the panel's head (lot 5, 19/11).
    static let fade: CGFloat = Space.l
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
                .background(Surface.bubble, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                // When Paul asked, under the pointer: the day and its hour by `Words` (lot 10, 20/11).
                .help(Words.moment(message.createdAt, now: Date(), calendar: calendar))
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
                        .font(.tag.weight(.medium))
                        .symbolEffect(.pulse, isActive: group.running)
                        // A failure: the icon of attention, its sentence grey (design system v2, 19/11).
                        .foregroundStyle(group.failed ? Tint.attention : Color.secondary)
                        .frame(width: 16)
                    Text(verbatim: group.running ? ColinStepText.present(group, subject: subject) : ColinStepText.past(group, subject: subject))
                        .font(.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !group.running, details.count > 1 {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
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
            Image(systemName: "sparkle").font(.tag.weight(.medium)).symbolEffect(.pulse, isActive: true)
                .foregroundStyle(.secondary).frame(width: 16)
            Text("Réfléchit…").font(.meta).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Cards

/// What a card of Colin's thread is (lot 5, 19/11), said at its head: one grammar for all — what it is, then the thing
/// in 15 points semi-bold.
enum ResultCard: Equatable {
    case message, draft, change, creation

    var label: String {
        switch self {
        case .message: "Message à copier"
        case .draft: "Brouillon"
        case .change: "Projet modifié"
        case .creation: "Nouveau projet"
        }
    }

    static func of(_ line: ProjectChangeLine) -> ResultCard {
        ChangeText.isCreation(line) ? .creation : .change
    }

    /// Whom a draft is for: « Pour Claire ».
    static func draftFor(_ to: [MailAddress]) -> String {
        "Pour \(to.first.map { ReviewRules.short($0.display) } ?? "toi")"
    }
}

/// The frame of a card in the thread: a thin line, no glass. On the window's own ground, so that it stands out of Colin's
/// grey panel (lot 5, 19/11).
private struct ThreadCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) { content }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: Radius.inner, style: .continuous).strokeBorder(Surface.stroke) }
    }
}

/// The head of a card (lot 5, 19/11): what it is, in a grey label of 12 points; its action on the right, a small outline.
private struct CardHead<Action: View>: View {
    let card: ResultCard
    @ViewBuilder var action: Action

    var body: some View {
        HStack(alignment: .center, spacing: Space.s) {
            Text(card.label).font(.tag.weight(.semibold)).foregroundStyle(.secondary)
            Spacer(minLength: Space.s)
            action.controlSize(.small)
        }
    }
}

/// What a change did to a project: « Projet modifié » or « Nouveau projet », its name, why or by whom, a line by field
/// before → after, then « Annuler », a grey word (lot 5, 19/11).
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
        let card = ResultCard.of(line)
        ThreadCard {
            CardHead(card: card) {
                if card == .creation, !undone, let open { Button("Ouvrir le projet", action: open).buttonStyle(.secondary) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: line.projectName).font(.rowTitle.weight(.semibold)).lineLimit(2)
                if let why = byline ?? ChangeText.note(line) {
                    Text(verbatim: why).font(.meta).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .opacity(undone ? 0.5 : 1)
            fieldLines
            if let done {
                Text(verbatim: done).font(.meta).foregroundStyle(.secondary)
            } else {
                TextButton("Annuler", quiet: true, action: undo)
            }
        }
    }

    private var fieldLines: some View {
        ForEach(Array(ChangeText.fields(line, calendar: calendar).enumerated()), id: \.offset) { _, field in
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                // Wide enough for « Tâche du moment » on one line, the field's name (lot 10, 20/11: « Tâche », 64 before).
                Text(verbatim: field.label).font(.meta).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                if let before = field.before {
                    Text(verbatim: before).font(.meta).foregroundStyle(.secondary).lineLimit(1)
                    Image(systemName: "arrow.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                }
                Text(verbatim: field.after ?? "retiré").font(.meta.weight(.medium)).lineLimit(2)
            }
            .opacity(undone ? 0.5 : 1)
        }
    }

    /// What « Annuler » did, once done.
    private var done: String? {
        if let outcome { return ChangeText.undone(outcome) }
        if line.undoneAt != nil { return ChangeText.undone(.undone) }
        return nil
    }
}

/// A draft the answer prepared, still a draft: « Brouillon », whom it is for and its subject; « Relire » opens it over the
/// Accueil.
struct DraftCard: View {
    let draft: MailDraftRow
    let open: () -> Void

    var body: some View {
        ThreadCard {
            CardHead(card: .draft) { Button("Relire", action: open).buttonStyle(.secondary) }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: ResultCard.draftFor(draft.to)).font(.rowTitle.weight(.semibold)).lineLimit(1)
                if !draft.subject.isEmpty { Text(verbatim: draft.subject).font(.meta).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
    }
}

/// A message to copy (a WhatsApp, an SMS): « Message à copier » and « Copier » at its head, which says it copied, then
/// its text (lot 5, 19/11: « Copier » no longer takes a line of its own at the bottom).
struct CopyCard: View {
    let text: String
    @State private var copied = false

    var body: some View {
        ThreadCard {
            CardHead(card: .message) {
                Button(copied ? "Copié" : "Copier") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                }
                .buttonStyle(.secondary)
            }
            Text(text).font(.rowTitle).lineSpacing(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
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
            Image(systemName: "bookmark").font(.tag.weight(.medium)).foregroundStyle(.secondary).frame(width: 16)
            Text(line).font(.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.s)
            if !known { Button("Garder", action: keep).buttonStyle(.secondary).controlSize(.small) }
        }
    }
}

// MARK: - An answer

/// One answer of Colin's, from its first word to its foot: the text with his actions in their places, the cards of
/// what he changed and prepared, how it ended, and its foot (« Copier », « Réessayer »); how long he worked under the
/// pointer.
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
        let foot = ColinThreadText.foot(of: message, colinOn: thread.isOn)
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
            // An empty foot takes no room (lot 5, 19/11: it left about 40 points under a card).
            if !writing, !foot.isEmpty { self.foot(foot) }
        }
        .onHover { hovering = $0 }
        // How long he worked: under the pointer, never in the way (lot 5, 19/11).
        .help(message.durationMs.map(ColinThreadText.worked) ?? "")
    }

    @ViewBuilder
    private func block(_ block: ColinAnswer.Block, writing: Bool) -> some View {
        switch block {
        case .text(let said): AnswerText(text: said, writing: writing)
        case .message(let said): CopyCard(text: said)
        case .keep(let line): KeepLine(line: line, known: thread.knows(line)) { try? thread.keep(line) }
        }
    }

    /// How it ended, always; « Copier » — unless its card copies — and « Réessayer » on the last answer, under the pointer
    /// on the others, in a room kept for them: nothing moves.
    private func foot(_ foot: ColinThreadText.Foot) -> some View {
        let shown = isLast || hovering
        return HStack(spacing: Space.m) {
            // « Arrêté : ta visio commence. »: a sentence with its « : », French typography (lot 10, 20/11).
            if let note = foot.note { Text(Words.typeset(note)).font(.meta).foregroundStyle(.secondary) }
            if foot.copy {
                TextButton(copied ? "Copié" : "Copier", quiet: true) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ColinThreadText.plain(ColinThreadText.note(of: message).said), forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                }
                .opacity(shown ? 1 : 0)
                .allowsHitTesting(shown)
            }
            if foot.retry {
                TextButton("Réessayer", quiet: true) { thread.retry(message) }
                    .opacity(shown ? 1 : 0)
                    .allowsHitTesting(shown)
            }
        }
    }
}

/// ↓: back to the end of the thread, when Paul went up to read.
struct JumpToEnd: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down").font(.meta.weight(.semibold)).frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .help("Revenir à la fin")
        // An icon alone: VoiceOver says what the bubble says (lot 10, 20/11).
        .accessibilityLabel("Revenir à la fin")
    }
}
