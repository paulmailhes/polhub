import Foundation

public enum DurationText {
    /// `12:34`, `1:02:03`.
    public static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let (hours, minutes, rest) = (s / 3600, (s % 3600) / 60, s % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }

    /// `42 min`, `1 h 05`, `moins d'une minute`.
    public static func short(_ seconds: Int) -> String {
        if seconds < 60 { return "moins d'une minute" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }
        return String(format: "%d h %02d", minutes / 60, minutes % 60)
    }
}
