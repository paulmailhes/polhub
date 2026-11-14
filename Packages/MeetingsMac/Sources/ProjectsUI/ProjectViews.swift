import Domain
import Foundation
import Persistence
import SwiftUI

/// The colors of the board: the column colors of `Projets.base`, and the card colors of the vault.
public enum BoardColor: String, Equatable, Sendable {
    case pink, red, orange, yellow, cyan, green, gray
}

public struct BoardColumn: Equatable, Identifiable, Sendable {
    public var id: String { status.rawValue }
    public let status: ProjectStatus
    public let title: String
    public let color: BoardColor
    public let projects: [ProjectRow]
}

/// The views of `Projets.base`, rebuilt: the board, « À rendre », « À surveiller », the table.
public enum ProjectViews {
    /// No sign of life for this many days: « Silence » (`seuil_silence` of the vault).
    public static let silenceDays = 14

    static let columnColors: [ProjectStatus: BoardColor] = [
        .idee: .pink, .priorite3: .red, .priorite2: .orange, .priorite1: .yellow, .enAttente: .cyan, .termine: .green, .none: .gray,
    ]

    /// A status's color, as on the board's columns.
    public static func statusColor(_ status: ProjectStatus) -> Color {
        (columnColors[status] ?? .gray).swiftUI
    }

    /// The six columns of the vault in its order (« terminé » only in the « Tous » view), then « Sans statut »
    /// when it has cards.
    public static func columns(_ projects: [ProjectRow], includeDone: Bool) -> [BoardColumn] {
        ProjectStatus.boardOrder.compactMap { status in
            if status == .termine && !includeDone { return nil }
            let cards = projects.filter { $0.status == status }.sorted { ($0.kanbanOrder, $0.name) < ($1.kanbanOrder, $1.name) }
            if status == ProjectStatus.none && cards.isEmpty { return nil }
            return BoardColumn(status: status, title: status.label, color: columnColors[status] ?? .gray, projects: cards)
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

    /// Priorities 1, 2, 3 with a to-do: by days left, then the undated by priority, then by name.
    public static func toHandIn(_ projects: [ProjectRow], today: Date, calendar: Calendar = .current) -> [ProjectRow] {
        func rank(_ project: ProjectRow) -> Int {
            if let due = project.dueDate { return days(from: today, to: due, calendar: calendar) }
            switch project.status {
            case .priorite1: return 9001
            case .priorite2: return 9002
            default: return 9003
            }
        }
        return projects
            .filter { $0.status.isPriority && !($0.todo ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { (rank($0), $0.name) < (rank($1), $1.name) }
    }

    /// The most recent sign of life: activity, a meeting (from the vault or filed in the app), a change of
    /// the note, a change in the app; the creation when there is none.
    public static func sign(_ project: ProjectRow, lastAppMeeting: Date?) -> Date {
        [project.lastActivity, project.lastMeetingImported, lastAppMeeting, project.noteModifiedAt, project.lastEditedAt]
            .compactMap { $0 }.max() ?? project.createdAt
    }

    /// Priorities 1, 2, 3 silent for 14 days or more, the longest silent first.
    public static func toWatch(
        _ projects: [ProjectRow], lastAppMeeting: [UUID: Date], today: Date, calendar: Calendar = .current
    ) -> [(ProjectRow, sign: Date)] {
        projects.filter(\.status.isPriority)
            .map { ($0, sign: sign($0, lastAppMeeting: lastAppMeeting[$0.id])) }
            .filter { days(from: $0.sign, to: today, calendar: calendar) >= silenceDays }
            .sorted { ($0.sign, $0.0.name) < ($1.sign, $1.0.name) }
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

    /// Priority 1 first, done last.
    public var statusRank: Int {
        [ProjectStatus.priorite1, .priorite2, .priorite3, .enAttente, .idee, .none, .termine].firstIndex(of: project.status) ?? 99
    }
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
