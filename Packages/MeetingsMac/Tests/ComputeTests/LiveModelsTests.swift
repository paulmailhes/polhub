import AVFoundation
import Foundation
import Testing
import Transcription

/// The real models, the real `polhub-calcul`, with the network forbidden. Not part of `make check`:
/// `swift build --product polhub-calcul && POLHUB_MODELS=1 swift test --filter LiveModelsTests`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["POLHUB_MODELS"] == "1"))
struct LiveModelsTests {
    static let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures")

    static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'") }).map(String.init)
    }

    /// 2·M / (|a| + |b|), M the longest common subsequence: the measure of the entry measure, to within a hair.
    static func similarity(_ a: [String], _ b: [String]) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 1 }
        var previous = [Int](repeating: 0, count: b.count + 1)
        for x in a {
            var current = [Int](repeating: 0, count: b.count + 1)
            for (j, y) in b.enumerated() {
                current[j + 1] = x == y ? previous[j] + 1 : max(previous[j + 1], current[j])
            }
            previous = current
        }
        return 2 * Double(previous[b.count]) / Double(a.count + b.count)
    }

    /// A meeting folder whose `autres` archive is the 46.7 s synthetic French sample.
    func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "live-\(UUID().uuidString)", directoryHint: .isDirectory)
        let pistes = folder.appending(path: "pistes", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: pistes, withIntermediateDirectories: true)
        let input = try AVAudioFile(forReading: Self.fixtures.appending(path: "echantillon-fr-16k.wav"))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: AVAudioFrameCount(input.length)))
        try input.read(into: buffer)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatAppleLossless, AVSampleRateKey: 16_000.0, AVNumberOfChannelsKey: 1, AVEncoderBitDepthHintKey: 16]
        let output = try AVAudioFile(forWriting: pistes.appending(path: "autres.caf"), settings: settings,
                                     commonFormat: input.processingFormat.commonFormat, interleaved: false)
        try output.write(from: buffer)
        return folder
    }

    @Test func theSampleIsTranscribedOfflineAt0_97() throws {
        let binary = Self.package.appending(path: ".build/debug/polhub-calcul")
        try #require(FileManager.default.isExecutableFile(atPath: binary.path(percentEncoded: false)), "Construire d'abord : swift build --product polhub-calcul")
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let request = String(decoding: try JSONEncoder().encode(CalculRequest(folder: folder.path(percentEncoded: false), language: "fr")), as: UTF8.self)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = ["-p", "(version 1)(allow default)(deny network*)", binary.path(percentEncoded: false), request]
        let output = Pipe()
        process.standardOutput = output
        let began = Date()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let messages = String(decoding: data, as: UTF8.self).split(separator: "\n")
            .compactMap { try? JSONDecoder().decode(CalculMessage.self, from: Data($0.utf8)) }
        print("polhub-calcul : \(String(format: "%.1f", Date().timeIntervalSince(began))) s, sortie \(process.terminationStatus)")
        #expect(process.terminationStatus == 0)
        #expect(messages.last == .finished, "\(messages.last.map { "\($0)" } ?? "aucun message")")

        let text = messages.compactMap { message -> String? in
            if case .chunk(let result) = message { return result.segments.map(\.text).joined(separator: " ") }
            return nil
        }.joined(separator: " ")
        let reference = try String(contentsOf: Self.fixtures.appending(path: "echantillon-fr.txt"), encoding: .utf8)
        let score = Self.similarity(Self.words(reference), Self.words(text))
        print("fidélité : \(String(format: "%.3f", score))")
        #expect(score >= 0.97)
    }
}
