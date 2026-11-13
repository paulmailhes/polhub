import Foundation

/// Reads the CAF segments written by `CAFSegmentWriter`, including one that was never closed
/// (data size -1) or whose last frame was cut short.
public enum CAFReader {
    public static func read(_ url: URL) throws -> (format: PCMFormat, samples: [Float]) {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw CAFError.cannotOpen("\(url.path) : \(error.localizedDescription)")
        }
        var cursor = Cursor(data: data)
        guard try cursor.fourCC() == "caff" else { throw CAFError.malformed("en-tête 'caff' absent") }
        _ = try cursor.integer(UInt16.self)
        _ = try cursor.integer(UInt16.self)

        var format: PCMFormat?
        while cursor.remaining >= 12 {
            let type = try cursor.fourCC()
            let size = try cursor.integer(Int64.self)
            switch type {
            case "desc":
                let sampleRate = Double(bitPattern: try cursor.integer(UInt64.self))
                let formatID = try cursor.fourCC()
                let flags = try cursor.integer(UInt32.self)
                _ = try cursor.integer(UInt32.self)                  // bytes per packet
                _ = try cursor.integer(UInt32.self)                  // frames per packet
                let channels = Int(try cursor.integer(UInt32.self))
                let bits = try cursor.integer(UInt32.self)
                guard formatID == "lpcm", flags == CAFLayout.formatFlagsFloatLittleEndian, bits == 32, channels > 0 else {
                    throw CAFError.malformed("format non pris en charge")
                }
                format = PCMFormat(sampleRate: sampleRate, channels: channels)
            case "data":
                guard let format else { throw CAFError.malformed("bloc 'data' avant 'desc'") }
                _ = try cursor.integer(UInt32.self)                  // edit count
                let declared = size < 0 ? Int.max : max(0, Int(size) - 4)
                let frames = min(declared, cursor.remaining) / format.bytesPerFrame
                return (format, cursor.floats(count: frames * format.channels))
            default:
                guard size >= 0, Int(size) <= cursor.remaining else { throw CAFError.malformed("bloc '\(type)' tronqué") }
                cursor.skip(Int(size))
            }
        }
        throw CAFError.malformed("bloc 'data' absent")
    }

    private struct Cursor {
        let data: Data
        var offset = 0

        init(data: Data) { self.data = data }

        var remaining: Int { data.count - offset }

        mutating func skip(_ count: Int) { offset += count }

        mutating func fourCC() throws -> String {
            guard remaining >= 4 else { throw CAFError.malformed("fichier tronqué") }
            defer { offset += 4 }
            return String(decoding: data[data.startIndex + offset ..< data.startIndex + offset + 4], as: UTF8.self)
        }

        mutating func integer<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
            let size = MemoryLayout<T>.size
            guard remaining >= size else { throw CAFError.malformed("fichier tronqué") }
            defer { offset += size }
            var value: T = 0
            withUnsafeMutableBytes(of: &value) { target in
                _ = data.copyBytes(to: target, from: data.startIndex + offset ..< data.startIndex + offset + size)
            }
            return T(bigEndian: value)
        }

        /// Samples are little-endian floats, the native layout on every Mac this runs on.
        func floats(count: Int) -> [Float] {
            guard count > 0 else { return [] }
            return [Float](unsafeUninitializedCapacity: count) { buffer, initialized in
                _ = data.copyBytes(
                    to: UnsafeMutableRawBufferPointer(buffer),
                    from: data.startIndex + offset ..< data.startIndex + offset + count * MemoryLayout<Float>.size
                )
                initialized = count
            }
        }
    }
}
