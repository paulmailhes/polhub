import Foundation
import Testing
@testable import Colin

/// Invented lines, in the shapes Claude Code writes on its standard output.
@Suite struct ClaudeStreamTests {
    func event(_ json: String) -> ClaudeEvent? { ClaudeStream.decode(Data(json.utf8)) }

    /// The lists every `init` of Claude Code 2.1.304 carries, empty (measured on 17/11). Its memory is not one of
    /// them: with the memory off, the line says nothing of it.
    static let lists = #""tools":[],"mcp_servers":[],"plugins":[],"skills":[],"slash_commands":[],"additional_directories":[]"#

    @Test func theInitTellsWhatIsLoaded() {
        let e = event(#"{"type":"system","subtype":"init","apiKeySource":"none","claude_code_version":"2.1.304","cwd":"/tmp/x","tools":["mcp__polhub__projets"],"mcp_servers":[{"name":"polhub","status":"connected"}],"model":"claude-haiku-4-5","permissionMode":"dontAsk","slash_commands":[],"skills":[],"plugins":[{"name":"p","path":"/x"}],"additional_directories":[],"capabilities":["interrupt_receipt_v1"],"uuid":"u","session_id":"s"}"#)
        #expect(e == .initialized(ClaudeInit(version: "2.1.304", model: "claude-haiku-4-5", permissionMode: "dontAsk", apiKeySource: "none",
            tools: ["mcp__polhub__projets"], servers: ["polhub": "connected"], plugins: 1, skills: 0, slashCommands: 0, capabilities: ["interrupt_receipt_v1"])))
    }

    /// As Claude Code 2.1.304 says it (measured on 17/11): its own plugins are named « builtin », and it tells its
    /// memory (an object, one key by kind: « auto » is the memory it keeps by itself), the extra folders and the
    /// agents it loaded.
    @Test func thePluginsBuiltIntoClaudeCodeAreCountedApart() {
        let e = event(#"{"type":"system","subtype":"init","tools":[],"mcp_servers":[],"skills":[],"slash_commands":[],"plugins":[{"name":"cc-plugin-telemetry","path":"builtin","source":"cc-plugin-telemetry@builtin"},{"name":"cc-plugin-agents-md","path":"builtin","source":"cc-plugin-agents-md@builtin"},{"name":"le-mien","path":"/x/plugins/le-mien","source":"le-mien@quelque-part"}],"memory_paths":{"auto":"/x/projects/y/memory"},"additional_directories":["/x/a","/x/b"],"agents":["claude","Explore"],"messaging_socket_path":"/tmp/cc.sock"}"#)
        #expect(e == .initialized(ClaudeInit(plugins: 1, builtinPlugins: 2, memoryPaths: 1, directories: 2, agents: ["claude", "Explore"], messaging: true)))
        #expect(event(#"{"type":"system","subtype":"init",\#(Self.lists),"messaging_socket_path":""}"#) == .initialized(ClaudeInit()))
    }

    /// Only what Claude Code itself calls « builtin » by its path is its own: a name that looks like it is not enough.
    @Test func aPluginThatOnlyLooksBuiltInIsTheUsers() {
        let e = event(#"{"type":"system","subtype":"init","tools":[],"mcp_servers":[],"skills":[],"slash_commands":[],"additional_directories":[],"plugins":[{"name":"faux","path":"/x/plugins/faux","source":"faux@builtin"}]}"#)
        #expect(e == .initialized(ClaudeInit(plugins: 1, builtinPlugins: 0)))
    }

    /// A list that is not there is not an empty list: nothing can be said of what it would have told.
    @Test func aListTheInitDoesNotCarryIsToldMissing() {
        #expect(event(#"{"type":"system","subtype":"init"}"#)
            == .initialized(ClaudeInit(missing: ["tools", "mcp_servers", "plugins", "skills", "slash_commands", "additional_directories"])))
        // A list of another shape (plain names where objects are expected) is missing too.
        #expect(event(#"{"type":"system","subtype":"init","tools":[],"mcp_servers":[],"plugins":["un-nom"],"skills":[],"slash_commands":[],"additional_directories":[]}"#)
            == .initialized(ClaudeInit(missing: ["plugins"])))
    }

    /// Each list in a shape that is not its own: none of them reads as empty.
    @Test func aListOfAnotherShapeIsToldMissing() {
        func initial(_ change: String) -> ClaudeEvent? {
            var lists = ["tools": "[]", "mcp_servers": "[]", "plugins": "[]", "skills": "[]", "slash_commands": "[]", "additional_directories": "[]"]
            let parts = change.split(separator: "=", maxSplits: 1).map(String.init)
            lists[parts[0]] = parts[1]
            let body = lists.sorted { $0.key < $1.key }.map { #""\#($0.key)":\#($0.value)"# }.joined(separator: ",")
            return event(#"{"type":"system","subtype":"init",\#(body)}"#)
        }
        #expect(initial(#"tools=[{"name":"Bash"}]"#) == .initialized(ClaudeInit(missing: ["tools"])))
        #expect(initial(#"mcp_servers=["polhub"]"#) == .initialized(ClaudeInit(missing: ["mcp_servers"])))
        #expect(initial(#"skills={"un":"objet"}"#) == .initialized(ClaudeInit(missing: ["skills"])))
        #expect(initial("slash_commands=null") == .initialized(ClaudeInit(missing: ["slash_commands"])))
        #expect(initial(#"additional_directories="/x""#) == .initialized(ClaudeInit(missing: ["additional_directories"])))
        // A server that does not say its name cannot be counted: the list is not taken for empty.
        #expect(initial(#"mcp_servers=[{"status":"pending"}]"#) == .initialized(ClaudeInit(missing: ["mcp_servers"])))
        #expect(initial(#"mcp_servers=[{"name":"polhub","status":"connected"},{"statut":"x"}]"#)
            == .initialized(ClaudeInit(servers: ["polhub": "connected"], missing: ["mcp_servers"])))
    }

    /// Numbers nobody would write, and values of the wrong kind: read as they can be, never a crash.
    @Test func hostileNumbersAreSurvived() {
        let huge = event(#"{"type":"result","subtype":"success","usage":{"input_tokens":9223372036854775807,"cache_creation_input_tokens":9223372036854775807,"cache_read_input_tokens":1,"output_tokens":-5},"duration_ms":1e300,"num_turns":"beaucoup","total_cost_usd":"cher"}"#)
        guard case .result(let result) = huge else { Issue.record("\(String(describing: huge))"); return }
        #expect(result.inputTokens == 2_000_000_001)
        #expect(result.outputTokens == 0)
        #expect(result.numTurns == 0 && result.costUSD == 0)
        #expect(event(#"{"type":"result","subtype":"success","usage":"aucun","permission_denials":"aucun","is_error":"oui","api_error_status":"x","result":12}"#)
            == .result(ClaudeResult(subtype: "success")))
        #expect(event(#"{"type":"rate_limit_event","rate_limit_info":{"status":3,"rateLimitType":null,"utilization":"x","resetsAt":"demain","unifiedWindows":[1]}}"#)
            == .rateLimit(ClaudeRateLimit()))
        #expect(event(#"{"type":"rate_limit_event","rate_limit_info":null}"#) == .rateLimit(ClaudeRateLimit()))
    }

    /// The memory, as Claude Code 2.1.304 says it (measured on 17/11): nothing at all when it is off, an object
    /// with one key by kind when it is on. Any other shape is a memory too: it is there, whatever it holds.
    @Test func theMemoryIsCountedWhateverItsShape() {
        func memory(_ value: String?) -> ClaudeEvent? {
            event(#"{"type":"system","subtype":"init",\#(Self.lists)\#(value.map { #","memory_paths":"# + $0 } ?? "")}"#)
        }
        #expect(memory(nil) == .initialized(ClaudeInit()))
        #expect(memory(#"{"auto":"/x/projects/y/memory"}"#) == .initialized(ClaudeInit(memoryPaths: 1)))
        #expect(memory(#"{"auto":"/x/a","user":"/x/b"}"#) == .initialized(ClaudeInit(memoryPaths: 2)))
        #expect(memory(#"["/x/CLAUDE.md","/y/CLAUDE.md","/z/CLAUDE.md"]"#) == .initialized(ClaudeInit(memoryPaths: 3)))
        #expect(memory(#""/x/CLAUDE.md""#) == .initialized(ClaudeInit(memoryPaths: 1)))
        // Present and empty: nothing loaded.
        #expect(memory("{}") == .initialized(ClaudeInit()))
        #expect(memory("[]") == .initialized(ClaudeInit()))
        #expect(memory("null") == .initialized(ClaudeInit()))
    }

    @Test func aPartialMessageGivesItsText() {
        #expect(event(#"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Bon"}},"parent_tool_use_id":null}"#) == .textDelta("Bon"))
        #expect(event(#"{"type":"stream_event","event":{"type":"message_start"}}"#) == .other("stream_event/message_start"))
        #expect(event(#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{"}}}"#) == .other("stream_event/content_block_delta"))
    }

    @Test func anAssistantMessageGivesItsTextAndItsTools() {
        #expect(event(#"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Bonjour."},{"type":"tool_use","id":"t1","name":"mcp__polhub__projets","input":{}}]},"parent_tool_use_id":null}"#)
            == .assistant(text: "Bonjour.", tools: ["mcp__polhub__projets"], calls: [ClaudeToolCall(id: "t1", name: "mcp__polhub__projets", arguments: [:])]))
    }

    /// The Accueil's pass (18/11): a tool's start is said the moment the model begins to write it, before its
    /// arguments; a text block's start is nothing.
    @Test func aToolStartIsSaid() {
        #expect(event(#"{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"mcp__polhub__mails","input":{}}}}"#)
            == .toolStarted(id: "toolu_1", name: "mcp__polhub__mails"))
        #expect(event(#"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}}"#)
            == .other("stream_event/content_block_start"))
    }

    /// A call's arguments, as short texts: numbers and switches written, lists joined, 60 characters at most.
    @Test func aCallSaysItsArguments() {
        let long = String(repeating: "a", count: 80)
        #expect(event(#"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_1","name":"mcp__polhub__mails","input":{"projet":"Cabinet Martin","limite":5,"non_lus":true,"numeros":[1,2],"texte":"\#(long)","objet":{"a":1}}}]}}"#)
            == .assistant(text: "", tools: ["mcp__polhub__mails"], calls: [ClaudeToolCall(id: "toolu_1", name: "mcp__polhub__mails", arguments: [
                "projet": "Cabinet Martin", "limite": "5", "non_lus": "true", "numeros": "1, 2", "texte": String(long.prefix(59)) + "…"])]))
    }

    @Test func eachResultSaysItsTool() {
        #expect(event(#"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok","is_error":false},{"type":"tool_result","tool_use_id":"t2","content":"non","is_error":true}]}}"#)
            == .toolResult(isError: true, text: "non", outcomes: [ClaudeToolOutcome(id: "t1", isError: false), ClaudeToolOutcome(id: "t2", isError: true)]))
    }

    @Test func aToolResultSaysWhetherItFailed() {
        #expect(event(#"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"3 projets","is_error":false}]}}"#)
            == .toolResult(isError: false, outcomes: [ClaudeToolOutcome(id: "t1", isError: false)]))
        #expect(event(#"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"refusé","is_error":true}]}}"#)
            == .toolResult(isError: true, text: "refusé", outcomes: [ClaudeToolOutcome(id: "t1", isError: true)]))
        #expect(event(#"{"type":"user","message":{"role":"user","content":"un message rejoué"}}"#) == .other("user"))
    }

    /// The text of a tool that failed, its beginning only (Colin's lock says itself there); never a tool's answer.
    @Test func aToolErrorKeepsItsText() {
        let long = String(repeating: "é", count: 400)
        #expect(event(#"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"Verrou de Colin : non","is_error":true}]}}"#)
            == .toolResult(isError: true, text: "Verrou de Colin : non", outcomes: [ClaudeToolOutcome(id: "t1", isError: true)]))
        #expect(event(#"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":[{"type":"text","text":"Verrou de Colin"}],"is_error":true}]}}"#)
            == .toolResult(isError: true, text: "Verrou de Colin", outcomes: [ClaudeToolOutcome(id: "t1", isError: true)]))
        #expect(event(#"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"\#(long)","is_error":true}]}}"#)
            == .toolResult(isError: true, text: String(long.prefix(300)), outcomes: [ClaudeToolOutcome(id: "t1", isError: true)]))
        #expect(event(#"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"Claire écrit…","is_error":false}]}}"#)
            == .toolResult(isError: false, text: "", outcomes: [ClaudeToolOutcome(id: "t1", isError: false)]))
    }

    /// What Claude Code 2.1.304 writes itself when a turn is interrupted (measured on 17/11): not a message of anyone.
    @Test func theMarkOfAnInterruptionIsToldApart() {
        #expect(event(#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]},"parent_tool_use_id":null,"timestamp":"2026-11-17T22:00:00Z"}"#)
            == .other("user/interruption"))
        #expect(event(#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Un message venu d'ailleurs"}]}}"#) == .other("user"))
        #expect(event(#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}"#) == .other("user/interruption"))
        // The mark and nothing else: a text that only begins like it, or the mark with something more, is a message.
        #expect(event(#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user] puis fais ceci"}]}}"#) == .other("user"))
        #expect(event(#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"},{"type":"text","text":"autre chose"}]}}"#) == .other("user"))
        // The mark's words in a block that is not a text: not the mark.
        #expect(event(#"{"type":"user","message":{"role":"user","content":[{"type":"image","text":"[Request interrupted by user]"}]}}"#) == .other("user"))
    }

    @Test func aRateLimitGivesBothWindows() {
        #expect(event(#"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","resetsAt":1795000000,"rateLimitType":"five_hour","utilization":0.42,"unifiedWindows":{"five_hour":{"utilization":0.42,"resetsAt":1795000000},"seven_day":{"utilization":0.11,"resetsAt":1795400000}}}}"#)
            == .rateLimit(ClaudeRateLimit(status: "allowed", type: "five_hour", fiveHour: 0.42, sevenDay: 0.11, resetsAt: Date(timeIntervalSince1970: 1_795_000_000))))
        #expect(event(#"{"type":"rate_limit_event","rate_limit_info":{"status":"rejected","rateLimitType":"seven_day","utilization":1}}"#)
            == .rateLimit(ClaudeRateLimit(status: "rejected", type: "seven_day", fiveHour: nil, sevenDay: 1, resetsAt: nil)))
    }

    @Test func aResultGivesItsCostItsTokensAndItsRefusals() {
        #expect(event(#"{"type":"result","subtype":"success","duration_ms":1200,"duration_api_ms":900,"is_error":false,"num_turns":2,"result":"fini","total_cost_usd":0.0002,"usage":{"input_tokens":12,"output_tokens":3,"cache_creation_input_tokens":800,"cache_read_input_tokens":100},"permission_denials":[{"tool_name":"mcp__polhub__journal","tool_use_id":"t2","tool_input":{}}]}"#)
            == .result(ClaudeResult(subtype: "success", isError: false, durationMs: 1200, numTurns: 2, costUSD: 0.0002, inputTokens: 912, outputTokens: 3,
                                    denied: ["mcp__polhub__journal"], apiErrorStatus: nil, text: "fini")))
        #expect(event(#"{"type":"result","subtype":"error_during_execution","is_error":true,"api_error_status":401}"#)
            == .result(ClaudeResult(subtype: "error_during_execution", isError: true, durationMs: 0, numTurns: 0, costUSD: 0, inputTokens: 0, outputTokens: 0,
                                    denied: [], apiErrorStatus: 401, text: "")))
    }

    @Test func anErrorResultKeepsWhatItSays() {
        #expect(event(#"{"type":"result","subtype":"error_max_turns","is_error":true,"errors":["Reached maximum number of turns (1)"]}"#)
            == .result(ClaudeResult(subtype: "error_max_turns", isError: true, text: "Reached maximum number of turns (1)")))
    }

    @Test func aControlResponseNamesItsRequest() {
        #expect(event(#"{"type":"control_response","response":{"subtype":"success","request_id":"r1","response":{}}}"#) == .controlResponse(requestID: "r1", success: true))
        #expect(event(#"{"type":"control_response","response":{"subtype":"error","request_id":"r2","error":"x"}}"#) == .controlResponse(requestID: "r2", success: false))
    }

    @Test func anUnknownLineIsKeptAsOther() {
        #expect(event(#"{"type":"system","subtype":"session_state_changed","state":"idle"}"#) == .other("system/session_state_changed"))
        #expect(event(#"{"type":"nouveau_message_de_demain"}"#) == .other("nouveau_message_de_demain"))
        #expect(event(#"{"type":"system","subtype":"init",\#(Self.lists)}"#) == .initialized(ClaudeInit()))
        #expect(event("pas du JSON") == nil)
        #expect(event(#"["un","tableau"]"#) == nil)
        #expect(event(#"{"sans":"type"}"#) == nil)
    }
}
