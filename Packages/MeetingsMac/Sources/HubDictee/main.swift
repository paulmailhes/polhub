import AVFoundation
import Compute
import Dictation
import Foundation
import Transcription

/// `hub-dictee`: the Dictée's ear (20/11). Launched by the app while the Dictée is installed, it keeps Whisper loaded,
/// listens to the microphone on « commencer », says the words as they come, and the whole text on « finir ». One line of
/// JSON per order on its input, per news on its output (`DictationWire`). It dies with the app that launched it.
setenv("HF_HUB_OFFLINE", "1", 1)
guard getppid() != 1 else { exit(0) }
let parentWatch = DispatchSource.makeProcessSource(identifier: getppid(), eventMask: .exit, queue: .global())
parentWatch.setEventHandler { exit(0) }
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
    private var language: String?
    private var prompt = ""
    private var busy = false
    private var lastLevel = Date.distantPast

    init(engine: WhisperEngine) {
        self.engine = engine
    }

    func begin(language: String?, prompt: String) {
        samples = []
        self.language = language
        self.prompt = prompt
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
        let text = (try? await engine.dictate(heard, language: language, prompt: prompt, long: false)) ?? ""
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
        do {
            let text = try await engine.dictate(heard, language: language, prompt: prompt, long: heard.count > 16_000 * 28)
            emit(.final(text: text, seconds: Double(heard.count) / 16_000))
        } catch {
            emit(.failed("Whisper n'a pas pu écrire ce qui a été dit (\(error))."))
        }
    }

    /// A file, for the measures.
    func file(_ path: String, language: String?, prompt: String) async {
        do {
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
            guard let read = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { return }
            try file.read(into: read)
            let heard = convert(read)
            let started = Date()
            let text = try await engine.dictate(heard, language: language, prompt: prompt, long: heard.count > 16_000 * 28)
            emit(.final(text: text, seconds: Date().timeIntervalSince(started)))
        } catch {
            emit(.failed("Le fichier n'a pas pu être lu (\(error))."))
        }
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
let microphone = AVAudioEngine()
nonisolated(unsafe) var partials: Task<Void, Never>?
emit(.ready)

func startListening() {
    let input = microphone.inputNode
    let format = input.outputFormat(forBus: 0)
    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 4_096, format: format) { buffer, _ in
        let chunk = convert(buffer)
        Task { await ear.append(chunk) }
    }
    do {
        try microphone.start()
    } catch {
        emit(.failed("Le micro ne s'ouvre pas (\(error))."))
        return
    }
    partials = Task {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(700))
            await ear.partial()
        }
    }
}

func stopListening() {
    partials?.cancel()
    partials = nil
    microphone.inputNode.removeTap(onBus: 0)
    microphone.stop()
}

// The orders, read on a thread of their own: reading waits.
while let line = readLine(strippingNewline: true) {
    guard let command = try? DictationWire.read(DictationCommand.self, line) else { continue }
    switch command {
    case .start(let language, let prompt):
        await ear.begin(language: language, prompt: prompt)
        startListening()
    case .stop:
        stopListening()
        await ear.finish(cancelled: false)
    case .cancel:
        stopListening()
        await ear.finish(cancelled: true)
    case .file(let path, let language, let prompt):
        await ear.file(path, language: language, prompt: prompt)
    }
}
exit(0)
