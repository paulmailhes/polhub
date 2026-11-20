import Domain
import Foundation
import Persistence
import PolhubDesign
import Summarization
import SwiftUI

public struct BoardColumn: Equatable, Identifiable, Sendable {
    public var id: String { status.rawValue }
    public let status: ProjectStatus
    public let title: String
    public let projects: [ProjectRow]
}

/// The views of the projects: the board, the table, the colors, the short texts of a card or a page.
public enum ProjectViews {
    /// A status's color, from the one palette (docs/design-system.md): every status has its own.
    public static func statusHex(_ status: ProjectStatus) -> String {
        switch status {
        case .priorite1: Palette.yellow
        case .priorite2: Palette.orange
        case .enPause: Palette.teal
        case .termine: Palette.green
        }
    }

    /// The dot of a status, in its column's head and in its capsule. « Terminé » in the color of what is done (lot 8, 19/11).
    public static func statusColor(_ status: ProjectStatus) -> Color {
        statusRole(status)?.color ?? Color(hex: statusHex(status))
    }

    /// What a status says by its color (lot 8, 19/11): only « Terminé », done; the others are a place on the board, their
    /// capsule neutral with its dot — « Priorité 2 » in orange read as « à vérifier ».
    public static func statusRole(_ status: ProjectStatus) -> Tint.Role? {
        status == .termine ? .done : nil
    }

    /// How much of its project's color a card of the board takes (lot 8, 19/11, « teinte allégée », Paul's choice): half
    /// of what it had, 13 % in light and 22 % in dark.
    public static func cardTint(dark: Bool) -> Double {
        dark ? 0.11 : 0.065
    }

    /// The ground of a column (lot 8, 19/11): none at rest, the columns no longer take their status's tint; under a card
    /// being dragged, the ground of what is chosen.
    public static func columnFill(targeted: Bool) -> Color? {
        targeted ? Surface.selected : nil
    }

    /// One line of a card under its next step: its words, its icon, and what its color says (lot 8, 19/11).
    public struct CardFact: Equatable, Sendable {
        public let text: String
        public let icon: String
        /// The color of what the fact means, on its icon only: every text of a card is in the text's own color.
        public let role: Tint.Role?
        /// Semibold, in the text's color; otherwise grey.
        public let strong: Bool

        public init(text: String, icon: String, role: Tint.Role?, strong: Bool) {
            self.text = text
            self.icon = icon
            self.role = role
            self.strong = strong
        }
    }

    /// The next meeting, the due date and the last meeting of a card, one per line, in words (15/11); late and today on
    /// their flag's color, the rest grey but the next meeting (lot 8, 19/11).
    public static func cardFacts(nextEvent: Date?, due: Date?, lastMeeting: Date?, now: Date, calendar: Calendar = .current) -> [CardFact] {
        var facts: [CardFact] = []
        if let nextEvent {
            facts.append(CardFact(text: nextEventLabel(nextEvent, now: now, calendar: calendar), icon: "calendar.badge.clock", role: nil, strong: true))
        }
        if let label = dueLabel(due, today: now, calendar: calendar) {
            let role = dueRole(label)
            facts.append(CardFact(text: label, icon: "flag", role: role, strong: role != nil))
        }
        if let lastMeeting {
            facts.append(CardFact(text: meetingLabel(lastMeeting, now: now, calendar: calendar), icon: "waveform", role: nil, strong: false))
        }
        return facts
    }

    /// The colors a project without one of its own takes, by its identifier: neither red (late) nor grey.
    static let tints = [Palette.blue, Palette.violet, Palette.green, Palette.teal, Palette.pink, Palette.orange, Palette.brown, Palette.yellow]

    /// A project's color: the one Paul chose, else always the same one of the palette, picked from its
    /// identifier (15/11). Every place that shows a project uses it: board, list, page, Accueil, mails.
    public static func tintHex(_ project: ProjectRow) -> String {
        if let hex = cardHex(project.color) { return hex }
        let sum = withUnsafeBytes(of: project.id.uuid) { bytes in bytes.reduce(0) { $0 &+ Int($1) } }
        return tints[sum % tints.count]
    }

    public static func tint(_ project: ProjectRow) -> Color {
        Color(hex: tintHex(project))
    }

    /// The cards of a column: the size chosen in Réglages › Projets, always compact in Terminé.
    public static func cardSize(_ status: ProjectStatus, chosen: CardSize) -> CardSize {
        status == .termine ? .small : chosen
    }

    /// One width for every column: the room shared out, never under `minimum` (the board then scrolls).
    public static func columnWidth(available: CGFloat, count: Int, spacing: CGFloat, minimum: CGFloat) -> CGFloat {
        guard count > 0 else { return minimum }
        return max(minimum, ((available - spacing * CGFloat(count - 1)) / CGFloat(count)).rounded(.down))
    }

