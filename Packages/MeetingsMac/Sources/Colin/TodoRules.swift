import Domain
import Foundation
import Persistence

/// « À faire » on the Accueil (0.36.0, 18/11): the projects where it is Paul's turn (« priorité 2 ») and those whose
/// deadline is past or within a week, grouped by day, the late first. A deadline is the next dated step: a meeting of
/// the project that day, when Paul did not set the date himself, makes it a call; once the call is over, the step is
/// done. Made by rules alone, nothing that leaves the Mac.
public enum TodoRules {
    public enum Group: Int, CaseIterable, Comparable, Sendable {
        case late, today, tomorrow, week, later

        public static func < (lhs: Group, rhs: Group) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// The title of a group.
    public static func title(_ group: Group) -> String {
        switch group {
        case .late: "En retard"
        case .today: "Aujourd'hui"
        case .tomorrow: "Demain"
        case .week: "Cette semaine"
        case .later: "Ensuite"
        }
    }

    /// One project of the list.
    public struct Line: Identifiable, Equatable, Sendable {
        /// The project's.
        public var id: UUID
        public var name: String
        public var client: String?
        public var group: Group
        /// The deadline; `nil` when there is none, or the call it was is over.
        public var due: Date?
        /// When the deadline is a call: its start.
        public var call: Date?
        /// The task of the moment, else the first action left.
        public var detail: String?
        public var status: ProjectStatus
        var order: Double

        public init(id: UUID, name: String, client: String? = nil, group: Group, due: Date? = nil, call: Date? = nil, detail: String? = nil,
                    status: ProjectStatus, order: Double = 0) {
            self.id = id
            self.name = name
            self.client = client
            self.group = group
            self.due = due
            self.call = call
            self.detail = detail
            self.status = status
            self.order = order
        }
    }

    /// The deadlines at most this many days away count.
    static let horizon = 7

    /// The list. `paulDeadlines`: the projects whose deadline Paul set himself (`ProjectChanges.paulDeadlines`), never a
    /// call; `firstActions`: the first action left of each project.
    public static func lines(projects: [ProjectRow], events: [CalendarEventRow], paulDeadlines: Set<UUID>, firstActions: [UUID: String],
                             now: Date, calendar: Calendar) -> [Line] {
        let meetings = Dictionary(grouping: events.filter { event in
            event.projectID != nil && !event.allDay && event.attendees.first(where: \.isSelf)?.response != "declined"
        }, by: { $0.projectID! })
        var lines: [Line] = []
        for project in projects where project.deletedAt == nil && project.status != .enPause && project.status != .termine {
            let mine = project.status == .priorite2
            var due = project.dueDate
            var call: Date?
            if let date = due, !paulDeadlines.contains(project.id) {
                let thatDay = (meetings[project.id] ?? []).filter { calendar.isDate($0.startAt, inSameDayAs: date) }
                if !thatDay.isEmpty {
                    if let coming = thatDay.filter({ $0.endAt > now }).min(by: { $0.startAt < $1.startAt }) {
                        call = coming.startAt
                    } else {
                        // The call is over: the step is done.
                        guard mine else { continue }
                        due = nil
                    }
                }
            }
            let group: Group
            if let due {
                let away = Briefing.days(from: now, to: due, calendar: calendar)
                switch away {
                case ..<0: group = .late
                case 0: group = .today
                case 1: group = .tomorrow
                case 2...horizon: group = .week
                default:
                    guard mine else { continue }
                    group = .later
                }
            } else {
                guard mine else { continue }
                group = .later
            }
            let task = project.todo?.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = task.flatMap { $0.isEmpty ? nil : $0 } ?? firstActions[project.id]
            lines.append(Line(id: project.id, name: project.name, client: project.client, group: group, due: due, call: call, detail: detail,
                              status: project.status, order: project.kanbanOrder))
        }
        return lines.sorted { one, other in
            if one.group != other.group { return one.group < other.group }
            switch (one.due, other.due) {
            case let (first?, second?) where first != second: return first < second
            case (.some, nil): return true
            case (nil, .some): return false
            default: return (one.order, one.name) < (other.order, other.name)
            }
        }
    }

    /// When, in words: « depuis 6 j », « aujourd'hui », « demain », « jeudi », « lundi 30 », « mercredi 2 décembre »;
    /// a call, « call demain 9:30 ». Nothing for a project without a date.
    public static func when(_ line: Line, now: Date, calendar: Calendar) -> String? {
        guard let due = line.due else { return nil }
        let away = Briefing.days(from: now, to: due, calendar: calendar)
        if let call = line.call {
            return callWords(call, now: now, calendar: calendar)
        }
        if away < 0 { return "depuis \(-away) j" }
        return dayWord(due, now: now, calendar: calendar)
    }

