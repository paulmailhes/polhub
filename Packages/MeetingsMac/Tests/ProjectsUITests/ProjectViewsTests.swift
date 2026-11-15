import Domain
import Foundation
import Persistence
import PolhubDesign
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

    /// 15/11 (Paul): four columns, Terminé always at the right, each status its color of the palette.
    @Test func fourColumnsTerminéAtTheRight() {
        let columns = ProjectViews.columns([project("A", .enPause), project("B", .priorite2), project("D", .termine)])
        #expect(columns.map(\.title) == ["Priorité 1", "Priorité 2", "En pause", "Terminé"])
        #expect(columns.map(\.status) == ProjectStatus.allCases)
        #expect(columns[0].projects.isEmpty && columns[2].projects.map(\.name) == ["A"] && columns[3].projects.map(\.name) == ["D"])
        #expect(ProjectStatus.allCases.map(ProjectViews.statusHex) == [Palette.yellow, Palette.orange, Palette.teal, Palette.green])
    }

    @Test func terminéShowsCompactCards() {
        #expect(ProjectViews.cardSize(.termine, chosen: .medium) == .small)
        #expect(ProjectViews.cardSize(.priorite1, chosen: .medium) == .medium && ProjectViews.cardSize(.enPause, chosen: .small) == .small)
    }

    @Test func cardsKeepTheirOrderInAColumn() {
        let columns = ProjectViews.columns([project("Deux", .enPause, order: 2), project("Un", .enPause, order: 1)])
        #expect(columns[2].projects.map(\.name) == ["Un", "Deux"])
    }

    /// A project's color everywhere: Paul's, else always the same one of the palette for the same project.
    @Test func aProjectKeepsItsColorEverywhere() {
        var chosen = project("Bleu", .priorite1)
        chosen.color = "bleu"
        #expect(ProjectViews.tintHex(chosen) == "#2F6FED")
        let plain = project("Sans couleur", .priorite1)
        let again = ProjectRow(id: plain.id, name: "Renommé", status: .termine, createdAt: date(2))
        #expect(ProjectViews.tintHex(plain) == ProjectViews.tintHex(again))
        #expect(ProjectViews.tints.contains(ProjectViews.tintHex(plain)) && !ProjectViews.tints.contains(Palette.red))
        let many = Set((0..<40).map { _ in ProjectViews.tintHex(project("P", .priorite1)) })
        #expect(many.count > 3)
    }

    @Test func theLastMeetingInWords() {
        let now = date(13, hour: 18)
        #expect(ProjectViews.meetingLabel(date(13, hour: 9), now: now, calendar: paris) == "Réunion aujourd'hui")
        #expect(ProjectViews.meetingLabel(date(12), now: now, calendar: paris) == "Réunion hier")
        #expect(ProjectViews.meetingLabel(date(9), now: now, calendar: paris) == "Réunion il y a 4 jours")
        #expect(ProjectViews.meetingLabel(date(4), now: now, calendar: paris) == "Réunion il y a 1 semaine")
        #expect(ProjectViews.meetingLabel(date(23, 10), now: now, calendar: paris) == "Réunion il y a 3 semaines")
        #expect(ProjectViews.meetingLabel(date(1, 8), now: now, calendar: paris) == "Réunion il y a 3 mois")
    }

    @Test func initialsForTheLogoOfAProjectWithoutOne() {
        #expect(ProjectViews.initials("Refonte site") == "RS" && ProjectViews.initials("agence") == "A")
        #expect(ProjectViews.initials("L'atelier du nord") == "LA" && ProjectViews.initials("") == "")
    }

    /// The journal shows two plain lines of an entry (a meeting's row reads SummaryText.overview, as the Réunions list).
    @Test func excerptsArePlainText() {
        #expect(ProjectViews.excerpt("## Titre\n- **Deux** pages\n- Retour [attendu](https://exemple.fr) lundi.\n\n```\ncode\n```")
                == "Deux pages · Retour attendu lundi.")
        #expect(ProjectViews.excerpt("Une phrase. Puis [[Atelier Nord|l'atelier]].\n\nAutre paragraphe") == "Une phrase. Puis l'atelier. Autre paragraphe")
        #expect(ProjectViews.excerpt(String(repeating: "mot ", count: 200), limit: 20) == "mot mot mot mot mot…")
    }

    @Test func dueLabelsSayLateTodayOrJMinus() {
        #expect(ProjectViews.dueLabel(date(16, hour: 0), today: today, calendar: paris) == "J-3")
        #expect(ProjectViews.dueLabel(date(13, hour: 0), today: today, calendar: paris) == "Aujourd'hui")
        #expect(ProjectViews.dueLabel(date(12, hour: 0), today: today, calendar: paris) == "En retard 1 j")
        #expect(ProjectViews.dueLabel(nil, today: today, calendar: paris) == nil)
    }

    @Test func theTableShowsTheMostRecentActivityFirst() {
        let rows = ProjectViews.table([project("Vieux", .enPause, activity: date(1)), project("Sans", .enPause),
                                       project("Récent", .enPause, activity: date(12))])
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
