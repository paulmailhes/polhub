import Domain
import Foundation
import Persistence
import Recording
import Transcription

public struct ImportSummary: Equatable, Sendable {
    public let lines: Int
    public let doubtful: Bool
    public let removed: Int
    public let rawAudioDeleted: Bool
}

/// Turns what `transcriptor-calcul` wrote into the meeting's dialogue: checks, merge, base, `meeting.json`.
/// The raw audio goes only once the 16 kHz archive is checked.
public enum TranscriptImport {
    public static func run(
        folder: URL, meetingID: UUID, language: String?, transcripts: TranscriptStore, meetings: MeetingStore, now: Date
    ) throws -> ImportSummary {
        let results = Speaker.allCases.flatMap {
            ChunkResultFile.read(folder.appending(path: "transcription/\($0.rawValue).jsonl"))
        }
        let clean = TranscriptChecks.clean(results)
        let lines = Dialogue.lines(clean)
        try transcripts.replaceUtterances(meetingID: meetingID, lines.map { line in
            UtteranceRow(meetingID: meetingID, speaker: line.speaker, startMs: Int((line.start * 1_000).rounded()),
                         endMs: Int((line.end * 1_000).rounded()), text: line.text, doubtful: line.doubtful)
        })
        if var row = try meetings.meeting(id: meetingID) {
            // The thirty days of the audio start here (validated choice).
            row.transcribedAt = now
            row.updatedAt = now
            try meetings.save(row)
        }

        var rawAudioDeleted = false
        let meetingJSON = folder.appending(path: "meeting.json")
        if let data = try? Data(contentsOf: meetingJSON), var file = try? MeetingFile.decoder.decode(MeetingFile.self, from: data) {
            file.version = 2
            file.transcript = TranscriptFile(language: language, transcribedAt: now, lines: lines.map {
                TranscriptLine(speaker: $0.speaker, start: $0.start, end: $0.end, text: $0.text, doubtful: $0.doubtful)
            })
            try MeetingFile.encoder.encode(file).write(to: meetingJSON, options: .atomic)
            if let timeline = try? MeetingTimeline.read(folder.appending(path: "timeline.jsonl")),
               TrackRenderer.rawAudioIsArchived(folder: folder, file: file, timeline: timeline) {
                let raw = folder.appending(path: "audio", directoryHint: .isDirectory)
                if FileManager.default.fileExists(atPath: raw.path(percentEncoded: false)) {
                    try FileManager.default.removeItem(at: raw)
                }
                rawAudioDeleted = true
            }
        }
        return ImportSummary(
            lines: lines.count, doubtful: clean.contains { $0.doubtful }, removed: clean.reduce(0) { $0 + $1.removed.count },
            rawAudioDeleted: rawAudioDeleted
        )
    }
}
