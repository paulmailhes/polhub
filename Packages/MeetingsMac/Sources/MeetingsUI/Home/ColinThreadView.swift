import AppKit
import Colin
import Persistence
import HubDesign
import SwiftUI

/// Why an answer of Colin stopped before its end (lot 10, 20/11): a call, the Mac's sleep, Colin turned off. The answer
/// keeps it after its text, in the base, as `stored`: a format, never reworded, so the thread finds it again in the
/// answers of before; the thread says `note`, which may change.
enum ColinStop: CaseIterable, Sendable {
    case call, sleep, off

    /// What the base keeps after the answer (17/11): never changed.
    var stored: String {
        switch self {
        case .call: "Arrêté : ton call commence."
        case .sleep: "Arrêté : le Mac s'endort."
        case .off: "Arrêté : Colin est à l'arrêt."
        }
    }

    /// What the thread says under the answer (lot 10, 20/11): « visio », never « call »; Colin off says it once, without
    /// « Arrêté : » before it.
    var note: String {
        switch self {
        case .call: "Arrêté : ta visio commence."
        case .sleep: "Arrêté : le Mac s'endort."
        case .off: "Colin est à l'arrêt."
        }
    }

    /// The answer a stop ends, and the stop: from what the base kept; `nil` when it does not end with one.
    static func ending(_ text: String) -> (said: String, stop: ColinStop)? {
        for stop in allCases {
            if text == stop.stored { return ("", stop) }
            if text.hasSuffix("\n\n" + stop.stored) { return (String(text.dropLast(stop.stored.count + 2)), stop) }
        }
        return nil
    }
}

/// The words of Colin's thread and bar (18/11), apart from the views.
enum ColinThreadText {
    /// « Aujourd'hui », « Hier », then the date (« lundi 16 novembre », « lundi 1er décembre 2025 » another year). Written
    /// by `Words`, no formatter (lot 10, 20/11; final review, 18/11: the thread is drawn again at each word).
    static func day(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Aujourd'hui" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Hier" }
        return Words.fullDate(date, now: now, calendar: calendar)
    }

    /// What « Copier » under an answer gives: the text as read — no fences, no stars, no line to keep.
    static func plain(_ answer: String) -> String {
        ColinAnswer.blocks(answer).compactMap { block -> String? in
            switch block {
            case .text(let text): String(ColinAnswer.inline(text).characters)
            case .message(let text): text
            case .keep: nil
            }
        }
        .joined(separator: "\n\n")
    }

    /// What the thread shows: a message, or a change Colin made on a project (step 3, 18/11).
    enum Item: Identifiable {
        case message(ColinMessageRow)
        case change(ProjectChangeLine)

        var id: String {
            switch self {
            case .message(let message): message.id
            case .change(let line): "change-\(line.id)"
            }
        }

        var date: Date {
            switch self {
            case .message(let message): message.createdAt
            case .change(let line): line.at
            }
        }
    }

