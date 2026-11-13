import AVFoundation
import AudioCapture
import Domain
import Foundation
import Testing
@testable import Recording

@Suite struct TrackRendererTests {
    func folder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "render \(UUID().uuidString)", directoryHint: .isDirectory)
    }

    func run(_ track: String, _ device: String?, build: Int = 1, from: Int, seconds: Int = 3) -> StreamRun {
        StreamRun(track: track, device: device, build: build, sampleRate: 48_000, startNanos: UInt64(from) * 1_000_000_000,
                  seconds: (from + 1...from + seconds).map { SecondSample(nanos: UInt64($0) * 1_000_000_000, rms: 0.1, peak: 0.1) })
    }

    func file(endSeconds: Double, moiSpans: [ChosenSpan]) -> MeetingFile {
        var file = MeetingFile(id: UUID(), title: "Essai", meetCode: nil, mode: .dia, startedAt: Date(), endedAt: Date(), endReason: nil)
        file.originNanos = 0
        file.endNanos = UInt64(endSeconds * 1e9)
        file.moiSpans = moiSpans
        return file
    }

    /// The level of the archive around `second`, read back from the file.
    func level(_ url: URL, at second: Double) throws -> Float {
        let audio = try AVAudioFile(forReading: url)
        audio.framePosition = AVAudioFramePosition(second * audio.fileFormat.sampleRate)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 1_600))
        try audio.read(into: buffer, frameCount: 1_600)
        let samples = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
        return samples.reduce(0) { $0 + abs($1) } / Float(max(1, samples.count))
    }

    func seconds(_ url: URL) throws -> Double {
        let audio = try AVAudioFile(forReading: url)
        return Double(audio.length) / audio.fileFormat.sampleRate
    }

    @Test func renderedTracksStartAtTheOriginAndFillGapsWithSilence() throws {
        let folder = folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try writeSegments(in: folder, path: "audio/autres/b01")
        try writeSegments(in: folder, path: "audio/autres/b02")
        try writeSegments(in: folder, path: "audio/moi/b01-A")
        let timeline = MeetingTimeline(runs: [run("autres", nil, from: 2), run("autres", nil, build: 2, from: 7), run("moi", "A", from: 2)],
                                       rebuilds: 1, selfTestPassed: nil, errors: [], secondsByTrack: [:], gapCount: 1)
        let tracks = try TrackRenderer.render(
            folder: folder, file: file(endSeconds: 10, moiSpans: [ChosenSpan(runID: "moi/1", fromNanos: 2_000_000_000, toNanos: 5_000_000_000)]),
            timeline: timeline, segmentSeconds: 1
        )
        #expect(tracks.autres.path().hasSuffix("pistes/autres.caf"))
        #expect(abs(try seconds(tracks.autres) - 10) < 0.05)
        #expect(try level(tracks.autres, at: 1) < 0.005)
        #expect(abs(try level(tracks.autres, at: 3.5) - 0.1) < 0.02)
        #expect(try level(tracks.autres, at: 6) < 0.005)
        #expect(abs(try level(tracks.autres, at: 8.5) - 0.1) < 0.02)
        let moi = try #require(tracks.moi)
        #expect(abs(try level(moi, at: 3.5) - 0.1) < 0.02)
        #expect(try level(moi, at: 8.5) < 0.005)
        let format = try AVAudioFile(forReading: tracks.autres).fileFormat
        #expect(format.sampleRate == 16_000 && format.channelCount == 1)
        #expect(format.streamDescription.pointee.mFormatID == kAudioFormatAppleLossless)
    }

    @Test func theSafetyTimeAfterTheEndIsNotArchived() throws {
        let folder = folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try writeSegments(in: folder, path: "audio/autres/b01")
        let timeline = MeetingTimeline(runs: [run("autres", nil, from: 2)], rebuilds: 0, selfTestPassed: nil, errors: [], secondsByTrack: [:], gapCount: 0)
        let tracks = try TrackRenderer.render(folder: folder, file: file(endSeconds: 3.5, moiSpans: []), timeline: timeline, segmentSeconds: 1)
        #expect(abs(try seconds(tracks.autres) - 3.5) < 0.05)
    }

    @Test func aMeetingWithoutMicrophoneHasNoMoiTrack() throws {
        let folder = folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try writeSegments(in: folder, path: "audio/autres/b01")
        let timeline = MeetingTimeline(runs: [run("autres", nil, from: 0)], rebuilds: 0, selfTestPassed: nil, errors: [], secondsByTrack: [:], gapCount: 0)
        let tracks = try TrackRenderer.render(folder: folder, file: file(endSeconds: 3, moiSpans: []), timeline: timeline, segmentSeconds: 1)
        #expect(tracks.moi == nil)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "pistes/moi.caf").path(percentEncoded: false)))
        #expect(TrackRenderer.prepared(in: folder)?.moi == nil)
    }

    @Test func verifyRejectsATrackShorterByMoreThanOneSecond() throws {
        let folder = folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try writeSegments(in: folder, path: "audio/autres/b01")
        let timeline = MeetingTimeline(runs: [run("autres", nil, from: 0)], rebuilds: 0, selfTestPassed: nil, errors: [], secondsByTrack: [:], gapCount: 0)
        let tracks = try TrackRenderer.render(folder: folder, file: file(endSeconds: 3, moiSpans: []), timeline: timeline, segmentSeconds: 1)
        #expect(TrackRenderer.verify(tracks, expectedSeconds: 3.5))
        #expect(!TrackRenderer.verify(tracks, expectedSeconds: 4.5))
    }

    @Test func playbackUsesTheArchiveOnceItExists() throws {
        let folder = folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try writeSegments(in: folder, path: "audio/autres/b01")
        try writeSegments(in: folder, path: "audio/moi/b01-A")
        let timeline = MeetingTimeline(runs: [run("autres", nil, from: 0), run("moi", "A", from: 0)], rebuilds: 0, selfTestPassed: nil,
                                       errors: [], secondsByTrack: [:], gapCount: 0)
        _ = try TrackRenderer.render(
            folder: folder, file: file(endSeconds: 3, moiSpans: [ChosenSpan(runID: "moi/1", fromNanos: 0, toNanos: 3_000_000_000)]),
            timeline: timeline, segmentSeconds: 1
        )
        let pieces = PlaybackPlan.pieces(folder: folder, timeline: timeline, moiSpans: [], originNanos: 0, segmentSeconds: 1, untilNanos: 2_000_000_000)
        #expect(pieces.count == 2)
        #expect(pieces.allSatisfy { $0.url.path().contains("/pistes/") && $0.atSeconds == 0 && $0.fromSeconds == 0 })
        #expect(pieces.allSatisfy { abs($0.durationSeconds - 2) < 0.01 })
    }

    // Revue finale, Important 3 : le brut n'est effacé que si chaque morceau est passé dans l'archive.
    @Test func rawAudioCountsAsArchivedOnlyIfEveryFileWasPlaced() throws {
        let folder = folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try writeSegments(in: folder, path: "audio/autres/b01")
        try writeSegments(in: folder, path: "audio/autres/b02")
        try writeSegments(in: folder, path: "audio/moi/b01-A")
        let full = MeetingTimeline(runs: [run("autres", nil, from: 2), run("autres", nil, build: 2, from: 7), run("moi", "A", from: 2)],
                                   rebuilds: 1, selfTestPassed: nil, errors: [], secondsByTrack: [:], gapCount: 1)
        let meeting = file(endSeconds: 10, moiSpans: [ChosenSpan(runID: "moi/1", fromNanos: 2_000_000_000, toNanos: 5_000_000_000)])
        _ = try TrackRenderer.render(folder: folder, file: meeting, timeline: full, segmentSeconds: 1)
        #expect(TrackRenderer.rawAudioIsArchived(folder: folder, file: meeting, timeline: full, segmentSeconds: 1))

        // The timeline forgot the second run of `autres`: its audio is on disk but not in the archive.
        let partial = MeetingTimeline(runs: [run("autres", nil, from: 2), run("moi", "A", from: 2)],
                                      rebuilds: 0, selfTestPassed: nil, errors: [], secondsByTrack: [:], gapCount: 0)
        _ = try TrackRenderer.render(folder: folder, file: meeting, timeline: partial, segmentSeconds: 1)
        #expect(!TrackRenderer.rawAudioIsArchived(folder: folder, file: meeting, timeline: partial, segmentSeconds: 1))
    }
}
