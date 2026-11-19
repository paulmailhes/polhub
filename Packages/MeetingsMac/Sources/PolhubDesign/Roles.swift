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

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RoleButton.radius, style: .continuous)
        configuration.label
            .font(.system(size: 13, weight: primary ? .semibold : .medium))
            .foregroundStyle(primary ? Tint.onAccent.color : Color.primary)
            .padding(.horizontal, RoleButton.padding)
            .frame(minHeight: RoleButton.height)
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

/// The measures of the principal and secondary buttons.
public enum RoleButton {
    public static let height: CGFloat = 28
    public static let padding: CGFloat = 12
    public static let radius: CGFloat = 8
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
