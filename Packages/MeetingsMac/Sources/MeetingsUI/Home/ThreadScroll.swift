import CoreGraphics

/// Colin's thread and its end (the Accueil's pass, 18/11): it follows what Colin writes only while Paul is at the end,
/// never when he went up to read; then a ↓ brings him back.
enum ThreadScroll {
    /// How near the end still counts as there.
    static let margin: CGFloat = 32

    static func follows(contentHeight: CGFloat, offset: CGFloat, visibleHeight: CGFloat) -> Bool {
        contentHeight - offset - visibleHeight <= margin
    }
}
