import AppKit
import Foundation
import ImageIO
import Persistence
import UniformTypeIdentifiers
@testable import MeetingsUI

/// An invented « Inspiration » (16/11): sites, branding posts and mock-ups with images drawn here, no file of anyone's,
/// no network. Studios, sites and clients are made up (`exemple.fr`, `example.com`).
@MainActor
struct InspirationTestWorld {
    let root: URL
    let paths: AppPaths
    let database: AppDatabase
    let store: InspirationStore
    let defaults: UserDefaults

    init(name: String = "inspiration") throws {
        root = FileManager.default.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        paths = AppPaths(root: root, logs: root.appending(path: "logs"))
        database = try AppDatabase.inMemory()
        store = InspirationStore(database)
        defaults = UserDefaults(suiteName: "\(name)-\(UUID().uuidString)")!
    }

    func library(services: InspirationServices = .notConnected) -> InspirationLibrary {
        InspirationLibrary(database: database, paths: paths, services: services, defaults: defaults)
    }

    func clean() {
        try? FileManager.default.removeItem(at: root)
    }

    /// A day of 2026 at noon.
    static func day(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    // MARK: - Items

    @discardableResult
    func website(_ title: String, url: String, on date: Date, categories: [String: [String]] = [:], text: String = "",
                 image: Int? = nil, fonts: [String] = [], client: String? = nil) throws -> InspirationItemRow {
        let images = try image.map { [try draw("site-\($0).jpg", kind: .website, seed: $0)] } ?? []
        let row = InspirationItemRow(kind: .website, key: url, title: title, text: text, url: url, date: date, categories: categories,
                                     fonts: fonts, client: client, images: images, createdAt: date)
        return try store.upsert(row, at: date).item
    }

    @discardableResult
    func branding(_ title: String, urn: String, on date: Date, studio: String?, sources: [String], categories: [String: [String]] = [:],
                  text: String = "", images: [Int] = [], links: [String] = []) throws -> InspirationItemRow {
        let files = try images.enumerated().map { index, seed in try draw("\(urn)-\(index + 1).jpg", kind: .branding, seed: seed,
                                                                         size: index == 1 ? CGSize(width: 900, height: 1_200) : CGSize(width: 1_200, height: 1_200)) }
        let row = InspirationItemRow(kind: .branding, key: urn, title: title, text: text,
                                     url: "https://www.linkedin.com/feed/update/urn:li:activity:\(urn)/", links: links, date: date,
                                     sources: sources, studio: studio, categories: categories, images: files, createdAt: date)
        return try store.upsert(row, at: date).item
    }

    @discardableResult
    func mockup(_ title: String, folder: String, on date: Date, types: [String], image: Int? = nil) throws -> InspirationItemRow {
        let images = try image.map { [try draw("\(folder.lowercased().replacingOccurrences(of: " ", with: "-")).jpg", kind: .mockup, seed: $0,
                                               size: CGSize(width: 900, height: 600))] } ?? []
        let row = InspirationItemRow(kind: .mockup, key: folder, title: title, date: date, studio: "Boutique Exemple",
                                     categories: ["type": types], images: images,
                                     extra: InspirationExtra(folderURL: "https://cloud.example.com/apps/files/?dir=/Mock-ups/\(folder)"),
                                     createdAt: date)
        return try store.upsert(row, at: date).item
    }

    // MARK: - Images

    /// An abstract composition: a gradient ground and a few shapes, different for each seed.
    @discardableResult
    func draw(_ name: String, kind: InspirationKind, seed: Int, size: CGSize = CGSize(width: 1_600, height: 1_000)) throws -> String {
        let folder = paths.inspirationImages(kind)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try Self.writeJPEG(Self.composition(seed: seed, size: size), to: url)
        return name
    }

    static let palettes: [[(CGFloat, CGFloat, CGFloat)]] = [
        [(0.96, 0.93, 0.86), (0.89, 0.36, 0.22), (0.13, 0.13, 0.16)],
        [(0.10, 0.12, 0.20), (0.36, 0.42, 0.98), (0.95, 0.80, 0.30)],
        [(0.92, 0.95, 0.93), (0.13, 0.55, 0.42), (0.98, 0.62, 0.55)],
        [(0.99, 0.86, 0.80), (0.55, 0.20, 0.40), (0.20, 0.20, 0.22)],
        [(0.08, 0.08, 0.09), (0.93, 0.93, 0.90), (0.98, 0.35, 0.20)],
        [(0.85, 0.90, 0.98), (0.20, 0.30, 0.60), (0.98, 0.98, 1.00)],
        [(0.97, 0.95, 0.70), (0.15, 0.15, 0.15), (0.85, 0.25, 0.30)],
        [(0.30, 0.20, 0.45), (0.95, 0.55, 0.75), (0.98, 0.90, 0.60)],
    ]

    static func composition(seed: Int, size: CGSize) -> CGImage {
        let width = Int(size.width), height = Int(size.height)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let palette = palettes[abs(seed) % palettes.count]
        func color(_ index: Int, _ alpha: CGFloat = 1) -> CGColor {
            let (r, g, b) = palette[index % palette.count]
            return CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
        }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [color(0), color(0, 0.85)] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: bounds.maxX, y: bounds.maxY), options: [])
        var random = UInt64(truncatingIfNeeded: seed &* 2_654_435_761 &+ 97)
        func next() -> CGFloat {
            random = random &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat((random >> 33) % 10_000) / 10_000
        }
        switch abs(seed) % 4 {
        case 0:
            // A big disc and a band.
            context.setFillColor(color(1))
            let side = bounds.height * (0.55 + next() * 0.3)
            context.fillEllipse(in: CGRect(x: bounds.width * (0.15 + next() * 0.4), y: bounds.height * 0.18, width: side, height: side))
            context.setFillColor(color(2))
            context.fill(CGRect(x: 0, y: bounds.height * 0.08, width: bounds.width, height: bounds.height * 0.07))
        case 1:
            // A grid of tiles, a few in the accent.
            let columns = 6, rows = 4
            let tile = CGSize(width: bounds.width / CGFloat(columns), height: bounds.height / CGFloat(rows))
            for column in 0..<columns {
                for row in 0..<rows {
                    context.setFillColor(next() > 0.7 ? color(1) : color(2, 0.12 + next() * 0.2))
                    context.fill(CGRect(x: CGFloat(column) * tile.width + 6, y: CGFloat(row) * tile.height + 6, width: tile.width - 12, height: tile.height - 12))
                }
            }
        case 2:
            // Stripes.
            for index in 0..<9 {
                context.setFillColor(index % 2 == 0 ? color(1, 0.9) : color(2, 0.85))
                let x = bounds.width * CGFloat(index) / 9
                context.fill(CGRect(x: x, y: 0, width: bounds.width / 18 + next() * bounds.width / 30, height: bounds.height * (0.4 + next() * 0.6)))
            }
        default:
            // A layout: a header bar, a headline block, three cards.
            context.setFillColor(color(2))
            context.fill(CGRect(x: 0, y: bounds.height - bounds.height * 0.1, width: bounds.width, height: bounds.height * 0.1))
            context.setFillColor(color(1))
            context.fill(CGRect(x: bounds.width * 0.08, y: bounds.height * 0.5, width: bounds.width * 0.55, height: bounds.height * 0.22))
            for index in 0..<3 {
                context.setFillColor(color(2, 0.18))
                context.fill(CGRect(x: bounds.width * (0.08 + CGFloat(index) * 0.29), y: bounds.height * 0.1, width: bounds.width * 0.25, height: bounds.height * 0.3))
            }
        }
        return context.makeImage()!
    }

    static func writeJPEG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    // MARK: - A full world, for the captures

    /// A dozen sites, a dozen posts from three pages, eight mock-ups, all invented.
    func fill() throws {
        try store.saveSource(InspirationSourceRow(name: "Studio Exemple", link: "https://www.linkedin.com/company/studio-exemple/", color: "#E8B923",
                                                  lastReadAt: Self.day(11, 16), createdAt: Self.day(9, 1)))
        try store.saveSource(InspirationSourceRow(name: "Atelier Nord", link: "https://www.linkedin.com/company/atelier-nord/", color: "#3B82F6",
                                                  lastReadAt: Self.day(11, 16), createdAt: Self.day(9, 1)))
        try store.saveSource(InspirationSourceRow(name: "Galerie Exemple", link: "https://www.linkedin.com/company/galerie-exemple/",
                                                  lastError: "LinkedIn demande une connexion", createdAt: Self.day(9, 1)))
        let sites: [(String, String, [String: [String]])] = [
            ("Maison Lumière — Céramiques", "https://maison-lumiere.exemple.fr", ["secteur": ["maison"], "style": ["minimal", "éditorial"], "techno": ["scroll"]]),
            ("Atelier Nord", "https://www.atelier-nord.example.com", ["secteur": ["agence"], "style": ["brutaliste"], "techno": ["3d", "curseur"]]),
            ("Fondation Exemple", "https://fondation.exemple.fr/expositions", ["secteur": ["culture"], "style": ["typographique"], "typo": ["empattement"]]),
            ("Vélo Exemple", "https://velo.example.com", ["secteur": ["mobilité"], "style": ["coloré", "ludique"], "support": ["e-commerce"]]),
            ("Studio Exemple — Portfolio", "https://studio-exemple.example.com", ["secteur": ["portfolio"], "style": ["minimal"], "techno": ["transitions"]]),
            ("Café des Formes", "https://cafe-des-formes.exemple.fr", ["secteur": ["alimentation"], "style": ["rétro", "illustratif"]]),
            ("Banque Exemple", "https://banque.example.com", ["secteur": ["finance"], "style": ["corporate", "sombre"], "techno": ["shaders"]]),
            ("Revue Exemple", "https://revue.exemple.fr", ["secteur": ["culture"], "style": ["éditorial"], "typo": ["display"]]),
            ("Parfums Exemple", "https://parfums.example.com", ["secteur": ["beauté"], "style": ["luxe", "photographique"]]),
            ("Festival Exemple", "https://festival.exemple.fr", ["secteur": ["événement"], "style": ["coloré"], "techno": ["motion"]]),
            ("Outil Exemple", "https://outil.example.com", ["secteur": ["tech"], "style": ["bento", "clair"], "support": ["produit"]]),
            ("Herbier Exemple", "https://herbier.exemple.fr", ["secteur": ["culture"], "style": ["organique"], "techno": ["scroll"]]),
        ]
        for (index, site) in sites.enumerated() {
            try website(site.0, url: site.1, on: Self.day(11, 16 - index), categories: site.2,
                        text: "Un site inventé pour les essais : une page d'accueil, des projets, un contact.", image: index,
                        fonts: index % 3 == 0 ? ["Exemple Sans", "Exemple Serif"] : [], client: index % 4 == 0 ? "Client Exemple" : nil)
        }
        let posts: [(String, String?, [String], [String: [String]], Int)] = [
            ("Café Nord — identité", "Studio Exemple", ["Studio Exemple"], ["secteur": ["restaurant"], "style": ["chaleureux"], "support": ["logo", "packaging"]], 3),
            ("Fondation Exemple", "Atelier Nord", ["Atelier Nord", "Studio Exemple"], ["secteur": ["culture"], "style": ["typographique"], "typo": ["empattement"]], 4),
            ("Marque Exemple", "Galerie Exemple", ["Galerie Exemple"], ["secteur": ["mode"], "style": ["luxe", "élégant"], "support": ["wordmark"]], 2),
            ("Brasserie des Quais", "Studio Exemple", ["Studio Exemple"], ["secteur": ["boisson"], "style": ["rétro"], "support": ["packaging", "enseigne"]], 3),
            ("Ville Exemple", "Atelier Nord", ["Atelier Nord"], ["secteur": ["ville"], "style": ["géométrique"], "support": ["signalétique"]], 1),
            ("Clinique Exemple", "Atelier Nord", ["Atelier Nord"], ["secteur": ["santé"], "style": ["minimal"], "support": ["symbole"]], 2),
            ("Librairie Exemple", "Galerie Exemple", ["Galerie Exemple"], ["secteur": ["culture"], "style": ["éditorial"], "typo": ["script"]], 3),
            ("Énergie Exemple", "Studio Exemple", ["Studio Exemple"], ["secteur": ["énergie"], "style": ["audacieux", "coloré"]], 2),
            ("Hôtel Exemple", "Atelier Nord", ["Atelier Nord"], ["secteur": ["hospitalité"], "style": ["héritage"], "support": ["papeterie"]], 4),
            ("Club Exemple", "Studio Exemple", ["Studio Exemple"], ["secteur": ["sport"], "style": ["urbain"], "support": ["merchandising"]], 1),
        ]
        for (index, post) in posts.enumerated() {
            let urn = String(7_390_000_000_000_000_000 + index * 1_000)
            try branding(post.0, urn: urn, on: Self.day(11, 15 - index), studio: post.1, sources: post.2, categories: post.3,
                         text: "Une identité inventée pour les essais : un logo, une palette, une typographie, des applications.\n\nPhotographies et textes fictifs.",
                         images: Array((0..<post.4).map { 20 + index * 5 + $0 }),
                         links: index == 1 ? ["https://fondation.exemple.fr", "https://studio-exemple.example.com/projets/fondation"] : [])
        }
        let mockups: [(String, [String])] = [
            ("Affiche urbaine", ["affiche", "signaletique"]), ("Carte de visite", ["business card", "papeterie"]), ("Boîte", ["boite"]),
            ("Livre ouvert", ["livre"]), ("Tote bag", ["tote bag", "sac"]), ("Vitrine", ["fenetre", "signaletique"]),
            ("Écran de téléphone", ["iphone", "ecran"]), ("Magazine", ["magazine"]),
        ]
        for (index, item) in mockups.enumerated() {
            try mockup(item.0, folder: item.0, on: Self.day(10, 28 - index), types: item.1, image: 60 + index)
        }
    }
}
