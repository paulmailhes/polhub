import Domain
import Foundation
import Testing
@testable import Persistence

/// Base v4: contacts, their projects, the calendar's events, the imported meetings (13/11).
@Suite struct ContactStoreTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)

    func stores() throws -> (ContactStore, ProjectStore, MeetingStore) {
        let database = try AppDatabase.inMemory()
        return (ContactStore(database), ProjectStore(database), MeetingStore(database))
    }

    @Test func aContactIsFoundByItsEmailWhateverTheCase() throws {
        let (contacts, _, _) = try stores()
        let first = try contacts.upsert(email: "Camille.Martin@Exemple.fr", name: "Camille Martin", company: "Exemple", at: now)
        let again = try contacts.upsert(email: "camille.martin@exemple.fr", name: "C. Martin", company: nil, at: now)
        #expect(first.id == again.id)
        #expect(again.name == "Camille Martin" && again.company == "Exemple" && again.email == "camille.martin@exemple.fr")
        #expect(try contacts.contacts().count == 1)
    }

    @Test func aLinkRemovedByPaulNeverComesBackOnItsOwn() throws {
        let (contacts, projects, _) = try stores()
        let project = try projects.addProject(name: "Atelier Nord", status: .idee, at: now)
        let camille = try contacts.upsert(email: "camille@exemple.fr", name: "Camille", company: nil, at: now)
        try contacts.link(contactID: camille.id, projectID: project.id, origin: .agenda, at: now)
        #expect(try contacts.contacts(projectID: project.id).map(\.name) == ["Camille"])
        try contacts.exclude(contactID: camille.id, projectID: project.id, at: now)
        #expect(try contacts.contacts(projectID: project.id).isEmpty)
        try contacts.link(contactID: camille.id, projectID: project.id, origin: .agenda, at: now)
        #expect(try contacts.contacts(projectID: project.id).isEmpty)
        try contacts.include(contactID: camille.id, projectID: project.id, at: now)
        #expect(try contacts.contacts(projectID: project.id).map(\.name) == ["Camille"])
        #expect(try contacts.projects(contactID: camille.id).map(\.name) == ["Atelier Nord"])
    }

    @Test func participantsOfAMeeting() throws {
        let (contacts, _, meetings) = try stores()
        let meeting = MeetingRow(createdAt: now, status: .ended, source: .dia, candidateKey: "t/a", title: "Point", startedAt: now)
        try meetings.save(meeting)
        let camille = try contacts.upsert(email: "camille@exemple.fr", name: "Camille", company: nil, at: now)
        try contacts.setParticipants(meetingID: meeting.id, contactIDs: [camille.id])
        #expect(try contacts.participants(meetingID: meeting.id).map(\.name) == ["Camille"])
        #expect(try contacts.meetings(contactID: camille.id).map(\.id) == [meeting.id])
    }
}

@Suite struct CalendarStoreTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)

    func event(_ id: String, title: String = "Point", start: Date, attendees: [Attendee] = []) -> CalendarEventRow {
        CalendarEventRow(account: "moi@exemple.fr", eventID: id, title: title, startAt: start, endAt: start.addingTimeInterval(1_800),
                         attendees: attendees, updatedAt: start)
    }

    @Test func aNewVersionFromGoogleKeepsTheLocalLinks() throws {
        let database = try AppDatabase.inMemory()
        let calendar = CalendarStore(database)
        let project = try ProjectStore(database).addProject(name: "Atelier Nord", status: .idee, at: now)
        try calendar.applyGoogle(account: "moi@exemple.fr", changed: [event("e1", start: now)], cancelled: [], at: now)
        let id = CalendarEventRow.key(account: "moi@exemple.fr", eventID: "e1")
        try calendar.setProject(eventID: id, projectID: project.id, origin: .paul)
        try calendar.applyGoogle(account: "moi@exemple.fr", changed: [event("e1", title: "Point déplacé", start: now.addingTimeInterval(3_600))],
                                 cancelled: [], at: now)
        let stored = try #require(try calendar.event(id: id))
        #expect(stored.title == "Point déplacé" && stored.projectID == project.id && stored.projectOrigin == .paul)
        try calendar.applyGoogle(account: "moi@exemple.fr", changed: [], cancelled: ["e1"], at: now)
        #expect(try calendar.event(id: id) == nil)
    }

    @Test func eventsBetweenTwoDatesComeInOrderWithTheirAttendees() throws {
        let calendar = CalendarStore(try AppDatabase.inMemory())
        let camille = Attendee(email: "camille@exemple.fr", name: "Camille", response: "accepted")
        try calendar.applyGoogle(account: "moi@exemple.fr", changed: [
            event("e2", start: now.addingTimeInterval(7_200), attendees: [camille]),
            event("e1", start: now),
            event("e3", start: now.addingTimeInterval(86_400 * 3)),
        ], cancelled: [], at: now)
        let day = try calendar.events(from: now.addingTimeInterval(-60), to: now.addingTimeInterval(86_400))
        #expect(day.map(\.eventID) == ["e1", "e2"])
        #expect(day[1].attendees == [camille])
    }

    @Test func accountsKeepTheirSyncToken() throws {
        let calendar = CalendarStore(try AppDatabase.inMemory())
        try calendar.addAccount(email: "moi@exemple.fr", at: now)
        try calendar.recordSync(email: "moi@exemple.fr", syncToken: "jeton-1", error: nil, at: now)
        let account = try #require(try calendar.accounts().first)
        #expect(account.email == "moi@exemple.fr" && account.syncToken == "jeton-1" && account.lastSyncAt == now)
    }
}

