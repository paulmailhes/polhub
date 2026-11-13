import Domain
import Foundation
import GRDB
import Testing
@testable import Persistence

@Suite struct TranscriptStoreTests {
    let base = Date(timeIntervalSince1970: 1_794_562_920)   // 13/11/2026 10:42 (Paris)

    func meeting(_ title: String, status: MeetingStatus = .ended, deleted: Bool = false, transcribed: Bool = false) -> MeetingRow {
        MeetingRow(
            createdAt: base, status: status, source: .dia, candidateKey: "t/abc-defg-hij", title: title, startedAt: base,
            deletedAt: deleted ? base : nil, transcribedAt: transcribed ? base : nil
        )
    }

    func stores() throws -> (MeetingStore, TranscriptStore) {
        let database = try AppDatabase.inMemory()
        return (MeetingStore(database), TranscriptStore(database))
    }

    func line(_ meetingID: UUID, _ text: String, at seconds: Int = 0, speaker: Speaker = .autres) -> UtteranceRow {
        UtteranceRow(meetingID: meetingID, speaker: speaker, startMs: seconds * 1_000, endMs: seconds * 1_000 + 2_000, text: text, doubtful: false)
    }

    @Test func enqueueReplacesAnUnfinishedJobOfTheSameMeeting() throws {
        let (meetings, transcripts) = try stores()
        let row = meeting("Point hebdo")
        try meetings.save(row)
        _ = try transcripts.enqueue(meetingID: row.id, language: "fr", at: base)
        _ = try transcripts.enqueue(meetingID: row.id, language: "en", at: base.addingTimeInterval(5))
        let queued = try #require(try transcripts.nextQueued())
        #expect(queued.meetingID == row.id && queued.language == "en" && queued.state == .queued)
        #expect(try transcripts.jobs(for: row.id).count == 1)
    }

    @Test func aJobLeftRunningGoesBackToTheQueue() throws {
        let (meetings, transcripts) = try stores()
        let row = meeting("Point hebdo")
        try meetings.save(row)
        var job = try transcripts.enqueue(meetingID: row.id, language: "fr", at: base)
        job.state = .running
        job.attempts = 1
        try transcripts.save(job)
        #expect(try transcripts.resetRunning(at: base) == 1)
        let back = try #require(try transcripts.job(for: row.id))
        #expect(back.state == .queued && back.attempts == 1)
    }

    @Test func onlyEndedMeetingsWithoutJobAwaitTranscription() throws {
        let (meetings, transcripts) = try stores()
        let waiting = meeting("Fin normale")
        let interrupted = meeting("Interrompue", status: .interrupted)
        let queued = meeting("Déjà en file")
        for row in [waiting, interrupted, queued, meeting("En cours", status: .recording), meeting("Refusée", status: .discarded),
                    meeting("Supprimée", deleted: true), meeting("Déjà transcrite", transcribed: true)] {
            try meetings.save(row)
        }
        _ = try transcripts.enqueue(meetingID: queued.id, language: "fr", at: base)
        #expect(Set(try transcripts.meetingsAwaitingTranscription().map(\.title)) == ["Fin normale", "Interrompue"])
    }

    @Test func searchIgnoresAccentsAndCase() throws {
        let (meetings, transcripts) = try stores()
        let row = meeting("Point hebdo")
        try meetings.save(row)
        try transcripts.replaceUtterances(meetingID: row.id, [
            line(row.id, "On fait une Réunion jeudi avec l'équipe.", at: 12),
            line(row.id, "Rien à voir.", at: 30),
        ])
        let hits = try transcripts.search("reunion", limit: 10)
        #expect(hits.count == 1)
        #expect(hits.first?.meetingID == row.id && hits.first?.startMs == 12_000 && hits.first?.title == "Point hebdo")
        #expect(hits.first?.excerpt.contains("Réunion") == true)
        #expect(try transcripts.search("equipe", limit: 10).count == 1)
    }

    @Test func replacingUtterancesKeepsTheIndexInStep() throws {
        let (meetings, transcripts) = try stores()
        let row = meeting("Point hebdo")
        try meetings.save(row)
        try transcripts.replaceUtterances(meetingID: row.id, [line(row.id, "ancienne version du budget")])
        try transcripts.replaceUtterances(meetingID: row.id, [line(row.id, "nouvelle version du planning")])
        #expect(try transcripts.search("budget", limit: 10).isEmpty)
        #expect(try transcripts.search("planning", limit: 10).count == 1)
        #expect(try transcripts.utterances(meetingID: row.id).map(\.text) == ["nouvelle version du planning"])
    }

    @Test func searchSkipsDeletedMeetings() throws {
        let (meetings, transcripts) = try stores()
        let row = meeting("Point hebdo")
        try meetings.save(row)
        try transcripts.replaceUtterances(meetingID: row.id, [line(row.id, "le budget du trimestre")])
        try meetings.softDelete(id: row.id, at: base)
        #expect(try transcripts.search("budget", limit: 10).isEmpty)
    }

    @Test func aReadOnlyBaseReadsButNeverWrites() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "base \(UUID().uuidString).sqlite").path(percentEncoded: false)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let writable = MeetingStore(try AppDatabase(path: path))
        try writable.save(meeting("Point hebdo"))
        let reading = try AppDatabase.readOnly(path: path)
        #expect(try MeetingStore(reading).recent(limit: 10).map(\.title) == ["Point hebdo"])
        #expect(throws: (any Error).self) { try MeetingStore(reading).save(meeting("Interdit")) }
    }

    @Test func aBaseOfStepOneSaysItIsNotReady() throws {
        #expect(try AppDatabase.inMemory().isAtStep2())
        let path = FileManager.default.temporaryDirectory.appending(path: "ancienne \(UUID().uuidString).sqlite").path(percentEncoded: false)
        defer { try? FileManager.default.removeItem(atPath: path) }
        try DatabaseQueue(path: path).write { try $0.execute(sql: "CREATE TABLE meeting (id TEXT PRIMARY KEY)") }
        #expect(try !AppDatabase.readOnly(path: path).isAtStep2())
    }

    // Revue finale, Important 2 : une lecture par la ligne de commande ne doit jamais faire échouer une écriture.
    @Test func aReaderNeverBlocksTheAppsWrites() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "wal \(UUID().uuidString).sqlite").path(percentEncoded: false)
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        let app = MeetingStore(try AppDatabase(path: path))
        try app.save(meeting("Avant"))
        let reading = try AppDatabase.readOnly(path: path)
        try reading.writer.read { db in
            _ = try MeetingRow.fetchAll(db)
            try app.save(meeting("Pendant la lecture"))
        }
        #expect(try app.recent(limit: 10).count == 2)
    }

    @Test func theReadOnlyBaseOpensWhenTheAppIsClosed() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "fermée \(UUID().uuidString).sqlite").path(percentEncoded: false)
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        do {
            let app = MeetingStore(try AppDatabase(path: path))
            try app.save(meeting("Point hebdo"))
        }
        #expect(try MeetingStore(AppDatabase.readOnly(path: path)).recent(limit: 10).map(\.title) == ["Point hebdo"])
    }
}
