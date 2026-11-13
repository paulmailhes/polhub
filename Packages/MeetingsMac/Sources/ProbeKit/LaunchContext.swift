import Foundation
import Observability

public enum LaunchOrigin: String, Codable, Sendable {
    /// Started by the relaunch agent: at login, or after a crash.
    case launchd
    /// Started by the person, by `open`, or from a terminal.
    case user
}

public enum LaunchContext {
    public static let agentLabel = "fr.paulmailhes.transcriptor.relance"
    public static let agentPlistName = "fr.paulmailhes.transcriptor.relance.plist"

    /// launchd sets `XPC_SERVICE_NAME` to the job's label for the processes it starts itself.
    public static func origin(environment: [String: String]) -> LaunchOrigin {
        environment["XPC_SERVICE_NAME"] == agentLabel ? .launchd : .user
    }

    public static var current: LaunchOrigin {
        origin(environment: ProcessInfo.processInfo.environment)
    }
}

/// `Mesures/lancements.jsonl`: one line per launch, per requested crash, per permission check after a
/// relaunch. It outlives the session folders, so a relaunch can be read against the crash before it.
public enum LaunchJournal {
    public static var fileURL: URL { TracePaths.root.appending(path: "lancements.jsonl") }

    public static func record<P: Encodable & Sendable>(_ kind: String, _ payload: P) async {
        guard let writer = try? TraceWriter(fileURL: fileURL) else { return }
        try? await writer.write(kind: kind, payload)
        await writer.close()
    }
}

/// What a copy of the app does when it starts.
public enum LaunchDecision: Equatable, Sendable {
    /// Another copy is already there: ask it to show its window, and leave.
    case yieldToRunningCopy
    case runProbe(ProbeRequest)
    case showWindow
    case stayInMenuBar
    /// The agent's copy found a copy Paul opened: it asks that one to quit, so that only one records.
    case askOtherCopyToQuit

    public static func decide(request: ProbeRequest?, origin: LaunchOrigin, anotherCopyIsRunning: Bool) -> LaunchDecision {
        // A probe asked on the command line always runs.
        if let request { return .runProbe(request) }
        // The agent's copy never yields: it is the only one launchd restarts after a crash.
        if origin == .launchd { return anotherCopyIsRunning ? .askOtherCopyToQuit : .stayInMenuBar }
        return anotherCopyIsRunning ? .yieldToRunningCopy : .showWindow
    }
}
