import Testing
@testable import ReadingKit

/// hub without Obsidian (16/11): the vault is deleted, so the server speaks of hub alone, and still keeps the
/// agents out of its base.
@Suite struct WithoutVaultInstructionsTests {
    @Test func theInstructionsNoLongerSpeakOfTheVault() {
        for text in [MCPServer.projectInstructions, MCPServer.meetingInstructions] {
            #expect(!text.contains("Obsidian") && !text.contains("coffre"))
        }
        #expect(MCPServer.projectInstructions.contains("N'ouvre jamais la base de hub toi-même"))
    }
}
