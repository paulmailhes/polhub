import AppKit
import AudioCapture
import Foundation
import Observability
import os

/// Drives a capture: logs every Core Audio route notification, rebuilds a track only when the route that
/// track really uses changes, and measures the holes. Used by the meeting recorder and by the probes.
/// What the person may want to hear about while a meeting records.
public enum CaptureEvent: Equatable, Sendable {
    case micsChanged([String])
    case outputChanged(String?)
    case trackFailed(track: CaptureEngine.Track, message: String)
    case rebuildAbandoned(CaptureEngine.Track)
}

public final class CaptureSupervisor: @unchecked Sendable {
    struct RebuildRecord: Encodable, Sendable {
        let track: String
        let reason: String
        let durationMs: Double
        let ok: Bool
    }

    struct GapsRecord: Encodable, Sendable {
        let track: String
        /// The microphone, for `moi`; absent for `autres`.
        let device: String?
        let build: Int
        let sampleRate: Double
        let anchors: Int
        let gaps: [Gap]
        /// Seconds without audio between the previous build of this track and this one.
        let holeBeforeSeconds: Double?
    }

    let engine: CaptureEngine
    let trace: TraceWriter

    public let events: AsyncStream<CaptureEvent>
    private let continuation: AsyncStream<CaptureEvent>.Continuation

    /// A probe stops when its trace fails (it would measure into the void); a meeting goes on recording.
    let stopOnTraceFailure: Bool

    public init(engine: CaptureEngine, trace: TraceWriter, stopOnTraceFailure: Bool = true) {
        self.engine = engine
        self.trace = trace
        self.stopOnTraceFailure = stopOnTraceFailure
        (events, continuation) = AsyncStream<CaptureEvent>.makeStream()
    }

    /// The events a change of microphones or of output gives, compared with what was there before.
    static func changes(previousMics: [String], currentMics: [String], previousOutput: String?, currentOutput: String?) -> [CaptureEvent] {
        // Getting the first device, or losing the last one, is a meeting starting or ending, not a change.
        var events: [CaptureEvent] = []
        if currentMics != previousMics, !previousMics.isEmpty, !currentMics.isEmpty { events.append(.micsChanged(currentMics)) }
        if let previousOutput, let currentOutput, currentOutput != previousOutput { events.append(.outputChanged(currentOutput)) }
        return events
    }

