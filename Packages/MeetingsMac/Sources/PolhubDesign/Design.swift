import AppKit
import SwiftUI

// Polhub's design system (14/11): the rules are in docs/design-system.md. Glass belongs to the navigation
// layer and to floating controls; content sits on calm, continuous rounded surfaces.

/// Spacing, on a 4-point grid.
public enum Space {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
}

/// Text read all day sits a step above the system's 13-point body, and nothing to read goes under 12 points
/// (Paul, 15/11: « tout est un peu petit… trop serré et illisible »).
public enum TextSize {
    /// The first line of a row: who, or what.
    public static let rowTitle: CGFloat = 15
    /// The second line of a row, and text to read in a list.
    public static let rowBody: CGFloat = 14
    /// Dates, addresses, counts, explanations.
    public static let meta: CGFloat = 13
    /// A label in a capsule; the smallest text of the app.
    public static let tag: CGFloat = 12
    /// The body of a message, in CSS pixels.
    public static let reading: CGFloat = 15
}

extension Font {
    /// 15 points: the first line of a row.
    public static let rowTitle = Font.system(size: TextSize.rowTitle)
    /// 14 points: the second line of a row.
    public static let rowBody = Font.system(size: TextSize.rowBody)
    /// 13 points: dates, addresses, counts.
    public static let meta = Font.system(size: TextSize.meta)
    /// 12 points: a label in a capsule.
    public static let tag = Font.system(size: TextSize.tag)
}

/// Corner radii, always with the continuous style.
public enum Radius {
    public static let small: CGFloat = 6
    public static let control: CGFloat = 10
    public static let card: CGFloat = 16
    public static let hero: CGFloat = 22
}

/// The width and margins of a page's content.
public enum PageMetrics {
    public static let maxWidth: CGFloat = 1_080
    public static let readingWidth: CGFloat = 860
    public static let horizontal: CGFloat = 28
    public static let top: CGFloat = 16
    public static let bottom: CGFloat = 40
}

/// Content surfaces: a hint of the text color over the window, so they read in light and dark alike.
public enum Surface {
    public static let fill = Color.primary.opacity(0.045)
    public static let raised = Color.primary.opacity(0.07)
    public static let stroke = Color.primary.opacity(0.08)
    public static let selected = Color.accentColor.opacity(0.12)
}

/// The mails' list, as Gmail's (Paul, 15/11: « quand le mail n'est pas ouvert il est bien blanc, ouvert un peu
/// plus bleu-gris »): an unread thread on the brightest ground, a read one a step down.
public enum MailSurface {
    public static let unread = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(srgbRed: 0.165, green: 0.169, blue: 0.180, alpha: 1) : .white
    })
    public static let read = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(srgbRed: 0.106, green: 0.110, blue: 0.118, alpha: 1) : NSColor(srgbRed: 0.949, green: 0.965, blue: 0.988, alpha: 1)
    })
    /// A thread ticked, as Gmail's light blue.
    public static let ticked = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(srgbRed: 0.17, green: 0.25, blue: 0.38, alpha: 1) : NSColor(srgbRed: 0.761, green: 0.859, blue: 1, alpha: 1)
    })
    /// Gmail's blue, for the boxes ticked and the people's tab, whatever the system's accent.
    public static let blue = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(srgbRed: 0.54, green: 0.71, blue: 0.97, alpha: 1) : NSColor(srgbRed: 0.04, green: 0.34, blue: 0.82, alpha: 1)
    })
    /// The thin line between two threads.
    public static let line = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(white: 1, alpha: 0.07) : NSColor(srgbRed: 0.39, green: 0.47, blue: 0.56, alpha: 0.14)
    })
}

