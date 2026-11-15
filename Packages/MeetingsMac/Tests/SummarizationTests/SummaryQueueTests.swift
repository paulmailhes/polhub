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
    /// The model reports a cancellation as its own error (review of 14/11, Important 4).
    var cancelAsModelError = false
    /// The model's assets are missing although `availability` says otherwise (Important 5).
    var assetsMissing = false
    /// The length of each part's notes.
    var notesLength = 0
    /// Called after each part's notes.
    var afterNotes: (() -> Void)?
    /// The parts the model refuses (its guardrails), even asked again.
    var refusedParts: Set<Int> = []
    /// A text longer than this overflows the model's window.
    var window: Int?
    /// What `characterBudget()` answers.
    var budget = SummaryPlan.maxCharacters
    private(set) var calls = 0
    private(set) var merges = 0
    private(set) var mergedLength = 0
    /// The length of every text read for notes.
    private(set) var read: [Int] = []

    func characterBudget() async -> Int { budget }

    func notes(for chunk: String, part: Int, of count: Int) async throws -> String {
        calls += 1
        if failing { throw SummaryError.model("le modèle n'a pas répondu") }
        if assetsMissing { throw SummaryError.unavailable("Le modèle d'Apple n'est pas disponible pour l'instant.") }
        if refusedParts.contains(part) { throw SummaryError.refused }
        if let window, chunk.count > window { throw SummaryError.tooLong }
        read.append(chunk.count)
        if slow {
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                if cancelAsModelError { throw SummaryError.model("requête annulée") }
                throw error
            }
        }
        afterNotes?()
        return notesLength > 0 ? String(repeating: "n", count: notesLength) : "notes \(part)/\(count)"
    }

    func merge(_ notes: String, part: Int, of count: Int) async throws -> String {
        merges += 1
        return notesLength > 0 ? String(repeating: "m", count: notesLength) : "fusion \(part)/\(count)"
    }

    func summary(of notes: [String], title: String) async throws -> MeetingSummary {
        mergedLength = notes.joined(separator: "\n\n").count
        return MeetingSummary(overview: "\(title) : \(notes.count) parties.", points: ["La maquette avance."], decisions: ["Garder la maquette."],
                              actions: [SummaryAction(text: "envoyer le devis", owner: "Moi", due: "vendredi")])
    }
}

/// The steps a summary went through.
final class Steps: @unchecked Sendable {
    var all: [SummaryProgress] = []
}

final class Flag: @unchecked Sendable {
    var on = false
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

    func queue(_ engine: FakeEngine, otherWork flag: Flag) -> SummaryQueue {
        SummaryQueue(database: database, engine: engine, otherWork: { flag.on }, now: { [now] in now })
    }

    /// 14/11: a written summary is announced (the notification « Compte rendu prêt »).
    @Test func aWrittenSummaryIsAnnounced() async throws {
        let row = try meeting(hoursAgo: 2, title: "Atelier maquette")
        let announced = Flag()
        let queue = SummaryQueue(database: database, engine: FakeEngine(), now: { [now] in now }, onFinished: { id, title in
            if id == row.id && title == "Atelier maquette" { announced.on = true }
        })
        await queue.wake()
        await queue.waitForIdle()
        #expect(announced.on)
    }

    /// 14/11: Réglages › Réunions can turn the summaries off.
    @Test func turnedOffItWritesNothing() async throws {
        let row = try meeting(hoursAgo: 2, title: "Atelier maquette")
        let engine = FakeEngine()
        let queue = SummaryQueue(database: database, engine: engine, isEnabled: { false }, now: { [now] in now })
        await queue.wake()
        await queue.waitForIdle()
        #expect(engine.calls == 0)
        #expect(try SummaryStore(database).job(meetingID: row.id) == nil)
    }

    /// 15/11: « Refaire le compte rendu » works with the automatic summaries off, and only for that meeting.
    @Test func turnedOffItStillRedoesWhenAsked() async throws {
        let asked = try meeting(hoursAgo: 30, title: "Ancien point")
        let other = try meeting(hoursAgo: 2, title: "Atelier maquette")
        let engine = FakeEngine()
        let queue = SummaryQueue(database: database, engine: engine, isEnabled: { false }, now: { [now] in now })
        await queue.redo(meetingID: asked.id)
        await queue.waitForIdle()
        #expect(try SummaryStore(database).job(meetingID: asked.id)?.state == .done)
        #expect(try meetings.summary(meetingID: asked.id) != nil)
        #expect(try SummaryStore(database).job(meetingID: other.id) == nil)
        await queue.wake()
        await queue.waitForIdle()
        #expect(try SummaryStore(database).job(meetingID: other.id) == nil)
    }

