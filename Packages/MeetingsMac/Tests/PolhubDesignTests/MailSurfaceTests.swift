import SwiftUI
import Testing
@testable import PolhubDesign

/// Lot 6 (19/11): a read thread still sits a step below an unread one, as Paul asked (15/11), but a soft step: at 4.5 %
/// of grey, the read lines made bands that weighed more than the unread ones.
@Suite struct MailSurfaceTests {
    /// The window under an unread line: white in light, #1E1E1E in dark (measured on 19/11, macOS 27).
    static let window = (light: 1.0, dark: 30.0 / 255)

    @Test func aReadThreadIsASoftStepBelowAnUnreadOne() {
        let light = Self.window.light - MailSurface.readWhite.light
        let dark = MailSurface.readWhite.dark - Self.window.dark
        #expect(light >= 0.02 && light <= 0.03, "clair : \(light)")
        #expect(dark >= 0.02 && dark <= 0.03, "sombre : \(dark)")
    }
}