    /// The messages and the changes by day, each in its place by its time.
    static func sections(_ messages: [ColinMessageRow], changes: [ProjectChangeLine] = [], now: Date, calendar: Calendar) -> [(day: String, items: [Item])] {
        let items = (messages.map(Item.message) + changes.map(Item.change)).enumerated()
            .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }.map(\.element)
        var sections: [(day: String, items: [Item])] = []
        for item in items {
            let day = day(item.date, now: now, calendar: calendar)
            if sections.last?.day == day { sections[sections.count - 1].items.append(item) } else { sections.append((day, [item])) }
        }
        return sections
    }

    /// A piece of an answer: its text, or the actions it did there.
    enum Piece: Equatable {
        case text(String)
        case steps(StepGroup)
    }

    /// The text cut where each action began; an action not reached yet by the words shown waits at the end.
    static func pieces(_ text: String, groups: [StepGroup]) -> [Piece] {
        var pieces: [Piece] = []
        var from = text.startIndex
        func add(upTo end: String.Index) {
            let said = text[from..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            if !said.isEmpty { pieces.append(.text(said)) }
            from = end
        }
        for group in groups.sorted(by: { $0.position < $1.position }) {
            let cut = text.index(text.startIndex, offsetBy: min(max(group.position, 0), text.count))
            add(upTo: max(cut, from))
            pieces.append(.steps(group))
        }
        add(upTo: text.endIndex)
        return pieces
    }

    /// « a travaillé 9 s », « a travaillé 1 min 12 » (lot 10, 20/11: the length by `Words.preciseDuration`).
    static func worked(_ milliseconds: Int) -> String {
        "a travaillé " + Words.preciseDuration(max(1, Int((Double(milliseconds) / 1_000).rounded())))
    }

    /// What Colin changed while he answered goes with that answer (made between the question and the next message,
    /// by him, with no rule's reason); the rest — his rules, an agent's changes — stays lines at their time.
    static func attach(_ changes: [ProjectChangeLine], to messages: [ColinMessageRow]) -> (inAnswers: [String: [ProjectChangeLine]], loose: [ProjectChangeLine]) {
        let sorted = messages.sorted { $0.createdAt < $1.createdAt }
        var inAnswers: [String: [ProjectChangeLine]] = [:]
        var loose: [ProjectChangeLine] = []
        for change in changes {
            guard change.who == .colin, change.reason == nil,
                  let index = sorted.lastIndex(where: { $0.author == .colin && $0.createdAt <= change.at }),
                  index + 1 >= sorted.count || sorted[index + 1].createdAt > change.at else {
                loose.append(change)
                continue
            }
            inAnswers[sorted[index].id, default: []].append(change)
        }
        return (inAnswers, loose)
    }

    /// The last thing of the thread, where it scrolls to: the latest of its last message and its last change.
    static func lastID(_ messages: [ColinMessageRow], changes: [ProjectChangeLine]) -> String? {
        let message = messages.max { $0.createdAt < $1.createdAt }
        let change = changes.max { $0.at < $1.at }
        switch (message, change) {
        case let (message?, change?): return change.at > message.createdAt ? "change-\(change.id)" : message.id
        case let (message?, nil): return message.id
        case let (nil, change?): return "change-\(change.id)"
        case (nil, nil): return nil
        }
    }

    /// An answer, and what the thread says of its end apart, in small: why it stopped, or that it could not finish.
    static func note(of message: ColinMessageRow) -> (said: String, note: String?) {
        switch message.state {
        case .interrupted:
            // Why it stopped, found by the words the base keeps, said in the thread's own (lot 10, 20/11).
            if let ended = ColinStop.ending(message.text) { return (ended.said, ended.stop.note) }
            return (message.text, "Arrêté.")
        case .failed:
            return (message.text, "Colin n'a pas pu finir.")
        case .done, .answering:
            return (message.text, nil)
        }
    }

    /// The start of an answer (lot 5, 19/11): its first line as Paul reads it — no stars, no fences, never the note of
    /// its end —, for the head of the narrow window's bar.
    static func opening(_ message: ColinMessageRow) -> String? {
        plain(note(of: message).said).components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    /// Whether an answer holds a message to copy: its card has « Copier », its foot does not (lot 5, 19/11).
    static func copiesInItsCard(_ answer: String) -> Bool {
        ColinAnswer.blocks(answer).contains { block in
            if case .message = block { return true }
            return false
        }
    }

    /// The foot of an answer (lot 5, 19/11): how it ended, « Copier » once — unless its card copies —, « Réessayer » once
    /// stopped and Colin on.
    struct Foot: Equatable {
        var note: String?
        var copy: Bool
        var retry: Bool

        /// An empty foot takes no room.
        var isEmpty: Bool { note == nil && !copy && !retry }
    }

    static func foot(of message: ColinMessageRow, colinOn: Bool) -> Foot {
        let (said, note) = note(of: message)
        let stopped = message.state == .interrupted || message.state == .failed
        let copy = message.state != .answering && !said.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !copiesInItsCard(said)
        return Foot(note: note, copy: copy, retry: stopped && colinOn)
    }

    enum Bar: Equatable {
        case field(placeholder: String, enabled: Bool, note: String?)
        /// Colin off: « Mettre Colin en marche » in place of the bar.
        case turnOn
    }

    static let ask = "Écris ou dicte à Colin…"

    static func bar(_ status: ColinThread.Status) -> Bar {
        switch status {
        case .off: .turnOn
        // « visio », never « call » (lot 10, 20/11).
        case .waitingCall: .field(placeholder: ask, enabled: false, note: "Colin attend la fin de ta visio.")
        case .settling: .field(placeholder: ask, enabled: true, note: "Le Mac vient de se réveiller : Colin répond dans un instant.")
        case .broken(let sentence): .field(placeholder: ask, enabled: true, note: sentence)
        case .idle, .starting, .working: .field(placeholder: ask, enabled: true, note: nil)
        }
    }
}

/// Colin's thread (the Accueil's pass, 18/11): a reading column, the days between two lines, Paul's questions in
/// bubbles, Colin's answers in clear text with his actions in their places and the cards of what he changed; the
/// changes of his rules and of the agents at their time.
struct ColinThreadView: View {
    @ObservedObject var thread: ColinThread
    let mails: MailLibrary?
    @ObservedObject var router: WindowRouter
    var calendar: Calendar = CalendarView.calendar

    var body: some View {
        let split = ColinThreadText.attach(thread.changes, to: thread.messages)
        let sections = ColinThreadText.sections(thread.messages, changes: split.loose, now: Date(), calendar: calendar)
        let lastAnswer = thread.messages.last(where: { $0.author == .colin })?.id
        VStack(alignment: .leading, spacing: 0) {
            if thread.messages.count >= 100 {
                TextButton("Voir les échanges d'avant", quiet: true) { thread.loadEarlier() }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, Space.s)
            }
            ForEach(Array(sections.enumerated()), id: \.element.day) { index, section in
                DaySeparator(day: section.day).padding(.top, index == 0 ? 0 : ThreadMetrics.turn)
                ForEach(section.items) { item in
                    switch item {
                    case .message(let message) where message.author == .paul:
                        PaulBubble(message: message, calendar: calendar).padding(.top, ThreadMetrics.turn).id(item.id)
                    case .message(let message):
                        ColinAnswerView(message: message, thread: thread, mails: mails, router: router, changes: split.inAnswers[message.id] ?? [],
                                        isLast: message.id == lastAnswer, calendar: calendar)
                            .padding(.top, ThreadMetrics.inTurn)
                            .id(item.id)
                    case .change(let line):
                        // A rule's change says why; an agent's, who made it.
                        ChangeCard(line: line, outcome: thread.outcomes[line.id], calendar: calendar,
                                   byline: line.who == .colin ? nil : ChangeText.byline(line, now: Date(), calendar: calendar),
                                   open: { router.openProject(line.projectID) }) { thread.undo(line) }
                            .padding(.top, ThreadMetrics.inTurn)
                            .id(item.id)
                    }
                }
            }
        }
        .frame(maxWidth: ThreadMetrics.column)
        .frame(maxWidth: .infinity)
        .animation(Motion.standard, value: thread.messages.count + thread.changes.count)
    }
}

