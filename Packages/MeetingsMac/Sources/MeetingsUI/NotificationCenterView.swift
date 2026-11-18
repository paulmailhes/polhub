import Notifications
import PolhubDesign
import SwiftUI

// Polhub's notification center (Paul, 15/11: « un système de notification dans l'outil »): a bell with the count of
// what is new, and a panel that lists what Polhub notified, as macOS's Notification Center does. The panel floats
// (a popover, in glass); its cards are calm surfaces.

extension WindowRouter {
    /// What a click on a notification opens, from macOS's center or from Polhub's list (15/11): the Meet with the
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
            section = .home
        }
        return true
    }
}

extension NoticeSection {
    /// The section of the sidebar it belongs to: its name, symbol and color (the test has none: Polhub's own).
    var item: SidebarItem? {
        switch self {
        case .calendar: .calendar
        case .meetings: .meetings
        case .mails: .mails
        case .polhub: nil
        case .home: .home
        }
    }

    var title: String { item?.title ?? "Polhub" }
    var icon: String { item?.icon ?? "bell.fill" }
    var tint: Color { Color(hex: item?.tint ?? Palette.gray) }
}

/// The cards of the panel: the brightest ground of the app, calm under the popover's glass.
enum NoticeSurface {
    static let card = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(srgbRed: 0.19, green: 0.19, blue: 0.205, alpha: 1) : .white
    })
    /// A card under the pointer: a touch deeper, nothing moves.
    static let cardHover = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(srgbRed: 0.225, green: 0.225, blue: 0.24, alpha: 1) : NSColor(white: 0.975, alpha: 1)
    })
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

    init(inbox: NotificationInbox, arrowEdge: Edge, opensAlone: Bool = false, request: Binding<Bool>? = nil,
         perform: @escaping (NoticeAction) -> Void) {
        self.inbox = inbox
        self.arrowEdge = arrowEdge
        self.opensAlone = opensAlone
        self.request = request
        self.perform = perform
    }

    static func badgeText(_ count: Int) -> String? {
        count <= 0 ? nil : count > 99 ? "99+" : "\(count)"
    }

    static func accessibilityText(_ count: Int) -> String {
        switch count {
        case 0: "Notifications"
        case 1: "Notifications, 1 nouvelle"
        default: "Notifications, \(count) nouvelles"
        }
    }

    public var body: some View {
        let count = inbox.unreadCount
        Button {
            open.toggle()
        } label: {
            // The same drawing as the sidebar's other icons (Phosphor), at the size of a row (15/11).
            AppIconImage(.bell, size: 20)
                .frame(width: SidebarFooterMetrics.rowHeight, height: SidebarFooterMetrics.rowHeight)
                .overlay(alignment: .topTrailing) {
                    if let text = Self.badgeText(count) {
                        Text(text)
                            .font(.tag.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Color.red, in: Capsule())
                            .fixedSize()
                            .offset(x: 5, y: -3)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(Motion.quick, value: count)
        }
        .buttonStyle(.hover(.circle))
        .foregroundStyle(.secondary)
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
}

// MARK: - The panel

/// The notifications Polhub sent, by day, the newest on top: a click opens what one is about, its × (or a swipe)
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
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Space.s) {
            Text("Notifications").font(.title2.weight(.bold))
            Spacer(minLength: 0)
            if !inbox.notices.isEmpty {
                Button {
                    withAnimation(Motion.standard) {
                        inbox.removeAll()
                        expanded = []
                    }
                } label: {
                    Text("Tout effacer")
                        .font(.meta.weight(.medium))
                        .padding(.horizontal, Space.m - 2)
                        .padding(.vertical, Space.xs + 1)
                        .background(Surface.fill, in: Capsule())
                }
                .buttonStyle(.hover(.capsule))
                .foregroundStyle(.secondary)
                .help("Effacer toutes les notifications")
            }
        }
        .padding(.horizontal, Space.l + 2)
        .padding(.top, Space.l)
        .padding(.bottom, Space.s)
    }

    private var empty: some View {
        VStack(spacing: Space.s) {
            Image(systemName: "bell")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, Space.xs)
            Text("Aucune notification").font(.rowTitle.weight(.semibold)).foregroundStyle(.secondary)
            Text("Les rappels, les comptes rendus et les mails que Polhub t'envoie s'affichent ici.")
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
                    Text(day.title)
                        .font(.meta.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Space.xs + 2)
                        .padding(.top, day.id == days.first?.id ? Space.xs : Space.m)
                        .padding(.bottom, Space.s - 2)
                    ForEach(day.groups) { group in
                        groupView(group, now: now)
                            .padding(.bottom, Space.s)
                            .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .trailing).combined(with: .opacity)))
                    }
                }
            }
            .padding(.horizontal, Space.m)
            .padding(.bottom, Space.m)
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
            VStack(alignment: .leading, spacing: Space.s - 2) {
                HStack(spacing: Space.s) {
                    Label(group.section.title, systemImage: group.section.icon)
                        .font(.meta.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(Motion.standard) { expanded.subtract(ids) }
                    } label: {
                        Text("Afficher moins")
                            .font(.meta.weight(.medium))
                            .padding(.horizontal, Space.m - 2)
                            .padding(.vertical, Space.xs + 1)
                            .background(Surface.fill, in: Capsule())
                    }
                    .buttonStyle(.hover(.capsule))
                    .foregroundStyle(.secondary)
                }
                .padding(.leading, Space.xs + 2)
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

/// One notification: the section's symbol on its color, the title, two lines, the time; a dot while it is new.
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

    static let radius: CGFloat = 16
    /// How far a card goes sideways before it is let go.
    static let swipeDistance: CGFloat = 90

    /// « 3 messages » on a thread's card that stands for several mails.
    static func countText(_ notice: InboxNotice) -> String? {
        notice.kind == .mail && notice.threadKey != nil && notice.count > 1 ? "\(notice.count) messages" : nil
    }

    static func hiddenText(_ hidden: Int) -> String? {
        switch hidden {
        case ..<1: nil
        case 1: "et 1 autre"
        default: "et \(hidden) autres"
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        HStack(alignment: .top, spacing: Space.xs + 1) {
            // Mail's blue dot, whatever the Mac's accent: orange means « à vérifier » in Polhub.
            Circle()
                .fill(Color.blue)
                .frame(width: 8, height: 8)
                .opacity(new ? 1 : 0)
                .frame(width: 10, height: SectionTile.size)
                .accessibilityHidden(true)
            HStack(alignment: .top, spacing: Space.m - 2) {
                SectionTile(section: notice.kind.section)
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
                    Text(notice.body)
                        .font(.rowBody)
                        .foregroundStyle(.primary.opacity(0.82))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let more = hidden > 0 ? Self.hiddenText(hidden) : Self.countText(notice) {
                        Text(more)
                            .font(.meta)
                            .foregroundStyle(.secondary)
                            .padding(.top, 1)
                    }
                }
            }
        }
        .padding(.leading, Space.xs)
        .padding(.trailing, Space.m + 2)
        .padding(.vertical, Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            shape.fill(hovering ? NoticeSurface.cardHover : NoticeSurface.card)
                .shadow(color: .black.opacity(0.07), radius: 2, y: 1)
        }
        .overlay(shape.strokeBorder(Surface.stroke))
        .background(alignment: .bottom) {
            if hidden > 0 { stack(shape) }
        }
        .padding(.bottom, hidden > 1 ? 12 : hidden == 1 ? 6 : 0)
        .overlay(alignment: .topLeading) {
            if hovering {
                DismissButton(help: hidden > 0 ? "Effacer ces notifications" : "Effacer", action: dismiss)
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

    /// The cards under a closed stack: narrower, a little lower.
    private func stack(_ shape: RoundedRectangle) -> some View {
        ZStack(alignment: .bottom) {
            if hidden > 1 {
                shape.fill(NoticeSurface.card.opacity(0.55))
                    .overlay(shape.strokeBorder(Surface.stroke))
                    .padding(.horizontal, Space.l + 2)
                    .offset(y: 12)
            }
            shape.fill(NoticeSurface.card.opacity(0.85))
                .overlay(shape.strokeBorder(Surface.stroke))
                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                .padding(.horizontal, Space.s + 1)
                .offset(y: 6)
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

/// The section's symbol, white on its color, as an app's icon in macOS's Notification Center.
struct SectionTile: View {
    let section: NoticeSection
    static let size: CGFloat = 32

    var body: some View {
        Image(systemName: section.icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: Self.size, height: Self.size)
            .background(section.tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityLabel(section.title)
    }
}

/// The × of a card, shown under the pointer: a small round button on its corner.
struct DismissButton: View {
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .frame(width: 22, height: 22)
                .background(hovering ? NoticeSurface.cardHover : NoticeSurface.card, in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12)))
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        }
        .buttonStyle(.hover(.circle))
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .help(help)
        .accessibilityLabel(help)
    }
}
