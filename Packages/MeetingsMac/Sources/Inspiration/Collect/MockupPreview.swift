import CoreGraphics
import Foundation
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Draws a file's still image, as the Finder shows it: a preview of a mock-up's PSD without Photoshop.
public protocol MockupThumbnailing: Sendable {
    /// The image of `file`, at most `maxSide` pixels on its long side, as PNG bytes; throws when macOS cannot draw
    /// its content (the file's icon never stands for it).
    func thumbnail(of file: URL, maxSide: Int) async throws -> Data
}

/// macOS's Quick Look thumbnails (`QLThumbnailGenerator`): the image of a JPEG, a PNG, a PSD, a PSB when the Mac
/// knows how to draw it.
public struct QuickLookThumbnailer: MockupThumbnailing {
    public init() {}

    public func thumbnail(of file: URL, maxSide: Int) async throws -> Data {
        let request = QLThumbnailGenerator.Request(fileAt: file, size: CGSize(width: maxSide, height: maxSide), scale: 1,
                                                   representationTypes: .thumbnail)
        let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw ImageShrinkError.notWritten
        }
        CGImageDestinationAddImage(destination, representation.cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImageShrinkError.notWritten }
        return output as Data
    }
}

/// What a mock-up's folder holds that shows it best.
public enum MockupFolder {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "tif", "tiff", "gif", "avif"]
    static let layeredExtensions: Set<String> = ["psd", "psb"]
    /// Names that say « this is the preview ».
    static let previewWords = ["preview", "apercu", "aperçu", "cover", "thumbnail", "thumb", "mockup", "mock-up"]

    /// A preview image (its name says so), else the first image, else the first PSD or PSB; in the folder, then in
    /// its subfolders (one level). Hidden files and packages are skipped; files by name, as the Finder sorts them.
    public static func previewFile(in folder: URL) -> URL? {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isHiddenKey]
        func children(_ url: URL) -> [URL] {
            ((try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants])) ?? [])
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
        func isFolder(_ url: URL) -> Bool {
            let values = try? url.resourceValues(forKeys: Set(keys))
            return values?.isDirectory == true && values?.isPackage != true
        }
        let top = children(folder)
        let files = top.filter { !isFolder($0) } + top.filter(isFolder).prefix(20).flatMap { children($0).filter { !isFolder($0) } }
        func ext(_ url: URL) -> String { url.pathExtension.lowercased() }
        let images = files.filter { imageExtensions.contains(ext($0)) }
        if let named = images.first(where: { file in
            let name = file.deletingPathExtension().lastPathComponent.lowercased()
            return previewWords.contains { name.contains($0) }
        }) { return named }
        return images.first ?? files.first { layeredExtensions.contains(ext($0)) }
    }
}