extension NSAppearance {
    public var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

/// The one palette of the app: accounts, projects and statuses take their colors here.
public enum Palette {
    public static let violet = "#8B5CF6"
    public static let green = "#22A06B"
    public static let orange = "#F97316"
    public static let blue = "#3B82F6"
    public static let pink = "#EC4899"
    public static let teal = "#14B8A6"
    public static let red = "#EF4444"
    public static let yellow = "#EAB308"
    public static let brown = "#8B5E3C"
    public static let gray = "#8E8E93"
}

extension Color {
    /// `#RRGGBB`.
    public init(hex: String) {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

/// A page: scrolls, keeps its width, and the same margins everywhere.
public struct Page<Content: View>: View {
    let maxWidth: CGFloat
    let spacing: CGFloat
    let content: Content

    public init(maxWidth: CGFloat = PageMetrics.maxWidth, spacing: CGFloat = Space.xl, @ViewBuilder content: () -> Content) {
        self.maxWidth = maxWidth
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) { content }
                .padding(.horizontal, PageMetrics.horizontal)
                .padding(.top, PageMetrics.top)
                .padding(.bottom, PageMetrics.bottom)
                .frame(maxWidth: maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

/// A page's title and the line under it.
public struct PageHeader<Accessory: View>: View {
    let title: String
    let subtitle: String?
    let accessory: Accessory

    public init(_ title: String, subtitle: String? = nil, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).font(.largeTitle.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                if let subtitle { Text(subtitle).font(.title3).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            accessory
        }
    }
}

/// A content surface.
public struct Card<Content: View>: View {
    let padding: CGFloat
    let content: Content

    public init(padding: CGFloat = Space.l, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.m) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .cardSurface()
    }
}

extension View {
    /// The card's background and edge.
    public func cardSurface(radius: CGFloat = Radius.card, fill: Color = Surface.fill) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Surface.stroke))
    }
}

/// The title of a part of a page or of a card, with an optional count and trailing control.
public struct SectionTitle<Trailing: View>: View {
    let title: String
    let systemImage: String?
    let count: Int?
    let trailing: Trailing

    public init(_ title: String, systemImage: String? = nil, count: Int? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.systemImage = systemImage
        self.count = count
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            if let systemImage {
                Label(title, systemImage: systemImage).font(.headline)
            } else {
                Text(title).font(.headline)
            }
            if let count { Text("\(count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
            trailing
        }
    }
}

/// A small tinted capsule: a status, a date, a tag.
public struct Chip: View {
    let text: String
    let systemImage: String?
    let tint: Color?
    @Environment(\.self) private var environment

    public init(_ text: String, systemImage: String? = nil, tint: Color? = nil) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: Space.xs) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text).lineLimit(1)
        }
        .font(.tag.weight(.semibold))
        .padding(.horizontal, Space.s)
        .padding(.vertical, 3)
        // Its text in a shade of its color that reads (correctifs, 15/11), its fill in the color itself.
        .foregroundStyle(tint.map { $0.readable(in: environment) } ?? .secondary)
        .background((tint ?? .secondary).opacity(0.14), in: Capsule())
    }
}

/// Someone's initials in a soft circle.
public struct Avatar: View {
    let initials: String
    let size: CGFloat
    let tint: Color

    public init(_ initials: String, size: CGFloat = 30, tint: Color = .accentColor) {
        self.initials = initials
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .frame(width: size, height: size)
            .foregroundStyle(tint)
            .background(tint.opacity(0.16), in: Circle())
    }
}

/// A colored dot: an account, a status, a project.
public struct ColorDot: View {
    let color: Color
    let size: CGFloat

    public init(_ color: Color, size: CGFloat = 9) {
        self.color = color
        self.size = size
    }

    public var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

/// Controls floating over the content, at the bottom of a page: a capsule of glass.
public struct FloatingBar<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.s + 2)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, Space.xl)
            .padding(.bottom, Space.l)
    }
}

/// The window's title and subtitle, from the page shown: the main window is made by hand and SwiftUI does not
/// pass `navigationTitle` to it (measured on 14/11).
public struct WindowTitle: NSViewRepresentable {
    let title: String
    let subtitle: String

    public func makeNSView(context: Context) -> NSView { NSView() }

    public func updateNSView(_ view: NSView, context: Context) {
        let title = title, subtitle = subtitle
        DispatchQueue.main.async {
            view.window?.title = title
            view.window?.subtitle = subtitle
        }
    }
}

extension View {
    /// Names the window after this page.
    public func windowTitle(_ title: String, subtitle: String = "") -> some View {
        background(WindowTitle(title: title, subtitle: subtitle).frame(width: 0, height: 0))
    }
}

/// A page opened over its list, which stays in sight behind (Paul, 14/11: « on rentre beaucoup »). A click
/// outside, or Échap, closes it.
public struct FloatingPanel<Content: View>: View {
    let close: () -> Void
    let content: Content

    public init(close: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.close = close
        self.content = content()
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
                .transition(.opacity)
            content
                .frame(maxWidth: 1_040, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: Radius.hero, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: Radius.hero, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.hero, style: .continuous).strokeBorder(Surface.stroke))
                .shadow(color: .black.opacity(0.3), radius: 36, y: 14)
                .padding(.horizontal, Space.xl)
                .padding(.top, Space.m)
                .padding(.bottom, Space.l)
                .transition(.scale(scale: 0.97).combined(with: .opacity))
        }
        .onExitCommand(perform: close)
    }
}

/// The round close button of a floating panel.
public struct PanelCloseButton: View {
    let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) { Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 28, height: 28) }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help("Fermer (Échap)")
            .keyboardShortcut(.cancelAction)
    }
}
