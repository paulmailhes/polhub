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

/// 14/11: the dialogue reads in paragraphs, one per turn of speech; the transcript copies as text; the
/// summary says where it is.
@Suite struct ParagraphTests {
    let id = UUID()

    func line(_ speaker: Speaker, _ start: Double, _ end: Double, _ text: String) -> UtteranceRow {
        UtteranceRow(meetingID: id, speaker: speaker, startMs: Int(start * 1_000), endMs: Int(end * 1_000), text: text, doubtful: false)
    }

    @Test func linesOfOneVoiceCloseInTimeMakeOneParagraph() {
        let lines = [line(.moi, 0, 3, "Bonjour."), line(.moi, 4, 6, "On commence ?"), line(.autres, 6.5, 8, "Oui."),
                     line(.autres, 14, 16, "Autre sujet."), line(.unknown, 20, 20, "Importé un."), line(.unknown, 20, 20, "Importé deux.")]
        let paragraphs = TranscriptModel.paragraphs(lines)
        #expect(paragraphs.map(\.text) == ["Bonjour. On commence ?", "Oui.", "Autre sujet.", "Importé un.", "Importé deux."])
        #expect(paragraphs.map(\.lines) == [0..<2, 2..<3, 3..<4, 4..<5, 5..<6])
        #expect(paragraphs.first?.speaker == .moi && paragraphs.first?.startMs == 0)
    }

    @Test func theParagraphBeingHeardHoldsTheCurrentLine() {
        let paragraphs = TranscriptModel.paragraphs([line(.moi, 0, 3, "a"), line(.moi, 4, 6, "b"), line(.autres, 7, 8, "c")])
        #expect(TranscriptModel.paragraph(containing: 1, in: paragraphs) == 0)
        #expect(TranscriptModel.paragraph(containing: 2, in: paragraphs) == 1)
        #expect(TranscriptModel.paragraph(containing: nil, in: paragraphs) == nil)
    }

    @Test func theTranscriptCopiesAsPlainText() {
        let text = TranscriptModel.plainText([line(.moi, 65, 66, "Bonjour."), line(.autres, 70, 72, "Salut.")], title: "Point maquette")
        #expect(text == "Point maquette\n\n[1:05] Moi : Bonjour.\n[1:10] Les autres : Salut.\n")
    }

    @Test func theSummarySaysWhereItIs() {
        let now = Date(timeIntervalSince1970: 1_794_562_920)
        #expect(TranscriptModel.summaryText(nil, hasSummary: false, unavailable: nil) == nil)
        #expect(TranscriptModel.summaryText(SummaryJobRow(meetingID: id, state: .queued, updatedAt: now), hasSummary: false, unavailable: nil)
                == "Compte rendu en attente : il se fait après la transcription, jamais pendant une réunion.")
        #expect(TranscriptModel.summaryText(SummaryJobRow(meetingID: id, state: .running, updatedAt: now), hasSummary: false, unavailable: nil)
                == "Compte rendu en cours d'écriture…")
        #expect(TranscriptModel.summaryText(SummaryJobRow(meetingID: id, state: .failed, error: "délai", updatedAt: now), hasSummary: false, unavailable: nil)
                == "Le compte rendu n'a pas pu se faire : délai")
        #expect(TranscriptModel.summaryText(SummaryJobRow(meetingID: id, state: .queued, updatedAt: now), hasSummary: false, unavailable: "Active Apple Intelligence.")
                == "Active Apple Intelligence.")
        #expect(TranscriptModel.summaryText(SummaryJobRow(meetingID: id, state: .done, updatedAt: now), hasSummary: false, unavailable: nil)
                == "Trop peu de paroles pour un compte rendu.")
        #expect(TranscriptModel.summaryText(SummaryJobRow(meetingID: id, state: .done, updatedAt: now), hasSummary: true, unavailable: nil) == nil)
    }
}
