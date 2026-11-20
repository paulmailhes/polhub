import Domain
import Foundation
import Persistence
import Testing
@testable import MeetingsUI

/// Contacts (15/11): the search, the last time Paul and someone crossed, the list cut by date, the texts of a page.
@Suite struct ContactsModelTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    func contact(_ name: String, _ email: String? = nil, company: String? = nil) -> ContactRow {
        ContactRow(name: name, email: email, company: company, createdAt: now)
    }

    func days(_ count: Double) -> Date { now.addingTimeInterval(count * 86_400) }

    /// Every word typed is found somewhere: the name, the address, the company, a project; no case nor accents.
    @Test func theSearchFindsTheNameTheAddressTheCompanyAndTheProjects() {
        let camille = contact("Camille Martin", "camille.martin@exemple-studio.fr", company: "Exemple Studio")
        let projects = ["Site vitrine", "Identité"]
        #expect(ContactsModel.matches(camille, projects: projects, query: ""))
        #expect(ContactsModel.matches(camille, projects: projects, query: "  "))
        #expect(ContactsModel.matches(camille, projects: projects, query: "CAMI"))
        #expect(ContactsModel.matches(camille, projects: projects, query: "exemple-studio"))
        #expect(ContactsModel.matches(camille, projects: projects, query: "studio"))
        #expect(ContactsModel.matches(camille, projects: projects, query: "identite"))
        #expect(ContactsModel.matches(camille, projects: projects, query: "martin vitrine"))
        #expect(!ContactsModel.matches(camille, projects: projects, query: "martin catalogue"))
        #expect(!ContactsModel.matches(contact("Jules"), projects: [], query: "studio"))
    }

    /// The most recent of a mail, a meeting and an event; on the same instant a mail first; nothing without any.
    @Test func theLastTimePaulAndSomeoneCrossed() {
        #expect(ContactsModel.last(mail: nil, meeting: nil, event: nil) == nil)
        #expect(ContactsModel.last(mail: days(-3), meeting: days(-1), event: days(-2)) == LastContact(date: days(-1), kind: .meeting))
        #expect(ContactsModel.last(mail: days(-1), meeting: days(-1), event: days(-1)) == LastContact(date: days(-1), kind: .mail))
        #expect(ContactsModel.last(mail: nil, meeting: nil, event: days(-5)) == LastContact(date: days(-5), kind: .event))
    }

    /// An event counts once begun, for its guests: neither Paul, nor a room, nor someone who declined.
    @Test func theLastEventOfEachGuest() {
        func event(_ id: String, start: Date, _ guests: [Attendee]) -> CalendarEventRow {
            CalendarEventRow(account: "moi@exemple.fr", eventID: id, title: "Point", startAt: start, endAt: start.addingTimeInterval(3_600), attendees: guests, updatedAt: now)
        }
        let events = [
            event("a", start: days(-10), [Attendee(email: "camille@studio.exemple"), Attendee(email: "jules@exemple.fr")]),
            event("b", start: days(-2), [Attendee(email: "camille@studio.exemple"), Attendee(email: "jules@exemple.fr", response: "declined"),
                                         Attendee(email: "moi@exemple.fr", isSelf: true), Attendee(email: "salle@ressource.exemple", isResource: true)]),
            event("c", start: days(3), [Attendee(email: "camille@studio.exemple"), Attendee(email: "lou@exemple.fr")]),
        ]
        #expect(ContactsModel.lastEvents(events, now: now) == ["camille@studio.exemple": days(-2), "jules@exemple.fr": days(-10)])
        // A page: those to come the soonest first, then the others the latest first.
        let split = ContactsModel.events(events, of: "Camille@Studio.exemple", now: now)
        #expect(split.coming.map(\.eventID) == ["c"] && split.past.map(\.eventID) == ["b", "a"])
        #expect(ContactsModel.events(events, of: nil, now: now).coming.isEmpty)
    }

    /// The links Paul removed leave the projects out; the others come by name.
    @Test func eachContactsProjects() {
        let site = ProjectRow(name: "Site vitrine", status: .priorite1, createdAt: now)
        let atelier = ProjectRow(name: "Atelier Nord", status: .priorite1, createdAt: now)
        let camille = UUID(), jules = UUID()
        let found = ContactsModel.projects(links: [camille: [site.id: false, atelier.id: false], jules: [site.id: true], UUID(): [UUID(): false]],
                                           projects: [site, atelier])
        #expect(found == [camille: [atelier, site]])
        #expect(ContactsModel.projects(of: camille, links: [camille: [site.id: false]], projects: [site, atelier]) == [site])
        #expect(ContactsModel.projects(of: jules, links: [:], projects: [site]).isEmpty)
    }

    /// The people crossed lately first, cut by date as Apple's Notes; then those never crossed, by last name.
    @Test func theListIsCutByTheLastExchange() {
        let hugo = contact("Hugo Moreau"), camille = contact("Camille Martin"), nina = contact("Nina Roche"), sarah = contact("Sarah Lambert")
        let ines = contact("Inès Garnier"), marc = contact("Marc Petit"), jules = contact("Jules Durand")
        let last: [UUID: LastContact] = [
            hugo.id: LastContact(date: days(-0.1), kind: .meeting), camille.id: LastContact(date: days(-0.05), kind: .mail),
            jules.id: LastContact(date: days(-6), kind: .event), nina.id: LastContact(date: days(-10), kind: .mail),
            sarah.id: LastContact(date: days(-95), kind: .mail),
        ]
        let sections = ContactsModel.sections([marc, sarah, ines, nina, jules, hugo, camille], last: last, now: now, calendar: calendar)
        #expect(sections.map(\.title) == ["7 jours précédents", "30 jours précédents", "Plus tôt", "Sans échange"])
        #expect(sections.map { $0.contacts.map(\.name) } == [["Camille Martin", "Hugo Moreau", "Jules Durand"], ["Nina Roche"], ["Sarah Lambert"],
                                                            ["Inès Garnier", "Marc Petit"]])
        // An empty part is not shown.
        #expect(ContactsModel.sections([marc], last: [:], now: now, calendar: calendar).map(\.title) == ["Sans échange"])
        #expect(ContactsModel.sections([], last: [:], now: now, calendar: calendar).isEmpty)
    }

    /// The row says when, the page how long ago.
    @Test func theTextsOfTheListAndOfThePage() {
        #expect(ContactsModel.when(days(0), now: now, calendar: calendar) == "aujourd'hui")
        #expect(ContactsModel.when(days(-1), now: now, calendar: calendar) == "hier")
        #expect(ContactsModel.when(days(-400), now: now, calendar: calendar) == "9 oct. 2025")
        #expect(ContactsModel.ago(days(0), now: now, calendar: calendar) == "aujourd'hui")
        #expect(ContactsModel.ago(days(-1), now: now, calendar: calendar) == "hier")
        #expect(ContactsModel.ago(days(-3), now: now, calendar: calendar) == "il y a 3 jours")
        #expect(ContactsModel.ago(days(-8), now: now, calendar: calendar) == "il y a 1 semaine")
        #expect(ContactsModel.ago(days(-20), now: now, calendar: calendar) == "il y a 2 semaines")
        #expect(ContactsModel.ago(days(-95), now: now, calendar: calendar) == "il y a 3 mois")
        #expect(ContactsModel.ago(days(-800), now: now, calendar: calendar) == "il y a 2 ans")
        #expect(ContactsModel.lastText(LastContact(date: days(-3), kind: .mail), now: now, calendar: calendar) == "Dernier mail il y a 3 jours")
        #expect(ContactsModel.lastText(LastContact(date: days(-1), kind: .meeting), now: now, calendar: calendar) == "Dernière réunion hier")
        let tomorrow = CalendarEventRow(account: "moi@exemple.fr", eventID: "e", title: "Point", startAt: days(1), endAt: days(1.05), updatedAt: now)
        #expect(ContactsModel.nextText(tomorrow, now: now, calendar: calendar) == "Rendez-vous demain 10:42")
        let running = CalendarEventRow(account: "moi@exemple.fr", eventID: "e", title: "Point", startAt: days(-0.01), endAt: days(0.02), updatedAt: now)
        #expect(ContactsModel.nextText(running, now: now, calendar: calendar) == "Rendez-vous en cours")
        #expect(ContactsModel.eventWhen(tomorrow, now: now, calendar: calendar).hasPrefix("Demain, "))
        let meeting = MeetingRow(createdAt: now, status: .ended, source: .dia, candidateKey: "t/a", title: "Point", startedAt: days(-2),
                                 endedAt: days(-2).addingTimeInterval(5_400))
        #expect(ContactsModel.meetingWhen(meeting, now: now, calendar: calendar).hasSuffix(" · 1 h 30"))
        #expect(ContactsModel.initials(contact("camille@exemple.fr", "camille@exemple.fr")) == "C")
        #expect(ContactsModel.detail(contact("Jules", "jules@exemple.fr", company: " ")) == "jules@exemple.fr")
    }
}