@Suite struct ImportedMeetingTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)

    @Test func theRecorderNeverWipesASummary() throws {
        let database = try AppDatabase.inMemory()
        let meetings = MeetingStore(database)
        var row = MeetingRow(createdAt: now, status: .recording, source: .dia, candidateKey: "t/a", title: "Point", startedAt: now)
        try meetings.save(row)
        try meetings.setSummary(meetingID: row.id, summary: "## Résumé\n- Un point.")
        row.status = .ended
        try meetings.save(row)
        #expect(try meetings.summary(meetingID: row.id) == "## Résumé\n- Un point.")
    }

    @Test func anImportedMeetingIsFoundByItsNote() throws {
        let database = try AppDatabase.inMemory()
        let meetings = MeetingStore(database)
        let row = MeetingRow(createdAt: now, status: .ended, source: .imported, candidateKey: "coffre/a", title: "Ancien point", startedAt: now)
        try meetings.saveImported(row, importedFrom: "database/Meet/a.md", googleEventID: "evt1", summary: "Résumé")
        #expect(try meetings.importedMeeting(from: "database/Meet/a.md")?.id == row.id)
        #expect(try meetings.meeting(googleEventID: "evt1")?.id == row.id)
        #expect(try meetings.importedMeeting(from: "database/Meet/b.md") == nil)
    }

    @Test func aProjectReimportKeepsTheProjectOfMeetingActions() throws {
        let database = try AppDatabase.inMemory()
        let projects = ProjectStore(database)
        let meetings = MeetingStore(database)
        let project = ProjectRow(name: "Atelier Nord", status: .idee, createdAt: now)
        try projects.replaceAll([project], actions: [], journal: [])
        let meeting = MeetingRow(createdAt: now, status: .ended, source: .imported, candidateKey: "coffre/a", title: "Point", startedAt: now)
        try meetings.save(meeting)
        try projects.setProject(meetingID: meeting.id, projectID: project.id)
        try projects.saveAction(ActionRow(projectID: project.id, meetingID: meeting.id, text: "Envoyer le devis", position: 0, createdAt: now))
        let again = ProjectRow(name: "Atelier Nord", status: .priorite1, createdAt: now)
        try projects.replaceAll([again], actions: [], journal: [])
        #expect(try projects.actions(projectID: again.id).map(\.text) == ["Envoyer le devis"])
    }
}

