import Domain
import Foundation
import Testing
@testable import Persistence

/// Base v6: which meetings wait for their summary, and how it went (14/11).
@Suite struct SummaryStoreTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)

    func base() throws -> (SummaryStore, MeetingStore, TranscriptStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (SummaryStore(database), MeetingStore(database), TranscriptStore(database), database)
    }

    @discardableResult
    func meeting(_ meetings: MeetingStore, _ transcripts: TranscriptStore, hoursAgo: Double, transcribed: Bool = true,
                 source: MeetingSource = .dia, words: Bool = true) throws -> MeetingRow {
        let start = now.addingTimeInterval(-hoursAgo * 3_600)
        let row = MeetingRow(createdAt: start, status: .ended, source: source, candidateKey: "t/\(hoursAgo)", title: "Réunion \(hoursAgo)",
                             startedAt: start, endedAt: start.addingTimeInterval(1_800), transcribedAt: transcribed ? start.addingTimeInterval(2_000) : nil)
        try meetings.save(row)
        if words {
            try transcripts.replaceUtterances(meetingID: row.id, [UtteranceRow(meetingID: row.id, speaker: .moi, startMs: 0, endMs: 900, text: "Bonjour", doubtful: false)])
        }
        return row
    }

    @Test func theNewestTranscribedMeetingComesFirst() throws {
        let (store, meetings, transcripts, _) = try base()
        try meeting(meetings, transcripts, hoursAgo: 30)
        let recent = try meeting(meetings, transcripts, hoursAgo: 2)
        try meeting(meetings, transcripts, hoursAgo: 1, transcribed: false)
        try meeting(meetings, transcripts, hoursAgo: 0.5, words: false)
        #expect(try store.nextPending() == recent.id)
    }

    @Test func aDoneSummaryIsNotDoneAgainUnlessTheMeetingIsTranscribedAgain() throws {
        let (store, meetings, transcripts, database) = try base()
        var row = try meeting(meetings, transcripts, hoursAgo: 2)
        try store.start(meetingID: row.id, at: now)
        try store.finish(meetingID: row.id, summary: "## Résumé\n\nUn point.", actions: [
            ActionRow(projectID: nil, meetingID: nil, text: "Envoyer la maquette", done: false, owner: "Moi", position: 0, createdAt: now, updatedAt: now),
        ], at: now)
        #expect(try store.nextPending() == nil)
        #expect(try MeetingStore(database).summary(meetingID: row.id) == "## Résumé\n\nUn point.")
        #expect(try ProjectStore(database).actions(meetingID: row.id).map(\.text) == ["Envoyer la maquette"])
        #expect(try store.job(meetingID: row.id)?.state == .done)
        row.transcribedAt = now.addingTimeInterval(60)
        try meetings.save(row)
        #expect(try store.nextPending() == row.id)
    }

    @Test func twoFailuresStopTheRetriesUntilPaulAsks() throws {
        let (store, meetings, transcripts, _) = try base()
        let row = try meeting(meetings, transcripts, hoursAgo: 2)
        try store.start(meetingID: row.id, at: now)
        try store.fail(meetingID: row.id, error: "délai dépassé", at: now)
        #expect(try store.nextPending() == row.id)
        try store.start(meetingID: row.id, at: now)
        try store.fail(meetingID: row.id, error: "délai dépassé", at: now)
        #expect(try store.nextPending() == nil)
        #expect(try store.job(meetingID: row.id)?.state == .failed && store.job(meetingID: row.id)?.error == "délai dépassé")
        try store.redo(meetingID: row.id, at: now)
        #expect(try store.nextPending() == row.id)
    }

    @Test func aStoppedSummaryGoesBackToTheQueueWithoutCountingAsAFailure() throws {
        let (store, meetings, transcripts, _) = try base()
        let row = try meeting(meetings, transcripts, hoursAgo: 2)
        try store.start(meetingID: row.id, at: now)
        #expect(try store.nextPending() == nil)
        try store.stopped(meetingID: row.id, at: now)
        #expect(try store.job(meetingID: row.id)?.attempts == 0)
        #expect(try store.nextPending() == row.id)
        try store.start(meetingID: row.id, at: now)
        #expect(try store.resetRunning(at: now) == 1)
        #expect(try store.nextPending() == row.id)
    }

    @Test func anActionPaulPutInTheProjectSurvivesANewSummary() throws {
        let (store, meetings, transcripts, database) = try base()
        let row = try meeting(meetings, transcripts, hoursAgo: 2)
        let project = try ProjectStore(database).addProject(name: "Atelier Nord", status: .priorite1, at: now)
        try store.finish(meetingID: row.id, summary: "## Résumé\n\nA.", actions: [
            ActionRow(text: "Envoyer le devis", position: 0, createdAt: now), ActionRow(text: "Relire", position: 1, createdAt: now),
        ], at: now)
        var kept = try #require(try ProjectStore(database).actions(meetingID: row.id).first { $0.text == "Envoyer le devis" })
        kept.projectID = project.id
        try ProjectStore(database).saveAction(kept)
        try store.finish(meetingID: row.id, summary: "## Résumé\n\nB.", actions: [ActionRow(text: "Appeler", position: 0, createdAt: now)], at: now)
        #expect(Set(try ProjectStore(database).actions(meetingID: row.id).map(\.text)) == ["Envoyer le devis", "Appeler"])
        #expect(try ProjectStore(database).actions(projectID: project.id).map(\.text) == ["Envoyer le devis"])
    }

    @Test func importedAndDeletedMeetingsAreLeftAlone() throws {
        let (store, meetings, transcripts, _) = try base()
        try meeting(meetings, transcripts, hoursAgo: 3, source: .imported)
        let deleted = try meeting(meetings, transcripts, hoursAgo: 2)
        try meetings.softDelete(id: deleted.id, at: now)
        #expect(try store.nextPending() == nil)
    }
}
