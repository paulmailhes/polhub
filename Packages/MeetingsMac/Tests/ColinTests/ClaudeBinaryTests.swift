import Foundation
import Testing
@testable import Colin

@Suite struct ClaudeBinaryTests {
    let home = URL(fileURLWithPath: "/Users/essai")

    @Test func theOfficialInstallComesFirst() {
        let all = ClaudeBinary.candidates(home: home, path: "/usr/bin:/bin", list: { _ in [] })
        #expect(all.first?.path == "/Users/essai/.local/bin/claude")
        #expect(all.map(\.path).contains("/usr/bin/claude"))
    }

    @Test func theNewestExtensionCopyComesBeforeOlderOnes() {
        let list: (URL) -> [String] = { $0.path.hasSuffix(".vscode/extensions")
            ? ["anthropic.claude-code-2.1.304-darwin-arm64", "anthropic.claude-code-2.1.326-darwin-arm64", "autre.extension-1.0.0"] : [] }
        let paths = ClaudeBinary.candidates(home: home, path: nil, list: list).map(\.path)
        let newest = paths.firstIndex { $0.contains("2.1.326") }, older = paths.firstIndex { $0.contains("2.1.304") }
        #expect(newest != nil && older != nil && newest! < older!)
        #expect(!paths.contains { $0.contains("autre.extension") })
    }

    @Test func aVersionIsComparedByItsNumbersNotItsLetters() {
        let list: (URL) -> [String] = { $0.path.hasSuffix(".vscode/extensions")
            ? ["anthropic.claude-code-2.1.99-darwin-arm64", "anthropic.claude-code-2.1.304-darwin-arm64"] : [] }
        let paths = ClaudeBinary.candidates(home: home, path: nil, list: list).map(\.path)
        #expect(paths.firstIndex { $0.contains("2.1.304") }! < paths.firstIndex { $0.contains("2.1.99-") }!)
    }

    @Test func theFirstExecutableCandidateWins() {
        let found = ClaudeBinary.find(home: home, path: nil, list: { _ in [] }, isExecutable: { $0.path == "/opt/homebrew/bin/claude" })
        #expect(found?.path == "/opt/homebrew/bin/claude")
    }

    @Test func nothingFoundIsNil() {
        #expect(ClaudeBinary.find(home: home, path: nil, list: { _ in [] }, isExecutable: { _ in false }) == nil)
    }

    @Test func theKindNeverTellsThePath() {
        #expect(ClaudeBinary.kind(of: URL(fileURLWithPath: "/Users/essai/.local/bin/claude"), home: home) == "officiel")
        #expect(ClaudeBinary.kind(of: URL(fileURLWithPath: "/opt/homebrew/bin/claude"), home: home) == "gestionnaire")
        #expect(ClaudeBinary.kind(of: URL(fileURLWithPath: "/Users/essai/.vscode/extensions/anthropic.claude-code-2.1.326-darwin-arm64/resources/native-binary/claude"), home: home) == "éditeur")
        #expect(ClaudeBinary.kind(of: URL(fileURLWithPath: "/Users/essai/Library/Application Support/Claude/claude-code/2.1.326/abc/claude.app/Contents/MacOS/claude"), home: home) == "app")
        #expect(ClaudeBinary.kind(of: URL(fileURLWithPath: "/usr/bin/claude"), home: home) == "chemin")
    }
}
