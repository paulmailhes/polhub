import AppKit
import ApplicationServices
import AudioCapture
import Dictation
import Foundation
import HubDesign
import Persistence

/// The Dictée at work (20/11): it launches the helper `hub-dictee`, which listens and writes; it watches the key; it
/// shows the window that says what is happening; then it pastes the text where the cursor was, and keeps it in the
/// history. 21/11: the key answers from the helper's first second, and the window always says why when it cannot.
@MainActor public final class DictationService: ObservableObject {
    public enum Phase: Equatable, Sendable {
        /// The helper is not there yet: hub has just been launched, or the helper starts again.
        case starting
        case ready
        case listening
        /// The final text is being written.
        case writing
        case failed(String)
    }

    @Published public private(set) var phase: Phase = .starting
    /// Whisper is loaded (about 20 s after the launch): until then a dictation is heard, and written as soon as it is.
    @Published public private(set) var whisperLoaded = false
    /// The microphone gives sound: Paul can talk.
    @Published public private(set) var micOpen = false
    /// The words said so far.
    @Published public private(set) var partial = ""
    @Published public private(set) var level: Double = 0
    /// The final writing's progress, 0 to 1.
    @Published public private(set) var progress: Double = 0
    /// How the last dictation ended, said in the window before it closes.
    @Published private(set) var outcome: DictationOutcome?
    /// Seconds before a long silence finishes the dictation, once it is near.
    @Published public private(set) var silenceLeft: Int?
    /// Whether macOS lets hub watch the key everywhere and paste into the other apps.
    @Published public private(set) var trusted = AXIsProcessTrusted()
    /// When the microphone started to give sound, for the window's clock.
    @Published public private(set) var startedAt: Date?
    /// The window at the top of the screen (Réglages › Dictée), read at each dictation.
    @Published public private(set) var windowAtTop = false
    /// The files being written (« Transcrire un fichier »), and the dictations written again, by the helper's id.
    @Published public private(set) var working: [String: String] = [:]
    /// What a file's writing said when it failed, shown once in the page.
    @Published public var fileProblem: String?

    let library: DictationLibrary
    let helper: URL
    private var process: Process?
    private var input: FileHandle?
    private var gesture: KeyGesture
    private var monitors: [Any] = []
    private var ticker: Timer?
    private var target: NSRunningApplication?
    private var pill: DictationPill?
    private var restarts = 0
    /// The id the dictation under way will have: its sound is kept under it.
    private var dictationID = UUID()
    private var silence: SilenceWatch?
    private let sound: DictationSound
    /// Whether hub records a meeting: then the Mac's sound and the music are left alone.
    private let inMeeting: @MainActor () -> Bool
    private var lastPurge = Date.distantPast
    private var lastKnown = Date.distantPast
    /// The window's closing that counts: a new dictation cancels the one asked before.
    private var hideToken = 0
    /// Réglages › Dictée; the tests give their own.
    private let defaults: UserDefaults
    private var settings: DictationSettings { DictationSettings(defaults: defaults) }
    /// For the tests: no window on the screen, a file played as the microphone, and where the text goes instead of the
    /// app in front.
    var showsWindow = true
    var testSource: String?
    var testDelivery: ((String) -> Void)?
    /// Where each dictation's times are written (the app's logs); nil: nowhere.
    public var timingFolder: URL?
    private var timing = DictationTiming()
    private var pressedAt: TimeInterval = 0
    private var listeningAt: TimeInterval = 0
    private var stoppedAt: TimeInterval = 0

    /// `media`: `hub-media.dylib`, which pauses the music; nil: the music is never paused.
    public init(library: DictationLibrary, helper: URL, media: URL? = nil, defaults: UserDefaults = .standard,
                inMeeting: @escaping @MainActor () -> Bool = { false }) {
        self.library = library
        self.helper = helper
        self.inMeeting = inMeeting
        self.defaults = defaults
        gesture = KeyGesture(mode: DictationSettings(defaults: defaults).mode)
        sound = DictationSound(settings: { DictationSettings(defaults: defaults) }, media: MediaPause(bridge: media.map(MediaBridge.init(library:))))
    }

