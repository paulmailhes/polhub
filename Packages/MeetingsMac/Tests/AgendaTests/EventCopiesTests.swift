import Domain
import Foundation
import Persistence
import Testing
@testable import Agenda

/// An event in two of Paul's calendars shows once, under the account to join it with (Paul, 14/11).
@Suite struct EventCopiesTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)
    var accounts: [GoogleAccountRow] {
        [GoogleAccountRow(email: "moi@gmail.com", addedAt: now), GoogleAccountRow(email: "paul@exemple.fr", addedAt: now.addingTimeInterval(60)),
         GoogleAccountRow(email: "paul@atelier-nord.fr", addedAt: now.addingTimeInterval(120))]
    }

    func copy(_ account: String, organizer: String?, id: String = "e1") -> CalendarEventRow {
        CalendarEventRow(account: account, eventID: id, title: "Point", startAt: now, endAt: now.addingTimeInterval(1_800),
                         meetCode: "abc-defg-hij", organizer: organizer, updatedAt: now)
    }

    @Test func theOrganizingAccountWins() {
        let copies = [copy("paul@exemple.fr", organizer: "moi@gmail.com"), copy("moi@gmail.com", organizer: "moi@gmail.com")]
        #expect(EventCopies.joinAccount(for: copies, accounts: accounts) == "moi@gmail.com")
    }

    @Test func thenTheAccountOfTheOrganizersDomain() {
        let copies = [copy("paul@exemple.fr", organizer: "camille@atelier-nord.fr"), copy("paul@atelier-nord.fr", organizer: "camille@atelier-nord.fr")]
        #expect(EventCopies.joinAccount(for: copies, accounts: accounts) == "paul@atelier-nord.fr")
    }

    @Test func thenAWorkAccountRatherThanThePersonalOne() {
        let copies = [copy("moi@gmail.com", organizer: "client@ailleurs.fr"), copy("paul@atelier-nord.fr", organizer: "client@ailleurs.fr"),
                      copy("paul@exemple.fr", organizer: "client@ailleurs.fr")]
        #expect(EventCopies.joinAccount(for: copies, accounts: accounts) == "paul@exemple.fr")
    }

    @Test func aFriendsInvitationGoesToThePersonalAccount() {
        let copies = [copy("paul@exemple.fr", organizer: "ami@gmail.com"), copy("moi@gmail.com", organizer: "ami@gmail.com")]
        #expect(EventCopies.joinAccount(for: copies, accounts: accounts) == "moi@gmail.com")
    }

    @Test func mergeKeepsOneRowAndPaulsProjectFromAnyCopy() {
        let project = UUID(), meeting = UUID()
        var personal = copy("moi@gmail.com", organizer: "client@ailleurs.fr")
        personal.projectID = project
        personal.projectOrigin = .paul
        personal.meetingID = meeting
        let work = copy("paul@exemple.fr", organizer: "client@ailleurs.fr")
        let other = copy("paul@exemple.fr", organizer: nil, id: "e2")
        let merged = EventCopies.merge([personal, work, other], accounts: accounts)
        #expect(merged.count == 2)
        let shown = try? #require(merged.first { $0.eventID == "e1" })
        #expect(shown?.account == "paul@exemple.fr")
        #expect(shown?.projectID == project && shown?.projectOrigin == .paul && shown?.meetingID == meeting)
    }

    /// Review of 14/11: accepted on one address and declined on the other, the meeting counts as accepted.
    @Test func paulsAnswerOnAnyCopyCounts() {
        var personal = copy("moi@gmail.com", organizer: "ami@gmail.com")
        personal.attendees = [Attendee(email: "moi@gmail.com", response: "declined", isSelf: true)]
        var work = copy("paul@exemple.fr", organizer: "ami@gmail.com")
        work.attendees = [Attendee(email: "paul@exemple.fr", response: "accepted", isSelf: true)]
        let shown = EventCopies.merge([personal, work], accounts: accounts).first
        #expect(shown?.account == "moi@gmail.com")
        #expect(shown?.attendees.first(where: \.isSelf)?.response == "accepted")
    }

    @Test func theJoinLinkNamesTheAccount() {
        #expect(MeetJoin.url(code: "abc-defg-hij", account: "paul+agenda@exemple.fr").absoluteString
                == "https://meet.google.com/abc-defg-hij?authuser=paul%2Bagenda@exemple.fr")
    }

    /// Review of 14/11, Important 7: the recording is linked to one copy; its project goes to every copy.
    @Test func theRecordingsProjectFilesEveryCopy() throws {
        let database = try AppDatabase.inMemory()
        let calendar = CalendarStore(database), projects = ProjectStore(database), contacts = ContactStore(database)
        let alpha = try projects.addProject(name: "Alpha", status: .priorite1, at: now)
        let beta = try projects.addProject(name: "Beta", status: .priorite1, at: now)
        // The guest belongs to Beta, but Paul filed the recording in Alpha.
        let guest = try contacts.upsert(email: "camille@ailleurs.fr", name: "Camille", company: nil, at: now)
        try contacts.link(contactID: guest.id, projectID: beta.id, origin: .coffre, at: now)
        var recorded = MeetingRow(createdAt: now, status: .ended, source: .dia, candidateKey: "t/a", meetCode: "abc-defg-hij", title: "Point",
                                  startedAt: now.addingTimeInterval(60), endedAt: now.addingTimeInterval(1_700))
        recorded.projectID = alpha.id
        try MeetingStore(database).save(recorded)
        for account in accounts.prefix(2) {
            try calendar.addAccount(email: account.email, at: account.addedAt)
            var event = copy(account.email, organizer: "client@ailleurs.fr")
            event.attendees = [Attendee(email: "camille@ailleurs.fr"), Attendee(email: account.email, isSelf: true)]
            try calendar.applyGoogle(account: account.email, changed: [event], cancelled: [], at: now)
        }
        try LinkRunner(database: database).run(now: now)
        let rows = try calendar.allEvents()
        #expect(rows.filter { $0.meetingID == recorded.id }.count == 1)
        #expect(rows.allSatisfy { $0.projectID == alpha.id })
        #expect(EventCopies.merge(rows, accounts: Array(accounts.prefix(2))).first?.projectID == alpha.id)
    }

    /// Review of 14/11: a copy whose sibling has its recording never takes the next meeting's.
    @Test func aCopyNeverTakesTheNextMeetingsRecording() throws {
        let database = try AppDatabase.inMemory()
        let calendar = CalendarStore(database), meetings = MeetingStore(database)
        let first = MeetingRow(createdAt: now, status: .ended, source: .dia, candidateKey: "t/1", meetCode: "abc-defg-hij", title: "Point",
                               startedAt: now, endedAt: now.addingTimeInterval(1_200))
        let next = MeetingRow(createdAt: now, status: .ended, source: .dia, candidateKey: "t/2", meetCode: "xyz-wxyz-xyz", title: "Suivant",
                              startedAt: now.addingTimeInterval(1_800), endedAt: now.addingTimeInterval(5_400))
        try meetings.save(first)
        try meetings.save(next)
        for account in accounts.prefix(2) {
            try calendar.addAccount(email: account.email, at: account.addedAt)
            var event = copy(account.email, organizer: "client@ailleurs.fr")
            event.endAt = now.addingTimeInterval(3_600)
            try calendar.applyGoogle(account: account.email, changed: [event], cancelled: [], at: now)
        }
        try calendar.applyGoogle(account: "paul@exemple.fr", changed: [
            CalendarEventRow(account: "paul@exemple.fr", eventID: "c", title: "Suivant", startAt: now.addingTimeInterval(1_800),
                             endAt: now.addingTimeInterval(5_400), meetCode: "xyz-wxyz-xyz", updatedAt: now),
        ], cancelled: [], at: now)
        try LinkRunner(database: database).run(now: now)
        let rows = try calendar.allEvents()
        #expect(rows.filter { $0.eventID == "e1" }.compactMap(\.meetingID) == [first.id])
        #expect(rows.first { $0.eventID == "c" }?.meetingID == next.id)
    }

    @Test func paulsChoiceOnOneCopyFilesEveryCopyAndTheLoopKeepsIt() throws {
        let database = try AppDatabase.inMemory()
        let calendar = CalendarStore(database)
        let alpha = try ProjectStore(database).addProject(name: "Alpha", status: .priorite1, at: now)
        for account in accounts.prefix(2) {
            try calendar.addAccount(email: account.email, at: now)
            try calendar.applyGoogle(account: account.email, changed: [copy(account.email, organizer: "client@ailleurs.fr")], cancelled: [], at: now)
        }
        try calendar.setProject(googleEventID: "e1", projectID: alpha.id, origin: .paul)
        try LinkRunner(database: database).run(now: now)
        let rows = try calendar.allEvents()
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.projectID == alpha.id && $0.projectOrigin == .paul })
    }
}
