import Darwin
import Foundation

public enum CAFError: Error, Equatable {
    case cannotOpen(String)
    case writeFailed(String)
    case malformed(String)
}

/// Layout of the CAF files written here. Every header field is big-endian.
///
///     0   'caff', version 1 (UInt16), flags 0 (UInt16)
///     8   'desc' chunk header (type, size 32 as Int64)
///     20  sample rate (Float64), 'lpcm', format flags 3 (float | little-endian),
///         bytes per packet, frames per packet 1, channels, bits per channel 32
///     52  'data' chunk header (type, size as Int64: -1 while the segment is open)
///     64  edit count 0 (UInt32)
///     68  samples
enum CAFLayout {
    static let dataSizeOffset: off_t = 56
    static let audioOffset = 68
    static let formatFlagsFloatLittleEndian: UInt32 = 3
}

/// Writes raw float PCM into numbered CAF segments (`000001.caf`, `000002.caf`, …).
///
/// Every `append` reaches the kernel before it returns, so a crashed or killed process keeps everything
/// already appended. An open segment says "size unknown" (-1) in its header and stays readable; closing a
/// segment writes its real size. Not thread-safe: one thread appends.
public final class CAFSegmentWriter {
    public private(set) var segmentURLs: [URL] = []

    private let directory: URL
    private let format: PCMFormat
    private let framesPerSegment: Int
    private let framesPerSync: Int
    private var descriptor: Int32 = -1
    private var framesInSegment = 0
    private var framesSinceSync = 0

    public init(directory: URL, format: PCMFormat, segmentSeconds: Double = 60, syncEverySeconds: Double = 1) throws {
        self.directory = directory
        self.format = format
        framesPerSegment = max(1, Int(segmentSeconds * format.sampleRate))
        framesPerSync = max(0, Int(syncEverySeconds * format.sampleRate))
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw CAFError.cannotOpen("\(directory.path) : \(error.localizedDescription)")
        }
    }

    deinit {
        if descriptor >= 0 { Darwin.close(descriptor) }
    }

    /// `samples.count` must be a whole number of frames.
    public func append(_ samples: UnsafeBufferPointer<Float>) throws {
        guard let base = samples.baseAddress else { return }
        var remaining = samples.count / format.channels
        var cursor = base
        while remaining > 0 {
            if descriptor < 0 { try openSegment() }
            let frames = min(remaining, framesPerSegment - framesInSegment)
            try write(UnsafeRawBufferPointer(start: cursor, count: frames * format.bytesPerFrame))
            framesInSegment += frames
            framesSinceSync += frames
            cursor += frames * format.channels
            remaining -= frames
            if framesInSegment >= framesPerSegment {
                try closeSegment()
            } else if framesSinceSync >= framesPerSync {
                fsync(descriptor)
                framesSinceSync = 0
            }
        }
    }

    public func close() throws {
        if descriptor >= 0 { try closeSegment() }
    }

    // MARK: - Segments

    private func openSegment() throws {
        let url = directory.appending(path: String(format: "%06d.caf", segmentURLs.count + 1))
        let fd = open(url.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard fd >= 0 else { throw CAFError.cannotOpen("\(url.path) : \(String(cString: strerror(errno)))") }
        descriptor = fd
        framesInSegment = 0
        framesSinceSync = 0
        segmentURLs.append(url)
        try header().withUnsafeBytes { try write($0) }
    }

    private func closeSegment() throws {
        // The data chunk holds the 4-byte edit count, then the samples.
        var size = Int64(4 + framesInSegment * format.bytesPerFrame).bigEndian
        let written = withUnsafeBytes(of: &size) { pwrite(descriptor, $0.baseAddress, $0.count, CAFLayout.dataSizeOffset) }
        fsync(descriptor)
        Darwin.close(descriptor)
        descriptor = -1
        if written != MemoryLayout<Int64>.size {
            throw CAFError.writeFailed("taille du segment non écrite : \(String(cString: strerror(errno)))")
        }
    }

    private func header() -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("caff".utf8))
        append(UInt16(1))
        append(UInt16(0))
        data.append(contentsOf: Array("desc".utf8))
        append(Int64(32))
        append(format.sampleRate.bitPattern)
        data.append(contentsOf: Array("lpcm".utf8))
        append(CAFLayout.formatFlagsFloatLittleEndian)
        append(UInt32(format.bytesPerFrame))
        append(UInt32(1))
        append(UInt32(format.channels))
        append(UInt32(32))
        data.append(contentsOf: Array("data".utf8))
        append(Int64(-1))
        append(UInt32(0))
        return data
    }

    private func write(_ bytes: UnsafeRawBufferPointer) throws {
        var offset = 0
        while offset < bytes.count {
            let n = Darwin.write(descriptor, bytes.baseAddress! + offset, bytes.count - offset)
            if n < 0 {
                if errno == EINTR { continue }
                throw CAFError.writeFailed(String(cString: strerror(errno)))
            }
            offset += n
        }
    }
}