    public func start() {
        // A hub stopped mid-dictation left the Mac muted: its sound comes back.
        OutputMute.unmute()
        launch()
        watchKey()
        purge()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.apply(self.gesture.tick(at: ProcessInfo.processInfo.systemUptime))
                // Accessibility given in Réglages Système: noticed without a relaunch.
                if !self.trusted, AXIsProcessTrusted() { self.trusted = true; self.watchKey() }
                if Date().timeIntervalSince(self.lastPurge) > 3_600 { self.purge() }
                // The names hub knows, read away from the key: a press never waits for the base.
                if Date().timeIntervalSince(self.lastKnown) > 300, self.phase == .ready { self.refreshKnown() }
            }
        }
    }

    public func stop() {
        ticker?.invalidate()
        ticker = nil
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        process?.terminate()
        process = nil
    }

    /// Réglages › Dictée's button: macOS shows hub in its list, then the page opens.
    public func askAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// What the window needs to say what is happening.
    var windowState: DictationWindowState {
        DictationWindowState(phase: phase, micOpen: micOpen, whisperLoaded: whisperLoaded, partial: partial,
                             liveText: settings.on(Preferences.Key.dictationLiveText), progress: progress, outcome: outcome,
                             silenceLeft: silenceLeft, mode: gesture.mode, key: DictationKey.current.title)
    }

    // MARK: - The helper

    private func launch() {
        let process = Process()
        process.executableURL = helper
        let toHelper = Pipe(), fromHelper = Pipe()
        process.standardInput = toHelper
        process.standardOutput = fromHelper
        process.standardError = FileHandle.nullDevice
        let lines = LineSplitter()
        fromHelper.fileHandleForReading.readabilityHandler = { [weak self] handle in
            for line in lines.add(handle.availableData) {
                guard let event = try? DictationWire.read(DictationEvent.self, line) else { continue }
                Task { @MainActor in self?.handle(event) }
            }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.helperStopped() }
        }
        do {
            try process.run()
            self.process = process
            input = toHelper.fileHandleForWriting
            phase = .starting
            whisperLoaded = false
        } catch {
            phase = .failed("La Dictée ne démarre pas : relance hub.")
        }
    }

    /// The helper died: what was under way is given up and said, and it is started again — three times at most.
    private func helperStopped() {
        guard process != nil else { return }
        process = nil
        input = nil
        whisperLoaded = false
        let wasBusy = phase == .listening || phase == .writing
        if phase == .listening { sound.stopped(finished: false) }
        silence = nil
        silenceLeft = nil
        gesture = KeyGesture(mode: mode)
        working = [:]
        restarts += 1
        guard restarts <= 3 else {
            phase = .failed("La Dictée s'est arrêtée : relance hub.")
            if wasBusy { tell(.problem("La Dictée s'est arrêtée : relance hub."), for: 4) }
            return
        }
        phase = .starting
        if wasBusy { tell(.problem("La Dictée s'est arrêtée. Elle redémarre : réessaie dans un instant."), for: 4) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.process == nil, self.ticker != nil else { return }
            self.launch()
        }
    }

    private func send(_ command: DictationCommand) {
        guard let input, let line = try? DictationWire.line(command) else { return }
        input.write(Data((line + "\n").utf8))
    }

    private func handle(_ event: DictationEvent) {
        switch event {
        case .hello:
            // The helper takes its orders: the key works, even while Whisper loads.
            if phase == .starting { phase = .ready }
        case .ready:
            whisperLoaded = true
            restarts = 0
            if phase == .starting { phase = .ready }
        case .listening:
            microphoneOpened()
        case .level(let value):
            level = value
            watchSilence(value)
        case .partial(let text):
            if phase == .listening, text != partial {
                timing.updates += 1
                if timing.firstWords == nil, listeningAt > 0 { timing.firstWords = Self.ms(since: listeningAt) }
            }
            if phase == .listening || phase == .writing, settings.on(Preferences.Key.dictationLiveText) { partial = text }
        case .progress(let value):
            if phase == .writing { progress = max(progress, value) }
        case .final(let text, let seconds):
            finish(text, seconds: seconds)
        case .transcribed(let id, let text, let seconds):
            written(id: id, raw: text, seconds: seconds)
        case .fileFailed(let id, let reason):
            working[id] = nil
            fileProblem = reason
        case .failed(let reason):
            failed(reason)
        }
    }

    // MARK: - The key

    /// Réglages › Dictée: a press starts and a press finishes, by default.
    private var mode: KeyGesture.Mode { settings.mode }

    /// Everywhere when macOS trusts hub (Accessibility), else only while hub is in front.
    private func watchKey() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) { monitors.append(local) }
    }

    private func handle(_ event: NSEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        // A way changed in Réglages takes effect at the next dictation.
        if gesture.state == .idle, gesture.mode != mode { gesture = KeyGesture(mode: mode) }
        let key = DictationKey.current
        switch event.type {
        case .flagsChanged where event.keyCode == key.keyCode:
            self.key(down: event.modifierFlags.contains(key.flag), at: now)
        case .flagsChanged:
            // Another modifier with the key: a character is being typed.
            apply(gesture.otherKey())
        case .keyDown where event.keyCode == 53:
            escape()
        case .keyDown:
            apply(gesture.otherKey())
        default:
            break
        }
    }

    /// The Dictée's key goes down or up.
    func key(down: Bool, at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        apply(down ? gesture.keyDown(at: now) : gesture.keyUp(at: now))
    }

    /// Échap: the dictation under way is given up.
    func escape() {
        apply(gesture.escape())
    }

    private func apply(_ action: KeyGesture.Action) {
        switch action {
        case .start:
            guard phase == .ready else {
                // Not a dictation: the window says why, and the next press is a first press again.
                explain()
                gesture = KeyGesture(mode: mode)
                return
            }
            let settings = settings
            target = NSWorkspace.shared.frontmostApplication
            partial = ""
            outcome = nil
            progress = 0
            level = 0
            micOpen = false
            silence = nil
            silenceLeft = nil
            startedAt = nil
            windowAtTop = settings.windowAtTop
            dictationID = UUID()
            hideToken += 1
            timing = DictationTiming()
            pressedAt = ProcessInfo.processInfo.systemUptime
            listeningAt = 0
            stoppedAt = 0
            phase = .listening
            var listening = listeningOptions(settings)
            listening.microphones = settings.microphones
            listening.keepSoundAt = settings.on(Preferences.Key.dictationKeepSound) ? library.soundURL(dictationID).path(percentEncoded: false) : nil
            listening.source = testSource
            send(.start(listening))
            sound.pressed(inMeeting: inMeeting())
            showPill()
        case .finish:
            guard phase == .listening else { return }
            phase = .writing
            silence = nil
            silenceLeft = nil
            stoppedAt = ProcessInfo.processInfo.systemUptime
            send(.stop)
            sound.stopped(finished: true)
        case .cancel:
            guard phase == .listening else { return }
            send(.cancel)
            silence = nil
            silenceLeft = nil
            phase = .ready
            pill?.hide()
            sound.stopped(finished: false)
            log("annulé")
        case .none:
            break
        }
    }

    /// The key pressed while the Dictée cannot listen: the window says why, instead of nothing.
    private func explain() {
        switch phase {
        case .starting: tell(.notReady("La Dictée démarre…"), for: 2)
        case .failed(let why): tell(.problem(why), for: 4)
        case .ready, .listening, .writing: break
        }
    }

    /// The microphone gives sound: the small sound says « parle », the clock and the silence count from here.
    private func microphoneOpened() {
        guard phase == .listening, !micOpen else { return }
        micOpen = true
        startedAt = Date()
        listeningAt = ProcessInfo.processInfo.systemUptime
        timing.microphone = Self.ms(since: pressedAt)
        silence = settings.autoStop.map { SilenceWatch(after: $0, startedAt: ProcessInfo.processInfo.systemUptime) }
        sound.listening(inMeeting: inMeeting())
    }

    /// The language, the memory and the paragraphs, for a dictation or a file.
    private func listeningOptions(_ settings: DictationSettings) -> DictationListening {
        let language = defaults.string(forKey: Preferences.Key.dictationLanguage) == "auto" ? nil : "fr"
        return DictationListening(language: language, prompt: library.prompt, paragraphPause: settings.paragraphPause)
    }

    /// « Arrêt seul » (20/11 in the evening): a long silence finishes the dictation, when the key is not held; its last
    /// three seconds are counted in the window.
    private func watchSilence(_ value: Double) {
        guard phase == .listening, [.listening, .handsFree].contains(gesture.state), var watch = silence else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let finish = watch.hear(value, at: now)
        silence = watch
        let left = Int(watch.remaining(at: now).rounded(.up))
        let shown: Int? = (1...3).contains(left) ? left : nil
        if shown != silenceLeft { silenceLeft = shown }
        guard finish else { return }
        apply(.finish)
        // The key is free again: the next press starts a dictation.
        gesture = KeyGesture(mode: mode)
    }

    // MARK: - The text

    private func finish(_ raw: String, seconds: Double) {
        guard phase == .writing else { return }
        let text = DictationText.clean(raw, replacements: library.corrections, rules: settings.rules)
        phase = .ready
        progress = 1
        // The names hub knows, for the next dictation: read now, not when the key is pressed.
        DispatchQueue.main.async { [weak self] in self?.refreshKnown() }
        timing.final = Self.ms(since: stoppedAt)
        timing.seconds = (seconds * 10).rounded() / 10
        timing.characters = text.count
        guard !text.isEmpty else {
            library.removeSound(dictationID)
            log("rien")
            tell(.nothing, for: 1.8)
            return
        }
        library.keep(DictationRow(id: dictationID, text: text, raw: raw, app: target?.localizedName, seconds: seconds, createdAt: Date()))
        // A space after, to dictate the next sentence straight on (Réglages › Dictée).
        let space = settings.on(Preferences.Key.dictationTrailingSpace) && !text.hasSuffix("\n") ? " " : ""
        if let testDelivery {
            testDelivery(text + space)
            log("collé")
            tell(.pasted(app: nil, text: text), for: 0.2)
        } else if trusted, AXIsProcessTrusted() {
            Paster.paste(text + space, restore: settings.on(Preferences.Key.dictationRestoreClipboard))
            log("collé")
            tell(.pasted(app: target?.localizedName, text: text), for: 1)
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            log("copié")
            tell(.copied(text: text), for: 3)
        }
    }

    /// A failure during a dictation (the microphone that does not open): said in the window, the Mac's sound given back,
    /// and the Dictée ready for the next one — the helper is still there. Outside a dictation, it is the Dictée's state.
    private func failed(_ reason: String) {
        guard phase == .listening || phase == .writing else {
            phase = .failed(reason)
            pill?.hide()
            return
        }
        if phase == .listening { sound.stopped(finished: false) }
        silence = nil
        silenceLeft = nil
        gesture = KeyGesture(mode: mode)
        phase = .ready
        log("échec")
        tell(.problem(reason), for: 4)
    }

    /// The dictation's times, in the day's log.
    private func log(_ end: String) {
        timing.end = end
        timing.write(in: timingFolder)
    }

    static func ms(since instant: TimeInterval) -> Int {
        Int(((ProcessInfo.processInfo.systemUptime - instant) * 1_000).rounded())
    }

    /// Says how a dictation ended, then closes the window — unless another dictation has begun.
    private func tell(_ outcome: DictationOutcome, for seconds: Double) {
        self.outcome = outcome
        showPill()
        hideToken += 1
        let token = hideToken
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.hideToken == token, self.phase != .listening, self.phase != .writing else { return }
            self.pill?.hide()
            self.outcome = nil
        }
    }

    private func refreshKnown() {
        lastKnown = Date()
        library.refreshKnown()
    }

    // MARK: - The files

    /// « Transcrire un fichier » (20/11 in the evening): a sound or a video; its text joins the history.
    public func transcribe(_ url: URL) {
        let id = "fichier-" + UUID().uuidString
        working[id] = url.lastPathComponent
        fileProblem = nil
        send(.file(id: id, path: url.path(percentEncoded: false), listening: listeningOptions(settings)))
    }

    /// « Retranscrire »: a dictation's kept sound written again, with today's memory.
    public func rewrite(_ row: DictationRow) {
        let id = "dictee-" + row.id.uuidString
        working[id] = row.app ?? ""
        fileProblem = nil
        send(.file(id: id, path: library.soundURL(row.id).path(percentEncoded: false), listening: listeningOptions(settings)))
    }

    public func isRewriting(_ row: DictationRow) -> Bool {
        working["dictee-" + row.id.uuidString] != nil
    }

    private func written(id: String, raw: String, seconds: Double) {
        guard let name = working.removeValue(forKey: id) else { return }
        let text = DictationText.clean(raw, replacements: library.corrections, rules: settings.rules)
        if id.hasPrefix("dictee-"), let row = UUID(uuidString: String(id.dropFirst("dictee-".count))) {
            if !text.isEmpty { library.setText(row, text: text, raw: raw) }
        } else if !text.isEmpty {
            library.keep(DictationRow(text: text, raw: raw, app: nil, seconds: seconds, createdAt: Date(), file: name))
        } else {
            fileProblem = "Whisper n'a rien entendu dans « \(name) »."
        }
    }

    /// « Garder l'historique » (Réglages › Dictée): the older dictations go, with their sounds.
    private func purge() {
        lastPurge = Date()
        library.purge(keepDays: settings.keepDays)
    }

    /// A state set by hand, for the window's captures and tests.
    func show(_ state: DictationWindowState, level: Double = 0.6) {
        phase = state.phase
        micOpen = state.micOpen
        whisperLoaded = state.whisperLoaded
        partial = state.partial
        progress = state.progress
        outcome = state.outcome
        silenceLeft = state.silenceLeft
        self.level = level
        startedAt = state.micOpen ? Date().addingTimeInterval(-7) : nil
    }

    private func showPill() {
        guard showsWindow else { return }
        if pill == nil { pill = DictationPill(service: self) }
        pill?.show()
    }
}

