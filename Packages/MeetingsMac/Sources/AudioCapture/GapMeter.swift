/// A stretch of time during which no audio was received.
public struct Gap: Equatable, Sendable, Codable {
    /// Frame index of the anchor after which the audio went missing.
    public let afterFrame: Int64
    public let missingSeconds: Double

    public init(afterFrame: Int64, missingSeconds: Double) {
        self.afterFrame = afterFrame
        self.missingSeconds = missingSeconds
    }
}

public enum GapMeter {
    /// Compares, between consecutive anchors, the time that passed with the audio that arrived.
    ///
    /// Time is read on the continuous clock, so a sleep shows up as a gap even though the audio clock
    /// stood still. Anchors that go backwards are ignored.
    public static func gaps(anchors: [TimeAnchor], sampleRate: Double, toleranceSeconds: Double = 0.05) -> [Gap] {
        guard sampleRate > 0 else { return [] }
        var gaps: [Gap] = []
        for (previous, next) in zip(anchors, anchors.dropFirst()) {
            guard next.frameIndex > previous.frameIndex, next.continuousNanos > previous.continuousNanos else { continue }
            let elapsed = Double(next.continuousNanos - previous.continuousNanos) / 1e9
            let received = Double(next.frameIndex - previous.frameIndex) / sampleRate
            let missing = elapsed - received
            if missing > toleranceSeconds {
                gaps.append(Gap(afterFrame: previous.frameIndex, missingSeconds: missing))
            }
        }
        return gaps
    }
}
