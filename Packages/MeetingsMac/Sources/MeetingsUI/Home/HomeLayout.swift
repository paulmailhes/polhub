import PolhubDesign
import SwiftUI

/// How the Accueil is laid out (lot 5, 19/11, « Colin à droite »): the day on the left, 640 points at most; Colin's panel
/// on the right, 420 points, the whole height. In a narrow window, the day alone, Colin's bar floating at its foot.
enum HomeLayout: Equatable {
    case columns, stacked

    /// Colin's panel, at the right edge of the window.
    static let panelWidth: CGFloat = 420
    /// The day's column, at most.
    static let dayWidth: CGFloat = 640
    /// The day's column beside the panel, at least: as wide as its cards were (0.37.0).
    static let dayMinimumWidth: CGFloat = 420
    /// Two columns from this width of the page: the panel and its line, and the day at its narrowest with the page's margins.
    static let breakpoint: CGFloat = panelWidth + 1 + dayMinimumWidth + 2 * PageMetrics.horizontal

    /// `width`: the page's, the whole width the window gives the Accueil.
    static func of(width: CGFloat) -> HomeLayout {
        width >= breakpoint ? .columns : .stacked
    }
}
