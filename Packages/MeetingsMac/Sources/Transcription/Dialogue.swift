import Domain
import Foundation

/// One line of the dialogue, in seconds from the start of the meeting.
public struct DialogueLine: Equatable, Sendable {
    public let speaker: Speaker
    public let start: Double
    public let end: Double
    public let text: String
    public let doubtful: Bool

    public init(speaker: Speaker, start: Double, end: Double, text: String, doubtful: Bool) {
        self.speaker = speaker
        self.start = start
        self.end = end
        self.text = text
        self.doubtful = doubtful
    }
}

/// The two tracks merged into one dialogue: by start time; a speaker's segments less than 1.5 s apart
/// make one line, a minute at most.
public enum Dialogue {
    public static let joinGap = 1.5
    public static let maxLineSeconds = 60.0

    public static func lines(_ chunks: [CleanChunk]) -> [DialogueLine] {
        let pieces = chunks
            .flatMap { chunk in chunk.segments.map { (chunk.track, $0, chunk.doubtful) } }
            .map { track, segment, doubtful in
                (speaker: track, start: segment.start, end: segment.end,
                 text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines), doubtful: doubtful)
            }
            .filter { !$0.text.isEmpty }
            .sorted { ($0.start, $0.speaker.rawValue) < ($1.start, $1.speaker.rawValue) }

        var lines: [DialogueLine] = []
        for piece in pieces {
            if let last = lines.last, last.speaker == piece.speaker, piece.start - last.end < joinGap,
               max(piece.end, last.end) - last.start <= maxLineSeconds {
                lines[lines.count - 1] = DialogueLine(
                    speaker: last.speaker, start: last.start, end: max(piece.end, last.end),
                    text: last.text + " " + piece.text, doubtful: last.doubtful || piece.doubtful
                )
            } else {
                lines.append(DialogueLine(speaker: piece.speaker, start: piece.start, end: piece.end, text: piece.text, doubtful: piece.doubtful))
            }
        }
        return lines
    }
}
