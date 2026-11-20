import AppKit
import ApplicationServices
import AudioCapture
import Dictation
import Foundation
import HubDesign
import Persistence

/// The Dictée at work (20/11): it launches the helper `hub-dictee`, which keeps Whisper loaded; it watches the key; it
/// shows the pill at the bottom of the screen; then it pastes the text where the cursor was, and keeps it in the history.
@MainActor public final class DictationService: ObservableObject {
    public enum Phase: Equatable, Sendable {
        /// Whisper loads (about 20 s at launch).
        case loading
        case ready
        case listening
        /// Whisper writes the whole recording.
        case writing
        case failed(String)
    }

    @Published public private(set) var phase: Phase = .loading
    /// The words said so far.
    @Published public private(set) var partial = ""
    @Published public private(set) var level: Double = 0
    /// What the pill says once: « Copié : colle-le avec ⌘V ».
    @Published public private(set) var notice: String?
    /// Whether macOS lets hub watch the key everywhere and paste into the other apps.
    @Published public private(set) var trusted = AXIsProcessTrusted()
    /// When the recording started, for the window's clock.
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
    private var gesture = KeyGesture(mode: DictationService.mode)
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

    /// `media`: `hub-media.dylib`, which pauses the music; nil: the music is never paused.
    public init(library: DictationLibrary, helper: URL, media: URL? = nil, inMeeting: @escaping @MainActor () -> Bool = { false }) {
        self.library = library
        self.helper = helper
        self.inMeeting = inMeeting
        sound = DictationSound(media: MediaPause(bridge: media.map(MediaBridge.init(library:))))
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
            phase = .loading
        } catch {
            phase = .failed("La Dictée ne démarre pas : relance hub.")
        }
    }

    /// The helper died: started again, three times at most, then said.
    private func helperStopped() {
        guard process != nil else { return }
        process = nil
        restarts += 1
        guard restarts <= 3 else {
            phase = .failed("La Dictée s'est arrêtée : relance hub.")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.launch() }
    }

    private func send(_ command: DictationCommand) {
        guard let input, let line = try? DictationWire.line(command) else { return }
        input.write(Data((line + "\n").utf8))
    }

    private func handle(_ event: DictationEvent) {
        switch event {
        case .ready:
            phase = .ready
            restarts = 0
        case .level(let value):
            level = value
            watchSilence(value)
        case .partial(let text):
            if phase == .listening, Self.on(Preferences.Key.dictationLiveText) { partial = text }
        case .final(let text, let seconds):
            finish(text, seconds: seconds)
        case .transcribed(let id, let text, let seconds):
            written(id: id, raw: text, seconds: seconds)
        case .fileFailed(let id, let reason):
            working[id] = nil
            fileProblem = reason
        case .failed(let reason):
            phase = .failed(reason)
            pill?.hide()
        }
    }

    // MARK: - The key

    /// Réglages › Dictée: a press starts and a press finishes, by default.
    static var mode: KeyGesture.Mode {
        UserDefaults.standard.string(forKey: Preferences.Key.dictationMode).flatMap(KeyGesture.Mode.init(rawValue:)) ?? .toggle
    }

    static func on(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

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
        if gesture.state == .idle, gesture.mode != Self.mode { gesture = KeyGesture(mode: Self.mode) }
        let key = DictationKey.current
        switch event.type {
        case .flagsChanged where event.keyCode == key.keyCode:
            apply(event.modifierFlags.contains(key.flag) ? gesture.keyDown(at: now) : gesture.keyUp(at: now))
        case .flagsChanged:
            // Another modifier with the key: a character is being typed.
            apply(gesture.otherKey())
        case .keyDown where event.keyCode == 53:
            apply(gesture.escape())
        case .keyDown:
            apply(gesture.otherKey())
        default:
            break
        }
    }

    private func apply(_ action: KeyGesture.Action) {
        switch action {
        case .start:
            guard phase == .ready else { return }
            let settings = DictationSettings()
            target = NSWorkspace.shared.frontmostApplication
            library.refreshKnown()
            partial = ""
            notice = nil
            startedAt = Date()
            windowAtTop = settings.windowAtTop
            dictationID = UUID()
            silence = settings.autoStop.map { SilenceWatch(after: $0, startedAt: ProcessInfo.processInfo.systemUptime) }
            phase = .listening
            var listening = listeningOptions(settings)
            listening.microphone = settings.microphone(connected: Devices.microphones())
            listening.keepSoundAt = settings.on(Preferences.Key.dictationKeepSound) ? library.soundURL(dictationID).path(percentEncoded: false) : nil
            send(.start(listening))
            sound.started(inMeeting: inMeeting())
            showPill()
        case .finish:
            guard phase == .listening else { return }
            phase = .writing
            silence = nil
            send(.stop)
            sound.stopped(finished: true)
        case .cancel:
            guard phase == .listening else { return }
            send(.cancel)
            silence = nil
            phase = .ready
            pill?.hide()
            sound.stopped(finished: false)
        case .none:
            break
        }
    }

    /// The language, the memory and the paragraphs, for a dictation or a file.
    private func listeningOptions(_ settings: DictationSettings) -> DictationListening {
        let language = UserDefaults.standard.string(forKey: Preferences.Key.dictationLanguage) == "auto" ? nil : "fr"
        return DictationListening(language: language, prompt: library.prompt, paragraphPause: settings.paragraphPause)
    }

    /// « Arrêt seul » (20/11 in the evening): a long silence finishes the dictation, when the key is not held.
    private func watchSilence(_ value: Double) {
        guard phase == .listening, [.listening, .handsFree].contains(gesture.state), var watch = silence else { return }
        let finish = watch.hear(value, at: ProcessInfo.processInfo.systemUptime)
        silence = watch
        guard finish else { return }
        apply(.finish)
        // The key is free again: the next press starts a dictation.
        gesture = KeyGesture(mode: Self.mode)
    }

    // MARK: - The text

    private func finish(_ raw: String, seconds: Double) {
        let text = DictationText.clean(raw, replacements: library.corrections, rules: DictationSettings().rules)
        phase = .ready
        guard !text.isEmpty else {
            library.removeSound(dictationID)
            pill?.hide()
            return
        }
        library.keep(DictationRow(id: dictationID, text: text, raw: raw, app: target?.localizedName, seconds: seconds, createdAt: Date()))
        if trusted, AXIsProcessTrusted() {
            // A space after, to dictate the next sentence straight on (Réglages › Dictée).
            let space = Self.on(Preferences.Key.dictationTrailingSpace) && !text.hasSuffix("\n") ? " " : ""
            Paster.paste(text + space, restore: Self.on(Preferences.Key.dictationRestoreClipboard))
            pill?.hide()
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            notice = "Copié : colle-le avec ⌘V"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard self?.phase != .listening else { return }
                self?.pill?.hide()
            }
        }
    }

    // MARK: - The files

    /// « Transcrire un fichier » (20/11 in the evening): a sound or a video; its text joins the history.
    public func transcribe(_ url: URL) {
        let id = "fichier-" + UUID().uuidString
        working[id] = url.lastPathComponent
        fileProblem = nil
        send(.file(id: id, path: url.path(percentEncoded: false), listening: listeningOptions(DictationSettings())))
    }

    /// « Retranscrire »: a dictation's kept sound written again, with today's memory.
    public func rewrite(_ row: DictationRow) {
        let id = "dictee-" + row.id.uuidString
        working[id] = row.app ?? ""
        fileProblem = nil
        send(.file(id: id, path: library.soundURL(row.id).path(percentEncoded: false), listening: listeningOptions(DictationSettings())))
    }

    public func isRewriting(_ row: DictationRow) -> Bool {
        working["dictee-" + row.id.uuidString] != nil
    }

    private func written(id: String, raw: String, seconds: Double) {
        guard let name = working.removeValue(forKey: id) else { return }
        let text = DictationText.clean(raw, replacements: library.corrections, rules: DictationSettings().rules)
        if id.hasPrefix("dictee-"), let row = UUID(uuidString: String(id.dropFirst("dictee-".count))) {
            library.setText(row, text: text, raw: raw)
        } else if !text.isEmpty {
            library.keep(DictationRow(text: text, raw: raw, app: nil, seconds: seconds, createdAt: Date(), file: name))
        } else {
            fileProblem = "Whisper n'a rien entendu dans « \(name) »."
        }
    }

    /// « Garder l'historique » (Réglages › Dictée): the older dictations go, with their sounds.
    private func purge() {
        lastPurge = Date()
        library.purge(keepDays: DictationSettings().keepDays)
    }

    /// A state set by hand, for the window's captures (tests only).
    func show(_ phase: Phase, partial: String, level: Double) {
        self.phase = phase
        self.partial = partial
        self.level = level
        startedAt = Date().addingTimeInterval(-7)
    }

    private func showPill() {
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
