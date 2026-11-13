import AudioCapture
import Foundation
import Testing
@testable import Recording

/// Three one-second segments per stream, starting two seconds after the origin.
func writeSegments(in folder: URL, path: String, seconds: Int = 3) throws {
    let writer = try CAFSegmentWriter(
        directory: folder.appending(path: path, directoryHint: .isDirectory),
        format: PCMFormat(sampleRate: 48_000, channels: 1), segmentSeconds: 1
    )
    let samples = [Float](repeating: 0.1, count: 48_000 * seconds)
    try samples.withUnsafeBufferPointer { try writer.append($0) }
    try writer.close()
}

func timeline(moiDevice: String = "A") -> MeetingTimeline {
    func run(_ track: String, _ device: String?) -> StreamRun {
        StreamRun(track: track, device: device, build: 1, sampleRate: 48_000, startNanos: 2_000_000_000,
                  seconds: (3...5).map { SecondSample(nanos: UInt64($0) * 1_000_000_000, rms: 0.1, peak: 0.1) })
    }
    return MeetingTimeline(runs: [run("autres", nil), run("moi", moiDevice)], rebuilds: 0, selfTestPassed: nil, errors: [],
                           secondsByTrack: [:], gapCount: 0)
}

@Suite struct PlaybackPlanTests {
    @Test func piecesFollowSegmentsAndSpans() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "playback-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try writeSegments(in: folder, path: "audio/autres/b01")
        try writeSegments(in: folder, path: "audio/moi/b01-A")

        let pieces = PlaybackPlan.pieces(
            folder: folder, timeline: timeline(),
            moiSpans: [ChosenSpan(runID: "moi/1", fromNanos: 2_500_000_000, toNanos: 3_500_000_000)],
            originNanos: 0, segmentSeconds: 1
        )
        let others = pieces.filter { $0.track == "autres" }
        #expect(others.map(\.atSeconds) == [2, 3, 4])
        #expect(others.allSatisfy { abs($0.durationSeconds - 1) < 0.001 && $0.fromSeconds == 0 })
        let mine = pieces.filter { $0.track == "moi" }
        #expect(mine.count == 2)
        #expect(mine.map(\.atSeconds) == [2.5, 3])
        #expect(mine.map(\.fromSeconds) == [0.5, 0])
        #expect(mine.allSatisfy { abs($0.durationSeconds - 0.5) < 0.001 })
        #expect(mine.first?.url.lastPathComponent == "000001.caf")
    }

    // Revue finale, mineur relevé : les 10 minutes de sécurité ne se rejouent pas.
    @Test func piecesStopAtTheEndOfTheMeeting() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "playback-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try writeSegments(in: folder, path: "audio/autres/b01")
        try writeSegments(in: folder, path: "audio/moi/b01-A")
        let pieces = PlaybackPlan.pieces(
            folder: folder, timeline: timeline(), moiSpans: [], originNanos: 0, segmentSeconds: 1, untilNanos: 3_500_000_000
        ).filter { $0.track == "autres" }
        #expect(pieces.map(\.atSeconds) == [2, 3])
        #expect(pieces.map { ($0.durationSeconds * 1_000).rounded() / 1_000 } == [1, 0.5])
    }
}
