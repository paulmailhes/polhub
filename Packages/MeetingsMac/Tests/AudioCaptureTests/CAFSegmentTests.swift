import AVFoundation
import Foundation
import Testing
@testable import AudioCapture

@Suite struct CAFSegmentTests {
    let mono = PCMFormat(sampleRate: 48_000, channels: 1)

    @Test func rollsSegmentsAtTheConfiguredLength() throws {
        let dir = try temporaryDirectory()
        let w = try CAFSegmentWriter(directory: dir, format: mono, segmentSeconds: 1, syncEverySeconds: 0)
        let source = sine(seconds: 2.5)
        try append(w, source)
        try w.close()
        #expect(w.segmentURLs.map(\.lastPathComponent) == ["000001.caf", "000002.caf", "000003.caf"])
        let read = try w.segmentURLs.map { try CAFReader.read($0) }
        #expect(read.map(\.samples.count) == [48_000, 48_000, 24_000])
        #expect(read.allSatisfy { $0.format == mono })
        #expect(read.flatMap(\.samples) == source)
    }

    @Test func closedSegmentIsReadableByAVAudioFile() throws {
        let dir = try temporaryDirectory()
        let w = try CAFSegmentWriter(directory: dir, format: mono, segmentSeconds: 1, syncEverySeconds: 0)
        try append(w, sine(seconds: 2.5))
        try w.close()
        let file = try AVAudioFile(forReading: w.segmentURLs[2])
        #expect(file.length == 24_000)
        #expect(file.fileFormat.sampleRate == 48_000 && file.fileFormat.channelCount == 1)
    }

    // An interrupted recording: the segment was never closed, its header still says "size unknown".
    @Test func unclosedSegmentKeepsEverySyncedFrame() throws {
        let dir = try temporaryDirectory()
        let w = try CAFSegmentWriter(directory: dir, format: mono, syncEverySeconds: 0)
        let source = sine(seconds: 1.5)
        try append(w, source)
        let read = try CAFReader.read(try #require(try segmentFiles(in: dir).first))
        #expect(read.samples.count == 72_000)
        #expect(read.samples == source)
        try w.close()
    }

    @Test func truncatedLastFrameIsIgnored() throws {
        let dir = try temporaryDirectory()
        let stereo = PCMFormat(sampleRate: 48_000, channels: 2)
        let w = try CAFSegmentWriter(directory: dir, format: stereo, syncEverySeconds: 0)
        try append(w, [Float](repeating: 0.25, count: 2_000))   // 1 000 stereo frames
        try w.close()
        let url = w.segmentURLs[0]
        let size = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: size - 3)
        try handle.close()
        let read = try CAFReader.read(url)
        #expect(read.format == stereo)
        #expect(read.samples.count == 1_998)   // 999 whole frames
    }

    @Test func rejectsAFileThatIsNotCAF() throws {
        let url = try temporaryDirectory().appending(path: "x.caf")
        try Data("pas un fichier audio".utf8).write(to: url)
        #expect(throws: CAFError.self) { _ = try CAFReader.read(url) }
    }
}
