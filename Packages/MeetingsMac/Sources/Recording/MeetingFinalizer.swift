import Domain
import Foundation

/// `meeting.json`: what a meeting is, in an open format next to its audio. With it, the base can be
/// rebuilt from the files alone.
public struct MeetingFile: Equatable, Sendable, Codable {
    public var version = 1
    public var id: UUID
    public var title: String
    public var meetCode: String?
    public var mode: MeetingSource
    public var startedAt: Date
    public var endedAt: Date?
    public var endReason: String?
    /// The earliest stream start, in continuous nanoseconds: the origin of the meeting's time line.
    public var originNanos: UInt64 = 0
    /// The end of the meeting on the streams' clock, when the detector gave it.
    public var endNanos: UInt64?
    public var moiSpans: [ChosenSpan] = []
    public var health: MeetingHealth = .empty
    /// Version 2 (step 2): the dialogue, so that the base can be rebuilt from the files.
    public var transcript: TranscriptFile?

    public init(id: UUID, title: String, meetCode: String?, mode: MeetingSource, startedAt: Date, endedAt: Date?, endReason: String?) {
        self.id = id
        self.title = title
        self.meetCode = meetCode
        self.mode = mode
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.endReason = endReason
    }

    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// The dialogue of a meeting, in `meeting.json`.
public struct TranscriptFile: Equatable, Sendable, Codable {
    public var language: String?
    public var transcribedAt: Date
    public var lines: [TranscriptLine]

    public init(language: String?, transcribedAt: Date, lines: [TranscriptLine]) {
        self.language = language
        self.transcribedAt = transcribedAt
        self.lines = lines
    }
}

public struct TranscriptLine: Equatable, Sendable, Codable {
    public var speaker: Speaker
    public var start: Double
    public var end: Double
    public var text: String
    public var doubtful: Bool

    public init(speaker: Speaker, start: Double, end: Double, text: String, doubtful: Bool) {
        self.speaker = speaker
        self.start = start
        self.end = end
        self.text = text
        self.doubtful = doubtful
    }
}

public enum MeetingFinalizer {
    /// Reads the timeline, chooses the microphone to listen to, writes `meeting.json` and returns it.
    /// A meeting whose timeline is missing (a crash before the first second) still gets its file.
    public static func finalize(folder: URL, header: MeetingFile) throws -> MeetingFile {
        let timeline = (try? MeetingTimeline.read(folder.appending(path: "timeline.jsonl"))) ?? .empty
        var file = header
        file.moiSpans = MicSourceChooser.choose(timeline.runs.filter { $0.track == "moi" })
        file.originNanos = timeline.runs.map(\.startNanos).min() ?? 0
        file.health = timeline.health
        try MeetingFile.encoder.encode(file).write(to: folder.appending(path: "meeting.json"), options: .atomic)
        return file
    }
}
