import Foundation
import Persistence
import PolhubDesign
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
        // Dia closed is a state of its own, said in words beside it (lot 10, 20/11).
        #expect(DiagnosticModel.state(.diaAutomation, from: "notRunning") == .notRunning)
        #expect(ItemState.notRunning.reason == "Dia n'est pas ouvert" && ItemState.denied("refusé").reason == "refusé" && ItemState.ok.reason == nil)
    }

    /// Only a fresh check of the others' sound is told (finding of 16/11): an earlier « ok » left in the list says
    /// nothing when another line is checked again, so the self-test's badge never goes on it.
    @Test func onlyAFreshCheckOfTheOthersSoundIsTold() async {
        let heard = Heard()
        let model = DiagnosticModel(amplitude: 0.0000316, showsRelaunch: true, relaunchEnabled: { true }, setRelaunch: { _ in nil },
                                    missingModels: { [] })
        model.systemAudioChecked = { heard.states.append($0) }
        // A check earlier in the session.
        model.set(.systemAudio, .ok)
        #expect(heard.states == [.ok])
        // The other lines, checked again (« Tout revérifier » starts with them, « Tester », the relaunch switch).
        await model.test(.relaunch, prompt: false)
        await model.test(.models, prompt: false)
        model.toggleRelaunch(false)
        model.set(.microphone, .ok)
        #expect(heard.states == [.ok])
        #expect(model.states[.systemAudio] == .ok)
        // The fresh check says it is not captured: told too.
        model.set(.systemAudio, .denied("Le son n'est pas capté"))
        #expect(heard.states == [.ok, .denied("Le son n'est pas capté")])
    }

    // Revue finale, mineur relevé : après une mise à jour, « Dia fermé » ou la relance décochée ne sont pas une autorisation perdue.
    @Test func aReplayOnlyCountsPermissions() {
        let model = DiagnosticModel(amplitude: 0.0000316, showsRelaunch: true, relaunchEnabled: { false }, setRelaunch: { _ in nil })
        model.set(.microphone, .ok)
        model.set(.systemAudio, .ok)
        model.set(.diaAutomation, .notRunning)
        model.set(.relaunch, .missing)
        #expect(model.permissionsGood)
        model.set(.diaAutomation, .denied("denied"))
        #expect(!model.permissionsGood)
    }
}

@MainActor final class Heard {
    var states: [ItemState] = []
}

/// Lot 10 (20/11): a problem's screen says Polhub's words; the system's own go to the journal of Réglages.
@Suite struct ProblemJournalTests {
    @Test func theSystemsWordsGoToTheJournal() throws {
        let database = try AppDatabase.inMemory()
        let offline = Words.problem("Le fil n'a pas pu être rangé", URLError(.notConnectedToInternet))
        database.journal(offline, at: Date(timeIntervalSince1970: 1_794_992_400))
        let entries = try MeetingStore(database).journal(limit: 10)
        #expect(entries.count == 1 && entries.first?.kind == .alert)
        #expect(entries.first?.message.hasPrefix("Le fil n'a pas pu être rangé : ") == true && entries.first?.message.contains("NSURLErrorDomain") == true)
        // Nothing for a problem without the system's words.
        database.journal(Words.problem("Le fil n'a pas pu être rangé"))
        #expect(try MeetingStore(database).journal(limit: 10).count == 1)
    }
}
