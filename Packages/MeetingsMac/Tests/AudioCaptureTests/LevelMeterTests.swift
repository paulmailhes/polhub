import Testing
@testable import AudioCapture

@Suite struct LevelMeterTests {
    func stats(_ samples: [Float], channels: Int = 1) -> LevelStats {
        var meter = LevelMeter(channels: channels)
        samples.withUnsafeBufferPointer { meter.add($0) }
        return meter.flush()
    }

    @Test func meterMeasuresASine() {
        let s = stats(sine(seconds: 1, amplitude: 0.5))
        #expect(s.frames == 48_000)
        #expect(abs(s.rms - 0.3536) < 0.001)
        #expect(abs(s.peak - 0.5) < 0.001)
        #expect(s.exactZeroFrames <= 2)
    }

    @Test func meterCountsFramesWhereEveryChannelIsExactlyZero() {
        let s = stats([0, 0, 0, 0.5, 0, 0, 0.5, 0], channels: 2)
        #expect(s.frames == 4)
        #expect(s.exactZeroFrames == 2)
    }

    @Test func flushResetsTheMeter() {
        var meter = LevelMeter(channels: 1)
        [Float](repeating: 0.5, count: 10).withUnsafeBufferPointer { meter.add($0) }
        _ = meter.flush()
        #expect(meter.flush() == LevelStats(frames: 0, exactZeroFrames: 0, rms: 0, peak: 0))
    }

    // Review Focus 1 : des zéros alors que le son joue, c'est une panne, pas une mesure.
    @Test func silentWhileAudibleIsFlagged() {
        let zeros = LevelStats(frames: 48_000, exactZeroFrames: 48_000, rms: 0, peak: 0)
        #expect(CaptureHealth.verdict(zeros, sourceWasPlaying: true) == .silentWhileAudible)
        #expect(CaptureHealth.verdict(zeros, sourceWasPlaying: false) == .silent)
        #expect(CaptureHealth.verdict(LevelStats(frames: 48_000, exactZeroFrames: 0, rms: 0.1, peak: 0.3), sourceWasPlaying: true) == .ok)
        let nothing = LevelStats(frames: 0, exactZeroFrames: 0, rms: 0, peak: 0)
        #expect(CaptureHealth.verdict(nothing, sourceWasPlaying: true) == .silentWhileAudible)
    }
}
