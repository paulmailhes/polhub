import Domain
import Foundation
import MeetingDetection
import Observability

/// Reads Dia's Meet tabs once per second and records what comes back and how long it took.
public struct TabsProbe: Probe {
    struct TabRecord: Encodable, Sendable {
        let windowID: String
        let tabID: String
        let url: String
        let title: String
        let isLoading: Bool
        let isFocused: Bool
        let isPinned: Bool
        let link: MeetLink?
    }

    struct Sample: Encodable, Sendable {
        let variant: String
        let result: String
        let errorCode: Int?
        let errorMessage: String?
        let latencyMs: Double
        let tabs: [TabRecord]
    }

    public init() {}

    struct VariantChange: Encodable, Sendable {
        let from: String
        let to: String
        let reason: String
    }

    public func run(_ request: ProbeRequest, trace: TraceWriter, directory: URL) async {
        // `whose` or `loop` asked for explicitly is kept; otherwise `whose`, with a fallback to `loop`.
        // `whose-hors`: `whose`, run by osascript off the main thread (étape 1, task 1).
        let outOfProcess = request.variant == "whose-hors"
        let asked = outOfProcess ? .whose : DiaAdapter.Variant(rawValue: request.variant ?? "")
        let runScript = outOfProcess ? DiaAdapter.outOfProcessRunScript : DiaAdapter.mainThreadRunScript
        let label = { (variant: DiaAdapter.Variant) in outOfProcess ? "whose-hors" : variant.rawValue }
        var variant = asked ?? .whose
        var adapter = DiaAdapter(variant: variant, runScript: runScript)
        var failuresInARow = 0
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(request.seconds)

        while clock.now < deadline, !Task.isCancelled {
            let start = clock.now
            let result = await adapter.meetTabs()
            let latency = clock.now - start
            try? await trace.write(kind: "tabs", Self.sample(result, variant: label(variant), latency: latency))

            if case .failed = result { failuresInARow += 1 } else { failuresInARow = 0 }
            let next = asked == nil ? Self.variant(after: failuresInARow, current: variant) : variant
            if next != variant {
                try? await trace.write(kind: "tabs-variant", VariantChange(
                    from: variant.rawValue, to: next.rawValue, reason: "\(failuresInARow) échecs de suite"
                ))
                variant = next
                adapter = DiaAdapter(variant: next, runScript: runScript)
                failuresInARow = 0
            }
            guard await Self.keepGoing(trace, after: 1) else { break }
        }
    }

    /// Dia may refuse the `whose` filter: after three failed readings in a row, read tab by tab instead.
    static func variant(after failuresInARow: Int, current: DiaAdapter.Variant) -> DiaAdapter.Variant {
        current == .whose && failuresInARow >= 3 ? .loop : current
    }

    static func sample(_ result: TabProbeResult, variant: String, latency: Duration) -> Sample {
        let ms = Double(latency.components.seconds) * 1_000 + Double(latency.components.attoseconds) / 1e15
        func make(_ name: String, code: Int? = nil, message: String? = nil, tabs: [BrowserTab] = []) -> Sample {
            Sample(
                variant: variant, result: name, errorCode: code, errorMessage: message, latencyMs: ms,
                tabs: tabs.map {
                    TabRecord(
                        windowID: $0.windowID, tabID: $0.tabID, url: $0.url, title: $0.title,
                        isLoading: $0.isLoading, isFocused: $0.isFocused, isPinned: $0.isPinned,
                        link: MeetLink.parse($0.url)
                    )
                }
            )
        }
        switch result {
        case .tabs(let tabs): return make("tabs", tabs: tabs)
        case .partial(let tabs, let failures):
            return make("partial", code: failures.first?.code, message: failures.first?.message, tabs: tabs)
        case .browserNotRunning: return make("notRunning")
        case .permissionDenied: return make("denied")
        case .failed(let code, let message): return make("failed", code: code, message: message)
        }
    }
}
