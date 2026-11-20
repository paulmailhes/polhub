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

    /// The selection wins over the hover; nothing at rest. Pressed, a row darkens a step.
    static func fill(selected: Bool, hovering: Bool, pressed: Bool = false) -> Color {
        if selected { return Surface.selected }
        if pressed { return Surface.raised }
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

/// A row that is a button (15/11): the row's highlight under the pointer, a step darker while pressed, the
/// selection's color when `selected`. Nothing moves: the label keeps its size, the fill spills `inset` points
/// left and right of it, as `hoverRow`.
public struct RowButtonStyle: ButtonStyle {
    let selected: Bool
    let radius: CGFloat
    let inset: CGFloat

    public init(selected: Bool = false, radius: CGFloat = Radius.control, inset: CGFloat = 0) {
        self.selected = selected
        self.radius = radius
        self.inset = inset
    }

    public func makeBody(configuration: Configuration) -> some View {
        RowButtonBody(configuration: configuration, selected: selected, radius: radius, inset: inset)
    }
}

extension ButtonStyle where Self == RowButtonStyle {
    /// A row's highlight under the pointer, darker pressed.
    public static var row: RowButtonStyle { RowButtonStyle() }
    /// A row's highlight, selected or not, its fill spilling `inset` points past the text.
    public static func row(selected: Bool = false, radius: CGFloat = Radius.control, inset: CGFloat = 0) -> RowButtonStyle {
        RowButtonStyle(selected: selected, radius: radius, inset: inset)
    }
}

private struct RowButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    let radius: CGFloat
    let inset: CGFloat
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let pressed = configuration.isPressed
        configuration.label
            .padding(.horizontal, inset)
            .background {
                shape.fill(HoverRow.fill(selected: selected, hovering: hovering && enabled, pressed: pressed))
            }
            .contentShape(shape)
            .onHover { hovering = $0 }
            .padding(.horizontal, -inset)
            .opacity(enabled ? 1 : 0.45)
            .animation(Motion.quick, value: hovering)
            .animation(Motion.quick, value: pressed)
            .animation(Motion.quick, value: selected)
    }
}

/// A clickable row of a card: the whole width answers, its text lined up with the card's, its highlight
/// spilling past it.
public struct RowButton<Label: View>: View {
    let selected: Bool
    let action: () -> Void
    let label: Label

    public init(selected: Bool = false, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.selected = selected
        self.action = action
        self.label = label()
    }

    public var body: some View {
        Button(action: action) {
            label
                .padding(.vertical, Space.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.row(selected: selected, inset: Space.s))
    }
}

/// A word to click in a card (« Modifier », « Changer », « Tout enregistrer… »): its capsule under the pointer,
/// its text lined up with the card's, as « Voir les N autres ».
public struct TextButton: View {
    let title: String
    let quiet: Bool
    let action: () -> Void

    /// `quiet`: grey — a gesture that is there, not one that calls (the Accueil's pass, 18/11); otherwise the app's
    /// accent, ink (design system v2, 19/11).
    public init(_ title: String, quiet: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.quiet = quiet
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            // French typography, laid at display (`Words.typeset`, lot 10, 20/11).
            Text(Words.typeset(title)).font(.meta.weight(.medium)).padding(.horizontal, Space.s).padding(.vertical, 3)
        }
        .buttonStyle(.hover(.capsule))
        .foregroundStyle(quiet ? Color.secondary : Tint.accent)
        .padding(.horizontal, -Space.s)
    }
}

/// The action of a line, quiet (the Accueil's pass, 18/11): small, a thin border, the text's own color, a fill
/// under the pointer. One by line; the orange is kept for what matters.
public struct SubtleButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        SubtleButtonBody(configuration: configuration)
    }
}

private struct SubtleButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        configuration.label
            .font(.tag.weight(.medium))
            .foregroundStyle(enabled ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(hovering ? Surface.raised : Color.clear)
                    .overlay { RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)) }
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
    }
}

extension ButtonStyle where Self == SubtleButtonStyle {
    public static var subtle: SubtleButtonStyle { SubtleButtonStyle() }
}

/// A full-width line of a list, as Gmail's (the mails, the drafts): on its own ground, a shadow under the pointer
/// lifts it, a shade darker while pressed. Nothing moves.
public struct LineButtonStyle: ButtonStyle {
    let ground: Color

    public init(ground: Color) {
        self.ground = ground
    }

    public func makeBody(configuration: Configuration) -> some View {
        LineButtonBody(configuration: configuration, ground: ground)
    }
}

private struct LineButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let ground: Color
    @State private var hovering = false

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .background {
                Rectangle().fill(ground)
                    .overlay { Color.primary.opacity(pressed ? 0.05 : 0) }
                    .shadow(color: .black.opacity(hovering ? 0.2 : 0), radius: hovering ? 3 : 0, y: hovering ? 1 : 0)
            }
            .contentShape(Rectangle())
            .zIndex(hovering ? 1 : 0)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
            .animation(Motion.quick, value: pressed)
    }
}

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
    let shortcut: Words.Shortcut?
    let size: CGFloat
    let action: () -> Void

    /// `help`: what it does, a verb and its object (« Archiver le fil »), the bubble and VoiceOver's name; `shortcut`: the
    /// key that does it where the button is, said in the bubble only, « Supprimer (⌫) » (lot 10, 20/11).
    public init(_ systemImage: String, help: String, shortcut: Words.Shortcut? = nil, size: CGFloat = 15, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.help = help
        self.shortcut = shortcut
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
        .help(Words.help(help, shortcuts: shortcut.map { [$0] } ?? []))
        .accessibilityLabel(help)
    }
}

