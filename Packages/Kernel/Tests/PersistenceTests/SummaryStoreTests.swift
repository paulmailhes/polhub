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

    /// Review of 14/11, Important 3: a recorded meeting that received the vault's summary at the history
    /// import keeps it, and its actions.
    @Test func aMeetingThatAlreadyHasASummaryIsNeverQueued() throws {
        let (store, meetings, transcripts, database) = try base()
        let row = try meeting(meetings, transcripts, hoursAgo: 2)
        try meetings.setSummary(meetingID: row.id, summary: "## Résumé\n\nVenu du coffre.")
        try ProjectStore(database).replaceMeetingActions(meetingID: row.id, projectID: nil, actions: [ActionRow(text: "Du coffre", position: 0, createdAt: now)])
        #expect(try store.nextPending() == nil)
        try store.redo(meetingID: row.id, at: now)
        #expect(try store.nextPending() == row.id)
    }

    /// Review of 14/11, minor: a new summary keeps the actions Paul checked.
    @Test func aNewSummaryKeepsTheCheckedActions() throws {
        let (store, meetings, transcripts, database) = try base()
        let row = try meeting(meetings, transcripts, hoursAgo: 2)
        try store.finish(meetingID: row.id, summary: "A", actions: [ActionRow(text: "Faite", position: 0, createdAt: now), ActionRow(text: "Pas faite", position: 1, createdAt: now)], at: now)
        var done = try #require(try ProjectStore(database).actions(meetingID: row.id).first { $0.text == "Faite" })
        done.done = true
        try ProjectStore(database).saveAction(done)
        try store.finish(meetingID: row.id, summary: "B", actions: [ActionRow(text: "Nouvelle", position: 0, createdAt: now)], at: now)
        #expect(Set(try ProjectStore(database).actions(meetingID: row.id).map(\.text)) == ["Faite", "Nouvelle"])
    }

    /// Review of 14/11: a summary made again keeps the rows of the actions it finds again (ticked, in a project)
    /// and adds only the new ones.
    @Test func aSummaryMadeAgainMatchesTheActionsItAlreadyHas() throws {
        let (store, meetings, transcripts, database) = try base()
        let row = try meeting(meetings, transcripts, hoursAgo: 2)
        let project = try ProjectStore(database).addProject(name: "Atelier Nord", status: .priorite1, at: now)
        try store.finish(meetingID: row.id, summary: "A", actions: [
            ActionRow(text: "Envoyer le devis", position: 0, createdAt: now), ActionRow(text: "Relire la maquette", position: 1, createdAt: now),
            ActionRow(text: "Appeler Camille", position: 2, createdAt: now),
        ], at: now)
        let actions = ProjectStore(database)
        var sent = try #require(try actions.actions(meetingID: row.id).first { $0.text == "Envoyer le devis" })
        sent.projectID = project.id
        try actions.saveAction(sent)
        var read = try #require(try actions.actions(meetingID: row.id).first { $0.text == "Relire la maquette" })
        read.done = true
        try actions.saveAction(read)
        try store.finish(meetingID: row.id, summary: "B", actions: [
            ActionRow(text: "envoyer le devis", position: 0, createdAt: now), ActionRow(text: "Relire la maquette", position: 1, createdAt: now),
            ActionRow(text: "Préparer le planning", position: 2, createdAt: now),
        ], at: now)
        let after = try actions.actions(meetingID: row.id)
        #expect(after.map(\.text).sorted() == ["Envoyer le devis", "Préparer le planning", "Relire la maquette"])
        #expect(after.first { $0.text == "Envoyer le devis" }?.projectID == project.id)
        #expect(after.first { $0.text == "Relire la maquette" }?.done == true)
    }

    @Test func importedAndDeletedMeetingsAreLeftAlone() throws {
        let (store, meetings, transcripts, _) = try base()
        try meeting(meetings, transcripts, hoursAgo: 3, source: .imported)
        let deleted = try meeting(meetings, transcripts, hoursAgo: 2)
        try meetings.softDelete(id: deleted.id, at: now)
        #expect(try store.nextPending() == nil)
    }
}
