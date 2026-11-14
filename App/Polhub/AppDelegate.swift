import AppKit
import Combine
import Domain
import MeetingDetection
import MeetingsUI
import Observability
import Persistence
import Pipeline
import PolhubDesign
import ProbeKit
import ProjectsUI
import Recording
import Summarization
import SwiftUI
import Updates
import UserNotifications
import Notifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    let model = AppModel()
    let runner = ProbeRunner()
    private var probeWindow: NSWindow?
    private var mainWindow: NSWindow?
    private var library: MeetingLibrary?
    /// The projects module (copy of the vault's projects, imported by Paul).
    private var projects: ProjectLibrary?
    /// Calendars, contacts and the loop of 13/11.
    private var agenda: AgendaLibrary?
    private var agendaTimer: Timer?
    /// The notifications (14/11): reminders, new events, meetings not recorded, summaries ready.
    private var notifications: NotificationHub?
    private var notificationTimer: Timer?
    private var startup: StartupControl?
    /// Step 2: the transcriptions, run by `polhub-calcul` outside meetings.
    private var transcription: TranscriptionQueue?
    /// The meetings' summaries, after their transcription (14/11).
    private var summaries: SummaryQueue?
    private var transcriptionTimer: Timer?
    /// Updates from GitHub, installed on their own when all is quiet.
    private var updates: UpdateService?
    private var updateTimer: Timer?
    let router = WindowRouter()
    private var diagnostic: DiagnosticModel?
    private var externalChanges: ExternalChangeSignal.Listener?
    private var checklistObserver: AnyCancellable?
    private var terminationSource: DispatchSourceSignal?
    private var guideObserver: AnyCancellable?

    // The meetings.
    private(set) var store: MeetingStore?
    private(set) var paths = AppPaths.standard(AppFlavor.current)
    private var coordinator: MeetingCoordinator?
    private var watcher: DiaWatcher?
    private var presenter: HUDPresenter?
    private var tickTimer: Timer?
    private var detectionLog: TraceWriter?
    private var detectionTask: Task<Void, Never>?
    private var memorySampler: MemorySampler?
    private var maintenanceTimer: Timer?
    private var database: AppDatabase?
    var isDevelopment: Bool { AppFlavor.current == .dev }

    /// Named after the bundle: the development version never talks to the production one.
    private static let showWindowNotification = Notification.Name("\(Bundle.main.bundleIdentifier ?? "fr.paulmailhes.polhub").show-window")
    /// Sent by the agent's copy to a copy Paul opened: only one copy records.
    private static let yieldNotification = Notification.Name("\(Bundle.main.bundleIdentifier ?? "fr.paulmailhes.polhub").yield")

    private struct LaunchRecord: Encodable, Sendable {
        let origin: LaunchOrigin
        let pid: Int32
        let probe: String?
    }

    /// Set before launch ends: a click on a notification may be what opened Polhub (14/11).
    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // macOS caches the icon by the date of the app's folder, which an update leaves as it was: refreshed, then
        // registered again, the icon shows in the Dock and the Finder (14/11).
        if let program = Bundle.main.executableURL {
            BundleFreshness.refreshIfStale(bundle: Bundle.main.bundleURL, executable: program)
        }
        LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
        exitCleanlyOnSIGTERM()
        // A pipe to an osascript that already ended must not kill the app.
        signal(SIGPIPE, SIG_IGN)
        let request = LaunchArguments.parse(CommandLine.arguments)
        let origin = LaunchContext.current
        let decision = LaunchDecision.decide(
            request: request, origin: origin, anotherCopyIsRunning: Self.anotherCopyIsRunning()
        )

        if decision == .yieldToRunningCopy {
            DistributedNotificationCenter.default().postNotificationName(
                Self.showWindowNotification, object: nil, userInfo: nil, deliverImmediately: true
            )
            exit(0)
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Self.showWindowNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.showMainWindow() }
        }
        if origin == .user {
            // A meeting this copy was recording is resumed by the agent's copy (crash recovery).
            DistributedNotificationCenter.default().addObserver(
                forName: Self.yieldNotification, object: nil, queue: .main
            ) { _ in exit(0) }
        }

        Task {
            await LaunchJournal.record("launch", LaunchRecord(origin: origin, pid: getpid(), probe: request?.probe.rawValue))
            // After a relaunch by the agent: do the permissions still hold?
            if origin == .launchd {
                let report = await PermissionProbe.run(prompt: false, testSystemAudio: true, amplitude: SystemAudioSelfTest.inaudibleAmplitude)
                await LaunchJournal.record("permissions", report)
            }
        }

        switch decision {
        case .runProbe(let request):
            // A measurement never runs next to the meetings: no detection, no recording.
            runHeadless(request)
        case .showWindow:
            startMeetings()
            showMainWindow()
        case .stayInMenuBar:
            startMeetings()
        case .askOtherCopyToQuit:
            DistributedNotificationCenter.default().postNotificationName(
                Self.yieldNotification, object: nil, userInfo: nil, deliverImmediately: true
            )
            Task {
                for _ in 0..<25 where Self.anotherCopyIsRunning() {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                startMeetings()
            }
        case .yieldToRunningCopy:
            break
        }
    }

    // MARK: - Meetings

    private func startMeetings() {
        let store: MeetingStore
        do {
            let database = try AppDatabase(path: paths.database.path)
            self.database = database
            store = MeetingStore(database)
            // A session wrote through `polhub mcp`: the views fetch again (13/11).
            externalChanges = ExternalChangeSignal.listen(queue: .main) { try? database.notifyExternalChanges() }
        } catch {
            Self.alertThenExit("La base des réunions ne s'ouvre pas : \(error.localizedDescription)")
        }
        self.store = store
        library = MeetingLibrary(store: store)
        projects = ProjectLibrary(store: ProjectStore(store.database), meetings: store)
        startAgenda(database: store.database)
        // Before the diagnostic, which may open the window: the window takes the update service as it is
        // when it opens, and Réglages › Mises à jour needs it (13/11).
        startUpdates(store: store)
        startDiagnostic(store: store)
        let presenter = HUDPresenter(model: model, app: self)
        self.presenter = presenter
        let day = Date().formatted(.iso8601.year().month().day().dateSeparator(.omitted))
        detectionLog = try? TraceWriter(fileURL: paths.logs.appending(path: "detection-\(day).jsonl"))

        let paths = paths
        let coordinator = MeetingCoordinator(
            store: store, paths: paths, recorders: LiveRecorderFactory(), presenter: presenter,
            detector: MeetingDetector(config: Self.detectorConfig, neverCodes: (try? store.neverCodes()) ?? []),
            clock: ContinuousTime.seconds, now: Date.init,
            availableBytes: { DiskGuard.availableBytes(at: paths.root) },
            deviceName: DeviceNames.name(forUID:), log: detectionLog,
            canResume: { row in
                RecoveryPolicy.canResume(lastWrite: RecoveryPolicy.lastWrite(of: row, paths: paths), bootTime: RecoveryPolicy.bootTime(), now: Date())
            },
            lastWrite: { row in RecoveryPolicy.lastWrite(of: row, paths: paths) },
            eventTitle: { [database = store.database] code, date in AgendaLibrary.eventTitle(in: database, code: code, at: date) }
        )
        self.coordinator = coordinator
        try? coordinator.recoverAfterLaunch()
        startTranscription(store: store)

        // The development version never detects on its own: it must not record a meeting twice.
        if !isDevelopment { setDetection(true) }

        let sampler = MemorySampler(store: store)
        sampler.start()
        memorySampler = sampler
        scheduleMaintenance()

        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.model.now = Date()
                self.presenter?.tick()
                Task { await self.coordinator?.tick() }
            }
        }
        refreshRecent()
    }

    /// The queue starts what a stop or a crash left, then looks for new meetings every minute and at the end of
    /// each meeting.
    private func startTranscription(store: MeetingStore) {
        let helper = Bundle.main.bundleURL.appending(path: "Contents/Helpers/polhub-calcul")
        let queue = TranscriptionQueue(
            meetings: store, transcripts: TranscriptStore(store.database), paths: paths,
            launcher: LiveCalculLauncher(executable: helper), log: detectionLog,
            // Réglages › Réunions (14/11).
            language: { Preferences().transcriptionLanguage }
        )
        transcription = queue
        library?.queue = queue
        // The first minute after launch belongs to the meeting the app may be resuming after a crash.
        Task { await queue.start(holdSeconds: 45) }
        let engine = AppleSummaryEngine()
        let summaries = SummaryQueue(database: store.database, engine: engine, otherWork: { await queue.isRunning },
                                     isEnabled: { Preferences().summariesEnabled },
                                     onFinished: { [weak self] meetingID, title in
                                         Task { @MainActor in await self?.notifications?.summaryReady(meetingID: meetingID, title: title) }
                                     })
        self.summaries = summaries
        library?.summaries = summaries
        library?.summaryUnavailable = engine.unavailableReason
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            Task { await summaries.start() }
        }
        transcriptionTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            // One after the other: the transcription first, the summary only if nothing computes (review of 14/11).
            Task {
                await queue.wake()
                await summaries.wake()
            }
            MainActor.assumeIsolated { self?.library?.summaryUnavailable = engine.unavailableReason }
        }
    }

    /// The version that runs, a line in the journal when it is new, then a look at GitHub every five minutes
    /// (the service itself checks once an hour). The development version never updates itself.
    private func startUpdates(store: MeetingStore) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let key = "lastLaunchedVersion"
        if let note = UpdateService.upgradeNote(previous: UserDefaults.standard.string(forKey: key), current: version) {
            try? store.addJournal(JournalEntry(createdAt: Date(), kind: .info, message: note))
        }
        UserDefaults.standard.set(version, forKey: key)
        guard !isDevelopment, let current = SemanticVersion(version) else { return }
        // The swap script waits for this: the new version has really started.
        LaunchSignal.write(version: version)
        let updates = UpdateService(current: current, isIdle: { [weak self] in await self?.isQuiet() ?? false })
        self.updates = updates
        updateTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { await updates.tick() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
            Task { await updates.tick() }
        }
    }

    /// The window opens on Accueil; the calendars are read at launch, then every 10 minutes, and the loop
    /// links guests, events, meetings and projects after each reading (13/11).
    private func startAgenda(database: AppDatabase) {
        let projects = projects
        let agenda = AgendaLibrary(database: database, vaultPath: { projects?.vaultPath })
        self.agenda = agenda
        router.section = .home
        agendaTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
            Task { @MainActor in await agenda.syncAll() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            Task { @MainActor in await agenda.syncAll() }
        }
        startNotifications(agenda: agenda)
    }

    /// Réglages › Notifications (14/11). The development version notifies nothing: no double with the installed one.
    private func startNotifications(agenda: AgendaLibrary) {
        guard !isDevelopment else { return }
        startup = StartupControl(read: { RelaunchAgent.isEnabled }, write: { $0 ? RelaunchAgent.enable() : RelaunchAgent.disable() },
                                 busy: { [weak self] in
                                     switch self?.model.status {
                                     case .prompting?, .recording?, .presumedEnded?: true
                                     default: false
                                     }
                                 },
                                 handsOver: LaunchContext.current == .user)
        let hub = NotificationHub(agenda: agenda)
        notifications = hub
        agenda.notifications = hub
        SystemNotifications.registerCategories()
        Task { @MainActor in
            _ = await SystemNotifications.requestAuthorization()
            await hub.refresh()
        }
        // Every minute: a meeting of the calendar under way while nothing records.
        notificationTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let recording: Bool, paused: Bool
                switch self.model.status {
                case .prompting, .recording, .presumedEnded: (recording, paused) = (true, false)
                case .idle: (recording, paused) = (false, false)
                case .paused: (recording, paused) = (false, true)
                }
                // Detection off (the development version, a pause): nothing is « non enregistrée ».
                Task { await hub.tick(recording: recording, paused: paused || !self.model.detectionOn) }
            }
        }
    }

    // MARK: - Notifications

    /// Shown even when Polhub is in front.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    /// A click: « Rejoindre » joins the Meet with the event's account; otherwise the event or the meeting opens.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let meet = info[NoticeKey.meet] as? String, account = info[NoticeKey.account] as? String
        let event = info[NoticeKey.event] as? String, meeting = (info[NoticeKey.meeting] as? String).flatMap(UUID.init(uuidString:))
        let action = response.actionIdentifier
        let kind = (info[NoticeKey.kind] as? String).flatMap(PlannedNotice.Kind.init(rawValue:))
        // A click joins only a reminder or a meeting not recorded; a new event, days ahead, opens its card (review
        // of 14/11). « Rejoindre » always joins.
        let join = action == NoticeKey.joinAction
            || (action == UNNotificationDefaultActionIdentifier && (kind == .reminder || kind == .unrecorded))
        completionHandler()
        Task { @MainActor in
            self.open(meet: meet, account: account, event: event, meeting: meeting, join: join)
        }
    }

    private func open(meet: String?, account: String?, event: String?, meeting: UUID?, join: Bool) {
        if join, let meet, let account {
            agenda?.joinMeet(code: meet, account: account)
        } else if let meeting {
            router.open(meetingID: meeting, at: nil)
            showMainWindow()
        } else if let event {
            router.openEvent(event)
            showMainWindow()
        } else {
            // « Nouveaux rendez-vous » (several at once): the Calendrier.
            router.section = .calendar
            showMainWindow()
        }
    }

    /// No meeting (from the pop-up to the end) and no transcription under way.
    private func isQuiet() async -> Bool {
        switch model.status {
        case .prompting, .recording, .presumedEnded: return false
        case .idle, .paused: break
        }
        if await transcription?.isRunning ?? false { return false }
        return !(await summaries?.isRunning ?? false)
    }

    /// Reads Dia and feeds the coordinator, or stops doing so.
    func setDetection(_ on: Bool) {
        model.detectionOn = on
        detectionTask?.cancel()
        detectionTask = nil
        watcher = nil
        guard on, let coordinator else { return }
        let watcher = DiaWatcher(adapter: DiaAdapter(runScript: DiaAdapter.outOfProcessRunScript))
        self.watcher = watcher
        detectionTask = Task {
            for await (at, input) in watcher.inputs() {
                await coordinator.handle(input, at: at)
            }
        }
    }

    /// Once a day, and a minute after launch: the copy of the base, and the audio past its 30 days.
    private func scheduleMaintenance() {
        guard let database, let store else { return }
        let paths = paths
        let run: @Sendable () -> Void = {
            Task.detached(priority: .background) {
                try? DatabaseBackup.run(database, into: paths.backups, now: Date())
                _ = try? AudioPurge.run(store: store, paths: paths, now: Date())
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { run() }
        maintenanceTimer = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { _ in run() }
    }

    /// At launch, a Meet tab already open while Dia holds no microphone is a past meeting.
    private static var detectorConfig: DetectorConfig {
        var config = DetectorConfig()
        config.ignoreTabsOpenAtLaunch = true
        return config
    }

    func user(_ action: UserAction) {
        Task { await coordinator?.user(action) }
    }

    func pauseDetection() {
        let until = Date().addingTimeInterval(3600)
        model.pausedUntil = until
        user(.pause(until: ContinuousTime.seconds() + 3600))
    }

    func resumeDetection() {
        model.pausedUntil = nil
        user(.resume)
    }

    /// The presenter passes every status on: the watcher reads tabs often while a meeting is on.
    func statusChanged(_ status: RecorderStatus) {
        let active = status != .idle
        Task { await watcher?.setMeetingActive(active) }
        // No computing from the pop-up to the end of a meeting.
        let busy: Bool
        switch status {
        case .prompting, .recording, .presumedEnded: busy = true
        case .idle, .paused: busy = false
        }
        library?.meetingActive = busy
        Task { await transcription?.meetingActivity(busy) }
        Task { await summaries?.meetingActivity(busy) }
        switch status {
        case .prompting, .recording:
            model.tabMeeting = true
        case .idle, .presumedEnded, .paused:
            model.tabMeeting = false
        }
        if status == .idle {
            refreshRecent()
            // The meeting that ended gets its event's project, title and guests now, not at the next sync.
            Task { await agenda?.runLinks() }
        }
    }

    func refreshRecent() {
        model.recent = (try? store?.recent(limit: 3)) ?? []
    }

    // MARK: - Windows

    func showMainWindow() {
        guard let library else {
            showProbeWindow()
            return
        }
        if mainWindow == nil {
            let diagnostic = diagnostic
            let view = MainWindowView(library: library, projects: projects, agenda: agenda, updates: updates, notifications: notifications,
                                      startup: startup, router: router, paths: paths) {
                if let diagnostic {
                    DiagnosticView(model: diagnostic) { [weak self] in self?.showProbeWindow() }
                }
            }
            let host = NSHostingController(rootView: view)
            // Each page's title and toolbar go to the window (14/11).
            host.sceneBridgingOptions = [.title, .toolbars]
            let window = NSWindow(contentViewController: host)
            window.title = "Polhub"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.setContentSize(NSSize(width: 1_180, height: 720))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setFrameAutosaveName("Polhub.main")
            window.center()
            mainWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func showMeeting(_ id: UUID) {
        router.section = .meetings
        router.selection = id
        showMainWindow()
    }

    func showDiagnostic() {
        router.openDiagnostic()
        showMainWindow()
    }

    // MARK: - Diagnostic

    private static let checklistDoneKey = "checklistDone"
    private static let lastVersionsKey = "lastCheckedVersions"

    /// The checks of the first launch, and again whenever macOS or Dia changed since they last ran.
    private func startDiagnostic(store: MeetingStore) {
        let isProduction = AppFlavor.current == .prod
        let model = DiagnosticModel(
            amplitude: SystemAudioSelfTest.inaudibleAmplitude, showsRelaunch: isProduction,
            relaunchEnabled: { RelaunchAgent.isEnabled },
            setRelaunch: { on in
                if !on { return RelaunchAgent.disable() }
                if let problem = RelaunchAgent.enable() { return problem }
                return LaunchContext.current == .user
                    ? "Relance activée : Polhub passe sous la garde de macOS. Cette fenêtre va se fermer ; rouvre-la par l'icône de la barre des menus."
                    : "Relance activée."
            }
        )
        diagnostic = model
        let defaults = UserDefaults.standard
        checklistObserver = model.$states.sink { [weak model] _ in
            Task { @MainActor in
                if model?.allGood == true { defaults.set(true, forKey: Self.checklistDoneKey) }
            }
        }

        let current = VersionPair.current()
        let last = defaults.data(forKey: Self.lastVersionsKey).flatMap { try? JSONDecoder().decode(VersionPair.self, from: $0) }
        if !defaults.bool(forKey: Self.checklistDoneKey) {
            showDiagnostic()
        } else if DiagnosticTrigger.shouldReplay(last: last, current: current) {
            Task {
                await model.testAll(prompt: false)
                if !model.permissionsGood {
                    try? store.addJournal(JournalEntry(createdAt: .now, kind: .alert,
                        message: "Une autorisation manque depuis la mise à jour de macOS ou de Dia : ouvre le Diagnostic."))
                    showDiagnostic()
                }
            }
        }
        defaults.set(try? JSONEncoder().encode(current), forKey: Self.lastVersionsKey)
    }

    static func anotherCopyIsRunning() -> Bool {
        let identifier = Bundle.main.bundleIdentifier ?? "fr.paulmailhes.polhub"
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains { $0.processIdentifier != getpid() && !$0.isTerminated }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// A double-click on the app while it is already running: show the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }

    /// `--probe …` on the command line: no window, run the probe, then quit if asked.
    /// Nobody reads the standard error of an app started by `open`: a failure is shown in an alert.
    private func runHeadless(_ request: ProbeRequest) {
        let started = runner.start(request) { problem in
            if let problem { Self.alertThenExit(problem) }
            if request.quitWhenDone { exit(0) }
        }
        if !started {
            Self.alertThenExit(runner.message ?? "La sonde n'a pas pu être lancée.")
        }
    }

    static func alertThenExit(_ text: String) -> Never {
        FileHandle.standardError.write(Data("Polhub : \(text)\n".utf8))
        // In a script there is nobody to click: the alert is only shown in a real session.
        if ProcessInfo.processInfo.environment["POLHUB_NO_ALERT"] == nil {
            let alert = NSAlert()
            alert.messageText = "Polhub : problème au démarrage"
            alert.informativeText = text
            NSApp.activate()
            alert.runModal()
        }
        exit(2)
    }

    func showProbeWindow() {
        if probeWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: ProbeWindow(runner: runner)))
            window.title = "Sondes — Polhub"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            probeWindow = window
            // During the guided call the instructions stay above Dia, on every desktop, in full screen too.
            guideObserver = ProtocolBoard.shared.$stepIndex.sink { [weak window] index in
                window?.level = index == nil ? .normal : .floating
                window?.collectionBehavior = index == nil ? [] : [.canJoinAllSpaces, .fullScreenAuxiliary]
            }
        }
        NSApp.setActivationPolicy(.regular)
        probeWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// The Dock icon only shows while a window is open.
    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        let others = [mainWindow, probeWindow].compactMap { $0 }.filter { $0 !== closing && $0.isVisible }
        if others.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }

    /// The relaunch agent restarts the app after an abnormal exit only: a plain `kill` must end with code 0.
    private func exitCleanlyOnSIGTERM() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { exit(0) }
        source.resume()
        terminationSource = source
    }
}
