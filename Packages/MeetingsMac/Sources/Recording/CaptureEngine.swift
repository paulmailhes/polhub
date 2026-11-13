import AudioCapture
import CoreAudio
import Foundation
import MeetingDetection
import Observability
import os

/// Which way of tapping Dia's sound a capture run uses. Phase 0 compares them.
public struct CaptureVariant: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case a = "A"   // the Core Audio processes whose executable lives inside Dia.app
        case b = "B"   // Dia's bundle identifier
        case c = "C"   // Dia's bundle identifier and its helper's
        case d = "D"   // the whole system output, except this app
    }

    static let diaHelperBundleID = "company.thebrowser.browser.helper"

    public let kind: Kind
    /// Anchor the aggregate on the default output device instead of holding the tap alone.
    public let anchoredOnOutput: Bool

    public var label: String { kind.rawValue + (anchoredOnOutput ? "+sortie" : "") }

    /// `A`, `B`, `C`, `D`, optionally followed by `+sortie`. Anything else is variant A.
    public static func parse(_ raw: String?) -> CaptureVariant {
        let parts = (raw ?? "").split(separator: "+", maxSplits: 1).map(String.init)
        return CaptureVariant(
            kind: Kind(rawValue: parts.first?.uppercased() ?? "") ?? .a,
            anchoredOnOutput: parts.count > 1 && parts[1].lowercased() == "sortie"
        )
    }

    /// Nil when there is nothing to listen to: variant A while Dia has no audio process.
    func target(diaProcesses: [AudioObjectID], ownProcess: AudioObjectID?) -> TapTarget? {
        switch kind {
        case .a: diaProcesses.isEmpty ? nil : .processes(diaProcesses)
        case .b: .bundleIDs([DiaAdapter.diaBundleID])
        case .c: .bundleIDs([DiaAdapter.diaBundleID, Self.diaHelperBundleID])
        case .d: .globalExcluding(ownProcess.map { [$0] } ?? [])
        }
    }
}

/// Where the `moi` track takes its microphones: those Dia holds (a meeting), or the system's default input
/// (« Enregistrer maintenant », which records the whole Mac).
public enum MicSource: Sendable {
    case heldByDia
    case systemDefault
}

/// Which microphones to stop and to start so that the `moi` track records exactly the ones Dia holds.
/// The microphones that stay held are left running: dropping one never cuts the other.
struct MicPlan: Equatable, Sendable {
    let stop: [String]
    let start: [String]

    var isEmpty: Bool { stop.isEmpty && start.isEmpty }

    static func reconcile(recording: Set<String>, held: [String]) -> MicPlan {
        MicPlan(
            stop: recording.subtracting(held).sorted(),
            start: Set(held).subtracting(recording).sorted()
        )
    }
}

/// One capture setup: the tap on Dia's sound (track `autres`) and every microphone Dia holds (track
/// `moi`, one stream per microphone). Dia can hold two microphones at once, the built-in one and the
/// headset's, and the first one listed is not always the one Meet sends (measured on 13/11): all are
/// recorded, and the clearest is chosen after the meeting. A microphone Dia does not hold is never opened,
/// so a Bluetooth headset is never switched to its call profile by this app.
///
/// The two tracks are built, started and rebuilt independently: losing the microphone never stops the
/// recording of the others. Nothing is processed in real time: raw audio goes to disk, statistics to the
/// trace. Each build of a stream writes to its own folder.
///
/// `start…` and `stop…` are called from one task at a time; they block for up to 3 s per stream.
public final class CaptureEngine: @unchecked Sendable {
    public enum Track: String, Sendable, Hashable, Codable, CaseIterable {
        case moi
        case autres
    }

    struct StartRecord: Encodable, Sendable {
        let variant: String
        let build: Int
        let reason: String
        let startLatencyMs: Double
        let tapFormat: PCMFormat?
        let streamFormat: PCMFormat
        let rewriteDescriptionStatus: Int32
        let processCount: Int
        let processPIDs: [Int32]
    }

