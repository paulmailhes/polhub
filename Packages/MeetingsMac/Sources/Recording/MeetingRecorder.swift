import Domain
import Foundation
import Observability
import os

/// What the coordinator hears from a recording.
public enum RecorderEvent: Equatable, Sendable {
    case selfTest(passed: Bool)
    case micsChanged([String])
    case outputChanged(String?)
    case trackFailed(track: String, message: String)
    case traceFailed(String)
}

/// A recording the coordinator can start, stop or throw away. The protocol lets tests use a fake one.
public protocol MeetingRecording: AnyObject, Sendable {
    var events: AsyncStream<RecorderEvent> { get }
    func start() async
    func stop() async
    func discard() async
}

/// One meeting on disk: `timeline.jsonl` (the trace format of phase 0) and `audio/<moi|autres>/<build>/`.
/// A meeting in Dia records Dia's processes (variant A) and every microphone Dia holds; « Enregistrer
/// maintenant » records the whole Mac (variant D) and the default microphone. Started again in the same
/// folder after a crash, it goes on with the next build numbers and appends to the timeline.
public final class MeetingRecorder: MeetingRecording, @unchecked Sendable {
    public static let segmentSeconds = 60.0

    public let folder: URL
    public let mode: MeetingSource
    public let events: AsyncStream<RecorderEvent>

    private let continuation: AsyncStream<RecorderEvent>.Continuation
    private let selfTestAmplitude: Float?
    private let trace: TraceWriter
    private let supervisor: CaptureSupervisor
    private let tasks = OSAllocatedUnfairLock<[Task<Void, Never>]>(initialState: [])
    private let stopped = OSAllocatedUnfairLock(initialState: false)

    private struct SelfTestRecord: Encodable, Sendable {
        let passed: Bool
        let result: String
        let amplitude: Float
    }

    /// `selfTestAmplitude`: the tone of the check that the others' sound is heard; nil for no check.
    public init(folder: URL, mode: MeetingSource, selfTestAmplitude: Float?) throws {
        self.folder = folder
        self.mode = mode
        self.selfTestAmplitude = selfTestAmplitude
        try FileManager.default.createDirectory(at: folder.appending(path: "audio", directoryHint: .isDirectory), withIntermediateDirectories: true)
        trace = try TraceWriter(fileURL: folder.appending(path: "timeline.jsonl"))
        let engine = CaptureEngine(
            variant: .parse(mode == .dia ? "A" : "D"),
            micSource: mode == .dia ? .heldByDia : .systemDefault,
            directory: folder,
            trace: trace,
            firstBuild: Self.firstBuilds(in: folder)
        )
        supervisor = CaptureSupervisor(engine: engine, trace: trace, stopOnTraceFailure: false)
        (events, continuation) = AsyncStream<RecorderEvent>.makeStream()
    }

    /// The number the next build of each track takes in `folder`.
    public static func firstBuilds(in folder: URL) -> [CaptureEngine.Track: Int] {
        var builds: [CaptureEngine.Track: Int] = [:]
        for track in CaptureEngine.Track.allCases {
            let path = folder.appending(path: "audio/\(track.rawValue)", directoryHint: .isDirectory).path
            builds[track] = BuildNumbering.next(existingFolders: (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [])
        }
        return builds
    }

    /// Only silence blames the permission; a check that could not start says nothing about it.
    static func selfTestFailed(result: String) -> Bool {
        result == "allZero"
    }

    public func start() async {
        // A start that comes after a stop (a meeting discarded meanwhile) does nothing.
        guard !stopped.withLock({ $0 }) else { return }
        let continuation = continuation
        let supervisor = supervisor
        let trace = trace
        var started: [Task<Void, Never>] = []

        started.append(Task {
            for await event in supervisor.events {
                switch event {
                case .micsChanged(let mics): continuation.yield(.micsChanged(mics))
                case .outputChanged(let output): continuation.yield(.outputChanged(output))
                case .trackFailed(let track, let message): continuation.yield(.trackFailed(track: track.rawValue, message: message))
                case .rebuildAbandoned(let track):
                    continuation.yield(.trackFailed(track: track.rawValue, message: "La piste « \(track.rawValue) » n'a pas pu repartir après cinq essais."))
                }
            }
        })
        started.append(Task { await supervisor.run(seconds: nil) })
        // A trace that can no longer be written is said once.
        started.append(Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if let failure = await trace.failure {
                    continuation.yield(.traceFailed("\(failure)"))
                    return
                }
            }
        })
        if let amplitude = selfTestAmplitude {
            started.append(Task.detached(priority: .utility) {
                // Starting the capture reconfigures the audio devices and can silence the check's tone for a
                // moment (seen with the whole-Mac tap): up to three tries, one second apart.
                var outcome = SystemAudioSelfTest.run(rounds: 1, amplitude: amplitude)
                for _ in 0..<2 where Self.selfTestFailed(result: outcome.result) && !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    outcome = SystemAudioSelfTest.run(rounds: 1, amplitude: amplitude)
                }
                let passed = !Self.selfTestFailed(result: outcome.result)
                try? await trace.write(kind: "self-test", SelfTestRecord(passed: passed, result: outcome.result, amplitude: amplitude))
                continuation.yield(.selfTest(passed: passed))
            })
        }
        let all = started
        tasks.withLock { $0 += all }
    }

    /// Stops the capture, waits until every file is closed and the gaps are written, then closes the timeline.
    public func stop() async {
        stopped.withLock { $0 = true }
        let running = tasks.withLock { tasks in defer { tasks = [] }; return tasks }
        for task in running { task.cancel() }
        for task in running { await task.value }
        await trace.close()
        continuation.finish()
    }

    /// The pre-recording of a declined meeting is destroyed, as the design says.
    public func discard() async {
        await stop()
        try? FileManager.default.removeItem(at: folder)
    }
}
