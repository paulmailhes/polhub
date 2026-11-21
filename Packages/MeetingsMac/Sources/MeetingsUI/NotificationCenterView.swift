import Notifications
import HubDesign
import SwiftUI

// hub's notification center (Paul, 15/11: « un système de notification dans l'outil »): a bell with the count of
// what is new, and a panel that lists what hub notified, as macOS's Notification Center does. The panel floats
// (a popover, in glass); its cards are calm surfaces.

extension WindowRouter {
    /// What a click on a notification opens, from macOS's center or from hub's list (15/11): the Meet with the
    /// event's account (in Dia, no window), the meeting, the event, the thread or the mails' folder. `false` when the
    /// window has nothing to show.
    @discardableResult
    public func perform(_ action: NoticeAction, agenda: AgendaLibrary?, mails: MailLibrary?) -> Bool {
        switch action {
        case .join(let code, let account):
            agenda?.joinMeet(code: code, account: account)
            return false
        case .meeting(let id):
            open(meetingID: id, at: nil)
        case .event(let id):
            openEvent(id)
        case .calendar:
            section = .calendar
        case .mailThread(let key):
            openMail(key)
        case .mailFolder(let folder):
            openMail(nil)
            mails?.show(folderNamed: folder)
        case .window:
            break
        case .home:
            // A thread left open over the Accueil would hide the draft that waits.
            homeMail = nil
            section = .home
        case .vigie:
            section = .vigie
        }
        return true
    }
}

extension NoticeSection {
    /// The section of the sidebar it belongs to: its name, symbol and color (the test has none: hub's own).
    var item: SidebarItem? {
        switch self {
        case .calendar: .calendar
        case .meetings: .meetings
        case .mails: .mails
        case .polhub: nil
        case .home: .home
        case .vigie: .vigie
        }
    }

    var title: String { item?.title ?? "hub" }
    /// Its icon, the sidebar's (Phosphor), as on « Coup d'œil »'s tiles (lot 9, 20/11: an SF Symbol on a gradient square
    /// before, an app's icon of iOS).
    var appIcon: AppIcon { item?.appIcon ?? .bell }
    var tint: Color { Color(hex: item?.tint ?? Palette.gray) }
}

// MARK: - The bell

/// The bell of the sidebar: the count of the notifications not seen yet; a click opens the panel, anchored to it.
/// `perform` opens what a notification is about: `router.perform($0, agenda: agenda, mails: mails)`.
public struct NotificationBell: View {
    @ObservedObject var inbox: NotificationInbox
    let arrowEdge: Edge
    let perform: (NoticeAction) -> Void
    /// The panel opens on its own once the bell is on screen (the captures).
    let opensAlone: Bool
    /// Asked from outside (`WindowRouter.openNotifications()`): the panel opens once the bell is on screen, and the
    /// request is cleared.
    let request: Binding<Bool>?
    @State private var open = false

    public init(inbox: NotificationInbox, arrowEdge: Edge = .top, perform: @escaping (NoticeAction) -> Void) {
        self.init(inbox: inbox, arrowEdge: arrowEdge, opensAlone: false, perform: perform)
    }

    /// In the window's toolbar, beside the sidebar's button (lot 4, 19/11): the toolbar draws its round, the bell its
    /// count.
    let inToolbar: Bool

    init(inbox: NotificationInbox, arrowEdge: Edge, opensAlone: Bool = false, inToolbar: Bool = false, request: Binding<Bool>? = nil,
         perform: @escaping (NoticeAction) -> Void) {
        self.inbox = inbox
        self.arrowEdge = arrowEdge
        self.opensAlone = opensAlone
        self.inToolbar = inToolbar
        self.request = request
        self.perform = perform
    }

    static func badgeText(_ count: Int) -> String? {
        count <= 0 ? nil : count > 99 ? "99+" : "\(count)"
    }

    /// « Ouvrir les notifications : 3 nouvelles »: the bubble and VoiceOver's name, the same words (lot 10, 20/11: a noun
    /// for an action, « Notifications, 3 nouvelles »), the count by `Words.count`.
    static func accessibilityText(_ count: Int) -> String {
        Words.help("Ouvrir les notifications", detail: count > 0 ? Words.count(count, "nouvelle") : nil)
    }

