import AppKit
import ApplicationServices
import AVFoundation
import Domain
import GoogleKit
import HubDesign
import Transcription
import VigieKit

/// What the app gives the Add-ons page (21/11): what this Mac has, and what a need's button does.
@MainActor public enum AddOnWiring {
    /// Read each time a tile asks: an authorization given in Réglages Système shows within two seconds.
    public static func facts(agenda: AgendaLibrary?, mails: MailLibrary?, phone: PhoneAccess?, claudeFound: Bool,
                             meetingsChecked: Bool, vigie: VigieLibrary? = nil) -> AddOnFacts {
        var facts = AddOnFacts()
        facts.modelsReady = ModelLocations.standard.missing().isEmpty
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: facts.microphone = .granted
        case .notDetermined: facts.microphone = .notAsked
        default: facts.microphone = .denied
        }
        facts.accessibility = AXIsProcessTrusted()
        facts.meetingsChecked = meetingsChecked
        facts.googleKey = FileManager.default.fileExists(atPath: GoogleClientConfig.file.path(percentEncoded: false))
        facts.googleAccounts = agenda?.accounts.count ?? 0
        facts.mailboxes = mails?.accounts.count ?? 0
        facts.claudeFound = claudeFound
        facts.colinOn = (UserDefaults.standard.object(forKey: Preferences.Key.colinOn) as? Bool) ?? false
        facts.iCloud = FileManager.default.ubiquityIdentityToken != nil
        facts.phones = phone?.devices.filter { $0.lastSeenAt != nil }.count ?? 0
        facts.vigieInstalled = VigieEngine().isInstalled
        // Not installed in hub: nothing asks the engine, the file alone says it is there.
        facts.vigieRunning = vigie.map { $0.link == .running } ?? facts.vigieInstalled
        return facts
    }

    public static func perform(_ action: AddOnAction, agenda: AgendaLibrary?, dictation: DictationService?, router: WindowRouter) {
        switch action {
        case .askMicrophone:
            // macOS asks once; after a refusal, only Réglages Système gives it back.
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { _ in }
            } else {
                open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
            }
        case .askAccessibility:
            if let dictation {
                dictation.askAccessibility()
            } else if !AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) {
                open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            }
        case .openDiagnostic:
            router.openSettings(.diagnostic)
        case .connectGoogle:
            Task { await agenda?.connect() }
        case .openGoogleAccounts:
            router.openSettings(.accounts)
        case .openColin:
            router.openSettings(.colin)
        case .openPhone:
            router.openSettings(.iphone)
        }
    }

    /// « Ses réglages » on a tile.
    public static func openSettings(of addOn: AddOn, router: WindowRouter) {
        guard let pane = addOn.settings else { return }
        router.openSettings(pane)
    }

    private static func open(_ address: String) {
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }
}
