import Domain
import Foundation
import Persistence
import Testing
@testable import Agenda

/// The loop of 13/11: guests become contacts, events find their project and their recording, contacts
/// follow the projects of their events.
@Suite struct GuestTests {
    @Test func aGuestsNameAndCompanyComeFromGoogleOrTheAddress() {
        #expect(Linker.name(for: Attendee(email: "camille.martin@exemple-studio.fr", name: "Camille Martin")) == "Camille Martin")
        #expect(Linker.name(for: Attendee(email: "camille.martin@exemple-studio.fr")) == "Camille Martin")
        #expect(Linker.name(for: Attendee(email: "jules_dupont-roy@exemple.fr")) == "Jules Dupont-Roy")
        #expect(Linker.company(forEmail: "camille@exemple-studio.fr") == "Exemple Studio")
        #expect(Linker.company(forEmail: "camille@gmail.com") == nil)
        #expect(Linker.company(forEmail: "camille@mail.exemple.co.uk") == "Exemple")
    }
}

@Suite struct ProjectRuleTests {
    let alpha = UUID(), beta = UUID()
    let start = Date(timeIntervalSince1970: 1_794_562_920)

    func event(title: String = "Point", series: String? = nil, guests: [String] = []) -> CalendarEventRow {
        CalendarEventRow(account: "moi@exemple.fr", eventID: UUID().uuidString, recurringEventID: series, title: title, startAt: start,
                         endAt: start.addingTimeInterval(1_800), attendees: guests.map { Attendee(email: $0) } + [Attendee(email: "moi@exemple.fr", isSelf: true)],
                         updatedAt: start)
    }

    var projects: [(id: UUID, name: String)] { [(alpha, "Alpha"), (beta, "Beta Studio")] }

    @Test func paulsChoiceComesFirst() {
        var paul = event(title: "Point Alpha")
        paul.projectID = beta
        paul.projectOrigin = .paul
        #expect(Linker.project(for: paul, meetingProject: alpha, seriesProjects: [:], contactProjects: [:], projects: projects)?.origin == .paul)
        #expect(Linker.project(for: paul, meetingProject: alpha, seriesProjects: [:], contactProjects: [:], projects: projects)?.id == beta)
    }

    @Test func thenTheRecordedMeetingThenTheSeriesThenTheGuestsThenTheTitle() {
        let plain = event(title: "Point Alpha", series: "s1", guests: ["camille@exemple.fr"])
        #expect(Linker.project(for: plain, meetingProject: beta, seriesProjects: ["s1": alpha], contactProjects: [:], projects: projects)?.origin == .reunion)
        #expect(Linker.project(for: plain, meetingProject: nil, seriesProjects: ["s1": beta], contactProjects: [:], projects: projects)! == (beta, .serie))
        #expect(Linker.project(for: event(guests: ["camille@exemple.fr"]), meetingProject: nil, seriesProjects: [:],
                               contactProjects: ["camille@exemple.fr": [beta]], projects: projects)! == (beta, .invites))
        #expect(Linker.project(for: event(title: "Point Alpha"), meetingProject: nil, seriesProjects: [:], contactProjects: [:], projects: projects)! == (alpha, .titre))
    }

    @Test func guestsOfSeveralProjectsOrAnUnknownTitleGiveNothing() {
        let mixed = event(guests: ["camille@exemple.fr", "jules@exemple.fr"])
        #expect(Linker.project(for: mixed, meetingProject: nil, seriesProjects: [:],
                               contactProjects: ["camille@exemple.fr": [alpha], "jules@exemple.fr": [beta]], projects: projects) == nil)
        #expect(Linker.project(for: event(title: "Déjeuner"), meetingProject: nil, seriesProjects: [:], contactProjects: [:], projects: projects) == nil)
        // A word inside another is not a project's name.
        #expect(Linker.project(for: event(title: "Alphabet"), meetingProject: nil, seriesProjects: [:], contactProjects: [:], projects: projects) == nil)
    }
}

@Suite struct MeetingMatchTests {
    let start = Date(timeIntervalSince1970: 1_794_562_920)

    func meeting(at offset: TimeInterval, minutes: Double = 30, code: String? = nil) -> MeetingRow {
        MeetingRow(createdAt: start, status: .ended, source: .dia, candidateKey: "t/\(offset)", meetCode: code, title: "Google Meet",
                   startedAt: start.addingTimeInterval(offset), endedAt: start.addingTimeInterval(offset + minutes * 60))
    }

    func event(code: String? = nil) -> CalendarEventRow {
        CalendarEventRow(account: "moi@exemple.fr", eventID: "e", title: "Point", startAt: start, endAt: start.addingTimeInterval(3_600),
                         meetCode: code, updatedAt: start)
    }

