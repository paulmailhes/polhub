import Foundation

/// The iPhone's dates and hours, written as the Mac writes them (`Words`, lot 10): « 9:05 », « hier », « 18 nov. »,
/// « jeudi 26 novembre », « 1 h 05 ». French whatever the iPhone's language.
public enum LinkWords {
    public static let locale = Locale(identifier: "fr_FR")

    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.firstWeekday = 2
        return calendar
    }

    static let months = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."]
    static let fullMonths = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"]
    static let weekdays = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]

    /// « 9:05 », « 14:00 »: never a zero before the hour.
    public static func time(_ date: Date, calendar: Calendar = calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return "\(parts.hour ?? 0):" + String(format: "%02d", parts.minute ?? 0)
    }

    /// « 9:30 – 10:00 ».
    public static func timeRange(_ start: Date, _ end: Date, calendar: Calendar = calendar) -> String {
        "\(time(start, calendar: calendar)) – \(time(end, calendar: calendar))"
    }

    /// A list's date: the hour today, « hier », the weekday within the week, else « 18 nov. », « 18 nov. 2025 ».
    public static func listDate(_ date: Date, now: Date = Date(), calendar: Calendar = calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return time(date, calendar: calendar) }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days == 1 { return "hier" }
        if (2...6).contains(days) { return String(weekdays[calendar.component(.weekday, from: date) - 1].prefix(3)) + "." }
        return shortDate(date, now: now, calendar: calendar)
    }

    /// « 18 nov. », « 1er déc. », « 18 nov. 2025 » (another year).
    public static func shortDate(_ date: Date, now: Date = Date(), calendar: Calendar = calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = parts.day == 1 ? "1er" : "\(parts.day ?? 0)"
        let text = "\(day) \(months[(parts.month ?? 1) - 1])"
        return parts.year == calendar.component(.year, from: now) ? text : "\(text) \(parts.year ?? 0)"
    }

    /// A day as a heading: « Aujourd'hui », « Demain », « Hier », else « Jeudi 26 novembre ».
    public static func dayTitle(_ date: Date, now: Date = Date(), calendar: Calendar = calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "Aujourd'hui"
        case 1: return "Demain"
        case -1: return "Hier"
        default:
            let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
            let day = parts.day == 1 ? "1er" : "\(parts.day ?? 0)"
            var text = "\(weekdays[(parts.weekday ?? 1) - 1]) \(day) \(fullMonths[(parts.month ?? 1) - 1])"
            if parts.year != calendar.component(.year, from: now) { text += " \(parts.year ?? 0)" }
            return text.prefix(1).uppercased() + text.dropFirst()
        }
    }

    /// « 42 min », « 1 h 05 », « 2 h ».
    public static func duration(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        guard minutes >= 60 else { return minutes == 0 ? "moins d'une minute" : "\(minutes) min" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h " + String(format: "%02d", rest)
    }

    /// « copie de 18:42 », « copie d'hier 18:42 », « copie du 18 nov. »: when the copy shown was taken.
    public static func kept(_ date: Date, now: Date = Date(), calendar: Calendar = calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "copie de \(time(date, calendar: calendar))" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days == 1 { return "copie d'hier \(time(date, calendar: calendar))" }
        return "copie du \(shortDate(date, now: now, calendar: calendar))"
    }
}