/// The helper's output, cut into lines: a line can come in two pieces.
final class LineSplitter: @unchecked Sendable {
    private var pending = Data()
    private let lock = NSLock()

    func add(_ data: Data) -> [String] {
        lock.withLock {
            pending += data
            var lines: [String] = []
            while let end = pending.firstIndex(of: 0x0A) {
                lines.append(String(decoding: pending[pending.startIndex..<end], as: UTF8.self))
                pending = Data(pending[pending.index(after: end)...])
            }
            return lines
        }
    }
}

/// The text where the cursor is (20/11): in the clipboard, a ⌘V for the app in front, then the clipboard as it was.
enum Paster {
    /// `restore`: the clipboard as it was afterwards (Réglages › Dictée); the text stays in the history either way.
    @MainActor static func paste(_ text: String, restore: Bool) {
        let board = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = board.pasteboardItems?.map { item in
            item.types.reduce(into: [:]) { result, type in result[type] = item.data(forType: type) }
        } ?? []
        board.clearContents()
        board.setString(text, forType: .string)
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard restore, !saved.isEmpty else { return }
            board.clearContents()
            board.writeObjects(saved.map { types in
                let item = NSPasteboardItem()
                for (type, data) in types { item.setData(data, forType: type) }
                return item
            })
        }
    }
}
