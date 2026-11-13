import Synchronization

/// Single-producer, single-consumer ring of interleaved float frames.
///
/// `write` is called from the real-time audio callback: it takes no lock and allocates nothing.
/// `read` is called from the writer thread. Counters only grow; positions are taken modulo capacity.
public final class SPSCRingBuffer: @unchecked Sendable {
    private let capacity: Int
    private let channels: Int
    private let storage: UnsafeMutablePointer<Float>
    private let written = Atomic<Int>(0)
    private let consumed = Atomic<Int>(0)
    private let dropped = Atomic<Int>(0)

    public init(capacityFrames: Int, channels: Int) {
        precondition(capacityFrames > 0 && channels > 0)
        capacity = capacityFrames
        self.channels = channels
        storage = .allocate(capacity: capacityFrames * channels)
        storage.initialize(repeating: 0, count: capacityFrames * channels)
    }

    deinit {
        storage.deallocate()
    }

    /// Frames lost because the reader fell behind.
    public var droppedFrames: Int { dropped.load(ordering: .relaxed) }

    /// Returns the number of frames written; fewer than `frames` means the ring was full.
    @discardableResult
    public func write(_ source: UnsafePointer<Float>, frames: Int) -> Int {
        let start = written.load(ordering: .relaxed)
        let free = capacity - (start - consumed.load(ordering: .acquiring))
        let count = max(0, min(frames, free))
        if count > 0 {
            let position = start % capacity
            let first = min(count, capacity - position)
            (storage + position * channels).update(from: source, count: first * channels)
            if count > first {
                storage.update(from: source + first * channels, count: (count - first) * channels)
            }
            written.store(start + count, ordering: .releasing)
        }
        if count < frames {
            dropped.add(frames - count, ordering: .relaxed)
        }
        return count
    }

    /// Returns the number of frames copied into `destination`.
    @discardableResult
    public func read(into destination: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int {
        let start = consumed.load(ordering: .relaxed)
        let available = written.load(ordering: .acquiring) - start
        let count = max(0, min(maxFrames, available))
        if count > 0 {
            let position = start % capacity
            let first = min(count, capacity - position)
            destination.update(from: storage + position * channels, count: first * channels)
            if count > first {
                (destination + first * channels).update(from: storage, count: (count - first) * channels)
            }
            consumed.store(start + count, ordering: .releasing)
        }
        return count
    }
}
