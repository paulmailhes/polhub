import Foundation

/// The title a meeting gets before the calendar knows anything (étape 4): the name of its Meet tab.
public enum MeetingTitle {
    public static func make(tabTitle: String?, code: String?, source: MeetingSource, micOnly: Bool) -> String {
        if source == .wholeMac { return "Enregistrement manuel" }
        if micOnly { return "Réunion dans Dia" }
        var title = (tabTitle ?? "").trimmingCharacters(in: .whitespaces)
        for prefix in ["Meet – ", "Meet - ", "Meet — "] where title.hasPrefix(prefix) {
            title = String(title.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        // An ad hoc meeting's tab only shows its code (phase 0: « Meet – abc-defg-hij »).
        if title.isEmpty || title == code || title == "Meet" { return "Google Meet" }
        return title
    }
}
