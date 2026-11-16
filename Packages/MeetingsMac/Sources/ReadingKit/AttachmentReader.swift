import Foundation
import ImageIO
import MailFormat
import PDFKit
import UniformTypeIdentifiers

/// An attachment made readable for an agent (16/11): an image shrunk for its eyes (1 568 pixels at most, as Claude
/// reads them), the words of a PDF or of a text, else only the file's place on the Mac. Read on the Mac, never sent
/// anywhere by this helper.
enum AttachmentReader {
    static let imageSide = 1_568

    static func read(_ url: URL, name: String, mimeType: String, maximumText: Int) -> MailDesk.FileAnswer {
        let path = url.path(percentEncoded: false)
        let type = UTType(mimeType: mimeType) ?? UTType(filenameExtension: url.pathExtension) ?? .data
        if type.conforms(to: .image), let jpeg = shrunk(url) {
            return .image(jpeg: jpeg, path: path, name: name)
        }
        if type.conforms(to: .pdf), let words = PDFDocument(url: url)?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty {
            return .text(String(words.prefix(maximumText)), path: path, name: name)
        }
        if type.conforms(to: .text) || type.conforms(to: .json) || type.conforms(to: .commaSeparatedText),
           let data = try? Data(contentsOf: url), let words = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            return .text(String(HTMLText.clean(words).prefix(maximumText)), path: path, name: name)
        }
        return .file(path: path, name: name)
    }

    /// The image, its first frame, at most `imageSide` pixels on its long side, as JPEG.
    static func shrunk(_ url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: imageSide,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
