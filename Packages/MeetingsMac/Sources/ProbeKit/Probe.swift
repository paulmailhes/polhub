import Foundation
import Observability

/// A measurement run. It writes its findings to `trace` and its files under `directory`.
/// It returns after `request.seconds`, or earlier when its Swift task is cancelled.
public protocol Probe: Sendable {
    func run(_ request: ProbeRequest, trace: TraceWriter, directory: URL) async
}

public enum ProbeRegistry {
    /// Returns nil while a probe is not implemented yet.
    @MainActor public static func make(_ id: ProbeID) -> (any Probe)? {
        switch id {
        case .permissions: PermissionsProbe()
        case .tabs: TabsProbe()
        case .micHolders: MicHoldersProbe()
        case .capture: CaptureProbe()
        case .devices: DevicesProbe()
        case .hud: HUDProbe()
        case .crashWriter: CrashWriterProbe()
        case .call: CallProbe()
        case .record: RecordProbe()
        case .pipeline: PipelineProbe()
        }
    }
}

extension Probe {
    /// Sleeps up to `seconds`; returns false when the task was cancelled meanwhile.
    static func pause(_ seconds: Double) async -> Bool {
        do {
            try await Task.sleep(for: .seconds(seconds))
            return true
        } catch {
            return false
        }
    }

    /// Sleeps, then says whether to go on: false when the task was cancelled, or when the trace can no
    /// longer be written. A probe never goes on measuring into the void.
    static func keepGoing(_ trace: TraceWriter, after seconds: Double) async -> Bool {
        guard await pause(seconds) else { return false }
        return await trace.failure == nil
    }
}
