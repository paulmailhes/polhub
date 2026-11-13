import Testing
@testable import AudioCapture

@Suite struct GapMeterTests {
    func anchor(_ frame: Int64, seconds: Double) -> TimeAnchor {
        TimeAnchor(frameIndex: frame, hostTime: 0, continuousNanos: UInt64(seconds * 1e9))
    }

    @Test func contiguousAnchorsHaveNoGap() {
        let anchors = (0...5).map { anchor(Int64($0) * 48_000, seconds: Double($0)) }
        #expect(GapMeter.gaps(anchors: anchors, sampleRate: 48_000).isEmpty)
    }

    @Test func missingAudioIsOneGap() {
        let g = GapMeter.gaps(anchors: [anchor(0, seconds: 0), anchor(48_000, seconds: 1), anchor(96_000, seconds: 4)], sampleRate: 48_000)
        #expect(g.count == 1)
        #expect(g.first?.afterFrame == 48_000)
        #expect(abs((g.first?.missingSeconds ?? 0) - 2.0) < 0.01)
    }

    // Review Focus 4 : pendant la veille l'horloge du son s'arrête, pas l'horloge continue.
    @Test func sleepJumpIsOneGap() {
        let g = GapMeter.gaps(anchors: [anchor(0, seconds: 0), anchor(48_000, seconds: 11)], sampleRate: 48_000)
        #expect(g.count == 1)
        #expect(abs((g.first?.missingSeconds ?? 0) - 10.0) < 0.01)
    }

    // Review Focus 4 : des repères dans le désordre ne font ni planter ni inventer un trou.
    @Test func outOfOrderAnchorsAreIgnored() {
        #expect(GapMeter.gaps(anchors: [anchor(48_000, seconds: 1), anchor(0, seconds: 0)], sampleRate: 48_000).isEmpty)
        #expect(GapMeter.gaps(anchors: [], sampleRate: 48_000).isEmpty)
        #expect(GapMeter.gaps(anchors: [anchor(0, seconds: 0)], sampleRate: 48_000).isEmpty)
    }

    @Test func jitterBelowTheToleranceIsNotAGap() {
        let anchors = [anchor(0, seconds: 0), anchor(48_000, seconds: 1.03), anchor(96_000, seconds: 2.0)]
        #expect(GapMeter.gaps(anchors: anchors, sampleRate: 48_000).isEmpty)
    }
}

@Suite struct RouteMonitorTests {
    @Test func ourOwnAggregatesNeverCountAsADeviceChange() {
        let own = TapAggregate.uidPrefix + "ABC"
        #expect(RouteMonitor.deviceListChange(from: ["a"], to: ["a", own]) == nil)
        #expect(RouteMonitor.deviceListChange(from: ["a", own], to: ["a"]) == nil)
        #expect(RouteMonitor.deviceListChange(from: ["a"], to: ["a"]) == nil)
        #expect(RouteMonitor.deviceListChange(from: ["a", "b"], to: ["a", "c", own]) == "+c -b")
        #expect(RouteMonitor.deviceListChange(from: [], to: ["z", "y"]) == "+y +z")
    }
}
