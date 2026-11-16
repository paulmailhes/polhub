import Foundation
import Persistence
import Testing
@testable import Inspiration

/// A mock-up added by its folder (16/11), and how a downloaded image is checked and cut short.
@Suite struct MockupAndImageTests {
    let now = Date(timeIntervalSince1970: 1_794_830_400)

    func folder(in world: CollectWorld, _ name: String, files: [String: Data]) throws -> URL {
        let folder = world.root.appending(path: "Mock-ups", directoryHint: .isDirectory).appending(path: name, directoryHint: .isDirectory)
        for (path, data) in files {
            let url = folder.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func aMockupIsAddedByItsFolder() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        let affiche = try folder(in: world, "Affiche urbaine", files: [
            "Affiche.psd": Data("8BPS".utf8), "Lisez-moi.txt": Data("licence".utf8), "preview.jpg": TestImages.jpeg(width: 1200, height: 900),
        ])
        let item = try await world.collector().addMockup(folder: affiche, now: now)
        #expect(item.kind == .mockup && item.key == "Affiche urbaine" && item.title == "Affiche urbaine")
        #expect(item.extra.localFolder == affiche.standardizedFileURL.path(percentEncoded: false))
        #expect(item.date == now && item.categories.isEmpty)
        // The Finder's thumbnail, made light, named as the import names the previews.
        #expect(item.images == [InspirationImageName.mockup(folder: "Affiche urbaine")])
        let probe = try #require(TestImages.Probe(world.imageURL(.mockup, item.images[0])))
        #expect(probe.width == 1600 && probe.height == 1200)
        // Added twice: one item.
        _ = try await world.collector().addMockup(folder: affiche, now: now)
        #expect(try world.store.items(kind: .mockup).count == 1)
    }

    /// Without a Quick Look thumbnail, ImageIO reads the image itself.
    @Test func withoutThumbnailTheImageIsReadDirectly() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        let boite = try folder(in: world, "Boi\u{0302}te carton", files: ["Images/vue-1.png": TestImages.png(width: 900, height: 600)])
        let item = try await world.collector(thumbnailer: FakeThumbnailer(image: nil)).addMockup(folder: boite, now: now)
        // The folder's name in its composed form, as the vault's keys.
        #expect(item.key == "Boîte carton" && item.key.unicodeScalars.count == 12)
        let probe = try #require(TestImages.Probe(world.imageURL(.mockup, item.images[0])))
        #expect(probe.width == 900 && probe.height == 600)
    }