    /// Runs the engine until `seconds` have passed (nil: until the task is cancelled).
    public func run(seconds: Int?) async {
        let rig = engine
        let wallClock = ContinuousClock()
        let deadline = seconds.map { wallClock.now + .seconds($0) }
        // Every delay below is counted in awake time: a Mac that slept has not been waiting.
        let awake = SuspendingClock()
        let origin = awake.now
        func now() -> Double {
            let elapsed = awake.now - origin
            return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        }

        let events = OSAllocatedUnfairLock<[RouteEvent]>(initialState: [])
        let power = OSAllocatedUnfairLock<[String]>(initialState: [])
        let powerObservers = [NSWorkspace.willSleepNotification: "sleep", NSWorkspace.didWakeNotification: "wake"].map { name, label in
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: nil) { _ in
                power.withLock { $0.append(label) }
            }
        }
        defer { powerObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver) }

        var monitor: RouteMonitor?
        func watchRoutes() {
            monitor?.stop()
            let fresh = RouteMonitor(processes: rig.tappedProcesses, tap: rig.tapID, micDeviceUIDs: rig.micDeviceUIDs) { event in
                events.withLock { $0.append(event) }
            }
            fresh.start()
            monitor = fresh
        }

        var scheduler = RebuildScheduler()
        func rebuild(_ track: CaptureEngine.Track, reason: String) async {
            // A notification that changes nothing is not a rebuild: no line, no count.
            if track == .moi, RebuildPolicy.syncsOnly(reason: reason), !rig.micsNeedSync() {
                scheduler.finished(track, ok: true, at: now())
                return
            }
            let began = wallClock.now
            let ok: Bool
            switch track {
            case .autres:
                rig.stopOthers()
                ok = rig.startOthers(reason: reason)
            case .moi:
                // Dia took or let go of a microphone: only that one is started or stopped. Anything else
                // (a format change, a stall) rebuilds them all. No microphone wanted any more is a success.
                ok = RebuildPolicy.syncsOnly(reason: reason) ? rig.syncMics(reason: reason) : rig.restartMics(reason: reason)
            }
            watchRoutes()   // the tap, or the microphone, is a new object
            scheduler.finished(track, ok: ok, at: now())
            let elapsed = wallClock.now - began
            try? await trace.write(kind: "rebuild", RebuildRecord(
                track: track.rawValue, reason: reason,
                durationMs: Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15,
                ok: ok
            ))
            if scheduler.hasGivenUp(track) {
                continuation.yield(.rebuildAbandoned(track))
                try? await trace.write(kind: "rebuild-abandoned", RebuildRecord(
                    track: track.rawValue, reason: "\(RebuildScheduler.maxFailuresInARow) échecs de suite", durationMs: 0, ok: false
                ))
            }
        }

        let continuation = continuation
        rig.onError { track, message in continuation.yield(.trackFailed(track: track, message: message)) }
        defer { continuation.finish() }

        // The first start fails when Dia has no audio process yet; the loop below starts it later.
        rig.start()
        watchRoutes()
        var lastMics = rig.micDeviceUIDs
        var lastOutput = rig.desiredOutputUIDs().first

        var lastPoll = now()
        var wokeAt: Double?
        var lastDesiredProcesses = rig.desiredProcesses()
        var lastDesiredMics = rig.desiredMicUIDs()

        while deadline.map({ wallClock.now < $0 }) ?? true, !Task.isCancelled {
            for label in power.withLock({ queued in defer { queued = [] }; return queued }) {
                try? await trace.write(kind: label, [String: String]())
                if label == "wake" { wokeAt = now() }
            }

            for event in events.withLock({ queued in defer { queued = [] }; return queued }) {
                try? await trace.write(kind: "route", event)
                let unchanged = event.source == "tapFormat" && rig.tapFormatMatchesBuild()
                for track in RebuildPolicy.tracks(for: event, tapFormatUnchanged: unchanged) {
                    scheduler.note(track, reason: event.source, at: now())
                }
            }

            // Polled once a second: Core Audio sends no notification when a process starts or stops recording.
            if now() - lastPoll >= 1 {
                lastPoll = now()
                rig.reportSilentTracks()

                let processes = rig.desiredProcesses()
                let microphones = rig.desiredMicUIDs()
                if processes != lastDesiredProcesses { scheduler.routeChanged(.autres) }
                if microphones != lastDesiredMics { scheduler.routeChanged(.moi) }
                lastDesiredProcesses = processes
                lastDesiredMics = microphones

                if rig.variant.kind == .a, processes != rig.tappedProcesses {
                    scheduler.noteIfIdle(.autres, reason: "processSet", at: now())
                }
                if microphones != rig.micDeviceUIDs {
                    scheduler.noteIfIdle(.moi, reason: "micRoute", at: now())
                }
                for track in rig.stalledTracks(secondsSinceWake: wokeAt.map { now() - $0 }) {
                    scheduler.noteIfIdle(track, reason: "stall", at: now())
                }

                let mics = rig.micDeviceUIDs
                let output = rig.desiredOutputUIDs().first
                for event in Self.changes(previousMics: lastMics, currentMics: mics, previousOutput: lastOutput, currentOutput: output) {
                    continuation.yield(event)
                }
                lastMics = mics
                lastOutput = output
            }

            for (track, reason) in scheduler.due(at: now()) {
                await rebuild(track, reason: reason)
            }

            guard await Self.keepGoing(trace, after: 0.1, stopOnTraceFailure: stopOnTraceFailure) else { break }
        }

        monitor?.stop()
        rig.stop()
        // Lets the last reports, written from the recorder threads, reach the trace.
        _ = await Self.pause(0.2)
        for record in Self.gapRecords(rig.anchorRuns) {
            try? await trace.write(kind: "gaps", record)
        }
    }

    /// One record per build of each stream: the gaps inside it, and the hole since the previous build of
    /// the same stream. Two microphones recorded at the same time are two streams: no hole between them.
    static func gapRecords(_ runs: [CaptureEngine.AnchorRun]) -> [GapsRecord] {
        var previous: [CaptureEngine.Feed: CaptureEngine.AnchorRun] = [:]
        var records: [GapsRecord] = []
        for run in runs {
            let feed = CaptureEngine.Feed(track: run.track, device: run.device)
            var hole: Double?
            if let before = previous[feed]?.anchors.last, let first = run.anchors.first {
                hole = RebuildPolicy.holeSeconds(lastOfPrevious: before, firstOfNext: first, nextSampleRate: run.sampleRate)
            }
            records.append(GapsRecord(
                track: run.track.rawValue, device: run.device, build: run.build, sampleRate: run.sampleRate,
                anchors: run.anchors.count,
                gaps: GapMeter.gaps(anchors: run.anchors, sampleRate: run.sampleRate), holeBeforeSeconds: hole
            ))
            if !run.anchors.isEmpty { previous[feed] = run }
        }
        return records
    }

    /// Sleeps up to `seconds`; returns false when the task was cancelled meanwhile.
    static func pause(_ seconds: Double) async -> Bool {
        do {
            try await Task.sleep(for: .seconds(seconds))
            return true
        } catch {
            return false
        }
    }

    /// Sleeps, then says whether to go on: false when the task was cancelled or the trace can no longer
    /// be written.
    static func keepGoing(_ trace: TraceWriter, after seconds: Double, stopOnTraceFailure: Bool = true) async -> Bool {
        guard await pause(seconds) else { return false }
        guard stopOnTraceFailure else { return true }
        return await trace.failure == nil
    }
}
