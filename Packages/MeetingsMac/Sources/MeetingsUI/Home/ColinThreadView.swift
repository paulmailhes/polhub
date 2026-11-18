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
        case .waitingCall: .field(placeholder: "Colin attend la fin de ton call", enabled: false, note: nil)
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

/// Colin's bar (18/11): a field that grows, ↑ to send (⌘↩ too), the stop arrow while he answers. Off, « Allumer
/// Colin » in its place; during a call, the field waits.
struct ColinComposer: View {
    @ObservedObject var thread: ColinThread
    @FocusState private var focused: Bool

    var body: some View {
        switch ColinThreadText.bar(thread.status) {
        case .turnOn:
            HStack {
                Spacer()
                Button("Allumer Colin") { thread.turnOn() }
                    .buttonStyle(.glassProminent)
                Spacer()
            }
            .padding(.bottom, Space.l)
        case .field(let placeholder, let enabled, let note):
            VStack(alignment: .leading, spacing: Space.xs) {
                if let note {
                    Text(note).font(.meta).foregroundStyle(.secondary).padding(.horizontal, Space.xl + Space.s)
                }
                FloatingBar(cornerRadius: Radius.hero) {
                    HStack(alignment: .bottom, spacing: Space.s) {
                        TextField(placeholder, text: $thread.draft, axis: .vertical)
                            .font(.rowBody)
                            .textFieldStyle(.plain)
                            .lineLimit(1...8)
                            .focused($focused)
                            .disabled(!enabled)
                            .onSubmit { thread.send() }
                        if thread.isAnswering {
                            IconButton("stop.fill", help: "Arrêter la réponse") { thread.stop() }
                        } else {
                            // ⌘↩ only while the bar has the focus: a draft open over the Accueil has its own.
                            let send = IconButton("arrow.up", help: "Envoyer à Colin (⌘↩)") { thread.send() }
                                .disabled(!enabled || thread.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if focused { send.keyboardShortcut(.return, modifiers: .command) } else { send }
                        }
                    }
                }
            }
            .onChange(of: focused) { _, now in if now { thread.focused() } }
        }
    }
}
