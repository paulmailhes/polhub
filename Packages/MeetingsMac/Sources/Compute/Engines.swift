import CoreML
import FluidAudio
import Foundation
import Transcription
import WhisperKit

/// Finds the speech on a track (16 kHz mono).
public protocol SpeechDetecting: Sendable {
    func regions(samples: [Float]) async throws -> [SpeechRegion]
}

/// Transcribes clips (16 kHz mono); times are seconds from each clip's start.
public protocol TranscribingEngine: Sendable {
    func transcribe(_ clips: [[Float]], language: String?) async throws -> [[EngineSegment]]
}

/// Silero through FluidAudio, with the model loaded from our folder: nothing is downloaded.
public struct SileroDetector: SpeechDetecting {
    /// FluidAudio's own default (0.85) misses a headset voice; 0.5 is Silero's (entry measure of step 2).
    public static let threshold: Float = 0.5
    private let manager: VadManager

    public init(model: URL) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        let loaded = try MLModel(contentsOf: model, configuration: configuration)
        manager = VadManager(config: VadConfig(defaultThreshold: Self.threshold), vadModel: loaded)
    }

    public func regions(samples: [Float]) async throws -> [SpeechRegion] {
        guard !samples.isEmpty else { return [] }
        let segments = try await manager.segmentSpeech(samples, config: VadSegmentationConfig(maxSpeechDuration: 28, speechPadding: 0))
        return segments.map { SpeechRegion(start: $0.startTime, end: $0.endTime) }
    }
}

/// WhisperKit, large-v3-turbo, offline: no download, no prompt, the language imposed unless `nil`.
public final class WhisperEngine: TranscribingEngine, @unchecked Sendable {
    /// Measured on this M3 Max: 16 workers, 23 times real time on a meeting track.
    public static let workers = 16
    /// The shortest sound a dictation gives to Whisper, in samples (1,25 s).
    static let shortest = 20_000
    private let kit: WhisperKit

    /// `encoderOnGPU`: the Dictée's choice (21/11). Measured on the M3 Max: a call takes 0,75 s instead of 1,4 s, for about
    /// 570 MB more memory; the meetings keep the Neural Engine, which their sixteen workers share better.
    public init(locations: ModelLocations, encoderOnGPU: Bool = false) async throws {
        let config = WhisperKitConfig(
            modelFolder: locations.whisperFolder.path(percentEncoded: false),
            tokenizerFolder: locations.tokenizerFolder,
            computeOptions: encoderOnGPU ? ModelComputeOptions(audioEncoderCompute: .cpuAndGPU) : nil,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false
        )
        kit = try await WhisperKit(config)
    }

    public func transcribe(_ clips: [[Float]], language: String?) async throws -> [[EngineSegment]] {
        let options = DecodingOptions(
            language: language,
            usePrefillPrompt: language != nil,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            promptTokens: nil,
            concurrentWorkerCount: Self.workers
        )
        let results = await kit.transcribe(audioArrays: clips, decodeOptions: options)
        return try results.enumerated().map { index, result in
            guard let result else { throw EngineError.clipFailed(index) }
            return result.flatMap(\.segments).map { segment in
                EngineSegment(
                    start: Double(segment.start), end: Double(segment.end), text: segment.text,
                    avgLogprob: Double(segment.avgLogprob), compressionRatio: Double(segment.compressionRatio),
                    noSpeechProb: Double(segment.noSpeechProb)
                )
            }
        }
    }

    /// The Dictée (20/11): one recording, its text. The memory's words go as Whisper's prompt; a recording longer than
    /// one window is cut by WhisperKit's own detector.
    /// `onText` (21/11): what is written so far, window by window, as Whisper writes; false stops the writing.
    public func dictate(_ samples: [Float], language: String?, prompt: String, long: Bool,
                        onText: (@Sendable (_ window: Int, _ text: String) -> Bool)? = nil) async throws -> String {
        try await dictation(samples, language: language, prompt: prompt, long: long, timed: false, onText: onText)
            .map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The same, in pieces with their times (20/11 in the evening): the paragraphs start after the long pauses.
    public func dictatePieces(_ samples: [Float], language: String?, prompt: String, long: Bool,
                              onText: (@Sendable (_ window: Int, _ text: String) -> Bool)? = nil) async throws -> [EngineSegment] {
        try await dictation(samples, language: language, prompt: prompt, long: long, timed: true, onText: onText)
    }

    private func dictation(_ samples: [Float], language: String?, prompt: String, long: Bool, timed: Bool,
                           onText: (@Sendable (_ window: Int, _ text: String) -> Bool)?) async throws -> [EngineSegment] {
        var tokens: [Int]?
        if !prompt.isEmpty, let tokenizer = kit.tokenizer {
            let begin = tokenizer.specialTokens.specialTokenBegin
            tokens = Array(tokenizer.encode(text: " " + prompt).filter { $0 < begin }.prefix(200))
        }
        let options = DecodingOptions(
            language: language,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: !timed,
            promptTokens: tokens,
            // Whisper's own « this is silence » is off: the Dictée only asks when a voice was heard, and that guess threw
            // away the first words of a sentence (measured 21/11: nothing on the screen before 2,8 s).
            noSpeechThreshold: nil,
            concurrentWorkerCount: 4,
            chunkingStrategy: long ? .vad : ChunkingStrategy.none
        )
        // WhisperKit writes nothing at all for a second of sound or less (measured 21/11: « Oui », « Merci » dictated alone
        // came back empty, and so did the first words of a sentence): a short sound is followed by silence up to 1,25 s.
        let samples = samples.count < Self.shortest ? samples + [Float](repeating: 0, count: Self.shortest - samples.count) : samples
        var callback: TranscriptionCallback?
        if let onText {
            callback = { (progress: TranscriptionProgress) -> Bool? in
                onText(progress.windowId, progress.text) ? nil : false
            }
        }
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options, callback: callback)
        guard timed else {
            return results.map { EngineSegment(start: 0, end: 0, text: $0.text, avgLogprob: 0, compressionRatio: 0, noSpeechProb: 0) }
        }
        return results.flatMap(\.segments).map { segment in
            EngineSegment(start: Double(segment.start), end: Double(segment.end), text: segment.text,
                          avgLogprob: Double(segment.avgLogprob), compressionRatio: Double(segment.compressionRatio),
                          noSpeechProb: Double(segment.noSpeechProb))
        }
    }

    public enum EngineError: Error, CustomStringConvertible {
        case clipFailed(Int)

        public var description: String {
            switch self {
            case .clipFailed(let index): "Le moteur n'a pas pu transcrire le morceau \(index + 1) du lot."
            }
        }
    }
}
