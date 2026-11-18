import Domain
import Foundation
import Persistence
import Testing
@testable import Colin

/// « Le point » (18/11): four sentences at most, made by rules alone. Every name here is invented.
@Suite struct BriefingTests {
    /// Wednesday 18/11/2026, 10:00 in Paris.
    let now = Date(timeIntervalSince1970: 1_794_992_400)
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.firstWeekday = 2
        return calendar
    }

    /// A day of November 2026, in Paris.
    func at(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func event(_ id: String, day: Int, hour: Int, minute: Int = 0, hours: Double = 1, allDay: Bool = false, declined: Bool = false) -> CalendarEventRow {
        CalendarEventRow(account: "moi@exemple.fr", eventID: id, title: id, startAt: at(day, hour, minute), endAt: at(day, hour, minute).addingTimeInterval(hours * 3_600),
                         allDay: allDay, attendees: [Attendee(email: "moi@exemple.fr", response: declined ? "declined" : "accepted", isSelf: true)], updatedAt: now)
    }

    func project(_ name: String, _ status: ProjectStatus = .priorite2, due: Date? = nil, deleted: Bool = false, order: Double = 0) -> ProjectRow {
        ProjectRow(name: name, status: status, dueDate: due, kanbanOrder: order, createdAt: at(1), deletedAt: deleted ? at(2) : nil)
    }

    func lines(week: (count: Int, next: CalendarEventRow?) = (0, nil), due: [ProjectRow] = [], yours: [ProjectRow] = [], clientMails: Int = 0,
               moved: Int = 0, since: Date? = nil, at date: Date? = nil) -> [String] {
        Briefing.lines(week: week, due: due, yours: yours, clientMails: clientMails, moved: moved, since: since, now: date ?? now, calendar: calendar)
    }

    /// « Le point · mardi 9:04 »: the day and the hour it was prepared, said as its sentences say them.
    @Test func thePointCarriesItsDayAndItsHour() {
        #expect(Briefing.stamp(at(17, 9, 4), calendar: calendar) == "mardi 9:04")
        #expect(Briefing.stamp(at(20, 19, 40), calendar: calendar) == "vendredi 19:40")
    }

    // MARK: - The week

    @Test func theWeekCountsNeitherWholeDaysNorDeclined() {
        let events = [
            event("hier", day: 17, hour: 9),                               // over
            event("en-cours", day: 18, hour: 9, minute: 30),               // under way at 10:00
            event("tantot", day: 18, hour: 16, minute: 30),
            event("jeudi", day: 19, hour: 10),
            event("refuse", day: 20, hour: 10, declined: true),
            event("journee", day: 21, hour: 0, hours: 24, allDay: true),
            event("dimanche", day: 22, hour: 20),
            event("lundi-prochain", day: 23, hour: 9),
        ]
        let week = Briefing.week(events, now: now, calendar: calendar)
        #expect(week.count == 4)
        #expect(week.next?.eventID == "en-cours")
        #expect(Briefing.week([], now: now, calendar: calendar).count == 0)
        #expect(Briefing.week([event("hier", day: 17, hour: 9)], now: now, calendar: calendar).next == nil)
    }

    // MARK: - What is due, and whose turn it is

    @Test func aDueDateWithAnHourIsComparedByDay() {
        let today = project("Aujourd'hui", due: at(18, 23)), yesterday = project("Hier", due: at(17, 23, 59))
        let inSeven = project("Dans sept jours", due: at(25, 8)), inEight = project("Dans huit jours", due: at(26, 8))
        let due = Briefing.due([inEight, inSeven, today, yesterday, project("Sans date")], now: now, calendar: calendar)
        // The most late first, then by date.
        #expect(due.map(\.name) == ["Hier", "Aujourd'hui", "Dans sept jours"])
        // Due today at 23:00 is due today, never late; yesterday at 23:59 is one day late.
        #expect(lines(due: [yesterday, today]) == ["Cette semaine : aucun rendez-vous.", "À livrer : Hier en retard de 1 jour, Aujourd'hui aujourd'hui."])
    }

    @Test func aFinishedProjectIsNeverDue() {
        let projects = [project("Fini", .termine, due: at(10)), project("À la corbeille", due: at(19), deleted: true), project("En pause", .enPause, due: at(19))]
        #expect(Briefing.due(projects, now: now, calendar: calendar).map(\.name) == ["En pause"])
    }

    @Test func yoursAreByDueDateUndatedLast() {
        let projects = [
            project("Mercredi prochain", due: at(25)), project("Sans date, second", order: 2), project("Vendredi", due: at(20)),
            project("Priorité 1", .priorite1, due: at(19)), project("Sans date, premier", order: 1), project("Jeté", due: at(19), deleted: true),
        ]
        #expect(Briefing.yours(projects).map(\.name) == ["Vendredi", "Mercredi prochain", "Sans date, premier", "Sans date, second"])
    }

    // MARK: - The mails of clients

    @Test func theMailsOfClientsAreThoseOfAProjectReceivedSince() {
        let site = UUID()
        let rules = MailFilingRules(contactProjects: ["claire@cabinet.exemple": [site]], contacts: ["claire@cabinet.exemple"],
                                    projects: [(site, "Cabinet Martin")], mine: ["moi@exemple.fr"])
        func thread(_ id: String, from: String, receivedAt: Date?, hidden: Bool = false) -> MailThreadRow {
            let message = MailMessageRow(account: "moi@exemple.fr", messageID: id, threadID: id, date: receivedAt ?? at(1), sender: MailAddress(email: from),
                                         subject: "Devis", snippet: "", labels: receivedAt == nil ? ["SENT"] : (hidden ? ["TRASH"] : ["INBOX"]))
            return MailThreadRow.aggregate(account: "moi@exemple.fr", threadID: id, messages: [message], mine: ["moi@exemple.fr"])!
        }
        let since = at(17, 19, 40)
        let threads = [
            thread("nouveau", from: "claire@cabinet.exemple", receivedAt: at(18, 8)),
            thread("avant", from: "claire@cabinet.exemple", receivedAt: at(17, 12)),
            thread("hors-projet", from: "marc@exemple.net", receivedAt: at(18, 9)),
            thread("jete", from: "claire@cabinet.exemple", receivedAt: at(18, 9), hidden: true),
        ]
        #expect(Briefing.clientMails(threads, rules: rules, since: since).map(\.threadID) == ["nouveau"])
    }

    // MARK: - The sentences

    @Test func theSentencesAreTheOnesOfTheDesign() {
        // The week.
        #expect(lines(week: (5, event("demain", day: 19, hour: 10))) == ["Cette semaine : 5 rendez-vous, le prochain demain 10:00."])
        #expect(lines(week: (1, event("tantot", day: 18, hour: 16, minute: 30))) == ["Cette semaine : 1 rendez-vous, aujourd'hui 16:30."])
        #expect(lines(week: (2, event("vendredi", day: 20, hour: 9, minute: 5))) == ["Cette semaine : 2 rendez-vous, le prochain vendredi 9:05."])
        #expect(lines() == ["Cette semaine : aucun rendez-vous."])
        // What is due. On a Tuesday, as in the design: Thursday is « jeudi »; the next day is « demain ».
        #expect(lines(due: [project("Cabinet Martin", due: at(19))], at: at(17, 9, 4))[1] == "À livrer : Cabinet Martin jeudi.")
        #expect(lines(due: [project("Cabinet Martin", due: at(19))])[1] == "À livrer : Cabinet Martin demain.")
        #expect(lines(due: [project("Cabinet Martin", due: at(24))])[1] == "À livrer : Cabinet Martin mardi.")
        #expect(lines(due: [project("Cabinet Martin", due: at(16))])[1] == "À livrer : Cabinet Martin en retard de 2 jours.")
        #expect(lines(due: [project("Cabinet Martin", due: at(25))])[1] == "À livrer : Cabinet Martin le 25.")
        let many = [project("A", due: at(16)), project("B", due: at(18)), project("C", due: at(19)), project("D", due: at(20)), project("E", due: at(21))]
        #expect(lines(due: many)[1] == "À livrer : A en retard de 2 jours, B aujourd'hui, C demain et 2 autres.")
        #expect(lines(due: Array(many.prefix(4)))[1] == "À livrer : A en retard de 2 jours, B aujourd'hui, C demain et 1 autre.")
        // Whose turn it is.
        #expect(lines(yours: [project("Cabinet Martin"), project("Studio Nord")])[1] == "À toi de jouer : Cabinet Martin, Studio Nord.")
        #expect(lines(yours: [project("A"), project("B"), project("C")])[1] == "À toi de jouer : A, B, C.")
        #expect(lines(yours: (1...5).map { project("P\($0)") })[1] == "À toi de jouer : 5 projets.")
        // Since the last time.
        #expect(lines(clientMails: 4, since: at(17, 19, 40))[1] == "Depuis hier 19:40 : 4 mails de clients.")
        #expect(lines(clientMails: 1, since: at(17, 19, 40))[1] == "Depuis hier 19:40 : 1 mail de client.")
        #expect(lines(clientMails: 2, since: at(18, 8, 5))[1] == "Depuis 8:05 : 2 mails de clients.")
        #expect(lines(clientMails: 2, since: at(13, 19, 40))[1] == "Depuis vendredi 19:40 : 2 mails de clients.")
        #expect(lines(clientMails: 2, since: at(2, 9))[1] == "Depuis le 2 novembre : 2 mails de clients.")
        // No mail, or no last time: no sentence.
        #expect(lines(clientMails: 0, since: at(17, 19, 40)).count == 1)
        #expect(lines(clientMails: 3, since: nil).count == 1)
    }

    @Test func fourLinesAtMost() {
        // Tuesday 17/11 at 9:04, as in the design.
        let all = lines(week: (5, event("demain", day: 18, hour: 10)), due: [project("Cabinet Martin", due: at(19))],
                        yours: [project("Cabinet Martin"), project("Studio Nord")], clientMails: 4, since: at(16, 19, 40), at: at(17, 9, 4))
        #expect(all == [
            "Cette semaine : 5 rendez-vous, le prochain demain 10:00.",
            "À livrer : Cabinet Martin jeudi.",
            "À toi de jouer : Cabinet Martin, Studio Nord.",
            "Depuis hier 19:40 : 4 mails de clients.",
        ])
    }

    /// Step 3 (18/11): the projects that moved without Paul — by Colin or by an agent — join the line « Depuis… »;
    /// still four lines.
    @Test func theSinceLineSaysWhatMoved() {
        let since = at(16, 19, 40), when = at(17, 9, 4)
        #expect(lines(clientMails: 2, moved: 3, since: since, at: when).last == "Depuis hier 19:40 : 2 mails de clients, 3 projets ont bougé.")
        #expect(lines(moved: 1, since: since, at: when).last == "Depuis hier 19:40 : 1 projet a bougé.")
        #expect(lines(moved: 2, at: when).count == 1)
        let all = lines(week: (5, event("demain", day: 18, hour: 10)), due: [project("Cabinet Martin", due: at(19))],
                        yours: [project("Cabinet Martin")], clientMails: 4, moved: 2, since: since, at: when)
        #expect(all.count == 4)
    }

    /// Only what moved without Paul, not undone, counted by project.
    @Test func whatMovedIsCountedByProject() {
        let martin = UUID(), nord = UUID()
        func line(_ project: UUID, _ who: ChangeAuthor, undone: Bool = false) -> ProjectChangeLine {
            ProjectChangeLine(id: UUID().uuidString, projectID: project, projectName: "", who: who, at: now, reason: nil, rows: [],
                              undoneAt: undone ? now : nil)
        }
        #expect(Briefing.moved([line(martin, .colin), line(martin, .agent), line(nord, .agent), line(nord, .paul)]) == 2)
        #expect(Briefing.moved([line(martin, .colin, undone: true), line(nord, .paul)]) == 0)
    }

    /// The Accueil's pass (18/11): « Le point » in figures — the meetings of the week, what is due, whose turn it is —
    /// only those that are not nothing.
    @Test func figuresCountWhatMatters() {
        let figures = Briefing.figures(week: (5, event("demain", day: 19, hour: 10)), due: [project("Cabinet Martin", due: at(19))],
                                       yours: [project("Cabinet Martin"), project("Studio Nord")])
        #expect(figures.tiles == [Briefing.Figure(tile: .meetings, count: 5), Briefing.Figure(tile: .due, count: 1), Briefing.Figure(tile: .yours, count: 2)])
        #expect(figures.due == ["Cabinet Martin"] && figures.yours == ["Cabinet Martin", "Studio Nord"])
        #expect(Briefing.figures(week: (0, nil), due: [], yours: []).tiles.isEmpty)
        #expect(Briefing.label(.meetings, count: 5) == "rendez-vous" && Briefing.label(.due, count: 1) == "à livrer" && Briefing.label(.yours, count: 2) == "à toi")
    }

    /// A figure clicked puts its question in Colin's bar.
    @Test func eachTileAsksItsQuestion() {
        #expect(Briefing.question(for: .meetings) == "Quels sont mes rendez-vous cette semaine ?")
        #expect(Briefing.question(for: .due) == "Qu'est-ce qui est à livrer ?")
        #expect(Briefing.question(for: .yours) == "Où en sont les projets où c'est à moi de jouer ?")
    }

    @Test func aDayIsSaidAsPaulWouldSayIt() {
        #expect(Briefing.dayLabel(at(18, 16, 30), now: now, calendar: calendar) == "aujourd'hui 16:30")
        #expect(Briefing.dayLabel(at(19, 10), now: now, calendar: calendar) == "demain 10:00")
        #expect(Briefing.dayLabel(at(21, 9, 5), now: now, calendar: calendar) == "samedi 9:05")
        #expect(Briefing.dayLabel(at(24, 9), now: now, calendar: calendar) == "mardi 9:00")
        // A week away or more, the day of the month too; another month, its name.
        #expect(Briefing.dayLabel(at(25, 9), now: now, calendar: calendar) == "mercredi 25 à 9:00")
        #expect(Briefing.dayLabel(calendar.date(from: DateComponents(year: 2026, month: 12, day: 2, hour: 14))!, now: now, calendar: calendar) == "mercredi 2 décembre à 14:00")
        #expect(Briefing.dayLabel(at(17, 19, 40), now: now, calendar: calendar) == "hier 19:40")
    }
}
