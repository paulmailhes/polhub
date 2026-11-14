import Domain
import Foundation
import Persistence
import Testing
@testable import Summarization

/// A model stand-in: notes are the chunk's first words, the summary says how many notes it got.
final class FakeEngine: SummaryEngine, @unchecked Sendable {
    var unavailableReason: String?
    var slow = false
    var failing = false
    private(set) var calls = 0

    func notes(for chunk: String, part: Int, of count: Int) async throws -> String {
        calls += 1
        if failing { throw SummaryError.model("le modèle n'a pas répondu") }
        if slow { try await Task.sleep(for: .seconds(30)) }
        return "notes \(part)/\(count)"
    }

    func summary(of notes: [String], title: String) async throws -> MeetingSummary {
        MeetingSummary(overview: "\(title) : \(notes.count) parties.", decisions: ["Garder la maquette."],
                       actions: [SummaryAction(text: "envoyer le devis", owner: "Moi", due: "vendredi")])
    }
}

@Suite struct SummaryQueueTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)
    let database: AppDatabase
    let meetings: MeetingStore

    init() throws {
        database = try AppDatabase.inMemory()
        meetings = MeetingStore(database)
    }

    @discardableResult
    func meeting(hoursAgo: Double, title: String) throws -> MeetingRow {
        let start = now.addingTimeInterval(-hoursAgo * 3_600)
        let row = MeetingRow(createdAt: start, status: .ended, source: .dia, candidateKey: "t/\(hoursAgo)", title: title,
                             startedAt: start, endedAt: start.addingTimeInterval(1_800), transcribedAt: start.addingTimeInterval(2_000))
        try meetings.save(row)
        let words = String(repeating: "On avance sur la maquette et le devis. ", count: 12)
        try TranscriptStore(database).replaceUtterances(meetingID: row.id, [
            UtteranceRow(meetingID: row.id, speaker: .moi, startMs: 0, endMs: 900, text: words, doubtful: false),
            UtteranceRow(meetingID: row.id, speaker: .autres, startMs: 1_000, endMs: 1_900, text: words, doubtful: false),
        ])
        return row
    }

    func queue(_ engine: FakeEngine, otherWork: Bool = false) -> SummaryQueue {
        SummaryQueue(database: database, engine: engine, otherWork: { otherWork }, now: { [now] in now })
    }

    @Test func theMeetingsAreSummarizedNewestFirstWithTheirActions() async throws {
        let older = try meeting(hoursAgo: 30, title: "Ancien point")
        let recent = try meeting(hoursAgo: 2, title: "Atelier maquette")
        let queue = queue(FakeEngine())
        await queue.wake()
        await queue.waitForIdle()
        #expect(try meetings.summary(meetingID: recent.id)?.hasPrefix("## Résumé\n\nAtelier maquette : ") == true)
        #expect(try meetings.summary(meetingID: older.id) != nil)
        let actions = try ProjectStore(database).actions(meetingID: recent.id)
        #expect(actions.map(\.text) == ["Envoyer le devis (vendredi)"] && actions.first?.owner == "Moi" && actions.first?.projectID == nil)
        #expect(try SummaryStore(database).job(meetingID: recent.id)?.state == .done)
    }

    @Test func aMeetingThatStartsStopsTheSummaryWhichResumesAfter() async throws {
        let row = try meeting(hoursAgo: 2, title: "Atelier maquette")
        let engine = FakeEngine()
        engine.slow = true
        let queue = queue(engine)
        await queue.wake()
        #expect(try SummaryStore(database).job(meetingID: row.id)?.state == .running)
        await queue.meetingActivity(true)
        await queue.waitForIdle()
        let stopped = try #require(try SummaryStore(database).job(meetingID: row.id))
        #expect(stopped.state == .queued && stopped.attempts == 0)
        engine.slow = false
        await queue.wake()   // still in a meeting: nothing starts
        #expect(try SummaryStore(database).job(meetingID: row.id)?.state == .queued)
        await queue.meetingActivity(false)
        await queue.waitForIdle()
        #expect(try SummaryStore(database).job(meetingID: row.id)?.state == .done)
    }

    @Test func anUnavailableModelOrATranscriptionUnderWayLetsItWait() async throws {
        let row = try meeting(hoursAgo: 2, title: "Atelier maquette")
        let engine = FakeEngine()
        engine.unavailableReason = "Apple Intelligence est désactivée."
        await queue(engine).wake()
        await queue(FakeEngine(), otherWork: true).wake()
        #expect(engine.calls == 0)
        #expect(try SummaryStore(database).job(meetingID: row.id) == nil)
        #expect(await queue(engine).unavailableReason == "Apple Intelligence est désactivée.")
    }

    @Test func twoFailuresWaitForRedo() async throws {
        let row = try meeting(hoursAgo: 2, title: "Atelier maquette")
        let engine = FakeEngine()
        engine.failing = true
        let queue = queue(engine)
        await queue.wake()
        await queue.waitForIdle()
        let job = try #require(try SummaryStore(database).job(meetingID: row.id))
        #expect(job.state == .failed && job.attempts == 2 && job.error?.contains("n'a pas répondu") == true)
        engine.failing = false
        await queue.redo(meetingID: row.id)
        await queue.waitForIdle()
        #expect(try SummaryStore(database).job(meetingID: row.id)?.state == .done)
    }
}
