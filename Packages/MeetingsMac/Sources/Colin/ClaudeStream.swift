import Foundation

/// What Claude Code says first: what it loaded. Polhub checks it at every launch (anything more than what was asked
/// stops the launch), and it is also how a change of Claude Code shows.
public struct ClaudeInit: Equatable, Sendable {
    public var version: String
    public var model: String
    public var permissionMode: String
    public var apiKeySource: String
    public var tools: [String]
    /// The servers by name, each with its state (« connected », « failed »…).
    public var servers: [String: String]
    /// The user's plugins. Those built into Claude Code itself (« builtin ») always load: they are counted apart.
    public var plugins: Int
    public var builtinPlugins: Int
    public var skills: Int
    public var slashCommands: Int
    /// The memory files (CLAUDE.md) and the extra folders taken along.
    public var memoryPaths: Int
    public var directories: Int
    /// The kinds of agents on offer; Claude Code has its own.
    public var agents: [String]
    /// A socket is open for the messages of the other sessions.
    public var messaging: Bool
    public var capabilities: [String]

    public init(version: String = "", model: String = "", permissionMode: String = "", apiKeySource: String = "", tools: [String] = [],
                servers: [String: String] = [:], plugins: Int = 0, builtinPlugins: Int = 0, skills: Int = 0, slashCommands: Int = 0,
                memoryPaths: Int = 0, directories: Int = 0, agents: [String] = [], messaging: Bool = false, capabilities: [String] = []) {
        self.version = version
        self.model = model
        self.permissionMode = permissionMode
        self.apiKeySource = apiKeySource
        self.tools = tools
        self.servers = servers
        self.plugins = plugins
        self.builtinPlugins = builtinPlugins
        self.skills = skills
        self.slashCommands = slashCommands
        self.memoryPaths = memoryPaths
        self.directories = directories
        self.agents = agents
        self.messaging = messaging
        self.capabilities = capabilities
    }
}

/// The end of a turn: how it went, what it cost, what was refused.
public struct ClaudeResult: Equatable, Sendable {
    /// « success », « error_during_execution » (an interrupted turn ends so), « error_max_turns »…
    public var subtype: String
    public var isError: Bool
    public var durationMs: Int
    public var numTurns: Int
    /// Claude Code's own estimate, at the API's prices.
    public var costUSD: Double
    /// Everything read: the new input, what was written to the cache and what was read from it.
    public var inputTokens: Int
    public var outputTokens: Int
    /// The names of the tools refused during the turn.
    public var denied: [String]
    public var apiErrorStatus: Int?
    /// The answer, or what an error says.
    public var text: String

    public init(subtype: String = "success", isError: Bool = false, durationMs: Int = 0, numTurns: Int = 0, costUSD: Double = 0,
                inputTokens: Int = 0, outputTokens: Int = 0, denied: [String] = [], apiErrorStatus: Int? = nil, text: String = "") {
        self.subtype = subtype
        self.isError = isError
        self.durationMs = durationMs
        self.numTurns = numTurns
        self.costUSD = costUSD
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.denied = denied
        self.apiErrorStatus = apiErrorStatus
        self.text = text
    }
}

/// Where the account stands in its windows of use: the five hours, the week.
public struct ClaudeRateLimit: Equatable, Sendable {
    /// « allowed », « allowed_warning », « rejected ».
    public var status: String
    public var type: String
    /// The part used, from 0 to 1.
    public var fiveHour: Double?
    public var sevenDay: Double?
    public var resetsAt: Date?

    public init(status: String = "", type: String = "", fiveHour: Double? = nil, sevenDay: Double? = nil, resetsAt: Date? = nil) {
        self.status = status
        self.type = type
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.resetsAt = resetsAt
    }
}

public enum ClaudeEvent: Equatable, Sendable {
    case initialized(ClaudeInit)
    /// A few words of the answer being written (a conversation only).
    case textDelta(String)
    /// A whole message of the model: its text, and the tools it calls.
    case assistant(text: String, tools: [String])
    case toolResult(isError: Bool)
    case rateLimit(ClaudeRateLimit)
    case result(ClaudeResult)
    case controlResponse(requestID: String, success: Bool)
    /// A line Polhub has no use for, or does not know yet: « type/subtype ». Counted, never fatal.
    case other(String)
    /// Never decoded: the process adds it when it ends, with the end of what it wrote on its error output.
    case exited(code: Int32, errors: String)
}

