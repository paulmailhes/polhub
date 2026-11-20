import AudioCapture
import AudioToolbox
import AVFoundation
import Compute
import Dictation
import Foundation
import Transcription

/// `hub-dictee`: the Dictée's ear (20/11). Launched by the app while the Dictée is installed, it keeps Whisper loaded,
/// listens to the microphone on « commencer », says the words as they come, and the whole text on « finir ». One line of
/// JSON per order on its input, per news on its output (`DictationWire`). It dies with the app that launched it.
/// 20/11 in the evening: the microphone Paul chose, the sound kept, the paragraphs after the long pauses, the files.
setenv("HF_HUB_OFFLINE", "1", 1)
guard getppid() != 1 else { exit(0) }
let parentWatch = DispatchSource.makeProcessSource(identifier: getppid(), eventMask: .exit, queue: .global())
// Sendable: run on a queue of its own, never the main actor's (a closure of the main actor stopped hub-dictee with a
// trap instead of leaving, 20/11).
parentWatch.setEventHandler { @Sendable in exit(0) }
parentWatch.resume()

let output = FileHandle.standardOutput
let outputLock = NSLock()
@Sendable func emit(_ event: DictationEvent) {
    guard let line = try? DictationWire.line(event) else { return }
    outputLock.withLock { output.write(Data((line + "\n").utf8)) }
}

let locations = ModelLocations.standard
let missing = locations.missing()
guard missing.isEmpty else {
    emit(.failed("Modèles absents : " + missing.joined(separator: ", ") + "."))
    exit(1)
}

/// 16 kHz mono, as Whisper hears.
let whisperFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

/// Whisper, one call at a time: a partial in flight finishes before the final starts.
actor Ear {
    let engine: WhisperEngine
    private var samples: [Float] = []
    private var listening = false
    private var options = DictationListening(language: "fr", prompt: "")
    private var busy = false
    private var lastLevel = Date.distantPast

    init(engine: WhisperEngine) {
        self.engine = engine
    }

    func begin(_ options: DictationListening) {
        samples = []
        self.options = options
        listening = true
    }

    func append(_ chunk: [Float]) {
        guard listening else { return }
        samples += chunk
        // The level for the waveform, twenty times a second at most.
        guard Date().timeIntervalSince(lastLevel) > 0.05, !chunk.isEmpty else { return }
        lastLevel = Date()
        let rms = (chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count)).squareRoot()
        emit(.level(Double(min(1, rms * 8))))
    }

    /// The words said so far, on the last 28 s, when Whisper is free.
    func partial() async {
        guard listening, !busy, samples.count > 8_000 else { return }
        busy = true
        let heard = Array(samples.suffix(16_000 * 28))
        let text = (try? await engine.dictate(heard, language: options.language, prompt: options.prompt, long: false)) ?? ""
        busy = false
        if listening, !text.isEmpty { emit(.partial(text)) }
    }

    func finish(cancelled: Bool) async {
        listening = false
        let heard = samples
        samples = []
        guard !cancelled else { return }
        while busy { try? await Task.sleep(for: .milliseconds(20)) }
        busy = true
        defer { busy = false }
        guard heard.count > 4_000 else {
            emit(.final(text: "", seconds: Double(heard.count) / 16_000))
            return
        }
        if let path = options.keepSoundAt { keep(heard, at: path) }
        do {
            emit(.final(text: try await write(heard, options), seconds: Double(heard.count) / 16_000))
        } catch {
            emit(.failed("Whisper n'a pas pu écrire ce qui a été dit (\(error))."))
        }
    }

    /// A file of sound or a video, or a kept sound written again.
    func file(id: String, path: String, options: DictationListening) async {
        while busy { try? await Task.sleep(for: .milliseconds(20)) }
        busy = true
        defer { busy = false }
        do {
            let heard = try await read(path)
            guard heard.count > 4_000 else {
                emit(.fileFailed(id: id, reason: "Il n'y a presque rien à entendre dans ce fichier."))
                return
            }
            emit(.transcribed(id: id, text: try await write(heard, options), seconds: Double(heard.count) / 16_000))
        } catch {
            emit(.fileFailed(id: id, reason: "Ce fichier n'a pas pu être lu : hub lit les sons et les vidéos que lit QuickTime."))
        }
    }

    /// The whole text; with paragraphs after the long pauses when Paul wants them, and when there are some.
    private func write(_ heard: [Float], _ options: DictationListening) async throws -> String {
        let long = heard.count > 16_000 * 28
        guard let pause = options.paragraphPause else {
            return try await engine.dictate(heard, language: options.language, prompt: options.prompt, long: long)
        }
        let breaks = DictationParagraphs.pauses(heard, longerThan: pause)
        guard !breaks.isEmpty else {
            return try await engine.dictate(heard, language: options.language, prompt: options.prompt, long: long)
        }
        let pieces = try await engine.dictatePieces(heard, language: options.language, prompt: options.prompt, long: long)
        return DictationParagraphs.join(pieces.map { DictationParagraphs.Piece(text: $0.text, start: $0.start, end: $0.end) }, breaks: breaks)
    }
}