/// Fixes of the review of 13/11.
@Suite struct ReviewFixTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)

    /// Critical 1: a new import of the projects keeps the contacts' links (removed ones included) and
    /// Paul's filing of events.
    @Test func aProjectReimportKeepsContactLinksAndPaulsFilings() throws {
        let database = try AppDatabase.inMemory()
        let projects = ProjectStore(database), contacts = ContactStore(database), calendar = CalendarStore(database)
        let alpha = ProjectRow(name: "Alpha", status: .idee, createdAt: now)
        try projects.replaceAll([alpha], actions: [], journal: [])
        let camille = try contacts.upsert(email: "camille@exemple.fr", name: "Camille", company: nil, at: now)
        let jules = try contacts.upsert(email: "jules@exemple.fr", name: "Jules", company: nil, at: now)
        try contacts.link(contactID: camille.id, projectID: alpha.id, origin: .coffre, at: now)
        try contacts.exclude(contactID: jules.id, projectID: alpha.id, at: now)
        try calendar.applyGoogle(account: "moi@exemple.fr", changed: [CalendarEventRow(account: "moi@exemple.fr", eventID: "e1", title: "Point",
                                                                                       startAt: now, endAt: now.addingTimeInterval(600), updatedAt: now)],
                                 cancelled: [], at: now)
        let id = CalendarEventRow.key(account: "moi@exemple.fr", eventID: "e1")
        try calendar.setProject(eventID: id, projectID: alpha.id, origin: .paul)

        let again = ProjectRow(name: "Alpha", status: .priorite1, createdAt: now)
        try projects.replaceAll([again], actions: [], journal: [])

        #expect(try contacts.contacts(projectID: again.id).map(\.name) == ["Camille"])
        #expect(try contacts.links().first { $0.contactID == jules.id }?.excluded == true)
        let event = try #require(try calendar.event(id: id))
        #expect(event.projectID == again.id && event.projectOrigin == .paul)
    }

    /// Important 3: an automatic filing never overwrites Paul's, even computed before it.
    @Test func anAutomaticFilingNeverOverwritesPauls() throws {
        let database = try AppDatabase.inMemory()
        let calendar = CalendarStore(database)
        let alpha = try ProjectStore(database).addProject(name: "Alpha", status: .idee, at: now)
        let beta = try ProjectStore(database).addProject(name: "Beta", status: .idee, at: now)
        try calendar.applyGoogle(account: "moi@exemple.fr", changed: [CalendarEventRow(account: "moi@exemple.fr", eventID: "e1", title: "Point",
                                                                                       startAt: now, endAt: now.addingTimeInterval(600), updatedAt: now)],
                                 cancelled: [], at: now)
        let id = CalendarEventRow.key(account: "moi@exemple.fr", eventID: "e1")
        try calendar.setProject(eventID: id, projectID: alpha.id, origin: .paul)
        try calendar.setAutomaticProject(eventID: id, projectID: beta.id, origin: .invites)
        #expect(try calendar.event(id: id)?.projectID == alpha.id)
        // Paul's « no project » is a choice too.
        try calendar.setProject(eventID: id, projectID: nil, origin: .paul)
        try calendar.setAutomaticProject(eventID: id, projectID: beta.id, origin: .titre)
        let event = try #require(try calendar.event(id: id))
        #expect(event.projectID == nil && event.projectOrigin == .paul)
    }

    /// Important 6: an old meeting of the vault is never sent to transcription.
    @Test func importedMeetingsAreNeverQueued() throws {
        let database = try AppDatabase.inMemory()
        let row = MeetingRow(createdAt: now, status: .ended, source: .imported, candidateKey: "coffre/a", title: "Ancien", startedAt: now)
        try MeetingStore(database).saveImported(row, importedFrom: "database/Meet/a.md", googleEventID: nil, summary: nil)
        #expect(try TranscriptStore(database).meetingsAwaitingTranscription().isEmpty)
    }

    /// Important 7: the project page saves only what Paul changed, over what a session wrote meanwhile.
    @Test func thePageSavesOnlyWhatPaulChanged() throws {
        let database = try AppDatabase.inMemory()
        let projects = ProjectStore(database)
        let opened = try projects.addProject(name: "Alpha", status: .idee, at: now)
        var written = try #require(try projects.project(id: opened.id))
        written.notes = "- 13/11/2026 : écrit par une session."
        try projects.saveNotes(written)
        var edited = opened
        edited.client = "Studio Sud"
        try projects.saveChanges(from: opened, to: edited, at: now)
        let stored = try #require(try projects.project(id: opened.id))
        #expect(stored.client == "Studio Sud" && stored.notes == "- 13/11/2026 : écrit par une session.")
    }
}

/// Base v5: the color Paul gives each Google account (14/11).
@Suite struct AccountColorTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)

    @Test func aChosenColorStaysThroughSyncs() throws {
        let store = CalendarStore(try AppDatabase.inMemory())
        try store.addAccount(email: "paul@exemple.fr", at: now)
        #expect(try store.accounts().first?.color == nil)
        try store.setColor(email: "Paul@Exemple.fr", hex: "#22A06B")
        try store.recordSync(email: "paul@exemple.fr", syncToken: nil, error: nil, at: now)
        try store.recordSync(email: "paul@exemple.fr", syncToken: nil, error: "réseau", at: now)
        #expect(try store.accounts().first?.color == "#22A06B")
        try store.setColor(email: "paul@exemple.fr", hex: nil)
        #expect(try store.accounts().first?.color == nil)
    }
}
