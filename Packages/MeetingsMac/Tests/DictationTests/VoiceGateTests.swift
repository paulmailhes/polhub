import Foundation
import Testing
@testable import Dictation

/// 21/11 : la voix ou le silence, morceau par morceau. Rien dit, rien écrit ; et l'aide sait quand Paul s'est tu, pour
/// écrire le texte final avant même qu'il appuie.
@Suite struct VoiceGateTests {
    /// 50 ms of a tone at this loudness (its RMS).
    static func piece(_ loudness: Float) -> [Float] {
        (0..<800).map { Float(sin(Double($0) * 0.3)) * loudness * 1.4142 }
    }

    static func hear(_ gate: inout VoiceGate, _ loudness: Float, seconds: Double) {
        for _ in 0..<Int((seconds / 0.05).rounded()) { gate.hear(piece(loudness)) }
    }

    @Test func aSilentRoomIsNotAVoice() {
        var gate = VoiceGate()
        Self.hear(&gate, 0.0008, seconds: 3)
        #expect(!gate.heardVoice && gate.voicedSeconds == 0)
        #expect(abs(gate.silence - 3) < 0.01)
    }

    @Test func aVoiceThenASilenceIsMeasured() {
        var gate = VoiceGate()
        Self.hear(&gate, 0.001, seconds: 0.5)
        Self.hear(&gate, 0.12, seconds: 2)
        #expect(gate.heardVoice && abs(gate.voicedSeconds - 2) < 0.01 && gate.silence == 0)
        Self.hear(&gate, 0.001, seconds: 0.6)
        #expect(abs(gate.silence - 0.6) < 0.01)
    }

    @Test func aSoftLastWordIsStillAVoice() {
        var gate = VoiceGate()
        Self.hear(&gate, 0.15, seconds: 2)
        Self.hear(&gate, 0.001, seconds: 0.5)
        // Ten times softer than the sentence: still above the share of the loudest voice.
        Self.hear(&gate, 0.015, seconds: 0.3)
        #expect(gate.silence == 0)
    }

    @Test func nothingSinceAMarkMeansTheSameSilence() {
        var gate = VoiceGate()
        Self.hear(&gate, 0.12, seconds: 2)
        Self.hear(&gate, 0.001, seconds: 0.5)
        let mark = gate.mark
        Self.hear(&gate, 0.0012, seconds: 1)
        #expect(gate.nothingSince(mark))
        // A noise under the voice's threshold, but well above the silence: not the same silence.
        Self.hear(&gate, 0.005, seconds: 0.1)
        #expect(!gate.nothingSince(mark))
    }

    @Test func aVoiceAfterTheMarkIsSeen() {
        var gate = VoiceGate()
        Self.hear(&gate, 0.12, seconds: 1)
        Self.hear(&gate, 0.001, seconds: 0.5)
        let mark = gate.mark
        Self.hear(&gate, 0.1, seconds: 0.2)
        #expect(!gate.nothingSince(mark))
    }
}
