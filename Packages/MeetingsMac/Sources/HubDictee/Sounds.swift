import AVFoundation
import Foundation

/// 16 kHz mono, as Whisper hears.
let whisperFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

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
func read(_ path: String) throws -> [Float] {
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
