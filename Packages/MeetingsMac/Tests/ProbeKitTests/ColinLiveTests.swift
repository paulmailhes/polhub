import Colin
import Foundation
import Observability
import Testing
@testable import ProbeKit

/// The real probe against the real Claude Code of this Mac: only with `POLHUB_COLIN_LIVE=1`, never in `make check`.
/// It spends a little of the account's use, on invented texts.
///
///     POLHUB_COLIN_LIVE=1 POLHUB_HELPER=<the built polhub> swift test --filter ColinLiveTests
///
/// `POLHUB_COLIN_ACCOUNT`: the folder of the Claude account (Claude Code's own when absent).
/// `POLHUB_COLIN_PINGS`: how many launches in a row (3 when absent).
@Suite struct ColinLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["POLHUB_COLIN_LIVE"] == "1"))
    func theProbeRunsAgainstTheRealClaudeCode() async throws {
        let environment = ProcessInfo.processInfo.environment
        let helper = environment["POLHUB_HELPER"].map { URL(fileURLWithPath: $0) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "sonde-colin-reelle-\(UUID().uuidString)", directoryHint: .isDirectory)
        let trace = try TraceWriter(fileURL: directory.appending(path: "trace.jsonl"))
        let probe = ColinProbe(helper: helper, pings: Int(environment["POLHUB_COLIN_PINGS"] ?? "") ?? 3)
        await probe.run(ProbeRequest(probe: .colin, variant: environment["POLHUB_COLIN_ACCOUNT"]), trace: trace, directory: directory)
        await trace.close()
        // The trace holds numbers and technical labels only: it can be shown.
        print(try String(contentsOf: directory.appending(path: "trace.jsonl"), encoding: .utf8))
        #expect(ColinProbe.verdict(in: directory) != nil)
    }
}
