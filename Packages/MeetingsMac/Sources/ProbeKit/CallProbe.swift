import Foundation
import Observability
import Recording

/// The guided test call: the tabs probe, the audio-process probe and the capture that follows the route
/// all run together into one trace, while the window walks the person through the steps. Each step the
/// person moves to is written as a `marker`, so every measurement can be read against what was being done.
public struct CallProbe: Probe {
    struct Marker: Encodable, Sendable {
        let id: String
        let instruction: String
    }

    /// The probes run until the last step is reached; this only bounds a test left unattended.
    static let ceilingSeconds = 6 * 3_600

    public init() {}

    public func run(_ request: ProbeRequest, trace: TraceWriter, directory: URL) async {
        let advances = await ProtocolBoard.shared.begin()
        let steps = await ProtocolBoard.shared.steps
        let long = ProbeRequest(probe: .call, seconds: Self.ceilingSeconds, variant: request.variant)
        let rig = CaptureEngine(variant: .parse(request.variant), directory: directory, trace: trace)

        try? await trace.write(kind: "marker", Marker(id: steps[0].id, instruction: steps[0].instruction))

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await TabsProbe().run(long, trace: trace, directory: directory) }
            group.addTask { await MicHoldersProbe().run(long, trace: trace, directory: directory) }
            group.addTask { await CaptureSupervisor(engine: rig, trace: trace).run(seconds: Self.ceilingSeconds) }
            // A trace that can no longer be written ends the call: the window must not keep guiding
            // someone through steps that record nothing.
            group.addTask {
                while await Self.keepGoing(trace, after: 1) {}
                if await trace.failure != nil { await ProtocolBoard.shared.end() }
            }

            for await index in advances {
                try? await trace.write(kind: "marker", Marker(id: steps[index].id, instruction: steps[index].instruction))
                if index == steps.count - 1 { break }
            }
            // The last step was reached, or the probe was stopped: the three recorders wind down.
            group.cancelAll()
        }
        await ProtocolBoard.shared.end()
    }
}
