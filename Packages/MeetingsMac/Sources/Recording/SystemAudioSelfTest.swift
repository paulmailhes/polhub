import AudioCapture
import AVFoundation
import CoreAudio
import Foundation
import os

/// Checks the "system audio recording" permission by its effect: this app plays a faint tone, taps its
/// own process, and looks for a sample that is not zero. macOS has no API to ask the question directly,
/// and a missing permission delivers silence without any error.
public enum SystemAudioSelfTest {
    /// -30 dBFS: a faint tone, heard in a headset.
    public static let audibleAmplitude: Float = 0.0316
    /// -90 dBFS: below anything one can hear; the tap still sees samples that are not zero (to be measured).
    public static let inaudibleAmplitude: Float = 0.0000316

    public struct Outcome: Sendable {
        public let result: String
        public let tapDescriptionStatus: Int32?
    }

    /// Blocking. Each round lasts at most two seconds; several rounds leave the person time to answer
    /// the system's question, since a running tap may stay silent until it is rebuilt.
    public static func run(rounds: Int, amplitude: Float = audibleAmplitude) -> Outcome {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1),
              let tone = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 14_400),
              let samples = tone.floatChannelData?[0]
        else { return Outcome(result: "startFailed:format", tapDescriptionStatus: nil) }

        tone.frameLength = 14_400                       // 300 ms, looped while a round lasts
        for index in 0..<14_400 {
            samples[index] = amplitude * Float(sin(2 * .pi * 440 * Double(index) / 48_000))
        }
        engine.attach(player)
        do {
            // macOS 27 names: the throwing forms replace `connect(_:to:format:)` and `play()`.
            try engine.connectNode(player, to: engine.mainMixerNode, format: format)
            try engine.start()
            player.scheduleBuffer(tone, at: nil, options: .loops)
            try player.playAudio()
        } catch {
            engine.stop()
            return Outcome(result: "startFailed:engine", tapDescriptionStatus: nil)
        }
        defer {
            player.stop()
            engine.stop()
        }

        var last = Outcome(result: "allZero", tapDescriptionStatus: nil)
        for round in 0..<max(1, rounds) {
            last = oneRound(startTimeout: round == 0 && rounds > 1 ? .seconds(60) : .seconds(3))
            if last.result == "nonZero" { break }
        }
        return last
    }

    private static func oneRound(startTimeout: Duration) -> Outcome {
        guard let own = try? HAL.processObject(forPID: getpid()) else {
            return Outcome(result: "startFailed:processObject", tapDescriptionStatus: nil)
        }
        let heard = OSAllocatedUnfairLock(initialState: false)
        var tap: ProcessTap?
        var aggregate: TapAggregate?
        var stream: HALInputStream?
        defer {
            // The aggregate and the tap go only once Core Audio has let go of the stream, however late.
            let builtAggregate = aggregate
            let builtTap = tap
            if let stream {
                stream.stop(then: {
                    builtAggregate?.invalidate()
                    builtTap?.invalidate()
                })
            } else {
                builtAggregate?.invalidate()
                builtTap?.invalidate()
            }
        }
        do {
            let builtTap = try ProcessTap(target: .processes([own]), name: "Transcriptor (vérification)")
            tap = builtTap
            let status = builtTap.rewriteDescription()
            let builtAggregate = try TapAggregate(tap: builtTap)
            aggregate = builtAggregate
            let builtStream = try HALInputStream(deviceID: builtAggregate.deviceID) { samples, _, _ in
                // Real-time thread: a plain scan, and a lock that is never contended for long.
                if samples.contains(where: { $0 != 0 }) { heard.withLockUnchecked { $0 = true } }
            }
            stream = builtStream
            try builtStream.start(timeout: startTimeout)

            let deadline = ContinuousClock.now + .seconds(2)
            while ContinuousClock.now < deadline {
                if heard.withLock({ $0 }) { return Outcome(result: "nonZero", tapDescriptionStatus: status) }
                usleep(50_000)
            }
            return Outcome(result: "allZero", tapDescriptionStatus: status)
        } catch let error as HALError {
            return Outcome(result: "startFailed:\(error.status)", tapDescriptionStatus: nil)
        } catch {
            return Outcome(result: "startFailed:\(error)", tapDescriptionStatus: nil)
        }
    }
}
