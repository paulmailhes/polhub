import AppKit
import Agenda
import MeetingDetection
import Notifications
import Observation
import ProjectsUI
import Updates

/// What « Coup d'œil » can do in the app (15/11): the app's own gestures, which the panel never redoes itself. A
/// gesture on the meeting goes through the coordinator (`user`), as the HUD's buttons do: the HUD and the panel stay in
/// step.
public struct CoupDoeilActions {
    /// `.accept`, `.decline`, `.neverForThisLink` (a detected meeting), `.recordNow`, `.stop`: to the coordinator.
    public var user: @MainActor (UserAction) -> Void
    /// One hour without detection, or detection again.
    public var pauseDetection: @MainActor () -> Void
    public var resumeDetection: @MainActor () -> Void
    /// The development build's switch: detection on or off.
    public var setDetection: @MainActor (Bool) -> Void
    /// Polhub's window, in front, on what the router says.
    public var showMainWindow: @MainActor () -> Void
    /// Réglages › Diagnostic, in the window. It shows what is known; it never runs a test by itself.
    public var showDiagnostic: @MainActor () -> Void
    /// What a notification is about (the bell's panel): the Meet in Dia, or the window on the meeting, event, thread.
    public var perform: @MainActor (NoticeAction) -> Void
    public var quit: @MainActor () -> Void

    public init(
        user: @escaping @MainActor (UserAction) -> Void = { _ in },
        pauseDetection: @escaping @MainActor () -> Void = {},
        resumeDetection: @escaping @MainActor () -> Void = {},
        setDetection: @escaping @MainActor (Bool) -> Void = { _ in },
        showMainWindow: @escaping @MainActor () -> Void = {},
        showDiagnostic: @escaping @MainActor () -> Void = {},
        perform: @escaping @MainActor (NoticeAction) -> Void = { _ in },
        quit: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }
    ) {
        self.user = user
        self.pauseDetection = pauseDetection
        self.resumeDetection = resumeDetection
        self.setDetection = setDetection
        self.showMainWindow = showMainWindow
        self.showDiagnostic = showDiagnostic
        self.perform = perform
        self.quit = quit
    }
}

/// Everything « Coup d'œil », the menu bar's panel, reads and does (15/11), in one object the app hands to
/// `MenuBarPanel`. The panel opens at once and without network: it only reads what these objects already published in
/// memory (`agenda.shown`, `mails.inbox`, `library.rows`, `jobs`, `summaryProgress`, `overviews`, the notifications'
/// inbox, `app`); it never reads the base, never calls `mails.refresh` nor `agenda.syncAll`, never runs a test.
///
/// The libraries arrive a moment after launch (`attach`): until then they are nil, and the panel shows the meeting,
/// the round buttons and the footer only. `@Observable`: a view that reads `context.agenda` is redrawn when it arrives;
/// each library is an `ObservableObject`, to observe with `@ObservedObject` in the view that reads it.
@MainActor @Observable
public final class CoupDoeilContext {
    /// The recordings: status, prompt and its deadline, alerts, pause, Meet code, development build.
    public let app: AppModel
    /// Where the window goes; `open(_:)` goes there and shows the window.
    public let router: WindowRouter
    public let actions: CoupDoeilActions

    /// The meetings: `rows` (live), `jobs` (transcriptions), `summaryProgress`, `summaryJobs`, `overviews`, `queue`
    /// (« Réessayer »: `queue?.retry(meetingID:)`), `summaryUnavailable`.
    public private(set) var library: MeetingLibrary?
    /// The calendars: `shown`, `projects`, `accounts`, `color(for:)`, `join(_:)` (Dia under the event's account).
    public private(set) var agenda: AgendaLibrary?
    /// The mails: `inbox`, `unreadCount`, `filing(of:)`, `isKnown(_:)`, `markRead(_:)`, `failure`, `accounts`. Nil without
    /// the agenda.
    public private(set) var mails: MailLibrary?
    public private(set) var projects: ProjectLibrary?
    /// For `ProjectLogo`: `MenuBarPanel` puts it in the environment (`\.projectLogos`).
    public private(set) var projectLogos: ProjectLogos?
    /// The notifications Polhub sent (`inbox`, for `NotificationBell`); nil in the development build.
    public private(set) var notifications: NotificationHub?
    /// Updates (`state`, `newer`, `autoInstall`, `installNow()`); nil in the development build.
    public private(set) var updates: UpdateService?

    public init(app: AppModel, router: WindowRouter, actions: CoupDoeilActions = CoupDoeilActions()) {
        self.app = app
        self.router = router
        self.actions = actions
    }

    /// The libraries are ready: once, at the end of the app's launch.
    public func attach(library: MeetingLibrary?, agenda: AgendaLibrary?, mails: MailLibrary?, projects: ProjectLibrary?,
                       projectLogos: ProjectLogos?, notifications: NotificationHub?, updates: UpdateService?) {
        self.library = library
        self.agenda = agenda
        self.mails = mails
        self.projects = projects
        self.projectLogos = projectLogos
        self.notifications = notifications
        self.updates = updates
    }

    /// The libraries arrived: tiles, mails and the rest can show.
    public var isReady: Bool { library != nil }

    // MARK: - Opening the window

    /// A place of the window, then the window in front. The panel closes on its own as Polhub comes forward; it is
    /// never closed by hand.
    public func open(_ place: WindowRouter.Place) {
        if case .mail(nil) = place, let mails, mails.folder != .inbox {
            // The tile and « Voir les N autres » speak of the inbox.
            mails.folder = .inbox
        }
        router.go(to: place)
        actions.showMainWindow()
    }

    /// « Ouvrir Polhub »: Accueil, or Réunions without the agenda.
    public func openHome() {
        open(.section(agenda != nil ? .home : .meetings))
    }

    /// « Nouveau mail » (⌘N): the composer over Mails, as the button of Mails does. Nothing without a mailbox.
    public func newMail() {
        guard let mails, !mails.accounts.isEmpty else { return }
        mails.writeNewMail(router: router)
        actions.showMainWindow()
    }

    /// « Rendez-vous »: Calendrier, with the editor of a new event.
    public func newEvent() {
        open(.newEvent)
    }
}
