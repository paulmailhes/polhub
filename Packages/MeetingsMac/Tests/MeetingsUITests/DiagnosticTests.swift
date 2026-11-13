import Foundation
import Testing
@testable import MeetingsUI

@MainActor @Suite struct DiagnosticTests {
    @Test func checksReplayWhenMacOSOrDiaChanges() {
        let now = VersionPair(macOS: "27.0.1", dia: "1.12.0")
        #expect(DiagnosticTrigger.shouldReplay(last: nil, current: now))
        #expect(!DiagnosticTrigger.shouldReplay(last: now, current: now))
        #expect(DiagnosticTrigger.shouldReplay(last: VersionPair(macOS: "27.0.1", dia: "1.11.3"), current: now))
        #expect(DiagnosticTrigger.shouldReplay(last: VersionPair(macOS: "27.0", dia: "1.12.0"), current: now))
    }

    @Test func allGoodNeedsEveryLine() {
        let model = DiagnosticModel(amplitude: 0.0000316, showsRelaunch: true, relaunchEnabled: { false }, setRelaunch: { _ in nil })
        for item in [ChecklistItem.microphone, .systemAudio, .diaAutomation, .models] { model.set(item, .ok) }
        model.set(.relaunch, .missing)
        #expect(!model.allGood)
        model.set(.relaunch, .ok)
        #expect(model.allGood)

        let dev = DiagnosticModel(amplitude: 0.0000316, showsRelaunch: false, relaunchEnabled: { false }, setRelaunch: { _ in nil })
        for item in [ChecklistItem.microphone, .systemAudio, .diaAutomation, .models] { dev.set(item, .ok) }
        #expect(dev.allGood)
    }

    @Test func theChecklistNamesMissingModels() async {
        let model = DiagnosticModel(amplitude: 0.0000316, showsRelaunch: false, relaunchEnabled: { false }, setRelaunch: { _ in nil },
                                    missingModels: { ["détecteur de voix (Silero)"] })
        #expect(model.items.contains(.models))
        await model.test(.models, prompt: false)
        #expect(model.states[.models] == .denied("Manque : détecteur de voix (Silero)"))
        let complete = DiagnosticModel(amplitude: 0.0000316, showsRelaunch: false, relaunchEnabled: { false }, setRelaunch: { _ in nil },
                                       missingModels: { [] })
        await complete.test(.models, prompt: false)
        #expect(complete.states[.models] == .ok)
        // Models are not a permission: a replay after an update does not count them.
        for item in [ChecklistItem.microphone, .systemAudio, .diaAutomation] { model.set(item, .ok) }
        #expect(model.permissionsGood && !model.allGood)
    }

    @Test func permissionAnswersBecomeStates() {
        #expect(DiagnosticModel.state(.microphone, from: "authorized") == .ok)
        #expect(DiagnosticModel.state(.microphone, from: "notDetermined") == .missing)
        #expect(DiagnosticModel.state(.systemAudio, from: "nonZero") == .ok)
        #expect(DiagnosticModel.state(.systemAudio, from: "allZero") == .denied("Le son n'est pas capté"))
        #expect(DiagnosticModel.state(.diaAutomation, from: "wouldPrompt") == .missing)
        #expect(DiagnosticModel.state(.diaAutomation, from: "notRunning") == .denied("Dia n'est pas ouvert"))
    }

    // Revue finale, mineur relevé : après une mise à jour, « Dia fermé » ou la relance décochée ne sont pas une autorisation perdue.
    @Test func aReplayOnlyCountsPermissions() {
        let model = DiagnosticModel(amplitude: 0.0000316, showsRelaunch: true, relaunchEnabled: { false }, setRelaunch: { _ in nil })
        model.set(.microphone, .ok)
        model.set(.systemAudio, .ok)
        model.set(.diaAutomation, .denied("Dia n'est pas ouvert"))
        model.set(.relaunch, .missing)
        #expect(model.permissionsGood)
        model.set(.diaAutomation, .denied("denied"))
        #expect(!model.permissionsGood)
    }
}
