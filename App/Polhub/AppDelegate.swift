import AppKit
import Colin
import Combine
import Domain
import Inspiration
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
    let model = AppModel(isDevelopment: AppFlavor.current == .dev)
    let router = WindowRouter()
    /// What « Coup d'œil », the menu bar's panel, reads and does (15/11): the libraries join it once ready.
    private(set) lazy var coupDoeil = CoupDoeilContext(app: model, router: router, actions: CoupDoeilActions(
        user: { [weak self] in self?.user($0) },
        pauseDetection: { [weak self] in self?.pauseDetection() },
        resumeDetection: { [weak self] in self?.resumeDetection() },
        setDetection: { [weak self] in self?.setDetection($0) },
        showMainWindow: { [weak self] in self?.showMainWindow() },
        showDiagnostic: { [weak self] in self?.showDiagnostic() },
        perform: { [weak self] in self?.perform($0) },
        quit: { NSApp.terminate(nil) }
    ))
    let runner = ProbeRunner()
    /// The probe of Colin on the Diagnostic page (17/11): never during a meeting, and stopped when one begins,
    /// when the Mac goes to sleep, or by hand.
    private(set) lazy var colinProbe = ColinProbeControl(
        isQuiet: { [weak self] in !(await self?.recordingOrTranscribing() ?? false) },
        start: { [weak self] account, onFinish in
            guard let self else { return "Polhub se ferme." }
            guard self.runner.running == nil else { return "Une autre sonde tourne déjà." }
            // What the runner says of a start it could not make (the trace, the probe itself) is shown as it is.
            return self.runner.start(ProbeRequest(probe: .colin, variant: account), onFinish: onFinish)
                ? nil : (self.runner.message ?? "La sonde n'a pas pu être lancée.")
        },
        stop: { [weak self] in self?.runner.stop() },
        report: { [weak self] in
            guard let directory = self?.runner.lastDirectory, let ok = ColinProbe.verdict(in: directory) else { return nil }
            return (ok, ColinProbe.reason(in: directory))
        }
    )
    private var probeWindow: NSWindow?
    private var mainWindow: NSWindow?
    private var library: MeetingLibrary?
    /// The projects module.
    private var projects: ProjectLibrary?
    /// The projects' logos (15/11): Paul's images and the icons of the clients' sites, in `Logos/`.
    private var projectLogos: ProjectLogos?
    /// Calendars, contacts and the loop of 13/11.
    private var agenda: AgendaLibrary?
    private var mails: MailLibrary?
    /// « Inspiration » (16/11): the sites, the branding and the mock-ups, and their collection.
    private var inspiration: InspirationLibrary?
    private var inspirationAutomation: InspirationAutomation?
    private var inspirationTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    /// The Mac's sleep and wake, told to the probe of Colin.
    private var powerObservers: [NSObjectProtocol] = []
    private var agendaTimer: Timer?
    /// The notifications (14/11): reminders, new events, meetings not recorded, summaries ready.
    private var notifications: NotificationHub?
    /// « Précédent », « Suivant »: the window's events read, the libraries followed.
    private var navigationMonitor: Any?
    private var navigationObservers: [AnyCancellable] = []
    /// The card that stays at the top right before a Meet (16/11); nil in the development build.
    private var meetingCards: MeetingCardPresenter?
    private var meetingCardsLook = Date.distantPast
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
    /// Once a minute while the disk alert is up: enough free space again, it goes (« Coup d'œil », 15/11).
    private var alertTimer: Timer?
    private var nextMeetObserver: AnyCancellable?
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
            ) { [weak self] _ in
                // A probe under way ends with this copy, and the Claude Code it launched with it.
                MainActor.assumeIsolated { self?.stopClaude() }
                exit(0)
            }
        }
        watchPower()

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
        } catch AppDatabaseError.newerBase {
            // Not a crash: a plain exit, which the relaunch agent leaves alone, instead of the same alert every
            // ten seconds (correctifs, 15/11).
            Self.alertThenExit(AppDatabaseError.newerBase.localizedDescription, code: 0)
        } catch {
            Self.alertThenExit("La base des réunions ne s'ouvre pas : \(error.localizedDescription)")
        }
        self.store = store
        library = MeetingLibrary(store: store)
        projects = ProjectLibrary(store: ProjectStore(store.database), meetings: store)
        projectLogos = ProjectLogos(folder: paths.logos, database: store.database)
        startAgenda(database: store.database)
        startInspiration(database: store.database)
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
                let now = Date()
                self.model.tick(now: now)
                // The Meet of « 8 min » started: the next one.
                if self.model.nextMeetPassed, let agenda = self.agenda { self.model.updateNextMeet(agenda.shown, now: now) }
                self.presenter?.tick()
                self.updateMeetingCards(now: now)
                Task { await self.coordinator?.tick() }
            }
        }
        followAlertCauses()
        // « Coup d'œil » reads what these already hold in memory, from now on.
        coupDoeil.attach(library: library, agenda: agenda, mails: mails, projects: projects, projectLogos: projectLogos,
                         notifications: notifications, updates: updates)
        countColinRulesOnce()
    }

    /// Colin's rules, counted on Paul's own mails before the Accueil shows them (18/11): once per version, a minute
    /// after the launch, then at the first quiet moment. Numbers only, written among the measures: no model, and
    /// nothing leaves the Mac. The development version, which has its own base, counts nothing.
    private func countColinRulesOnce() {
        guard AppFlavor.current != .dev, let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              UserDefaults.standard.string(forKey: Preferences.Key.colinRulesCount) != version else { return }
        Task { [weak self] in
            var wait = Duration.seconds(60)
            // Never beside a meeting: asked again every five minutes, for a day at most.
            for _ in 0..<288 {
                try? await Task.sleep(for: wait)
                wait = .seconds(300)
                guard let self else { return }
                guard await self.isQuiet() else { continue }
                if self.runner.start(ProbeRequest(probe: .colinRules)) {
                    UserDefaults.standard.set(version, forKey: Preferences.Key.colinRulesCount)
                    return
                }
            }
        }
    }

    /// What the menu bar needs besides the coordinator (« Coup d'œil », 15/11): the next Meet, from the events as they
    /// change; the free space while a meeting records or the disk alert is up (a statfs a minute, never otherwise), so
    /// the badge follows the disk, back in the same meeting if it fills again.
    private func followAlertCauses() {
        if let agenda {
            nextMeetObserver = agenda.$shown.sink { [weak self] events in
                MainActor.assumeIsolated { self?.model.updateNextMeet(events, now: Date()) }
            }
        }
        let root = paths.root
        alertTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.needsDiskCheck else { return }
                self.model.checkDisk(availableBytes: DiskGuard.availableBytes(at: root))
            }
        }
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
        let agenda = AgendaLibrary(database: database)
        self.agenda = agenda
        // The events the agents ask for (`rendez_vous`, 16/11), at their signal and at launch.
        agenda.startAgentEvents(root: paths.root)
        // The mails (14/11): the mailboxes that granted them are followed from the launch, window open or not.
        // The programmed sends live in the Keychain (wave B); the development build never touches it.
        let mails = MailLibrary(agenda: agenda, root: paths.root, schedules: .keychain)
        self.mails = mails
        mails.start()
        router.section = .home
        agendaTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
            Task { @MainActor in await agenda.syncAll() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            Task { @MainActor in await agenda.syncAll() }
        }
        startNotifications(agenda: agenda)
    }

    /// « Inspiration » (16/11): the pages follow the base; the collection runs at its slots (Awwwards every two
    /// hours from 8 h to 22 h, the LinkedIn pages at 9, 14 and 20 h), looked at a minute after launch, every five
    /// minutes and at wake; the items without categories are tagged by Apple's model after each pass. Nothing on its
    /// own in the development build (no doubled requests to Awwwards and LinkedIn), nor during a meeting; the model
    /// also waits for the transcriptions and the summaries.
    private func startInspiration(database: AppDatabase) {
        let library = InspirationLibrary(database: database, paths: paths)
        inspiration = library
        let runLog = CollectionRunLog()
        // The vocabularies the menus read: Polhub's copy (the vault's, brought while there was one), else the bundled.
        let tagger = InspirationTagger(database: database, paths: paths)
        let collector = InspirationCollector(database: database, paths: paths, runLog: runLog)
        let isDevelopment = isDevelopment
        let conditions = InspirationAutomation.Conditions(
            mayCollect: { [weak self] in
                guard !isDevelopment, Preferences().inspirationAutoCollect else { return false }
                return await self?.inspirationMayRun(computing: false) ?? false
            },
            mayTag: { [weak self] in
                guard !isDevelopment, Preferences().inspirationAICategories else { return false }
                return await self?.inspirationMayRun(computing: true) ?? false
            },
            aiCategories: { Preferences().inspirationAICategories }
        )
        let automation = InspirationAutomation(collector: collector, tagger: tagger, runLog: runLog, conditions: conditions)
        inspirationAutomation = automation
        library.services = .collection(automation, database: database)
        guard !isDevelopment else { return }
        let tick: @Sendable () -> Void = {
            Task.detached(priority: .utility) { await automation.tick() }
        }
        // The first minute belongs to the meeting the app may be resuming after a crash.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { tick() }
        inspirationTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in tick() }
        // At wake, once the network is back: a slot missed while the Mac slept is caught up once.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { tick() }
        }
    }

    /// No meeting under way, from the prompt to the end; with `computing`, no transcription nor summary either:
    /// the Mac's power and Apple's model go to them first.
    private func inspirationMayRun(computing: Bool) async -> Bool {
        guard !model.meetingUnderWay else { return false }
        guard computing else { return true }
        if await transcription?.isRunning ?? false { return false }
        return !(await summaries?.isRunning ?? false)
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
        // What it notifies is also kept in Polhub's own list, read by the bell of the sidebar (15/11).
        let hub = NotificationHub(agenda: agenda, inbox: NotificationInbox(file: paths.notifications))
        notifications = hub
        agenda.notifications = hub
        // The new mails of the main tab (14/11).
        mails?.onArrival = { arrived in Task { await hub.mailsArrived(arrived) } }
        mails?.onSendFailed = { subject, thread in Task { await hub.mailNotSent(subject: subject, threadKey: thread) } }
        // A programmed mail that left late, waits for Paul or did not leave (wave B).
        mails?.onScheduleNotice = { notice in Task { await hub.mailScheduleNotice(notice) } }
        // The card before a Meet: « Rejoindre » opens it in Dia under the event's account, as Coup d'œil does.
        meetingCards = MeetingCardPresenter(join: { [weak agenda] event in agenda?.join(event) },
                                            color: { [weak agenda] account in agenda?.color(for: account) ?? .accentColor })
        SystemNotifications.registerCategories()
        Task { @MainActor in
            _ = await SystemNotifications.requestAuthorization()
            await hub.refresh()
        }
        // Every minute: a meeting of the calendar under way while nothing records.
        notificationTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let recording = self.model.meetingUnderWay
                // Detection off (the development version, a pause): nothing is « non enregistrée ». The coordinator
                // never says « paused »: the pause is the model's (« Coup d'œil », 15/11).
                let paused = self.model.isPaused || !self.model.detectionOn
                Task { await hub.tick(recording: recording, paused: paused) }
            }
        }
    }

    // MARK: - Notifications

    /// Once a second: the card before a Meet shows, changes or goes. No card for the meeting Polhub records or
    /// offers to record: Paul is in it.
    private func updateMeetingCards(now: Date) {
        guard let meetingCards, let agenda, now.timeIntervalSince(meetingCardsLook) >= 1 else { return }
        meetingCardsLook = now
        let settings = Preferences()
        meetingCards.update(events: agenda.shown, now: now, enabled: settings.meetingCard, minutes: settings.meetingCardMinutes,
                            meetingCode: model.meetingUnderWay ? model.meetCode : nil)
    }

    /// Shown even when Polhub is in front.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    /// A click: « Rejoindre » joins the Meet with the event's account; otherwise the event, the meeting or the
    /// thread opens. The same as a click in Polhub's own list (`perform`, 15/11).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let kind = (info[NoticeKey.kind] as? String).flatMap(PlannedNotice.Kind.init(rawValue:))
        // A click joins only a reminder or a meeting not recorded; a new event, days ahead, opens its card (review
        // of 14/11). « Rejoindre » always joins.
        let join = action == NoticeKey.joinAction
            || (action == UNNotificationDefaultActionIdentifier && (kind == .reminder || kind == .unrecorded))
        let opened = NoticeAction.of(kind: kind, eventID: info[NoticeKey.event] as? String, meetCode: info[NoticeKey.meet] as? String,
                                     account: info[NoticeKey.account] as? String,
                                     meetingID: (info[NoticeKey.meeting] as? String).flatMap(UUID.init(uuidString:)),
                                     threadKey: info[NoticeKey.thread] as? String, folder: info[NoticeKey.folder] as? String, join: join)
        completionHandler()
        Task { @MainActor in self.perform(opened) }
    }

    /// What a notification is about, opened: the Meet in Dia, or the window on the meeting, the event, the thread,
    /// the mails' folder (« Programmés » for a mail that waits for Paul, wave B), Calendrier for several events.
    func perform(_ action: NoticeAction) {
        if router.perform(action, agenda: agenda, mails: mails) { showMainWindow() }
    }

    /// A meeting (from the pop-up to the end) or a transcription: nothing heavy runs meanwhile.
    private func recordingOrTranscribing() async -> Bool {
        let transcribing = await transcription?.isRunning ?? false
        // The app's own state is read last, with nothing waited for after it: a meeting that began while the
        // transcription was asked is seen (17/11).
        switch model.status {
        case .prompting, .recording, .presumedEnded: return true
        case .idle, .paused: return transcribing
        }
    }

    /// No meeting (from the pop-up to the end) and no transcription under way.
    private func isQuiet() async -> Bool {
        // What must be waited for is asked first; the app's own state is read after, and nothing waits after it.
        // A collection or the tagging under way: they finish first (16/11).
        let collecting = await inspirationAutomation?.isRunning ?? false
        let summarizing = await summaries?.isRunning ?? false
        if await recordingOrTranscribing() { return false }
        // A probe under way finishes first: an update now would cut it, and leave its Claude Code behind (17/11).
        if runner.running != nil { return false }
        // A mail leaving waits ten seconds in memory: an update now would call it back (14/11).
        if mails?.isSending == true { return false }
        return !collecting && !summarizing
    }

    /// The Mac goes to sleep: the probe of Colin stops. It wakes: nothing is launched for a few minutes (17/11).
    private func watchPower() {
        let center = NSWorkspace.shared.notificationCenter
        powerObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.colinProbe.macWillSleep() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.colinProbe.macWoke() }
            },
        ]
    }

    /// The app is going, by whatever way: the probe under way stops, and every Claude Code that Polhub launched
    /// with it.
    func stopClaude() {
        runner.stopForExit()
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
        // A collection or the tagging under way stops at once; its slot stays due (« Inspiration », 16/11).
        if busy { Task { await inspirationAutomation?.stop() } }
        // So does the probe of Colin, and the Claude Code it launched (17/11).
        if busy { colinProbe.meetingBegan() }
        if status == .idle {
            // The meeting that ended gets its event's project, title and guests now, not at the next sync.
            Task { await agenda?.runLinks() }
        }
    }

    // MARK: - Windows

    func showMainWindow() {
        guard let library else {
            showProbeWindow()
            return
        }
        if mainWindow == nil {
            let diagnostic = diagnostic
            let colin = colinProbe
            let view = MainWindowView(library: library, projects: projects, agenda: agenda, mails: mails, inspiration: inspiration,
                                      updates: updates, notifications: notifications, startup: startup, router: router, paths: paths) {
                if let diagnostic {
                    DiagnosticView(model: diagnostic, colin: colin) { [weak self] in self?.showProbeWindow() }
                }
            }
            // Every logo of a project reads it there; without it, initials (15/11).
            let host = NSHostingController(rootView: view.environment(\.projectLogos, projectLogos))
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
            router.clearHistory()
            followNavigation()
        }
        NSApp.setActivationPolicy(.regular)
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// « Précédent » and « Suivant » in the window (Paul, 16/11: his mouse's side buttons, as in a browser): the
    /// mouse's buttons, ⌘[ ⌘], ⌘← ⌘→ outside a text, the trackpad's swipe; the open project and the mails' folder told
    /// to the router, and given back by it.
    private func followNavigation() {
        guard navigationMonitor == nil else { return }
        let router = router
        router.restoreProject = { [weak self] id in self?.projects?.selected = id }
        router.restoreMailFolder = { [weak self] folder in self?.mails?.folder = folder }
        if let projects {
            navigationObservers.append(projects.$selected.sink { id in MainActor.assumeIsolated { router.projectChanged(id) } })
        }
        if let mails {
            navigationObservers.append(mails.$folder.sink { folder in MainActor.assumeIsolated { router.mailFolderChanged(folder) } })
        }
        navigationMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .keyDown, .swipe]) { [weak self] event in
            let handled: Bool = MainActor.assumeIsolated {
                guard let window = self?.mainWindow, event.window === window else { return false }
                switch NavigationInput.direction(of: event, editingText: window.firstResponder is NSTextView) {
                case .back?: router.goBack()
                case .forward?: router.goForward()
                case nil: return false
                }
                return true
            }
            return handled ? nil : event
        }
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
        // The others' sound is captured again, by a check just run (never an earlier « ok » left in the list, when
        // another line is checked): the self-test's alert goes.
        model.systemAudioChecked = { [weak self] state in
            if state == .ok { self?.model.resolve(.selfTestFailed) }
        }
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

    /// `code` 0 for a stop the relaunch agent must not undo (it relaunches only after a failure).
    static func alertThenExit(_ text: String, code: Int32 = 2) -> Never {
        FileHandle.standardError.write(Data("Polhub : \(text)\n".utf8))
        // In a script there is nobody to click: the alert is only shown in a real session.
        if ProcessInfo.processInfo.environment["POLHUB_NO_ALERT"] == nil {
            let alert = NSAlert()
            alert.messageText = "Polhub : problème au démarrage"
            alert.informativeText = text
            NSApp.activate()
            alert.runModal()
        }
        exit(code)
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

    /// A probe under way ends with the app: the Claude Code it launched is told at once, never left behind (17/11).
    func applicationWillTerminate(_ notification: Notification) {
        stopClaude()
    }

    /// The relaunch agent restarts the app after an abnormal exit only: a plain `kill` must end with code 0.
    private func exitCleanlyOnSIGTERM() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            // The handler runs on the main queue: a probe under way stops its Claude Code before the app goes.
            MainActor.assumeIsolated { self?.stopClaude() }
            exit(0)
        }
        source.resume()
        terminationSource = source
    }
}
