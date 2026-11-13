import AppKit
import Combine
import Domain
import MeetingsUI
import Observability
import Persistence
import Pipeline
import ProbeKit
import SwiftUI

@main
struct TranscriptorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: delegate.model, app: delegate)
        } label: {
            MenuBarIcon(model: delegate.model)
        }
    }
}

/// What the menu bar shows, kept up to date by the presenter and the delegate.
@MainActor
final class AppModel: ObservableObject {
    @Published var status: RecorderStatus = .idle
    @Published var attention = false
    @Published var pausedUntil: Date?
    @Published var now = Date()
    @Published var recent: [MeetingRow] = []
    @Published var tabMeeting = false
    @Published var detectionOn = false

    /// The status as the menu shows it: a pause only shows while nothing records.
    var shownStatus: RecorderStatus {
        if case .idle = status, let pausedUntil, pausedUntil > now { return .paused(until: pausedUntil) }
        return status
    }

    var isRecording: Bool {
        switch status {
        case .recording, .presumedEnded: true
        default: false
        }
    }
}

struct MenuBarIcon: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let label = MenuBarLabel.make(status: model.shownStatus, attention: model.attention, now: model.now)
        if label.symbol == "record.circle.fill" {
            Image(nsImage: Self.redImage(label.symbol))
        } else {
            Image(systemName: label.symbol)
        }
        if let text = label.text {
            Text(text).monospacedDigit()
        }
    }

    /// The menu bar draws its images in one colour; this one stays red.
    static func redImage(_ symbol: String) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Enregistrement")?
            .withSymbolConfiguration(configuration) ?? NSImage()
        image.isTemplate = false
        return image
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel
    let app: AppDelegate

    var body: some View {
        Text(MenuBarLabel.statusLine(model.shownStatus, now: model.now))
        if model.isRecording {
            Button("Arrêter l'enregistrement") { app.user(.stop) }
        } else {
            Button("Enregistrer maintenant") { app.user(.recordNow) }
                .disabled(model.status != .idle)
        }
        if model.tabMeeting {
            Button("Jamais pour ce lien") { app.user(.neverForThisLink) }
        }
        if let until = model.pausedUntil, until > model.now {
            Button("Reprendre la détection") { app.resumeDetection() }
        } else {
            Button("Suspendre la détection une heure") { app.pauseDetection() }
        }
        if app.isDevelopment {
            Toggle("Détection automatique (version de développement)", isOn: Binding(
                get: { model.detectionOn }, set: { app.setDetection($0) }
            ))
        }
        Divider()
        ForEach(model.recent) { row in
            Button("\(row.title) · \(row.startedAt.formatted(date: .abbreviated, time: .shortened))") { app.showMeeting(row.id) }
        }
        if !model.recent.isEmpty { Divider() }
        Button("Ouvrir Transcriptor") { app.showMainWindow() }
        Button("Diagnostic…") { app.showDiagnostic() }
        Divider()
        Button("Quitter") { NSApp.terminate(nil) }
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
}
