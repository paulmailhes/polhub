import AppKit

/// The menu bar's logo: the three columns of hub's icon (Paul, 14/11). One rule (« Coup d'œil », 15/11): filled,
/// hub watches for meetings; in outline, it does not (detection paused, or the development build, which never
/// detects). A small cut-out badge on the top right corner when a recording is at risk. A template image, so the menu
/// bar draws it black or white with the rest, tinted bars included; nothing in it moves.
public enum MenuBarGlyph {
    public enum Style: Sendable, Hashable {
        /// hub watches for meetings.
        case filled
        /// hub does not watch: detection paused, or the development build.
        case outline
    }

    /// The columns' box; the image of the badge is wider (`size(badge:)`).
    public static let size = NSSize(width: 18, height: 16)
    static let lineWidth: CGFloat = 1.2
    /// The icon's own rounding: rx 48 on columns 160 wide.
    static let cornerRatio: CGFloat = 0.3
    /// The badge and the gap cut around it. It sits on the corner, mostly outside the third column, which keeps its
    /// full height with a bite out of its top: centred on the column, the badge read as the dot of an « i » at real
    /// size (finding of 16/11; compared with a larger disc and a triangle, in light and dark, at 1x and 2x).
    static let badgeRadius: CGFloat = 3
    static let badgeGap: CGFloat = 1
    static let badgeCenter = NSPoint(x: 19, y: 12.5)

    /// 18 × 16; 22 wide with the badge, which spills past the corner.
    public static func size(badge: Bool) -> NSSize {
        badge ? NSSize(width: badgeCenter.x + badgeRadius, height: size.height) : size
    }

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

    /// The images are drawn once per look: the menu bar asks for its label twice a second.
    @MainActor private static var cache: [Key: NSImage] = [:]

    private struct Key: Hashable {
        let style: Style
        let badge: Bool
    }

    @MainActor
    public static func image(style: Style = .filled, badge: Bool = false) -> NSImage {
        let key = Key(style: style, badge: badge)
        if let image = cache[key] { return image }
        let image = NSImage(size: size(badge: badge), flipped: false) { _ in
            draw(style: style, badge: badge, in: NSRect(origin: .zero, size: size))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description(style: style, badge: badge)
        cache[key] = image
        return image
    }

    static func description(style: Style, badge: Bool) -> String {
        // The detection is active or suspended, never « arrêtée » (lot 10, 20/11).
        let state = style == .filled ? "hub" : "hub, détection suspendue"
        return badge ? "\(state), un enregistrement est menacé" : state
    }

    /// Filled: the columns as the icon draws them, rounded at 0.3 of their width. In outline: the line inside the
    /// same box, as on 14/11. `bounds` is the columns' box; the badge spills past its right edge.
    static func draw(style: Style, badge: Bool, in bounds: NSRect) {
        NSColor.black.set()
        switch style {
        case .filled:
            for column in columns(in: bounds) {
                let radius = column.width * cornerRatio
                NSBezierPath(roundedRect: column, xRadius: radius, yRadius: radius).fill()
            }
        case .outline:
            let inset = lineWidth / 2
            for column in columns(in: bounds.insetBy(dx: inset, dy: inset)) {
                let path = NSBezierPath(roundedRect: column, xRadius: 1.8, yRadius: 1.8)
                path.lineWidth = lineWidth
                path.stroke()
            }
        }
        guard badge, let context = NSGraphicsContext.current?.cgContext else { return }
        let center = badgeCenter
        // The cut: a clear ring around the badge, then the badge itself.
        let cut = badgeRadius + badgeGap
        context.saveGState()
        context.setBlendMode(.clear)
        context.fillEllipse(in: CGRect(x: center.x - cut, y: center.y - cut, width: 2 * cut, height: 2 * cut))
        context.restoreGState()
        NSBezierPath(ovalIn: NSRect(x: center.x - badgeRadius, y: center.y - badgeRadius, width: 2 * badgeRadius, height: 2 * badgeRadius)).fill()
    }
}
