import Darwin
import Foundation
import Synchronization

/// Ties a position in the recorded audio to two clocks: the audio hardware's (`hostTime`, which stops
/// while the Mac sleeps) and a continuous one (which does not). Gaps are measured between anchors.
public struct TimeAnchor: Equatable, Sendable, Codable {
    /// Index, in frames ingested since the start, of the first frame of the buffer this anchor describes.
    public let frameIndex: Int64
    public let hostTime: UInt64
    public let continuousNanos: UInt64

    public init(frameIndex: Int64, hostTime: UInt64, continuousNanos: UInt64) {
        self.frameIndex = frameIndex
        self.hostTime = hostTime
        self.continuousNanos = continuousNanos
    }
}

/// Records one track: the audio callback hands buffers to `ingest`, a writer thread stores them in CAF
/// segments and reports level statistics once per second of audio.
///
/// `ingest` is real-time safe: it copies into a ring buffer and notes a time anchor, nothing else.
public final class TrackRecorder: @unchecked Sendable {
    public typealias SecondHandler = @Sendable (_ stats: LevelStats, _ anchor: TimeAnchor, _ droppedFrames: Int) -> Void

    private let format: PCMFormat
    private let ring: SPSCRingBuffer
    private let onSecond: SecondHandler
    private let onWriteError: (@Sendable (Error) -> Void)?

    // Written by the audio callback only.
    private let ingested = Atomic<Int64>(0)
    // Seqlock around the latest anchor: odd while the callback is writing it.
    private let anchorSequence = Atomic<UInt64>(0)
    private nonisolated(unsafe) var anchorFrame: Int64 = 0
    private nonisolated(unsafe) var anchorHostTime: UInt64 = 0
    private nonisolated(unsafe) var anchorNanos: UInt64 = 0

    // Touched by the writer thread only, then by `finish` once that thread has ended.
    private nonisolated(unsafe) var writer: CAFSegmentWriter
    private nonisolated(unsafe) var meter: LevelMeter
    private nonisolated(unsafe) var framesInSecond = 0
    private nonisolated(unsafe) var reportedDrops = 0
    private nonisolated(unsafe) var writeError: Error?
    private let scratch: UnsafeMutablePointer<Float>
    private let scratchFrames: Int

    private let stopping = Atomic<Bool>(false)
    private let stopped = DispatchSemaphore(value: 0)
    private nonisolated(unsafe) var finished = false

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    public init(
        directory: URL,
        format: PCMFormat,
        segmentSeconds: Double = 60,
        ringSeconds: Double = 2,
        onWriteError: (@Sendable (Error) -> Void)? = nil,
        onSecond: @escaping SecondHandler
    ) throws {
        self.format = format
        self.onSecond = onSecond
        self.onWriteError = onWriteError
        ring = SPSCRingBuffer(capacityFrames: max(1, Int(ringSeconds * format.sampleRate)), channels: format.channels)
        writer = try CAFSegmentWriter(directory: directory, format: format, segmentSeconds: segmentSeconds)
        meter = LevelMeter(channels: format.channels)
        scratchFrames = max(1, Int(format.sampleRate / 2))
        scratch = .allocate(capacity: scratchFrames * format.channels)
        _ = Self.timebase

        let thread = Thread { [self] in
            while !stopping.load(ordering: .acquiring) {
                drain()
                usleep(50_000)
            }
            stopped.signal()
        }
        thread.name = "fr.paulmailhes.transcriptor.track-writer"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    deinit {
        if !finished {
            stopping.store(true, ordering: .releasing)
            stopped.wait()
        }
        scratch.deallocate()
    }

    /// Called from the audio callback. `samples` holds `frames` interleaved frames.
    public func ingest(_ samples: UnsafeBufferPointer<Float>, frames: Int, hostTime: UInt64) {
        // Never trust the count over the buffer: a device can deliver fewer channels than announced.
        let frames = min(frames, samples.count / format.channels)
        guard let base = samples.baseAddress, frames > 0 else { return }
        let first = ingested.load(ordering: .relaxed)
        let nanos = mach_continuous_time() * UInt64(Self.timebase.numer) / UInt64(Self.timebase.denom)

        anchorSequence.add(1, ordering: .acquiringAndReleasing)
        anchorFrame = first
        anchorHostTime = hostTime
        anchorNanos = nanos
        anchorSequence.add(1, ordering: .acquiringAndReleasing)

        ring.write(base, frames: frames)
        ingested.store(first + Int64(frames), ordering: .relaxed)
    }

    /// Stops the writer thread, stores what is left, reports the last partial second, closes the segment.
    public func finish() throws {
        guard !finished else { return }
        stopping.store(true, ordering: .releasing)
        stopped.wait()
        finished = true
        drain()
        report()
        try writer.close()
        if let writeError { throw writeError }
    }

    // MARK: - Writer thread

    private func drain() {
        while true {
            let frames = ring.read(into: scratch, maxFrames: scratchFrames)
            guard frames > 0 else { return }
            let buffer = UnsafeBufferPointer(start: scratch, count: frames * format.channels)
            do {
                try writer.append(buffer)
            } catch {
                // The first write error is said at once: a full disk must not wait for the end of the meeting.
                if writeError == nil { onWriteError?(error) }
                writeError = writeError ?? error
            }
            meterBySeconds(buffer, frames: frames)
        }
    }

    /// Feeds the meter, cutting exactly at each second of audio.
    private func meterBySeconds(_ buffer: UnsafeBufferPointer<Float>, frames: Int) {
        let framesPerSecond = max(1, Int(format.sampleRate))
        var offset = 0
        while offset < frames {
            let count = min(frames - offset, framesPerSecond - framesInSecond)
            let slice = UnsafeBufferPointer(rebasing: buffer[(offset * format.channels)..<((offset + count) * format.channels)])
            meter.add(slice)
            framesInSecond += count
            offset += count
            if framesInSecond >= framesPerSecond { report() }
        }
    }

    private func report() {
        let dropped = ring.droppedFrames
        let newDrops = dropped - reportedDrops
        guard framesInSecond > 0 || newDrops > 0 else { return }
        reportedDrops = dropped
        framesInSecond = 0
        onSecond(meter.flush(), latestAnchor(), newDrops)
    }

    private func latestAnchor() -> TimeAnchor {
        while true {
            let before = anchorSequence.load(ordering: .acquiring)
            if before & 1 == 1 { continue }
            let anchor = TimeAnchor(frameIndex: anchorFrame, hostTime: anchorHostTime, continuousNanos: anchorNanos)
            if anchorSequence.load(ordering: .acquiring) == before { return anchor }
        }
    }
}
