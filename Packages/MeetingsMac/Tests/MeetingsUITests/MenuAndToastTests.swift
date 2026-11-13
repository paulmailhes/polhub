import AppKit
import Foundation
import Pipeline
import Testing
@testable import MeetingsUI

@MainActor @Suite struct MenuAndToastTests {
    @Test func durationsReadLikeAClock() {
        #expect(DurationText.clock(0) == "0:00")
        #expect(DurationText.clock(754) == "12:34")
        #expect(DurationText.clock(3723) == "1:02:03")
        #expect(DurationText.short(2520) == "42 min")
        #expect(DurationText.short(3900) == "1 h 05")
        #expect(DurationText.short(20) == "moins d'une minute")
    }

    @Test func theMenuBarShowsARedClockWhileRecording() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(MenuBarLabel.make(status: .recording(title: "Point", since: now.addingTimeInterval(-754)), attention: false, now: now)
            == MenuBarLabel(symbol: "record.circle.fill", text: "12:34"))
        #expect(MenuBarLabel.make(status: .idle, attention: false, now: now) == MenuBarLabel(symbol: "waveform", text: nil))
        #expect(MenuBarLabel.make(status: .idle, attention: true, now: now) == MenuBarLabel(symbol: "exclamationmark.triangle", text: nil))
        #expect(MenuBarLabel.make(status: .paused(until: now), attention: false, now: now) == MenuBarLabel(symbol: "pause.circle", text: nil))
    }

    @Test func aToastWaitsForThePromptToClose() {
        var queue = HUDQueue()
        let prompt = HUDContent.prompt(title: "Point", deadline: Date(timeIntervalSince1970: 0))
        let toast = HUDContent.toast(title: "L'enregistrement continue", subtitle: "Micro : Casque")
        #expect(queue.enqueue(prompt) == prompt)
        #expect(queue.enqueue(toast) == nil)
        #expect(queue.closed() == toast)
        #expect(queue.closed() == nil)
    }

    @Test func deviceChangesWithinTwoSecondsMakeOneToast() {
        var coalescer = ToastCoalescer()
        coalescer.add(.devices(mic: "Casque", output: nil), at: 10.0)
        coalescer.add(.devices(mic: "AirPods", output: nil), at: 10.8)
        coalescer.add(.devices(mic: "Micro du Mac", output: "Haut-parleurs"), at: 11.5)
        #expect(coalescer.due(at: 12.0) == nil)
        #expect(coalescer.due(at: 13.5) == .devices(mic: "Micro du Mac", output: "Haut-parleurs"))
        #expect(coalescer.due(at: 20) == nil)
    }

    @Test func toastsAndAlertsSayWhatThePlanSays() {
        #expect(HUDText.toast(.devices(mic: "Casque", output: "Haut-parleurs")) == ("L'enregistrement continue", "Micro : Casque · Sortie : Haut-parleurs"))
        #expect(HUDText.toast(.ended(title: "Point hebdo", seconds: 2520)) == ("Réunion enregistrée", "Point hebdo · 42 min"))
        #expect(HUDText.alert(.diskLow(freeGB: 15)).message == "Il reste 15 Go. Une heure de réunion en prend environ 1,4.")
        #expect(HUDText.alert(.selfTestFailed).title == "Le son des autres n'est pas capté")
    }

    // Review Focus 5
    @Test func thePromptPanelNeverTakesTheFocus() {
        _ = NSApplication.shared
        let panel = HUDPanelController.makePanel(style: .production)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.level == .statusBar)
        #expect(panel.collectionBehavior.contains([.canJoinAllSpaces, .fullScreenAuxiliary]))
        #expect(panel.becomesKeyOnlyIfNeeded)
    }
}
