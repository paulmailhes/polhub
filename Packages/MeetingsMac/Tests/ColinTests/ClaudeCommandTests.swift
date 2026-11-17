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
        #expect(Array(arguments.prefix(5)) == ["-p", "ok ?", "--output-format", "stream-json", "--verbose"])
        let pairs = [("--setting-sources", ""), ("--tools", ""), ("--permission-mode", "dontAsk"), ("--permission-prompts", "none"),
                     ("--settings", #"{"crossSessionInbound":"refuse"}"#), ("--max-turns", "1"), ("--model", "haiku"),
                     ("--system-prompt", "Réponds en un mot.")]
        for (flag, expected) in pairs {
            #expect(value(after: flag, in: arguments) == expected, "\(flag)")
        }
        for flag in ["--strict-mcp-config", "--disable-slash-commands", "--no-session-persistence"] {
            #expect(arguments.contains(flag), "\(flag)")
        }
        for flag in ["--input-format", "--include-partial-messages", "--mcp-config", "--allowedTools"] {
            #expect(!arguments.contains(flag), "\(flag)")
        }
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
        #expect(environment == ["HOME": "/Users/essai", "PATH": "/usr/bin", "ENABLE_CLAUDEAI_MCP_SERVERS": "false"])
    }

    @Test func theAccountFolderBecomesClaudeConfigDir() {
        let command = ClaudeCommand(model: "haiku", systemPrompt: "x", prompt: "y", configDirectory: URL(fileURLWithPath: "/Users/essai/comptes/second"))
        #expect(command.environment(from: base)["CLAUDE_CONFIG_DIR"] == "/Users/essai/comptes/second")
    }

    @Test func theServerConfigNamesTheHelperAndItsBase() {
        let json = ClaudeCommand.mcpConfig(helper: URL(fileURLWithPath: "/Applications/Polhub.app/Contents/Helpers/polhub"),
                                           base: URL(fileURLWithPath: "/tmp/essai/Polhub.sqlite"))
        #expect(json == #"{"mcpServers":{"polhub":{"args":["mcp","--base","/tmp/essai/Polhub.sqlite"],"command":"/Applications/Polhub.app/Contents/Helpers/polhub","type":"stdio"}}}"#)
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
