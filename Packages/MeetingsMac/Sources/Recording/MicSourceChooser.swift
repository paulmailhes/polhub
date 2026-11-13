import Foundation

/// A stretch of time during which one microphone run is the one to listen to.
public struct ChosenSpan: Equatable, Sendable, Codable {
    public let runID: String
    public let fromNanos: UInt64
    public let toNanos: UInt64

    public init(runID: String, fromNanos: UInt64, toNanos: UInt64) {
        self.runID = runID
        self.fromNanos = fromNanos
        self.toNanos = toNanos
    }
}

/// Dia sometimes holds two microphones at once, the headset's and the Mac's (phase 0): both are recorded,
/// and after the meeting the clearest one is kept wherever they overlap. Time is cut at every start and end
/// of a run; on each piece the run whose median level is the highest wins; neighbouring pieces won by the
/// same run are joined.
public enum MicSourceChooser {
    public static func choose(_ moiRuns: [StreamRun]) -> [ChosenSpan] {
        let bounds = Array(Set(moiRuns.flatMap { [$0.startNanos, $0.endNanos] })).sorted()
        var spans: [ChosenSpan] = []
        for (from, to) in zip(bounds, bounds.dropFirst()) where to > from {
            let covering = moiRuns.filter { $0.startNanos <= from && $0.endNanos >= to }
            guard let best = covering.max(by: { level($0, from, to) < level($1, from, to) }) else { continue }
            if let last = spans.last, last.runID == best.id, last.toNanos == from {
                spans[spans.count - 1] = ChosenSpan(runID: best.id, fromNanos: last.fromNanos, toNanos: to)
            } else {
                spans.append(ChosenSpan(runID: best.id, fromNanos: from, toNanos: to))
            }
        }
        return spans
    }

    /// The median level of a run between two instants; its whole median when no second falls there.
    static func level(_ run: StreamRun, _ from: UInt64, _ to: UInt64) -> Float {
        let inside = run.seconds.filter { $0.nanos > from && $0.nanos <= to }.map(\.rms)
        return median(inside.isEmpty ? run.seconds.map(\.rms) : inside)
    }

    static func median(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
