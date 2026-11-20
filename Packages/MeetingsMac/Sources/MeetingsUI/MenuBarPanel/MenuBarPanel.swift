import AppKit
import Agenda
import MeetingDetection
import Persistence
import HubDesign
import ProjectsUI
import SwiftUI
import Updates

/// « Coup d'œil », the panel under the menu bar's logo (15/11), built as macOS's Control Center: from top to bottom,
/// « À régler » (only when something keeps Polhub from working well), the hero (what matters now, one main action),
/// two fixed tiles (Calendrier, Mails), the new mails of people, three round buttons and the footer (« Tuiles
/// allégées », Paul, 16/11: nothing said twice).
/// The grid and the buttons never move; only the banner, the hero's content and the mails change, and go when they
/// have nothing to say. The rules are in docs/design-system.md, « Coup d'œil ».
///
/// What the panel may count on (see `CoupDoeilContext`): it is drawn in the window of `MenuBarExtra`
/// (`.menuBarExtraStyle(.window)`); a gesture on the meeting goes through `context.actions.user`, a page through
/// `context.open(_:)`. It never opens by itself (the HUD stays the alert), never closes its window by hand, never runs
/// a hardware test, reads only what is already in memory (no base, no network), and reads `AppModel.now` nowhere: a
/// clock lives in its own `TimelineView`.
public struct MenuBarPanel: View {
    let context: CoupDoeilContext
    /// A fixed « now » for the captures; the app leaves it nil and follows the clock.
    @Environment(\.panelNow) private var fixedNow

    public static let width: CGFloat = 360
    /// Margins and gaps of the panel, on the app's scale (lot 9, 20/11: 14 and 10 before).
    static let margin: CGFloat = Space.l
    static let gap: CGFloat = Space.s
    /// The panel's tallest: past it, only the mails' card gives way, by whole rows.
    static let maxHeight: CGFloat = 640

    public init(context: CoupDoeilContext) {
        self.context = context
    }

    public var body: some View {
        OptionalObserving(context.library) { library in
            OptionalObserving(context.agenda) { agenda in
                OptionalObserving(context.mails) { mails in
                    OptionalObserving(context.updates) { updates in
                        // « dans 8 min » and the hero's choice follow the clock every 30 s, on the half-minutes the
                        // menu bar's « 8 min » turns on; the countdown and the recording's clock have their own
                        // timeline, by the second.
                        TimelineView(PanelModel.clock) { timeline in
                            PanelBody(context: context, library: library, agenda: agenda, mails: mails, updates: updates,
                                      now: fixedNow ?? timeline.date)
                        }
                    }
                }
            }
        }
        .frame(width: Self.width)
        // Its own height, never less: the window under the logo grows to it. Flexible, the panel let that window keep
        // an older, shorter height, and squeezed the hero (Paul's capture, 16/11, during a recording).
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.projectLogos, context.projectLogos)
        // Polhub's accent, ink, whatever the Mac's (design system v2, 19/11): the panel's glass buttons take it.
        .tint(Tint.control.color)
    }

    /// The panel's height cap: 640 points, or the screen's height less 40 when it is smaller.
    @MainActor static var heightCap: CGFloat {
        min(maxHeight, (NSScreen.main?.visibleFrame.height ?? 900) - 40)
    }
}

/// What the panel shows, from the app and the libraries at `now`.
struct PanelBody: View {
    let context: CoupDoeilContext
    let library: MeetingLibrary?
    let agenda: AgendaLibrary?
    let mails: MailLibrary?
    let updates: UpdateService?
    let now: Date
    @AppStorage(Preferences.Key.summariesEnabled) private var summariesEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What the panel measured of itself: the fixed top (banner, hero, tiles) and bottom (buttons, footer), the mails'
    /// card without its rows, and one row. Past the cap, only the card gives way, by whole rows.
    @State private var topHeight: CGFloat = 0
    @State private var bottomHeight: CGFloat = 0
    @State private var mailChrome: CGFloat = 66
    @State private var mailRowHeight: CGFloat = 0

    private var app: AppModel { context.app }
    private var ready: Bool { library != nil }

    private var meeting: PanelModel.Meeting {
        PanelModel.Meeting(status: app.status, prompt: app.prompt, canForgetLink: app.canForgetLink, meetCode: app.meetCode,
                           pausedUntil: app.pausedUntil)
    }

