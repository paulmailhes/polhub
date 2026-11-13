import Darwin
import Foundation

public enum TraceError: Error, Equatable {
    case cannotOpen(String)
    case writeFailed(String)
}

/// Clock that keeps running while the Mac sleeps (`mach_continuous_time`).
public enum ContinuousTime {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    public static func nanos() -> UInt64 {
        mach_continuous_time() * UInt64(timebase.numer) / UInt64(timebase.denom)
    }

    public static func seconds() -> Double {
        Double(nanos()) / 1_000_000_000
    }
}

/// Appends one JSON object per line: `{"t":…,"up":…,"kind":…,"data":…}`.
/// Each line reaches the file before `write` returns, so a killed process loses nothing already written.
///
/// A trace that can no longer be written (disk full, folder gone) remembers its first failure in
/// `failure`: the probes stop on it instead of going on measuring into the void.
public actor TraceWriter {
    private struct Line<P: Encodable>: Encodable {
        let t: String
        let up: Double
        let kind: String
        let data: P
    }

    /// The first write that failed, if any. Writing to a closed trace is not such a failure.
    public private(set) var failure: TraceError?

    private var sink: (@Sendable (Data) throws -> Void)?
    private var closeSink: (@Sendable () -> Void)?
    private let path: String
    private let encoder: JSONEncoder

    public init(fileURL: URL) throws {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw TraceError.cannotOpen("\(fileURL.path) : \(error.localizedDescription)")
        }
        if !manager.fileExists(atPath: fileURL.path),
           !manager.createFile(atPath: fileURL.path, contents: nil) {
            throw TraceError.cannotOpen(fileURL.path)
        }
        // O_APPEND: every write lands at the end of the file, even when another copy of the app writes the
        // same journal at the same time.
        let descriptor = open(fileURL.path, O_WRONLY | O_APPEND)
        guard descriptor >= 0 else {
            throw TraceError.cannotOpen("\(fileURL.path) : \(String(cString: strerror(errno)))")
        }
        let file = FileBox(FileHandle(fileDescriptor: descriptor, closeOnDealloc: true))
        path = fileURL.path
        encoder = Self.makeEncoder()
        sink = { try file.handle.write(contentsOf: $0) }
        closeSink = { try? file.handle.close() }
    }

    /// For tests: the lines go to `sink` instead of a file.
    init(path: String, sink: @escaping @Sendable (Data) throws -> Void) {
        self.path = path
        encoder = Self.makeEncoder()
        self.sink = sink
        closeSink = nil
    }

    public func write<P: Encodable & Sendable>(kind: String, _ payload: P) throws {
        guard let sink else { throw TraceError.writeFailed("\(path) : trace fermée") }
        let stamp = Date.now.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        // A line that cannot be encoded (a NaN) is lost alone: the trace itself is fine.
        var data: Data
        do {
            data = try encoder.encode(Line(t: stamp, up: ContinuousTime.seconds(), kind: kind, data: payload))
        } catch {
            throw TraceError.writeFailed("\(path) : ligne illisible (\(error.localizedDescription))")
        }
        data.append(0x0A)
        do {
            try sink(data)
        } catch {
            let wrapped = TraceError.writeFailed("\(path) : \(error.localizedDescription)")
            failure = failure ?? wrapped
            throw wrapped
        }
    }

    public func close() {
        closeSink?()
        sink = nil
        closeSink = nil
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// `FileHandle` is used from this actor only.
    private final class FileBox: @unchecked Sendable {
        let handle: FileHandle
        init(_ handle: FileHandle) { self.handle = handle }
    }
}
