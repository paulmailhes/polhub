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
        // A space and an accent in the path, on purpose: the app's own folder (« Application Support ») has a space.
        let directory = FileManager.default.temporaryDirectory.appending(path: "sonde colin réelle \(UUID().uuidString)", directoryHint: .isDirectory)
        let trace = try TraceWriter(fileURL: directory.appending(path: "trace.jsonl"))
        let probe = ColinProbe(helper: helper, pings: Int(environment["POLHUB_COLIN_PINGS"] ?? "") ?? 3)
        await probe.run(ProbeRequest(probe: .colin, variant: environment["POLHUB_COLIN_ACCOUNT"]), trace: trace, directory: directory)
        await trace.close()
        // The trace holds numbers and technical labels only: it can be shown.
        let text = try String(contentsOf: directory.appending(path: "trace.jsonl"), encoding: .utf8)
        print(text)
        #expect(ColinProbe.verdict(in: directory) != nil)
        struct Line: Decodable { let kind: String; let data: ColinMeasure }
        let measures = text.split(separator: "\n").compactMap { try? JSONDecoder().decode(Line.self, from: Data($0.utf8)) }
            .filter { $0.kind == "colin" }.map(\.data)
        // The words by which Claude Code says « not connected » may change with its versions: a probe that reached
        // its end has seen them on the empty account, and must have known them.
        if measures.last?.labels["fin"] == "complete" {
            let unconnected = measures.last { $0.step == "panne" }
            #expect(unconnected?.labels["categorie"] == "pas-connecte")
            #expect(unconnected?.ok == true)
        }
        // Nothing of the run stays but its trace and its report.
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted() == ["bilan.json", "trace.jsonl"])
    }
}
