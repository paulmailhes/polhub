import AppKit
import Colin
import Persistence
import PolhubDesign
import SwiftUI

/// The words of Colin's thread and bar (18/11), apart from the views.
enum ColinThreadText {
    /// « Aujourd'hui », « Hier », then the date (« lundi 16 novembre »).
    static func day(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Aujourd'hui" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Hier" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: date)
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

    /// « a travaillé 9 s », « a travaillé 1 min 12 ».
    static func worked(_ milliseconds: Int) -> String {
        let seconds = max(1, Int((Double(milliseconds) / 1_000).rounded()))
        return seconds < 60 ? "a travaillé \(seconds) s" : "a travaillé \(seconds / 60) min \(String(format: "%02d", seconds % 60))"
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

    /// The last thing of the thread, where it scrolls to.
    static func lastID(_ messages: [ColinMessageRow], changes: [ProjectChangeLine]) -> String? {
        sections(messages, changes: changes, now: Date(), calendar: Calendar(identifier: .gregorian)).last?.items.last?.id
    }

    /// An answer, and what the thread says of its end apart, in small: why it stopped, or that it could not finish.
    static func note(of message: ColinMessageRow) -> (said: String, note: String?) {
        switch message.state {
        case .interrupted:
            let parts = message.text.components(separatedBy: "\n\n")
            if let last = parts.last, last.hasPrefix("Arrêté :") { return (parts.dropLast().joined(separator: "\n\n"), last) }
            return (message.text, "Arrêté.")
        case .failed:
            return (message.text, "Colin n'a pas pu finir.")
        case .done, .answering:
            return (message.text, nil)
        }
    }

    enum Bar: Equatable {
        case field(placeholder: String, enabled: Bool, note: String?)
        /// Colin off: « Allumer Colin » in place of the bar.
        case turnOn
    }

    static let ask = "Écris ou dicte à Colin…"

    static func bar(_ status: ColinThread.Status) -> Bar {
        switch status {
        case .off: .turnOn
        case .waitingCall: .field(placeholder: ask, enabled: false, note: "Colin attend la fin de ton call.")
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
                                   byline: line.who == .colin ? nil : ChangeText.byline(line, now: Date(), calendar: calendar)) { thread.undo(line) }
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
/// to eight; « Dicter » and the round send button at its foot (■ while he answers). Return sends, Shift-Return goes to
/// the line, Escape stops. Why it waits is said above the field, in the glass; off, a calm card to turn Colin on.
struct ColinComposer: View {
    @ObservedObject var thread: ColinThread
    /// The day, for the suggestions: who waits, what is due.
    var review: [ReviewRules.Line] = []
    var due: [String] = []
    /// Given as they are (captures); else from the day.
    var suggestions: [String]?
    @FocusState private var focused: Bool

    private var empty: Bool { thread.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        Group {
            switch ColinThreadText.bar(thread.status) {
            case .turnOn:
                ColinOffCard { thread.turnOn() }
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
        .padding(.bottom, Space.l)
        .onChange(of: focused) { _, now in if now { thread.focused() } }
    }

    private func field(placeholder: String, enabled: Bool, note: String?) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let note {
                Text(note).font(.meta).foregroundStyle(.secondary).padding(.horizontal, Space.s).padding(.top, 2)
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
                            thread.send()
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
                RoundButton(symbol: "mic", help: "Dicter", prominent: false) {
                    focused = true
                    // macOS's own dictation, in the field that has the focus.
                    DispatchQueue.main.async { NSApp.sendAction(Selector(("startDictation:")), to: nil, from: nil) }
                }
                .disabled(!enabled)
                if thread.isAnswering {
                    RoundButton(symbol: "stop.fill", help: "Arrêter la réponse", prominent: true) { thread.stop() }
                } else {
                    RoundButton(symbol: "arrow.up", help: "Envoyer à Colin (↩)", prominent: !empty && enabled) { thread.send() }
                        .disabled(!enabled || empty)
                }
            }
        }
        .padding(Space.s)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.hero, style: .continuous))
    }
}

/// A round button of the bar, 28 points: filled with the accent when it is the one to press, quiet otherwise.
private struct RoundButton: View {
    let symbol: String
    let help: String
    let prominent: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(prominent ? Color.white : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 28, height: 28)
                .background(prominent ? Color.accentColor : Color.primary.opacity(enabled ? 0.08 : 0.04), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
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
                        Text(said).font(.meta).lineLimit(1).fixedSize().padding(.horizontal, Space.m).padding(.vertical, 6)
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

/// Colin off: a calm card in the bar's place.
private struct ColinOffCard: View {
    let turnOn: () -> Void

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: "moon.zzz").foregroundStyle(.secondary)
            Text("Colin est à l'arrêt").font(.rowBody).foregroundStyle(.secondary)
            Spacer(minLength: Space.s)
            Button("Allumer Colin", action: turnOn).buttonStyle(.glassProminent)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .background(Surface.fill, in: RoundedRectangle(cornerRadius: Radius.hero, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Radius.hero, style: .continuous).strokeBorder(Surface.stroke) }
    }
}
