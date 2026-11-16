import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Inspiration

/// The images of « Inspiration » made light (16/11): at most 1 600 px on the long side, never enlarged, JPEG
/// 0.82 in sRGB without metadata, the first frame of a GIF; what is not an image is left aside with its reason.
@Suite struct ImageShrinkerTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "images \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func write(_ data: Data, _ name: String) throws -> URL {
        let url = folder.appending(path: name)
        try data.write(to: url)
        return url
    }

    @Test func aLargeImageComesDownTo1600OnItsLongSide() throws {
        let source = try write(TestImages.png(width: 3200, height: 1800), "grande.png")
        let target = folder.appending(path: "sortie/grande.jpg")
        let bytes = try ImageShrinker().shrink(file: source, to: target)
        let probe = try #require(TestImages.Probe(target))
        #expect(probe.width == 1600 && probe.height == 900)
        #expect(probe.type == "public.jpeg")
        #expect(bytes == (try FileManager.default.attributesOfItem(atPath: target.path(percentEncoded: false))[.size] as? Int))
        #expect(bytes > 0)
    }

    @Test func aTallImageComesDownByItsHeight() throws {
        let source = try write(TestImages.jpeg(width: 1200, height: 4000), "haute.jpg")
        let target = folder.appending(path: "haute-sortie.jpg")
        try ImageShrinker().shrink(file: source, to: target)
        let probe = try #require(TestImages.Probe(target))
        #expect(probe.width == 480 && probe.height == 1600)
    }

    @Test func aSmallImageIsNeverEnlarged() throws {
        let source = try write(TestImages.png(width: 400, height: 300), "petite.png")
        let target = folder.appending(path: "petite.jpg")
        try ImageShrinker().shrink(file: source, to: target)
        let probe = try #require(TestImages.Probe(target))
        #expect(probe.width == 400 && probe.height == 300)
    }

    /// Still images only (Paul, 16/11): the first frame of an animated GIF.
    @Test func anAnimatedGIFKeepsItsFirstFrame() throws {
        let source = try write(TestImages.gif(width: 300, height: 200, frames: [.red, .blue, .blue]), "anime.gif")
        let target = folder.appending(path: "anime.jpg")
        try ImageShrinker().shrink(file: source, to: target)
        let probe = try #require(TestImages.Probe(target))
        #expect(probe.type == "public.jpeg" && probe.width == 300 && probe.height == 200)
        let pixel = probe.pixel(x: 10, y: 10)
        #expect(pixel.red > 200 && pixel.blue < 60)
    }

    /// The vault holds pages saved with an image's name: left aside, with the reason, and nothing written.
    @Test func whatIsNotAnImageIsLeftAsideWithItsReason() throws {
        let source = try write(Data("<!doctype html><html><head><title>Exemple</title></head></html>".utf8), "page.png")
        let target = folder.appending(path: "page.jpg")
        #expect(throws: ImageShrinkError.self) { try ImageShrinker().shrink(file: source, to: target) }
        do {
            try ImageShrinker().shrink(file: source, to: target)
        } catch let error as ImageShrinkError {
            #expect(error.reason == "ce n'est pas une image lisible")
        }
        #expect(!FileManager.default.fileExists(atPath: target.path(percentEncoded: false)))
        #expect(throws: ImageShrinkError.self) { try ImageShrinker().shrink(file: folder.appending(path: "absente.png"), to: target) }
    }

    /// No metadata leaves: no position, no camera, no comment.
    @Test func theMetadataStayBehind() throws {
        let data = TestImages.jpeg(width: 800, height: 600, frameProperties: [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 45.76, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 4.83, kCGImagePropertyGPSLongitudeRef: "E"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "commentaire privé"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Appareil Exemple"],
        ])
        let source = try write(data, "photo.jpg")
        #expect(TestImages.Probe(source)?.properties[kCGImagePropertyGPSDictionary] != nil)
        let target = folder.appending(path: "photo-sortie.jpg")
        try ImageShrinker().shrink(file: source, to: target)
        let probe = try #require(TestImages.Probe(target))
        #expect(probe.properties[kCGImagePropertyGPSDictionary] == nil)
        #expect(probe.properties[kCGImagePropertyTIFFDictionary] == nil)
        let exif = probe.properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifUserComment] == nil)
    }

    /// A photo turned on its side by its orientation tag comes out upright.
    @Test func theOrientationIsApplied() throws {
        let source = try write(TestImages.jpeg(width: 400, height: 200, frameProperties: [kCGImagePropertyOrientation: 6]), "tournee.jpg")
        let target = folder.appending(path: "tournee-sortie.jpg")
        try ImageShrinker().shrink(file: source, to: target)
        let probe = try #require(TestImages.Probe(target))
        #expect(probe.width == 200 && probe.height == 400)
    }

    /// sRGB whatever came in; a transparent background turns white, as a logo on a page.
    @Test func theColorsAreSRGBOnWhite() throws {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let source = try write(TestImages.png(width: 200, height: 200, color: .red, transparent: true, space: p3), "logo.png")
        let target = folder.appending(path: "logo.jpg")
        try ImageShrinker().shrink(file: source, to: target)
        let probe = try #require(TestImages.Probe(target))
        #expect(probe.colorSpace == (CGColorSpace.sRGB as String))
        let corner = probe.pixel(x: 2, y: 2)
        #expect(corner.red > 245 && corner.green > 245 && corner.blue > 245)
        let middle = probe.pixel(x: 70, y: 70)
        #expect(middle.red > 200 && middle.green < 80)
    }

    /// Downloaded bytes go the same way (the collection).
    @Test func bytesInMemoryAreShrunkToo() throws {
        let target = folder.appending(path: "telechargee.jpg")
        let bytes = try ImageShrinker().shrink(data: TestImages.png(width: 2000, height: 1000), to: target)
        #expect(bytes > 0 && TestImages.Probe(target)?.width == 1600)
        #expect(throws: ImageShrinkError.self) { try ImageShrinker().shrink(data: Data("pas une image".utf8), to: target) }
    }

    /// Many at once, from many threads: each comes out whole.
    @Test func manyImagesAtOnce() async throws {
        let sources = try (0..<12).map { try write(TestImages.png(width: 1800 + $0 * 10, height: 1200), "lot-\($0).png") }
        let folder = folder
        let sizes = try await withThrowingTaskGroup(of: Int.self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask { try ImageShrinker().shrink(file: source, to: folder.appending(path: "lot-\(index).jpg")) }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(sizes.count == 12 && sizes.allSatisfy { $0 > 0 })
        for index in 0..<12 {
            #expect(TestImages.Probe(folder.appending(path: "lot-\(index).jpg"))?.width == 1600)
        }
    }
}
