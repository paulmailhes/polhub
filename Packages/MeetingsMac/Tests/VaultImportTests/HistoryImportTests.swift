import Domain
import Foundation
import Persistence
import Testing
@testable import VaultImport

/// The vault's contacts and old meetings, added to the app without replacing anything (13/11).
@Suite struct HistoryNoteTests {
    func note(_ path: String) throws -> String {
        try String(contentsOf: fixtureVault.appending(path: "database/\(path)"), encoding: .utf8)
    }

    @Test func aContactNoteGivesItsFieldsAndProjects() throws {
        let contact = HistoryNotes.contact(try note("Contacts/Camille Martin.md"), name: "Camille Martin", relativePath: "database/Contacts/Camille Martin.md")
        #expect(contact.email == "camille.martin@exemple-studio.fr")
        #expect(contact.company == "Exemple Studio" && contact.phone == "+33 6 00 00 00 00")
        #expect(contact.projects == ["Alpha"])
        #expect(contact.notes == "Préfère les rendez-vous le matin.")
    }

    @Test func aMeetingNoteGivesSummaryActionsAndTranscript() throws {
        let meeting = HistoryNotes.meeting(try note("Meet/2026-10-20 10h00 Point maquette Alpha.md"), name: "2026-10-20 10h00 Point maquette Alpha",
                                           relativePath: "database/Meet/2026-10-20 10h00 Point maquette Alpha.md")
        #expect(meeting.title == "Point maquette Alpha")
        #expect(meeting.date == VaultDates.date("2026-10-20T10:00"))
        #expect(meeting.participants == ["Camille Martin", "Nadia Exemple"])
        #expect(meeting.project == "Alpha" && meeting.eventID == "evt-alpha-1")
        #expect(meeting.summary == "### Contexte\n- La maquette de l'accueil est validée.\n### Suite\n- Reste la page Contact.")
        #expect(meeting.actions.map(\.text) == ["Envoyer la maquette", "Préparer la page Contact"])
        #expect(meeting.actions.map(\.done) == [true, false])
        #expect(meeting.transcript == ["Bonjour, on regarde la maquette ?", "Oui, l'accueil me plaît.\nEt la suite ?"])
    }

    @Test func aBareNoteStillGivesATitleAndADate() throws {
        let meeting = HistoryNotes.meeting(try note("Meet/2026-11-01 Point Alpha.md"), name: "2026-11-01 Point Alpha",
                                           relativePath: "database/Meet/2026-11-01 Point Alpha.md")
        #expect(meeting.title == "Point Alpha" && meeting.project == "Alpha" && meeting.date != nil)
        #expect(meeting.transcript.isEmpty && meeting.summary.isEmpty)
    }
}

