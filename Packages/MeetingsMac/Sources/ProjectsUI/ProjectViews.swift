import Domain
import Foundation
import Persistence
import PolhubDesign
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

    public static func statusColor(_ status: ProjectStatus) -> Color {
        Color(hex: statusHex(status))
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

    /// « En retard N j », « Aujourd'hui », « J-N », or nothing.
    public static func dueLabel(_ due: Date?, today: Date, calendar: Calendar = .current) -> String? {
        guard let due else { return nil }
        let left = days(from: today, to: due, calendar: calendar)
        if left < 0 { return "En retard \(-left) j" }
        return left == 0 ? "Aujourd'hui" : "J-\(left)"
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
        let unlinked = text.replacing(#/\[\[([^\]|#]+)(#[^\]|]*)?(\|([^\]]+))?\]\]/#) { match in
            String(match.output.4 ?? match.output.1)
        }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let read = (try? AttributedString(markdown: unlinked, options: options)).map { String($0.characters) } ?? unlinked
        return read.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func cut(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
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