    struct MicStartRecord: Encodable, Sendable {
        let build: Int
        let reason: String
        let startLatencyMs: Double
        let deviceUID: String
        let format: PCMFormat
    }

    struct SecondRecord: Encodable, Sendable {
        let track: String
        /// The microphone, for `moi`; absent for `autres`.
        let device: String?
        let build: Int
        let stats: LevelStats
        let anchor: TimeAnchor
        let dropped: Int
        let health: CaptureHealth
        let sourceWasPlaying: Bool
    }

    struct ErrorRecord: Encodable, Sendable {
        let track: String
        let step: String
        let status: Int32?
        let message: String
        let build: Int
    }

    /// The anchors of one stream during one build, with the sample rate needed to read them.
    struct AnchorRun: Sendable {
        let track: Track
        let build: Int
        /// The microphone, for `moi`; nil for `autres`.
        let device: String?
        let sampleRate: Double
        var anchors: [TimeAnchor]
    }

    /// One stream: the tap for `autres`, or one microphone for `moi`.
    struct Feed: Hashable, Sendable {
        let track: Track
        let device: String?

        static let others = Feed(track: .autres, device: nil)
        static func mic(_ uid: String) -> Feed { Feed(track: .moi, device: uid) }
    }

    /// What the tracks were built on. Read from the recorder threads, written by the task that builds.
    private struct Route: Sendable {
        var tappedProcesses: [AudioObjectID] = []
        var micDeviceUIDs: [String] = []
        var tapFormat: PCMFormat?
        var builds: [Track: Int] = [:]
    }

    private struct MicFeed {
        let build: Int
        let stream: HALInputStream
        let recorder: TrackRecorder
    }

    let variant: CaptureVariant
    let micSource: MicSource
    private let directory: URL
    private let trace: TraceWriter
    private let monitor = AudioProcessMonitor()
    private let diaAppPath: String
    private let clock = ContinuousClock()
    /// Time without a report is counted on a clock that stops during sleep: a Mac that slept fifteen
    /// seconds has not been silent for fifteen seconds.
    private let awakeClock = SuspendingClock()

    private var tap: ProcessTap?
    private var aggregate: TapAggregate?
    private var othersStream: HALInputStream?
    private var othersRecorder: TrackRecorder?
    /// By device UID.
    private var mics: [String: MicFeed] = [:]

    private let route: OSAllocatedUnfairLock<Route>
    private let errorHandler = OSAllocatedUnfairLock<(@Sendable (Track, String) -> Void)?>(initialState: nil)
    private let runs = OSAllocatedUnfairLock<[AnchorRun]>(initialState: [])
    private let lastReports = OSAllocatedUnfairLock<[Feed: SuspendingClock.Instant]>(initialState: [:])

    /// `firstBuild`: the number the next build of each track takes, to go on in a folder after a crash.
    public init(
        variant: CaptureVariant, micSource: MicSource = .heldByDia, directory: URL, trace: TraceWriter,
        firstBuild: [Track: Int] = [:]
    ) {
        self.variant = variant
        self.micSource = micSource
        route = OSAllocatedUnfairLock(initialState: Route(builds: firstBuild.mapValues { $0 - 1 }))
        self.directory = directory
        self.trace = trace
        diaAppPath = DiaAdapter.appPath()
    }

    var tapID: AudioObjectID? { tap?.tapID }
    var othersRunning: Bool { othersStream != nil }
    var micRunning: Bool { !mics.isEmpty }
    var anchorRuns: [AnchorRun] { runs.withLock { $0 } }
    /// The processes the `autres` track was built on; empty while it is not running.
    var tappedProcesses: [AudioObjectID] { route.withLock { $0.tappedProcesses } }
    /// The microphones the `moi` track records, sorted; empty while it is not running.
    var micDeviceUIDs: [String] { route.withLock { $0.micDeviceUIDs } }

    // MARK: - What Dia is doing right now

    /// The Core Audio process objects that belong to Dia, sorted.
    func desiredProcesses() -> [AudioObjectID] {
        diaProcesses().map(\.objectID).sorted()
    }

