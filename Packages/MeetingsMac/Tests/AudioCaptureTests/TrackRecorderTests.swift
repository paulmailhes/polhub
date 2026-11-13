import Foundation
import os
import Testing
@testable import AudioCapture

@Suite struct TrackRecorderTests {
    let mono = PCMFormat(sampleRate: 48_000, channels: 1)

    /// Feeds synthetic buffers the way the audio callback would, without any hardware.
    func feed(_ recorder: TrackRecorder, _ samples: [Float], bufferFrames: Int = 512, startHostTime: UInt64 = 1_000) {
        var offset = 0
        var hostTime = startHostTime
        samples.withUnsafeBufferPointer { all in
            while offset < all.count {
                let count = min(bufferFrames, all.count - offset)
                recorder.ingest(UnsafeBufferPointer(rebasing: all[offset..<offset + count]), frames: count, hostTime: hostTime)
                offset += count
                hostTime += UInt64(count)
            }
        }
    }

    func totalFrames(in directory: URL) throws -> Int {
        try segmentFiles(in: directory).reduce(0) { try $0 + CAFReader.read($1).samples.count }
    }

    @Test func recordsEveryIngestedFrame() throws {
        let dir = try temporaryDirectory()
        let seen = OSAllocatedUnfairLock<[(LevelStats, TimeAnchor, Int)]>(initialState: [])
        let recorder = try TrackRecorder(directory: dir, format: mono, segmentSeconds: 1, ringSeconds: 4) { stats, anchor, dropped in
            seen.withLock { $0.append((stats, anchor, dropped)) }
        }
        let source = sine(seconds: 3)
        feed(recorder, source)
        try recorder.finish()

        #expect(try totalFrames(in: dir) == 144_000)
        #expect(try segmentFiles(in: dir).flatMap { try CAFReader.read($0).samples } == source)
        let calls = seen.withLock { $0 }
        #expect(calls.map(\.0.frames) == [48_000, 48_000, 48_000])
        #expect(calls.allSatisfy { $0.0.exactZeroFrames <= 2 && $0.2 == 0 })
        #expect(calls.map(\.1.frameIndex) == calls.map(\.1.frameIndex).sorted())
        #expect(calls.allSatisfy { $0.1.continuousNanos > 0 })
    }

    @Test func reportsExactZerosPerSecond() throws {
        let dir = try temporaryDirectory()
        let seen = OSAllocatedUnfairLock<[LevelStats]>(initialState: [])
        let recorder = try TrackRecorder(directory: dir, format: mono, ringSeconds: 4) { stats, _, _ in
            seen.withLock { $0.append(stats) }
        }
        feed(recorder, [Float](repeating: 0, count: 48_000))
        try recorder.finish()
        #expect(seen.withLock { $0 } == [LevelStats(frames: 48_000, exactZeroFrames: 48_000, rms: 0, peak: 0)])
    }

    @Test func reportsTheLastPartialSecondAndTheDroppedFrames() throws {
        let dir = try temporaryDirectory()
        let seen = OSAllocatedUnfairLock<[(LevelStats, Int)]>(initialState: [])
        // A ring of a quarter second, fed a whole second at once: the reader cannot keep up.
        let recorder = try TrackRecorder(directory: dir, format: mono, ringSeconds: 0.25) { stats, _, dropped in
            seen.withLock { $0.append((stats, dropped)) }
        }
        feed(recorder, sine(seconds: 1), bufferFrames: 48_000)
        try recorder.finish()
        let calls = seen.withLock { $0 }
        #expect(calls.map(\.0.frames).reduce(0, +) == 12_000)
        #expect(calls.map(\.1).reduce(0, +) == 36_000)
        #expect(try totalFrames(in: dir) == 12_000)
    }

    @Test func anchorsCarryTheHostTimeOfTheBufferTheyDescribe() throws {
        let dir = try temporaryDirectory()
        let seen = OSAllocatedUnfairLock<[TimeAnchor]>(initialState: [])
        let recorder = try TrackRecorder(directory: dir, format: mono, ringSeconds: 4) { _, anchor, _ in
            seen.withLock { $0.append(anchor) }
        }
        feed(recorder, sine(seconds: 1), bufferFrames: 480, startHostTime: 5_000)
        try recorder.finish()
        let anchor = try #require(seen.withLock { $0 }.last)
        // feed() advances hostTime by one unit per frame: hostTime - 5 000 is the buffer's first frame.
        #expect(Int64(anchor.hostTime) - 5_000 == anchor.frameIndex)
    }
}

