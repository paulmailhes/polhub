import AVFoundation
import Foundation

/// The archive of a meeting: one file per track, 16 kHz mono, lossless (Apple Lossless), on the meeting's
/// time line: second t of the file is second t of the meeting. Silence where nothing was captured.
public struct PreparedTracks: Equatable, Sendable {
    /// Absent when no microphone was recorded.
    public let moi: URL?
    public let autres: URL
    public let seconds: Double

    public init(moi: URL?, autres: URL, seconds: Double) {
        self.moi = moi
        self.autres = autres
        self.seconds = seconds
    }
}

public enum TrackRenderer {
    public static let sampleRate = 16_000.0
    public static let folderName = "pistes"

    public enum RenderError: Error, CustomStringConvertible {
        case noAudio
        case unreadable(String)

        public var description: String {
            switch self {
            case .noAudio: "L'audio de la réunion est introuvable."
            case .unreadable(let name): "Un morceau d'audio est illisible : \(name)."
            }
        }
    }

    /// Writes `pistes/moi.caf` and `pistes/autres.caf`, from the origin to the end of the meeting (the ten
    /// minutes of safety are left out). Each file is written under another name, then renamed.
    public static func render(
        folder: URL, file: MeetingFile, timeline: MeetingTimeline? = nil,
        segmentSeconds: Double = MeetingRecorder.segmentSeconds
    ) throws -> PreparedTracks {
        let timeline = try timeline ?? MeetingTimeline.read(folder.appending(path: "timeline.jsonl"))
        let pieces = PlaybackPlan.pieces(
            folder: folder, timeline: timeline, moiSpans: file.moiSpans, originNanos: file.originNanos,
            segmentSeconds: segmentSeconds, untilNanos: file.endNanos, preferArchive: false
        )
        guard !pieces.isEmpty else { throw RenderError.noAudio }
        let seconds = file.endNanos.map { (Double($0) - Double(file.originNanos)) / 1e9 }
            ?? pieces.map { $0.atSeconds + $0.durationSeconds }.max() ?? 0

        let directory = folder.appending(path: folderName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // `autres.caf` is what says the archive exists: it is renamed last.
        let moiPieces = pieces.filter { $0.track == "moi" }
        let moiPartial = moiPieces.isEmpty ? nil : try writePartial(moiPieces, seconds: seconds, for: directory.appending(path: "moi.caf"))
        let autresPartial = try writePartial(pieces.filter { $0.track == "autres" }, seconds: seconds, for: directory.appending(path: "autres.caf"))
        let moi = try moiPartial.map { try rename($0, to: directory.appending(path: "moi.caf")) }
        let autres = try rename(autresPartial, to: directory.appending(path: "autres.caf"))
        return PreparedTracks(moi: moi, autres: autres, seconds: seconds)
    }

    /// The archive, if it was made.
    public static func prepared(in folder: URL) -> PreparedTracks? {
        let directory = folder.appending(path: folderName, directoryHint: .isDirectory)
        let autres = directory.appending(path: "autres.caf")
        guard let seconds = duration(of: autres) else { return nil }
        let moi = directory.appending(path: "moi.caf")
        return PreparedTracks(moi: FileManager.default.fileExists(atPath: moi.path(percentEncoded: false)) ? moi : nil, autres: autres, seconds: seconds)
    }

    /// Every file of the archive lasts the expected time, to one second.
    public static func verify(_ tracks: PreparedTracks, expectedSeconds: Double) -> Bool {
        [tracks.moi, tracks.autres].compactMap { $0 }.allSatisfy { url in
            guard let seconds = duration(of: url) else { return false }
            return abs(seconds - expectedSeconds) <= 1
        }
    }

    /// Whether the raw audio may go: the archive lasts the meeting, every raw file of `autres` was placed
    /// in it, every microphone run on disk is known to the time line, and a chosen microphone has its track
    /// (review, Important 3: the length alone proved nothing, since the archive is padded with silence).
    public static func rawAudioIsArchived(
        folder: URL, file: MeetingFile, timeline: MeetingTimeline, segmentSeconds: Double = MeetingRecorder.segmentSeconds
    ) -> Bool {
        guard let archive = prepared(in: folder), let endNanos = file.endNanos,
              verify(archive, expectedSeconds: (Double(endNanos) - Double(file.originNanos)) / 1e9)
        else { return false }
        if !file.moiSpans.isEmpty && archive.moi == nil { return false }
        let pieces = PlaybackPlan.pieces(
            folder: folder, timeline: timeline, moiSpans: file.moiSpans, originNanos: file.originNanos,
            segmentSeconds: segmentSeconds, untilNanos: nil, preferArchive: false
        )
        func path(_ url: URL) -> String { url.resolvingSymlinksInPath().path(percentEncoded: false) }
        let placed = Set(pieces.filter { $0.track == "autres" }.map { path($0.url) })
        let raw = folder.appending(path: "audio", directoryHint: .isDirectory)
        let manager = FileManager.default
        let autres = (manager.enumerator(at: raw.appending(path: "autres"), includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "caf" }
        guard autres.allSatisfy({ placed.contains(path($0)) }) else { return false }
        let knownMicrophones = Set(timeline.runs.filter { $0.track == "moi" }.map(\.folderName))
        let microphones = (try? manager.contentsOfDirectory(atPath: raw.appending(path: "moi").path(percentEncoded: false))) ?? []
        return microphones.filter { !$0.hasPrefix(".") }.allSatisfy(knownMicrophones.contains)
    }

    static func duration(of url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    // MARK: - Writing

    private static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!

    private static func writePartial(_ pieces: [PlaybackPiece], seconds: Double, for url: URL) throws -> URL {
        let partial = url.deletingLastPathComponent().appending(path: url.deletingPathExtension().lastPathComponent + ".partiel.caf")
        try? FileManager.default.removeItem(at: partial)
        try writeFile(pieces, seconds: seconds, to: partial)
        return partial
    }

    private static func rename(_ partial: URL, to url: URL) throws -> URL {
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: partial)
        } else {
            try FileManager.default.moveItem(at: partial, to: url)
        }
        return url
    }

    /// The output file lives only in this function: it is closed when the function returns.
    private static func writeFile(_ pieces: [PlaybackPiece], seconds: Double, to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatAppleLossless, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
            AVEncoderBitDepthHintKey: 16,
        ]
        let output = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let total = AVAudioFramePosition((seconds * sampleRate).rounded())
        var cursor: AVAudioFramePosition = 0
        for piece in pieces.sorted(by: { $0.atSeconds < $1.atSeconds }) {
            let start = AVAudioFramePosition((piece.atSeconds * sampleRate).rounded())
            if start > cursor {
                try writeSilence(start - cursor, to: output)
                cursor = start
            }
            var samples = try read(piece)
            // Two pieces never overlap on purpose; if they touch, the later one gives way.
            let overlap = Int(cursor - start)
            if overlap > 0 { samples.removeFirst(min(overlap, samples.count)) }
            let room = Int(total - cursor)
            if samples.count > room { samples.removeLast(samples.count - max(0, room)) }
            guard !samples.isEmpty else { continue }
            try writeSamples(samples, to: output)
            cursor += AVAudioFramePosition(samples.count)
        }
        if total > cursor { try writeSilence(total - cursor, to: output) }
    }