    private var meetings: PanelModel.Meetings? {
        library.map { library in
            PanelModel.Meetings(rows: library.rows, jobs: library.jobs, summaryJobs: library.summaryJobs, summaryProgress: library.summaryProgress,
                                overviews: library.overviews, summariesOn: summariesEnabled, unavailable: library.summaryUnavailable,
                                putAway: app.reportsPutAway)
        }
    }

    private var mailState: PanelModel.Mails? {
        mails.map { mails in
            PanelModel.Mails(unread: PanelModel.unread(mails.inbox, hidden: mails.hidden, tab: mails.tab(of:)), hasMailboxes: !mails.accounts.isEmpty,
                             failure: mails.failure.map { PanelModel.Mails.Failure(account: $0.account, text: $0.text) })
        }
    }

    private var updateState: PanelModel.Updates? {
        updates.map { PanelModel.Updates(state: $0.state, latest: $0.latest.map { "\($0.version)" }, autoInstall: $0.autoInstall) }
    }

    var body: some View {
        let meetings = meetings, mailState = mailState, updateState = updateState
        let projects = agenda?.projects ?? []
        let hero = PanelModel.hero(meeting: meeting, events: agenda?.shown, projects: projects, meetings: meetings, now: now)
        let issues = ready ? PanelModel.issues(alerts: app.alerts, accounts: agenda?.accounts ?? [],
                                               mailFailure: mailState?.failure, updates: updateState) : []
        let lines = mailLines(mailState)
        // The mails' rows under the cap, whole; nil when not one fits (then the card goes, the tile names the senders).
        let fixed = topHeight + bottomHeight + 2 * MenuBarPanel.margin + MenuBarPanel.gap
        let mailRows = PanelModel.mailRowsShown(cap: MenuBarPanel.heightCap, fixed: fixed, chrome: mailChrome, gap: MenuBarPanel.gap,
                                                rowHeight: mailRowHeight, count: min(lines.count, PanelModel.mailLimit))
        let showMails = ready && !app.meetingUnderWay && !lines.isEmpty && mailRows != nil
        VStack(alignment: .leading, spacing: MenuBarPanel.gap) {
            VStack(alignment: .leading, spacing: MenuBarPanel.gap) {
                if !issues.isEmpty {
                    PanelAttention(issues: issues, perform: perform).transition(arrival)
                }
                PanelHero(hero: hero, now: now, context: context, agenda: agenda, library: library)
                if ready {
                    // Nothing said twice (lot 9, 20/11): the tiles leave out what the hero, the mails' card and « À
                    // régler » say.
                    PanelTiles(context: context,
                               calendar: PanelModel.calendarTile(agenda?.shown, hero: hero, now: now),
                               mails: PanelModel.mailsTile(mailState, listed: showMails, issues: issues),
                               hasAgenda: agenda != nil, hasMailboxes: mailState?.hasMailboxes ?? false)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topHeight = $0 }
            if showMails, let mails, let mailRows {
                PanelMailCard(lines: lines, mails: mails, rows: mailRows, open: { context.open($0) }) { row, chrome in
                    if abs(row - mailRowHeight) > 0.5 { mailRowHeight = row }
                    if abs(chrome - mailChrome) > 0.5 { mailChrome = chrome }
                }
                .transition(arrival)
            }
            VStack(alignment: .leading, spacing: MenuBarPanel.gap) {
                PanelButtons(context: context, hasMailboxes: mailState?.hasMailboxes ?? false)
                PanelFooter(context: context, updateLine: PanelModel.updateLine(updateState))
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomHeight = $0 }
        }
        .padding(MenuBarPanel.margin)
        .frame(width: MenuBarPanel.width, alignment: .topLeading)
        .background { PanelShortcuts(context: context, join: joinAction(hero), hasMailboxes: mailState?.hasMailboxes ?? false) }
        .animation(Motion.standard, value: issues.map(\.id))
        .animation(Motion.standard, value: showMails)
    }

    /// The banner and the mails arrive softly; with « Réduire les animations », a fade only.
    private var arrival: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
    }

    private func mailLines(_ state: PanelModel.Mails?) -> [PanelModel.MailLine] {
        guard let mails, let state else { return [] }
        return PanelModel.mailLines(state.unread, projectTint: { thread in
            mails.filing(of: thread)?.filing.projectID.flatMap { mails.project($0) }.map(ProjectViews.tintHex)
        }, isKnown: mails.isKnown, now: now)
    }

