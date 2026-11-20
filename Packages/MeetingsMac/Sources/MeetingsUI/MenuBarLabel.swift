import AppKit
import Foundation
import Pipeline
import HubDesign

/// The menu bar's logo and the few characters next to it (« Coup d'œil », 15/11). From the most to the least
/// important: a recording (the red circle and its clock), a meeting just detected (the circle in outline and the
/// 10 s countdown), a presumed end (« fin ? »), detection off (the columns in outline), at rest (the columns filled,
/// « 8 min » before a Meet when Paul wants it). The badge is added to the columns, never to a meeting. Mails,
/// notifications, accounts and updates never touch the logo.
public struct MenuBarLabel: Equatable, Sendable {
    public enum Icon: Equatable, Sendable {
        /// Recording: the red filled circle, the only color of the bar.
        case recording
        /// Not sure yet (the prompt's 10 s, a presumed end): the circle in outline.
        case listening
        /// The app's columns: filled while hub watches for meetings, in outline when it does not; the badge when a
        /// recording is at risk.
        case columns(MenuBarGlyph.Style, badge: Bool)
    }

    /// How long before a Meet the minutes show (Paul, 15/11: « dans le quart d'heure »).
    public static let meetLead: TimeInterval = 15 * 60

    public let icon: Icon
    public let text: String?

    public init(icon: Icon, text: String?) {
        self.icon = icon
        self.text = text
    }

    /// - Parameters:
    ///   - status: what records, as the menu shows it (`AppModel.shownStatus`: a pause only while nothing records).
    ///   - promptDeadline: when the detected meeting records by itself (`AppModel.promptDeadline`).
    ///   - minutesToMeet: minutes before the next event with a Meet link, already limited to the quarter of an hour
    ///     before it and to Paul's setting (`AppModel.minutesToMeet`).
    ///   - danger: a recording is at risk (`AppModel.recordingsAtRisk`).
    ///   - watching: detection is on (it is off before launch ends, or in the development build until switched on).
    public static func make(status: RecorderStatus, now: Date, promptDeadline: Date? = nil, minutesToMeet: Int? = nil,
                            danger: Bool = false, watching: Bool = true, isDevelopment: Bool = false) -> MenuBarLabel {
        // « 12:47 », « 7 s », « 8 min » (`Words`, lot 10, 20/11).
        switch status {
        case .recording(_, let since):
            MenuBarLabel(icon: .recording, text: Words.clock(Int(now.timeIntervalSince(since))))
        case .prompting:
            MenuBarLabel(icon: .listening, text: promptDeadline.map { Words.preciseDuration(HUDText.remaining(until: $0, now: now)) })
        case .presumedEnded:
            MenuBarLabel(icon: .listening, text: "fin ?")
        case .paused:
            MenuBarLabel(icon: .columns(.outline, badge: danger), text: nil)
        case .idle:
            // The development build never detects on its own: its logo stays in outline, so it is told apart from the
            // real one at a glance.
            if isDevelopment || !watching {
                MenuBarLabel(icon: .columns(.outline, badge: danger), text: nil)
            } else {
                // `minutesToMeet` is 1 at least (`minutes(before:)`, rounded up).
                MenuBarLabel(icon: .columns(.filled, badge: danger), text: minutesToMeet.map { Words.duration($0 * 60) })
            }
        }
    }

    /// « 8 min » before an event that starts at `start`, rounded up; nothing past the quarter of an hour before it,
    /// nor once it started.
    public static func minutes(before start: Date?, now: Date) -> Int? {
        guard let start else { return nil }
        let seconds = start.timeIntervalSince(now)
        guard seconds > 0, seconds <= meetLead else { return nil }
        return Int((seconds / 60).rounded(.up))
    }

    /// The image of the icon: a template the menu bar colors, except the recording's red.
    @MainActor
    public var image: NSImage {
        switch icon {
        case .recording: Self.redCircle
        case .listening: Self.listening
        case .columns(let style, let badge): MenuBarGlyph.image(style: style, badge: badge)
        }
    }

    /// The menu bar draws its images in one colour; this one stays the recording's red (design system v2, 19/11).
    @MainActor static let redCircle: NSImage = {
        let configuration = NSImage.SymbolConfiguration(paletteColors: [MenuBarLabel.recordingRed()])
        let image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Enregistrement")?
            .withSymbolConfiguration(configuration) ?? NSImage()
        image.isTemplate = false
        return image
    }()

    /// `Tint.recording` for AppKit: its light or dark value as the menu bar is. Made off the main actor, as `Tint`'s own
    /// colors are: the dynamic color's closure assumes no thread.
    /// A sign, not a text: the system's red, which reads on a light and a dark bar. The image is drawn once, so a
    /// dynamic color was resolved once (measured on 19/11: salmon on a light bar).
    static func recordingRed() -> NSColor {
        .systemRed
    }

    /// Drawn once, as the others: the menu bar asks for its label twice a second, and a new image each time would be a
    /// new label for it.
    @MainActor static let listening = symbol("record.circle", description: "Réunion détectée")

    @MainActor static func symbol(_ name: String, description: String) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description) ?? NSImage()
        image.isTemplate = true
        return image
    }

    /// One line that says what hub does now: « Enregistrement », as « Coup d'œil » says it, the clock and the hour by
    /// `Words` (lot 10, 20/11).
    public static func statusLine(_ status: RecorderStatus, now: Date) -> String {
        switch status {
        case .idle: "Aucune réunion"
        case .prompting(let title): "Réunion détectée · \(title)"
        case .recording(let title, let since): "Enregistrement · \(title) · \(Words.clock(Int(now.timeIntervalSince(since))))"
        case .presumedEnded(let title): "Fin de réunion détectée · \(title)"
        case .paused(let until): "Détection suspendue jusqu'à \(Words.time(until))"
        }
    }
}