    @Test func theSameMeetCodeAtTheSameTimeIsTheEventsMeeting() {
        let lastWeek = meeting(at: -7 * 86_400, code: "abc-defg-hij")
        let today = meeting(at: 120, code: "abc-defg-hij")
        #expect(Linker.meeting(for: event(code: "abc-defg-hij"), among: [lastWeek, today])?.id == today.id)
    }

    @Test func withoutCodeTheMeetingMustCoverHalfOfTheShorterOne() {
        let overlapping = meeting(at: 600, minutes: 40)
        let barely = meeting(at: 3_300, minutes: 30)
        #expect(Linker.meeting(for: event(), among: [barely, overlapping])?.id == overlapping.id)
        #expect(Linker.meeting(for: event(), among: [barely]) == nil)
    }
}

@Suite struct LoopTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)

    @Test func theLoopLinksGuestsEventsMeetingsAndProjects() throws {
        let database = try AppDatabase.inMemory()
        let projects = ProjectStore(database), contacts = ContactStore(database), calendar = CalendarStore(database), meetings = MeetingStore(database)
        let alpha = try projects.addProject(name: "Alpha", status: .priorite1, at: now)
        try calendar.addAccount(email: "moi@exemple.fr", at: now)
        // Camille is in Alpha (vault); Jules is new.
        let camille = try contacts.upsert(email: "camille@exemple.fr", name: "Camille", company: nil, at: now)
        try contacts.link(contactID: camille.id, projectID: alpha.id, origin: .coffre, at: now)
        let recorded = MeetingRow(createdAt: now, status: .ended, source: .dia, candidateKey: "t/a", meetCode: "abc-defg-hij", title: "Google Meet",
                                  startedAt: now.addingTimeInterval(60), endedAt: now.addingTimeInterval(1_800))
        try meetings.save(recorded)
        try calendar.applyGoogle(account: "moi@exemple.fr", changed: [
            CalendarEventRow(account: "moi@exemple.fr", eventID: "e1", title: "Atelier maquette", startAt: now, endAt: now.addingTimeInterval(1_800),
                             meetCode: "abc-defg-hij", attendees: [Attendee(email: "camille@exemple.fr"), Attendee(email: "Jules.Roy@atelier-exemple.fr", name: "Jules Roy"),
                                                                   Attendee(email: "moi@exemple.fr", isSelf: true), Attendee(email: "salle@resource.calendar.google.com", isResource: true)],
                             updatedAt: now),
        ], cancelled: [], at: now)

        try LinkRunner(database: database).run(now: now)

        let event = try #require(try calendar.event(id: CalendarEventRow.key(account: "moi@exemple.fr", eventID: "e1")))
        #expect(event.projectID == alpha.id && event.projectOrigin == .invites)
        #expect(event.meetingID == recorded.id)
        let jules = try #require(try contacts.contact(email: "jules.roy@atelier-exemple.fr"))
        #expect(jules.name == "Jules Roy" && jules.company == "Atelier Exemple")
        #expect(try contacts.contacts().count == 2)   // neither Paul nor the room
        #expect(Set(try contacts.contacts(projectID: alpha.id).map(\.name)) == ["Camille", "Jules Roy"])
        let meeting = try #require(try meetings.meeting(id: recorded.id))
        #expect(meeting.projectID == alpha.id && meeting.title == "Atelier maquette")
        #expect(Set(try contacts.participants(meetingID: recorded.id).map(\.name)) == ["Camille", "Jules Roy"])
    }

    @Test func anImportedMeetingFindsItsEventByGooglesID() throws {
        let database = try AppDatabase.inMemory()
        let calendar = CalendarStore(database), meetings = MeetingStore(database)
        let old = MeetingRow(createdAt: now, status: .ended, source: .imported, candidateKey: "coffre/a", title: "Ancien point", startedAt: now.addingTimeInterval(-86_400))
        try meetings.saveImported(old, importedFrom: "database/Meet/a.md", googleEventID: "evt-ancien", summary: nil)
        try calendar.applyGoogle(account: "moi@exemple.fr", changed: [
            CalendarEventRow(account: "moi@exemple.fr", eventID: "evt-ancien", title: "Ancien point", startAt: now.addingTimeInterval(-86_400 - 600),
                             endAt: now.addingTimeInterval(-86_400 + 3_000), updatedAt: now),
        ], cancelled: [], at: now)
        try LinkRunner(database: database).run(now: now)
        #expect(try calendar.event(id: CalendarEventRow.key(account: "moi@exemple.fr", eventID: "evt-ancien"))?.meetingID == old.id)
    }
}

/// `(UUID, EventProjectOrigin)` compared as a pair.
func == (lhs: (id: UUID, origin: EventProjectOrigin), rhs: (UUID, EventProjectOrigin)) -> Bool {
    lhs.id == rhs.0 && lhs.origin == rhs.1
}