    /// J: the hero's « Rejoindre ».
    private func joinAction(_ hero: PanelModel.Hero) -> (() -> Void)? {
        guard case .upcoming(let upcoming) = hero, upcoming.event.meetCode != nil, let agenda else { return nil }
        return { agenda.join(upcoming.event) }
    }

    private func perform(_ action: PanelModel.Issue.Action) {
        switch action {
        case .diagnostic: context.actions.showDiagnostic()
        case .accounts: context.open(.settings(.accounts))
        case .installUpdate:
            guard let updates else { return }
            Task { await updates.installNow() }
        }
    }
}

/// The keys of the panel without a button of their own: ⌘1 to ⌘7 for the pages, in the sidebar's order, ⌘, for Réglages,
/// ⌘N for a new mail: the same as in the window (lot 4, 19/11). J to join. Esc closes the panel (the system's). No key
/// ever stops a recording.
private struct PanelShortcuts: View {
    let context: CoupDoeilContext
    let join: (() -> Void)?
    let hasMailboxes: Bool

    var body: some View {
        ZStack {
            ForEach(Array(PanelModel.pages.enumerated()), id: \.offset) { index, item in
                Button(item.title) { context.open(.section(item)) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Button("Réglages") { context.open(.settings(nil)) }.keyboardShortcut(",", modifiers: .command)
            if hasMailboxes {
                Button("Nouveau mail") { context.newMail() }.keyboardShortcut("n", modifiers: .command)
            }
            if let join {
                Button("Rejoindre", action: join).keyboardShortcut("j", modifiers: [])
            }
        }
        .buttonStyle(.plain)
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension EnvironmentValues {
    /// The panel's « now », fixed for the captures (made-up days); nil in the app.
    @Entry var panelNow: Date? = nil
}

/// Draws `content` again whenever `object` changes, and once without it while it is nil: the panel follows libraries
/// that arrive a moment after launch.
struct OptionalObserving<Object: ObservableObject, Content: View>: View {
    let object: Object?
    let content: (Object?) -> Content

    init(_ object: Object?, @ViewBuilder content: @escaping (Object?) -> Content) {
        self.object = object
        self.content = content
    }

    var body: some View {
        if let object {
            Observing(object) { content($0) }
        } else {
            content(nil)
        }
    }
}

// MARK: - Shared pieces

/// The recipe of the panel's tinted cards (the hero while it records or asks for a look, « À régler »). Their color is
/// `Tint`'s (design system v2, 19/11): the recording's (`Tint.recording`) or attention's (`Tint.attention`), nothing
/// else; the violet and the grey said nothing, and a calm card is `PanelSurface`'s.
enum PanelTint {
    /// A tinted card's fill and edge: a little stronger in dark, where the ground is.
    static func fill(_ tint: Color, dark: Bool) -> Color { tint.opacity(dark ? 0.16 : 0.1) }
    static func edge(_ tint: Color, dark: Bool) -> Color { tint.opacity(dark ? 0.26 : 0.18) }
}

/// The calm cards of the panel (the hero, the tiles, « À régler », the mails) and of the bell's notifications: the
/// app's own cards, its fill and its one stroke, without a shadow (lot 9, 20/11: a white platter here, white cards with
/// a shadow in the bell, a grey card in the window before).
enum PanelSurface {
    static let card = Surface.fill
    static let edge = Surface.stroke
}

/// A card of the panel that is a button (the tiles, the day): it rises under the pointer (`cardHover`) and sinks a
/// little while pressed; with « Réduire les animations », it only darkens.
struct PanelCardStyle: ButtonStyle {
    var radius: CGFloat = Radius.card

    func makeBody(configuration: Configuration) -> some View {
        PanelCardBody(configuration: configuration, radius: radius)
    }
}

private struct PanelCardBody: View {
    let configuration: ButtonStyleConfiguration
    let radius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.primary.opacity(pressed ? 0.06 : 0))
            }
            .cardHover(radius: radius)
            .scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
            .animation(Motion.quick, value: pressed)
    }
}

/// A word to click in a card, grey (« Jamais pour ce lien »): its capsule under the pointer, its text lined up with
/// the card's.
struct PanelLink: View {
    let title: String
    let help: String?
    let action: () -> Void

    init(_ title: String, help: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title).font(.meta.weight(.medium)).padding(.horizontal, Space.s).padding(.vertical, 4)
        }
        .buttonStyle(.hover(.capsule))
        .foregroundStyle(.secondary)
        .padding(.horizontal, -Space.s)
        .help(help ?? title)
    }
}
