import Domain
import Foundation
import Persistence
import Testing
@testable import MeetingsUI

@Suite struct TranscriptModelTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)

    var meeting: MeetingRow {
        MeetingRow(createdAt: now, status: .ended, source: .dia, candidateKey: "t/abc", title: "Point hebdo", startedAt: now)
    }

    func job(_ state: JobState, progress: Double = 0, doubtful: Bool = false, error: String? = nil) -> JobRow {
        JobRow(meetingID: meeting.id, state: state, language: "fr", error: error, progress: progress, doubtful: doubtful, createdAt: now)
    }

    func lines(_ starts: [Int]) -> [UtteranceRow] {
        starts.map { UtteranceRow(meetingID: meeting.id, speaker: .autres, startMs: $0, endMs: $0 + 2_000, text: "…", doubtful: false) }
    }

    @Test func statusTextsSayWhatThePlanSays() {
        func text(_ job: JobRow?, active: Bool = false) -> String? {
            TranscriptModel.text(TranscriptModel.status(job, meeting: meeting, meetingActive: active))
        }
        #expect(text(nil) == "En attente de transcription")
        #expect(text(job(.queued)) == "En attente de transcription")
        #expect(text(job(.queued), active: true) == "Transcription en pause pendant la réunion")
        #expect(text(job(.running, progress: 0.42)) == "Transcription : 42 %")
        #expect(text(job(.done)) == nil)
        #expect(text(job(.done, doubtful: true)) == "À vérifier : le moteur a peut-être inventé des passages.")
        #expect(text(job(.failed, error: "Le moteur a planté.")) == "La transcription a échoué : Le moteur a planté.")
        var recording = meeting
        recording.status = .recording
        #expect(TranscriptModel.status(nil, meeting: recording, meetingActive: true) == nil)
    }

    @Test func theCurrentLineIsTheLastStartedOne() {
        let dialogue = lines([0, 5_000, 12_000])
        #expect(TranscriptModel.currentLine(dialogue, at: 6) == 1)
        #expect(TranscriptModel.currentLine(dialogue, at: 12) == 2)
        #expect(TranscriptModel.currentLine(dialogue, at: 400) == 2)
    }

    @Test func noLineBeforeTheFirstStart() {
        #expect(TranscriptModel.currentLine(lines([3_000, 9_000]), at: 1) == nil)
        #expect(TranscriptModel.currentLine([], at: 10) == nil)
    }

    @Test func timestampsReadLikeAClock() {
        #expect(TranscriptModel.timestamp(65_000) == "1:05")
        #expect(TranscriptModel.timestamp(3_725_000) == "1:02:05")
        #expect(TranscriptModel.timestamp(0) == "0:00")
    }

    @Test func theListBadgeFollowsTheJob() {
        #expect(TranscriptModel.badge(job(.running, progress: 0.5)) == "Transcription 50 %")
        #expect(TranscriptModel.badge(job(.queued)) == "En file")
        #expect(TranscriptModel.badge(job(.failed)) == "Échec")
        #expect(TranscriptModel.badge(job(.done, doubtful: true)) == "À vérifier")
        #expect(TranscriptModel.badge(job(.done)) == nil)
        #expect(TranscriptModel.badge(nil) == nil)
    }
}
