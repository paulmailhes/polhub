import Domain
import Foundation
import Persistence
import Summarization
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
        #expect(text(job(.running, progress: 0.42)) == "Transcription 42\u{202F}%")
        #expect(text(job(.done)) == nil)
        #expect(text(job(.done, doubtful: true)) == "À vérifier : la transcription a peut-être inventé des passages.")
        #expect(text(job(.failed, error: "Le moteur a planté.")) == "La transcription a échoué. Réessaie.")
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
        #expect(TranscriptModel.badge(job(.running, progress: 0.5)) == .running(percent: 50))
        #expect(TranscriptModel.badge(job(.queued)) == .queued)
        #expect(TranscriptModel.badge(job(.failed)) == .failed)
        #expect(TranscriptModel.badge(job(.done, doubtful: true)) == .toCheck)
        #expect(TranscriptModel.badge(job(.done)) == nil)
        #expect(TranscriptModel.badge(nil) == nil)
        // The words beside the state; the color reads the state (lot 10, 20/11).
        #expect(TranscriptBadge.running(percent: 50).text == "Transcription 50\u{202F}%" && TranscriptBadge.queued.text == "En attente")
        #expect(TranscriptBadge.failed.text == "Échec" && TranscriptBadge.toCheck.text == "À vérifier")
        #expect(TranscriptBadge.failed.needsAttention && TranscriptBadge.toCheck.needsAttention)
        #expect(!TranscriptBadge.queued.needsAttention && !TranscriptBadge.running(percent: 50).needsAttention)
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

    /// Correctifs du 15/11 : un « Refaire » qui échoue ou attend se dit au-dessus de l'ancien compte rendu ; une
    /// pause du modèle (occupé) dit sa raison, pas « il se fait après la transcription ».
    @Test func aRedoThatFailsOrWaitsIsSaidOverTheOldSummary() {
        let now = Date(timeIntervalSince1970: 1_794_562_920)
        #expect(TranscriptModel.summaryText(SummaryJobRow(meetingID: id, state: .failed, attempts: 2, error: "délai", updatedAt: now),
                                            hasSummary: true, unavailable: nil) == "Le nouveau compte rendu n'a pas pu se faire : délai")
        #expect(TranscriptModel.summaryText(SummaryJobRow(meetingID: id, state: .queued, updatedAt: now), hasSummary: true, unavailable: nil)
                == "Nouveau compte rendu en attente : il se fait après la transcription, jamais pendant une réunion.")
        let busy = SummaryJobRow(meetingID: id, state: .queued, error: "Le modèle d'Apple est occupé.", updatedAt: now)
        #expect(TranscriptModel.summaryText(busy, hasSummary: false, unavailable: nil) == "Le modèle d'Apple est occupé.")
        #expect(TranscriptModel.summaryText(busy, hasSummary: true, unavailable: nil) == "Le modèle d'Apple est occupé.")
        // A first failure that will be tried again still says it waits.
        #expect(TranscriptModel.summaryText(SummaryJobRow(meetingID: id, state: .queued, attempts: 1, error: "délai", updatedAt: now),
                                            hasSummary: false, unavailable: nil)
                == "Compte rendu en attente : il se fait après la transcription, jamais pendant une réunion.")
    }

    /// 15/11: the card says which part is read, then the last step; and that a transcribed meeting waits, before
    /// the queue takes it.
    @Test func theSummarySaysWhichPartIsRead() {
        let now = Date(timeIntervalSince1970: 1_794_562_920)
        let running = SummaryJobRow(meetingID: id, state: .running, updatedAt: now)
        #expect(TranscriptModel.summaryText(running, hasSummary: false, unavailable: nil, progress: SummaryProgress(done: 1, total: 5))
                == "Compte rendu : partie 2 sur 5…")
        #expect(TranscriptModel.summaryText(running, hasSummary: false, unavailable: nil, progress: SummaryProgress(done: 5, total: 5, finishing: true))
                == "Compte rendu : dernière étape…")
        #expect(TranscriptModel.summaryText(running, hasSummary: false, unavailable: nil, progress: SummaryProgress(done: 0, total: 1))
                == "Compte rendu en cours d'écriture…")
        #expect(TranscriptModel.summaryText(nil, hasSummary: false, unavailable: nil, waiting: true)
                == "Compte rendu en attente : il se fait après la transcription, jamais pendant une réunion.")
        #expect(TranscriptModel.summaryText(nil, hasSummary: true, unavailable: nil, waiting: true) == nil)
        #expect(TranscriptModel.summaryText(nil, hasSummary: false, unavailable: "Active Apple Intelligence.", waiting: true) == "Active Apple Intelligence.")
        #expect(SummaryProgress(done: 2, total: 3).fraction == 0.5)
    }
}
