import Foundation
@testable import AudioCapture

func sine(seconds: Double, sampleRate: Double = 48_000, amplitude: Float = 0.5, frequency: Double = 440) -> [Float] {
    (0..<Int(seconds * sampleRate)).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) }
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "polhub-audio-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func append(_ writer: CAFSegmentWriter, _ samples: [Float]) throws {
    try samples.withUnsafeBufferPointer { try writer.append($0) }
}

func segmentFiles(in directory: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "caf" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}
