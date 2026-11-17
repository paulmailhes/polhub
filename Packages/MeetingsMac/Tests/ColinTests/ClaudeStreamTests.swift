import Foundation
import Testing
@testable import Colin

/// Invented lines, in the shapes Claude Code writes on its standard output.
@Suite struct ClaudeStreamTests {
    func event(_ json: String) -> ClaudeEvent? { ClaudeStream.decode(Data(json.utf8)) }

    @Test func theInitTellsWhatIsLoaded() {
        let e = event(#"{"type":"system","subtype":"init","apiKeySource":"none","claude_code_version":"2.1.304","cwd":"/tmp/x","tools":["mcp__polhub__projets"],"mcp_servers":[{"name":"polhub","status":"connected"}],"model":"claude-haiku-4-5","permissionMode":"dontAsk","slash_commands":[],"skills":[],"plugins":[{"name":"p","path":"/x"}],"capabilities":["interrupt_receipt_v1"],"uuid":"u","session_id":"s"}"#)
        #expect(e == .initialized(ClaudeInit(version: "2.1.304", model: "claude-haiku-4-5", permissionMode: "dontAsk", apiKeySource: "none",
            tools: ["mcp__polhub__projets"], servers: ["polhub": "connected"], plugins: 1, skills: 0, slashCommands: 0, capabilities: ["interrupt_receipt_v1"])))
    }

    @Test func aPartialMessageGivesItsText() {
        #expect(event(#"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Bon"}},"parent_tool_use_id":null}"#) == .textDelta("Bon"))
        #expect(event(#"{"type":"stream_event","event":{"type":"message_start"}}"#) == .other("stream_event/message_start"))
        #expect(event(#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{"}}}"#) == .other("stream_event/content_block_delta"))
    }

    @Test func anAssistantMessageGivesItsTextAndItsTools() {
        #expect(event(#"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Bonjour."},{"type":"tool_use","id":"t1","name":"mcp__polhub__projets","input":{}}]},"parent_tool_use_id":null}"#)
            == .assistant(text: "Bonjour.", tools: ["mcp__polhub__projets"]))
    }

    @Test func aToolResultSaysWhetherItFailed() {
        #expect(event(#"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"3 projets","is_error":false}]}}"#) == .toolResult(isError: false))
        #expect(event(#"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"refusé","is_error":true}]}}"#) == .toolResult(isError: true))
        #expect(event(#"{"type":"user","message":{"role":"user","content":"un message rejoué"}}"#) == .other("user"))
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
        #expect(event(#"{"type":"system","subtype":"init"}"#) == .initialized(ClaudeInit()))
        #expect(event("pas du JSON") == nil)
        #expect(event(#"["un","tableau"]"#) == nil)
        #expect(event(#"{"sans":"type"}"#) == nil)
    }
}
