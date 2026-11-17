import Foundation

/// One launch of Claude Code by Polhub, closed on itself: none of the user's settings, hooks, plugins, skills,
/// instructions or servers come along, no tool of the Mac, nothing asked on a screen, no session and no memory kept,
/// deaf to the other sessions. What it may use is said here and nowhere else.
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
    /// « low », « medium », « high »…; `nil`: the model's own.
    public var effort: String?

    public init(model: String, systemPrompt: String, prompt: String? = nil, mcpConfig: String? = nil,
                allowedTools: [String] = [], maxTurns: Int? = nil, configDirectory: URL? = nil, effort: String? = nil) {
        self.model = model
        self.systemPrompt = systemPrompt
        self.prompt = prompt
        self.mcpConfig = mcpConfig
        self.allowedTools = allowedTools
        self.maxTurns = maxTurns
        self.configDirectory = configDirectory
        self.effort = effort
    }

    public var arguments: [String] {
        // The answer always comes word by word: its first word is what a person waits for.
        var all: [String]
        if let prompt {
            all = ["-p", prompt, "--output-format", "stream-json", "--verbose", "--include-partial-messages"]
        } else {
            all = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages"]
        }
        all += ["--model", model]
        if let effort { all += ["--effort", effort] }
        all += [
            "--system-prompt", systemPrompt,
            "--setting-sources", "",
            "--strict-mcp-config",
            "--tools", "",
            "--permission-mode", "dontAsk",
            "--permission-prompts", "none",
            "--disable-slash-commands",
            "--no-session-persistence",
            "--settings", Self.settings,
        ]
        if let mcpConfig { all += ["--mcp-config", mcpConfig] }
        if !allowedTools.isEmpty { all += ["--allowedTools", allowedTools.joined(separator: ",")] }
        if let maxTurns { all += ["--max-turns", String(maxTurns)] }
        return all
    }

    /// The settings given on top of none: deaf to the other sessions, and no memory of its own. Without the second,
    /// Claude Code keeps a memory by folder in the account, even with no settings file read (measured on 17/11 with
    /// Claude Code 2.1.304: its first line then tells a memory; with this setting, or with the variable below, none).
    static let settings = #"{"autoMemoryEnabled":false,"crossSessionInbound":"refuse"}"#

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
        // Said twice, here and in the settings: one of the two may change its name with a version.
        environment["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1"
        // Written as the user's own launches write it, with no slash at its end: with one more, Claude Code no longer
        // finds the account's connection (measured on 17/11 with Claude Code 2.1.304).
        if let configDirectory { environment["CLAUDE_CONFIG_DIR"] = Self.plain(configDirectory) }
        return environment
    }

    /// The folder to give for an account chosen by hand. Claude Code's own folder, or none, is its own account: no
    /// variable at all. Given as a variable, even its own folder is « not logged in » (measured on 17/11 with
    /// Claude Code 2.1.304).
    public static func account(folder: String?, home: URL) -> URL? {
        guard let folder, !folder.isEmpty else { return nil }
        let chosen = URL(fileURLWithPath: folder, isDirectory: true).standardizedFileURL
        let own = home.appending(path: ".claude", directoryHint: .isDirectory).standardizedFileURL
        if plain(chosen) == plain(own) { return nil }
        // The same folder written another way (a link to it, another case): compared as the disk knows them.
        if let one = identity(chosen), let other = identity(own), one.isEqual(other) { return nil }
        return chosen
    }

    private static func identity(_ url: URL) -> (any NSObjectProtocol)? {
        (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier
    }

    /// A folder's path with no slash at its end.
    static func plain(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
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
