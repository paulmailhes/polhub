import AppKit
import Notifications
import Persistence
import PolhubDesign
import SwiftUI

/// The card before a meeting with a Meet (Paul, 16/11: macOS's banners « s'en vont direct »): at the top right of
/// the screen, above every app and on every desktop, it stays until Paul joins or closes it, ten minutes after the
/// start at most. The app hands it the events and the clock (`update`); `MeetingCardPlan` decides.
@MainActor
public final class MeetingCardPresenter: ObservableObject {
    @Published public private(set) var cards: [CalendarEventRow] = []
    /// The occurrences Paul closed or joined: their card never comes back.
    private var closed: Set<String> = []
    private var panel: NSPanel?
    private let showsPanel: Bool
    private let joinMeet: (CalendarEventRow) -> Void
    private let accountColor: (String) -> Color

    /// `showsPanel`: false in the tests, which read `cards` only. `color`: an account's color, for its round; grey
    /// without one (design system v2, 19/11).
    public init(showsPanel: Bool = true, join: @escaping (CalendarEventRow) -> Void,
                color: @escaping (String) -> Color = { _ in .secondary }) {
        self.showsPanel = showsPanel
        self.joinMeet = join
        self.accountColor = color
    }

    /// The events and the clock, as the app sees them (`meetingCode`: the meeting Polhub records or offers to record).
    public func update(events: [CalendarEventRow], now: Date, enabled: Bool, minutes: Int, meetingCode: String?) {
        let due = enabled ? MeetingCardPlan.due(events, now: now, minutes: minutes, closed: closed, meetingCode: meetingCode) : []
        guard due != cards else { return }
        cards = due
        layout()
    }

    /// The cross: this occurrence's card goes for good.
    public func close(_ event: CalendarEventRow) {
        closed.insert(MeetingCardPlan.key(event))
        cards.removeAll { MeetingCardPlan.key($0) == MeetingCardPlan.key(event) }
        layout()
    }

    /// « Rejoindre »: the Meet, under the event's account, then the card goes.
    public func join(_ event: CalendarEventRow) {
        joinMeet(event)
        close(event)
    }

    func color(_ event: CalendarEventRow) -> Color { accountColor(event.account) }

    /// Shown, resized or hidden after a change of the cards.
    private func layout() {
        guard showsPanel else { return }
        guard !cards.isEmpty else {
            panel?.orderOut(nil)
            panel = nil
            return
        }
        let panel = self.panel ?? {
            let made = HUDPanelController.makePanel(style: .production)
            made.contentView = FirstMouseHostingView(rootView: MeetingCardStack(presenter: self))
            return made
        }()
        // The screen of the menu bar, where macOS shows its notifications.
        if let screen = NSScreen.screens.first {
            panel.setFrame(MeetingCardPlacement.frame(screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
                                                      safeAreaTop: screen.safeAreaInsets.top, size: MeetingCardMetrics.size(cards: cards.count)),
                           display: true)
        }
        if self.panel == nil { panel.orderFrontRegardless() }
        self.panel = panel
    }
}

/// The card's measures.
enum MeetingCardMetrics {
    static let width: CGFloat = 420
    static let height: CGFloat = 68
    static let spacing: CGFloat = Space.s

    static func size(cards: Int) -> CGSize {
        let count = CGFloat(max(1, cards))
        return CGSize(width: width, height: height * count + spacing * (count - 1))
    }
}

/// At the top right, below the menu bar or the notch, as macOS's notifications.
public enum MeetingCardPlacement {
    public static func frame(screenFrame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat, size: CGSize, margin: CGFloat = 12) -> CGRect {
        let menuBar = screenFrame.maxY - visibleFrame.maxY
        let x = max(screenFrame.minX, screenFrame.maxX - size.width - margin)
        let y = screenFrame.maxY - max(safeAreaTop, menuBar) - margin - size.height
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

/// The cards, the soonest first.
struct MeetingCardStack: View {
    @ObservedObject var presenter: MeetingCardPresenter

    var body: some View {
        VStack(spacing: MeetingCardMetrics.spacing) {
            ForEach(presenter.cards) { event in
                MeetingCardView(event: event, color: presenter.color(event)) {
                    presenter.join(event)
                } close: {
                    presenter.close(event)
                }
            }
        }
        .frame(width: MeetingCardMetrics.width, alignment: .top)
        // The card's root: Polhub's accent, ink, whatever the Mac's (design system v2, 19/11).
        .tint(Tint.control.color)
    }
}

/// One card, in glass (it floats over everything): the account's color in its round, the title, « Dans 2 min »,
/// « Rejoindre » in Polhub's ink (design system v2, 19/11: an account's color never goes on a button), and the cross.
/// It reads as « Coup d'œil » (lot 9, 20/11): its title in 15 points and its line in 13 (13 and 11 before, under the
/// app's floor), 16 from its edge, « Rejoindre » the panel's main button and the cross the app's discreet one.
struct MeetingCardView: View {
    let event: CalendarEventRow
    let color: Color
    let join: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: "video.fill")
                .font(.meta.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(FloatingMetrics.title)
                    .lineLimit(1)
                    .help(event.title)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(MeetingCardPlan.when(event.startAt, now: context.date) + " · Google Meet")
                        .font(FloatingMetrics.meta)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            // The title takes all the room the buttons leave, before it is cut (lot 9, 20/11).
            .layoutPriority(1)
            Spacer(minLength: Space.xs)
            // The panel's main button, drawn by hand in Polhub's ink (`.primary`): the panel never becomes key, and a
            // prominent button of the system turns grey there. It answers the pointer and the press, as every button of
            // the app (lot 9, 20/11: a plain capsule before). The account stays in its round (design system v2, 19/11).
            Button("Rejoindre", action: join)
                .buttonStyle(.primary)
                .fixedSize()
                .help("Ouvrir le Meet dans Dia avec le compte \(event.account)")
            IconButton("xmark", help: "Fermer le rappel", size: 13, action: close)
        }
        .padding(.leading, FloatingMetrics.margin)
        // The cross's circle keeps its own air: its glyph sits 16 from the edge.
        .padding(.trailing, Space.xs)
        .frame(width: MeetingCardMetrics.width, height: MeetingCardMetrics.height)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}