    /// A mock-up the import brought: it keeps its title and preview, and learns its folder on the Mac.
    @Test func aKnownMockupLearnsItsFolder() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        try world.store.upsert(InspirationItemRow(kind: .mockup, key: "Carte de visite", title: "Carte de visite (recto verso)",
                                                  date: Date(timeIntervalSince1970: 1_700_000_000), categories: ["type": ["business card"]],
                                                  images: ["carte.jpg"], extra: InspirationExtra(folderURL: "https://nuage.exemple.fr/index.php/apps/files/?dir=/Mock-ups/Carte%20de%20visite"),
                                                  createdAt: now))
        let carte = try folder(in: world, "Carte de visite", files: ["apercu.jpg": TestImages.jpeg(width: 400, height: 300)])
        let item = try await world.collector().addMockup(folder: carte, now: now)
        #expect(item.title == "Carte de visite (recto verso)" && item.images == ["carte.jpg"])
        #expect(item.categories == ["type": ["business card"]] && item.date == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(item.extra.localFolder != nil && item.extra.folderURL != nil)
        #expect(world.imageFiles(.mockup).isEmpty)
    }

    @Test func aFileIsNotAMockupFolder() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        let file = world.root.appending(path: "affiche.psd")
        try Data("8BPS".utf8).write(to: file)
        await #expect(throws: InspirationAddError.notAFolder) { try await world.collector().addMockup(folder: file, now: now) }
        await #expect(throws: InspirationAddError.notAFolder) {
            try await world.collector().addMockup(folder: world.root.appending(path: "absent", directoryHint: .isDirectory), now: now)
        }
    }

    /// The preview: an image whose name says so, else the first image, else the PSD or PSB.
    @Test func thePreviewFileIsChosenAsAPersonWould() throws {
        let world = try CollectWorld()
        defer { world.remove() }
        let pixel = TestImages.png(width: 4, height: 4)
        let named = try folder(in: world, "A", files: ["01.jpg": pixel, "Images/Cover.png": pixel, "a.psd": pixel])
        #expect(MockupFolder.previewFile(in: named)?.lastPathComponent == "Cover.png")
        let first = try folder(in: world, "B", files: ["z.psd": pixel, "b 10.jpg": pixel, "b 9.jpg": pixel, ".cache.jpg": pixel])
        #expect(MockupFolder.previewFile(in: first)?.lastPathComponent == "b 9.jpg")
        let layered = try folder(in: world, "C", files: ["Mockup.psb": pixel, "Lisez-moi.pdf": pixel])
        #expect(MockupFolder.previewFile(in: layered)?.lastPathComponent == "Mockup.psb")
        let empty = try folder(in: world, "D", files: ["Lisez-moi.txt": pixel])
        #expect(MockupFolder.previewFile(in: empty) == nil)
    }

    /// Quick Look draws a real file's thumbnail on this Mac (no network, no window).
    @Test func quickLookDrawsAThumbnail() async throws {
        let world = try CollectWorld()
        defer { world.remove() }
        let file = world.root.appending(path: "vue.png")
        try TestImages.png(width: 1200, height: 800).write(to: file)
        let png = try await QuickLookThumbnailer().thumbnail(of: file, maxSide: 600)
        let destination = world.root.appending(path: "vignette.jpg")
        try ImageShrinker().shrink(data: png, to: destination)
        let probe = try #require(TestImages.Probe(destination))
        #expect(max(probe.width, probe.height) <= 600 && probe.width > probe.height)
    }

    // MARK: - Images

    /// A GIF is read up to the end of its first frame: what follows is never needed.
    @Test func aGifStopsAfterItsFirstFrame() throws {
        let gif = TestImages.gif(width: 400, height: 300, frames: [.red, .blue, .green])
        #expect(!GIFData.firstFrameIsComplete(gif.prefix(13)))
        var cut = 0
        for length in stride(from: 14, through: gif.count, by: 16) where GIFData.firstFrameIsComplete(gif.prefix(length)) {
            cut = length
            break
        }
        #expect(cut > 0 && cut < gif.count)
        let destination = FileManager.default.temporaryDirectory.appending(path: "premiere-image-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: destination) }
        try ImageShrinker().shrink(data: gif.prefix(cut), to: destination)
        let probe = try #require(TestImages.Probe(destination))
        let pixel = probe.pixel(x: 5, y: 5)
        #expect(probe.width == 400 && pixel.red > 200 && pixel.blue < 60 && pixel.green < 60)
        #expect(!GIFData.firstFrameIsComplete(TestImages.jpeg(width: 10, height: 10)))
        #expect(GIFData.firstFrameIsComplete(gif))
    }

    @Test func onlyRasterImagesAreDecoded() {
        #expect(RemoteImage.isAcceptable(TestImages.jpeg(width: 10, height: 10), contentType: "image/jpeg"))
        #expect(RemoteImage.isAcceptable(TestImages.png(width: 10, height: 10), contentType: "application/octet-stream"))
        #expect(!RemoteImage.isAcceptable(Data("<svg xmlns='http://www.w3.org/2000/svg'/>".utf8), contentType: "image/svg+xml"))
        #expect(!RemoteImage.isAcceptable(Data("<html></html>".utf8), contentType: "text/html"))
        #expect(!RemoteImage.isAcceptable(TestImages.png(width: 10, height: 10), contentType: "text/html"))
    }
}
