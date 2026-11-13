import AppKit
import AVFoundation
import CoreAudio
import Foundation
import MeetingDetection
import Security

/// The state of the three permissions, read by their effect wherever macOS offers no way to ask.
public struct PermissionStatus: Equatable, Sendable, Codable {
    /// `authorized`, `denied`, `notDetermined` or `restricted`.
    public let microphone: String
    /// `granted`, `denied`, `wouldPrompt`, `notRunning` or `error:<code>`.
    public let appleEventsDia: String
    /// `nonZero` (the tap hears this app's own tone), `allZero`, `startFailed:<status>` or `notTested`.
    public let systemAudio: String
    public let tapDescriptionStatus: Int32?
    public let designatedRequirement: String
}

@MainActor
public enum PermissionCheck {
    /// `prompt` lets macOS ask for what is not decided yet. `testSystemAudio` plays a faint tone for up to
    /// two seconds (thirty when prompting) and checks that a tap on this app hears it.
    public static func run(prompt: Bool, testSystemAudio: Bool, amplitude: Float = 0.0316) async -> PermissionStatus {
        var microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        if prompt, microphone == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        }

        // Both of these block while macOS shows its question: never on the main thread.
        let appleEvents = await Task.detached { appleEventsStatus(prompt: prompt) }.value
        let audio: SystemAudioSelfTest.Outcome = testSystemAudio
            ? await Task.detached { SystemAudioSelfTest.run(rounds: prompt ? 10 : 1, amplitude: amplitude) }.value
            : .init(result: "notTested", tapDescriptionStatus: nil)

        return PermissionStatus(
            microphone: name(ofMicrophoneStatus: microphone.rawValue),
            appleEventsDia: appleEvents,
            systemAudio: audio.result,
            tapDescriptionStatus: audio.tapDescriptionStatus,
            designatedRequirement: designatedRequirement()
        )
    }

    public nonisolated static func name(ofMicrophoneStatus raw: Int) -> String {
        switch raw {
        case 0: "notDetermined"
        case 1: "restricted"
        case 2: "denied"
        case 3: "authorized"
        default: "unknown:\(raw)"
        }
    }

    public nonisolated static func name(ofAppleEventsStatus status: Int) -> String {
        switch status {
        case 0: "granted"
        case -1743: "denied"          // errAEEventNotPermitted
        case -1744: "wouldPrompt"     // errAEEventWouldRequireUserConsent
        case -600: "notRunning"       // procNotFound
        default: "error:\(status)"
        }
    }

    /// Never sent while Dia is not running: it would launch it.
    public nonisolated static func appleEventsStatus(prompt: Bool) -> String {
        guard DiaAdapter.systemIsRunning() else { return "notRunning" }
        let target = NSAppleEventDescriptor(bundleIdentifier: DiaAdapter.diaBundleID)
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, prompt)
        return name(ofAppleEventsStatus: Int(status))
    }

    public nonisolated static func designatedRequirement() -> String {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        var text: CFString?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement,
              SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text
        else { return "illisible" }
        return text as String
    }
}
