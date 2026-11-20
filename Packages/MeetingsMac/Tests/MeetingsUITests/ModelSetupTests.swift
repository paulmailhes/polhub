import Foundation
import Testing
import Transcription
@testable import MeetingsUI

/// 20/11 : le modèle de Réunions se télécharge à l'installation quand il manque, et s'efface quand Réunions part.
@MainActor @Suite struct ModelSetupTests {
    func locations(complete: Bool) throws -> ModelLocations {
        let root = FileManager.default.temporaryDirectory.appending(path: "modeles-\(UUID().uuidString)", directoryHint: .isDirectory)
        let locations = ModelLocations(root: root)
        guard complete else { return locations }
        for file in [locations.whisperFolder.appending(path: "AudioEncoder.mlmodelc/x"),
                     locations.tokenizerFolder.appending(path: "models/openai/whisper-large-v3/tokenizer.json"),
                     locations.sileroModel.appending(path: "x")] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: file)
        }
        return locations
    }

    @Test func aModelAlreadyThereDownloadsNothing() async throws {
        let locations = try locations(complete: true)
        defer { try? FileManager.default.removeItem(at: locations.root) }
        // A session that would fail any request: none is made.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = []
        let setup = ModelSetup(locations: locations, download: ModelDownload(session: URLSession(configuration: configuration),
                                                                            host: URL(string: "https://hub.exemple.invalid")!))
        #expect(await setup.prepare() == nil)
    }

    @Test func removingReunionsTakesItsModelAway() throws {
        let locations = try locations(complete: true)
        defer { try? FileManager.default.removeItem(at: locations.root) }
        ModelSetup(locations: locations).remove()
        #expect(locations.missing().count == 3)
    }
}
