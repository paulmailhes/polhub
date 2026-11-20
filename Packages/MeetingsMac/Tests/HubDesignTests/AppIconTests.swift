import AppKit
import SwiftUI
import Testing
@testable import HubDesign

/// The app's icons (15/11): Phosphor's SVGs, read as templates, drawn at the exact pixels shown.
@MainActor @Suite struct AppIconTests {
    @Test(arguments: AppIcon.allCases) func everyIconLoadsAsATemplate(_ icon: AppIcon) throws {
        let image = try #require(IconCache.image(icon), "Icons/\(icon.glyph)-duotone.svg")
        #expect(image.isTemplate)
        #expect(image.size.width > 0 && image.size.height > 0)
        #expect(icon.nsImage.isTemplate)
        let bitmap = try #require(IconCache.bitmap(icon, pixels: 36))
        #expect(Pixels(bitmap).alphas.contains { $0 > 200 }, "\(icon) est vide")
    }

    @Test func everyPlaceHasItsOwnGlyph() {
        #expect(Set(AppIcon.allCases.map(\.glyph)).count == AppIcon.allCases.count)
    }

    @Test func theLicenseShipsWithTheIcons() throws {
        let url = try #require(Bundle.module.url(forResource: "LICENSE-Phosphor", withExtension: "txt", subdirectory: "Icons"))
        #expect(try String(contentsOf: url, encoding: .utf8).contains("MIT License"))
    }

    /// Tinted by the foreground style, and drawn at 2× without being resampled: the same pixels as the vector.
    @Test func anIconTakesTheForegroundColorAndStaysSharp() throws {
        let renderer = ImageRenderer(content: AppIconImage(.projects, size: 18).foregroundStyle(Color(red: 1, green: 0, blue: 0)))
        renderer.scale = 2
        let shown = Pixels(try #require(renderer.cgImage))
        #expect(shown.width == 36 && shown.height == 36)
        let reference = Pixels(try #require(IconCache.bitmap(.projects, pixels: 36)))
        let difference = zip(shown.alphas, reference.alphas).map { abs(Int($0) - Int($1)) }
        #expect(Double(difference.reduce(0, +)) / Double(difference.count) < 2, "rééchantillonnée")
        #expect(shown.alphas.contains(255))
        // Every visible pixel is red: the template takes the color given.
        for index in shown.alphas.indices where shown.alphas[index] > 128 {
            let (red, green, blue) = shown.rgb(index)
            #expect(red > 200 && green < 40 && blue < 40)
        }
    }

    @Test func aLabelKeepsItsTitle() {
        let host = NSHostingView(rootView: AppLabel("Projets", icon: .projects))
        #expect(host.fittingSize.width > 18)
    }
}

/// The RGBA pixels of a bitmap, premultiplied, top row first.
struct Pixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        self.bytes = bytes
    }

    var alphas: [UInt8] { stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] } }

    /// The color of a pixel, out of its premultiplication.
    func rgb(_ index: Int) -> (Int, Int, Int) {
        let alpha = max(1, Int(bytes[index * 4 + 3]))
        return (Int(bytes[index * 4]) * 255 / alpha, Int(bytes[index * 4 + 1]) * 255 / alpha, Int(bytes[index * 4 + 2]) * 255 / alpha)
    }
}

/// The contact sheet of the icons, to look at: `HUB_SNAPSHOTS=<dossier> swift test --filter AppIconSheetTests`.
/// Every icon at 18 and 32 points, in light and dark, then a sidebar with the SF Symbols of before and these.
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["HUB_SNAPSHOTS"] != nil))
struct AppIconSheetTests {
    @Test func theContactSheet() throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["HUB_SNAPSHOTS"]), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let sheet = HStack(alignment: .top, spacing: 0) {
            IconSheet().environment(\.colorScheme, .light).background(Color(white: 0.97))
            IconSheet().environment(\.colorScheme, .dark).background(Color(white: 0.13))
        }
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: output.appending(path: "icones.png"))
    }

    /// In a real sidebar `List`, offscreen: the tint, the selection and the size against the SF Symbols.
    @Test func theSidebar() throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["HUB_SNAPSHOTS"]), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for dark in [false, true] {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SidebarSample()))
            window.setContentSize(NSSize(width: 640, height: 340))
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            window.layoutIfNeeded()
            let content = try #require(window.contentView)
            let bitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: output.appending(path: dark ? "icones-barre-sombre.png" : "icones-barre-claire.png"))
        }
    }
}

private struct IconSheet: View {
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
            ForEach(AppIcon.allCases, id: \.self) { icon in
                GridRow {
                    AppIconImage(icon, size: 32).foregroundStyle(Color.accentColor)
                    AppIconImage(icon, size: 32).foregroundStyle(.primary)
                    AppIconImage(icon, size: 18).foregroundStyle(.primary)
                    AppIconImage(icon, size: 18).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(icon.rawValue).font(.system(size: 13, weight: .semibold))
                        Text(icon.glyph).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .frame(width: 140, alignment: .leading)
                }
            }
        }
        .padding(20)
    }
}

/// The sidebar's sections as drawn on 15/11 (filled symbols, hierarchical, a tint per section), then with these icons.
private struct SidebarSample: View {
    private static let rows: [(title: String, symbol: String, icon: AppIcon, tint: String)] = [
        ("Accueil", "house.fill", .home, Palette.teal), ("Projets", "square.grid.3x2.fill", .projects, Palette.blue),
        ("Réunions", "waveform", .meetings, Palette.violet), ("Calendrier", "calendar", .calendar, Palette.orange),
        ("Mails", "envelope.fill", .mails, Palette.pink), ("Contacts", "person.2.fill", .contacts, Palette.green),
        ("Réglages", "gearshape.fill", .settings, Palette.gray),
    ]

    var body: some View {
        HStack(spacing: 0) {
            List(selection: .constant("Projets")) {
                Section("SF Symbols") {
                    ForEach(Self.rows, id: \.title) { row in
                        Label(row.title, systemImage: row.symbol).symbolRenderingMode(.hierarchical)
                            .listItemTint(.fixed(Color(hex: row.tint))).tag(row.title)
                    }
                }
            }
            .listStyle(.sidebar)
            ForEach([AppLabel.sidebarSize, 18], id: \.self) { size in
                List(selection: .constant("Projets")) {
                    Section("Phosphor \(Int(size)) pt") {
                        ForEach(Self.rows, id: \.title) { row in
                            AppLabel(row.title, icon: row.icon, size: size).listItemTint(.fixed(Color(hex: row.tint))).tag(row.title)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .environment(\.sidebarRowSize, .large)
        // Offscreen, the window is never key: drawn as the active one. The sections' tints only show on screen.
        .environment(\.appearsActive, true)
    }
}
