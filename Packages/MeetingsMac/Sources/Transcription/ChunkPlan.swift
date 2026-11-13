import Domain
import Foundation

/// Where Silero hears speech on a track, in seconds from the track's start.
public struct SpeechRegion: Codable, Equatable, Sendable {
    public let start: Double
    public let end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }
}

/// A piece of a track given to the engine, in seconds from the track's start.
public struct Chunk: Codable, Hashable, Sendable {
    public let index: Int
    public let start: Double
    public let end: Double

    public init(index: Int, start: Double, end: Double) {
        self.index = index
        self.start = start
        self.end = end
    }

    public var duration: Double { end - start }
}

/// The engine only gets speech, in long pieces: short ones deprive Whisper of context and make it invent
/// (entry measure of step 2: 0.5 s of margin, merged under 4 s apart, 29 s at most).
public enum ChunkPlan {
    public static func chunks(
        _ regions: [SpeechRegion], duration: Double, padding: Double = 0.5, mergeGap: Double = 4, maxSeconds: Double = 29
    ) -> [Chunk] {
        var spans: [(start: Double, end: Double)] = []
        for region in regions.sorted(by: { $0.start < $1.start }) {
            let start = max(0, region.start - padding), end = min(duration, region.end + padding)
            guard end > start else { continue }
            if let last = spans.last, start - last.end < mergeGap, max(end, last.end) - last.start <= maxSeconds {
                spans[spans.count - 1].end = max(end, last.end)
            } else {
                spans.append((start, end))
            }
        }
        var chunks: [Chunk] = []
        for span in spans {
            let parts = max(1, Int((span.end - span.start - 1e-9) / maxSeconds) + 1)
            let length = (span.end - span.start) / Double(parts)
            for part in 0..<parts {
                let start = span.start + Double(part) * length
                let end = part == parts - 1 ? span.end : start + length
                chunks.append(Chunk(index: chunks.count, start: start, end: end))
            }
        }
        return chunks
    }
}
