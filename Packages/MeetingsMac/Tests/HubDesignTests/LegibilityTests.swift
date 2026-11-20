import SwiftUI
import Testing
@testable import HubDesign

/// Correctifs du 15/11 : le texte d'une puce dans sa couleur se lit à 4,5:1 au moins, en clair comme en sombre,
/// même en jaune ou en marron ; la couleur brute reste pour les points, les bandes et les fonds.
@Suite struct LegibilityTests {
    static let palette = [Palette.violet, Palette.green, Palette.orange, Palette.blue, Palette.pink, Palette.teal, Palette.red,
                          Palette.yellow, Palette.brown, Palette.gray]

    @Test func everyColorOfThePaletteReadsOnItsChip() {
        for hex in Self.palette {
            let color = Legibility.RGB(hex: hex)
            for dark in [false, true] {
                let text = Legibility.text(color, dark: dark)
                let ground = Legibility.chipGround(color, dark: dark)
                #expect(Legibility.contrast(text, ground) >= Legibility.minimumContrast, "\(hex) \(dark ? "sombre" : "clair")")
            }
        }
    }

    /// Before: the yellow of Priorité 1 on its own chip, about 1.9:1 on white.
    @Test func theRawYellowWasUnreadable() {
        let yellow = Legibility.RGB(hex: Palette.yellow)
        #expect(Legibility.contrast(yellow, Legibility.chipGround(yellow, dark: false)) < 2.2)
        // A color that already reads is left as it is.
        let ink = Legibility.RGB(red: 0.1, green: 0.1, blue: 0.4)
        #expect(Legibility.text(ink, dark: false) == ink)
    }
}
