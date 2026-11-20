import Domain
import Foundation
import Persistence
import HubDesign

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

    /// How many projects moved without Paul (step 3, 18/11): by Colin or by an agent, and not undone.
    public static func moved(_ lines: [ProjectChangeLine]) -> Int {
        Set(lines.filter { $0.who != .paul && $0.undoneAt == nil }.map(\.projectID)).count
    }

    /// A sentence of « Le point » (lot 10, 20/11): what it speaks of, then what it says. The Accueil finds a line by its
    /// kind and shows its label and its text apart, never by cutting the sentence or reading its first word.
    public struct Line: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// The meetings left this week: always there.
            case week
            /// The projects to deliver.
            case due
            /// The projects where it is Paul's turn.
            case yours
            /// What came since Paul last came.
            case since
        }

        public let kind: Kind
        /// What it speaks of: « Cette semaine », « À livrer », « À toi de jouer », « Depuis hier 19:40 ».
        public let label: String
        /// What it says, a sentence's end: « aucun rendez-vous. », « 1 mail de client, 2 projets ont bougé. ».
        public let text: String

        public init(_ kind: Kind, label: String, text: String) {
            self.kind = kind
            self.label = label
            self.text = text
        }

        /// The whole sentence: « Cette semaine : aucun rendez-vous. ».
        public var sentence: String { "\(label) : \(text)" }
    }

    /// The sentences, four at most: the week always, the others only when they have something to say. `moved`: the
    /// projects that moved without Paul since he last came.
    public static func lines(week: (count: Int, next: CalendarEventRow?), due: [ProjectRow], yours: [ProjectRow], clientMails: Int, moved: Int = 0,
                             since: Date?, now: Date, calendar: Calendar) -> [Line] {
        var lines: [Line] = []
        if week.count == 0 {
            lines.append(Line(.week, label: "Cette semaine", text: "aucun rendez-vous."))
        } else if let next = week.next {
            let when = dayLabel(next.startAt, now: now, calendar: calendar)
            lines.append(Line(.week, label: "Cette semaine", text: week.count == 1 ? "1 rendez-vous, \(when)." : "\(Words.count(week.count, "rendez-vous")), le prochain \(when)."))
        } else {
            lines.append(Line(.week, label: "Cette semaine", text: Words.count(week.count, "rendez-vous") + "."))
        }
        if !due.isEmpty {
            let named = due.prefix(3).map { project in "\(project.name) \(dueLabel(project.dueDate ?? now, now: now, calendar: calendar))" }
            let others = due.count - named.count
            lines.append(Line(.due, label: "À livrer",
                              // Accorded by `Words` (lot 10, 20/11).
                              text: named.joined(separator: ", ") + (others > 0 ? " et " + Words.count(others, "autre") : "") + "."))
        }
        if !yours.isEmpty {
            lines.append(Line(.yours, label: "À toi de jouer", text: yours.count <= 3 ? yours.map(\.name).joined(separator: ", ") + "." : Words.count(yours.count, "projet") + "."))
        }
        if let since, clientMails > 0 || moved > 0 {
            var said: [String] = []
            if clientMails > 0 { said.append(Words.count(clientMails, "mail de client", "mails de clients")) }
            if moved > 0 { said.append(Words.count(moved, "projet") + " " + Words.plural(moved, "a bougé", "ont bougé")) }
            lines.append(Line(.since, label: "Depuis \(sinceLabel(since, now: now, calendar: calendar))", text: said.joined(separator: ", ") + "."))
        }
        return lines
    }

    // MARK: - Days, said as Paul would say them, by `Words` (lot 10, 20/11: made by hand here, `Words` took them)

    /// « aujourd'hui 16:30 », « demain 10:00 », « hier 19:40 », « jeudi 10:00 »; a week away or more, « mercredi 25 à
    /// 9:00 », with the month when it is another one; long ago, « le 2 novembre ».
    public static func dayLabel(_ date: Date, now: Date, calendar: Calendar) -> String {
        Words.moment(date, now: now, calendar: calendar)
    }

    /// When a project is due: « en retard de 2 jours », « aujourd'hui », « demain », « jeudi », « mercredi 25 ».
    static func dueLabel(_ date: Date, now: Date, calendar: Calendar) -> String {
        let away = days(from: now, to: date, calendar: calendar)
        return away < 0 ? "en retard de " + Words.dayCount(-away) : Words.day(date, now: now, calendar: calendar)
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
        Words.days(from: from, to: to, calendar: calendar)
    }

    /// « 9:05 », « 16:30 ».
    static func time(_ date: Date, calendar: Calendar) -> String {
        Words.time(date, calendar: calendar)
    }

    /// « jeudi ».
    static func weekday(_ date: Date, calendar: Calendar) -> String {
        Words.weekday(date, calendar: calendar)
    }
}