    /// A day in words: « aujourd'hui », « demain », « jeudi », « lundi 30 », « mercredi 2 décembre »; past, « le 12 novembre ».
    public static func dayWord(_ date: Date, now: Date, calendar: Calendar) -> String {
        switch Briefing.days(from: now, to: date, calendar: calendar) {
        case ..<0: "le \(Briefing.dayOfMonth(date, now: now, calendar: calendar, always: true))"
        case 0: "aujourd'hui"
        case 1: "demain"
        case 2...6: Briefing.weekday(date, calendar: calendar)
        default: "\(Briefing.weekday(date, calendar: calendar)) \(Briefing.dayOfMonth(date, now: now, calendar: calendar))"
        }
    }

    /// What shows of the list folded: today's and tomorrow's always; the others, in order, up to `limit` lines in all.
    public static func visible(_ lines: [Line], limit: Int, expanded: Bool) -> (shown: [Line], hidden: Int) {
        guard !expanded else { return (lines, 0) }
        let kept = lines.filter { $0.group == .today || $0.group == .tomorrow }
        var room = max(0, limit - kept.count)
        var shown: [Line] = []
        for line in lines {
            if line.group == .today || line.group == .tomorrow {
                shown.append(line)
            } else if room > 0 {
                shown.append(line)
                room -= 1
            }
        }
        return (shown, lines.count - shown.count)
    }

    /// A choice of « Reporter ».
    public enum Postpone: Equatable, Sendable {
        case tomorrow(Date), monday(Date), inAWeek(Date)

        public var date: Date {
            switch self {
            case let .tomorrow(date), let .monday(date), let .inAWeek(date): date
            }
        }

        public var label: String {
            switch self {
            case .tomorrow: "Demain"
            case .monday: "Lundi"
            case .inAWeek: "Dans une semaine"
            }
        }
    }

    /// The choices of « Reporter », counted from today, at the start of their day: never one that does not fall after
    /// the deadline (it would bring it earlier), never twice the same day.
    public static func postpone(due: Date?, now: Date, calendar: Calendar) -> [Postpone] {
        let today = calendar.startOfDay(for: now)
        func plus(_ days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: today) ?? today }
        let weekday = calendar.component(.weekday, from: today)   // 1 = Sunday … 2 = Monday
        let toMonday = (9 - weekday) % 7
        let choices: [Postpone] = [.tomorrow(plus(1)), .monday(plus(toMonday == 0 ? 7 : toMonday)), .inAWeek(plus(7))]
        let after = due.map { calendar.startOfDay(for: $0) }
        var seen: Set<Date> = []
        return choices.filter { choice in
            if let after, choice.date <= after { return false }
            return seen.insert(choice.date).inserted
        }
    }

    /// The projects of the lines with a date within the week, late ones included, in the lines' order: « Le point »
    /// and Colin's bar say these.
    public static func dated(_ lines: [Line], projects: [ProjectRow]) -> [ProjectRow] {
        let byID = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return lines.filter { $0.due != nil && $0.group != .later }.compactMap { byID[$0.id] }
    }

    /// The project's next call (0.37.0): its first meeting to come, neither declined nor a whole day. « Livré » proposes it
    /// as the next deadline.
    public static func nextCall(_ projectID: UUID, events: [CalendarEventRow], now: Date) -> CalendarEventRow? {
        events
            .filter { $0.projectID == projectID && !$0.allDay && $0.startAt > now && $0.attendees.first(where: \.isSelf)?.response != "declined" }
            .min { $0.startAt < $1.startAt }
    }

    /// « Livré, prochaine échéance : call jeudi 9:30 ».
    public static func deliveredNext(_ call: CalendarEventRow, now: Date, calendar: Calendar) -> String {
        "Livré, prochaine échéance : \(callWords(call.startAt, now: now, calendar: calendar))"
    }

    /// « call jeudi 9:30 ».
    public static func callWords(_ date: Date, now: Date, calendar: Calendar) -> String {
        "call \(dayWord(date, now: now, calendar: calendar)) \(Briefing.time(date, calendar: calendar))"
    }

    /// The journal's line of « Livré »: « Livré le 18/11 ».
    public static func delivered(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.day, .month], from: date)
        return String(format: "Livré le %02d/%02d", parts.day ?? 0, parts.month ?? 0)
    }
}
