import SwiftUI

// The four roles of a button (design system v2, plan of 19/11). Nothing else draws a button in the content:
// - principal: `.primary`, full and matte at the accent, one per screen;
// - secondary: `.secondary`, a thin outline, the text's own color;
// - discreet: `IconButton` and `TextButton`, grey, a fill under the pointer;
// - row: `RowButtonStyle`, a whole line.
// No glass in the content (measured on 19/11: in a window that is not in front, a glass button looks disabled); the
// glass stays for the toolbar, the popovers and the floating bars.

/// The principal action of a screen: full and matte, at the accent; its label is the accent's opposite.
public struct PrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        RoleButtonBody(configuration: configuration, primary: true)
    }
}

/// A secondary action: a thin outline, the text's own color, a fill under the pointer.
public struct SecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        RoleButtonBody(configuration: configuration, primary: false)
    }
}

private struct RoleButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let primary: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.controlSize) private var size

    var body: some View {
        let metrics = RoleButton.metrics(size)
        let shape = RoundedRectangle(cornerRadius: RoleButton.radius, style: .continuous)
        configuration.label
            .font(.system(size: metrics.text, weight: primary ? .semibold : .medium))
            .foregroundStyle(primary ? Tint.onAccent.color : Color.primary)
            .padding(.horizontal, metrics.padding)
            .frame(minHeight: metrics.height)
            .background {
                if primary {
                    shape.fill(Tint.accent.opacity(configuration.isPressed ? 0.72 : hovering ? 0.86 : 1))
                } else {
                    shape.fill(configuration.isPressed ? Surface.raised : hovering ? Surface.fill : Color.clear)
                        .overlay { shape.strokeBorder(Color.primary.opacity(0.18)) }
                }
            }
            .opacity(enabled ? 1 : 0.4)
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
    }
}

/// The measures of the principal and secondary buttons: 28 points high by default, as the system's own; the
/// `.controlSize` around them says smaller or larger, as for the system's buttons.
public enum RoleButton {
    public static let height: CGFloat = 28
    public static let padding: CGFloat = 12
    public static let radius: CGFloat = 8

    public struct Metrics: Equatable, Sendable {
        public let height: CGFloat
        public let padding: CGFloat
        public let text: CGFloat
    }

    public static func metrics(_ size: ControlSize) -> Metrics {
        switch size {
        case .mini: Metrics(height: 18, padding: 6, text: 11)
        case .small: Metrics(height: 22, padding: 9, text: 12)
        case .large: Metrics(height: 34, padding: 16, text: 14)
        case .extraLarge: Metrics(height: 40, padding: 18, text: 15)
        default: Metrics(height: height, padding: padding, text: 13)
        }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    public static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    public static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// A band of information (design system v2): only its icon carries the color of what it says; the text stays the
/// text's own, its actions on the right.
public struct Banner<Actions: View>: View {
    public enum Tone: Sendable {
        case information, attention, late, done, agent

        var icon: String {
            switch self {
            case .information: "info.circle"
            case .attention: "exclamationmark.triangle"
            case .late: "clock.badge.exclamationmark"
            case .done: "checkmark.circle"
            case .agent: "sparkles"
            }
        }

        var color: Color {
            switch self {
            case .information: Color.secondary
            case .attention: Tint.attention
            case .late: Tint.late
            case .done: Tint.done
            case .agent: Tint.agent
            }
        }
    }

    let tone: Tone
    let title: String
    let detail: String?
    let actions: Actions

    public init(_ tone: Tone, _ title: String, detail: String? = nil, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.tone = tone
        self.title = title
        self.detail = detail
        self.actions = actions()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: Space.m) {
            Image(systemName: tone.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tone.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let detail { Text(detail).font(.system(size: 13)).foregroundStyle(.secondary) }
            }
            Spacer(minLength: Space.m)
            actions
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Surface.fill)
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Surface.stroke) }
        }
    }
}

/// A problem said in one line (design system v2, 19/11): the icon of attention in its color, the sentence in the
/// text's own color, never a colored sentence. Its font is the one around it.
public struct ErrorLine: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Label {
            Text(text).foregroundStyle(.primary)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tint.attention)
        }
    }
}