/// A round icon that opens a menu, drawn and answering as `IconButton`. A « … » menu says `Words.moreActions`, its help by
/// default (lot 10, 20/11).
public struct IconMenu<Content: View>: View {
    let systemImage: String
    let help: String
    let size: CGFloat
    let content: () -> Content

    public init(_ systemImage: String, help: String = Words.moreActions, size: CGFloat = 15, @ViewBuilder content: @escaping () -> Content) {
        self.systemImage = systemImage
        self.help = help
        self.size = size
        self.content = content
    }

    public var body: some View {
        Menu(content: content) {
            Image(systemName: systemImage).font(.system(size: size)).foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
        }
        .menuStyle(.button)
        .buttonStyle(.hover(.circle))
        .menuIndicator(.hidden)
        .fixedSize()
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
                    // French typography, laid at display (`Words.typeset`, lot 10, 20/11).
                    Text(Words.typeset(Self.title(hidden: hidden, expanded: expanded)))
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

/// The first `limit` rows, then « Voir les N autres »: a list never cut in silence. The rows of `alwaysShown`
/// (what Paul just added) show even past the limit, so a gesture always shows its result (correctifs, 15/11).
public struct ShowMoreList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    let limit: Int
    let alwaysShown: Set<Item.ID>
    let row: (Item) -> Row
    @State private var expanded = false

    public init(_ items: [Item], limit: Int, alwaysShown: Set<Item.ID> = [], @ViewBuilder row: @escaping (Item) -> Row) {
        self.items = items
        self.limit = limit
        self.alwaysShown = alwaysShown
        self.row = row
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(ShowMore.visible(items, limit: limit, expanded: expanded, alwaysShown: alwaysShown)) { item in
                row(item).transition(.opacity)
            }
            ShowMoreButton(hidden: ShowMore.hidden(items, limit: limit, alwaysShown: alwaysShown), expanded: $expanded)
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

    /// The first rows, and past them the ones that must show.
    static func visible<Item: Identifiable>(_ items: [Item], limit: Int, expanded: Bool, alwaysShown: Set<Item.ID>) -> [Item] {
        guard !expanded else { return items }
        return items.enumerated().filter { $0.offset < max(0, limit) || alwaysShown.contains($0.element.id) }.map(\.element)
    }

    static func hidden<Item: Identifiable>(_ items: [Item], limit: Int, alwaysShown: Set<Item.ID>) -> Int {
        items.count - visible(items, limit: limit, expanded: false, alwaysShown: alwaysShown).count
    }
}

/// One grey line, in a section that has nothing to show.
public struct EmptyLine: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        // French typography, laid at display (`Words.typeset`, lot 10, 20/11).
        Text(Words.typeset(text))
            .font(.rowBody)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Columns

/// The line between two columns that Paul drags to resize the one on its right (Colin's panel, 20/11): one point drawn,
/// `grab` points to take it, the system's column pointer over it. `changed` receives the drag's distance since it began,
/// in the window (the line moves with the column: its own space would shake); `ended`, when Paul lets go.
public struct ColumnResizeLine: View {
    /// The width that takes the drag, centred on the line.
    public static let grab: CGFloat = 9
    let changed: (CGFloat) -> Void
    let ended: () -> Void

    public init(changed: @escaping (CGFloat) -> Void, ended: @escaping () -> Void) {
        self.changed = changed
        self.ended = ended
    }

    public var body: some View {
        Divider()
            .ignoresSafeArea(edges: .vertical)
            .overlay {
                Color.clear
                    .frame(width: Self.grab)
                    .contentShape(Rectangle())
                    .pointerStyle(.columnResize)
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { changed($0.translation.width) }
                            .onEnded { _ in ended() }
                    )
                    .ignoresSafeArea(edges: .vertical)
            }
            // Above both columns, so the half of the grab over each still takes the pointer.
            .zIndex(1)
            .accessibilityHidden(true)
    }
}

// MARK: - The pill at the bottom

extension View {
    /// The pill at the bottom of a page (Paul, 20/11: « petite pilule discrète »): one line, the meta's size, glass, never
    /// wider than `Pill.maxWidth`; a longer text ends in « … » and says itself whole in its bubble.
    public func bottomPill() -> some View {
        font(.meta)
            .lineLimit(1)
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.s)
            .glassEffect(.regular, in: Capsule())
            .modifier(PillWidth())
    }
}

public enum Pill {
    /// The pill's widest, its padding included.
    public static let maxWidth: CGFloat = 520
}

/// At most `Pill.maxWidth`, else as wide as what it holds (a frame with a `maxWidth` would always take it all).
struct PillWidth: ViewModifier {
    func body(content: Content) -> some View {
        CappedWidth(max: Pill.maxWidth) { content }
    }
}

struct CappedWidth: Layout {
    let max: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.map { Swift.min($0, max) } ?? max
        return subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: proposal.height)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}
