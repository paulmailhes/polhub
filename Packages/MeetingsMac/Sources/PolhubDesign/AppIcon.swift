import AppKit
import SwiftUI

// The app's own icons (15/11): Paul found the SF Symbols of the sidebar « très basiques ». They are Phosphor
// Icons (https://phosphoricons.com, MIT license, in Icons/LICENSE-Phosphor.txt), duotone weight: a line drawing
// with a light fill. Each SVG is a template, tinted by `.foregroundStyle` like a symbol, in light and dark alike.

/// A place or a mail folder of the app, and the Phosphor glyph that draws it.
public enum AppIcon: String, CaseIterable, Sendable {
    // The sidebar.
    case home, projects, meetings, calendar, mails, contacts, settings
    /// The notifications center.
    case bell
    // The mail folders.
    case inbox, sent, drafts, scheduled
    /// The mail folder « Notifications », drawn apart from the center's bell.
    case notifications
    case subscriptions, spam, trash, allMail
    /// « Nouveau mail ».
    case newMail
    /// « Inspiration » and its three pages (16/11).
    case inspiration, websites, branding, mockups

    /// The Phosphor glyph, shipped as `Icons/<glyph>-duotone.svg`. To change an icon: copy the new SVG from
    /// `@phosphor-icons/core` (`assets/duotone/`; those of 16/11 come from version 2.1.1) into Icons/, then change
    /// its name here.
    public var glyph: String {
        switch self {
        case .home: "house"
        case .projects: "folders"
        case .meetings: "microphone"
        case .calendar: "calendar-dots"
        case .mails: "envelope-simple"
        case .contacts: "address-book"
        case .settings: "gear-six"
        case .bell: "bell"
        case .inbox: "tray"
        case .sent: "paper-plane-tilt"
        case .drafts: "file-text"
        case .scheduled: "clock-countdown"
        case .notifications: "bell-simple-ringing"
        case .subscriptions: "newspaper"
        case .spam: "warning-octagon"
        case .trash: "trash"
        case .allMail: "stack"
        case .newMail: "note-pencil"
        case .inspiration: "lightbulb"
        case .websites: "globe"
        case .branding: "palette"
        case .mockups: "frame-corners"
        }
    }

    /// The icon as an AppKit template image, still vector (a menu, an AppKit toolbar). Empty if its SVG is missing.
    @MainActor public var nsImage: NSImage {
        IconCache.image(self) ?? NSImage(size: NSSize(width: 256, height: 256))
    }
}

/// The icons read once, then their bitmaps at each size and screen scale: drawn at the exact pixels shown, so
/// they stay as sharp as the vector at any size (SwiftUI, given the SVG itself, resamples it and blurs it a little).
@MainActor
enum IconCache {
    private static var images: [AppIcon: NSImage] = [:]
    private static var bitmaps: [BitmapKey: CGImage] = [:]

    private struct BitmapKey: Hashable {
        let icon: AppIcon
        let pixels: Int
    }

    /// The SVG of the icon, as a template image; nil if the file is missing or unreadable.
    static func image(_ icon: AppIcon) -> NSImage? {
        if let image = images[icon] { return image }
        guard let url = Bundle.module.url(forResource: "\(icon.glyph)-duotone", withExtension: "svg", subdirectory: "Icons"),
              let data = try? Data(contentsOf: url), let image = NSImage(data: data) else { return nil }
        image.isTemplate = true
        images[icon] = image
        return image
    }

    /// The icon drawn in a square of `pixels` pixels; only its alpha counts, the color comes from the view.
    static func bitmap(_ icon: AppIcon, pixels: Int) -> CGImage? {
        let key = BitmapKey(icon: icon, pixels: pixels)
        if let bitmap = bitmaps[key] { return bitmap }
        guard pixels > 0, let image = image(icon),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        guard let bitmap = context.makeImage() else { return nil }
        bitmaps[key] = bitmap
        return bitmap
    }
}

/// An icon of the app, in a square of `size` points, tinted by `.foregroundStyle` (or the sidebar's tint) as an
/// SF Symbol is.
public struct AppIconImage: View {
    private let icon: AppIcon
    private let size: CGFloat
    @Environment(\.displayScale) private var displayScale

    public init(_ icon: AppIcon, size: CGFloat = 18) {
        self.icon = icon
        self.size = size
    }

    public var body: some View {
        let pixels = max(1, Int((size * displayScale).rounded()))
        Group {
            if let bitmap = IconCache.bitmap(icon, pixels: pixels) {
                Image(decorative: bitmap, scale: CGFloat(pixels) / size).renderingMode(.template).resizable()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
    }
}

/// `Label(title, systemImage:)` with an icon of the app: for a sidebar row, a menu item, a toolbar button.
public struct AppLabel: View {
    /// The size of the sidebar's large rows: a Phosphor glyph fills three quarters of its square, so at 22 points
    /// it looks as large as the SF Symbol it replaces, without making the row taller. 16 to 18 for a menu or a toolbar.
    public static let sidebarSize: CGFloat = 22

    private let title: String
    private let icon: AppIcon
    private let size: CGFloat

    public init(_ title: String, icon: AppIcon, size: CGFloat = AppLabel.sidebarSize) {
        self.title = title
        self.icon = icon
        self.size = size
    }

    public var body: some View {
        Label {
            Text(title)
        } icon: {
            AppIconImage(icon, size: size)
        }
    }
}
