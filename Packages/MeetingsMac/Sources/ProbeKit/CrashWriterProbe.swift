import AudioCapture
import Foundation
import Observability

/// Measures what a brutal stop (`kill -9`) costs.
///
/// Default run: writes a 440 Hz tone in 100 ms buffers at real pace and logs the frame count after each
/// buffer, until it is killed. `--variant verify`: reads back the previous run and prints `perte_ms=<n>`,
/// the audio that had been logged as appended but cannot be read.
public struct CrashWriterProbe: Probe {
    struct Progress: Encodable, Sendable {
        let framesAppended: Int
    }

    struct Verdict: Encodable, Sendable {
        let directory: String
        let framesAppended: Int
        let framesRead: Int
        let lossMs: Int
    }

    static let format = PCMFormat(sampleRate: 48_000, channels: 1)
    static let bufferFrames = 4_800

    public init() {}

    public func run(_ request: ProbeRequest, trace: TraceWriter, directory: URL) async {
        if request.variant == "verify" {
            await verify(trace: trace, ownDirectory: directory)
        } else {
            await write(request, trace: trace, directory: directory)
        }
    }

    private func write(_ request: ProbeRequest, trace: TraceWriter, directory: URL) async {
        guard let writer = try? CAFSegmentWriter(directory: directory.appending(path: "audio"), format: Self.format) else {
            return
        }
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(request.seconds)
        var appended = 0
        var buffer = [Float](repeating: 0, count: Self.bufferFrames)

        while clock.now < deadline, !Task.isCancelled {
            for index in buffer.indices {
                buffer[index] = 0.25 * Float(sin(2 * .pi * 440 * Double(appended + index) / Self.format.sampleRate))
            }
            guard (try? buffer.withUnsafeBufferPointer({ try writer.append($0) })) != nil else { break }
            appended += Self.bufferFrames
            try? await trace.write(kind: "crash-writer", Progress(framesAppended: appended))
            guard await Self.keepGoing(trace, after: 0.1) else { break }
        }
        try? writer.close()
    }

    private func verify(trace: TraceWriter, ownDirectory: URL) async {
        let root = ownDirectory.deletingLastPathComponent()
        let candidates = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasSuffix("-\(ProbeID.crashWriter.rawValue)") }
            .filter { $0.standardizedFileURL != ownDirectory.standardizedFileURL }
            .filter { FileManager.default.fileExists(atPath: $0.appending(path: "audio").path) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard let target = candidates.last,
              let text = try? String(contentsOf: target.appending(path: "trace.jsonl"), encoding: .utf8)
        else {
            print("perte_ms=inconnue (aucune écriture précédente)")
            return
        }
        let appended = Self.lastFramesAppended(inTrace: text) ?? 0
        let segments = ((try? FileManager.default.contentsOfDirectory(at: target.appending(path: "audio"), includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "caf" }
        let read = segments.reduce(0) { total, url in
            total + ((try? CAFReader.read(url).samples.count) ?? 0)
        }
        let loss = Self.lossMilliseconds(framesAppended: appended, framesRead: read, sampleRate: Self.format.sampleRate)
        try? await trace.write(kind: "crash-verify", Verdict(directory: target.path, framesAppended: appended, framesRead: read, lossMs: loss))
        print("perte_ms=\(loss) ecrites=\(appended) lues=\(read) dossier=\(target.path)")
    }

    /// Audio that was logged as appended but cannot be read back, in milliseconds.
    static func lossMilliseconds(framesAppended: Int, framesRead: Int, sampleRate: Double) -> Int {
        Int((Double(max(0, framesAppended - framesRead)) / sampleRate * 1_000).rounded())
    }

    /// The last `framesAppended` of a trace whose final line may have been cut by the kill.
    static func lastFramesAppended(inTrace text: String) -> Int? {
        struct Line: Decodable {
            struct Payload: Decodable { let framesAppended: Int? }
            let kind: String
            let data: Payload
        }
        let decoder = JSONDecoder()
        for line in text.split(separator: "\n").reversed() {
            if let parsed = try? decoder.decode(Line.self, from: Data(line.utf8)),
               parsed.kind == "crash-writer", let frames = parsed.data.framesAppended {
                return frames
            }
        }
        return nil
    }
}
