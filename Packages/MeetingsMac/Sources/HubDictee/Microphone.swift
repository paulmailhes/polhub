import AudioCapture
import AVFoundation
import CoreAudio
import Foundation

/// Where a dictation's sound comes from: a microphone, or — for the measures — a file played at the speed of a voice.
protocol SoundSource: AnyObject, Sendable {
    /// Opens the source. Core Audio may block: never on the main thread.
    func start() throws
    /// What came since the last call, as 16 kHz mono. One reader at a time.
    func drain() -> [Float]
    func stop()
}

/// The microphone, read as the meeting recorder reads it (20/11 in the evening): straight from Core Audio, at the format
/// the device really has. AVAudioEngine kept an old format for Bluetooth earphones (48 kHz announced, 24 kHz real) and
/// stopped hub-dictee with a « format mismatch » (0.63.0 and 0.63.1, measured). The sound goes through a lock-free ring,
/// then is made 16 kHz mono for Whisper, twenty times a second.
final class Microphone: SoundSource, @unchecked Sendable {
    private final class Slot: @unchecked Sendable {
        var ring: SPSCRingBuffer?
    }

    private let stream: HALInputStream
    private let ring: SPSCRingBuffer
    private let channels: Int
    private let deviceFormat: AVAudioFormat
    private let converter: AVAudioConverter
    private var scratch: [Float]
    private static let slice = 4_096

    /// The first of Paul's microphones that is connected, else the system's; nil when the Mac has none.
    static func choose(_ preferred: [String]) -> AudioObjectID? {
        preferred.lazy.compactMap(Devices.device(uid:)).first ?? Devices.defaultInput()
    }

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

    func start() throws {
        try stream.start()
    }

    func stop() {
        stream.stop()
    }

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

/// A file played as if it were said into the microphone (the measures and the tests, never the app): its sound comes
/// at the speed of a voice, so the words in direct and the final text are timed as they would be.
final class PlayedFile: SoundSource, @unchecked Sendable {
    private let samples: [Float]
    private var startedAt: ContinuousClock.Instant?
    private var cursor = 0

    init(path: String) throws {
        samples = try read(path)
    }

    func start() {
        startedAt = .now
    }

    func stop() {}

    /// After the file's end, silence goes on, as a microphone goes on after the last word.
    func drain() -> [Float] {
        guard let startedAt else { return [] }
        let elapsed = ContinuousClock.now - startedAt
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let due = Int(seconds * 16_000)
        guard due > cursor else { return [] }
        defer { cursor = due }
        let said = cursor < samples.count ? Array(samples[cursor..<min(due, samples.count)]) : []
        return said + [Float](repeating: 0, count: (due - cursor) - said.count)
    }
}
