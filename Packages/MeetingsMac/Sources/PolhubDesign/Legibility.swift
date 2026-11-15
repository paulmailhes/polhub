import SwiftUI

/// Text in a color, on that color's chip, reads at 4.5:1 at least (WCAG AA): darker in light mode, lighter in dark
/// mode, the same hue. The yellow of « Priorité 1 » read at about 1.9:1 on white (correctifs, 15/11). The raw color
/// stays for the dots, the stripes and the fills.
public enum Legibility {
    public static let minimumContrast = 4.5
    /// The grounds the chips sit on: a window, light or dark.
    static let lightGround = RGB(red: 1, green: 1, blue: 1)
    static let darkGround = RGB(red: 0.118, green: 0.118, blue: 0.118)
    /// A chip's fill: its color at 14 %.
    static let chipOpacity = 0.14

    /// A color in sRGB, each part from 0 to 1.
    public struct RGB: Equatable, Sendable {
        public var red: Double
        public var green: Double
        public var blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// `#RRGGBB`.
        public init(hex: String) {
            let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
            self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
        }

        /// `amount` of `other` over this color.
        func mixed(with other: RGB, _ amount: Double) -> RGB {
            RGB(red: red + (other.red - red) * amount, green: green + (other.green - green) * amount, blue: blue + (other.blue - blue) * amount)
        }

        /// The relative luminance of WCAG.
        var luminance: Double {
            func linear(_ part: Double) -> Double { part <= 0.04045 ? part / 12.92 : pow((part + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
    }

    /// What a chip of this color shows under its text.
    static func chipGround(_ color: RGB, dark: Bool) -> RGB {
        (dark ? darkGround : lightGround).mixed(with: color, chipOpacity)
    }

    static func contrast(_ one: RGB, _ other: RGB) -> Double {
        let (a, b) = (one.luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// The color, darkened (light mode) or lightened (dark mode) by steps until its text reads on its chip.
    static func text(_ color: RGB, dark: Bool) -> RGB {
        let ground = chipGround(color, dark: dark)
        let toward = dark ? RGB(red: 1, green: 1, blue: 1) : RGB(red: 0, green: 0, blue: 0)
        var text = color
        var amount = 0.0
        while contrast(text, ground) < minimumContrast, amount < 1 {
            amount = min(1, amount + 0.05)
            text = color.mixed(with: toward, amount)
        }
        return text
    }
}

extension Color {
    /// This color as text that reads on its own chip, in the light or the dark of `environment`.
    public func readable(in environment: EnvironmentValues) -> Color {
        let resolved = resolve(in: environment)
        let text = Legibility.text(Legibility.RGB(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue)),
                                   dark: environment.colorScheme == .dark)
        return Color(.sRGB, red: text.red, green: text.green, blue: text.blue, opacity: Double(resolved.opacity))
    }
}
