import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What a downloaded image may be before it meets ImageIO (16/11): the raster kinds of the web only, never SVG nor
/// a page saved under an image's name; and a GIF is read only up to the end of its first frame.
enum RemoteImage {
    /// JPEG, PNG, GIF, WebP, HEIC, AVIF, TIFF, BMP.
    static let allowedTypes: Set<String> = [
        UTType.jpeg.identifier, UTType.png.identifier, UTType.gif.identifier, UTType.webP.identifier, UTType.heic.identifier,
        UTType.heif.identifier, UTType.tiff.identifier, UTType.bmp.identifier, "public.avif", "public.avci",
    ]

    /// An image hub decodes: its header says one of the allowed kinds, whatever the server called it.
    static func isAcceptable(_ data: Data, contentType: String?) -> Bool {
        if let contentType, contentType.contains("svg") || contentType.hasPrefix("text/") { return false }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String? else { return false }
        return allowedTypes.contains(type)
    }

    static func isGIF(_ data: Data) -> Bool {
        data.count >= 6 && data.prefix(4).elementsEqual("GIF8".utf8)
    }
}

/// The blocks of a GIF, walked without decoding anything (GIF89a): enough to know when its first frame has
/// arrived, so that a 40 MB animation costs only its first image.
enum GIFData {
    /// Whether the bytes hold a GIF's whole first image (its data and their terminator), or its end. `false` for
    /// anything that is not a GIF.
    @Sendable static func firstFrameIsComplete(_ data: Data) -> Bool {
        guard RemoteImage.isGIF(data), data.count >= 13 else { return false }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            let bytes = raw.bindMemory(to: UInt8.self)
            let count = bytes.count
            var index = 6
            // The logical screen: 7 bytes, then the global color table.
            let flags = bytes[index + 4]
            index += 7
            if flags & 0x80 != 0 { index += 3 << (Int(flags & 0x07) + 1) }
            /// Past a chain of sub-blocks (a length byte, that many bytes… until 0); `nil` when it runs past the end.
            func skipSubBlocks(from start: Int) -> Int? {
                var position = start
                while position < count {
                    let length = Int(bytes[position])
                    position += 1
                    if length == 0 { return position }
                    position += length
                }
                return nil
            }
            while index < count {
                switch bytes[index] {
                case 0x21:
                    // An extension: its label, then its sub-blocks.
                    guard index + 2 <= count, let next = skipSubBlocks(from: index + 2) else { return false }
                    index = next
                case 0x2C:
                    // An image: its descriptor (10 bytes), its local color table, the code size, its data.
                    guard index + 10 <= count else { return false }
                    let local = bytes[index + 9]
                    var position = index + 10
                    if local & 0x80 != 0 { position += 3 << (Int(local & 0x07) + 1) }
                    position += 1
                    guard position <= count, skipSubBlocks(from: position) != nil else { return false }
                    return true
                case 0x3B:
                    return true
                default:
                    // Not a block a GIF holds: let the whole file come.
                    return false
                }
            }
            return false
        }
    }
}
