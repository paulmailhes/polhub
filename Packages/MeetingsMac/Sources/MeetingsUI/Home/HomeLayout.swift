import PolhubDesign
import SwiftUI

/// How the Accueil is laid out (18/11): Colin's column and the lists side by side, or the lists above Colin when
/// the window is narrow.
enum HomeLayout: Equatable {
    case columns, stacked

    /// Two columns from this width of the page's content (0.37.0: the day in cards needs a little more).
    static let breakpoint: CGFloat = 800
    /// The day's column, in cards: « Aujourd'hui », « À valider », « À faire », « Comptes Claude ».
    static let listsWidth: CGFloat = 420

    static func of(width: CGFloat) -> HomeLayout {
        width >= breakpoint ? .columns : .stacked
    }

    /// Colin's column, and his bar under it, in two columns: what the lists leave of the page's content.
    static func colinWidth(content: CGFloat) -> CGFloat {
        content - listsWidth - Space.l
    }
}
