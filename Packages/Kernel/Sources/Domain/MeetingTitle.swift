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

    /// A title made without knowing the meeting: the calendar's title replaces it (13/11).
    public static func isGeneric(_ title: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespaces)
        return title.isEmpty || ["Google Meet", "Réunion dans Dia", "Enregistrement manuel"].contains(title)
            || title.wholeMatch(of: #/[a-z]{3}-[a-z]{4}-[a-z]{3}/#) != nil
    }
}
