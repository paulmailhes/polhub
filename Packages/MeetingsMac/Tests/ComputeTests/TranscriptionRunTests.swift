import AVFoundation
import Domain
import Foundation
import Testing
@testable import Compute
import Recording
import Transcription

/// Regions given by track, whatever the samples.
struct FakeDetector: SpeechDetecting {
    let regions: [Int: [SpeechRegion]]   // by sample count, to tell the tracks apart

    func regions(samples: [Float]) async throws -> [SpeechRegion] {
        regions[samples.count] ?? []
    }
}

/// One segment per clip, from 1 s to 2 s of the clip; counts the clips it was given.
final class FakeEngine: TranscribingEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var given = 0
    var clipsGiven: Int { lock.withLock { given } }

    func transcribe(_ clips: [[Float]], language: String?) async throws -> [[EngineSegment]] {
        lock.withLock { given += clips.count }
        return clips.map { _ in [EngineSegment(start: 1, end: 2, text: "Bonjour.", avgLogprob: -0.2, compressionRatio: 1.1, noSpeechProb: 0.1)] }
    }
}

final class Messages: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [CalculMessage] = []
    var all: [CalculMessage] { lock.withLock { list } }
    func add(_ message: CalculMessage) { lock.withLock { list.append(message) } }
}

@Suite struct TranscriptionRunTests {
    static let seconds = 60

