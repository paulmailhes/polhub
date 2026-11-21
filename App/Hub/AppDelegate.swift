import AppKit
import Colin
import Combine
import Domain
import Inspiration
import MeetingDetection
import MeetingsUI
import Observability
import Persistence
import HubCloud
import HubLink
import Pipeline
import HubDesign
import ProbeKit
import ProjectsUI
import Recording
import Summarization
import Security
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
            guard let self else { return "hub se ferme." }
            guard self.runner.running == nil else { return "Une autre sonde tourne déjà." }
            // One Claude Code of Colin's at a time (18/11).
            guard self.colinThread?.isAnswering != true else { return "Colin répond : relance la sonde dans un instant." }
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
    /// hub on the iPhone (20/11): Réglages › iPhone, and the server on the loopback when Paul switched it on.
    private var phone: PhoneAccess?

    /// The number on hub's icon (Paul, 20/11): the unread mails of the main tab and what hub told that was not
    /// seen yet, in the Dock, and on the iPhone's icon with each notification or alone when it changes.
    private func watchBadge(_ hub: NotificationHub) {
        let count: @MainActor () -> Int = { [weak self] in
            AppBadge.count(unreadMails: self?.mails?.unread(in: .personnes) ?? 0, notices: hub.inbox?.notices ?? [])
        }
        phone?.badge = count
        var changes: [AnyPublisher<Void, Never>] = []
        if let mails { changes.append(mails.objectWillChange.map { _ in () }.eraseToAnyPublisher()) }
        if let inbox = hub.inbox { changes.append(inbox.objectWillChange.map { _ in () }.eraseToAnyPublisher()) }
        badgeObserver = Publishers.MergeMany(changes)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] in
                MainActor.assumeIsolated {
                    let value = count()
                    NSApp.dockTile.badgeLabel = AppBadge.label(value)
                    Task { await self?.phone?.badgeChanged(value) }
                }
            }
        NSApp.dockTile.badgeLabel = AppBadge.label(count())
    }

    /// Whether this build carries iCloud's rights: the release does, the development build not. CloudKit stops an app
    /// that asks for a container it has no right to.
    static var carriesICloud: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil) else { return false }
        return (value as? [String])?.contains(CloudRecords.container) == true
    }
    /// What the Accueil knows (18/11): « À valider » and « Le point », kept up to date window open or not.
    private var colin: ColinLibrary?
    /// Colin's bar (18/11): his thread, and the one Claude Code it launches.
    private var colinThread: ColinThread?
    /// The Claude accounts Vigie knows, on the Accueil (0.36.0).
    private let claudeAccounts = ClaudeAccountsModel()
    private var presenceObserver: NSObjectProtocol?
    private var absenceObserver: NSObjectProtocol?
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
    /// Step 2: the transcriptions, run by `hub-calcul` outside meetings.
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
    /// The number on hub's icon, in the Dock and on the iPhone (20/11).
    private var badgeObserver: AnyCancellable?
    private var terminationSource: DispatchSourceSignal?
    private var guideObserver: AnyCancellable?
    /// Vigie's count, for the menu bar's logo (21/11).
    private var vigieObserver: AnyCancellable?
    /// Vigie's notifications, in the app Vigie's place (21/11).
    private var vigieNotifier: VigieNotifier?

    /// The add-ons installed (20/11), settled at launch: what is not installed is never made.
    private(set) var addOns = Set(AddOn.allCases)
    private var addOnControl: AddOnControl?
    private var dictation: DictationLibrary?
    private var dictationService: DictationService?
    /// Vigie, when installed (21/11): it talks to Vigie's own engine, already on the Mac.
    private var vigie: VigieLibrary?
    // The meetings.
    private(set) var store: MeetingStore?
    /// The folders, moved under the name hub-board at the first launch that has it (20/11), before anything opens the base.
    private(set) var paths: AppPaths = {
        for line in AppFolders.moveLegacyFolders(dev: AppFlavor.current == .dev) { NSLog("%@", line) }
        return AppPaths.standard(AppFlavor.current)
    }()
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

    /// Set before launch ends: a click on a notification may be what opened hub (14/11).
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
        // The add-ons installed (20/11), before the base is opened: a base already there has them all, a new one none.
        let addOnStore = AddOnStore(defaults: .standard)
        addOnStore.settle(baseExists: FileManager.default.fileExists(atPath: paths.database.path(percentEncoded: false)))
        addOns = addOnStore.installed
        // Réglages › Add-ons (20/11): installing or removing relaunches hub, never during a meeting.
        // The model of Réunions, downloaded when it is installed and missing, taken away when it is removed.
        // The models are shared by the installed and the development versions (13/11): their standard place.
        let models = ModelSetup()
        // Réunions and Dictée share it: it goes with the last of them (20/11).
        weak var installed: AddOnControl?
        let control = AddOnControl(store: addOnStore, isBusy: { [weak self] in !(await self?.isQuiet() ?? false) },
                                   relaunch: { [weak self] in self?.relaunchForAddOns() },
                                   prepare: { addOn in [.meetings, .dictation].contains(addOn) ? await models.prepare() : nil },
                                   cleanUp: { addOn in
                                       guard [.meetings, .dictation].contains(addOn), let after = installed?.installed,
                                             !after.contains(.meetings), !after.contains(.dictation) else { return }
                                       models.remove()
                                   })
        installed = control
        models.control = control
        control.claudeFound = ClaudeBinary.find() != nil
        // The tiles of Réglages › Add-ons (21/11): what this Mac has, and what a need's button does.
        control.facts = { [weak self, weak control] in
            guard let self else { return AddOnFacts() }
            return AddOnWiring.facts(agenda: self.agenda, mails: self.mails, phone: self.phone, claudeFound: control?.claudeFound ?? true,
                                     meetingsChecked: UserDefaults.standard.bool(forKey: Self.checklistDoneKey), vigie: self.vigie)
        }
        control.perform = { [weak self] action in
            guard let self else { return }
            AddOnWiring.perform(action, agenda: self.agenda, dictation: self.dictationService, router: self.router)
        }
        control.openSettings = { [weak self] addOn in
            guard let self else { return }
            AddOnWiring.openSettings(of: addOn, router: self.router)
        }
        addOnControl = control
        let store: MeetingStore
        do {
            let database = try AppDatabase(path: paths.database.path)
            self.database = database
            store = MeetingStore(database)
            // A session wrote through `hub mcp`: the views fetch again (13/11).
            externalChanges = ExternalChangeSignal.listen(queue: .main) { try? database.notifyExternalChanges() }
        } catch AppDatabaseError.newerBase {
            // Not a crash: a plain exit, which the relaunch agent leaves alone, instead of the same alert every
            // ten seconds (correctifs, 15/11). Its sentence is hub's own, in French (lot 10, 20/11).
            Self.alertThenExit(AppDatabaseError.newerBase.errorDescription ?? "", code: 0)
        } catch {
            // What did not work, in French, then what to do; the system's own text goes to the log, the base is not
            // there for the journal (lot 10, 20/11). hub quits after the alert: reopening it is the gesture.
            let problem = Words.problem("La base des réunions ne s'ouvre pas", error, remedy: "Rouvre hub.")
            if let journal = problem.journal { NSLog("%@", journal) }
            Self.alertThenExit(problem.sentence)
        }
        self.store = store
        library = MeetingLibrary(store: store)
        projects = addOns.contains(.projects) ? ProjectLibrary(store: ProjectStore(store.database), meetings: store) : nil
        projectLogos = ProjectLogos(folder: paths.logos, database: store.database)
        startAgenda(database: store.database)
        // The Dictée (20/11): its helper keeps Whisper loaded, the key is watched.
        if addOns.contains(.dictation) {
            let library = DictationLibrary(database: store.database, sounds: paths.dictation)
            // The music paused through `hub-media.dylib`; the Mac's sound left alone while hub records a meeting.
            let service = DictationService(library: library, helper: Bundle.main.bundleURL.appending(path: "Contents/Helpers/hub-dictee"),
                                           media: Bundle.main.bundleURL.appending(path: "Contents/Helpers/hub-media.dylib"),
                                           inMeeting: { [weak self] in
                                               switch self?.model.status {
                                               case .prompting, .recording, .presumedEnded: true
                                               default: false
                                               }
                                           })
            // What each dictation took, in the day's log: times only, never a word (21/11).
            service.timingFolder = paths.logs
            service.start()
            dictation = library
            dictationService = service
            coupDoeil.dictation = library
        }
        // Nothing installed yet (a new Mac): the window opens on Réglages › Add-ons, under the Bienvenue (21/11).
        if addOns.isEmpty {
            router.section = .settings
            router.settingsPane = .addOns
            control.showsWelcome = true
            DispatchQueue.main.async { [weak self] in self?.showMainWindow() }
        }
        // After an installation's relaunch: the guide of what the new add-ons need, over Réglages › Add-ons. A moment
        // after the launch: the Google accounts are read from the base by then.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak control] in
            guard let self, let control else { return }
            control.openPendingGuide()
            guard control.showsGuide else { return }
            self.router.openSettings(.addOns)
            self.showMainWindow()
        }
        // Vigie (21/11): what its engine sees, read every few seconds; its decisions' count rides the logo of the menu bar.
        if addOns.contains(.vigie) {
            let library = VigieLibrary()
            library.start()
            vigie = library
            coupDoeil.vigie = library
            vigieObserver = library.objectWillChange.receive(on: RunLoop.main).sink { [weak self, weak library] _ in
                guard let self, let library else { return }
                self.model.vigieDecisions = library.decisions.count
            }
            // hub notifies in the app Vigie's place, never while it runs (21/11, the migration).
            let notifier = VigieNotifier(post: { [weak self] notice in
                if let hub = self?.notifications { await hub.vigie(notice) } else { await SystemNotifications().deliverNow(notice, sound: !notice.quiet) }
            }, remove: { [weak self] ids in
                if let hub = self?.notifications { await hub.removeVigie(ids) } else { await SystemNotifications().removeDelivered(ids) }
            })
            vigieNotifier = notifier
            library.onRead = { [weak self] overview in
                Task { @MainActor in
                    // The Vigie page in front: no banner for what it already shows.
                    let front = NSApp.isActive && self?.router.section == .vigie
                    await notifier.process(overview, inFront: { _ in front })
                }
            }
        }
        if addOns.contains(.inspiration) { startInspiration(database: store.database) }
        // Before the diagnostic, which may open the window: the window takes the update service as it is
        // when it opens, and Réglages › Mises à jour needs it (13/11).
        startUpdates(store: store)
        startDiagnostic(store: store)
        let presenter = HUDPresenter(model: model, app: self)
        self.presenter = presenter
        let day = Date().formatted(.iso8601.year().month().day().dateSeparator(.omitted))
        detectionLog = try? TraceWriter(fileURL: paths.logs.appending(path: "detection-\(day).jsonl"))

        // Réunions (20/11): the detection, the recording, the transcriptions and the summaries only when installed.
        if addOns.contains(.meetings) { startRecording(store: store, presenter: presenter) }

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

    /// An add-on installed or removed (20/11): hub quits, then starts again, making only what is installed.
    private func relaunchForAddOns() {
        do {
            try DetachedShell.relaunch()
        } catch {
            // The system's text to the log, by `Words.problem` (lot 10, 20/11).
            if let journal = Words.problem("La relance pour les add-ons n'a pas pu partir", error).journal { NSLog("%@", journal) }
            return
        }
        NSApp.terminate(nil)
    }

    /// Réunions (20/11): the coordinator that detects and records the Meets, then the transcriptions and the summaries.
    private func startRecording(store: MeetingStore, presenter: HUDPresenter) {
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
    }

    /// Colin's rules, counted on Paul's own mails before the Accueil shows them (18/11): once per version, a minute
    /// after the launch, then at the first quiet moment. Numbers only, written among the measures: no model, and
    /// nothing leaves the Mac. The development version, which has its own base, counts nothing.
    private func countColinRulesOnce() {
        let key = Preferences.Key.colinRulesCount
        guard AppFlavor.current != .dev, let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              UserDefaults.standard.string(forKey: key) != version else { return }
        Task { [weak self] in
            var wait = Duration.seconds(60)
            var attempts = 0
            // Never beside a meeting: asked again every five minutes, for a day at most. The version is noted once
            // a count went to its end; one that could not read the base is tried again, three times in all.
            for _ in 0..<288 {
                try? await Task.sleep(for: wait)
                wait = .seconds(300)
                guard let self, UserDefaults.standard.string(forKey: key) != version, attempts < 3 else { return }
                guard await self.isQuiet() else { continue }
                let started = self.runner.start(ProbeRequest(probe: .colinRules)) { [weak self] _ in
                    if let directory = self?.runner.lastDirectory, ColinRulesProbe.completed(in: directory) {
                        UserDefaults.standard.set(version, forKey: key)
                    }
                }
                if started { attempts += 1 }
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
        let helper = Bundle.main.bundleURL.appending(path: "Contents/Helpers/hub-calcul")
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
        // The app changed its name (Polhub.app → hub.app, 0.58.0): the relaunch that was on is registered again from its
        // new place, once. launchd then starts its own copy, which this one hands over to.
        let reregistered = "relanceReinscrite"
        if UserDefaults.standard.bool(forKey: Preferences.Key.relaunchHint), !UserDefaults.standard.bool(forKey: reregistered) {
            UserDefaults.standard.set(true, forKey: reregistered)
            _ = RelaunchAgent.disable()
            if let problem = RelaunchAgent.enable() { NSLog("%@", problem) }
        }
        // Whether the relaunch is on, for the version that changes its name (0.57.1, 20/11).
        UserDefaults.standard.set(RelaunchAgent.isEnabled, forKey: Preferences.Key.relaunchHint)
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
        // Calendrier, Mails and Colin follow their add-ons (20/11); the Google accounts live with the agenda.
        let agenda = addOns.contains(.calendar) ? AgendaLibrary(database: database) : nil
        self.agenda = agenda
        if let agenda {
            // The events the agents ask for (`rendez_vous`, 16/11), at their signal and at launch.
            agenda.startAgentEvents(root: paths.root)
            // The mails (14/11): the mailboxes that granted them are followed from the launch, window open or not.
            // The programmed sends live in the Keychain (wave B); the development build never touches it.
            if addOns.contains(.mails) {
                let mails = MailLibrary(agenda: agenda, root: paths.root, schedules: .keychain)
                self.mails = mails
                mails.start()
            }
            if addOns.contains(.colin), let mails { startColin(database: database, agenda: agenda, mails: mails) }
        }
        // hub on the iPhone (20/11): mails, agenda, projects, meetings and Colin's thread. The development build listens one
        // port further, so both can run.
        if addOns.contains(.iphone) {
            let phone = PhoneAccess(database: database, agenda: agenda, mails: mails, colin: colinThread,
                                    appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
                                    port: isDevelopment ? LinkAPI.port + 1 : LinkAPI.port,
                                    // The copy in iCloud (20/11): only a build that carries iCloud's rights asks CloudKit.
                                    cloud: Self.carriesICloud ? ICloudDrive() : nil,
                                    addOns: { [addOns] in addOns })
            self.phone = phone
            Task { await phone.resume() }
        }
        guard let agenda else { return }
        // hub comes back in front on the Accueil: Paul is there.
        presenceObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.accueilMayBeSeen() }
        }
        // Another app comes in front while the Accueil shows: Paul's absence starts then.
        absenceObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.accueilLeft() }
        }
        router.section = .home
        agendaTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
            Task { @MainActor in await agenda.syncAll() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            Task { @MainActor in await agenda.syncAll() }
        }
        startNotifications(agenda: agenda)
    }

    /// Colin (18/11): what waits for Paul's click and « Le point », rules alone; his bar, the Claude Code of this Mac on the
    /// account of Réglages › Colin, with hub's tools in Colin's profile, on this build's own base. Nothing is launched
    /// before Paul asks.
    private func startColin(database: AppDatabase, agenda: AgendaLibrary, mails: MailLibrary) {
        colin = ColinLibrary(agenda: agenda, mails: mails)
        let base = paths.database
        let runner = ColinRunner(launcher: LiveClaudeLauncher(), setup: {
            guard let binary = ClaudeBinary.find(), let helper = ColinProbe.embeddedHelper() else { return nil }
            let account = ClaudeCommand.account(folder: UserDefaults.standard.string(forKey: Preferences.Key.colinAccount),
                                                home: FileManager.default.homeDirectoryForCurrentUser)
            // An empty folder whose path names no one: the model is told where it works.
            return ColinSetup(binary: binary, helper: helper, base: base, account: account,
                              work: FileManager.default.temporaryDirectory.appending(path: "colin-travail", directoryHint: .isDirectory))
        })
        colinThread = ColinThread(database: database, runner: runner, review: { [weak self] in ColinThread.sentences(of: self?.colin?.review ?? []) },
                                  isBusy: { [weak self] in await self?.colinMustWait() ?? true },
                                  sinceWake: {
                                      let uptime = ProcessInfo.processInfo.systemUptime
                                      return min(uptime, ColinProbeControl.systemSinceWake() ?? uptime)
                                  },
                                  newDrafts: { [weak mails] in Set(mails.map { $0.drafts.filter { $0.origin == .agent }.map(\.id) } ?? []) })
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
        // The vocabularies the menus read: hub's copy (the vault's, brought while there was one), else the bundled.
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
        // What it notifies is also kept in hub's own list, read by the bell of the sidebar (15/11).
        let hub = NotificationHub(agenda: agenda, inbox: NotificationInbox(file: paths.notifications))
        notifications = hub
        agenda.notifications = hub
        // The iPhone gets what the Mac notifies, and the reminders at their time (20/11).
        if let phone {
            hub.phone = { [weak phone] notice in await phone?.notify(notice) }
            hub.phoneReminders = { [weak phone] plan in phone?.plan(plan) }
        }
        // The new mails of the main tab (14/11).
        mails?.onArrival = { arrived in Task { await hub.mailsArrived(arrived) } }
        // Every new mail on the iPhone, as Gmail would show it (20/11).
        mails?.onPhoneArrival = { arrived in Task { await hub.phoneMailsArrived(arrived) } }
        watchBadge(hub)
        mails?.onSendFailed = { subject, thread in Task { await hub.mailNotSent(subject: subject, threadKey: thread) } }
        // A programmed mail that left late, waits for Paul or did not leave (wave B).
        mails?.onScheduleNotice = { notice in Task { await hub.mailScheduleNotice(notice) } }
        // A draft an agent prepared: Colin says it is ready (18/11). A click opens the Accueil.
        // One Paul just asked of Colin in the bar does not ring: he is there.
        mails?.onAgentDrafts = { [weak self] drafts in
            guard self?.colinThread?.answeredRecently != true else { return }
            Task { await hub.draftsReady(drafts) }
        }
        // The card before a Meet: « Rejoindre » opens it in Dia under the event's account, as Coup d'œil does. An
        // account without its color is grey, never the Mac's accent (design system v2, 19/11).
        meetingCards = MeetingCardPresenter(join: { [weak agenda] event in agenda?.join(event) },
                                            color: { [weak agenda] account in agenda?.color(for: account) ?? .secondary })
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

    /// Once a second: the card before a Meet shows, changes or goes. No card for the meeting hub records or
    /// offers to record: Paul is in it.
    private func updateMeetingCards(now: Date) {
        guard let meetingCards, let agenda, now.timeIntervalSince(meetingCardsLook) >= 1 else { return }
        meetingCardsLook = now
        let settings = Preferences()
        meetingCards.update(events: agenda.shown, now: now, enabled: settings.meetingCard, minutes: settings.meetingCardMinutes,
                            meetingCode: model.meetingUnderWay ? model.meetCode : nil)
    }

    /// Shown even when hub is in front.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    /// A click: « Rejoindre » joins the Meet with the event's account; otherwise the event, the meeting or the
    /// thread opens. The same as a click in hub's own list (`perform`, 15/11).
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
                                     threadKey: info[NoticeKey.thread] as? String, folder: info[NoticeKey.folder] as? String, join: join,
                                     vigie: info[NoticeKey.vigie] as? String)
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
    /// Colin's bar waits during a call, its transcription, and a probe under way (one Claude Code of Colin's at a time).
    private func colinMustWait() async -> Bool {
        if await recordingOrTranscribing() { return true }
        return runner.running != nil
    }

    private func isQuiet() async -> Bool {
        // What must be waited for is asked first; the app's own state is read after, and nothing waits after it.
        // A collection or the tagging under way: they finish first (16/11).
        let collecting = await inspirationAutomation?.isRunning ?? false
        let summarizing = await summaries?.isRunning ?? false
        if await recordingOrTranscribing() { return false }
        // A probe under way finishes first: an update now would cut it, and leave its Claude Code behind (17/11).
        if runner.running != nil { return false }
        // Colin answering: an update now would cut his answer (18/11).
        if colinThread?.isAnswering == true { return false }
        // A mail leaving waits ten seconds in memory: an update now would call it back (14/11).
        if mails?.isSending == true { return false }
        return !collecting && !summarizing
    }

    /// The Mac goes to sleep: the probe of Colin stops. It wakes: nothing is launched for a few minutes (17/11).
    private func watchPower() {
        let center = NSWorkspace.shared.notificationCenter
        powerObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.colinProbe.macWillSleep()
                    self?.colinThread?.macWillSleep()
                    // The Mac goes to sleep with the Accueil before Paul: he leaves now.
                    if NSApp.isActive { self?.accueilLeft() }
                }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.colinProbe.macWoke()
                    // The thresholds passed while the Mac slept; and Paul is back before the Accueil, if it shows.
                    self?.colin?.refresh()
                    self?.accueilMayBeSeen()
                }
            },
        ]
    }

    /// The Accueil is before Paul: hub in front, its window shown, on the Accueil. « Le point » is prepared when
    /// he is back (the first time of a day, or three hours later).
    /// Paul leaves the Accueil: its window showed it, and something else takes his eyes. His absence starts now.
    private func accueilLeft() {
        guard let window = mainWindow, window.isVisible, !window.isMiniaturized, router.section == .home else { return }
        colin?.left()
    }

    private func accueilMayBeSeen() {
        guard NSApp.isActive, let window = mainWindow, window.isVisible, !window.isMiniaturized, router.section == .home else { return }
        colin?.seen()
    }

    /// The app is going, by whatever way: the probe under way stops, and every Claude Code that hub launched
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
        if busy {
            colinProbe.meetingBegan()
            colinThread?.meetingBegan()
        }
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
            let probe = colinProbe
            let view = MainWindowView(library: library, projects: projects, agenda: agenda, mails: mails, colin: colin, thread: colinThread, colinProbe: colinProbe, claudeAccounts: claudeAccounts, inspiration: inspiration,
                                      updates: updates, notifications: notifications, startup: startup, phone: phone, addOns: addOns, addOnControl: addOnControl,
                                      dictation: dictation, dictationService: dictationService, vigie: vigie, router: router, paths: paths) {
                if let diagnostic {
                    DiagnosticView(model: diagnostic, colin: probe, connections: addOnControl, notifications: notifications) { [weak self] in self?.showProbeWindow() }
                }
            }
            // Every logo of a project reads it there; without it, initials (15/11). hub's own accent, ink, whatever
            // the Mac's (design system v2, 19/11).
            let host = NSHostingController(rootView: view.environment(\.projectLogos, projectLogos).tint(Tint.control.color))
            // Each page's title and toolbar go to the window (14/11).
            host.sceneBridgingOptions = [.title, .toolbars]
            let window = NSWindow(contentViewController: host)
            window.title = "hub"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.setContentSize(NSSize(width: 1_180, height: 720))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setFrameAutosaveName("hub.main")
            window.center()
            mainWindow = window
            router.clearHistory()
            followNavigation()
        }
        NSApp.setActivationPolicy(.regular)
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        // The window is shown to Paul on the Accueil (it was closed, not gone: its page does not appear again by itself).
        if router.section == .home { colin?.seen() }
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
        // And the window's keys (lot 4, 19/11): ⌘1 to ⌘7 in the sidebar's order, ⌘, ⌘N and ⌘F. A mail's editor writes too:
        // ⌘← and ⌘→ are its line's start and end there, never « Précédent ».
        navigationMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .keyDown, .swipe]) { [weak self] event in
            let handled: Bool = MainActor.assumeIsolated {
                guard let self, let window = self.mainWindow, event.window === window,
                      let command = NavigationInput.command(of: event, editingText: NavigationInput.isEditing(window.firstResponder))
                else { return false }
                return self.windowKeys.run(command, in: window)
            }
            return handled ? nil : event
        }
    }

    /// What the window's keys do, on the sidebar the window shows (lot 4, 19/11).
    private var windowKeys: WindowKeys {
        WindowKeys(router: router, mails: mails, projects: projects,
                   sections: SidebarItem.numbered(hasProjects: projects != nil, hasAgenda: agenda != nil, hasMails: mails != nil,
                                                  hasInspiration: inspiration != nil))
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
                    ? "Relance activée : hub passe sous la garde de macOS. Cette fenêtre va se fermer ; rouvre-la par l'icône de la barre des menus."
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
        // Réunions' own list: it opens the window only when Réunions is installed (21/11 — a new Mac opened on it
        // instead of the add-ons, and it came back at every launch for who has no Réunions).
        if addOns.contains(.meetings), !defaults.bool(forKey: Self.checklistDoneKey) {
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

    /// ⌘Q, « Quitter hub », a logout: during a recording, or with a mail about to leave, Paul is asked first (audit
    /// of 19/11). An update quits by itself, only when all is quiet, and never comes here.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let question = QuitGuard.question(status: model.status, sending: mails?.isSending ?? false) else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = question.title
        alert.informativeText = question.detail
        alert.addButton(withTitle: question.stay)
        alert.addButton(withTitle: question.quit)
        NSApp.activate()
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
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
        FileHandle.standardError.write(Data("hub : \(text)\n".utf8))
        // In a script there is nobody to click: the alert is only shown in a real session.
        if ProcessInfo.processInfo.environment["HUB_NO_ALERT"] == nil {
            let alert = NSAlert()
            alert.messageText = "hub : problème au démarrage"
            alert.informativeText = text
            NSApp.activate()
            alert.runModal()
        }
        exit(code)
    }

    func showProbeWindow() {
        if probeWindow == nil {
            // hub's own accent, ink, as in the main window (design system v2, 19/11).
            let window = NSWindow(contentViewController: NSHostingController(rootView: ProbeWindow(runner: runner).tint(Tint.control.color)))
            window.title = "Sondes — hub"
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
