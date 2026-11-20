import Foundation
import Testing
@testable import Observability

/// 20/11 : hub devient hub-board. Ses dossiers changent de nom au premier lancement de la nouvelle version ; l'ancien
/// chemin devient un lien, pour la ligne de commande des sessions déjà ouvertes et pour un retour en arrière.
@Suite struct AppFoldersTests {
    func scratch() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "dossiers-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func isLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path(percentEncoded: false))) != nil
    }

    @Test func theNamesAreHubBoardsAndPolhubsBefore() {
        #expect(AppFolders.name(dev: false) == "hub-board" && AppFolders.name(dev: true) == "hub-board-dev")
        #expect(AppFolders.legacyName(dev: false) == "Polhub" && AppFolders.legacyName(dev: true) == "Polhub-dev")
    }

    @Test func legacyFoldersAreMovedAndLinked() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("base", to: root.appending(path: "Polhub/Polhub.sqlite"))
        let lines = AppFolders.moveLegacy(in: root, dev: false)
        #expect(lines.count == 1)
        #expect(try String(contentsOf: root.appending(path: "hub-board/Polhub.sqlite"), encoding: .utf8) == "base")
        #expect(isLink(root.appending(path: "Polhub")))
    }

    @Test func movingTwiceChangesNothing() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("base", to: root.appending(path: "Polhub/Polhub.sqlite"))
        _ = AppFolders.moveLegacy(in: root, dev: false)
        #expect(AppFolders.moveLegacy(in: root, dev: false).isEmpty)
        #expect(try String(contentsOf: root.appending(path: "hub-board/Polhub.sqlite"), encoding: .utf8) == "base")
    }

    @Test func aNewFolderAlreadyThereIsLeftAlone() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("ancienne", to: root.appending(path: "Polhub/Polhub.sqlite"))
        try write("nouvelle", to: root.appending(path: "hub-board/Polhub.sqlite"))
        #expect(AppFolders.moveLegacy(in: root, dev: false).isEmpty)
        #expect(!isLink(root.appending(path: "Polhub")))
        #expect(try String(contentsOf: root.appending(path: "Polhub/Polhub.sqlite"), encoding: .utf8) == "ancienne")
    }

    /// A `hub mcp` still alive in an open session opens the base by its old path: the same file, never an empty base.
    @Test func theOldPathStillReachesTheSameBase() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("base", to: root.appending(path: "Polhub/Polhub.sqlite"))
        _ = AppFolders.moveLegacy(in: root, dev: false)
        try write("écrite après", to: root.appending(path: "hub-board/Polhub.sqlite"))
        #expect(try String(contentsOf: root.appending(path: "Polhub/Polhub.sqlite"), encoding: .utf8) == "écrite après")
    }

    @Test func resolveFindsTheOldFolderBeforeTheMove() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(AppFolders.resolve(in: root, dev: false).lastPathComponent == "hub-board")
        try write("base", to: root.appending(path: "Polhub/Polhub.sqlite"))
        #expect(AppFolders.resolve(in: root, dev: false).lastPathComponent == "Polhub")
        _ = AppFolders.moveLegacy(in: root, dev: false)
        #expect(AppFolders.resolve(in: root, dev: false).lastPathComponent == "hub-board")
    }
}