/// Colin's bar (the Accueil's pass, 18/11): a glass capsule of 44 points, its text centred on one line, growing up
/// to eight; the round send button at its foot (■ while he answers). Return sends, Shift-Return goes to
/// the line, Escape stops. Why it waits is said above the field, in the glass; off, a calm card to turn Colin on.
/// In a narrow window (lot 5, 19/11), it floats at the foot of the day: a line at its head says Colin's state or the start
/// of his last answer; a click on it, or a question sent, opens the thread over the day.
struct ColinComposer: View {
    @ObservedObject var thread: ColinThread
    /// The day, for the suggestions: who waits, what is due.
    var review: [ReviewRules.Line] = []
    var due: [String] = []
    /// Given as they are (captures); else from the day.
    var suggestions: [String]?
    /// The narrow window: the line at the head of the bar, and what opens the thread.
    var open: (() -> Void)?
    @FocusState private var focused: Bool

    private var empty: Bool { thread.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        Group {
            switch ColinThreadText.bar(thread.status) {
            case .turnOn:
                ColinOffCard(open: open) { thread.turnOn() }
            case .field(let placeholder, let enabled, let note):
                let asked = suggestions ?? thread.suggestions(review: review, due: due)
                VStack(alignment: .leading, spacing: Space.s) {
                    if enabled, empty, !thread.isAnswering, !asked.isEmpty {
                        SuggestionChips(suggestions: asked) { thread.fill($0); focused = true }
                    }
                    field(placeholder: placeholder, enabled: enabled, note: note)
                }
            }
        }
        .frame(maxWidth: ThreadMetrics.column)
        .frame(maxWidth: .infinity)
        .onChange(of: focused) { _, now in if now { thread.focused() } }
    }

    /// A question sent from the narrow window's bar opens the thread: the answer is read as it comes.
    private func send() {
        guard !empty else { return }
        thread.send()
        open?()
    }

    private func field(placeholder: String, enabled: Bool, note: String?) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let open { ColinBarLine(thread: thread, open: open) }
            if let note {
                // A sentence, often with its « : »: French typography (lot 10, 20/11).
                Text(Words.typeset(note)).font(.meta).foregroundStyle(.secondary).padding(.horizontal, Space.s).padding(.top, 2)
            }
            HStack(alignment: .bottom, spacing: Space.s) {
                TextField(placeholder, text: $thread.draft, axis: .vertical)
                    .font(.rowTitle)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    // As tall as the buttons on one line: the text sits in the middle, the buttons at the foot after.
                    .padding(.vertical, 5)
                    .padding(.leading, Space.s)
                    .focused($focused)
                    .disabled(!enabled)
                    .onKeyPress(keys: [.return, .escape]) { press in
                        switch ComposerKeys.action(key: press.key, modifiers: press.modifiers, composing: ComposerKeys.composing,
                                                   answering: thread.isAnswering) {
                        case .send:
                            send()
                            return .handled
                        case .newline:
                            thread.draft += "\n"
                            return .handled
                        case .stop:
                            thread.stop()
                            return .handled
                        case .none:
                            return press.key == .return && !ComposerKeys.composing ? .handled : .ignored
                        }
                    }
                // No « Dicter » for now (Paul, 18/11): Polhub's own dictation will come, on Whisper. VoiceInk writes here
                // as anywhere else.
                // The keys of the field, said in the bubbles: Échap stops, Return sends (lot 10, 20/11).
                if thread.isAnswering {
                    RoundButton(symbol: "stop.fill", help: "Arrêter la réponse", prominent: false, shortcut: .escape) { thread.stop() }
                } else {
                    RoundButton(symbol: "arrow.up", help: "Envoyer à Colin", prominent: !empty && enabled, shortcut: .return) { send() }
                        .disabled(!enabled || empty)
                }
            }
        }
        .padding(Space.s)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