@Suite struct HistoryImportTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)

    struct Stores {
        let database: AppDatabase
        var projects: ProjectStore { ProjectStore(database) }
        var contacts: ContactStore { ContactStore(database) }
        var meetings: MeetingStore { MeetingStore(database) }
        var transcripts: TranscriptStore { TranscriptStore(database) }
    }

    func stores() throws -> Stores {
        let stores = Stores(database: try AppDatabase.inMemory())
        try stores.projects.replaceAll([ProjectRow(name: "Alpha", status: .idee, createdAt: now),
                                        ProjectRow(name: "Beta Studio", status: .idee, createdAt: now)], actions: [], journal: [])
        return stores
    }

    func imported(_ stores: Stores) throws -> MeetingRow {
        try #require(try stores.meetings.importedMeeting(from: "database/Meet/2026-10-20 10h00 Point maquette Alpha.md"))
    }

    @Test func contactsAndMeetingsComeWithTheirLinks() throws {
        let stores = try stores()
        let report = try HistoryImport.apply(try HistoryReader.read(vault: fixtureVault), database: stores.database, now: now)
        #expect(report.contacts == 2 && report.meetings == 3)
        let alpha = try #require(try stores.projects.projects().first { $0.name == "Alpha" })
        let camille = try #require(try stores.contacts.contact(email: "camille.martin@exemple-studio.fr"))
        #expect(try stores.contacts.contacts(projectID: alpha.id).map(\.name) == ["Camille Martin"])
        let meeting = try imported(stores)
        #expect(meeting.source == .imported && meeting.title == "Point maquette Alpha" && meeting.projectID == alpha.id)
        #expect(try stores.contacts.participants(meetingID: meeting.id).map(\.name) == ["Camille Martin", "Nadia Exemple"])
        #expect(try stores.contacts.meetings(contactID: camille.id).map(\.id).contains(meeting.id))
        #expect(try stores.meetings.summary(meetingID: meeting.id)?.contains("La maquette de l'accueil est validée.") == true)
        #expect(try stores.meetings.meeting(googleEventID: "evt-alpha-1")?.id == meeting.id)
        let actions = try stores.projects.actions(projectID: alpha.id)
        #expect(actions.map(\.text) == ["Envoyer la maquette", "Préparer la page Contact"] && actions.allSatisfy { $0.meetingID == meeting.id })
        let lines = try stores.transcripts.utterances(meetingID: meeting.id)
        #expect(lines.count == 2 && lines.allSatisfy { $0.speaker == .unknown })
    }

    @Test func importingTwiceChangesNothing() throws {
        let stores = try stores()
        let snapshot = try HistoryReader.read(vault: fixtureVault)
        _ = try HistoryImport.apply(snapshot, database: stores.database, now: now)
        let first = (try stores.contacts.contacts().count, try stores.meetings.recent(limit: 100).count, try stores.projects.actions(projectID: try imported(stores).projectID!).count)
        _ = try HistoryImport.apply(snapshot, database: stores.database, now: now)
        let second = (try stores.contacts.contacts().count, try stores.meetings.recent(limit: 100).count, try stores.projects.actions(projectID: try imported(stores).projectID!).count)
        #expect(first == second)
    }

    @Test func aMeetingPolhubRecordedIsCompletedNotDuplicated() throws {
        let stores = try stores()
        let start = try #require(VaultDates.date("2026-10-20T10:03"))
        let recorded = MeetingRow(createdAt: start, status: .ended, source: .dia, candidateKey: "t/a", title: "Google Meet", startedAt: start,
                                  endedAt: start.addingTimeInterval(1_800))
        try stores.meetings.save(recorded)
        let report = try HistoryImport.apply(try HistoryReader.read(vault: fixtureVault), database: stores.database, now: now)
        #expect(report.meetings == 3 && report.merged == 1)
        let merged = try #require(try stores.meetings.meeting(id: recorded.id))
        #expect(merged.title == "Point maquette Alpha" && merged.projectID != nil)
        #expect(try stores.meetings.meeting(googleEventID: "evt-alpha-1")?.id == recorded.id)
        #expect(try stores.contacts.participants(meetingID: recorded.id).count == 2)
        #expect(try stores.transcripts.utterances(meetingID: recorded.id).isEmpty)   // Polhub's own transcript is kept
    }

    @Test func aLinkPaulRemovedIsNotBroughtBackByTheImport() throws {
        let stores = try stores()
        let snapshot = try HistoryReader.read(vault: fixtureVault)
        _ = try HistoryImport.apply(snapshot, database: stores.database, now: now)
        let alpha = try #require(try stores.projects.projects().first { $0.name == "Alpha" })
        let camille = try #require(try stores.contacts.contact(email: "camille.martin@exemple-studio.fr"))
        try stores.contacts.exclude(contactID: camille.id, projectID: alpha.id, at: now)
        _ = try HistoryImport.apply(snapshot, database: stores.database, now: now)
        #expect(try stores.contacts.contacts(projectID: alpha.id).isEmpty)
    }

    /// Review, Important 4: a second import adds what is missing and overwrites nothing Paul did.
    @Test func aSecondImportKeepsPaulsEdits() throws {
        let stores = try stores()
        let snapshot = try HistoryReader.read(vault: fixtureVault)
        _ = try HistoryImport.apply(snapshot, database: stores.database, now: now)
        var camille = try #require(try stores.contacts.contact(email: "camille.martin@exemple-studio.fr"))
        camille.company = "Nouveau studio"
        try stores.contacts.save(camille, at: now)
        let meeting = try imported(stores)
        var action = try #require(try stores.projects.actions(projectID: meeting.projectID!).first { !$0.done })
        action.done = true
        try stores.projects.saveAction(action)
        let bare = try #require(try stores.meetings.importedMeeting(from: "database/Meet/2026-11-01 Point Alpha.md"))
        try stores.meetings.softDelete(id: bare.id, at: now)

        _ = try HistoryImport.apply(snapshot, database: stores.database, now: now)

        #expect(try stores.contacts.contact(email: "camille.martin@exemple-studio.fr")?.company == "Nouveau studio")
        #expect(try stores.projects.actions(projectID: meeting.projectID!).allSatisfy(\.done))
        #expect(try stores.meetings.meeting(id: bare.id)?.deletedAt != nil)
    }

    /// Review, Important 5: an address already used by another contact never stops the import.
    @Test func anAddressAlreadyUsedDoesNotStopTheImport() throws {
        let stores = try stores()
        func snapshot(email: String?) -> HistorySnapshot {
            var jules = ImportedContact(name: "Jules (Beta)", relativePath: "database/Contacts/Jules (Beta).md")
            jules.email = email
            let nadia = ImportedContact(name: "Nadia", relativePath: "database/Contacts/Nadia.md")
            return HistorySnapshot(contacts: [jules, nadia], meetings: [], warnings: [])
        }
        _ = try HistoryImport.apply(snapshot(email: nil), database: stores.database, now: now)
        try stores.contacts.upsert(email: "jules@beta.fr", name: "Jules", company: nil, at: now)
        let report = try HistoryImport.apply(snapshot(email: "jules@beta.fr"), database: stores.database, now: now)
        #expect(report.contacts == 2)
        #expect(try stores.contacts.contacts().map(\.name).contains("Nadia"))
    }
}
