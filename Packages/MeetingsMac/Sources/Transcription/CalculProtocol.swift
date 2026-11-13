import Domain
import Foundation

/// One piece of text from the engine, in seconds from the track's start.
public struct EngineSegment: Codable, Equatable, Sendable {
    public let start: Double
    public let end: Double
    public let text: String
    public let avgLogprob: Double
    public let compressionRatio: Double
    public let noSpeechProb: Double

    public init(start: Double, end: Double, text: String, avgLogprob: Double, compressionRatio: Double, noSpeechProb: Double) {
        self.start = start
        self.end = end
        self.text = text
        self.avgLogprob = avgLogprob
        self.compressionRatio = compressionRatio
        self.noSpeechProb = noSpeechProb
    }
}

/// What the engine made of one chunk: one line of `transcription/<track>.jsonl`.
public struct ChunkResult: Codable, Equatable, Sendable {
    public let track: Speaker
    public let chunk: Chunk
    public let segments: [EngineSegment]

    public init(track: Speaker, chunk: Chunk, segments: [EngineSegment]) {
        self.track = track
        self.chunk = chunk
        self.segments = segments
    }
}

/// The request the app gives `transcriptor-calcul`, as JSON in its first argument.
public struct CalculRequest: Codable, Equatable, Sendable {
    /// The meeting's folder.
    public let folder: String
    /// `fr`, `en`, or `nil` for the engine's own detection.
    public let language: String?

    public init(folder: String, language: String?) {
        self.folder = folder
        self.language = language
    }
}

/// What `transcriptor-calcul` writes on its standard output, one JSON object per line.
public enum CalculMessage: Codable, Equatable, Sendable {
    case progress(track: Speaker, done: Int, total: Int)
    case chunk(ChunkResult)
    case finished
    case failed(String)
}

/// `transcription/<track>.jsonl`: one `ChunkResult` per line, appended and flushed one at a time.
public enum ChunkResultFile {
    /// The lines already written, one per chunk (the last one wins); a line cut by a stop is ignored.
    public static func read(_ url: URL) -> [ChunkResult] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var results: [ChunkResult] = []
        var position: [Chunk: Int] = [:]
        for line in text.split(separator: "\n") {
            guard let result = try? JSONDecoder().decode(ChunkResult.self, from: Data(line.utf8)) else { continue }
            if let index = position[result.chunk] {
                results[index] = result
            } else {
                position[result.chunk] = results.count
                results.append(result)
            }
        }
        return results
    }

    public static func append(_ result: ChunkResult, to url: URL) throws {
        let path = url.path(percentEncoded: false)
        if !FileManager.default.fileExists(atPath: path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        // A stop in the middle of a line leaves it without its end: the next line starts on its own.
        let end = try handle.seekToEnd()
        var line = try JSONEncoder().encode(result) + Data("\n".utf8)
        if end > 0 {
            try handle.seek(toOffset: end - 1)
            if try handle.read(upToCount: 1) != Data("\n".utf8) { line = Data("\n".utf8) + line }
            try handle.seekToEnd()
        }
        try handle.write(contentsOf: line)
        try handle.synchronize()
    }
}
