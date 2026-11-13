import AudioCapture
import AVFoundation
import Foundation
import Testing
@testable import MeetingsUI
@testable import Recording

@MainActor @Suite struct MeetingPlayerTests {
    @Test func thePlayerPlacesEachPieceAtItsTime() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "player-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let format = PCMFormat(sampleRate: 48_000, channels: 1)
        for path in ["audio/autres/b01", "audio/moi/b01-A"] {
            let writer = try CAFSegmentWriter(directory: folder.appending(path: path, directoryHint: .isDirectory), format: format, segmentSeconds: 1)
            try [Float](repeating: 0.1, count: 48_000 * 3).withUnsafeBufferPointer { try writer.append($0) }
            try writer.close()
        }
        let pieces = [
            PlaybackPiece(url: folder.appending(path: "audio/autres/b01/000001.caf"), track: "autres", atSeconds: 2, fromSeconds: 0, durationSeconds: 1),
            PlaybackPiece(url: folder.appending(path: "audio/autres/b01/000003.caf"), track: "autres", atSeconds: 4, fromSeconds: 0, durationSeconds: 1),
            PlaybackPiece(url: folder.appending(path: "audio/moi/b01-A/000001.caf"), track: "moi", atSeconds: 2.5, fromSeconds: 0.5, durationSeconds: 0.5),
        ]
        let player = try await MeetingPlayer(pieces: pieces)
        #expect(abs(player.durationSeconds - 5) < 0.01)
        let starts = player.segmentStarts()
        #expect(starts["autres"]?.map { ($0 * 100).rounded() / 100 } == [2, 4])
        #expect(starts["moi"]?.map { ($0 * 100).rounded() / 100 } == [2.5])
    }
}
