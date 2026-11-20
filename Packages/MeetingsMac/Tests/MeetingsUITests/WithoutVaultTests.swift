import Foundation
import Persistence
import Testing
@testable import MeetingsUI

/// hub without Obsidian (16/11): Paul deleted the vault. No code reads it any more, no screen leads to it, no
/// setting keeps its folder; what came from it stays in the base.
@MainActor @Suite struct WithoutVaultTests {
    static let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The importers, their settings and their target are gone from the app and its packages.
    @Test func noCodeReadsTheVault() throws {
        let banned = ["VaultImport", "HistoryImport", "HistoryReader", "InspirationImport", "importHistory", "runImport", "vaultPath", "vaultKey",
                      "vaultCopy", "inspirationOldCopyFolder", "dossierAncienneCopie", "oldCopyPath", "Importer depuis le coffre"]
        let manager = FileManager.default
        for folder in ["Sources", "../Kernel/Sources", "../../App"] {
            let root = Self.package.appending(path: folder, directoryHint: .isDirectory)
            let files = try #require(manager.enumerator(at: root, includingPropertiesForKeys: nil))
            for case let file as URL in files where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                for word in banned {
                    #expect(!text.contains(word), "\(file.lastPathComponent) : \(word)")
                }
            }
        }
        for file in ["Package.swift", "../../project.yml", "../../scripts/verify-bundle.sh"] {
            let text = try String(contentsOf: Self.package.appending(path: file), encoding: .utf8)
            #expect(!text.contains("VaultImport"), "\(file)")
        }
    }

    /// What Paul reads no longer speaks of the vault as a thing he has: Réglages › Inspiration and the empty pages.
    @Test func theScreensNoLongerSpeakOfTheVault() {
        #expect(!SettingsPane.inspiration.subtitle.contains("coffre"))
        for kind in InspirationKind.allCases {
            #expect(!kind.emptyText.contains("coffre") && !kind.emptyText.contains("Obsidian"), "\(kind)")
        }
    }
}
