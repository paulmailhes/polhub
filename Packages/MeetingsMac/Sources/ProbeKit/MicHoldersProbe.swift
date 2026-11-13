import AppKit
import Foundation
import MeetingDetection
import Observability

/// Records, four times a second, which processes hold the microphone or play sound.
/// It writes only when something changed, plus a heartbeat every five seconds.
public struct MicHoldersProbe: Probe {
    struct Sample: Encodable, Sendable {
        let reason: String          // "change" | "heartbeat" | "error"
        let procs: [AudioProcessInfo]
        let error: String?
    }

    public init() {}

    public func run(_ request: ProbeRequest, trace: TraceWriter, directory: URL) async {
        let monitor = AudioProcessMonitor()
        let diaAppPath = DiaAdapter.appPath()
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(request.seconds)
        var last: [AudioProcessInfo]?
        var lastWrite = clock.now

        while clock.now < deadline, !Task.isCancelled {
            do {
                let procs = Self.relevant(try monitor.snapshot(), diaAppPath: diaAppPath)
                if procs != last {
                    try? await trace.write(kind: "audio-procs", Sample(reason: "change", procs: procs, error: nil))
                    last = procs
                    lastWrite = clock.now
                } else if clock.now - lastWrite >= .seconds(5) {
                    try? await trace.write(kind: "audio-procs", Sample(reason: "heartbeat", procs: procs, error: nil))
                    lastWrite = clock.now
                }
            } catch {
                try? await trace.write(kind: "audio-procs", Sample(reason: "error", procs: [], error: "\(error)"))
            }
            guard await Self.keepGoing(trace, after: 0.25) else { break }
        }
    }

    /// Processes recording or playing, plus every process that belongs to Dia. Sorted by pid.
    static func relevant(_ procs: [AudioProcessInfo], diaAppPath: String) -> [AudioProcessInfo] {
        procs
            .filter { $0.isRunningInput || $0.isRunningOutput || $0.owningAppPath == diaAppPath }
            .sorted { $0.pid < $1.pid }
    }
}
