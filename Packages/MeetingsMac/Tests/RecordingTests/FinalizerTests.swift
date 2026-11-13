import AudioCapture
import Domain
import Foundation
import Observability
import Testing
@testable import Recording

@Suite struct FinalizerTests {
    func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "finalize-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func second(_ track: String, device: String?, build: Int, frame: Int64, seconds: Double, rms: Float = 0.02) -> CaptureEngine.SecondRecord {
        CaptureEngine.SecondRecord(
            track: track, device: device, build: build,
            stats: LevelStats(frames: 48_000, exactZeroFrames: 0, rms: rms, peak: rms * 4),
            anchor: TimeAnchor(frameIndex: frame, hostTime: 0, continuousNanos: UInt64(seconds * 1e9)),
            dropped: 0, health: .ok, sourceWasPlaying: true
        )
    }

    func run(_ build: Int, device: String, from: Int, to: Int, rms: Float) -> StreamRun {
        StreamRun(
            track: "moi", device: device, build: build, sampleRate: 48_000, startNanos: UInt64(from) * 1_000_000_000,
            seconds: (from + 1...to).map { SecondSample(nanos: UInt64($0) * 1_000_000_000, rms: rms, peak: rms) }
        )
    }

    @Test func readsRunsAndTheirStartFromTheTimeline() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let trace = try TraceWriter(fileURL: folder.appending(path: "timeline.jsonl"))
        try await trace.write(kind: "mic-start", CaptureEngine.MicStartRecord(
            build: 2, reason: "start", startLatencyMs: 10, deviceUID: "A", format: PCMFormat(sampleRate: 48_000, channels: 1)
        ))
        try await trace.write(kind: "capture", second("moi", device: "A", build: 2, frame: 48_000, seconds: 5))
        try await trace.write(kind: "capture", second("moi", device: "A", build: 2, frame: 96_000, seconds: 6))
        await trace.close()

        let timeline = try MeetingTimeline.read(folder.appending(path: "timeline.jsonl"))
        let read = try #require(timeline.runs.first)
        #expect(timeline.runs.count == 1)
        #expect(read.id == "moi/2" && read.device == "A" && read.sampleRate == 48_000)
        #expect(read.startNanos == 4_000_000_000)
        #expect(read.seconds.map(\.nanos) == [5_000_000_000, 6_000_000_000])
        #expect(read.folderName == "b02-A")
    }

    @Test func theLouderMicrophoneIsKeptWhereTwoOverlap() {
        let spans = MicSourceChooser.choose([run(1, device: "A", from: 0, to: 60, rms: 0.01), run(2, device: "B", from: 20, to: 40, rms: 0.05)])
        #expect(spans == [
            ChosenSpan(runID: "moi/1", fromNanos: 0, toNanos: 20_000_000_000),
            ChosenSpan(runID: "moi/2", fromNanos: 20_000_000_000, toNanos: 40_000_000_000),
            ChosenSpan(runID: "moi/1", fromNanos: 40_000_000_000, toNanos: 60_000_000_000),
        ])
    }

    @Test func aSingleMicrophoneIsKeptWhole() {
        #expect(MicSourceChooser.choose([run(1, device: "A", from: 3, to: 9, rms: 0.01)])
            == [ChosenSpan(runID: "moi/1", fromNanos: 3_000_000_000, toNanos: 9_000_000_000)])
        #expect(MicSourceChooser.choose([]).isEmpty)
    }

    @Test func healthCountsSecondsGapsAndRebuilds() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let trace = try TraceWriter(fileURL: folder.appending(path: "timeline.jsonl"))
        for index in 1...30 {
            try await trace.write(kind: "capture", second("moi", device: "A", build: 1, frame: Int64(index) * 48_000, seconds: Double(index)))
        }
        for index in 1...45 {
            try await trace.write(kind: "capture", second("autres", device: nil, build: 1, frame: Int64(index) * 48_000, seconds: Double(index)))
        }
        for _ in 1...2 {
            try await trace.write(kind: "rebuild", CaptureSupervisor.RebuildRecord(track: "moi", reason: "micRoute", durationMs: 120, ok: true))
        }
        try await trace.write(kind: "gaps", CaptureSupervisor.GapsRecord(
            track: "autres", device: nil, build: 1, sampleRate: 48_000, anchors: 45,
            gaps: [Gap(afterFrame: 96_000, missingSeconds: 0.4)], holeBeforeSeconds: nil
        ))
        await trace.close()

        let health = try MeetingTimeline.read(folder.appending(path: "timeline.jsonl")).health
        #expect(health == MeetingHealth(moiSeconds: 30, autresSeconds: 45, gapCount: 1, rebuilds: 2, selfTestPassed: nil, errors: []))
    }

    @Test func meetingFileIsWrittenAndReadBack() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let trace = try TraceWriter(fileURL: folder.appending(path: "timeline.jsonl"))
        try await trace.write(kind: "capture", second("moi", device: "A", build: 1, frame: 48_000, seconds: 11))
        await trace.close()

        let header = MeetingFile(
            id: UUID(), title: "Point hebdo", meetCode: "abc-defg-hij", mode: .dia,
            startedAt: Date(timeIntervalSince1970: 1_763_026_920), endedAt: Date(timeIntervalSince1970: 1_763_029_440), endReason: "tabClosed"
        )
        let written = try MeetingFinalizer.finalize(folder: folder, header: header)
        #expect(written.originNanos == 10_000_000_000)
        #expect(written.moiSpans == [ChosenSpan(runID: "moi/1", fromNanos: 10_000_000_000, toNanos: 11_000_000_000)])
        let data = try Data(contentsOf: folder.appending(path: "meeting.json"))
        #expect(try MeetingFile.decoder.decode(MeetingFile.self, from: data) == written)
    }
}
