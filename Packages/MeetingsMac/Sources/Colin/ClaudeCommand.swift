import Foundation

/// One launch of Claude Code by Polhub, closed on itself: none of the user's settings, hooks, plugins, skills or
/// servers come along, no tool of the Mac, nothing asked on a screen, no session kept, deaf to the other sessions.
/// What it may use is said here and nowhere else.
public struct ClaudeCommand: Equatable, Sendable {
    /// « haiku », « opus »: Claude Code's own names.
    public var model: String
    /// It replaces Claude Code's own instructions.
    public var systemPrompt: String
    /// The one request of a launch that answers once and ends. `nil`: a conversation, whose messages come on the
    /// standard input (`userLine`), and whose answer comes word by word.
    public var prompt: String?
    /// The JSON given to `--mcp-config` (`mcpConfig(helper:base:)`); `nil`: no server at all.
    public var mcpConfig: String?
    /// The only tools that run; every other one is refused without a question.
    public var allowedTools: [String]
    public var maxTurns: Int?
    /// The folder of the Claude account to use; `nil`: Claude Code's own.
    public var configDirectory: URL?

    public init(model: String, systemPrompt: String, prompt: String? = nil, mcpConfig: String? = nil,
                allowedTools: [String] = [], maxTurns: Int? = nil, configDirectory: URL? = nil) {
        self.model = model
        self.systemPrompt = systemPrompt
        self.prompt = prompt
        self.mcpConfig = mcpConfig
        self.allowedTools = allowedTools
        self.maxTurns = maxTurns
        self.configDirectory = configDirectory
    }

    public var arguments: [String] {
        var all: [String]
        if let prompt {
            all = ["-p", prompt, "--output-format", "stream-json", "--verbose"]
        } else {
            all = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages"]
        }
        all += [
            "--model", model,
            "--system-prompt", systemPrompt,
            "--setting-sources", "",
            "--strict-mcp-config",
            "--tools", "",
            "--permission-mode", "dontAsk",
            "--permission-prompts", "none",
            "--disable-slash-commands",
            "--no-session-persistence",
            "--settings", #"{"crossSessionInbound":"refuse"}"#,
        ]
        if let mcpConfig { all += ["--mcp-config", mcpConfig] }
        if !allowedTools.isEmpty { all += ["--allowedTools", allowedTools.joined(separator: ",")] }
        if let maxTurns { all += ["--max-turns", String(maxTurns)] }
        return all
    }

    /// What passes from the app's environment: where the user lives, the language, a proxy. Nothing of Anthropic's
    /// or of Claude Code's is inherited: an API key lying there would change who pays, a session's variables would
    /// change what loads.
    static let inherited: Set<String> = [
        "HOME", "USER", "LOGNAME", "PATH", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "SHELL", "__CF_USER_TEXT_ENCODING",
        "HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY", "http_proxy", "https_proxy", "no_proxy", "SSL_CERT_FILE", "NODE_EXTRA_CA_CERTS",
    ]

    public func environment(from base: [String: String]) -> [String: String] {
        var environment = base.filter { Self.inherited.contains($0.key) }
        environment["ENABLE_CLAUDEAI_MCP_SERVERS"] = "false"
        if let configDirectory {
            // Written as the user's own launches write it, with no slash at the end: Claude Code names the account's
            // entry in the Keychain after this very text.
            var path = configDirectory.path(percentEncoded: false)
            while path.count > 1, path.hasSuffix("/") { path.removeLast() }
            environment["CLAUDE_CONFIG_DIR"] = path
        }
        return environment
    }

    /// Polhub's own server and nothing else, on the base given.
    public static func mcpConfig(helper: URL, base: URL) -> String {
        json(["mcpServers": ["polhub": [
            "type": "stdio",
            "command": helper.path(percentEncoded: false),
            "args": ["mcp", "--base", base.path(percentEncoded: false)],
        ]]])
    }

    /// A message of the user, as a conversation reads it on its standard input: one line.
    public static func userLine(_ text: String) -> String {
        json(["type": "user", "message": ["role": "user", "content": text], "parent_tool_use_id": NSNull()])
    }

    /// « Stop this turn »: the turn ends on a result, the conversation stays open.
    public static func interruptLine(_ requestID: String) -> String {
        json(["type": "control_request", "request_id": requestID, "request": ["subtype": "interrupt"]])
    }

    private static func json(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