    /// A meeting folder whose archive already exists: `autres` 60 s, `moi` 60 s unless `withMoi` is false.
    func meetingFolder(withMoi: Bool = true) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "calcul \(UUID().uuidString)", directoryHint: .isDirectory)
        let pistes = folder.appending(path: "pistes", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: pistes, withIntermediateDirectories: true)
        for (name, seconds) in [("autres", Self.seconds)] + (withMoi ? [("moi", Self.seconds - 1)] : []) {
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatAppleLossless, AVSampleRateKey: 16_000.0, AVNumberOfChannelsKey: 1, AVEncoderBitDepthHintKey: 16]
            let file = try AVAudioFile(forWriting: pistes.appending(path: "\(name).caf"), settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(16_000 * seconds))!
            buffer.frameLength = buffer.frameCapacity
            for index in 0..<Int(buffer.frameLength) { buffer.floatChannelData![0][index] = 0.05 }
            try file.write(from: buffer)
        }
        return folder
    }

    /// `autres` (60 s): speech at 5–10 s and 40–45 s → two chunks. `moi` (59 s): speech at 20–22 s → one.
    let detector = FakeDetector(regions: [
        16_000 * 60: [SpeechRegion(start: 5, end: 10), SpeechRegion(start: 40, end: 45)],
        16_000 * 59: [SpeechRegion(start: 20, end: 22)],
    ])

    func lines(_ folder: URL, _ track: Speaker) throws -> [ChunkResult] {
        let url = folder.appending(path: "transcription/\(track.rawValue).jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return try text.split(separator: "\n").map { try JSONDecoder().decode(ChunkResult.self, from: Data($0.utf8)) }
    }

    @Test func aRunWritesOneLinePerChunkAndFinishes() async throws {
        let folder = try meetingFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let messages = Messages()
        try await TranscriptionRun(request: CalculRequest(folder: folder.path(percentEncoded: false), language: "fr"), detector: detector, engine: FakeEngine(), emit: messages.add).run()
        #expect(try lines(folder, .autres).map(\.chunk.index) == [0, 1])
        #expect(try lines(folder, .moi).map(\.chunk.index) == [0])
        #expect(messages.all.last == .finished)
        #expect(messages.all.contains(.progress(track: .autres, done: 2, total: 2)))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "transcription/regions-autres.json").path(percentEncoded: false)))
    }

    @Test func aSecondRunSkipsChunksAlreadyDone() async throws {
        let folder = try meetingFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try await TranscriptionRun(request: CalculRequest(folder: folder.path(percentEncoded: false), language: "fr"), detector: detector, engine: FakeEngine(), emit: { _ in }).run()
        // The process was stopped before the last chunk of `autres` was written.
        let url = folder.appending(path: "transcription/autres.jsonl")
        let first = try #require(try String(contentsOf: url, encoding: .utf8).split(separator: "\n").first)
        try (first + "\n").write(to: url, atomically: true, encoding: .utf8)

        let engine = FakeEngine()
        try await TranscriptionRun(request: CalculRequest(folder: folder.path(percentEncoded: false), language: "fr"), detector: detector, engine: engine, emit: { _ in }).run()
        #expect(engine.clipsGiven == 1)
        #expect(try lines(folder, .autres).map(\.chunk.index) == [0, 1])
    }

    @Test func aSilentMoiTrackGivesNoChunkAndNoFailure() async throws {
        let folder = try meetingFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let messages = Messages()
        let silentMoi = FakeDetector(regions: [16_000 * 60: [SpeechRegion(start: 5, end: 10)]])
        try await TranscriptionRun(request: CalculRequest(folder: folder.path(percentEncoded: false), language: "fr"), detector: silentMoi, engine: FakeEngine(), emit: messages.add).run()
        #expect(try lines(folder, .moi).isEmpty)
        #expect(messages.all.last == .finished)
    }

    @Test func engineTimesBecomeTrackTimes() async throws {
        let folder = try meetingFolder(withMoi: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await TranscriptionRun(request: CalculRequest(folder: folder.path(percentEncoded: false), language: "fr"), detector: detector, engine: FakeEngine(), emit: { _ in }).run()
        let first = try #require(try lines(folder, .autres).first)
        // The chunk starts at 4.5 s (0.5 s of margin); the engine said 1–2 s into the chunk.
        #expect(first.chunk.start == 4.5)
        #expect(first.segments.first?.start == 5.5 && first.segments.first?.end == 6.5)
    }

    @Test func missingRawAudioFailsWithAReadableMessage() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "calcul \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try await TranscriptionRun(request: CalculRequest(folder: folder.path(percentEncoded: false), language: "fr"), detector: detector, engine: FakeEngine(), emit: { _ in }).run()
            Issue.record("La transcription aurait dû échouer.")
        } catch {
            #expect("\(error)".contains("meeting.json"))
        }
    }

    // Revue finale, Important 4 : deux calculs ne travaillent jamais sur la même réunion.
    @Test func aSecondRunOnTheSameMeetingIsRefused() async throws {
        let folder = try meetingFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let lockURL = folder.appending(path: "transcription/.lock")
        try FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(lockURL.path(percentEncoded: false), O_CREAT | O_RDWR, 0o644)
        defer { close(fd) }
        #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
        let engine = FakeEngine()
        do {
            try await TranscriptionRun(request: CalculRequest(folder: folder.path(percentEncoded: false), language: "fr"), detector: detector, engine: engine, emit: { _ in }).run()
            Issue.record("Le second calcul aurait dû être refusé.")
        } catch {
            #expect("\(error)".contains("déjà"))
        }
        #expect(engine.clipsGiven == 0)
    }

    @Test func missingModelsAreNamed() {
        let locations = ModelLocations(root: FileManager.default.temporaryDirectory.appending(path: "nulle-part-\(UUID().uuidString)"))
        #expect(locations.missing().count == 3)
    }
}

@Suite struct ModelLocationsTests {
    @Test func modelsInAFolderWithASpaceAreFound() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Application Support \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let locations = ModelLocations(root: root)
        for directory in [locations.whisperFolder.appending(path: "AudioEncoder.mlmodelc"), locations.sileroModel,
                          locations.tokenizerFolder.appending(path: "models/openai/whisper-large-v3")] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        FileManager.default.createFile(atPath: locations.tokenizerFolder.appending(path: "models/openai/whisper-large-v3/tokenizer.json").path(percentEncoded: false), contents: Data("{}".utf8))
        #expect(locations.missing().isEmpty)
    }
}
