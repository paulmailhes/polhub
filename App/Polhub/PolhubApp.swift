import AppKit
import Colin
import Combine
import Domain
import MeetingsUI
import Observability
import Persistence
import Pipeline
import PolhubDesign
import ProbeKit
import SwiftUI

@main
struct PolhubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    /// « Coup d'œil » (15/11): a window under the logo, not a menu (an `NSMenu` cannot hold tiles, and froze the
    /// clock while open). It never opens by itself, and is never closed by hand: it closes as the focus leaves.
    var body: some Scene {
        MenuBarExtra {
            // Polhub's own accent, ink, whatever the Mac's (design system v2, 19/11).
            MenuBarPanel(context: delegate.coupDoeil)
                .tint(Tint.control.color)
        } label: {
            MenuBarIcon(model: delegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Runs one probe at a time and exposes its state to the probes window.
@MainActor
final class ProbeRunner: ObservableObject {
    @Published private(set) var running: ProbeID?
    @Published private(set) var lastDirectory: URL?
    @Published private(set) var message: String?
    private var task: Task<Void, Never>?

    /// `onFinish` receives the reason the measurement is not to be trusted, or nil when it went through.
    @discardableResult
    func start(_ request: ProbeRequest, onFinish: (@MainActor (String?) -> Void)? = nil) -> Bool {
        guard running == nil else { return false }
        guard let probe = ProbeRegistry.make(request.probe) else {
            message = "La sonde « \(request.probe.title) » n'est pas encore disponible."
            return false
        }
        let directory = TracePaths.sessionDirectory(root: TracePaths.root, probe: request.probe.rawValue, at: .now)
        let trace: TraceWriter
        do {
            trace = try TraceWriter(fileURL: directory.appending(path: "trace.jsonl"))
        } catch {
            message = "Impossible d'écrire la trace : \(error)"
            return false
        }
        running = request.probe
        lastDirectory = directory
        message = nil
        // A measurement must not be slowed down because the app has no window in front (App Nap).
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "Sonde de mesure en cours")
        task = Task { [weak self] in
            await probe.run(request, trace: trace, directory: directory)
            let failure = await trace.failure
            await trace.close()
            ProcessInfo.processInfo.endActivity(activity)
            let problem = failure.map { "La trace n'a plus pu être écrite, la mesure s'est arrêtée : \($0)" }
            self?.running = nil
            self?.message = problem
            onFinish?(problem)
        }
        return true
    }

    func stop() {
        task?.cancel()
    }

    /// The app is going, by whatever way: the probe under way stops, every Claude Code that Polhub launched is
    /// asked to stop, then killed if it stays, and the probe is left a moment to end its own way (its last line,
    /// its folder removed). It returns once all are gone: three seconds at most, at once when nothing runs.
    func stopForExit() {
        stop()
        ClaudeProcesses.shared.stopAll()
        ColinProbe.waitUntilDone(within: 1)
    }
}
