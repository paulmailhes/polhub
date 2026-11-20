import Foundation

/// A paragraph after each long pause (20/11 in the evening, Paul: « que ça revienne à la ligne … quand on fait des
/// assez longues pauses … pour que ça change de sujet »). The pauses are read in the sound; Whisper writes the whole
/// recording once, in pieces with their times; a paragraph starts at the first piece after each pause.
public enum DictationParagraphs {
    /// A piece of what Whisper wrote, and when it was said, in seconds from the start.
    public struct Piece: Equatable, Sendable {
        public var text: String
        public var start: Double
        public var end: Double

        public init(text: String, start: Double, end: Double) {
            self.text = text
            self.start = start
            self.end = end
        }
    }

    /// Slices of 30 ms.
    static let frame = 0.03

    /// The middle of each silence longer than `minimum` between two moments of voice, in seconds. A silence is quieter
    /// than an eighth of the voice (its loud slices), and than a floor for a silent recording.
    public static func pauses(_ samples: [Float], rate: Double = 16_000, longerThan minimum: Double) -> [Double] {
        let size = Int(rate * frame)
        guard size > 0, samples.count >= size * 2 else { return [] }
        let energies: [Float] = stride(from: 0, through: samples.count - size, by: size).map { start in
            var sum: Float = 0
            for index in start..<(start + size) { sum += samples[index] * samples[index] }
            return (sum / Float(size)).squareRoot()
        }
        let loud = energies.sorted()[Int(Double(energies.count - 1) * 0.9)]
        let threshold = max(0.004, loud * 0.12)
        var pauses: [Double] = []
        var quietSince: Int?
        var heardVoice = false
        for (index, energy) in energies.enumerated() {
            if energy < threshold {
                if quietSince == nil { quietSince = index }
                continue
            }
            if let since = quietSince, heardVoice, Double(index - since) * frame >= minimum {
                pauses.append((Double(since) + Double(index - since) / 2) * frame)
            }
            quietSince = nil
            heardVoice = true
        }
        return pauses
    }

    /// The pieces, a paragraph starting at the first piece whose middle comes after each pause.
    public static func join(_ pieces: [Piece], breaks: [Double]) -> String {
        var pending = breaks.sorted()
        var paragraphs: [[String]] = [[]]
        for piece in pieces {
            let middle = (piece.start + piece.end) / 2
            var crossed = false
            while let next = pending.first, middle >= next {
                pending.removeFirst()
                crossed = true
            }
            if crossed, !(paragraphs.last ?? []).isEmpty { paragraphs.append([]) }
            let text = piece.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { paragraphs[paragraphs.count - 1].append(text) }
        }
        return paragraphs.map { $0.joined(separator: " ") }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

/// « Appuyer, parler, appuyer » finishes alone after a long silence (20/11 in the evening, Paul): when he forgets to
/// press. The level is the helper's (0 to 1, the voice's loudness times eight).
public struct SilenceWatch: Sendable {
    /// Under this, the microphone hears a room, not a voice. To check on Paul's own microphone.
    public static let threshold = 0.06
    public let after: TimeInterval
    private var lastVoice: TimeInterval

    public init(after: TimeInterval, startedAt: TimeInterval) {
        self.after = after
        lastVoice = startedAt
    }

    /// True when it is time to finish.
    public mutating func hear(_ level: Double, at time: TimeInterval) -> Bool {
        if level >= Self.threshold {
            lastVoice = time
            return false
        }
        return time - lastVoice > after
    }

    /// Seconds left before it finishes, if nothing is said.
    public func remaining(at time: TimeInterval) -> TimeInterval {
        max(0, after - (time - lastVoice))
    }
}
