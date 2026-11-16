import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Why an image was left aside, in plain words.
public struct ImageShrinkError: Error, Equatable, Sendable, CustomStringConvertible {
    public let reason: String
    public var description: String { reason }

    public static let notAnImage = ImageShrinkError(reason: "ce n'est pas une image lisible")
    public static let unreadable = ImageShrinkError(reason: "fichier introuvable ou illisible")
    public static let notWritten = ImageShrinkError(reason: "l'image n'a pas pu être écrite")
}

/// Makes an image of « Inspiration » light (16/11): the first frame of anything ImageIO reads (GIF, PNG, JPEG,
/// WebP, AVIF, HEIC…), at most 1 600 px on its long side and never enlarged, upright, in sRGB on white, written
/// as JPEG 0.82 without any metadata. What is not an image (a page saved with an image's name) is refused with
/// its reason, and nothing is written.
///
/// Synchronous and without state: call it off the main thread (the import does); safe from many threads at
/// once. Each call drains its own autorelease pool.
public struct ImageShrinker: Sendable {
    public static let maxSide = 1600
    public static let quality = 0.82

    public let maxSide: Int
    public let quality: Double

    public init(maxSide: Int = ImageShrinker.maxSide, quality: Double = ImageShrinker.quality) {
        self.maxSide = maxSide
        self.quality = quality
    }

    /// Writes `file` made light at `destination` (its folder is made), replacing what was there; returns the
    /// bytes written.
    @discardableResult
    public func shrink(file: URL, to destination: URL) throws -> Int {
        try autoreleasepool {
            guard FileManager.default.isReadableFile(atPath: file.path(percentEncoded: false)) else { throw ImageShrinkError.unreadable }
            guard let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
                throw ImageShrinkError.notAnImage
            }
            return try write(source, to: destination)
        }
    }

    /// The same for bytes in memory (a downloaded image).
    @discardableResult
    public func shrink(data: Data, to destination: URL) throws -> Int {
        try autoreleasepool {
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
                throw ImageShrinkError.notAnImage
            }
            return try write(source, to: destination)
        }
    }

    private func write(_ source: CGImageSource, to destination: URL) throws -> Int {
        guard CGImageSourceGetType(source) != nil, CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0
        else { throw ImageShrinkError.notAnImage }
        // Only the first frame is decoded, already at its final size: a 40 MB GIF costs one small image.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxSide, max(width, height)),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let frame = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw ImageShrinkError.notAnImage }
        let image = try flattened(frame)
        return try writeJPEG(image, to: destination)
    }

    /// In sRGB, on white: a JPEG has no transparency, and a transparent logo reads as on a page.
    private func flattened(_ image: CGImage) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw ImageShrinkError.notWritten }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        guard let flat = context.makeImage() else { throw ImageShrinkError.notWritten }
        return flat
    }

    /// Written beside under another name, then put in place: a half-written file never passes for an image.
    private func writeJPEG(_ image: CGImage, to destination: URL) throws -> Int {
        let manager = FileManager.default
        let folder = destination.deletingLastPathComponent()
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let partial = folder.appending(path: ".\(destination.lastPathComponent).\(UUID().uuidString).partiel")
        defer { try? manager.removeItem(at: partial) }
        guard let output = CGImageDestinationCreateWithURL(partial as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ImageShrinkError.notWritten
        }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw ImageShrinkError.notWritten }
        if manager.fileExists(atPath: destination.path(percentEncoded: false)) {
            _ = try manager.replaceItemAt(destination, withItemAt: partial)
        } else {
            try manager.moveItem(at: partial, to: destination)
        }
        let size = try manager.attributesOfItem(atPath: destination.path(percentEncoded: false))[.size] as? Int
        return size ?? 0
    }
}
