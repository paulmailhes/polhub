import CoreGraphics
import Testing
@testable import MeetingsUI

@Suite struct HUDPlacementTests {
    let size = CGSize(width: 440, height: 72)

    @Test func placesThePanelTopCentreBelowTheNotch() {
        // Built-in display with a notch: the safe area is taller than the menu bar.
        #expect(HUDPlacement.frame(screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117), safeAreaTop: 38, menuBarHeight: 24, size: size)
                == CGRect(x: 644, y: 999, width: 440, height: 72))
        // External display to the right: no notch, the menu bar decides.
        #expect(HUDPlacement.frame(screenFrame: CGRect(x: 1728, y: 0, width: 2560, height: 1440), safeAreaTop: 0, menuBarHeight: 24, size: size)
                == CGRect(x: 2788, y: 1336, width: 440, height: 72))
    }

    @Test func staysOnAScreenNarrowerThanThePanel() {
        let frame = HUDPlacement.frame(screenFrame: CGRect(x: 100, y: 0, width: 400, height: 300), safeAreaTop: 0, menuBarHeight: 0, size: size)
        // Pinned to the left edge rather than hanging off it; 8 points under the top edge.
        #expect(frame == CGRect(x: 100, y: 220, width: 440, height: 72))
    }
}
