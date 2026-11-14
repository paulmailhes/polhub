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
        // 14/11: at rest, the app's own columns, in outline.
        #expect(MenuBarLabel.make(status: .idle, attention: false, now: now) == MenuBarLabel(symbol: MenuBarLabel.appGlyph, text: nil))
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

/// The menu bar's own icon: the three columns of Polhub's icon, in outline (Paul, 14/11).
@MainActor @Suite struct MenuBarGlyphTests {
    @Test func theColumnsAreATemplateImageOfTheMenuBarsHeight() throws {
        let image = MenuBarGlyph.image()
        #expect(image.isTemplate)
        #expect(image.size.height == 16 && image.size.width == 18)
        let rects = MenuBarGlyph.columns(in: NSRect(x: 0, y: 0, width: 18, height: 16))
        #expect(rects.count == 3)
        // The icon's proportions: the first the tallest, the middle one the shortest.
        #expect(rects[0].height > rects[2].height)
        #expect(rects[2].height > rects[1].height)
        #expect(rects.allSatisfy { $0.minX >= 0 && $0.maxX <= 18 && $0.minY >= 0 && $0.maxY <= 16 })
    }
}
