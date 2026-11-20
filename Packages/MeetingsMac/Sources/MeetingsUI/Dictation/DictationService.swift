import AppKit
import ApplicationServices
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

    let library: DictationLibrary
    let helper: URL
    private var process: Process?
    private var input: FileHandle?
    private var gesture = KeyGesture()
    private var monitors: [Any] = []
    private var ticker: Timer?
    private var target: NSRunningApplication?
    private var pill: DictationPill?
    private var restarts = 0

    public init(library: DictationLibrary, helper: URL) {
        self.library = library
        self.helper = helper
    }

    public func start() {
        launch()
        watchKey()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.apply(self.gesture.tick(at: ProcessInfo.processInfo.systemUptime))
                // Accessibility given in Réglages Système: noticed without a relaunch.
                if !self.trusted, AXIsProcessTrusted() { self.trusted = true; self.watchKey() }
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
        case .partial(let text):
            if phase == .listening { partial = text }
        case .final(let text, let seconds):
            finish(text, seconds: seconds)
        case .failed(let reason):
            phase = .failed(reason)
            pill?.hide()
        }
    }

    // MARK: - The key

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
            target = NSWorkspace.shared.frontmostApplication
            library.refreshKnown()
            partial = ""
            notice = nil
            phase = .listening
            let language = UserDefaults.standard.string(forKey: Preferences.Key.dictationLanguage) == "auto" ? nil : "fr"
            send(.start(language: language, prompt: library.prompt))
            showPill()
        case .finish:
            guard phase == .listening else { return }
            phase = .writing
            send(.stop)
        case .cancel:
            guard phase == .listening else { return }
            send(.cancel)
            phase = .ready
            pill?.hide()
        case .none:
            break
        }
    }

    // MARK: - The text

    private func finish(_ raw: String, seconds: Double) {
        let text = DictationText.clean(raw, replacements: library.corrections)
        phase = .ready
        guard !text.isEmpty else {
            pill?.hide()
            return
        }
        library.keep(DictationRow(text: text, raw: raw, app: target?.localizedName, seconds: seconds, createdAt: Date()))
        if trusted, AXIsProcessTrusted() {
            Paster.paste(text)
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
    @MainActor static func paste(_ text: String) {
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
            guard !saved.isEmpty else { return }
            board.clearContents()
            board.writeObjects(saved.map { types in
                let item = NSPasteboardItem()
                for (type, data) in types { item.setData(data, forType: type) }
                return item
            })
        }
    }
}