    /// The piece's audio, converted to 16 kHz.
    private static func read(_ piece: PlaybackPiece) throws -> [Float] {
        let input: AVAudioFile
        do { input = try AVAudioFile(forReading: piece.url) } catch { throw RenderError.unreadable(piece.url.lastPathComponent) }
        let sourceRate = input.processingFormat.sampleRate
        input.framePosition = AVAudioFramePosition((piece.fromSeconds * sourceRate).rounded())
        let frames = AVAudioFrameCount(min(Double(input.length - input.framePosition), (piece.durationSeconds * sourceRate).rounded()))
        guard frames > 0, let source = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: frames) else { return [] }
        try input.read(into: source, frameCount: frames)

        guard let converter = AVAudioConverter(from: input.processingFormat, to: format),
              let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(frames) * sampleRate / sourceRate) + 1_024)
        else { throw RenderError.unreadable(piece.url.lastPathComponent) }
        var given = false
        var failure: NSError?
        let status = converter.convert(to: converted, error: &failure) { _, state in
            if given { state.pointee = .endOfStream; return nil }
            given = true
            state.pointee = .haveData
            return source
        }
        guard status != .error else { throw RenderError.unreadable(piece.url.lastPathComponent) }
        return Array(UnsafeBufferPointer(start: converted.floatChannelData![0], count: Int(converted.frameLength)))
    }

    private static func writeSamples(_ samples: [Float], to file: AVAudioFile) throws {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        try file.write(from: buffer)
    }

    private static func writeSilence(_ frames: AVAudioFramePosition, to file: AVAudioFile) throws {
        var left = frames
        let block = AVAudioFramePosition(sampleRate * 10)
        while left > 0 {
            let count = Int(min(left, block))
            try writeSamples([Float](repeating: 0, count: count), to: file)
            left -= AVAudioFramePosition(count)
        }
    }
}
