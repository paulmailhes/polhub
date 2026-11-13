import CoreGraphics

/// Where the pop-up goes: top centre of a screen, just below the menu bar or the notch.
/// AppKit coordinates: the origin is at the bottom left.
public enum HUDPlacement {
    public static func frame(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        menuBarHeight: CGFloat,
        size: CGSize,
        margin: CGFloat = 8
    ) -> CGRect {
        let centred = screenFrame.midX - size.width / 2
        // On a screen narrower than the panel, stay against its left edge.
        let x = max(screenFrame.minX, centred)
        let y = screenFrame.maxY - max(safeAreaTop, menuBarHeight) - margin - size.height
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
