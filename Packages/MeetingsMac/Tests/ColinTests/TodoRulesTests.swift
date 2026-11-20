import Domain
import Foundation
import Persistence
import Testing
@testable import Colin

/// « À faire » on the Accueil (0.36.0, 18/11): the projects where it is Paul's turn and those with a deadline close,
/// grouped by day, a call said as one. Every name here is invented.
@Suite struct TodoRulesTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.firstWeekday = 2
        return calendar
    }

    /// A day of November 2026, in Paris (the 30th + n is in December).
    func at(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    /// Wednesday 18/11/2026, 22:43.
    var now: Date { at(18, 22, 43) }

    func project(_ name: String, _ status: ProjectStatus = .priorite1, due: Date? = nil, todo: String? = nil, client: String? = nil,
                 order: Double = 0) -> ProjectRow {
        ProjectRow(name: name, status: status, client: client, dueDate: due, todo: todo, kanbanOrder: order, createdAt: at(1))
    }

    func event(_ project: ProjectRow, day: Int, hour: Int, minute: Int = 0, hours: Double = 1, declined: Bool = false) -> CalendarEventRow {
        CalendarEventRow(account: "moi@exemple.fr", eventID: "\(project.name)-\(day)-\(hour)", title: "Point", startAt: at(day, hour, minute),
                         endAt: at(day, hour, minute).addingTimeInterval(hours * 3_600),
                         attendees: [Attendee(email: "moi@exemple.fr", response: declined ? "declined" : "accepted", isSelf: true)],
                         projectID: project.id, updatedAt: at(1))
    }

    func lines(_ projects: [ProjectRow], events: [CalendarEventRow] = [], paulDeadlines: Set<UUID> = [], actions: [UUID: String] = [:],
               at date: Date? = nil) -> [TodoRules.Line] {
        TodoRules.lines(projects: projects, events: events, paulDeadlines: paulDeadlines, firstActions: actions, now: date ?? now, calendar: calendar)
    }

    func when(_ line: TodoRules.Line?, at date: Date? = nil) -> String? {
        line.flatMap { TodoRules.when($0, now: date ?? now, calendar: calendar) }
    }

    @Test func keepsPriority2AndNearDeadlines() {
        let kept = [project("Studio Nord", due: at(21)), project("Cabinet Martin", .priorite2)]
        var deleted = project("Supprimé", .priorite2)
        deleted.deletedAt = at(2)
        let dropped = [project("En pause", .enPause, due: at(17)), project("Loin", due: at(27)), project("Fini", .termine, due: at(18)), deleted]
        #expect(Set(lines(kept + dropped).map(\.name)) == ["Studio Nord", "Cabinet Martin"])
    }

    @Test func groupsByDayInOrder() {
        let projects = [project("Ensuite", .priorite2), project("Semaine", due: at(23)), project("Demain", due: at(19)),
                        project("Aujourd'hui", due: at(18)), project("Retard", due: at(12))]
        let found = lines(projects)
        #expect(found.map(\.group) == [.late, .today, .tomorrow, .week, .later])
        #expect(found.map(\.name) == ["Retard", "Aujourd'hui", "Demain", "Semaine", "Ensuite"])
        #expect(TodoRules.Group.allCases.map(TodoRules.title) == ["En retard", "Aujourd'hui", "Demain", "Cette semaine", "Ensuite"])
    }

    @Test func aCallSaysItsHour() {
        let martin = project("Cabinet Martin", due: at(19))
        let call = event(martin, day: 19, hour: 9, minute: 30)
        let byColin = lines([martin], events: [call]).first
        #expect(byColin?.call == at(19, 9, 30))
        #expect(when(byColin) == "visio demain 9:30")
        // Set before the journal: no one known, a call all the same.
        #expect(when(lines([martin], events: [call]).first) == "visio demain 9:30")
        // On the day, and a few days off.
        #expect(when(lines([martin], events: [call]).first, at: at(19, 8)) == "visio aujourd'hui 9:30")
        #expect(when(lines([martin], events: [call]).first, at: at(16, 8)) == "visio jeudi 9:30")
    }

    /// Review Focus 1: a deadline Paul set himself stays one, whatever meeting falls that day.
    @Test func aDeadlinePaulSetIsNeverACall() {
        let martin = project("Cabinet Martin", due: at(19))
        let call = event(martin, day: 19, hour: 9, minute: 30)
        let line = lines([martin], events: [call], paulDeadlines: [martin.id]).first
        #expect(line?.call == nil)
        #expect(when(line) == "demain")
        let after = lines([martin], events: [call], paulDeadlines: [martin.id], at: at(20, 10)).first
        #expect(after?.group == .late)
        #expect(when(after, at: at(20, 10)) == "depuis 1 j")
    }

    @Test func aCallDoneLeavesTheList() {
        let waiting = project("Cabinet Martin", due: at(18))
        let mine = project("Studio Nord", .priorite2, due: at(18))
        let events = [event(waiting, day: 18, hour: 9, minute: 30, hours: 0.5), event(mine, day: 18, hour: 9, minute: 30, hours: 0.5)]
        let found = lines([waiting, mine], events: events, at: at(18, 11))
        #expect(found.map(\.name) == ["Studio Nord"])
        #expect(found.first?.group == .later && found.first?.due == nil && found.first?.call == nil)
        #expect(when(found.first, at: at(18, 11)) == nil)
    }

    @Test func aDeclinedMeetingIsNoCall() {
        let martin = project("Cabinet Martin", due: at(19))
        let line = lines([martin], events: [event(martin, day: 19, hour: 9, declined: true)]).first
        #expect(line?.call == nil && when(line) == "demain")
    }

    @Test func detailIsTheTaskElseTheFirstAction() {
        let withTask = project("Cabinet Martin", .priorite2, todo: "Retours de Claire à traiter")
        let blank = project("Studio Nord", .priorite2, todo: "  ")
        let bare = project("Atelier Dupont", .priorite2)
        let found = lines([withTask, blank, bare], actions: [blank.id: "Envoyer la maquette", withTask.id: "Autre chose"])
        #expect(found.first { $0.id == withTask.id }?.detail == "Retours de Claire à traiter")
        #expect(found.first { $0.id == blank.id }?.detail == "Envoyer la maquette")
        #expect(found.first { $0.id == bare.id }?.detail == nil)
    }

    @Test func whenWords() {
        #expect(when(lines([project("A", due: at(12))]).first) == "depuis 6 j")
        #expect(when(lines([project("A", due: at(20))]).first) == "vendredi")
        #expect(when(lines([project("A", .priorite2, due: at(30))]).first) == "lundi 30")
        #expect(when(lines([project("A", .priorite2, due: at(32))]).first) == "mercredi 2 décembre")
    }

    @Test func sameGroupByDateThenBoard() {
        let found = lines([project("B", due: at(12), order: 2), project("A", due: at(12), order: 1), project("C", due: at(10), order: 3)])
        #expect(found.map(\.name) == ["C", "A", "B"])
    }

    /// Review Focus 3: many late projects never hide today's and tomorrow's.
    @Test func todayAndTomorrowAreNeverFolded() {
        let late = (1...8).map { project("Retard \($0)", due: at(10), order: Double($0)) }
        let found = lines(late + [project("Aujourd'hui", due: at(18)), project("Demain", due: at(19))])
        let folded = TodoRules.visible(found, limit: 6, expanded: false)
        #expect(folded.shown.map(\.name) == ["Retard 1", "Retard 2", "Retard 3", "Retard 4", "Aujourd'hui", "Demain"])
        #expect(folded.hidden == 4)
        let open = TodoRules.visible(found, limit: 6, expanded: true)
        #expect(open.shown.count == 10 && open.hidden == 0)
    }

    @Test func postponeChoices() {
        #expect(TodoRules.postpone(due: nil, now: now, calendar: calendar) == [.tomorrow(at(19)), .monday(at(23)), .inAWeek(at(25))])
        #expect(TodoRules.postpone(due: at(23), now: now, calendar: calendar) == [.inAWeek(at(25))])
        #expect(TodoRules.postpone(due: at(18), now: now, calendar: calendar) == [.tomorrow(at(19)), .monday(at(23)), .inAWeek(at(25))])
        // On a Monday, « Lundi » and « Dans une semaine » fall the same day: said once.
        #expect(TodoRules.postpone(due: nil, now: at(23, 9), calendar: calendar) == [.tomorrow(at(24)), .monday(at(30))])
        #expect(TodoRules.postpone(due: nil, now: now, calendar: calendar).map(\.label) == ["Demain", "Lundi", "Dans une semaine"])
    }

    /// 0.37.0: « Livré » proposes the project's next call as the new deadline.
    @Test func nextCallSkipsDeclinedWholeDaysAndPast() {
        let martin = project("Cabinet Martin", due: at(17))
        var whole = event(martin, day: 19, hour: 0, hours: 24)
        whole.allDay = true
        let events = [event(martin, day: 18, hour: 9), event(martin, day: 19, hour: 11, declined: true), whole,
                      event(martin, day: 23, hour: 10), event(martin, day: 20, hour: 9, minute: 30)]
        #expect(TodoRules.nextCall(martin.id, events: events, now: now)?.startAt == at(20, 9, 30))
        #expect(TodoRules.nextCall(martin.id, events: [event(martin, day: 18, hour: 9)], now: now) == nil)
        #expect(TodoRules.nextCall(UUID(), events: events, now: now) == nil)
    }

    @Test func deliveredNextSaysTheCall() {
        let martin = project("Cabinet Martin")
        #expect(TodoRules.deliveredNext(event(martin, day: 19, hour: 9, minute: 30), now: now, calendar: calendar)
                == "Livré, prochaine échéance : visio demain 9:30")
        #expect(TodoRules.deliveredNext(event(martin, day: 23, hour: 10), now: now, calendar: calendar)
                == "Livré, prochaine échéance : visio lundi 10:00")
    }

    @Test func deliveredSaysTheDay() {
        #expect(TodoRules.delivered(now, calendar: calendar) == "Livré le 18 nov.")
    }

    @Test func datedKeepsTheProjectsWithADate() {
        let martin = project("Cabinet Martin", due: at(19)), nord = project("Studio Nord", .priorite2)
        let found = lines([martin, nord])
        #expect(TodoRules.dated(found, projects: [martin, nord]).map(\.name) == ["Cabinet Martin"])
    }
}
