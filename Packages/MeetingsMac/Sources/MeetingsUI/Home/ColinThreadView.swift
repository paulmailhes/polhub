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

/// Colin's thread (18/11): the days, Paul's questions, Colin's answers (a message to copy, a line to keep, the drafts
/// of the answer), and the answer being written with what Colin is doing.
struct ColinThreadView: View {
    @ObservedObject var thread: ColinThread
    let mails: MailLibrary?
    @ObservedObject var router: WindowRouter
    var calendar: Calendar = CalendarView.calendar

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if thread.messages.count >= 100 {
                TextButton("Voir les échanges d'avant") { thread.loadEarlier() }
            }
            ForEach(ColinThreadText.sections(thread.messages, changes: thread.changes, now: Date(), calendar: calendar), id: \.day) { section in
                Text(section.day)
                    .font(.meta.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, Space.s)
                ForEach(section.items) { item in
                    switch item {
                    case .message(let message): row(message).id(item.id)
                    case .change(let line): ChangeRow(line: line, outcome: thread.outcomes[line.id], calendar: calendar) { thread.undo(line) }.id(item.id)
                    }
                }
            }
            if case .working(let phrase) = thread.status {
                if !thread.streaming.isEmpty { answerText(thread.streaming) }
                Text(phrase).font(.meta).foregroundStyle(.secondary).id("colin-travaille")
            }
        }
        .animation(Motion.standard, value: thread.messages.count + thread.changes.count)
    }

    @ViewBuilder
    private func row(_ message: ColinMessageRow) -> some View {
        switch message.author {
        case .paul:
            Text(message.text)
                .font(.rowBody)
                .textSelection(.enabled)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
                .background(Surface.fill, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .colin:
            // The answer being written shows apart, under the thread.
            if message.state != .answering {
                let (said, note) = ColinThreadText.note(of: message)
                VStack(alignment: .leading, spacing: Space.s) {
                    ForEach(Array(ColinAnswer.blocks(said).enumerated()), id: \.offset) { _, block in
                        self.block(block)
                    }
                    ForEach(message.drafts, id: \.self) { id in draftLine(id) }
                    if let note { Text(note).font(.meta).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func block(_ block: ColinAnswer.Block) -> some View {
        switch block {
        case .text(let text):
            answerText(text)
        case .message(let text):
            VStack(alignment: .leading, spacing: Space.s) {
                Text(text).font(.rowBody).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                TextButton("Copier") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        case .keep(let line):
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(line).font(.rowBody).foregroundStyle(.secondary)
                Spacer(minLength: Space.s)
                if !thread.knows(line) {
                    TextButton("Garder") { try? thread.keep(line) }
                }
            }
        }
    }

    private func answerText(_ text: String) -> some View {
        Text(ColinAnswer.inline(text))
            .font(.rowTitle)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A draft the answer prepared, still a draft: « Relire » opens it over the Accueil.
    @ViewBuilder
    private func draftLine(_ id: String) -> some View {
        if let mails, let draft = mails.drafts.first(where: { $0.id == id }) {
            HStack(spacing: Space.s) {
                Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
                Text(verbatim: "Brouillon prêt pour \(draft.to.first.map { ReviewRules.short($0.display) } ?? "toi")").font(.rowBody)
                Spacer(minLength: Space.s)
                TextButton("Relire") { mails.open(draft) { router.homeMail = $0 } }
            }
        }
    }
}

/// A change Colin made on a project (step 3, 18/11): one sentence, why in small, and « Annuler » — or what it did.
struct ChangeRow: View {
    let line: ProjectChangeLine
    let outcome: UndoOutcome?
    var calendar: Calendar = CalendarView.calendar
    let undo: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(verbatim: ChangeText.sentence(line, calendar: calendar))
                    .font(.rowBody)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let said = said { Text(verbatim: said).font(.meta).foregroundStyle(.secondary) }
            }
            Spacer(minLength: Space.s)
            if outcome == nil, line.undoneAt == nil {
                TextButton("Annuler", action: undo)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Why it was made; once undone, what « Annuler » did.
    private var said: String? {
        if let outcome { return ChangeText.undone(outcome) }
        if line.undoneAt != nil { return ChangeText.undone(.undone) }
        return ChangeText.note(line)
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