/// The head of Colin's bar in a narrow window (lot 5, 19/11): his state's dot, « Colin », then his state, or, ready, the
/// start of his last answer; ⌃ says it opens. A click opens his thread over the day.
struct ColinBarLine: View {
    @ObservedObject var thread: ColinThread
    let open: () -> Void

    var body: some View {
        let state = ColinState(thread.status, answering: thread.isAnswering)
        let last = thread.messages.last { $0.author == .colin && $0.state != .answering }.flatMap(ColinThreadText.opening)
        Button(action: open) {
            HStack(spacing: Space.s) {
                ColinStateDot(state: state)
                Text("\(Text("Colin").fontWeight(.semibold).foregroundStyle(.primary)) · \(ColinState.barLine(state, lastAnswer: last))")
                    .font(.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: Space.s)
                Image(systemName: "chevron.up").font(.tag.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.row)
        .help("Ouvrir le fil de Colin")
    }
}

/// A round button of the bar, 28 points: filled with the accent when it is the one to press, quiet otherwise. The
/// accent is Polhub's ink, its arrow the accent's opposite (design system v2, 19/11).
private struct RoundButton: View {
    let symbol: String
    /// What it does: the bubble and VoiceOver's name.
    let help: String
    let prominent: Bool
    /// The key that does it in the bar, said in the bubble only, « Envoyer à Colin (↩) », as `IconButton` (lot 10, 20/11).
    var shortcut: Words.Shortcut?
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.tag.weight(.bold))
                .foregroundStyle(prominent ? Tint.onAccent.color : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 28, height: 28)
                .background(prominent ? Tint.accent : Color.primary.opacity(enabled ? 0.08 : 0.04), in: Circle())
        }
        .buttonStyle(.plain)
        .help(Words.help(help, shortcuts: shortcut.map { [$0] } ?? []))
        .accessibilityLabel(help)
    }
}

/// What to ask Colin, from the day: a click puts it in the bar, it is not sent.
private struct SuggestionChips: View {
    let suggestions: [String]
    let pick: (String) -> Void

    var body: some View {
        // Whole, side by side; scrolled when they do not fit.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(suggestions, id: \.self) { said in
                    Button { pick(said) } label: {
                        // « Qui attend ma réponse ? »: French typography on the chip, the bar gets the words as they are
                        // (lot 10, 20/11).
                        Text(Words.typeset(said)).font(.meta).lineLimit(1).fixedSize().padding(.horizontal, Space.m).padding(.vertical, 6)
                            .background(Surface.fill, in: Capsule())
                            .overlay { Capsule().strokeBorder(Surface.stroke) }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Space.xs)
        }
    }
}

/// Colin off: the bar becomes « Colin est à l'arrêt » and « Mettre Colin en marche », in the same glass (lot 5, 19/11). In a
/// narrow window, its sentence opens the thread over the day.
private struct ColinOffCard: View {
    var open: (() -> Void)?
    let turnOn: () -> Void

    var body: some View {
        HStack(spacing: Space.m) {
            if let open {
                Button(action: open) {
                    HStack(spacing: Space.m) {
                        said
                        Image(systemName: "chevron.up").font(.tag.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Ouvrir le fil de Colin")
            } else {
                said
            }
            Spacer(minLength: Space.s)
            // An outline, no glass on the glass: « Rejoindre » is the Accueil's one principal button (design system v2, 19/11).
            // Colin is « en marche » or « à l'arrêt », never « allumé » (lot 10, 20/11).
            Button("Mettre Colin en marche", action: turnOn).buttonStyle(.secondary).controlSize(.small)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private var said: some View {
        HStack(spacing: Space.m) {
            Image(systemName: "moon.zzz").foregroundStyle(.secondary)
            Text("Colin est à l'arrêt").font(.rowBody).foregroundStyle(.secondary)
        }
    }
}
