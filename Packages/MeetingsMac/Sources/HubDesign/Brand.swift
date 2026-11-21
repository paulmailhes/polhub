import SwiftUI

// hub's own look (21/11, Paul: « brander le truc… utiliser plus ce système de couleurs… dans les icônes sur la gauche…
// comme du Notion »; his choices: the pages as Notion's, colored badges in the sidebar, the Mac's glass kept). A tool is
// drawn the same everywhere — the sidebar, Réglages, the add-ons, the Bienvenue, a page's header —: its Phosphor glyph
// in white on a rounded square of its color.

/// A tool's mark: its glyph in white on a rounded square of its color.
public struct ToolBadge: View {
    public enum Size: CGFloat, Sendable, CaseIterable {
        /// A tag, a mention in a sentence.
        case mini = 18
        /// A row of the sidebar.
        case sidebar = 24
        /// A line of a list.
        case row = 32
        /// An add-on's line, a choice of the Bienvenue.
        case line = 40
        /// A page's header.
        case header = 56

        /// The square's corners: a little over a quarter of its side, as an app's icon.
        public var radius: CGFloat { (rawValue * 0.27).rounded() }
        /// The glyph inside: a Phosphor glyph fills three quarters of its box, so at 70 % of the square it keeps a margin
        /// as wide as an app icon's.
        public var glyph: CGFloat { (rawValue * 0.7).rounded() }
    }

    private let icon: AppIcon
    private let color: String
    private let size: Size
    private let muted: Bool

    /// `muted`: an add-on not installed, greyed.
    public init(_ icon: AppIcon, color: String, size: Size, muted: Bool = false) {
        self.icon = icon
        self.color = color
        self.size = size
        self.muted = muted
    }

    public var body: some View {
        AppIconImage(icon, size: size.glyph)
            .foregroundStyle(.white)
            .frame(width: size.rawValue, height: size.rawValue)
            .background(Color(hex: color), in: RoundedRectangle(cornerRadius: size.radius, style: .continuous))
            .saturation(muted ? 0 : 1)
            .opacity(muted ? 0.45 : 1)
            .accessibilityHidden(true)
    }
}

/// The top of a page, as Notion's: its tool's badge, a large title, one line on what the page holds.
public struct ToolHeader: View {
    private let icon: AppIcon
    private let color: String
    private let title: String
    private let subtitle: String?

    public init(_ title: String, icon: AppIcon, color: String, subtitle: String? = nil) {
        self.title = title
        self.icon = icon
        self.color = color
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ToolBadge(icon, color: color, size: .header)
                .padding(.bottom, Space.s)
            Text(title)
                .font(.pageTitle)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(Words.typeset(subtitle))
                    .font(.pageSubtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The title of a part of a page, as Notion's: small, semibold, grey, a line under it; something to do on its right.
public struct PartTitle<Trailing: View>: View {
    private let title: String
    private let trailing: Trailing

    public init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        VStack(spacing: Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.meta.weight(.semibold)).foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.m)
                trailing
            }
            Rectangle().fill(Surface.stroke).frame(height: 1)
        }
    }
}

/// What a tool needs, on a soft tag (21/11, Paul: « les outils qui sont nécessaires, donc connexion Google, nécessaire
/// pour chaque truc qui a besoin d'une connexion Google »): with its check when it is there, in the color of attention
/// when it is missing, grey for what installing the tool will ask.
public struct NeedTag: View {
    public enum Kind: Sendable, Equatable {
        case done, missing, planned
    }

    private let title: String
    private let icon: AppIcon?
    private let kind: Kind

    public init(_ title: String, icon: AppIcon?, kind: Kind) {
        self.title = title
        self.icon = icon
        self.kind = kind
    }

    public var body: some View {
        HStack(spacing: Space.xs) {
            if let icon { AppIconImage(icon, size: TextSize.tag + 2) }
            Text(Words.typeset(title)).font(.tag.weight(.medium)).lineLimit(1)
            if kind == .done { AppIconImage(.checked, size: TextSize.tag + 1) }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs - 1)
        .background(background, in: RoundedRectangle(cornerRadius: Radius.tag, style: .continuous))
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title + (kind == .done ? ", fait" : kind == .missing ? ", à faire" : "")))
    }

    private var foreground: AnyShapeStyle {
        switch kind {
        case .done: AnyShapeStyle(Tint.done)
        case .missing: AnyShapeStyle(Tint.attention)
        case .planned: AnyShapeStyle(.secondary)
        }
    }

    private var background: AnyShapeStyle {
        switch kind {
        case .done: AnyShapeStyle(Tint.done.opacity(0.12))
        case .missing: AnyShapeStyle(Tint.attention.opacity(0.13))
        case .planned: AnyShapeStyle(Surface.raised)
        }
    }
}
