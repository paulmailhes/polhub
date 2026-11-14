import Foundation
import Pipeline

/// The menu bar icon and the clock next to it.
public struct MenuBarLabel: Equatable, Sendable {
    /// Not a system symbol: the app's columns, drawn by `MenuBarGlyph` (14/11).
    public static let appGlyph = "polhub.colonnes"

    public let symbol: String
    public let text: String?

    public init(symbol: String, text: String?) {
        self.symbol = symbol
        self.text = text
    }

    public static func make(status: RecorderStatus, attention: Bool, now: Date) -> MenuBarLabel {
        switch status {
        case .recording(_, let since):
            MenuBarLabel(symbol: "record.circle.fill", text: DurationText.clock(Int(now.timeIntervalSince(since))))
        case .presumedEnded:
            MenuBarLabel(symbol: "record.circle", text: "fin ?")
        case .prompting:
            MenuBarLabel(symbol: "record.circle", text: nil)
        case .paused:
            MenuBarLabel(symbol: "pause.circle", text: nil)
        case .idle:
            attention ? MenuBarLabel(symbol: "exclamationmark.triangle", text: nil) : MenuBarLabel(symbol: appGlyph, text: nil)
        }
    }

    /// The first line of the menu.
    public static func statusLine(_ status: RecorderStatus, now: Date) -> String {
        switch status {
        case .idle: "Aucune réunion"
        case .prompting(let title): "Réunion détectée · \(title)"
        case .recording(let title, let since): "Enregistre · \(title) · \(DurationText.clock(Int(now.timeIntervalSince(since))))"
        case .presumedEnded(let title): "Fin de réunion détectée · \(title)"
        case .paused(let until): "Détection suspendue jusqu'à \(until.formatted(date: .omitted, time: .shortened))"
        }
    }
}
