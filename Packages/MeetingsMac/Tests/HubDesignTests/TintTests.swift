import SwiftUI
import Testing
@testable import HubDesign

/// The tints of the design system v2 (plan of 19/11): one color, one meaning, each readable as text (4.5:1, WCAG AA)
/// on a window and on a card, in light and in dark. The accent is ink (Paul's choice of 19/11): near black in light,
/// near white in dark; the primary button's label is its opposite.
@Suite struct TintTests {
    /// A window, a card on it, a raised card: light, then dark.
    static let light = ["#FFFFFF", "#ECECEC", "#E1E1E1"].map(Legibility.RGB.init(hex:))
    static let dark = ["#1E1E1E", "#282828", "#323232"].map(Legibility.RGB.init(hex:))

    @Test func theAccentIsInk() {
        #expect(Tint.ink.light == Legibility.RGB(hex: "#1D1D1F") && Tint.ink.dark == Legibility.RGB(hex: "#F5F5F7"))
        #expect(Tint.Role.accent.text == Tint.ink)
    }

    @Test func everyTintReadsAsTextInLightAndInDark() {
        for role in Tint.Role.allCases {
            for ground in Self.light { #expect(Legibility.contrast(role.text.light, ground) >= Legibility.minimumContrast, "\(role) en clair") }
            for ground in Self.dark { #expect(Legibility.contrast(role.text.dark, ground) >= Legibility.minimumContrast, "\(role) en sombre") }
        }
    }

    @Test func thePrimaryLabelReadsOnTheAccent() {
        #expect(Legibility.contrast(Tint.onAccent.light, Tint.ink.light) >= Legibility.minimumContrast)
        #expect(Legibility.contrast(Tint.onAccent.dark, Tint.ink.dark) >= Legibility.minimumContrast)
    }

    /// Each meaning has its own color: the late is no longer the accent, nor the attention.
    @Test func noTwoMeaningsShareAColor() {
        let lights = Tint.Role.allCases.map(\.text.light), darks = Tint.Role.allCases.map(\.text.dark)
        #expect(Set(lights.map { "\($0)" }).count == lights.count && Set(darks.map { "\($0)" }).count == darks.count)
    }
}