    public var body: some View {
        let count = inbox.unreadCount
        Group {
            if inToolbar {
                Button { open.toggle() } label: { label(count, size: 18) }
            } else {
                // The same drawing as the sidebar's other icons (Phosphor), at the size of a row (15/11).
                Button { open.toggle() } label: {
                    label(count, size: 20).frame(width: SidebarFooterMetrics.rowHeight, height: SidebarFooterMetrics.rowHeight)
                }
                .buttonStyle(.hover(.circle))
                .foregroundStyle(.secondary)
            }
        }
        .help(Self.accessibilityText(count))
        .accessibilityLabel(Self.accessibilityText(count))
        .popover(isPresented: $open, arrowEdge: arrowEdge) {
            NotificationPanel(inbox: inbox) { action in
                open = false
                perform(action)
            }
        }
        .task(id: request?.wrappedValue ?? false) {
            let asked = request?.wrappedValue == true
            guard opensAlone || asked else { return }
            // A popover needs its window on screen: the window may be opening.
            try? await Task.sleep(for: .milliseconds(400))
            open = true
            if asked { request?.wrappedValue = false }
        }
    }

    /// The bell and its count: what is new, in hub's ink, its figure the ink's opposite; the red says only « late »
    /// and « recording » (design system v2, 19/11).
    private func label(_ count: Int, size: CGFloat) -> some View {
        AppIconImage(.bell, size: size)
            .overlay(alignment: .topTrailing) {
                if let text = Self.badgeText(count) {
                    Text(text)
                        .font(.tag.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Tint.onAccent.color)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Tint.accent, in: Capsule())
                        .fixedSize()
                        .offset(x: inToolbar ? 9 : 13, y: inToolbar ? -7 : -11)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(Motion.quick, value: count)
    }
}

// MARK: - The panel

/// The notifications hub sent, by day, the newest on top: a click opens what one is about, its × (or a swipe)
/// lets it go, « Tout effacer » empties the list. Opening it marks everything seen; the dots stay while it is open.
public struct NotificationPanel: View {
    @ObservedObject var inbox: NotificationInbox
    let perform: (NoticeAction) -> Void
    /// A fixed clock, for the captures.
    let clock: Date?
    /// What was new when the panel opened: its dot stays until the panel closes.
    @State private var newAtOpen: Set<UUID> = []
    /// The notifications of the stacks Paul opened.
    @State private var expanded: Set<UUID>

    public static let width: CGFloat = 380
    static let maxListHeight: CGFloat = 540

    public init(inbox: NotificationInbox, perform: @escaping (NoticeAction) -> Void) {
        self.init(inbox: inbox, clock: nil, perform: perform)
    }

    /// `clock` and `expanded`: a fixed time and stacks open, for the captures.
    init(inbox: NotificationInbox, clock: Date?, expanded: Set<UUID> = [], perform: @escaping (NoticeAction) -> Void) {
        self.inbox = inbox
        self.clock = clock
        self.perform = perform
        _expanded = State(initialValue: expanded)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            if inbox.notices.isEmpty {
                empty
            } else {
                TimelineView(.everyMinute) { context in
                    list(now: clock ?? context.date)
                }
            }
        }
        .frame(width: Self.width)
        .onAppear {
            newAtOpen = Set(inbox.notices.filter { !$0.seen }.map(\.id))
            inbox.markAllSeen()
        }
        .onDisappear { inbox.markAllSeen() }
        // The popover's root: hub's accent, ink, whatever the Mac's (design system v2, 19/11).
        .tint(Tint.control.color)
    }

