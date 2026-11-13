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
    private let kit: WhisperKit

    public init(locations: ModelLocations) async throws {
        let config = WhisperKitConfig(
            modelFolder: locations.whisperFolder.path(percentEncoded: false),
            tokenizerFolder: locations.tokenizerFolder,
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

    public enum EngineError: Error, CustomStringConvertible {
        case clipFailed(Int)

        public var description: String {
            switch self {
            case .clipFailed(let index): "Le moteur n'a pas pu transcrire le morceau \(index + 1) du lot."
            }
        }
    }
}
