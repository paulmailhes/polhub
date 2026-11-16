import AppKit
import Agenda
import MeetingDetection
import Persistence
import PolhubDesign
import ProjectsUI
import SwiftUI
import Updates

/// « Coup d'œil », the panel under the menu bar's logo (15/11), built as macOS's Control Center: from top to bottom,
/// « À régler » (only when something keeps Polhub from working well), the hero (what matters now, one main action),
/// four fixed tiles (Calendrier, Mails, Réunions, Projets), the new mails of people, four round buttons and the footer.
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
    /// Margins and gaps of the panel (Control Center's).
    static let margin: CGFloat = 14
    static let gap: CGFloat = 10
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
                                overviews: library.overviews, summariesOn: summariesEnabled, unavailable: library.summaryUnavailable)
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
        let report = meetings.flatMap { PanelModel.report($0, now: now) }
        let issues = ready ? PanelModel.issues(alerts: app.alerts, accounts: agenda?.accounts ?? [],
                                               mailFailure: mailState?.failure, updates: updateState) : []
        let lines = mailLines(mailState)
        // The mails' rows under the cap, whole; nil when not even the card's header fits (then it goes, the tile says it).
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
                    PanelTiles(context: context,
                               calendar: PanelModel.calendarTile(agenda?.shown, hiding: hero.eventID, now: now),
                               mails: PanelModel.mailsTile(mailState),
                               meetings: PanelModel.meetingsTile(status: app.status, meetings: meetings, report: report, now: now),
                               projects: PanelModel.projectsTile(agenda.map { _ in projects }),
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
                PanelButtons(context: context, hasMailboxes: mailState?.hasMailboxes ?? false, hasAgenda: agenda != nil)
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

/// The keys of the panel without a button of their own: ⌘1 to ⌘6 for the pages, ⌘, for Réglages, ⌘N for a new mail,
/// J to join. Esc closes the panel (the system's). No key ever stops a recording.
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

/// The panel's colors: one per section, as in the sidebar, and the meeting's red.
enum PanelTint {
    static let red = Color(hex: Palette.red)
    static let orange = Color(hex: Palette.orange)
    static let violet = Color(hex: SidebarItem.meetings.tint)
    static let gray = Color(hex: Palette.gray)

    /// A tinted card's fill and edge: a little stronger in dark, where the ground is.
    static func fill(_ tint: Color, dark: Bool) -> Color { tint.opacity(dark ? 0.16 : 0.1) }
    static func edge(_ tint: Color, dark: Bool) -> Color { tint.opacity(dark ? 0.26 : 0.18) }
}

/// The panel's calm cards (the tiles, the day, the mails): the panel sits on the system's material, not on the
/// window, so its cards are a light platter over it, as Control Center's modules, in light and dark alike.
enum PanelSurface {
    static let card = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(white: 1, alpha: 0.07) : NSColor(white: 1, alpha: 0.5)
    })
    static let edge = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(white: 1, alpha: 0.08) : NSColor(white: 0, alpha: 0.06)
    })
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
