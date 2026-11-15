import Domain
import Foundation
import Persistence
import Summarization

/// Where the transcription of a meeting is, as the window says it.
public enum TranscriptStatus: Equatable, Sendable {
    case notYet
    case queued
    /// Queued, but a meeting is going on: nothing is computed during a meeting.
    case paused
    case running(Double)
    case done(doubtful: Bool)
    case failed(String)
}

public enum TranscriptModel {
    /// `nil` while the meeting is still being recorded.
    public static func status(_ job: JobRow?, meeting: MeetingRow, meetingActive: Bool) -> TranscriptStatus? {
        guard !meeting.status.isUnfinished, meeting.status != .discarded else { return nil }
        guard let job else { return meeting.transcribedAt == nil ? .notYet : .done(doubtful: false) }
        switch job.state {
        case .queued: return meetingActive ? .paused : .queued
        case .running: return .running(job.progress)
        case .done: return .done(doubtful: job.doubtful)
        case .failed: return .failed(job.error ?? "raison inconnue.")
        }
    }

    /// The sentence above the dialogue; `nil` when there is nothing to say.
    public static func text(_ status: TranscriptStatus?) -> String? {
        switch status {
        case nil, .done(doubtful: false)?: nil
        case .notYet?, .queued?: "En attente de transcription"
        case .paused?: "Transcription en pause pendant la réunion"
        case .running(let progress)?: "Transcription : \(Int((progress * 100).rounded())) %"
        case .done(doubtful: true)?: "À vérifier : le moteur a peut-être inventé des passages."
        case .failed(let message)?: "La transcription a échoué : \(message)"
        }
    }

    /// The small label next to a meeting in the list.
    public static func badge(_ job: JobRow?) -> String? {
        switch job?.state {
        case .queued?: "En file"
        case .running?: "Transcription \(Int(((job?.progress ?? 0) * 100).rounded())) %"
        case .failed?: "Échec"
        case .done? where job?.doubtful == true: "À vérifier"
        default: nil
        }
    }

    /// The line being heard: the last one started at `seconds`.
    public static func currentLine(_ lines: [UtteranceRow], at seconds: Double) -> Int? {
        let ms = Int(seconds * 1_000)
        return lines.lastIndex { $0.startMs <= ms }
    }

    /// One turn of speech: the lines of one voice, each starting within 4 s of the previous one's end (14/11).
    public struct Paragraph: Equatable, Sendable {
        public var speaker: Speaker
        public var startMs: Int
        public var text: String
        public var doubtful: Bool
        /// The lines it gathers, as indices in the dialogue.
        public var lines: Range<Int>
    }

    public static let paragraphGapMs = 4_000

    public static func paragraphs(_ lines: [UtteranceRow]) -> [Paragraph] {
        var result: [Paragraph] = []
        for (index, line) in lines.enumerated() {
            if var last = result.last, line.speaker != .unknown, last.speaker == line.speaker,
               line.startMs - lines[last.lines.upperBound - 1].endMs <= paragraphGapMs {
                last.text += " " + line.text
                last.doubtful = last.doubtful || line.doubtful
                last.lines = last.lines.lowerBound..<(index + 1)
                result[result.count - 1] = last
            } else {
                result.append(Paragraph(speaker: line.speaker, startMs: line.startMs, text: line.text, doubtful: line.doubtful, lines: index..<(index + 1)))
            }
        }
        return result
    }

    /// The paragraph holding the line being heard.
    public static func paragraph(containing line: Int?, in paragraphs: [Paragraph]) -> Int? {
        guard let line else { return nil }
        return paragraphs.firstIndex { $0.lines.contains(line) }
    }

    /// The dialogue as text, for « Copier la transcription ».
    public static func plainText(_ lines: [UtteranceRow], title: String) -> String {
        title + "\n\n" + lines.map { line in
            line.speaker == .unknown ? line.text : "[\(timestamp(line.startMs))] \(line.speaker.label) : \(line.text)"
        }.joined(separator: "\n") + "\n"
    }

    static let summaryWaiting = "Compte rendu en attente : il se fait après la transcription, jamais pendant une réunion."

    /// The sentence of the summary's card, or `nil` when the summary is there (or not started). `waiting`: the
    /// meeting is transcribed and nothing has been asked yet, as in the minute before the queue's next turn (15/11).
    public static func summaryText(_ job: SummaryJobRow?, hasSummary: Bool, unavailable: String?, progress: SummaryProgress? = nil,
                                   waiting: Bool = false) -> String? {
        guard let job else { return waiting && !hasSummary ? unavailable ?? summaryWaiting : nil }
        guard !hasSummary || job.state == .running else { return nil }
        if let unavailable, job.state != .done { return unavailable }
        switch job.state {
        case .queued: return summaryWaiting
        case .running:
            guard let progress, progress.total > 1 || progress.finishing else { return "Compte rendu en cours d'écriture…" }
            if progress.finishing { return "Compte rendu : dernière étape…" }
            return "Compte rendu : partie \(min(progress.done + 1, progress.total)) sur \(progress.total)…"
        case .failed: return "Le compte rendu n'a pas pu se faire : \(job.error ?? "raison inconnue.")"
        case .done: return "Trop peu de paroles pour un compte rendu."
        }
    }

    /// `1:05`, or `1:02:05` past an hour.
    public static func timestamp(_ ms: Int) -> String {
        let total = ms / 1_000
        let (hours, minutes, seconds) = (total / 3_600, total / 60 % 60, total % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%d:%02d", minutes, seconds)
    }
}
