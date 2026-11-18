import Domain
import Foundation
import Persistence

/// « Le point » on the Accueil (18/11): the week, what is due, whose turn it is, what came since the last time. Four
/// sentences at most, made by rules alone: no model, nothing that leaves the Mac.
public enum Briefing {
    /// The events left this week, the one under way included: neither whole days nor those Paul declined. `next`
    /// is the first of them.
    public static func week(_ events: [CalendarEventRow], now: Date, calendar: Calendar) -> (count: Int, next: CalendarEventRow?) {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return (0, nil) }
        let left = events
            .filter { !$0.allDay && $0.endAt > now && $0.startAt < week.end && $0.attendees.first(where: \.isSelf)?.response != "declined" }
            .sorted { $0.startAt < $1.startAt }
        return (left.count, left.first)
    }

    /// The projects to deliver: a due date that is past, or within `withinDays` days, counted in days and not in
    /// hours; never a finished project. The most late first.
    public static func due(_ projects: [ProjectRow], now: Date, calendar: Calendar, withinDays: Int = 7) -> [ProjectRow] {
        projects
            .filter { project in
                guard project.status != .termine, project.deletedAt == nil, let due = project.dueDate else { return false }
                return days(from: now, to: due, calendar: calendar) <= withinDays
            }
            .sorted { ($0.dueDate ?? .distantFuture, $0.name) < ($1.dueDate ?? .distantFuture, $1.name) }
    }

    /// The projects where it is Paul's turn: « priorité 2 », by due date, those without one last.
    public static func yours(_ projects: [ProjectRow]) -> [ProjectRow] {
        projects.filter { $0.status == .priorite2 && $0.deletedAt == nil }.sorted { one, other in
            switch (one.dueDate, other.dueDate) {
            case let (first?, second?) where first != second: return first < second
            case (.some, nil): return true
            case (nil, .some): return false
            default: return (one.kanbanOrder, one.name) < (other.kanbanOrder, other.name)
            }
        }
    }

    /// The threads of a project in which a message was received after `since`.
    public static func clientMails(_ threads: [MailThreadRow], rules: MailFilingRules, since: Date) -> [MailThreadRow] {
        threads.filter { thread in
            !thread.hidden && (thread.lastReceivedAt ?? .distantPast) > since && rules.filing(of: thread)?.filing.projectID != nil
        }
    }

    /// The sentences, four at most: the week always, the others only when they have something to say.
    public static func lines(week: (count: Int, next: CalendarEventRow?), due: [ProjectRow], yours: [ProjectRow], clientMails: Int,
                             since: Date?, now: Date, calendar: Calendar) -> [String] {
        var lines: [String] = []
        if week.count == 0 {
            lines.append("Cette semaine : aucun rendez-vous.")
        } else if let next = week.next {
            let when = dayLabel(next.startAt, now: now, calendar: calendar)
            lines.append(week.count == 1 ? "Cette semaine : 1 rendez-vous, \(when)." : "Cette semaine : \(week.count) rendez-vous, le prochain \(when).")
        } else {
            lines.append("Cette semaine : \(week.count) rendez-vous.")
        }
        if !due.isEmpty {
            let named = due.prefix(3).map { project in "\(project.name) \(dueLabel(project.dueDate ?? now, now: now, calendar: calendar))" }
            let others = due.count - named.count
            lines.append("À livrer : " + named.joined(separator: ", ") + (others > 0 ? " et \(others) \(others == 1 ? "autre" : "autres")" : "") + ".")
        }
        if !yours.isEmpty {
            lines.append(yours.count <= 3 ? "À toi de jouer : " + yours.map(\.name).joined(separator: ", ") + "." : "À toi de jouer : \(yours.count) projets.")
        }
        if let since, clientMails > 0 {
            lines.append("Depuis \(sinceLabel(since, now: now, calendar: calendar)) : \(clientMails) \(clientMails == 1 ? "mail de client" : "mails de clients").")
        }
        return lines
    }

    // MARK: - Days, said as Paul would say them

    /// « aujourd'hui 16:30 », « demain 10:00 », « hier 19:40 », « jeudi 10:00 »; a week away or more, « mercredi 25 à
    /// 9:00 », with the month when it is another one; long ago, « le 2 novembre ».
    public static func dayLabel(_ date: Date, now: Date, calendar: Calendar) -> String {
        let away = days(from: now, to: date, calendar: calendar)
        let hour = time(date, calendar: calendar)
        switch away {
        case 0: return "aujourd'hui \(hour)"
        case 1: return "demain \(hour)"
        case -1: return "hier \(hour)"
        case 2...6, -6 ... -2: return "\(weekday(date, calendar: calendar)) \(hour)"
        case 7...: return "\(weekday(date, calendar: calendar)) \(dayOfMonth(date, now: now, calendar: calendar)) à \(hour)"
        default: return "le \(dayOfMonth(date, now: now, calendar: calendar, always: true))"
        }
    }

    /// When a project is due: « en retard de 2 jours », « aujourd'hui », « demain », « jeudi », « le 25 ».
    static func dueLabel(_ date: Date, now: Date, calendar: Calendar) -> String {
        let away = days(from: now, to: date, calendar: calendar)
        switch away {
        case ..<0: return "en retard de \(-away) \(away == -1 ? "jour" : "jours")"
        case 0: return "aujourd'hui"
        case 1: return "demain"
        case 2...6: return weekday(date, calendar: calendar)
        default: return "le \(dayOfMonth(date, now: now, calendar: calendar))"
        }
    }

    /// Since when: « 8:05 » today, « hier 19:40 », « vendredi 19:40 », « le 2 novembre ».
    static func sinceLabel(_ date: Date, now: Date, calendar: Calendar) -> String {
        days(from: now, to: date, calendar: calendar) == 0 ? time(date, calendar: calendar) : dayLabel(date, now: now, calendar: calendar)
    }

    /// « mardi 9:04 »: the day and the hour « Le point » was prepared, at its head.
    public static func stamp(_ date: Date, calendar: Calendar) -> String {
        "\(weekday(date, calendar: calendar)) \(time(date, calendar: calendar))"
    }

    /// Whole days between two dates, as a calendar counts them: from one day to the next, whatever the hours.
    static func days(from: Date, to: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)).day ?? 0
    }

    /// « 9:05 », « 16:30 ».
    static func time(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = parts.minute ?? 0
        return "\(parts.hour ?? 0):\(minute < 10 ? "0" : "")\(minute)"
    }

    private static let weekdays = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
    private static let months = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"]

    static func weekday(_ date: Date, calendar: Calendar) -> String {
        weekdays[(calendar.component(.weekday, from: date) - 1 + 7) % 7]
    }

    /// « 25 », « 1er »; with the month when it is another one than today's, or when asked.
    static func dayOfMonth(_ date: Date, now: Date, calendar: Calendar, always: Bool = false) -> String {
        let day = calendar.component(.day, from: date), month = calendar.component(.month, from: date)
        let number = day == 1 ? "1er" : String(day)
        let sameMonth = month == calendar.component(.month, from: now) && calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return always || !sameMonth ? "\(number) \(months[(month - 1 + 12) % 12])" : number
    }
}
