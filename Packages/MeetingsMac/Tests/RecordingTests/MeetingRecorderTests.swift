import Foundation
import Testing
@testable import Recording

@Suite struct MeetingRecorderTests {
    func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "meeting-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // Review Focus 1 : après un plantage, la réunion continue dans son dossier sans rien écraser.
    @Test func resumingInAFolderContinuesTheBuildNumbers() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for path in ["audio/moi/b01-casque-input", "audio/autres/b02"] {
            try FileManager.default.createDirectory(at: folder.appending(path: path), withIntermediateDirectories: true)
        }
        #expect(MeetingRecorder.firstBuilds(in: folder) == [.moi: 2, .autres: 3])
        #expect(MeetingRecorder.firstBuilds(in: folder.appending(path: "vide")) == [.moi: 1, .autres: 1])
    }

    // « Pas cette fois » : le pré-enregistrement est détruit.
    @Test func discardRemovesTheWholeFolder() async throws {
        let folder = try temporaryFolder()
        let recorder = try MeetingRecorder(folder: folder, mode: .dia, selfTestAmplitude: nil)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "timeline.jsonl").path))
        await recorder.discard()
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }
}