@Suite struct TrackRecorderGuardTests {
    // A buffer that holds fewer samples than `frames × channels` must never be read past its end.
    @Test func ingestNeverReadsPastTheBufferItWasGiven() throws {
        let dir = try temporaryDirectory()
        let stereo = PCMFormat(sampleRate: 48_000, channels: 2)
        let recorder = try TrackRecorder(directory: dir, format: stereo, ringSeconds: 1) { _, _, _ in }
        let memory = [Float](repeating: 0.5, count: 400)
        memory.withUnsafeBufferPointer { all in
            // 100 samples are 50 stereo frames, whatever the caller claims.
            recorder.ingest(UnsafeBufferPointer(rebasing: all[0..<100]), frames: 100, hostTime: 1)
        }
        try recorder.finish()
        let samples = try segmentFiles(in: dir).flatMap { try CAFReader.read($0).samples }
        #expect(samples.count == 100)
    }

    // The audio thread and the writer thread at real pace: 10 ms buffers for 1.2 s.
    @Test func keepsEveryFrameAtRealPace() async throws {
        let dir = try temporaryDirectory()
        let mono = PCMFormat(sampleRate: 48_000, channels: 1)
        let seen = OSAllocatedUnfairLock<[(LevelStats, TimeAnchor, Int)]>(initialState: [])
        let recorder = try TrackRecorder(directory: dir, format: mono) { stats, anchor, dropped in
            seen.withLock { $0.append((stats, anchor, dropped)) }
        }
        let source = sine(seconds: 1.2)
        await Task.detached {
            source.withUnsafeBufferPointer { all in
                var offset = 0
                while offset < all.count {
                    recorder.ingest(UnsafeBufferPointer(rebasing: all[offset..<offset + 480]), frames: 480, hostTime: UInt64(offset))
                    offset += 480
                    usleep(10_000)
                }
            }
        }.value
        try recorder.finish()
        #expect(try segmentFiles(in: dir).flatMap { try CAFReader.read($0).samples } == source)
        let calls = seen.withLock { $0 }
        #expect(calls.map(\.0.frames).reduce(0, +) == 57_600)
        #expect(calls.allSatisfy { $0.2 == 0 && Int64($0.1.hostTime) == $0.1.frameIndex })
    }
}

@Suite struct TrackRecorderFailureTests {
    final class Box: @unchecked Sendable {
        let lock = NSLock()
        var error: Error?
        func set(_ value: Error) { lock.lock(); error = error ?? value; lock.unlock() }
        var value: Error? { lock.lock(); defer { lock.unlock() }; return error }
    }

    // Revue finale, Important 2 : une erreur d'écriture se dit quand elle arrive, pas à l'arrêt.
    @Test func aWriteErrorIsReportedWhenItHappens() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "rofs-\(UUID().uuidString)", directoryHint: .isDirectory)
        let box = Box()
        let recorder = try TrackRecorder(
            directory: directory, format: PCMFormat(sampleRate: 48_000, channels: 1), segmentSeconds: 0.01,
            onWriteError: { box.set($0) }, onSecond: { _, _, _ in }
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let samples = [Float](repeating: 0.1, count: 4_800)
        samples.withUnsafeBufferPointer { recorder.ingest($0, frames: 4_800, hostTime: 0) }
        for _ in 0..<40 where box.value == nil { try await Task.sleep(for: .milliseconds(25)) }
        #expect(box.value != nil)
        _ = try? recorder.finish()
    }

    @Test func nonFiniteLevelsAreWrittenAsZero() {
        let stats = LevelStats(frames: 10, exactZeroFrames: 0, rms: .nan, peak: .infinity).finite
        #expect(stats == LevelStats(frames: 10, exactZeroFrames: 0, rms: 0, peak: 0))
    }
}
