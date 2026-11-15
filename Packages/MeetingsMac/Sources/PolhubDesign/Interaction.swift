import SwiftUI

// Polhub's interaction layer (15/11): everything clickable answers the pointer and the press, and nothing moves
// in the layout when it does. The rules are in docs/design-system.md, « L'interaction ». `.hoverEffect` does not
// exist on macOS: every hover here comes from `onHover`.

/// The app's animations: one timing per kind of change.
public enum Motion {
    /// A hover, a press, a selection: at once.
    public static let quick: Animation = .snappy(duration: 0.15)
    /// Something that opens, closes, unfolds or moves.
    public static let standard: Animation = .snappy(duration: 0.25)
    /// A larger change of content.
    public static let gentle: Animation = .smooth(duration: 0.35)
}

// MARK: - Rows and cards

extension View {
    /// A row that answers the pointer: a rounded highlight behind it, the selection's color when `selected`.
    /// The row keeps its size: `inset` lets the highlight spill that far left and right of the row, so its text
    /// stays lined up with the card's edge.
    public func hoverRow(selected: Bool = false, radius: CGFloat = Radius.control, inset: CGFloat = 0) -> some View {
        modifier(HoverRow(selected: selected, radius: radius, inset: inset))
    }

    /// A card that rises under the pointer: a shadow, a touch larger, a firmer edge. It draws the card's edge
    /// itself: the card needs no other.
    public func cardHover(radius: CGFloat = Radius.card) -> some View {
        modifier(CardHover(radius: radius))
    }
}

struct HoverRow: ViewModifier {
    let selected: Bool
    let radius: CGFloat
    let inset: CGFloat
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    /// The selection wins over the hover; nothing at rest.
    static func fill(selected: Bool, hovering: Bool) -> Color {
        if selected { return Surface.selected }
        return hovering ? Surface.fill : .clear
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(.horizontal, inset)
            .background {
                shape.fill(Self.fill(selected: selected, hovering: hovering && enabled))
                    .animation(Motion.quick, value: hovering)
                    .animation(Motion.quick, value: selected)
            }
            .contentShape(shape)
            .onHover { hovering = $0 }
            .padding(.horizontal, -inset)
    }
}

struct CardHover: ViewModifier {
    let radius: CGFloat
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            // The shadow comes from a plain shape behind the card, so a see-through card casts one too.
            .background {
                shape.fill(.background)
                    .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
                    .opacity(hovering ? 1 : 0)
            }
            .overlay(shape.strokeBorder(hovering ? Color.primary.opacity(0.14) : Surface.stroke))
            .scaleEffect(hovering && !reduceMotion ? 1.01 : 1)
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
    }
}

// MARK: - Buttons

/// A button that answers: a fill under the pointer, a little smaller and lighter while pressed. It does not
/// change the label's size: the label carries its own margins (an `IconButton` is 32 × 32).
public struct HoverButtonStyle: ButtonStyle {
    /// The shape of the fill.
    public enum Shape: Sendable {
        case circle, capsule, rounded
    }

    let shape: Shape
    let fill: Color

    public init(_ shape: Shape = .rounded, fill: Color = Surface.raised) {
        self.shape = shape
        self.fill = fill
    }

    public func makeBody(configuration: Configuration) -> some View {
        HoverButtonBody(configuration: configuration, outline: outline, fill: fill)
    }

    var outline: AnyShape {
        switch shape {
        case .circle: AnyShape(Circle())
        case .capsule: AnyShape(Capsule())
        case .rounded: AnyShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
    }
}

extension ButtonStyle where Self == HoverButtonStyle {
    /// A rounded fill under the pointer.
    public static var hover: HoverButtonStyle { HoverButtonStyle() }
    /// A fill of this shape under the pointer.
    public static func hover(_ shape: HoverButtonStyle.Shape) -> HoverButtonStyle { HoverButtonStyle(shape) }
}

/// A ButtonStyle cannot hold the hover: this view does.
private struct HoverButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let outline: AnyShape
    let fill: Color
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .background {
                outline.fill((hovering && enabled) || pressed ? fill : .clear)
            }
            .contentShape(outline)
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .opacity(enabled ? (pressed ? 0.85 : 1) : 0.45)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
            .animation(Motion.quick, value: pressed)
    }
}

/// A round icon button, as Gmail's above its list: grey, its circle shows under the pointer.
public struct IconButton: View {
    let systemImage: String
    let help: String
    let size: CGFloat
    let action: () -> Void

    public init(_ systemImage: String, help: String, size: CGFloat = 15, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.help = help
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.hover(.circle))
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Lists that stay short

/// « Voir les 4 autres », « Voir l'autre », then « Voir moins »: under a list cut to a few rows. Nothing when
/// nothing is hidden.
public struct ShowMoreButton: View {
    let hidden: Int
    @Binding var expanded: Bool

    public init(hidden: Int, expanded: Binding<Bool>) {
        self.hidden = hidden
        _expanded = expanded
    }

    static func title(hidden: Int, expanded: Bool) -> String {
        if expanded { return "Voir moins" }
        return hidden == 1 ? "Voir l'autre" : "Voir les \(hidden) autres"
    }

    public var body: some View {
        if hidden > 0 {
            Button {
                withAnimation(Motion.standard) { expanded.toggle() }
            } label: {
                HStack(spacing: Space.xs) {
                    Text(Self.title(hidden: hidden, expanded: expanded))
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .semibold))
                }
                .font(.meta.weight(.medium))
                .padding(.horizontal, Space.s)
                .padding(.vertical, Space.xs)
            }
            .buttonStyle(.hover(.capsule))
            .foregroundStyle(.secondary)
            // The text lines up with the rows above; the fill spills past them.
            .padding(.horizontal, -Space.s)
        }
    }
}

/// The first `limit` rows, then « Voir les N autres »: a list never cut in silence.
public struct ShowMoreList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    let limit: Int
    let row: (Item) -> Row
    @State private var expanded = false

    public init(_ items: [Item], limit: Int, @ViewBuilder row: @escaping (Item) -> Row) {
        self.items = items
        self.limit = limit
        self.row = row
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(ShowMore.visible(items, limit: limit, expanded: expanded)) { item in
                row(item).transition(.opacity)
            }
            ShowMoreButton(hidden: ShowMore.hidden(count: items.count, limit: limit), expanded: $expanded)
        }
    }
}

/// What a list cut to a few rows shows, and hides.
enum ShowMore {
    static func hidden(count: Int, limit: Int) -> Int {
        max(0, count - max(0, limit))
    }

    static func visible<Item>(_ items: [Item], limit: Int, expanded: Bool) -> [Item] {
        expanded ? items : Array(items.prefix(max(0, limit)))
    }
}

/// One grey line, in a section that has nothing to show.
public struct EmptyLine: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.rowBody)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