    /// The microphones the `moi` track should record right now, sorted; empty when there are none.
    func desiredMicUIDs() -> [String] {
        Self.microphones(
            source: micSource, held: diaProcesses(),
            defaultInput: micSource == .systemDefault ? defaultInputUID() : nil
        )
    }

    static func microphones(source: MicSource, held: [AudioProcessInfo], defaultInput: String?) -> [String] {
        switch source {
        case .heldByDia: microphones(heldBy: held)
        case .systemDefault: defaultInput.map { [$0] } ?? []
        }
    }

    /// Where the sound the `autres` track records goes out, sorted: Dia's outputs, or the default output.
    func desiredOutputUIDs() -> [String] {
        switch micSource {
        case .heldByDia: Array(Set(diaProcesses().filter(\.isRunningOutput).flatMap(\.outputDeviceUIDs))).sorted()
        case .systemDefault: defaultOutputUID().map { [$0] } ?? []
        }
    }

    /// Called with each stream error, on the thread that met it.
    func onError(_ handler: @escaping @Sendable (Track, String) -> Void) {
        errorHandler.withLock { $0 = handler }
    }

    static func microphones(heldBy processes: [AudioProcessInfo]) -> [String] {
        Array(Set(processes.filter(\.isRunningInput).flatMap(\.inputDeviceUIDs))).sorted()
    }

    func isDiaPlaying() -> Bool {
        diaProcesses().contains { $0.isRunningOutput }
    }

    /// Whether the stream is supposed to be receiving audio right now: Dia is playing, for `autres`;
    /// Dia still holds this microphone, for `moi`.
    private func shouldDeliver(_ feed: Feed) -> Bool {
        switch feed.track {
        case .autres: isDiaPlaying()
        case .moi: feed.device.map(desiredMicUIDs().contains) ?? false
        }
    }

    /// The streams that are running in the rig right now.
    private var runningFeeds: [Feed] {
        (othersRunning ? [Feed.others] : []) + mics.keys.sorted().map(Feed.mic)
    }

    /// The tracks with a stream that should be delivering and has gone quiet (see `RebuildScheduler`).
    func stalledTracks(secondsSinceWake: Double?) -> [Track] {
        let stalled = runningFeeds.filter {
            RebuildScheduler.isStalled(
                secondsSinceReport: secondsSinceReport($0), shouldDeliver: shouldDeliver($0),
                secondsSinceWake: secondsSinceWake
            )
        }
        return Track.allCases.filter { track in stalled.contains { $0.track == track } }
    }

    /// True when the tap still has the format the `autres` track was built with.
    func tapFormatMatchesBuild() -> Bool {
        guard let tap, let built = route.withLock({ $0.tapFormat }) else { return false }
        return (try? tap.format()) == built
    }

