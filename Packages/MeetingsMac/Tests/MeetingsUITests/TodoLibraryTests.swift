import Colin
import Domain
import Foundation
import Persistence
import Testing
@testable import MeetingsUI

/// « Reporter » and « Livré » on the Accueil (0.36.0, 18/11): Paul's own gestures, written as his, with « Annuler » for
/// a few seconds. Every name here is invented.
@MainActor @Suite(.timeLimit(.minutes(1))) struct TodoLibraryTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.firstWeekday = 2
        return calendar
    }

    func at(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    /// Wednesday 18/11/2026, 22:43; Cabinet Martin due yesterday.
    func world(lasts: Duration = .seconds(8)) throws -> (AppDatabase, ProjectStore, ProjectRow, TodoLibrary) {
        let database = try AppDatabase.inMemory(author: .paul)
        let store = ProjectStore(database)
        var martin = try store.addProject(name: "Cabinet Martin", status: .priorite2, at: at(18, 9))
        martin.dueDate = at(17)
        try store.save(martin, at: at(18, 9))
        let now = at(18, 22, 43)
        return (database, store, martin, TodoLibrary(database: database, now: { now }, calendar: calendar, lasts: lasts))
    }

    func line(_ project: ProjectRow, library: TodoLibrary) throws -> TodoRules.Line {
        try #require(library.lines(projects: [project], events: []).first)
    }

    @Test func deliverClearsTheDateAndUndoPutsItBack() throws {
        let (_, store, martin, library) = try world()
        library.deliver(try line(martin, library: library))
        #expect(try store.project(id: martin.id)?.dueDate == nil)
        #expect(try store.journal(projectID: martin.id).map(\.title) == ["Livré le 18/11"])
        #expect(library.settled?.text == "Cabinet Martin livré")
        library.undoSettled()
        #expect(try store.project(id: martin.id)?.dueDate == at(17))
        #expect(try store.journal(projectID: martin.id).isEmpty)
        #expect(library.settled == nil)
    }

    @Test func postponeToMondayWritesAsPaul() throws {
        let (database, store, martin, library) = try world()
        library.postpone(try line(martin, library: library), to: .monday(at(23)))
        #expect(try store.project(id: martin.id)?.dueDate == at(23))
        #expect(try ProjectChanges(database).paulDeadlines().contains(martin.id))
        #expect(library.settled?.text == "Cabinet Martin reporté à lundi")
        library.postpone(try line(martin, library: library), to: at(25))
        #expect(library.settled?.text == "Cabinet Martin reporté à mercredi 25")
    }

    func call(_ project: ProjectRow, day: Int, hour: Int, minute: Int = 0) -> CalendarEventRow {
        CalendarEventRow(account: "moi@exemple.fr", eventID: "point-\(day)", title: "Point", startAt: at(day, hour, minute),
                         endAt: at(day, hour, minute).addingTimeInterval(1_800),
                         attendees: [Attendee(email: "moi@exemple.fr", response: "accepted", isSelf: true)], projectID: project.id, updatedAt: at(1))
    }

    /// Review Focus 1 (0.37.0): « Livré, prochaine échéance » sets the call's day, and the line stays a call.
    @Test func aNextCallLivreStaysACall() async throws {
        let (database, store, martin, library) = try world()
        let next = call(martin, day: 20, hour: 9, minute: 30)
        library.deliver(try line(martin, library: library), next: next)
        #expect(try store.project(id: martin.id)?.dueDate == at(20))
        #expect(try store.journal(projectID: martin.id).map(\.title) == ["Livré le 18/11"])
        #expect(library.settled?.text == "Cabinet Martin livré · call vendredi 9:30")
        #expect(try !ProjectChanges(database).paulDeadlines().contains(martin.id))
        for _ in 0..<100 where library.paulDeadlines.contains(martin.id) { try await Task.sleep(for: .milliseconds(20)) }
        let moved = try #require(try store.project(id: martin.id))
        #expect(library.lines(projects: [moved], events: [next]).first?.call == at(20, 9, 30))
    }

    /// Review Focus 2: « Annuler » puts back the old date and takes the journal line away.
    @Test func undoLivreWithNextCall() throws {
        let (_, store, martin, library) = try world()
        library.deliver(try line(martin, library: library), next: call(martin, day: 20, hour: 9, minute: 30))
        library.undoSettled()
        #expect(try store.project(id: martin.id)?.dueDate == at(17))
        #expect(try store.journal(projectID: martin.id).isEmpty)
    }

    @Test func settledClearsItself() async throws {
        let (_, _, martin, library) = try world(lasts: .milliseconds(50))
        library.deliver(try line(martin, library: library))
        #expect(library.settled != nil)
        for _ in 0..<100 where library.settled != nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(library.settled == nil)
    }

    @Test func linesFollowTheBase() async throws {
        let (_, store, martin, library) = try world()
        _ = try store.signed(.colin, source: "event:x").setDue(martin.id, to: at(19), journal: nil, at: at(18, 20))
        // Colin's date, after Paul's own of the fixture: no longer a deadline of Paul's.
        for _ in 0..<100 where library.paulDeadlines.contains(martin.id) { try await Task.sleep(for: .milliseconds(20)) }
        let moved = try #require(try store.project(id: martin.id))
        let call = CalendarEventRow(account: "moi@exemple.fr", eventID: "point", title: "Point", startAt: at(19, 9, 30), endAt: at(19, 10),
                                    attendees: [Attendee(email: "moi@exemple.fr", response: "accepted", isSelf: true)], projectID: martin.id,
                                    updatedAt: at(1))
        #expect(library.lines(projects: [moved], events: [call]).first?.call == at(19, 9, 30))
    }
}