    /// The panel's title, as a card's (17 semibold, 17 bold before), and « Tout effacer » in a grey word (lot 9, 20/11:
    /// a capsule always drawn before), 16 from the edges.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text("Notifications").font(.title2.weight(.semibold))
            Spacer(minLength: 0)
            if !inbox.notices.isEmpty {
                TextButton("Tout effacer", quiet: true) {
                    withAnimation(Motion.standard) {
                        inbox.removeAll()
                        expanded = []
                    }
                }
                .help("Effacer toutes les notifications")
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.l)
        .padding(.bottom, Space.s)
    }

    private var empty: some View {
        VStack(spacing: Space.s) {
            Image(systemName: "bell")
                .font(.largeTitle.weight(.light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, Space.xs)
            Text("Aucune notification").font(.rowTitle.weight(.semibold)).foregroundStyle(.secondary)
            Text("Les rappels, les comptes rendus et les mails que hub t'envoie s'affichent ici.")
                .font(.meta)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Space.xxl)
        .padding(.top, Space.xl)
        .padding(.bottom, Space.xxl + Space.s)
        .frame(maxWidth: .infinity)
    }

    private func list(now: Date) -> some View {
        let days = NoticeFeed.days(inbox.notices, now: now)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(days) { day in
                    // A group's label, as « En retard » on the Accueil: 12 points, semibold, grey (lot 9, 20/11), on the
                    // title's edge.
                    Text(day.title)
                        .font(.tag.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, day.id == days.first?.id ? Space.xs : Space.m)
                        .padding(.bottom, Space.s)
                    ForEach(day.groups) { group in
                        groupView(group, now: now)
                            .padding(.bottom, Space.s)
                            .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .trailing).combined(with: .opacity)))
                    }
                }
            }
            // 16 from the panel's edges, as its title (lot 9, 20/11: 12 and 18 before).
            .padding(.horizontal, Space.l)
            .padding(.bottom, Space.s)
            .padding(.top, Space.xs)
        }
        .scrollBounceBehavior(.basedOnSize)
        // The cards fade under the panel's edges as they scroll, as in the system's popovers.
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .frame(maxHeight: Self.maxListHeight)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func groupView(_ group: NoticeFeed.Group, now: Date) -> some View {
        let ids = Set(group.notices.map(\.id))
        if group.notices.count == 1 {
            card(group.notices[0], now: now)
        } else if !expanded.isDisjoint(with: ids) {
            VStack(alignment: .leading, spacing: Space.s) {
                // The stack opened: its section's label, as the days', and « Voir moins » in a grey word (lot 9, 20/11: a
                // capsule always drawn before; lot 10, 20/11: « Voir » unfolds in place, « Afficher » shows what is hidden).
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(group.section.title)
                        .font(.tag.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    TextButton("Voir moins", quiet: true) {
                        withAnimation(Motion.standard) { expanded.subtract(ids) }
                    }
                }
                ForEach(group.notices) { notice in
                    card(notice, now: now)
                        .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .trailing).combined(with: .opacity)))
                }
            }
        } else {
            NoticeCard(notice: group.notices[0], now: now, new: group.notices.contains(where: isNew), hidden: group.notices.count - 1,
                       open: { withAnimation(Motion.standard) { expanded.formUnion(ids) } },
                       dismiss: { remove(ids) })
        }
    }

    private func card(_ notice: InboxNotice, now: Date) -> some View {
        NoticeCard(notice: notice, now: now, new: isNew(notice), hidden: 0,
                   open: { perform(notice.action(now: Date())) },
                   dismiss: { remove([notice.id]) })
    }

    private func isNew(_ notice: InboxNotice) -> Bool {
        !notice.seen || newAtOpen.contains(notice.id)
    }

    private func remove(_ ids: Set<UUID>) {
        withAnimation(Motion.standard) {
            inbox.remove(ids)
            expanded.subtract(ids)
        }
    }
}

// MARK: - A card

/// One notification: the section's icon in its color, the title, two lines, the time; a dot while it is new.
/// A click opens it; the pointer shows its ×; a swipe sideways lets it go. A stack shows the others under it.
struct NoticeCard: View {
    let notice: InboxNotice
    let now: Date
    let new: Bool
    /// The notifications stacked under this one, until the stack opens.
    let hidden: Int
    let open: () -> Void
    let dismiss: () -> Void
    @State private var hovering = false
    @State private var pressed = false
    @State private var offset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let radius: CGFloat = Radius.card
    /// How far a card goes sideways before it is let go.
    static let swipeDistance: CGFloat = 90

    /// « 3 messages » on a thread's card that stands for several mails (`Words.count`, lot 10, 20/11).
    static func countText(_ notice: InboxNotice) -> String? {
        notice.kind == .mail && notice.threadKey != nil && notice.count > 1 ? Words.count(notice.count, "message") : nil
    }

