import Domain
import Foundation
import Persistence

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

    /// `1:05`, or `1:02:05` past an hour.
    public static func timestamp(_ ms: Int) -> String {
        let total = ms / 1_000
        let (hours, minutes, seconds) = (total / 3_600, total / 60 % 60, total % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%d:%02d", minutes, seconds)
    }
}
