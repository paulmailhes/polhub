import AppKit
import SwiftUI

/// The colors of the design system v2 (plan of 19/11): one color, one meaning. hub has its own accent, ink, whatever
/// accent the Mac is given (Paul's choice of 19/11): the orange no longer says « send », « selected », « a link » and
/// « late » at once. Each value is the one text reads in, at 4.5:1 at least on a window and on a card, in light and in
/// dark (`TintTests`); a dot or a fill may use it too.
public enum Tint {
    /// A color in light and in dark.
    public struct Pair: Equatable, Sendable {
        public let light: Legibility.RGB
        public let dark: Legibility.RGB

        public init(_ light: String, _ dark: String) {
            self.light = Legibility.RGB(hex: light)
            self.dark = Legibility.RGB(hex: dark)
        }

        /// The color, light or dark as the view's appearance is.
        public var color: Color {
            let (light, dark) = (light, dark)
            return Color(nsColor: NSColor(name: nil) { appearance in
                let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
                return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
            })
        }
    }

    /// What a color says.
    public enum Role: String, CaseIterable, Sendable {
        /// hub's own: the primary button, the selection, the focus.
        case accent
        /// Late: a deadline passed, a reply waited for too long.
        case late
        /// Now, or to check: a meeting about to start, a misleading link, a draft to reread.
        case attention
        /// A meeting being recorded.
        case recording
        /// Done: delivered, sent.
        case done
        /// Written by an agent, or by Colin.
        case agent

        public var text: Pair {
            switch self {
            case .accent: Tint.ink
            case .late: Pair("#B42318", "#FF6961")
            case .attention: Pair("#944A00", "#FFB340")
            case .recording: Pair("#C00013", "#FF7A70")
            case .done: Pair("#17712F", "#4CD964")
            case .agent: Pair("#6340C8", "#B79CFF")
            }
        }

        public var color: Color { text.color }
    }

    /// Near black in light, near white in dark.
    public static let ink = Pair("#1D1D1F", "#F5F5F7")
    /// The label of what is drawn at the accent: its opposite.
    public static let onAccent = Pair("#FFFFFF", "#1D1D1F")
    /// The tint posed at the root of every window and panel, for the system's own controls (switches, boxes, the
    /// toolbar's prominent button): ink in light, graphite in dark. Measured on 19/11: with the near-white ink in dark,
    /// the system writes black on its glass buttons and a switch's track meets its thumb.
    public static let control = Pair("#1D1D1F", "#8E8E93")
    /// The fill of « Arrêter », which carries a white label in light and in dark (6.5:1 and 5.4:1); the text value of
    /// `recording` is lighter in dark, to be read on the window, and too light under white.
    public static let recordingFill = Pair("#C00013", "#D70015")

    public static var accent: Color { Role.accent.color }
    public static var late: Color { Role.late.color }
    public static var attention: Color { Role.attention.color }
    public static var recording: Color { Role.recording.color }
    public static var done: Color { Role.done.color }
    public static var agent: Color { Role.agent.color }
}
