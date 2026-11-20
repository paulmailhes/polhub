import Foundation
import PolhubDesign

/// Kept for what still calls it; the words are `Words`' (lot 10, 20/11).
public enum DurationText {
    /// `12:34`, `1:02:03`.
    public static func clock(_ seconds: Int) -> String {
        Words.clock(seconds)
    }

    /// `42 min`, `1 h 05`, `2 h`, `moins d'une minute`.
    public static func short(_ seconds: Int) -> String {
        Words.duration(seconds)
    }
}
