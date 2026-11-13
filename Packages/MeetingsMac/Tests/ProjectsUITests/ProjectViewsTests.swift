import Domain
import Foundation
import Persistence
import Testing
@testable import ProjectsUI

@Suite struct ProjectViewsTests {
    var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    func date(_ day: Int, _ month: Int = 11, hour: Int = 12, minute: Int = 0) -> Date {
        paris.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    var today: Date { date(13, hour: 23, minute: 30) }

    func project(_ name: String, _ status: ProjectStatus, due: Date? = nil, todo: String? = nil, activity: Date? = nil,
                 modified: Date? = nil, order: Double = 0) -> ProjectRow {
        ProjectRow(name: name, status: status, dueDate: due, todo: todo, lastActivity: activity, noteModifiedAt: modified,
                   kanbanOrder: order, createdAt: date(1, 9))
    }

    @Test func columnsFollowObsidiansOrderAndColors() {
        let columns = ProjectViews.columns([project("A", .idee), project("B", .priorite2), project("C", ProjectStatus.none),
                                            project("D", .termine)], includeDone: false)
        #expect(columns.map(\.title) == ["idée", "priorité 3", "priorité 2", "priorité 1", "en attente", "Sans statut"])
        #expect(columns.map(\.color) == [.pink, .red, .orange, .yellow, .cyan, .gray])
        #expect(columns[0].projects.map(\.name) == ["A"] && columns[1].projects.isEmpty)
    }

    @Test func doneOnlyInTheAllView() {
        let all = ProjectViews.columns([project("D", .termine)], includeDone: true)
        #expect(all.map(\.title) == ["idée", "priorité 3", "priorité 2", "priorité 1", "en attente", "terminé"])
        #expect(all.last?.color == .green && all.last?.projects.map(\.name) == ["D"])
    }

    @Test func cardsKeepTheirOrderInAColumn() {
        let columns = ProjectViews.columns([project("Deux", .idee, order: 2), project("Un", .idee, order: 1)], includeDone: false)
        #expect(columns[0].projects.map(\.name) == ["Un", "Deux"])
    }

    @Test func dueLabelsSayLateTodayOrJMinus() {
        #expect(ProjectViews.dueLabel(date(16, hour: 0), today: today, calendar: paris) == "J-3")
        #expect(ProjectViews.dueLabel(date(13, hour: 0), today: today, calendar: paris) == "Aujourd'hui")
        #expect(ProjectViews.dueLabel(date(12, hour: 0), today: today, calendar: paris) == "En retard 1 j")
        #expect(ProjectViews.dueLabel(nil, today: today, calendar: paris) == nil)
    }

    @Test func toHandInPutsLateFirstThenUndatedByPriority() {
        let projects = [
            project("C", .priorite3, todo: "c"), project("B", .priorite2, due: date(20), todo: "b"),
            project("A", .priorite1, due: date(10), todo: "a"), project("D", .priorite1, todo: "d"),
            project("E", .priorite2, due: date(14)), project("F", .idee, todo: "f"),
        ]
        #expect(ProjectViews.toHandIn(projects, today: today, calendar: paris).map(\.name) == ["A", "B", "D", "C"])
    }

    @Test func toWatchUsesTheMostRecentSignAndFourteenDays() {
        let projects = [
            project("X", .priorite1, activity: date(20, 10)), project("Y", .priorite2, activity: date(10)),
            project("Z", .priorite3, modified: date(1, 10)), project("W", .idee, activity: date(1, 9)),
        ]
        let watched = ProjectViews.toWatch(projects, lastAppMeeting: [:], today: today, calendar: paris)
        #expect(watched.map(\.0.name) == ["Z", "X"])
        #expect(watched.first?.sign == date(1, 10))
    }

    @Test func anAppMeetingCountsAsASign() {
        let x = project("X", .priorite1, activity: date(20, 10))
        #expect(ProjectViews.toWatch([x], lastAppMeeting: [x.id: date(12)], today: today, calendar: paris).isEmpty)
    }

    @Test func theTableShowsTheMostRecentActivityFirst() {
        let rows = ProjectViews.table([project("Vieux", .idee, activity: date(1)), project("Sans", .idee),
                                       project("Récent", .idee, activity: date(12))])
        #expect(rows.map(\.name) == ["Récent", "Vieux", "Sans"])
    }

    // Revue finale, Important 2 : la palette du greffon du coffre, noms français d'abord, et les codes hexa.
    @Test func cardColorsAreThePluginsPalette() {
        #expect(ProjectViews.cardHex("bleu") == "#2F6FED" && ProjectViews.cardHex("Violet") == "#8E44AD")
        #expect(ProjectViews.cardHex("blue") == "#2F6FED" && ProjectViews.cardHex("marron") == "#8B5E3C")
        #expect(ProjectViews.cardHex("#12ab9f") == "#12AB9F" && ProjectViews.cardHex("12ab9f") == "#12AB9F")
        #expect(ProjectViews.cardHex("chartreuse") == nil && ProjectViews.cardHex(nil) == nil)
        #expect(ProjectViews.colorChoices.first == "rouge" && ProjectViews.colorChoices.count == 11)
    }
}
