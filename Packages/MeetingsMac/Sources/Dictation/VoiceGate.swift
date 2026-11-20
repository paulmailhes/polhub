import Foundation

/// A voice or a silence, piece of sound after piece of sound (21/11). The helper uses it for two things: to write nothing
/// when Paul said nothing (Whisper invents « Merci. » in a silence), and to start writing the final text as soon as he
/// stops talking, before he presses the key.
///
/// A piece holds a voice when it is louder than a floor and than a share of the loudest voice heard, which is slowly
/// forgotten. Both are low on purpose: a soft last word must count as a voice.
public struct VoiceGate: Sendable {
    /// Under this, the microphone gives its own noise.
    public static let floor: Float = 0.002
    /// The share of the loudest voice a piece must reach.
    public static let share: Float = 0.06
    /// What the loudest voice keeps from one piece to the next: half forgotten after about seven seconds of 50 ms pieces.
    static let memory: Float = 0.995

    public let rate: Double
    /// Samples heard so far.
    public private(set) var samples = 0
    /// The sample after the last piece that held a voice.
    public private(set) var voiceEnd = 0
    /// Samples that held a voice.
    public private(set) var voiced = 0
    private var loud: Float = 0
    /// The loudest piece since the last voice: how quiet the silence is.
    private var quietPeak: Float = 0

    public init(rate: Double = 16_000) {
        self.rate = rate
    }

    public var heardVoice: Bool { voiced > 0 }
    /// Seconds of voice so far.
    public var voicedSeconds: Double { Double(voiced) / rate }
    /// Seconds since the last voice.
    public var silence: Double { Double(samples - voiceEnd) / rate }

    public static func loudness(_ piece: [Float]) -> Float {
        guard !piece.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in piece { sum += sample * sample }
        return (sum / Float(piece.count)).squareRoot()
    }

    /// True when the piece holds a voice.
    @discardableResult
    public mutating func hear(_ piece: [Float]) -> Bool {
        guard !piece.isEmpty else { return false }
        let level = Self.loudness(piece)
        samples += piece.count
        loud = max(loud * Self.memory, level)
        guard level > max(Self.floor, loud * Self.share) else {
            quietPeak = max(quietPeak, level)
            return false
        }
        voiceEnd = samples
        voiced += piece.count
        quietPeak = 0
        return true
    }

    /// A mark of where the listening is, to ask later whether a voice came after it.
    public struct Mark: Sendable, Equatable {
        public let samples: Int
        /// How loud the silence was when the mark was taken.
        public let quiet: Float
    }

    public var mark: Mark { Mark(samples: samples, quiet: quietPeak) }

    /// True when nothing but the same silence came after the mark: no voice, and nothing twice as loud as the silence was.
    public func nothingSince(_ mark: Mark) -> Bool {
        voiceEnd <= mark.samples && quietPeak <= max(Self.floor, mark.quiet * 2)
    }
}