/// One line of Claude Code's output (`--output-format stream-json`) → one event. Lenient on purpose: the shapes
/// change from one version to the next, and a field that is missing reads as empty.
public enum ClaudeStream {
    public static func decode(_ line: Data) -> ClaudeEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let type = object["type"] as? String else { return nil }
        let subtype = object["subtype"] as? String
        switch type {
        case "system" where subtype == "init":
            return .initialized(initialization(object))
        case "stream_event":
            let event = object["event"] as? [String: Any] ?? [:]
            let delta = event["delta"] as? [String: Any] ?? [:]
            if event["type"] as? String == "content_block_delta", delta["type"] as? String == "text_delta", let text = delta["text"] as? String {
                return .textDelta(text)
            }
            return .other(named("stream_event", event["type"] as? String))
        case "assistant":
            let blocks = content(object)
            let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            let tools = blocks.filter { $0["type"] as? String == "tool_use" }.compactMap { $0["name"] as? String }
            return .assistant(text: text, tools: tools)
        case "user":
            let blocks = content(object)
            let results = blocks.filter { $0["type"] as? String == "tool_result" }
            if !results.isEmpty { return .toolResult(isError: results.contains { $0["is_error"] as? Bool == true }) }
            // What Claude Code writes itself when a turn is interrupted: nobody's message. Any other line of this
            // kind was not asked for.
            let interrupted = blocks.contains { ($0["text"] as? String)?.hasPrefix("[Request interrupted") == true }
            return .other(interrupted ? "user/interruption" : "user")
        case "rate_limit_event":
            return .rateLimit(rateLimit(object["rate_limit_info"] as? [String: Any] ?? [:]))
        case "result":
            return .result(result(object, subtype: subtype ?? ""))
        case "control_response":
            let response = object["response"] as? [String: Any] ?? [:]
            return .controlResponse(requestID: response["request_id"] as? String ?? "", success: response["subtype"] as? String == "success")
        default:
            return .other(named(type, subtype))
        }
    }

    private static func named(_ type: String, _ subtype: String?) -> String {
        subtype.map { "\(type)/\($0)" } ?? type
    }

    /// The blocks of a message; a message whose content is plain text has none.
    private static func content(_ object: [String: Any]) -> [[String: Any]] {
        (object["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
    }

    private static func int(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? 0 }
    private static func double(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
    private static func strings(_ value: Any?) -> [String] { value as? [String] ?? [] }
    private static func count(_ value: Any?) -> Int { (value as? [Any])?.count ?? 0 }

    private static func initialization(_ object: [String: Any]) -> ClaudeInit {
        var servers: [String: String] = [:]
        for server in object["mcp_servers"] as? [[String: Any]] ?? [] {
            if let name = server["name"] as? String { servers[name] = server["status"] as? String ?? "" }
        }
        let plugins = object["plugins"] as? [[String: Any]] ?? []
        // Claude Code's own are the ones it places at « builtin »; a name that ends like theirs is not enough.
        let builtin = plugins.filter { $0["path"] as? String == "builtin" }.count
        return ClaudeInit(
            version: object["claude_code_version"] as? String ?? "", model: object["model"] as? String ?? "",
            permissionMode: object["permissionMode"] as? String ?? "", apiKeySource: object["apiKeySource"] as? String ?? "",
            tools: strings(object["tools"]), servers: servers, plugins: plugins.count - builtin, builtinPlugins: builtin,
            skills: count(object["skills"]), slashCommands: count(object["slash_commands"]),
            memoryPaths: count(object["memory_paths"]), directories: count(object["additional_directories"]),
            agents: strings(object["agents"]), messaging: !(object["messaging_socket_path"] as? String ?? "").isEmpty,
            capabilities: strings(object["capabilities"]))
    }

    private static func rateLimit(_ info: [String: Any]) -> ClaudeRateLimit {
        let type = info["rateLimitType"] as? String ?? ""
        let windows = info["unifiedWindows"] as? [String: Any] ?? [:]
        func used(_ window: String) -> Double? {
            double((windows[window] as? [String: Any])?["utilization"]) ?? (type == window ? double(info["utilization"]) : nil)
        }
        return ClaudeRateLimit(status: info["status"] as? String ?? "", type: type, fiveHour: used("five_hour"), sevenDay: used("seven_day"),
                               resetsAt: double(info["resetsAt"]).map(Date.init(timeIntervalSince1970:)))
    }

    private static func result(_ object: [String: Any], subtype: String) -> ClaudeResult {
        let usage = object["usage"] as? [String: Any] ?? [:]
        let denials = object["permission_denials"] as? [[String: Any]] ?? []
        return ClaudeResult(
            subtype: subtype, isError: object["is_error"] as? Bool ?? false, durationMs: int(object["duration_ms"]), numTurns: int(object["num_turns"]),
            costUSD: double(object["total_cost_usd"]) ?? 0,
            inputTokens: int(usage["input_tokens"]) + int(usage["cache_creation_input_tokens"]) + int(usage["cache_read_input_tokens"]),
            outputTokens: int(usage["output_tokens"]), denied: denials.compactMap { $0["tool_name"] as? String },
            apiErrorStatus: (object["api_error_status"] as? NSNumber)?.intValue,
            text: object["result"] as? String ?? strings(object["errors"]).joined(separator: "\n"))
    }
}
