import Foundation
import Observability
import Recording

/// Records Dia's sound (and the microphone, when Dia holds one) with one tap variant, and writes a
/// level report every second. `--variant A|B|C|D`, optionally `+sortie`. It never rebuilds anything.
public struct CaptureProbe: Probe {
    public init() {}

    public func run(_ request: ProbeRequest, trace: TraceWriter, directory: URL) async {
        let rig = CaptureEngine(variant: .parse(request.variant), directory: directory, trace: trace)
        guard rig.start() else {
            rig.stop()   // the microphone may have started before the tap failed
            _ = await Self.pause(0.2)
            return
        }

        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(request.seconds)
        var lastCheck = clock.now
        while clock.now < deadline, !Task.isCancelled {
            if clock.now - lastCheck >= .seconds(1) {
                lastCheck = clock.now
                rig.reportSilentTracks()
            }
            guard await Self.keepGoing(trace, after: 0.25) else { break }
        }
        rig.stop()
        // Lets the last reports, written from the recorder threads, reach the trace before it is closed.
        _ = await Self.pause(0.2)
    }
}