/// Any sound, as 16 kHz mono.
func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
    guard let converter = AVAudioConverter(from: buffer.format, to: whisperFormat) else { return [] }
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 16_000 / buffer.format.sampleRate) + 1_024
    guard let out = AVAudioPCMBuffer(pcmFormat: whisperFormat, frameCapacity: capacity) else { return [] }
    // The whole buffer once, then the end of the stream: the converter gives back what it still holds.
    nonisolated(unsafe) var given = false
    var error: NSError?
    converter.convert(to: out, error: &error) { _, status in
        if given { status.pointee = .endOfStream; return nil }
        given = true
        status.pointee = .haveData
        return buffer
    }
    guard let channel = out.floatChannelData?[0] else { return [] }
    return Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
}

/// The sound of a file or of a video, as 16 kHz mono. AVAudioFile reads them all on macOS 27, videos and Opus voice
/// messages included (measured 20/11 on aiff, m4a, mp3, ogg, opus, mp4, mov); read a minute at a time.
func read(_ path: String) async throws -> [Float] {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let slice = AVAudioFrameCount(file.processingFormat.sampleRate * 60)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: slice) else { throw CocoaError(.fileReadCorruptFile) }
    var samples: [Float] = []
    while file.framePosition < file.length {
        try file.read(into: buffer, frameCount: slice)
        guard buffer.frameLength > 0 else { break }
        samples += convert(buffer)
    }
    return samples
}

/// The sound of a dictation, in AAC (about 4 kB a second), where the app asked.
func keep(_ samples: [Float], at path: String) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
                                   AVEncoderBitRateKey: 32_000]
    guard let file = try? AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false),
          let buffer = AVAudioPCMBuffer(pcmFormat: whisperFormat, frameCapacity: AVAudioFrameCount(samples.count)),
          let channel = buffer.floatChannelData?[0] else { return }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
    try? file.write(from: buffer)
}

let engine: WhisperEngine
do {
    engine = try await WhisperEngine(locations: locations)
} catch {
    emit(.failed("Whisper ne se charge pas (\(error))."))
    exit(1)
}
// A first second of silence: the model is compiled and warm before the first press.
_ = try? await engine.dictate([Float](repeating: 0, count: 16_000), language: "fr", prompt: "", long: false)
let ear = Ear(engine: engine)
emit(.ready)

/// The microphone, read as the meeting recorder reads it (20/11 in the evening): straight from Core Audio, at the format
/// the device really has. AVAudioEngine kept an old format for Bluetooth earphones (48 kHz announced, 24 kHz real) and
/// stopped hub-dictee with a « format mismatch » (0.63.0 and 0.63.1, measured). The sound goes through a lock-free ring,
/// then is made 16 kHz mono for Whisper, twenty times a second.
final class Listening: @unchecked Sendable {
    private final class Slot: @unchecked Sendable {
        var ring: SPSCRingBuffer?
    }