    /// Awake seconds since the stream last reported a second of audio (or since it was started).
    private func secondsSinceReport(_ feed: Feed) -> Double? {
        guard let last = lastReports.withLock({ $0[feed] }) else { return nil }
        let elapsed = awakeClock.now - last
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    // MARK: - Tracks that deliver nothing

    static func isSilent(secondsSinceReport: Double?) -> Bool {
        (secondsSinceReport ?? 0) > 2
    }

    /// The line written for a second during which a stream delivered no audio at all.
    static func silentRecord(track: Track, device: String?, build: Int, playing: Bool, lastAnchor: TimeAnchor?) -> SecondRecord {
        let nothing = LevelStats(frames: 0, exactZeroFrames: 0, rms: 0, peak: 0)
        return SecondRecord(
            track: track.rawValue, device: device, build: build, stats: nothing,
            anchor: lastAnchor ?? TimeAnchor(frameIndex: 0, hostTime: 0, continuousNanos: 0),
            dropped: 0, health: CaptureHealth.verdict(nothing, sourceWasPlaying: playing), sourceWasPlaying: playing
        )
    }

    /// Call once a second. A running stream that has delivered nothing for two seconds gets a `capture`
    /// line saying so: without it, a capture that never receives a buffer would leave no trace at all and
    /// read as a flawless one.
    public func reportSilentTracks() {
        for feed in runningFeeds where Self.isSilent(secondsSinceReport: secondsSinceReport(feed)) {
            let build = feed.device.flatMap { mics[$0]?.build } ?? route.withLock { $0.builds[feed.track] ?? 0 }
            let lastAnchor = runs.withLock { $0.last { $0.track == feed.track && $0.build == build }?.anchors.last }
            write("capture", Self.silentRecord(
                track: feed.track, device: feed.device, build: build, playing: shouldDeliver(feed), lastAnchor: lastAnchor
            ))
        }
    }

    // MARK: - Both tracks

    /// The microphones first: opening a Bluetooth microphone can change the default output.
    /// When the `autres` track cannot start, the microphones are released too.
    @discardableResult
    public func start(reason: String = "start") -> Bool {
        syncMics(reason: reason)
        return startOthers(reason: reason)
    }

    public func stop() {
        stopOthers()
        stopMics()
    }

    // MARK: - Track `autres`

    /// Builds the tap, its aggregate and the recorder, and starts them. On failure everything built so far
    /// is torn down and the error is written to the trace.
    @discardableResult
    func startOthers(reason: String) -> Bool {
        let build = nextBuild(.autres)
        let began = clock.now
        let dia = diaProcesses()
        let processes = dia.map(\.objectID).sorted()
        var step = "target"
        do {
            guard let target = variant.target(
                diaProcesses: processes,
                ownProcess: try? HAL.processObject(forPID: getpid())
            ) else {
                throw RigError.noDiaAudioProcess
            }

            step = "tap"
            let tap = try ProcessTap(target: target, name: "Transcriptor (autres)")
            self.tap = tap
            let tapFormat = try? tap.format()
            let rewriteStatus = tap.rewriteDescription()

            step = "aggregate"
            let aggregate = try TapAggregate(
                tap: tap, mainSubDeviceUID: variant.anchoredOnOutput ? defaultOutputUID() : nil
            )
            self.aggregate = aggregate

            step = "stream"
            let (stream, recorder) = try makeTrack(.others, build: build, device: aggregate.deviceID)
            othersStream = stream
            othersRecorder = recorder

            step = "start"
            try stream.start()

            route.withLock {
                $0.tappedProcesses = processes
                $0.tapFormat = tapFormat
            }
            write("capture-start", StartRecord(
                variant: variant.label, build: build, reason: reason, startLatencyMs: milliseconds(since: began),
                tapFormat: tapFormat, streamFormat: stream.format, rewriteDescriptionStatus: rewriteStatus,
                processCount: processes.count, processPIDs: dia.map(\.pid)
            ))
            return true
        } catch {
            reportError(ErrorRecord(
                track: Track.autres.rawValue, step: step, status: (error as? HALError)?.status,
                message: "\(error)", build: build
            ))
            stopOthers()
            return false
        }
    }

    /// Always complete, always in this order: stream, then aggregate, then tap. The aggregate and the tap
    /// are destroyed only once Core Audio has really let go of the stream, even if that comes late.
    func stopOthers() {
        let aggregate = aggregate
        let tap = tap
        if let stream = othersStream {
            let stopped = stream.stop(then: {
                aggregate?.invalidate()
                tap?.invalidate()
            })
            if !stopped { noteStopTimeout(.autres) }
        } else {
            aggregate?.invalidate()
            tap?.invalidate()
        }
        finish(othersRecorder, track: .autres)
        othersStream = nil
        othersRecorder = nil
        self.aggregate = nil
        self.tap = nil
        route.withLock {
            $0.tappedProcesses = []
            $0.tapFormat = nil
        }
        lastReports.withLock { $0[.others] = nil }
    }

    // MARK: - Track `moi`

    /// Records exactly the microphones Dia holds: stops those it let go, starts those it took, and leaves
    /// the others running. True when every start succeeded (nothing to start is a success).
    @discardableResult
    func syncMics(reason: String) -> Bool {
        let plan = MicPlan.reconcile(recording: Set(mics.keys), held: desiredMicUIDs())
        plan.stop.forEach(stopMic)
        var allStarted = true
        for uid in plan.start {
            if !startMic(uid, reason: reason) { allStarted = false }
        }
        return allStarted
    }

    /// Whether the microphones recorded differ from those wanted.
    func micsNeedSync() -> Bool {
        !MicPlan.reconcile(recording: Set(mics.keys), held: desiredMicUIDs()).isEmpty
    }

    /// Rebuilds every microphone: after a format change, a stall or a restart of Core Audio.
    @discardableResult
    func restartMics(reason: String) -> Bool {
        stopMics()
        return syncMics(reason: reason)
    }

    func stopMics() {
        mics.keys.sorted().forEach(stopMic)
    }

    private func startMic(_ uid: String, reason: String) -> Bool {
        let build = nextBuild(.moi)
        let began = clock.now
        var step = "device"
        var built: (stream: HALInputStream, recorder: TrackRecorder)?
        do {
            let device = try HAL.device(forUID: uid)
            step = "stream"
            let (stream, recorder) = try makeTrack(.mic(uid), build: build, device: device)
            built = (stream, recorder)
            step = "start"
            try stream.start()
            mics[uid] = MicFeed(build: build, stream: stream, recorder: recorder)
            let recording = mics.keys.sorted()
            route.withLock { $0.micDeviceUIDs = recording }
            write("mic-start", MicStartRecord(
                build: build, reason: reason, startLatencyMs: milliseconds(since: began),
                deviceUID: uid, format: stream.format
            ))
            return true
        } catch {
            reportError(ErrorRecord(
                track: Track.moi.rawValue, step: step, status: (error as? HALError)?.status,
                message: "\(error) (\(uid))", build: build
            ))
            if let built {
                if !built.stream.stop() { noteStopTimeout(.moi) }
                finish(built.recorder, track: .moi)
            }
            lastReports.withLock { $0[.mic(uid)] = nil }
            return false
        }
    }

    private func stopMic(_ uid: String) {
        guard let feed = mics.removeValue(forKey: uid) else { return }
        if !feed.stream.stop() { noteStopTimeout(.moi) }
        finish(feed.recorder, track: .moi)
        let recording = mics.keys.sorted()
        route.withLock { $0.micDeviceUIDs = recording }
        lastReports.withLock { $0[.mic(uid)] = nil }
    }

    // MARK: - Pieces

    private enum RigError: Error {
        case noDiaAudioProcess
    }

    private func nextBuild(_ track: Track) -> Int {
        route.withLock {
            let build = ($0.builds[track] ?? 0) + 1
            $0.builds[track] = build
            return build
        }
    }

    private func milliseconds(since instant: ContinuousClock.Instant) -> Double {
        let elapsed = clock.now - instant
        return Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
    }

    private func diaProcesses() -> [AudioProcessInfo] {
        ((try? monitor.snapshot()) ?? []).filter { $0.owningAppPath == diaAppPath }
    }

    private func reportError(_ record: ErrorRecord) {
        write("capture-error", record)
        guard Self.isWorthTelling(step: record.step, message: record.message),
              let track = Track(rawValue: record.track), let handler = errorHandler.withLock({ $0 })
        else { return }
        handler(track, Self.frenchMessage(track: record.track, step: record.step, status: record.status))
    }

    /// « Nothing to listen to » (Dia's audio process went away) and a slow stop are expected: they stay in
    /// the trace and do not reach the person (review, Important 6).
    static func isWorthTelling(step: String, message: String) -> Bool {
        step != "stop-timeout" && step != "target" && !message.contains("noDiaAudioProcess")
    }

    static func frenchMessage(track: String, step: String, status: Int32?) -> String {
        let steps = ["tap": "prise du son de Dia", "aggregate": "périphérique de capture", "stream": "ouverture du flux",
                     "start": "démarrage", "device": "micro introuvable", "write": "écriture sur le disque", "finish": "fermeture du fichier"]
        let what = steps[step] ?? step
        return "La piste « \(track) » s'est interrompue (\(what)\(status.map { ", erreur \($0)" } ?? ""))."
    }

    private func defaultInputUID() -> String? {
        guard let device = try? HAL.value(HAL.system, kAudioHardwarePropertyDefaultInputDevice, as: AudioObjectID.self)
        else { return nil }
        return try? HAL.string(device, kAudioDevicePropertyDeviceUID)
    }

    private func defaultOutputUID() -> String? {
        guard let device = try? HAL.value(HAL.system, kAudioHardwarePropertyDefaultOutputDevice, as: AudioObjectID.self)
        else { return nil }
        return try? HAL.string(device, kAudioDevicePropertyDeviceUID)
    }

    private func noteStopTimeout(_ track: Track) {
        reportError(ErrorRecord(
            track: track.rawValue, step: "stop-timeout", status: nil,
            message: "Core Audio n'a pas rendu la main en 3 s ; le démontage se finira quand il la rendra.",
            build: route.withLock { $0.builds[track] ?? 0 }
        ))
    }

    private func finish(_ recorder: TrackRecorder?, track: Track) {
        do {
            try recorder?.finish()
        } catch {
            reportError(ErrorRecord(
                track: track.rawValue, step: "finish", status: nil, message: "\(error)",
                build: route.withLock { $0.builds[track] ?? 0 }
            ))
        }
    }

    /// `b01` for the tap, `b02-00-11-22-33-44-55-input` for a microphone: a name the Finder shows as is.
    static func folderName(build: Int, device: String?) -> String {
        let number = "b" + String(format: "%02d", build)
        guard let device else { return number }
        let slug = String(device.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
        return number + "-" + slug
    }

    private func makeTrack(_ feed: Feed, build: Int, device: AudioObjectID) throws -> (HALInputStream, TrackRecorder) {
        let track = feed.track
        let slot = RecorderSlot()
        let stream = try HALInputStream(deviceID: device) { samples, frames, hostTime in
            slot.recorder?.ingest(samples, frames: frames, hostTime: hostTime)
        }
        let folder = directory.appending(
            path: "audio/\(track.rawValue)/\(Self.folderName(build: build, device: feed.device))", directoryHint: .isDirectory
        )
        runs.withLock {
            $0.append(AnchorRun(track: track, build: build, device: feed.device, sampleRate: stream.format.sampleRate, anchors: []))
        }
        lastReports.withLock { $0[feed] = awakeClock.now }

        let recorder = try TrackRecorder(directory: folder, format: stream.format, onWriteError: { [weak self] error in
            self?.reportError(ErrorRecord(track: track.rawValue, step: "write", status: nil, message: "\(error)", build: build))
        }) { [weak self] stats, anchor, dropped in
            guard let self else { return }
            runs.withLock { runs in
                if let index = runs.lastIndex(where: { $0.track == track && $0.build == build }) {
                    runs[index].anchors.append(anchor)
                }
            }
            lastReports.withLock { reports in
                if reports[feed] != nil { reports[feed] = self.awakeClock.now }
            }
            let playing = shouldDeliver(feed)
            let stats = stats.finite
            write("capture", SecondRecord(
                track: track.rawValue, device: feed.device, build: build, stats: stats, anchor: anchor, dropped: dropped,
                health: CaptureHealth.verdict(stats, sourceWasPlaying: playing), sourceWasPlaying: playing
            ))
        }
        slot.recorder = recorder
        return (stream, recorder)
    }

    func write<P: Encodable & Sendable>(_ kind: String, _ payload: P) {
        let trace = trace
        Task { try? await trace.write(kind: kind, payload) }
    }

    /// Lets the audio callback reach a recorder that is created after the stream it reads from.
    private final class RecorderSlot: @unchecked Sendable {
        var recorder: TrackRecorder?
    }
}

/// When a track must be built again, and how long the hole lasted.
enum RebuildPolicy {
    /// Only a change of the route a track really uses rebuilds it. A screen that goes to sleep or an iPhone
    /// that comes near changes the list of devices without touching the call: such events are logged only.
    /// A `tapFormat` notification that leaves the format as it was built is the echo of our own rebuild.
    static func tracks(for event: RouteEvent, tapFormatUnchanged: Bool = false) -> Set<CaptureEngine.Track> {
        switch (event.source, event.side) {
        case ("tapFormat", _): tapFormatUnchanged ? [] : [.autres]
        case ("streamFormat", "input"): [.moi]
        case ("serviceRestarted", _): [.moi, .autres]
        // Dia took or let go of a device: the microphones are synced at once, without waiting for the poll.
        case ("processDevices", _): [.moi]
        default: []
        }
    }

    /// A rebuild of `moi` for these reasons only starts or stops the microphones that changed.
    static func syncsOnly(reason: String) -> Bool {
        reason == "micRoute" || reason == "processDevices"
    }

    /// Time without audio between the last buffer of one build and the first frame of the next.
    /// Approximate to one audio buffer: the anchors describe whole buffers.
    static func holeSeconds(lastOfPrevious: TimeAnchor, firstOfNext: TimeAnchor, nextSampleRate: Double) -> Double {
        let firstFrameNanos = Double(firstOfNext.continuousNanos) - Double(firstOfNext.frameIndex) / nextSampleRate * 1e9
        return (firstFrameNanos - Double(lastOfPrevious.continuousNanos)) / 1e9
    }
}

/// Decides when a track is rebuilt. Times are seconds on any clock that only goes forward.
///
/// - an event waits for 400 ms without another event before it acts (a route change comes in bursts);
/// - two rebuilds of the same track are at least 2 s apart;
/// - after five rebuilds in a row that failed, the track is left alone until its route changes: no
///   rebuilding for ever against something that will not work.
struct RebuildScheduler {
    static let quietSeconds = 0.4
    static let minimumSpacing = 2.0
    static let maxFailuresInARow = 5
    static let stallSeconds = 3.0
    static let wakeGraceSeconds = 5.0

    private var pending: [CaptureEngine.Track: (reason: String, since: Double)] = [:]
    private var lastRebuild: [CaptureEngine.Track: Double] = [:]
    private var failures: [CaptureEngine.Track: Int] = [:]

    /// A route notification: it (re)starts the quiet wait.
    mutating func note(_ track: CaptureEngine.Track, reason: String, at now: Double) {
        guard !hasGivenUp(track) else { return }
        pending[track] = (reason, now)
    }

    /// Something noticed by polling: it does not restart a wait already running.
    mutating func noteIfIdle(_ track: CaptureEngine.Track, reason: String, at now: Double) {
        guard !hasGivenUp(track), pending[track] == nil else { return }
        pending[track] = (reason, now)
    }

    /// The rebuilds to do now. Each is handed out once.
    mutating func due(at now: Double) -> [(track: CaptureEngine.Track, reason: String)] {
        var ready: [(track: CaptureEngine.Track, reason: String)] = []
        for track in CaptureEngine.Track.allCases {
            guard let wanted = pending[track], now - wanted.since >= Self.quietSeconds else { continue }
            if let last = lastRebuild[track], now - last < Self.minimumSpacing { continue }
            pending[track] = nil
            ready.append((track, wanted.reason))
        }
        return ready
    }

    mutating func finished(_ track: CaptureEngine.Track, ok: Bool, at now: Double) {
        lastRebuild[track] = now
        failures[track] = ok ? 0 : (failures[track] ?? 0) + 1
    }

    func hasGivenUp(_ track: CaptureEngine.Track) -> Bool {
        (failures[track] ?? 0) >= Self.maxFailuresInARow
    }

    /// What the track should be listening to has changed: earlier failures no longer count.
    mutating func routeChanged(_ track: CaptureEngine.Track) {
        failures[track] = 0
    }

    /// A track that should be delivering and has reported nothing for three awake seconds is stalled,
    /// except in the five seconds after a wake, when the audio thread has not resumed yet.
    static func isStalled(secondsSinceReport: Double?, shouldDeliver: Bool, secondsSinceWake: Double?) -> Bool {
        guard shouldDeliver, let secondsSinceReport, secondsSinceReport > stallSeconds else { return false }
        if let secondsSinceWake, secondsSinceWake < wakeGraceSeconds { return false }
        return true
    }
}
