import Compression
import Domain
import Foundation

/// A chunk once checked: what stays, what was removed and why, and whether it must be read with care.
public struct CleanChunk: Equatable, Sendable {
    public let track: Speaker
    public let chunk: Chunk
    public var segments: [EngineSegment]
    /// Shown with « à vérifier »: never hidden.
    public var doubtful: Bool
    public var removed: [Removal]

    public init(track: Speaker, chunk: Chunk, segments: [EngineSegment], doubtful: Bool, removed: [Removal]) {
        self.track = track
        self.chunk = chunk
        self.segments = segments
        self.doubtful = doubtful
        self.removed = removed
    }
}

public struct Removal: Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        /// Whisper repeats itself within a segment (compression ratio above 2.4, its own threshold).
        case loop
        /// A sentence Whisper is known to invent in silence.
        case phantom
        /// The same sentence comes back again and again over the track (a real meeting of 16/09/2026).
        case repeated
    }

    public let reason: Reason
    public let text: String

    public init(reason: Reason, text: String) {
        self.reason = reason
        self.text = text
    }
}

/// The checks of step 2. They remove what Whisper invents and flag what looks wrong; they never hide a
/// meeting.
public enum TranscriptChecks {
    public static let maxCompressionRatio = 2.4
    public static let maxWordsPerSecond = 6.0
    /// A sentence of at least this many words… (« Oui, c'est ça. » is not a loop: review, Important 1)
    static let repeatMinWords = 5
    /// …seen this many times on a track, or this many times in a row, is a loop of the engine: only its
    /// first occurrence stays.
    static let repeatLimit = 10
    static let repeatInARow = 3
    /// Sentences Whisper invents in silence, as whole segments only: a real sentence that contains
    /// « abonnez-vous » stays (review, minor 1).
    static let phantomPatterns = [
        #"^sous[- ]?titr(age|es)\b(\S*\s*){0,3}$"#,
        #"amara\.org"#,
        #"radio[- ]canada$"#,
        #"^merci d'avoir regardé( cette vidéo)?$"#,
        #"^(n'oubliez pas de )?(vous )?abonnez[- ]vous( à (la|ma|notre) chaîne)?$"#,
    ]
    static let loneWords: Set<String> = ["merci", "ok", "okay", "merci beaucoup"]

    /// A sentence Whisper invents in the silence, as a whole (the Dictée, 20/11).
    public static func isPhantom(_ text: String) -> Bool {
        let said = normalized(text)
        return phantomPatterns.contains { said.range(of: $0, options: .regularExpression) != nil }
    }

    public static func clean(_ results: [ChunkResult]) -> [CleanChunk] {
        var chunks = results.map(cleanOne)
        removeRepeats(&chunks)
        return chunks
    }

    static func cleanOne(_ result: ChunkResult) -> CleanChunk {
        var kept: [EngineSegment] = []
        var removed: [Removal] = []
        for segment in result.segments {
            let text = normalized(segment.text)
            let ratio = segment.compressionRatio > 0 ? segment.compressionRatio : compressionRatio(segment.text)
            if ratio > maxCompressionRatio {
                removed.append(Removal(reason: .loop, text: segment.text))
            } else if phantomPatterns.contains(where: { text.range(of: $0, options: .regularExpression) != nil }) {
                removed.append(Removal(reason: .phantom, text: segment.text))
            } else if result.chunk.duration < 2, loneWords.contains(text) {
                removed.append(Removal(reason: .phantom, text: segment.text))
            } else {
                kept.append(segment)
            }
        }
        let words = kept.reduce(0) { $0 + wordCount($1.text) }
        let doubtful = result.chunk.duration > 0 && Double(words) / result.chunk.duration > maxWordsPerSecond
        return CleanChunk(track: result.track, chunk: result.chunk, segments: kept, doubtful: doubtful, removed: removed)
    }

    /// A long sentence that comes back `repeatLimit` times on a track, or `repeatInARow` times in a row: the
    /// later ones go, and every chunk that had one is flagged.
    static func removeRepeats(_ chunks: inout [CleanChunk]) {
        for track in Speaker.allCases {
            let ordered = chunks.indices.filter { chunks[$0].track == track }
                .flatMap { index in chunks[index].segments.map { (index, $0) } }
                .sorted { $0.1.start < $1.1.start }
            var counts: [String: Int] = [:]
            var looping: Set<String> = []
            var previous: String?
            var run = 0
            for (_, segment) in ordered where wordCount(segment.text) >= repeatMinWords {
                let text = normalized(segment.text)
                counts[text, default: 0] += 1
                run = text == previous ? run + 1 : 1
                previous = text
                if counts[text]! >= repeatLimit || run >= repeatInARow { looping.insert(text) }
            }
            guard !looping.isEmpty else { continue }
            var seen: Set<String> = []
            for index in chunks.indices where chunks[index].track == track {
                var kept: [EngineSegment] = []
                for segment in chunks[index].segments {
                    let text = normalized(segment.text)
                    guard looping.contains(text) else { kept.append(segment); continue }
                    chunks[index].doubtful = true
                    if seen.insert(text).inserted {
                        kept.append(segment)
                    } else {
                        chunks[index].removed.append(Removal(reason: .repeated, text: segment.text))
                    }
                }
                chunks[index].segments = kept
            }
        }
    }

    static func normalized(_ text: String) -> String {
        text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: "’", with: "'")
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// Whisper's measure: the text's length over its compressed length.
    static func compressionRatio(_ text: String) -> Double {
        let bytes = Array(text.utf8)
        guard !bytes.isEmpty else { return 0 }
        var output = [UInt8](repeating: 0, count: bytes.count + 1_024)
        let size = compression_encode_buffer(&output, output.count, bytes, bytes.count, nil, COMPRESSION_ZLIB)
        return size > 0 ? Double(bytes.count) / Double(size) : 0
    }
}
