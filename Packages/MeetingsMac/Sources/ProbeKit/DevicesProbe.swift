import Foundation
import Observability
import Recording

/// A capture that follows the audio route: it logs every Core Audio route notification, rebuilds a track
/// only when the route that track really uses changes, and measures the holes.
public struct DevicesProbe: Probe {
    public init() {}

    public func run(_ request: ProbeRequest, trace: TraceWriter, directory: URL) async {
        let engine = CaptureEngine(variant: .parse(request.variant), directory: directory, trace: trace)
        await CaptureSupervisor(engine: engine, trace: trace).run(seconds: request.seconds)
    }
}
