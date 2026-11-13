import Foundation
import Observability

extension DiaAudio {
    /// What Dia does with sound, read from Core Audio's list of processes: only processes whose executable
    /// lives inside Dia.app count (a dictation app holding the microphone is not Dia).
    public static func from(_ processes: [AudioProcessInfo], diaAppPath: String) -> DiaAudio {
        let dia = processes.filter { $0.owningAppPath == diaAppPath }
        return DiaAudio(holdsMic: dia.contains(where: \.isRunningInput), playing: dia.contains(where: \.isRunningOutput))
    }
}

/// How often Dia's tabs are read. A reading costs Dia about 0.3 s (phase 0, measure 4), and Dia takes the
/// microphone within the second a Meet tab opens, even muted in the waiting room (measures 9 and S02):
/// tabs are read every 2 s around the microphone or during a meeting, every 30 s otherwise.
public enum TabCadence {
    public static let near = 2.0
    public static let idle = 30.0

    public static func interval(holdsMic: Bool, secondsSinceMicReleased: Double?, meetingActive: Bool) -> Double {
        if holdsMic || meetingActive { return near }
        if let secondsSinceMicReleased, secondsSinceMicReleased <= 30 { return near }
        return idle
    }
}

/// Watches Dia and turns what it sees into detector inputs, stamped in continuous seconds: Dia's audio
/// every second (published when it changes), its Meet tabs at the cadence above, and Dia quitting.
/// It never sends an Apple Event while Dia is not running: that would launch it.
public actor DiaWatcher {
    private let adapter: any BrowserAdapter
    private let monitor: AudioProcessMonitor
    private let clock: @Sendable () -> Double
    private let isRunning: @Sendable () -> Bool
    private let diaAppPath: String

    private var meetingActive = false
    private var lastAudio: DiaAudio?
    private var micReleasedAt: Double?
    private var lastTabsAt: Double?
    private var diaWasRunning = false

    public init(
        adapter: any BrowserAdapter,
        monitor: AudioProcessMonitor = AudioProcessMonitor(),
        clock: @escaping @Sendable () -> Double = ContinuousTime.seconds,
        isRunning: @escaping @Sendable () -> Bool = DiaAdapter.systemIsRunning,
        diaAppPath: String = DiaAdapter.appPath()
    ) {
        self.adapter = adapter
        self.monitor = monitor
        self.clock = clock
        self.isRunning = isRunning
        self.diaAppPath = diaAppPath
    }

    /// While a meeting is prompted or recorded, tabs are read often whatever the microphone does.
    public func setMeetingActive(_ active: Bool) {
        meetingActive = active
    }

    public nonisolated func inputs() -> AsyncStream<(at: Double, input: DetectionInput)> {
        AsyncStream { continuation in
            let task = Task { await self.loop(continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func loop(_ continuation: AsyncStream<(at: Double, input: DetectionInput)>.Continuation) async {
        while !Task.isCancelled {
            let now = clock()
            let running = isRunning()
            if diaWasRunning, !running {
                continuation.yield((now, .diaQuit))
                lastAudio = DiaAudio(holdsMic: false, playing: false)
                micReleasedAt = nil
            }
            diaWasRunning = running

            if running, let processes = try? monitor.snapshot() {
                let audio = DiaAudio.from(processes, diaAppPath: diaAppPath)
                if audio != lastAudio {
                    if lastAudio?.holdsMic == true, !audio.holdsMic { micReleasedAt = now }
                    lastAudio = audio
                    continuation.yield((now, .audio(audio)))
                }
            }

            let interval = TabCadence.interval(
                holdsMic: lastAudio?.holdsMic ?? false,
                secondsSinceMicReleased: micReleasedAt.map { now - $0 },
                meetingActive: meetingActive
            )
            if running, now >= (lastTabsAt ?? -.infinity) + interval {
                let result = await adapter.meetTabs()
                let at = clock()
                lastTabsAt = at
                switch result {
                case .tabs(let tabs): continuation.yield((at, .tabs(tabs, complete: true)))
                case .partial(let tabs, _): continuation.yield((at, .tabs(tabs, complete: false)))
                case .permissionDenied: continuation.yield((at, .tabsUnavailable("autorisation refusée")))
                case .failed(let code, let message): continuation.yield((at, .tabsUnavailable("\(code) \(message)")))
                case .browserNotRunning: break   // Dia quitting is reported once, above
                }
            }

            try? await Task.sleep(for: .seconds(1))
        }
        continuation.finish()
    }
}
