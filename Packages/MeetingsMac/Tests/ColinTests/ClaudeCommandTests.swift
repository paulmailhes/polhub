import Foundation
import Testing
@testable import Colin

@Suite struct ClaudeCommandTests {
    let base = ["HOME": "/Users/essai", "PATH": "/usr/bin", "ANTHROPIC_API_KEY": "sk-x", "CLAUDE_CONFIG_DIR": "/ailleurs",
                "CLAUDE_CODE_ENTRYPOINT": "vscode", "AUTRE": "1"]

    func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    @Test func aOneShotCommandCarriesItsPromptAndTheIsolation() {
        let arguments = ClaudeCommand(model: "haiku", systemPrompt: "Réponds en un mot.", prompt: "ok ?", maxTurns: 1).arguments
        #expect(Array(arguments.prefix(6)) == ["-p", "ok ?", "--output-format", "stream-json", "--verbose", "--include-partial-messages"])
        #expect(!arguments.contains("--effort"))
        let pairs = [("--setting-sources", ""), ("--tools", ""), ("--permission-mode", "dontAsk"), ("--permission-prompts", "none"),
                     ("--settings", #"{"autoMemoryEnabled":false,"crossSessionInbound":"refuse"}"#), ("--max-turns", "1"), ("--model", "haiku"),
                     ("--system-prompt", "Réponds en un mot.")]
        for (flag, expected) in pairs {
            #expect(value(after: flag, in: arguments) == expected, "\(flag)")
        }
        for flag in ["--strict-mcp-config", "--disable-slash-commands", "--no-session-persistence"] {
            #expect(arguments.contains(flag), "\(flag)")
        }
        for flag in ["--input-format", "--mcp-config", "--allowedTools"] {
            #expect(!arguments.contains(flag), "\(flag)")
        }
    }

    @Test func anEffortIsSaidOnlyWhenChosen() {
        var command = ClaudeCommand(model: "opus", systemPrompt: "x", prompt: "y")
        command.effort = "low"
        #expect(value(after: "--effort", in: command.arguments) == "low")
    }

    @Test func aConversationReadsItsMessagesOnTheStandardInput() {
        let arguments = ClaudeCommand(model: "opus", systemPrompt: "x", mcpConfig: "{}",
                                      allowedTools: ["mcp__polhub__projets", "mcp__polhub__contexte"]).arguments
        #expect(Array(arguments.prefix(7)) == ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages"])
        #expect(value(after: "--allowedTools", in: arguments) == "mcp__polhub__projets,mcp__polhub__contexte")
        #expect(value(after: "--mcp-config", in: arguments) == "{}")
        #expect(value(after: "--tools", in: arguments) == "")
        #expect(!arguments.contains("--max-turns"))
    }

    @Test func noAnthropicNorClaudeVariableIsInherited() {
        let environment = ClaudeCommand(model: "haiku", systemPrompt: "x", prompt: "y").environment(from: base)
        // Two switches of Claude Code's own are set: no server of claude.ai, and no memory kept by itself.
        #expect(environment == ["HOME": "/Users/essai", "PATH": "/usr/bin", "ENABLE_CLAUDEAI_MCP_SERVERS": "false",
                                "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1"])
    }

    /// The rule, not three names: nothing of Anthropic's nor of Claude Code's is ever let through.
    @Test func nothingOfAnthropicNorOfClaudeCodeCanBeInherited() {
        #expect(ClaudeCommand.inherited.allSatisfy { !$0.uppercased().hasPrefix("ANTHROPIC") && !$0.uppercased().hasPrefix("CLAUDE") })
        var loud = base
        for name in ["ANTHROPIC_BASE_URL", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_SIMPLE", "CLAUDECODE"] { loud[name] = "x" }
        let environment = ClaudeCommand(model: "haiku", systemPrompt: "x", prompt: "y").environment(from: loud)
        #expect(Set(environment.keys) == ["HOME", "PATH", "ENABLE_CLAUDEAI_MCP_SERVERS", "CLAUDE_CODE_DISABLE_AUTO_MEMORY"])
    }

    /// A folder written from the user's own (« ~/… ») is read from it, not from wherever the app runs.
    @Test func aFolderWrittenWithATildeIsReadFromTheUsersFolder() {
        let home = URL(fileURLWithPath: "/Users/essai")
        #expect(ClaudeCommand.account(folder: "~/.claude", home: home) == nil)
        #expect(ClaudeCommand.account(folder: "~/.claude/", home: home) == nil)
        #expect(ClaudeCommand.account(folder: "~/comptes/second", home: home)?.path(percentEncoded: false).hasPrefix("/Users/essai/comptes/second") == true)
        #expect(ClaudeCommand.account(folder: "~", home: home)?.standardizedFileURL.path(percentEncoded: false).hasPrefix("/Users/essai") == true)
    }

    @Test func theAccountFolderBecomesClaudeConfigDir() {
        let command = ClaudeCommand(model: "haiku", systemPrompt: "x", prompt: "y", configDirectory: URL(fileURLWithPath: "/Users/essai/comptes/second"))
        #expect(command.environment(from: base)["CLAUDE_CONFIG_DIR"] == "/Users/essai/comptes/second")
    }

    @Test func theAccountFolderIsWrittenWithoutASlashAtItsEnd() {
        // Claude Code names the account's entry in the Keychain after this text: a slash more is another account.
        let command = ClaudeCommand(model: "haiku", systemPrompt: "x", prompt: "y",
                                    configDirectory: URL(fileURLWithPath: "/Users/essai/comptes/second", isDirectory: true))
        #expect(command.environment(from: base)["CLAUDE_CONFIG_DIR"] == "/Users/essai/comptes/second")
    }

    /// Measured on 17/11 with Claude Code 2.1.304: given as a variable, even its own folder is « not logged in ».
    @Test func claudeCodesOwnFolderIsNeverGivenAsAVariable() {
        let home = URL(fileURLWithPath: "/Users/essai")
        #expect(ClaudeCommand.account(folder: nil, home: home) == nil)
        #expect(ClaudeCommand.account(folder: "", home: home) == nil)
        #expect(ClaudeCommand.account(folder: "/Users/essai/.claude", home: home) == nil)
        #expect(ClaudeCommand.account(folder: "/Users/essai/.claude/", home: home) == nil)
        let second = ClaudeCommand.account(folder: "/Users/essai/comptes/second/", home: home)
        #expect(second != nil)
        let command = ClaudeCommand(model: "haiku", systemPrompt: "x", prompt: "y", configDirectory: second)
        #expect(command.environment(from: base)["CLAUDE_CONFIG_DIR"] == "/Users/essai/comptes/second")
    }

    /// Another way to write Claude Code's own folder (a link to it) is still its own account.
    @Test func aLinkToClaudeCodesOwnFolderIsItsOwnAccountToo() throws {
        let manager = FileManager.default
        let home = manager.temporaryDirectory.appending(path: "colin-maison-\(UUID().uuidString)", directoryHint: .isDirectory)
        let own = home.appending(path: ".claude", directoryHint: .isDirectory)
        let other = home.appending(path: "second", directoryHint: .isDirectory)
        try manager.createDirectory(at: own, withIntermediateDirectories: true)
        try manager.createDirectory(at: other, withIntermediateDirectories: true)
        let link = home.appending(path: "lien")
        try manager.createSymbolicLink(at: link, withDestinationURL: own)
        defer { try? manager.removeItem(at: home) }
        #expect(ClaudeCommand.account(folder: link.path(percentEncoded: false), home: home) == nil)
        #expect(ClaudeCommand.account(folder: other.path(percentEncoded: false), home: home) != nil)
    }

    @Test func theServerConfigNamesTheHelperAndItsBase() {
        let json = ClaudeCommand.mcpConfig(helper: URL(fileURLWithPath: "/Applications/Polhub.app/Contents/Helpers/polhub"),
                                           base: URL(fileURLWithPath: "/tmp/essai/Polhub.sqlite"))
        #expect(json == #"{"mcpServers":{"polhub":{"args":["mcp","--base","/tmp/essai/Polhub.sqlite"],"command":"/Applications/Polhub.app/Contents/Helpers/polhub","type":"stdio"}}}"#)
    }

    @Test func colinsServerIsLaunchedWithItsProfile() throws {
        let json = ClaudeCommand.mcpConfig(helper: URL(fileURLWithPath: "/Applications/Polhub.app/Contents/Helpers/polhub"),
                                           base: URL(fileURLWithPath: "/tmp/essai/Polhub.sqlite"), colin: true)
        let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let server = try #require((object["mcpServers"] as? [String: Any])?["polhub"] as? [String: Any])
        #expect(server["args"] as? [String] == ["mcp", "--base", "/tmp/essai/Polhub.sqlite", "--colin"])
    }

    @Test func theInputLinesAreSingleLinesOfJSON() throws {
        let user = ClaudeCommand.userLine("Bonjour,\n« ça va » ?")
        #expect(!user.contains("\n"))
        let decoded = try JSONSerialization.jsonObject(with: Data(user.utf8)) as? [String: Any]
        #expect(decoded?["type"] as? String == "user")
        #expect(decoded?["parent_tool_use_id"] is NSNull)
        let message = decoded?["message"] as? [String: Any]
        #expect(message?["role"] as? String == "user")
        #expect(message?["content"] as? String == "Bonjour,\n« ça va » ?")
        #expect(ClaudeCommand.interruptLine("r1") == #"{"request":{"subtype":"interrupt"},"request_id":"r1","type":"control_request"}"#)
    }
}
