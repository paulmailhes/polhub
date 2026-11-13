import AVFoundation
import Domain
import Foundation
import Recording
import Transcription

/// One transcription of a meeting, resumable: every chunk done is one line of
/// `transcription/<track>.jsonl`, written before it is announced. A stopped run starts again where it was.
public struct TranscriptionRun: Sendable {
    public let request: CalculRequest
    let detector: any SpeechDetecting
    let engine: any TranscribingEngine
    let batchSize: Int
    let emit: @Sendable (CalculMessage) -> Void

    public init(
        request: CalculRequest, detector: any SpeechDetecting, engine: any TranscribingEngine, batchSize: Int = 16,
        emit: @escaping @Sendable (CalculMessage) -> Void
    ) {
        self.request = request
        self.detector = detector
        self.engine = engine
        self.batchSize = batchSize
        self.emit = emit
    }

    public enum RunError: Error, CustomStringConvertible {
        case noMeetingFile
        case unreadableTrack(String)
        case alreadyRunning

        public var description: String {
            switch self {
            case .noMeetingFile: "La réunion n'a pas de meeting.json : son enregistrement s'est arrêté avant la fin."
            case .unreadableTrack(let name): "La piste « \(name) » de l'archive est illisible."
            case .alreadyRunning: "Une autre transcription de cette réunion tourne déjà."
            }
        }
    }

    var folder: URL { URL(fileURLWithPath: request.folder, isDirectory: true) }
    var results: URL { folder.appending(path: "transcription", directoryHint: .isDirectory) }

    public func run() async throws {
        try FileManager.default.createDirectory(at: results, withIntermediateDirectories: true)
        // One run per meeting: a run left by a crashed app must not write the same files (review, Important 4).
        let lock = open(results.appending(path: ".lock").path(percentEncoded: false), O_CREAT | O_RDWR, 0o644)
        guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            if lock >= 0 { close(lock) }
            throw RunError.alreadyRunning
        }
        defer { close(lock) }
        let tracks = try archive()
        for (track, url) in [(Speaker.moi, tracks.moi), (.autres, tracks.autres)] {
            guard let url else { continue }
            try await transcribe(track, url: url)
        }
        emit(.finished)
    }

    /// The 16 kHz archive, made from the raw audio the first time.
    func archive() throws -> PreparedTracks {
        if let prepared = TrackRenderer.prepared(in: folder) { return prepared }
        guard let data = try? Data(contentsOf: folder.appending(path: "meeting.json")) else { throw RunError.noMeetingFile }
        let file = try MeetingFile.decoder.decode(MeetingFile.self, from: data)
        return try TrackRenderer.render(folder: folder, file: file)
    }

    func transcribe(_ track: Speaker, url: URL) async throws {
        let samples = try Self.samples(of: url, name: track.rawValue)
        let duration = Double(samples.count) / TrackRenderer.sampleRate
        let regions = try await speech(track, samples: samples)
        let chunks = ChunkPlan.chunks(regions, duration: duration)
        let output = results.appending(path: "\(track.rawValue).jsonl")
        let done = Set(ChunkResultFile.read(output).map(\.chunk))
        let remaining = chunks.filter { !done.contains($0) }
        var count = chunks.count - remaining.count
        emit(.progress(track: track, done: count, total: chunks.count))

        for start in stride(from: 0, to: remaining.count, by: batchSize) {
            let batch = Array(remaining[start..<min(start + batchSize, remaining.count)])
            let clips = batch.map { chunk in
                let from = max(0, Int(chunk.start * TrackRenderer.sampleRate))
                let to = min(samples.count, Int(chunk.end * TrackRenderer.sampleRate))
                return from < to ? Array(samples[from..<to]) : []
            }
            let segments = try await engine.transcribe(clips, language: request.language)
            for (chunk, found) in zip(batch, segments) {
                let result = ChunkResult(track: track, chunk: chunk, segments: found.map { segment in
                    EngineSegment(
                        start: chunk.start + segment.start, end: chunk.start + segment.end, text: segment.text,
                        avgLogprob: segment.avgLogprob, compressionRatio: segment.compressionRatio, noSpeechProb: segment.noSpeechProb
                    )
                })
                try ChunkResultFile.append(result, to: output)
                emit(.chunk(result))
                count += 1
                emit(.progress(track: track, done: count, total: chunks.count))
            }
        }
    }

    /// Silero's regions, kept so that a resumed run cuts the same chunks.
    func speech(_ track: Speaker, samples: [Float]) async throws -> [SpeechRegion] {
        let cache = results.appending(path: "regions-\(track.rawValue).json")
        if let data = try? Data(contentsOf: cache), let regions = try? JSONDecoder().decode([SpeechRegion].self, from: data) {
            return regions
        }
        let regions = try await detector.regions(samples: samples)
        try JSONEncoder().encode(regions).write(to: cache, options: .atomic)
        return regions
    }

    /// The whole track, 16 kHz mono Float32.
    static func samples(of url: URL, name: String) throws -> [Float] {
        guard let file = try? AVAudioFile(forReading: url),
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: TrackRenderer.sampleRate, channels: 1, interleaved: false),
              file.processingFormat.sampleRate == TrackRenderer.sampleRate,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))
        else { throw RunError.unreadableTrack(name) }
        if file.length > 0 {
            do { try file.read(into: buffer) } catch { throw RunError.unreadableTrack(name) }
        }
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }
}