    /// 15/11: asked while a meeting goes on, it starts once the meeting ends, even turned off.
    @Test func turnedOffARedoAskedDuringAMeetingWaitsForItsEnd() async throws {
        let row = try meeting(hoursAgo: 2, title: "Atelier maquette")
        let queue = SummaryQueue(database: database, engine: FakeEngine(), isEnabled: { false }, now: { [now] in now })
        await queue.meetingActivity(true)
        await queue.redo(meetingID: row.id)
        #expect(try SummaryStore(database).job(meetingID: row.id)?.state == .queued)
        await queue.meetingActivity(false)
        await queue.waitForIdle()
        #expect(try SummaryStore(database).job(meetingID: row.id)?.state == .done)
    }

    /// 15/11: a meeting with too few words keeps the summary it had (the vault's) and its actions.
    @Test func aShortTranscriptNeverErasesAnExistingSummary() async throws {
        let row = try meeting(hoursAgo: 2, title: "Atelier maquette")
        try TranscriptStore(database).replaceUtterances(meetingID: row.id, [
            UtteranceRow(meetingID: row.id, speaker: .moi, startMs: 0, endMs: 900, text: "Bonjour.", doubtful: false),
        ])
        try meetings.setSummary(meetingID: row.id, summary: "## Résumé\n\nVenu du coffre.")
        try ProjectStore(database).replaceMeetingActions(meetingID: row.id, projectID: nil, actions: [ActionRow(text: "Du coffre", position: 0, createdAt: now)])
        let engine = FakeEngine()
        let queue = queue(engine)
        await queue.redo(meetingID: row.id)
        await queue.waitForIdle()
        #expect(engine.calls == 0)
        #expect(try meetings.summary(meetingID: row.id) == "## Résumé\n\nVenu du coffre.")
        #expect(try ProjectStore(database).actions(meetingID: row.id).map(\.text) == ["Du coffre"])
        #expect(try SummaryStore(database).job(meetingID: row.id)?.state == .done)
    }

    @Test func aStopIsNeverAFailureEvenWhenTheModelCallsItAnError() async throws {
        let row = try meeting(hoursAgo: 2, title: "Atelier maquette")
        let engine = FakeEngine()
        engine.slow = true
        engine.cancelAsModelError = true
        let queue = queue(engine)
        await queue.wake()
        // The meeting starts while the model is working, not before.
        for _ in 0..<200 where engine.calls == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(engine.calls == 1)
        await queue.meetingActivity(true)
        await queue.waitForIdle()
        let job = try #require(try SummaryStore(database).job(meetingID: row.id))
        #expect(job.state == .queued && job.attempts == 0)
    }

    @Test func missingModelAssetsDoNotSpin() async throws {
        let row = try meeting(hoursAgo: 2, title: "Atelier maquette")
        let engine = FakeEngine()
        engine.assetsMissing = true
        let queue = queue(engine)
        await queue.wake()
        await queue.waitForIdle()
        await queue.wake()
        await queue.waitForIdle()
        #expect(engine.calls == 1)
        let job = try #require(try SummaryStore(database).job(meetingID: row.id))
        #expect(job.state == .queued && job.attempts == 0)
    }

    @Test func aTranscriptionThatStartsStopsTheSummary() async throws {
        let row = try meeting(hoursAgo: 2, title: "Atelier maquette")
        let engine = FakeEngine(), transcribing = Flag()
        engine.afterNotes = { transcribing.on = true }
        // Long enough for two parts.
        try TranscriptStore(database).replaceUtterances(meetingID: row.id, (0..<40).map { index in
            UtteranceRow(meetingID: row.id, speaker: .autres, startMs: index * 1_000, endMs: index * 1_000 + 900,
                         text: String(repeating: "On avance sur la maquette. ", count: 20), doubtful: false)
        })
        let queue = queue(engine, otherWork: transcribing)
        await queue.wake()
        await queue.waitForIdle()
        #expect(engine.calls == 1)
        let job = try #require(try SummaryStore(database).job(meetingID: row.id))
        #expect(job.state == .queued && job.attempts == 0)
    }

    @Test func aLongMeetingsNotesAreReducedToFitTheModel() async throws {
        let row = try meeting(hoursAgo: 2, title: "Atelier de deux heures")
        try TranscriptStore(database).replaceUtterances(meetingID: row.id, (0..<400).map { index in
            UtteranceRow(meetingID: row.id, speaker: index % 2 == 0 ? .moi : .autres, startMs: index * 10_000, endMs: index * 10_000 + 9_000,
                         text: String(repeating: "Une phrase de la réunion. ", count: 20), doubtful: false)
        })
        let engine = FakeEngine()
        engine.notesLength = 1_500
        let queue = queue(engine)
        await queue.wake()
        await queue.waitForIdle()
        #expect(try SummaryStore(database).job(meetingID: row.id)?.state == .done)
        #expect(engine.mergedLength > 0 && engine.mergedLength <= SummaryPlan.maxCharacters)
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