    /// « et 1 autre », « et 3 autres » (`Words.count`, lot 10, 20/11).
    static func hiddenText(_ hidden: Int) -> String? {
        hidden < 1 ? nil : "et " + Words.count(hidden, "autre")
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        HStack(alignment: .top, spacing: Space.xs) {
            // What is new, in hub's ink, as the bell's count (design system v2, 19/11), 8 from the card's edge (lot 9,
            // 20/11: 4 before).
            Circle()
                .fill(Tint.accent)
                .frame(width: 8, height: 8)
                .opacity(new ? 1 : 0)
                .frame(height: NoticeIcon.size)
                .accessibilityHidden(true)
            HStack(alignment: .top, spacing: Space.m) {
                NoticeIcon(section: notice.kind.section)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text(notice.title)
                            .font(.rowTitle.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(NoticeFeed.time(of: notice.date, now: now))
                            .font(.meta)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    // French typography on hub's own sentences (« a commencé. Rejoindre ? »), never on a mail's subject
                    // (`Words.typeset`, lot 10, 20/11).
                    Text(notice.kind == .mail ? notice.body : Words.typeset(notice.body))
                        .font(.rowBody)
                        .foregroundStyle(.primary.opacity(0.82))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let more = hidden > 0 ? Self.hiddenText(hidden) : Self.countText(notice) {
                        Text(more)
                            .font(.meta)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.leading, Space.s)
        .padding(.trailing, Space.m)
        .padding(.vertical, Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The panel's card, as « Coup d'œil »'s and the app's: its fill and its one stroke, no shadow (lot 9, 20/11: a
        // white card with a shadow before); a step deeper under the pointer.
        .background(hovering ? Surface.raised : PanelSurface.card, in: shape)
        .overlay(shape.strokeBorder(PanelSurface.edge))
        .background {
            if hidden > 0 { stack }
        }
        .padding(.bottom, StackedCard.drop * CGFloat(min(hidden, 2)))
        .overlay(alignment: .topLeading) {
            if hovering {
                // A verb and its object, the bubble and VoiceOver's name (lot 10, 20/11: « Effacer » alone).
                DismissButton(help: hidden > 0 ? "Effacer ces notifications" : "Effacer cette notification", action: dismiss)
                    .offset(x: -7, y: -7)
                    .transition(.opacity)
            }
        }
        .scaleEffect(pressed && !reduceMotion ? 0.985 : 1)
        .offset(x: offset)
        .opacity(1 - min(abs(offset) / 260, 0.7))
        .contentShape(shape)
        .onHover { hovering = $0 }
        .gesture(swipeOrClick)
        .animation(Motion.quick, value: hovering)
        .animation(Motion.quick, value: pressed)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, open)
        .accessibilityAction(named: "Effacer", dismiss)
    }

    /// The cards under a closed stack: narrower, a little lower, without a shadow; the farther one fainter.
    private var stack: some View {
        ZStack {
            ForEach(1...min(hidden, 2), id: \.self) { depth in
                StackedCard(depth: depth)
                    .fill(PanelSurface.card.opacity(depth == 1 ? 1 : 0.6))
                    .overlay {
                        StackedCard.Outline(depth: depth).stroke(PanelSurface.edge, lineWidth: 1).clipShape(StackedCard(depth: depth))
                    }
            }
        }
    }

    /// A press without moving clicks; a slide sideways past `swipeDistance` lets the card go.
    private var swipeOrClick: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let moved = abs(value.translation.width) > 4 || abs(value.translation.height) > 4
                pressed = !moved
                if abs(value.translation.width) > 6 { offset = value.translation.width }
            }
            .onEnded { value in
                pressed = false
                let distance = value.translation.width
                if abs(distance) > Self.swipeDistance {
                    withAnimation(Motion.standard) { offset = distance > 0 ? 440 : -440 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { dismiss() }
                } else {
                    if abs(distance) <= 4 && abs(value.translation.height) <= 4 { open() }
                    withAnimation(Motion.standard) { offset = 0 }
                }
            }
    }
}

/// A card under a closed stack (lot 9, 20/11), narrower and lower, by `depth`. The cards are see-through, as the app's:
/// only what shows under the cards above it is drawn, so neither its fill nor its edge shows through them.
struct StackedCard: Shape {
    /// 1 under the card, 2 under that one.
    let depth: Int

    /// Each card of the stack is narrower by `inset` on each side and lower by `drop` than the one above it.
    static let inset: CGFloat = Space.s
    static let drop: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        (0..<depth).reduce(Self.card(depth, in: rect)) { path, above in path.subtracting(Self.card(above, in: rect)) }
    }

    static func card(_ depth: Int, in rect: CGRect, inset edge: CGFloat = 0) -> Path {
        let level = CGFloat(depth)
        return Path(roundedRect: rect.insetBy(dx: inset * level + edge, dy: edge).offsetBy(dx: 0, dy: drop * level),
                    cornerRadius: NoticeCard.radius - edge, style: .continuous)
    }

    /// Its whole edge, half a point inside, as a card's stroke: clipped to what shows of it, it draws no line across the
    /// card above.
    struct Outline: Shape {
        let depth: Int

        func path(in rect: CGRect) -> Path {
            StackedCard.card(depth, in: rect, inset: 0.5)
        }
    }
}

/// A notification's section (lot 9, 20/11): its Phosphor icon in its color, without a square, as « Coup d'œil »'s tiles.
struct NoticeIcon: View {
    let section: NoticeSection
    static let size: CGFloat = 20

    var body: some View {
        AppIconImage(section.appIcon, size: 17)
            .foregroundStyle(section.tint)
            .frame(width: Self.size, height: Self.size)
            .accessibilityLabel(section.title)
    }
}

/// The × of a card, shown under the pointer: a small round button on its corner, opaque over the card's edge, without a
/// shadow (lot 9, 20/11).
struct DismissButton: View {
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .frame(width: 22, height: 22)
                .background(Color(nsColor: .windowBackgroundColor), in: Circle())
                .overlay(Circle().strokeBorder(PanelSurface.edge))
        }
        .buttonStyle(.hover(.circle))
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .help(help)
        .accessibilityLabel(help)
    }
}