    let stream: HALInputStream
    private let ring: SPSCRingBuffer
    private let channels: Int
    private let deviceFormat: AVAudioFormat
    private let converter: AVAudioConverter
    private var scratch: [Float]
    private static let slice = 4_096

    init(device: AudioObjectID) throws {
        let slot = Slot()
        stream = try HALInputStream(deviceID: device) { samples, frames, _ in
            guard let base = samples.baseAddress else { return }
            slot.ring?.write(base, frames: frames)
        }
        channels = max(1, stream.format.channels)
        ring = SPSCRingBuffer(capacityFrames: Int(stream.format.sampleRate) * 8, channels: channels)
        slot.ring = ring
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: stream.format.sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: whisperFormat) else { throw CocoaError(.featureUnsupported) }
        deviceFormat = format
        self.converter = converter
        scratch = [Float](repeating: 0, count: Self.slice * channels)
    }

    /// What the ring holds, as 16 kHz mono. One reader at a time.
    func drain() -> [Float] {
        var heard: [Float] = []
        while true {
            let frames = scratch.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, maxFrames: Self.slice) }
            guard frames > 0, let mono = AVAudioPCMBuffer(pcmFormat: deviceFormat, frameCapacity: AVAudioFrameCount(frames)),
                  let channel = mono.floatChannelData?[0] else { break }
            mono.frameLength = AVAudioFrameCount(frames)
            for frame in 0..<frames {
                var sum: Float = 0
                for index in 0..<channels { sum += scratch[frame * channels + index] }
                channel[frame] = sum / Float(channels)
            }
            heard += resample(mono)
        }
        return heard
    }

    /// One converter for the whole dictation: no click between two slices.
    private func resample(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 16_000 / deviceFormat.sampleRate) + 256
        guard let out = AVAudioPCMBuffer(pcmFormat: whisperFormat, frameCapacity: capacity) else { return [] }
        nonisolated(unsafe) var given = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true
            status.pointee = .haveData
            return buffer
        }
        guard let channel = out.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
    }
}

nonisolated(unsafe) var listening: Listening?
nonisolated(unsafe) var pump: Task<Void, Never>?
nonisolated(unsafe) var partials: Task<Void, Never>?

/// The microphone Paul chose when it is connected, else the system's.
func startListening(_ options: DictationListening) async {
    guard let device = options.microphone.flatMap(Devices.device(uid:)) ?? Devices.defaultInput() else {
        emit(.failed("Aucun micro n'est branché."))
        return
    }
    do {
        let opened = try Listening(device: device)
        // Core Audio may block: never on the main thread, which waits on the orders.
        try await Task.detached { try opened.stream.start() }.value
        listening = opened
    } catch {
        emit(.failed("Le micro ne s'ouvre pas (\(error))."))
        return
    }
    pump = Task.detached {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
            guard let heard = listening?.drain(), !heard.isEmpty else { continue }
            await ear.append(heard)
        }
    }
    partials = Task.detached {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(700))
            await ear.partial()
        }
    }
}

/// The microphone closed; what it still held joins the dictation.
func stopListening() async {
    partials?.cancel()
    partials = nil
    pump?.cancel()
    await pump?.value
    pump = nil
    guard let closing = listening else { return }
    listening = nil
    await Task.detached { closing.stream.stop() }.value
    let rest = closing.drain()
    if !rest.isEmpty { await ear.append(rest) }
}

// The orders, read on a thread of their own: reading waits. A file is written aside: the key stays free meanwhile.
while let line = readLine(strippingNewline: true) {
    guard let command = try? DictationWire.read(DictationCommand.self, line) else { continue }
    switch command {
    case .start(let options):
        await ear.begin(options)
        await startListening(options)
    case .stop:
        await stopListening()
        await ear.finish(cancelled: false)
    case .cancel:
        await stopListening()
        await ear.finish(cancelled: true)
    case .file(let id, let path, let options):
        // Detached: the main thread waits on the next order, a task of its own would never start.
        Task.detached { await ear.file(id: id, path: path, options: options) }
    }
}
exit(0)
