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

/// Whether Colin's thread follows its end (final review, 18/11): Paul's hand on it stops the following at once — even a
/// slow scroll inside the end's margin —; let go at the end, it follows again. While it follows, content that grows
/// (a word, a card, a foot) is followed; his own question always brings him back.
struct ThreadFollow: Equatable {
    private(set) var following = true
    private(set) var userScrolling = false
    private(set) var atEnd = true

    /// Each tick of what Colin writes scrolls to the end.
    var scrollsOnTick: Bool { following && !userScrolling }

    /// Paul's hand on the thread, or let go.
    mutating func userScroll(began: Bool) {
        userScrolling = began
        following = began ? false : atEnd
    }

    /// Where the end stands; `true` when the thread should be scrolled to it (it grew while followed).
    mutating func geometry(atEnd: Bool) -> Bool {
        self.atEnd = atEnd
        guard !userScrolling else { return false }
        if atEnd { following = true }
        return following && !atEnd
    }

    /// Paul asked: back to the end.
    mutating func asked() {
        following = true
        userScrolling = false
    }
}
