import Domain
import Foundation
import Persistence
import Testing
@testable import Colin

/// « Colin tient le kanban seul » (step 3, 18/11): two rules, no model. After a mail Paul sends in a thread of a
/// project, the card waits for the person; a meeting booked in a project becomes its deadline when it has none, or
/// a past one. Every name and address is invented.
@Suite struct KanbanRulesTests {
    let now = Date(timeIntervalSince1970: 1_794_992_400)   // Wednesday 18/11/2026, 10:00 in Paris
    let martin = ProjectRow(name: "Cabinet Martin", status: .priorite2, createdAt: Date(timeIntervalSince1970: 1_790_000_000))
    let mine: Set<String> = ["moi@exemple.fr"]

    var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.firstWeekday = 2
        return calendar
    }

    func sent(_ key: String, thread: String = "fil-devis", to people: [(String, String?)] = [("claire@cabinet.exemple", "Claire Morel")],
              minutesAgo: Double = 10, mine: Bool = true, calendar: Bool = false, automatic: Bool = false) -> MailExchange {
        var names: [String: String] = [:]
        for (email, name) in people { names[email] = name }
        return MailExchange(threadKey: thread, date: now.addingTimeInterval(-minutesAgo * 60), mine: mine, sender: mine ? "moi@exemple.fr" : people.first?.0,
                            recipients: people.map(\.0), calendar: calendar, automatic: automatic, messageKey: key, names: names)
    }

    func sends(_ exchanges: [MailExchange], projects: [ProjectRow]? = nil, sinceMinutes: Double = 24 * 60, known: Set<String> = [],
               touched: Set<ProjectFieldKey> = []) -> [KanbanEdit] {
        KanbanRules.afterSends(exchanges, projectOf: ["fil-devis": martin.id], projects: projects ?? [martin], mine: mine,
                               since: now.addingTimeInterval(-sinceMinutes * 60), known: known, touched: touched, now: now, calendar: paris)
    }

    func with(_ status: ProjectStatus, todo: String? = nil, due: Date? = nil) -> ProjectRow {
        var project = martin
        project.status = status
        project.todo = todo
        project.dueDate = due
        return project
    }

    // MARK: - After a mail

    @Test func aMailSentInAProjectThreadWaitsForX() {
        #expect(sends([sent("m-1")]) == [KanbanEdit(projectID: martin.id, status: .priorite1, todo: "En attente retour de Claire", dueDate: nil,
                                                    journal: "Mail envoyé à Claire le 18/11", reason: "Après ton mail à Claire, 9:50", source: "mail:m-1")])
        // An address with no name is said as it is.
        #expect(sends([sent("m-2", to: [("contact@cabinet.exemple", nil)])]).first?.todo == "En attente retour de contact@cabinet.exemple")
    }

    @Test func priority1StaysAndPauseIsLeftAlone() {
        let waiting = sends([sent("m-1")], projects: [with(.priorite1)])
        #expect(waiting.first?.status == nil && waiting.first?.todo == "En attente retour de Claire")
        #expect(sends([sent("m-1")], projects: [with(.enPause)]).isEmpty)
        #expect(sends([sent("m-1")], projects: [with(.termine)]).isEmpty)
        var gone = martin
        gone.deletedAt = now
        #expect(sends([sent("m-1")], projects: [gone]).isEmpty)
    }

    /// Only what was sent since the switch was turned on, and in the last seven days.
    @Test func aMailBeforeTheSwitchCountsNot() {
        #expect(sends([sent("m-1", minutesAgo: 30)], sinceMinutes: 20).isEmpty)
        #expect(sends([sent("m-1", minutesAgo: 8 * 24 * 60)], sinceMinutes: 30 * 24 * 60).isEmpty)
    }

    @Test func aFieldPaulChangedTodayIsKept() {
        let status = sends([sent("m-1")], touched: [ProjectFieldKey(projectID: martin.id, field: .status)])
        #expect(status.first?.status == nil && status.first?.todo == "En attente retour de Claire")
        let both = sends([sent("m-1")], touched: [ProjectFieldKey(projectID: martin.id, field: .status), ProjectFieldKey(projectID: martin.id, field: .todo)])
        #expect(both.first?.status == nil && both.first?.todo == nil && both.first?.journal == "Mail envoyé à Claire le 18/11")
    }

    @Test func aKnownSourceIsNotDoneAgain() {
        #expect(sends([sent("m-1")], known: ["mail:m-1"]).isEmpty)
    }

    @Test func onlyAMailOfPaulsToSomeoneCounts() {
        #expect(sends([sent("m-1", to: [("moi@exemple.fr", "Moi")])]).isEmpty)
        #expect(sends([sent("m-1", mine: false)]).isEmpty)
        #expect(sends([sent("m-1", calendar: true)]).isEmpty)
        #expect(sends([sent("m-1", automatic: true)]).isEmpty)
        #expect(sends([sent("m-1", thread: "fil-ailleurs")]).isEmpty)
        // The first person who is not Paul.
        #expect(sends([sent("m-1", to: [("moi@exemple.fr", "Moi"), ("marc@studio.exemple", "Marc Dubois")])]).first?.todo == "En attente retour de Marc")
    }

    /// Two mails of one project in one pass: the card changes once, each mail has its line in the journal.
    @Test func twoMailsInOnePassChangeTheCardOnce() {
        let edits = sends([sent("m-1", minutesAgo: 30), sent("m-2", minutesAgo: 10)])
        #expect(edits.count == 2)
        #expect(edits[0].status == .priorite1 && edits[0].todo == "En attente retour de Claire")
        #expect(edits[1].status == nil && edits[1].todo == nil && edits[1].journal == "Mail envoyé à Claire le 18/11")
    }

    // MARK: - A meeting booked

    func event(_ id: String, project: UUID?, inDays days: Double, allDay: Bool = false, declined: Bool = false) -> CalendarEventRow {
        let start = now.addingTimeInterval(days * 86_400)
        return CalendarEventRow(account: "moi@exemple.fr", eventID: id, title: "Point devis", startAt: start, endAt: start.addingTimeInterval(1_800),
                                allDay: allDay, attendees: [Attendee(email: "moi@exemple.fr", response: declined ? "declined" : "accepted", isSelf: true)],
                                projectID: project, updatedAt: now)
    }

    func bookings(_ events: [CalendarEventRow], projects: [ProjectRow]? = nil, known: Set<String> = [], touched: Set<ProjectFieldKey> = []) -> [KanbanEdit] {
        KanbanRules.afterBookings(events, projects: projects ?? [martin], now: now, known: known, touched: touched, calendar: paris)
    }

    @Test func aMeetingBecomesTheEmptyDeadline() {
        let tomorrow = event("e-1", project: martin.id, inDays: 1)
        let day = paris.startOfDay(for: tomorrow.startAt)
        #expect(bookings([event("e-2", project: martin.id, inDays: 6), tomorrow]) == [
            KanbanEdit(projectID: martin.id, status: nil, todo: nil, dueDate: day, journal: nil, reason: "Rendez-vous du jeudi 19/11", source: "event:\(tomorrow.id)"),
        ])
        // A past deadline too.
        #expect(bookings([tomorrow], projects: [with(.priorite1, due: now.addingTimeInterval(-2 * 86_400))]).first?.dueDate == day)
    }

    @Test func aDeadlineToComeStays() {
        #expect(bookings([event("e-1", project: martin.id, inDays: 1)], projects: [with(.priorite2, due: now.addingTimeInterval(10 * 86_400))]).isEmpty)
        // Today is not past.
        #expect(bookings([event("e-1", project: martin.id, inDays: 1)], projects: [with(.priorite2, due: paris.startOfDay(for: now))]).isEmpty)
    }

    @Test func aMeetingThatCannotBeTheDeadlineCountsNot() {
        #expect(bookings([event("e-1", project: martin.id, inDays: 1, allDay: true)]).isEmpty)
        #expect(bookings([event("e-1", project: martin.id, inDays: 1, declined: true)]).isEmpty)
        #expect(bookings([event("e-1", project: martin.id, inDays: -1)]).isEmpty)
        #expect(bookings([event("e-1", project: nil, inDays: 1)]).isEmpty)
        #expect(bookings([event("e-1", project: martin.id, inDays: 1)], projects: [with(.enPause)]).isEmpty)
        #expect(bookings([event("e-1", project: martin.id, inDays: 1)], known: ["event:moi@exemple.fr|e-1"]).isEmpty)
        #expect(bookings([event("e-1", project: martin.id, inDays: 1)], touched: [ProjectFieldKey(projectID: martin.id, field: .dueDate)]).isEmpty)
    }
}