    /// The four columns, in their order, Terminé always at the right (15/11).
    public static func columns(_ projects: [ProjectRow]) -> [BoardColumn] {
        ProjectStatus.boardOrder.map { status in
            let cards = projects.filter { $0.status == status }.sorted { ($0.kanbanOrder, $0.name) < ($1.kanbanOrder, $1.name) }
            return BoardColumn(status: status, title: status.title, projects: cards)
        }
    }

    static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }

    /// « En retard de N j », « Échéance aujourd'hui », « Échéance demain », « Échéance dans N j », or nothing:
    /// in words, not « J-2 », which read as a meeting (Paul, 15/11).
    public static func dueLabel(_ due: Date?, today: Date, calendar: Calendar = .current) -> String? {
        guard let due else { return nil }
        let left = days(from: today, to: due, calendar: calendar)
        if left < 0 { return "En retard de \(-left) j" }
        switch left {
        case 0: return "Échéance aujourd'hui"
        case 1: return "Échéance demain"
        default: return "Échéance dans \(left) j"
        }
    }

    /// What a due date says by its color (design system v2, 19/11): late in the tint of the late, today in the tint of
    /// attention, both readable as text; else nothing, neutral.
    public static func dueRole(_ label: String) -> Tint.Role? {
        label.hasPrefix("En retard") ? .late : label == "Échéance aujourd'hui" ? .attention : nil
    }

    /// The color of `dueRole`, else neutral.
    public static func dueTint(_ label: String) -> Color? {
        dueRole(label)?.color
    }

    /// « RDV aujourd'hui à 14:00 », « RDV demain à 9:30 », « RDV jeudi à 14:00 », « RDV le 2 déc. »: the next
    /// event of a project, the first thing a card says (Paul, 15/11).
    public static func nextEventLabel(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let locale = Locale(identifier: "fr_FR")
        let hour = date.formatted(.dateTime.hour().minute().locale(locale))
        let ahead = days(from: now, to: date, calendar: calendar)
        switch ahead {
        case ...0: return "RDV aujourd'hui à \(hour)"
        case 1: return "RDV demain à \(hour)"
        case 2...6: return "RDV \(date.formatted(.dateTime.weekday(.wide).locale(locale))) à \(hour)"
        default: return "RDV le \(date.formatted(.dateTime.day().month(.abbreviated).locale(locale)))"
        }
    }

    /// « Réunion il y a 3 semaines »: the last meeting, in words (15/11).
    public static func meetingLabel(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let ago = max(0, days(from: date, to: now, calendar: calendar))
        let when: String = switch ago {
        case 0: "aujourd'hui"
        case 1: "hier"
        case ..<7: "il y a \(ago) jours"
        case ..<35: ago / 7 == 1 ? "il y a 1 semaine" : "il y a \(ago / 7) semaines"
        case ..<365: "il y a \(max(1, ago / 30)) mois"
        default: ago / 365 == 1 ? "il y a 1 an" : "il y a \(ago / 365) ans"
        }
        return "Réunion \(when)"
    }

    /// The most recent sign of life: activity, a meeting (from the vault or filed in the app), a change of
    /// the note, a change in the app; the creation when there is none.
    public static func sign(_ project: ProjectRow, lastAppMeeting: Date?) -> Date {
        [project.lastActivity, project.lastMeetingImported, lastAppMeeting, project.noteModifiedAt, project.lastEditedAt]
            .compactMap { $0 }.max() ?? project.createdAt
    }

    /// Every project, the most recent activity first, those without at the end.
    public static func table(_ projects: [ProjectRow]) -> [ProjectRow] {
        projects.sorted { a, b in
            switch (a.lastActivity, b.lastActivity) {
            case let (x?, y?): x == y ? a.name < b.name : x > y
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): a.name < b.name
            }
        }
    }

    /// The projects whose name, client, next step or notes hold the text, without case or accents (14/11).
    public static func matching(_ projects: [ProjectRow], _ query: String) -> [ProjectRow] {
        let words = fold(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return projects }
        return projects.filter { project in
            let text = fold([project.name, project.client ?? "", project.todo ?? "", project.notes].joined(separator: " "))
            return words.allSatisfy(text.contains)
        }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    /// The card a dropped card goes above. Dropped on a card lower in its own column, it goes below it:
    /// moving a card down one place is dropping it on the next one (review, minor 7).
    public static func dropBefore(dragged: UUID, onto target: UUID, column: [UUID]) -> UUID? {
        guard let from = column.firstIndex(of: dragged), let to = column.firstIndex(of: target), from < to else { return target }
        return to + 1 < column.count ? column[to + 1] : nil
    }

    /// The newest meeting of a project: seen in the vault, or filed in the app.
    public static func lastMeeting(_ project: ProjectRow, appMeeting: Date?) -> Date? {
        [project.lastMeetingImported, appMeeting].compactMap { $0 }.max()
    }

    /// « RS » for « Refonte site », « A » for « Agence »: the logo of a project without one.
    public static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return words.prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
    }

    // MARK: - Short texts

    /// A text of Markdown as one plain line: no headings, no code, no marks; the bullets one after the other.
    /// The journal shows two lines of it (15/11).
    public static func excerpt(_ markdown: String, limit: Int = 280) -> String {
        let parts = MarkdownBlocks.parse(markdown).compactMap { block -> String? in
            switch block {
            case .heading, .code: nil
            case .bullet(_, let text), .task(_, let text), .numbered(_, _, let text), .quote(let text), .paragraph(let text): text
            case .callout(_, let title, let body): [title, body].filter { !$0.isEmpty }.joined(separator: " ")
            }
        }
        .map(plain)
        .filter { !$0.isEmpty }
        var text = ""
        for part in parts {
            if !text.isEmpty { text += text.last.map { ".!?:;…".contains($0) } == true ? " " : " · " }
            text += part
        }
        return cut(text, limit: limit)
    }

    /// Inline Markdown and wiki links taken away, the spaces put back to one.
    static func plain(_ text: String) -> String {
        SummaryText.plain(text).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func cut(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// What the base changed in a project while its page was open (a session's `projet`, 16/11), carried over to the
    /// page's copy: a field Paul has not touched since takes the new value, one he is changing keeps his (review of 16/11).
    static func reported(from old: ProjectRow, to new: ProjectRow, onto draft: ProjectRow) -> ProjectRow {
        var shown = draft
        func carry<Value: Equatable>(_ field: WritableKeyPath<ProjectRow, Value>) {
            if new[keyPath: field] != old[keyPath: field], draft[keyPath: field] == old[keyPath: field] { shown[keyPath: field] = new[keyPath: field] }
        }
        carry(\.name)
        carry(\.status)
        carry(\.client)
        carry(\.dueDate)
        carry(\.todo)
        carry(\.icon)
        carry(\.color)
        carry(\.contacts)
        carry(\.createdOn)
        carry(\.codeFolder)
        carry(\.github)
        carry(\.notion)
        carry(\.lastActivity)
        carry(\.lastMeetingImported)
        carry(\.noteModifiedAt)
        carry(\.lastEditedAt)
        carry(\.notes)
        carry(\.kanbanOrder)
        carry(\.importedFrom)
        carry(\.createdAt)
        carry(\.updatedAt)
        carry(\.deletedAt)
        return shown
    }

    // MARK: - The vault's colors

    /// The palette of the vault's own plugin: French names first, English aliases.
    static let palette: [String: String] = [
        "rouge": "#E2453C", "orange": "#F08A24", "jaune": "#E8B923", "vert": "#1FA971", "cyan": "#17A2B8",
        "bleu": "#2F6FED", "violet": "#8E44AD", "rose": "#E0559B", "gris": "#6B7280", "marron": "#8B5E3C", "noir": "#222222",
        "red": "#E2453C", "yellow": "#E8B923", "green": "#1FA971", "blue": "#2F6FED", "purple": "#8E44AD", "pink": "#E0559B",
        "gray": "#6B7280", "grey": "#6B7280",
    ]
    /// The choices of the « Couleur » field, as in the vault's plugin.
    public static let colorChoices = ["rouge", "orange", "jaune", "vert", "cyan", "bleu", "violet", "rose", "gris", "marron", "noir"]

    /// A card's `couleur` as a hex code: a palette name, or a free hex value the note already holds.
    public static func cardHex(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let hex = palette[value.lowercased()] { return hex }
        let digits = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + digits.uppercased()
    }
}

/// A project's status in its capsule (lot 8, 19/11): neutral, with its dot; « Terminé » in the color of what is done,
/// with its check. In the list and in a project's page.
struct StatusChip: View {
    let status: ProjectStatus

    var body: some View {
        if let role = ProjectViews.statusRole(status) {
            Chip(status.title, systemImage: "checkmark", tint: role.color)
        } else {
            Chip(status.title, dot: ProjectViews.statusColor(status))
        }
    }
}

/// One line of the « Liste » (14/11): the project and the keys its columns sort by.
public struct ProjectListRow: Identifiable, Sendable {
    public let project: ProjectRow
    public let lastSign: Date
    public var id: UUID { project.id }

    /// The board's order: Priorité 1 first, Terminé last.
    public var statusRank: Int { ProjectStatus.allCases.firstIndex(of: project.status) ?? 99 }
    public var name: String { ProjectViews.fold(project.name) }
    /// Without a client, last.
    public var clientSort: String { project.client.map(ProjectViews.fold) ?? "\u{10FFFF}" }
    /// Without a due date, last.
    public var dueSort: Date { project.dueDate ?? .distantFuture }
    public var activitySort: Date { lastSign }

    public static func rows(_ projects: [ProjectRow], lastMeetings: [UUID: Date], status: ProjectStatus?) -> [ProjectListRow] {
        projects.filter { status == nil || $0.status == status }
            .map { ProjectListRow(project: $0, lastSign: ProjectViews.sign($0, lastAppMeeting: lastMeetings[$0.id])) }
    }
}
