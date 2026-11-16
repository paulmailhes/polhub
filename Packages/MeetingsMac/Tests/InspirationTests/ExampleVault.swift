import CryptoKit
import Foundation
import Persistence
@testable import Inspiration

/// The invented vault of `Fixtures/coffre-exemple` and its old copy `Fixtures/ancienne-copie`, copied to a
/// temporary folder with their images drawn by the tests, and an empty Polhub beside them.
struct ExampleVault {
    let root: URL
    let vault: URL
    let extra: URL
    let paths: AppPaths
    let database: AppDatabase

    static var fixtures: URL {
        Bundle.module.url(forResource: "Fixtures", withExtension: nil)
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures", directoryHint: .isDirectory)
    }

    init() throws {
        let manager = FileManager.default
        root = manager.temporaryDirectory.appending(path: "inspiration \(UUID().uuidString)", directoryHint: .isDirectory)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        vault = root.appending(path: "coffre-exemple", directoryHint: .isDirectory)
        extra = root.appending(path: "ancienne-copie", directoryHint: .isDirectory)
        try manager.copyItem(at: Self.fixtures.appending(path: "coffre-exemple"), to: vault)
        try manager.copyItem(at: Self.fixtures.appending(path: "ancienne-copie"), to: extra)
        paths = AppPaths(root: root.appending(path: "Polhub", directoryHint: .isDirectory), logs: root.appending(path: "Logs"))
        database = try AppDatabase.inMemory()
        try drawImages()
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    private func put(_ data: Data, _ relative: String, in base: URL) throws {
        let url = base.appending(path: relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private func drawImages() throws {
        // Websites: one large PNG, one JPEG; a page saved with an image's place; Maison Exemple's is missing.
        try put(TestImages.png(width: 2400, height: 1260), "database/Websites/_og/studio-exemple.fr.png", in: vault)
        try put(TestImages.jpeg(width: 1200, height: 630), "database/Websites/_og/atelier-nord.example.com-projets.jpg", in: vault)
        try put(Data("<!doctype html><html><body>Pas une image</body></html>".utf8), "database/Websites/_og/page-html.example.com.html", in: vault)
        // Branding: an animated GIF, the cover as JPEG, a PNG; the duplicate's two; a large PNG; six small ones.
        let cafe = "database/Branding/_media/7479089115955373553"
        try put(TestImages.gif(width: 800, height: 600, frames: [.red, .blue]), "\(cafe)-1.gif", in: vault)
        try put(TestImages.jpeg(width: 1080, height: 1350), "\(cafe)-2.jpg", in: vault)
        try put(TestImages.png(width: 1080, height: 1080), "\(cafe)-3.png", in: vault)
        try put(TestImages.jpeg(width: 1000, height: 1000), "database/Branding/_media/7481000460288173553-1.jpg", in: vault)
        try put(TestImages.jpeg(width: 1000, height: 1000), "database/Branding/_media/7481000460288173553-2.jpg", in: vault)
        try put(TestImages.png(width: 3000, height: 2000), "database/Branding/_media/7493244891955373553-1.png", in: vault)
        try put(TestImages.png(width: 300, height: 300), "database/Branding/_media/7511761905254573553-1.png", in: vault)
        for index in 2...6 {
            try put(TestImages.jpeg(width: 300, height: 300), "database/Branding/_media/7511761905254573553-\(index).jpg", in: vault)
        }
        // Mock-ups: two previews; the business card has none.
        try put(TestImages.jpeg(width: 900, height: 600), "database/Mockups/_previews/Affiche urbaine.jpg", in: vault)
        try put(TestImages.jpeg(width: 900, height: 675), "database/Mockups/_previews/Boîte carton.jpg", in: vault)
        // The old copy.
        try put(TestImages.jpeg(width: 1200, height: 630), "database/Websites/_og/site-recent.example.com.jpg", in: extra)
        try put(TestImages.png(width: 1200, height: 630), "database/Websites/_og/studio-exemple.fr.png", in: extra)
        try put(TestImages.jpeg(width: 1080, height: 1080), "database/Branding/_media/7525847216947373553-1.jpg", in: extra)
        try put(TestImages.jpeg(width: 1080, height: 1350), "database/Branding/_media/7479089115955373553-2.jpg", in: extra)
    }

    func run(extra: URL? = nil, options: InspirationImport.Options = .init(),
             progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> InspirationImportReport {
        try await InspirationImport.run(vault: vault, extra: extra, database: database, paths: paths, options: options, progress: progress)
    }

    var store: InspirationStore { InspirationStore(database) }

    func item(_ kind: InspirationKind, titled title: String) throws -> InspirationItemRow? {
        try store.allItems(kind: kind).first { $0.title == title }
    }

    func imageURL(_ kind: InspirationKind, _ name: String) -> URL {
        paths.inspirationImages(kind).appending(path: name)
    }

    /// Every file under a folder: its path, size, date and content hash.
    static func snapshot(_ folder: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return [:] }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let hash = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
            result[url.path(percentEncoded: false)] = "\(values.fileSize ?? 0) \(values.contentModificationDate?.timeIntervalSince1970 ?? 0) \(hash)"
        }
        return result
    }
}
