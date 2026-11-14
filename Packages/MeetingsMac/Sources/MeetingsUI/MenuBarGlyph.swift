import AppKit

/// The menu bar's icon at rest: the three columns of Polhub's icon, in outline (Paul, 14/11). A template image,
/// so the menu bar draws it black or white with the rest.
public enum MenuBarGlyph {
    public static let size = NSSize(width: 18, height: 16)
    static let lineWidth: CGFloat = 1.2

    /// The columns in a box, with the icon's proportions (heights 132, 96, 116 on a 132 tall glyph), top aligned.
    public static func columns(in box: NSRect) -> [NSRect] {
        let gap: CGFloat = 2
        let width = (box.width - 2 * gap) / 3
        let heights: [CGFloat] = [132, 96, 116].map { $0 / 132 * box.height }
        return heights.enumerated().map { index, height in
            // AppKit counts from the bottom: top aligned means starting at maxY - height.
            NSRect(x: box.minX + CGFloat(index) * (width + gap), y: box.maxY - height, width: width, height: height)
        }
    }

    public static func image() -> NSImage {
        let image = NSImage(size: size, flipped: false) { bounds in
            let inset = lineWidth / 2
            NSColor.black.setStroke()
            for column in columns(in: bounds.insetBy(dx: inset, dy: inset)) {
                let path = NSBezierPath(roundedRect: column, xRadius: 1.8, yRadius: 1.8)
                path.lineWidth = lineWidth
                path.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Polhub"
        return image
    }
}
