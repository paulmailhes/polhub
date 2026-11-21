import AppKit
import Domain
import Foundation
import Recording
import SwiftUI
import Testing
@testable import MeetingsUI

/// Le guide, le Diagnostic et la Bienvenue des add-ons, en capture (21/11). Données inventées.
/// `HUB_LIVE=1 HUB_SNAPSHOTS=<dossier> swift test --filter AddOnsScreenTests`.
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["HUB_LIVE"] == "1")) struct AddOnsScreenTests {
    @Test func theGuideTheDiagnosticAndTheWelcome() async throws {
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["HUB_SNAPSHOTS"]), isDirectory: true)
        let store = AddOnStore(defaults: try #require(UserDefaults(suiteName: "addons-captures-\(UUID().uuidString)")))
        store.save([.projects, .dictation, .calendar, .mails, .inspiration])
        store.setPendingGuide([.dictation, .calendar, .mails], welcome: true)
        let control = AddOnControl(store: store, isBusy: { false }, relaunch: {})
        var facts = AddOnFacts()
        facts.accessibility = false
        facts.googleAccounts = 1
        control.facts = { facts }
        control.claudeFound = false
        // The add-ons' lines are on Réglages' home since 21/11: SettingsScreenTests captures it (« reglages-familles »).
        control.openPendingGuide()
        try await LiveWindow.capture(AddOnGuideSheet(control: control), to: folder.appending(path: "addons-guide.png"),
                                     size: NSSize(width: 540, height: 430), wait: .milliseconds(900))
        // The Diagnostic's list (21/11): each need once, for whom, with its button.
        let model = DiagnosticModel(amplitude: 0.0000316, showsRelaunch: true, relaunchEnabled: { true }, setRelaunch: { _ in nil },
                                    missingModels: { [] })
        for item in [ChecklistItem.microphone, .systemAudio, .models, .relaunch] { model.set(item, .ok) }
        model.set(.diaAutomation, .notRunning)
        try await LiveWindow.capture(DiagnosticView(model: model, connections: control) {}, to: folder.appending(path: "diagnostic-connexions.png"),
                                     size: NSSize(width: 760, height: 760), wait: .milliseconds(1_200))
        try await LiveWindow.capture(WelcomeSheet(control: control), to: folder.appending(path: "bienvenue-1.png"),
                                     size: NSSize(width: 680, height: 400), wait: .milliseconds(900))
        try await LiveWindow.capture(WelcomeSheet(control: control, step: 2, chosen: [.meetings]), to: folder.appending(path: "bienvenue-2.png"),
                                     size: NSSize(width: 680, height: 640), wait: .milliseconds(900))
    }
}
