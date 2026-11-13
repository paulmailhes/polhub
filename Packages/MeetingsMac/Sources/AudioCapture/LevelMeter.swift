/// What one stretch of audio contained.
public struct LevelStats: Equatable, Sendable, Codable {
    public let frames: Int
    /// Frames where every channel is exactly 0.0: what macOS delivers when a permission is missing.
    public let exactZeroFrames: Int
    public let rms: Float
    public let peak: Float

    /// The same, with a level that is not a number (a broken sample) written as 0.
    public var finite: LevelStats {
        LevelStats(frames: frames, exactZeroFrames: exactZeroFrames, rms: rms.isFinite ? rms : 0, peak: peak.isFinite ? peak : 0)
    }

    public init(frames: Int, exactZeroFrames: Int, rms: Float, peak: Float) {
        self.frames = frames
        self.exactZeroFrames = exactZeroFrames
        self.rms = rms
        self.peak = peak
    }
}

/// Accumulates level statistics over interleaved buffers until `flush`.
public struct LevelMeter: Sendable {
    private let channels: Int
    private var frames = 0
    private var zeroFrames = 0
    private var sumOfSquares = 0.0
    private var peak: Float = 0

    public init(channels: Int) {
        self.channels = max(1, channels)
    }

    public mutating func add(_ samples: UnsafeBufferPointer<Float>) {
        var index = 0
        while index + channels <= samples.count {
            var silent = true
            for channel in 0..<channels {
                let sample = samples[index + channel]
                if sample != 0 { silent = false }
                sumOfSquares += Double(sample) * Double(sample)
                peak = max(peak, abs(sample))
            }
            if silent { zeroFrames += 1 }
            frames += 1
            index += channels
        }
    }

    /// Returns the statistics since the last flush and starts over.
    public mutating func flush() -> LevelStats {
        let sampleCount = frames * channels
        let stats = LevelStats(
            frames: frames,
            exactZeroFrames: zeroFrames,
            rms: sampleCount > 0 ? Float((sumOfSquares / Double(sampleCount)).squareRoot()) : 0,
            peak: peak
        )
        frames = 0
        zeroFrames = 0
        sumOfSquares = 0
        peak = 0
        return stats
    }
}

public enum CaptureHealth: String, Codable, Sendable {
    case ok
    /// Nothing but exact zeros, and nothing was playing: plain silence.
    case silent
    /// Nothing but exact zeros (or nothing at all) while the source was playing: the capture is broken,
    /// most likely a missing permission. Never to be read as a measurement.
    case silentWhileAudible

    public static func verdict(_ stats: LevelStats, sourceWasPlaying: Bool) -> CaptureHealth {
        guard stats.exactZeroFrames == stats.frames else { return .ok }
        return sourceWasPlaying ? .silentWhileAudible : .silent
    }
}
