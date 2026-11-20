import AppKit
import SwiftUI

// hub's design system (14/11): the rules are in docs/design-system.md. Glass belongs to the navigation
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

/// Corner radii, always with the continuous style (design system v2, 19/11): three, and the capsule.
public enum Radius {
    /// What is clicked: a button, a row, a field, a chip.
    public static let control: CGFloat = 8
    /// Inside a card: a tile, an image, a quote, a band.
    public static let inner: CGFloat = 12
    /// A card, a panel, a sheet.
    public static let card: CGFloat = 16
    /// Before 19/11: 6. Now `control`.
    @available(*, deprecated, renamed: "control")
    public static let small: CGFloat = control
    /// Before 19/11: 22. Now `card`.
    @available(*, deprecated, renamed: "card")
    public static let hero: CGFloat = card
}

/// The width and margins of a page's content.
public enum PageMetrics {
    public static let maxWidth: CGFloat = 1_080
    public static let readingWidth: CGFloat = 860
    public static let horizontal: CGFloat = 28
    public static let top: CGFloat = 16
    public static let bottom: CGFloat = 40
    /// Inside every card, the Accueil's twenty points (design system v2; lot 8, 19/11: the pages' cards had 16, a
    /// meeting's summary 24).
    public static let cardPadding: CGFloat = 20
    /// Between two cards of a page (design system v2; lot 8, 19/11); 24 stays between a page's header and its cards.
    public static let cardGap: CGFloat = Space.l
}

/// Content surfaces: a hint of the text color over the window, so they read in light and dark alike.
public enum Surface {
    public static let fill = Color.primary.opacity(0.045)
    public static let raised = Color.primary.opacity(0.07)
    public static let stroke = Color.primary.opacity(0.08)
    /// What is chosen: the app's accent (ink), lightly.
    public static let selected = Tint.accent.opacity(0.12)
    /// Paul's bubble in Colin's thread: a light grey, a little more in the dark (the Accueil's pass, 18/11).
    public static let bubble = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor.white.withAlphaComponent(0.11) : NSColor.black.withAlphaComponent(0.055)
    })
}

/// The mails' list, as Gmail's (Paul, 15/11: « quand le mail n'est pas ouvert il est bien blanc, ouvert un peu
/// plus bleu-gris »): an unread thread on the brightest ground, a read one a step down.
public enum MailSurface {
    /// The grey of a read thread, as a white: a soft step from the window, white in light and #1E1E1E in dark (lot 6, 19/11:
    /// at 0.955 and 0.158, the read lines made grey bands that weighed more than the unread ones).
    public static let readWhite: (light: CGFloat, dark: CGFloat) = (0.972, 0.145)
    /// The window's own ground, as on every page (Paul, 15/11: « la même couleur que dans tout le reste »).
    public static let unread = Color(nsColor: .windowBackgroundColor)
    /// A soft step down (Paul, 15/11: « ouvert un peu plus bleu-gris »), opaque: the line's own ground under its shadow.
    public static let read = Color(nsColor: NSColor(name: nil) { appearance in
        NSColor(white: appearance.isDark ? readWhite.dark : readWhite.light, alpha: 1)
    })
    /// A thread ticked: the selection's accent (ink), as everywhere in the app; opaque, the gestures cover the line.
    public static let ticked = Color(nsColor: NSColor(name: nil) { appearance in
        var color = NSColor.white
        appearance.performAsCurrentDrawingAppearance {
            let ground = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? .white
            let ink = appearance.isDark ? Tint.ink.dark : Tint.ink.light
            let accent = NSColor(srgbRed: ink.red, green: ink.green, blue: ink.blue, alpha: 1)
            // Measured on 19/11: at 9 % in light, a ticked line was 6 levels off a read one, and passed for one.
            color = ground.blended(withFraction: appearance.isDark ? 0.2 : 0.17, of: accent) ?? ground
        }
        return color
    })
    /// The boxes ticked and the line the keys are on: the app's accent.
    public static let accent = Tint.accent
    /// The thin line between two threads.
    public static let line = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(white: 1, alpha: 0.07) : NSColor(white: 0, alpha: 0.08)
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
    /// The Dictée's (20/11).
    public static let indigo = "#6366F1"
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
                // French typography, laid at display (`Words.typeset`, lot 10, 20/11).
                Text(Words.typeset(title)).font(.largeTitle.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                if let subtitle { Text(Words.typeset(subtitle)).font(.title3).foregroundStyle(.secondary) }
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

    public init(padding: CGFloat = PageMetrics.cardPadding, @ViewBuilder content: () -> Content) {
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
            // French typography, laid at display (`Words.typeset`, lot 10, 20/11).
            if let systemImage {
                Label(Words.typeset(title), systemImage: systemImage).font(.headline)
            } else {
                Text(Words.typeset(title)).font(.headline)
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
    let dot: Color?
    @Environment(\.self) private var environment

    /// `dot`: a color of identity (a status, a project) before the text, which stays neutral (lot 8, 19/11): an identity
    /// never colors a text.
    public init(_ text: String, systemImage: String? = nil, tint: Color? = nil, dot: Color? = nil) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
        self.dot = dot
    }

    public var body: some View {
        HStack(spacing: Space.xs) {
            if let dot { ColorDot(dot, size: 8) }
            if let systemImage { Image(systemName: systemImage) }
            // French typography, laid at display (`Words.typeset`, lot 10, 20/11).
            Text(Words.typeset(text)).lineLimit(1)
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
    @Environment(\.self) private var environment

    public init(_ initials: String, size: CGFloat = 30, tint: Color = .secondary) {
        self.initials = initials
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .frame(width: size, height: size)
            // The initials in a shade of their color that reads on its circle, as a chip's text (lot 10, 20/11: the raw
            // color, a yellow or an orange under 4.5:1); the grey of nobody stays as it is.
            .foregroundStyle(tint == .secondary ? tint : tint.readable(in: environment))
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

/// Controls floating over the content, at the bottom of a page: a capsule of glass; with `cornerRadius`, a rounded
/// rectangle, for a field that grows over several lines (Colin's bar, 18/11).
public struct FloatingBar<Content: View>: View {
    let content: Content
    let cornerRadius: CGFloat?

    public init(cornerRadius: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        Group {
            if let cornerRadius {
                content
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.s + 2)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                content
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.s + 2)
                    .glassEffect(.regular, in: .capsule)
            }
        }
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

    /// A scrolling area that starts under the toolbar instead of passing beneath it (19/11). A scroll view that
    /// touches the top of the window gets a blurred backdrop there, as wide as itself: narrower than the page (the
    /// Accueil's cards, Réunions' list), it drew a box over the content that looked like a control. Measured on
    /// macOS 27: neither `scrollEdgeEffectStyle`, `scrollEdgeEffectHidden` nor `toolbarBackgroundVisibility`
    /// removes it; one point of distance does.
    public func belowToolbar() -> some View {
        padding(.top, 1)
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
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Surface.stroke))
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
            // Neutral glass, whatever the tint around (measured on 19/11: a tinted glass button looks like a principal one).
            .tint(nil)
            // « Fermer (Échap) », by `Words.help` (lot 10, 20/11).
            .help(Words.help("Fermer", .escape))
            .keyboardShortcut(.cancelAction)
    }
}
