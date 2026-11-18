import Domain
import Foundation
import Testing
@testable import Colin

/// What Polhub accepts of a launch of Colin (18/11): his eleven tools, his one server, nothing of the user's, Opus,
/// no key. Checked on every `init`, which Claude Code says again at each turn.
@Suite struct ColinInitCheckTests {
    static let good = ClaudeInit(version: "2.1.304", model: "claude-opus-5-5", permissionMode: "dontAsk", apiKeySource: "none",
                                 tools: ColinTool.allowed, servers: ["polhub": "connected"], builtinPlugins: 4, agents: ["claude"], messaging: true)

    func with(_ change: (inout ClaudeInit) -> Void) -> ClaudeInit {
        var value = Self.good
        change(&value)
        return value
    }

    @Test func colinsLaunchPasses() {
        #expect(ColinInitCheck.problem(Self.good, tools: Set(ColinTool.allowed)) == nil)
    }

    @Test func anythingMoreOrOtherStopsIt() {
        let tools = Set(ColinTool.allowed)
        #expect(ColinInitCheck.problem(with { $0.tools.append("mcp__polhub__journal") }, tools: tools) == "outils")
        #expect(ColinInitCheck.problem(with { $0.tools.removeLast() }, tools: tools) == "outils")
        #expect(ColinInitCheck.problem(with { $0.tools.append("Bash") }, tools: tools) == "outils")
        #expect(ColinInitCheck.problem(with { $0.servers["autre"] = "connected" }, tools: tools) == "serveurs")
        #expect(ColinInitCheck.problem(with { $0.servers["polhub"] = "failed" }, tools: tools) == "serveurs")
        #expect(ColinInitCheck.problem(with { $0.plugins = 1 }, tools: tools) == "plugins")
        #expect(ColinInitCheck.problem(with { $0.skills = 1 }, tools: tools) == "skills")
        #expect(ColinInitCheck.problem(with { $0.slashCommands = 2 }, tools: tools) == "commandes")
        #expect(ColinInitCheck.problem(with { $0.memoryPaths = 1 }, tools: tools) == "memoire")
        #expect(ColinInitCheck.problem(with { $0.directories = 1 }, tools: tools) == "dossiers")
        #expect(ColinInitCheck.problem(with { $0.permissionMode = "default" }, tools: tools) == "mode")
        #expect(ColinInitCheck.problem(with { $0.model = "claude-fable-5-2" }, tools: tools) == "modele")
        #expect(ColinInitCheck.problem(with { $0.model = "claude-sonnet-5-5" }, tools: tools) == "modele")
        #expect(ColinInitCheck.problem(with { $0.apiKeySource = "ANTHROPIC_API_KEY" }, tools: tools) == "cle")
        #expect(ColinInitCheck.problem(with { $0.missing = ["tools"] }, tools: tools) == "incomplet")
    }

    @Test func theFailuresSayWhatWillGoOn() {
        #expect(ColinFailure.of(result: ClaudeResult(isError: true, apiErrorStatus: 401, text: "x"), rateLimit: nil, errors: "", initialized: true) == .notConnected)
        #expect(ColinFailure.of(result: ClaudeResult(isError: true, text: "Not logged in · Please run /login"), rateLimit: nil, errors: "", initialized: true) == .notConnected)
        let reset = Date(timeIntervalSince1970: 1_795_000_000)
        #expect(ColinFailure.of(result: ClaudeResult(isError: true, apiErrorStatus: 429), rateLimit: ClaudeRateLimit(status: "rejected", resetsAt: reset),
                                errors: "", initialized: true) == .limit(resetsAt: reset))
        #expect(ColinFailure.of(result: nil, rateLimit: nil, errors: "", initialized: false) == .launch)
        #expect(ColinFailure.of(result: nil, rateLimit: nil, errors: "", initialized: true) == .noAnswer)
        // An error of the turn's own says nothing that will go on.
        #expect(ColinFailure.of(result: ClaudeResult(subtype: "error_max_turns", isError: true), rateLimit: nil, errors: "", initialized: true) == nil)
    }
}
