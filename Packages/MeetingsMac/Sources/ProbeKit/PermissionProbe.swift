import AppKit
import Foundation
import Observability
import Recording

/// The state of the three permissions, read by their effect wherever macOS offers no way to ask.
public struct PermissionReport: Equatable, Sendable, Codable {
    /// `authorized`, `denied`, `notDetermined` or `restricted`.
    public let microphone: String
    /// `granted`, `denied`, `wouldPrompt`, `notRunning` or `error:<code>`.
    public let appleEventsDia: String
    /// `nonZero` (the tap hears this app's own tone), `allZero`, `startFailed:<status>` or `notTested`.
    public let systemAudio: String
    /// Status returned when a tap's description is written back to it; phase 0 checks whether it tells
    /// a missing permission apart without playing any sound.
    public let tapDescriptionStatus: Int32?
    public let launchOrigin: LaunchOrigin
    public let designatedRequirement: String
}

/// Publishes the latest report to the probes window.
@MainActor
public final class PermissionBoard: ObservableObject {
    public static let shared = PermissionBoard()
    @Published public private(set) var latest: PermissionReport?

    func publish(_ report: PermissionReport) {
        latest = report
    }
}

@MainActor
public enum PermissionProbe {
    /// The three permissions, with the copy that asked, published to the probes window.
    public static func run(prompt: Bool, testSystemAudio: Bool, amplitude: Float = 0.0316) async -> PermissionReport {
        let status = await PermissionCheck.run(prompt: prompt, testSystemAudio: testSystemAudio, amplitude: amplitude)
        let report = PermissionReport(
            microphone: status.microphone,
            appleEventsDia: status.appleEventsDia,
            systemAudio: status.systemAudio,
            tapDescriptionStatus: status.tapDescriptionStatus,
            launchOrigin: LaunchContext.current,
            designatedRequirement: status.designatedRequirement
        )
        PermissionBoard.shared.publish(report)
        return report
    }
}

/// `--probe permissions`: `--variant status` (default) reads the three permissions without asking;
/// `prompt` lets macOS ask; `crash` aborts the app, to measure the relaunch agent.
public struct PermissionsProbe: Probe {
    struct CrashRequest: Encodable, Sendable {
        let pid: Int32
        let origin: LaunchOrigin
    }

    public init() {}

    public func run(_ request: ProbeRequest, trace: TraceWriter, directory: URL) async {
        switch request.variant {
        case "crash":
            await Self.crashNow()
        case "inaudible":
            let report = await PermissionProbe.run(prompt: false, testSystemAudio: true, amplitude: SystemAudioSelfTest.inaudibleAmplitude)
            try? await trace.write(kind: "permissions", report)
        default:
            let report = await PermissionProbe.run(prompt: request.variant == "prompt", testSystemAudio: true)
            try? await trace.write(kind: "permissions", report)
        }
    }

    /// Writes the request to the launch journal, then dies the way a crash does.
    public static func crashNow() async -> Never {
        await LaunchJournal.record("crash-requested", CrashRequest(pid: getpid(), origin: LaunchContext.current))
        abort()
    }
}
