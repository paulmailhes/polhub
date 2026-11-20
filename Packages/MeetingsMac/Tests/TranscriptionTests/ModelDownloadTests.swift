import CryptoKit
import Foundation
import Testing
@testable import Transcription

/// 20/11 : un nouvel utilisateur qui installe Réunions télécharge le modèle depuis Hugging Face, à une révision fixée,
/// chaque fichier vérifié par son empreinte ; un fichier abîmé n'installe rien. Aucun réseau ici : un faux serveur.
@Suite(.serialized) struct ModelDownloadTests {
    /// A fake Hugging Face, served to the session of the tests.
    final class FakeHub: URLProtocol {
        nonisolated(unsafe) static var answers: [String: Data] = [:]

        override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "hub.exemple" }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let url = request.url!
            let key = url.path + (url.query.map { "?" + $0 } ?? "")
            let data = Self.answers[key]
            let response = HTTPURLResponse(url: url, statusCode: data == nil ? 404 : 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data { client?.urlProtocol(self, didLoad: data) }
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    static let big = Data((0..<4_000).map { UInt8($0 % 251) })
    static let small = Data(#"{"nom":"essai"}"#.utf8)

    static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func gitSHA1(_ data: Data) -> String {
        Insecure.SHA1.hash(data: Data("blob \(data.count)\0".utf8) + data).map { String(format: "%02x", $0) }.joined()
    }

    func world(corrupt: Bool = false) throws -> (ModelDownload, ModelSource, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "modeles-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let tree: [[String: Any]] = [
            ["type": "directory", "path": "modele/Encodeur.mlmodelc", "oid": "0"],
            ["type": "file", "path": "modele/Encodeur.mlmodelc/poids.bin", "size": 134, "oid": "x",
             "lfs": ["oid": Self.sha256(Self.big), "size": Self.big.count]],
            ["type": "file", "path": "modele/config.json", "size": Self.small.count, "oid": Self.gitSHA1(Self.small)],
        ]
        FakeHub.answers = [
            "/api/models/exemple/modeles/tree/abc123/modele?recursive=true": try JSONSerialization.data(withJSONObject: tree),
            "/exemple/modeles/resolve/abc123/modele/Encodeur.mlmodelc/poids.bin": corrupt ? Self.big.dropLast() + Data([0]) : Self.big,
            "/exemple/modeles/resolve/abc123/modele/config.json": Self.small,
        ]
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeHub.self]
        let download = ModelDownload(session: URLSession(configuration: configuration), host: URL(string: "https://hub.exemple")!)
        let source = ModelSource(repo: "exemple/modeles", revision: "abc123", folder: "modele", include: { _ in true },
                                 destination: root.appending(path: "installe", directoryHint: .isDirectory))
        return (download, source, root)
    }

    @Test func theTreeGivesTheFilesOfTheFolder() async throws {
        let (download, source, root) = try world()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = try await download.files(source)
        #expect(files.map(\.path) == ["Encodeur.mlmodelc/poids.bin", "config.json"])
        #expect(files[0].sha256 == Self.sha256(Self.big) && files[0].size == Int64(Self.big.count))
        #expect(files[1].gitSHA1 == Self.gitSHA1(Self.small) && files[1].sha256 == nil)
    }

    @Test func aGoodDownloadReplacesTheFolder() async throws {
        let (download, source, root) = try world()
        defer { try? FileManager.default.removeItem(at: root) }
        try await download.install([source]) { _, _ in }
        #expect(try Data(contentsOf: source.destination.appending(path: "Encodeur.mlmodelc/poids.bin")) == Self.big)
        #expect(try Data(contentsOf: source.destination.appending(path: "config.json")) == Self.small)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false)) == ["installe"])
    }

    @Test func aCorruptFileInstallsNothing() async throws {
        let (download, source, root) = try world(corrupt: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: source.destination, withIntermediateDirectories: true)
        try Data("ancien".utf8).write(to: source.destination.appending(path: "ancien.txt"))
        await #expect(throws: ModelDownloadError.mismatch("Encodeur.mlmodelc/poids.bin")) {
            try await download.install([source]) { _, _ in }
        }
        #expect(FileManager.default.fileExists(atPath: source.destination.appending(path: "ancien.txt").path(percentEncoded: false)))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false)) == ["installe"])
    }

    @Test func theStandardSourcesArePinned() {
        let locations = ModelLocations(root: URL(fileURLWithPath: "/tmp/modeles"))
        let sources = ModelSource.standard(locations)
        #expect(sources.map(\.revision) == ["0f63a7800b00dd0226abd051b906c246e1907482", "06f233fe06e710322aca913c1bc4249a0d71fce1",
                                            "b419383c55c110e2c9271fa6ee0ea83d03c70d96"])
        #expect(sources.map(\.repo) == ["argmaxinc/whisperkit-coreml", "openai/whisper-large-v3", "FluidInference/silero-vad-coreml"])
        #expect(sources[0].destination == locations.whisperFolder)
        #expect(sources[1].destination == locations.tokenizerFolder.appending(path: "models/openai/whisper-large-v3", directoryHint: .isDirectory))
        #expect(sources[2].destination == locations.sileroModel)
        #expect(sources[1].include("tokenizer.json") && !sources[1].include("model.safetensors") && !sources[1].include("onnx/encoder.onnx"))
    }
}
