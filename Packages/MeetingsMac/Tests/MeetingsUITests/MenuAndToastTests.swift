import AppKit
import Foundation
import Pipeline
import SwiftUI
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
        let recording = RecorderStatus.recording(title: "Point", since: now.addingTimeInterval(-754))
        #expect(MenuBarLabel.make(status: recording, now: now) == MenuBarLabel(icon: .recording, text: "12:34"))
        // Nothing else shows over a recording: neither the badge nor the minutes before a Meet.
        #expect(MenuBarLabel.make(status: recording, now: now, minutesToMeet: 8, danger: true) == MenuBarLabel(icon: .recording, text: "12:34"))
    }

    // « Coup d'œil » (15/11): filled, Polhub watches for meetings; in outline, it does not.
    @Test func atRestTheColumnsAreFilled() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(MenuBarLabel.make(status: .idle, now: now) == MenuBarLabel(icon: .columns(.filled, badge: false), text: nil))
        #expect(MenuBarLabel.make(status: .idle, now: now, minutesToMeet: 8) == MenuBarLabel(icon: .columns(.filled, badge: false), text: "8 min"))
    }

    @Test func detectionPausedOrTheDevelopmentBuildShowTheColumnsInOutline() {
        let now = Date(timeIntervalSince1970: 10_000)
        let outline = MenuBarLabel(icon: .columns(.outline, badge: false), text: nil)
        #expect(MenuBarLabel.make(status: .paused(until: now.addingTimeInterval(600)), now: now, minutesToMeet: 8) == outline)
        #expect(MenuBarLabel.make(status: .idle, now: now, minutesToMeet: 8, isDevelopment: true) == outline)
        // Before launch ends, detection is not on yet.
        #expect(MenuBarLabel.make(status: .idle, now: now, watching: false) == outline)
    }

    @Test func aDetectedMeetingCountsDownAsThePopUpDoes() {
        let now = Date(timeIntervalSince1970: 10_000)
        let prompting = RecorderStatus.prompting(title: "Point")
        #expect(MenuBarLabel.make(status: prompting, now: now, promptDeadline: now.addingTimeInterval(6.2))
            == MenuBarLabel(icon: .listening, text: "7 s"))
        #expect(MenuBarLabel.make(status: prompting, now: now, promptDeadline: now.addingTimeInterval(-1)) == MenuBarLabel(icon: .listening, text: "0 s"))
        #expect(MenuBarLabel.make(status: prompting, now: now) == MenuBarLabel(icon: .listening, text: nil))
        // The same number as the HUD: rounded up.
        #expect(HUDText.remaining(until: now.addingTimeInterval(6.2), now: now) == 7)
        // Over the minutes before a Meet and over the badge.
        #expect(MenuBarLabel.make(status: prompting, now: now, promptDeadline: now.addingTimeInterval(9), minutesToMeet: 3, danger: true)
            == MenuBarLabel(icon: .listening, text: "9 s"))
        #expect(MenuBarLabel.make(status: .presumedEnded(title: "Point"), now: now, minutesToMeet: 3) == MenuBarLabel(icon: .listening, text: "fin ?"))
    }

    @Test func aRecordingAtRiskAddsTheBadgeToTheColumns() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(MenuBarLabel.make(status: .idle, now: now, minutesToMeet: 8, danger: true) == MenuBarLabel(icon: .columns(.filled, badge: true), text: "8 min"))
        #expect(MenuBarLabel.make(status: .paused(until: now), now: now, danger: true) == MenuBarLabel(icon: .columns(.outline, badge: true), text: nil))
        #expect(MenuBarLabel.make(status: .idle, now: now, danger: true, isDevelopment: true) == MenuBarLabel(icon: .columns(.outline, badge: true), text: nil))
    }

    @Test func theMinutesShowInTheQuarterOfAnHourBeforeAMeet() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(MenuBarLabel.minutes(before: now.addingTimeInterval(7 * 60 + 10), now: now) == 8)
        #expect(MenuBarLabel.minutes(before: now.addingTimeInterval(15 * 60), now: now) == 15)
        #expect(MenuBarLabel.minutes(before: now.addingTimeInterval(15 * 60 + 1), now: now) == nil)
        #expect(MenuBarLabel.minutes(before: now.addingTimeInterval(20), now: now) == 1)
        #expect(MenuBarLabel.minutes(before: now, now: now) == nil)
        #expect(MenuBarLabel.minutes(before: nil, now: now) == nil)
    }

    @Test func theImagesAreTemplatesExceptTheRecordingsRed() {
        _ = NSApplication.shared
        #expect(MenuBarLabel(icon: .recording, text: nil).image.isTemplate == false)
        #expect(MenuBarLabel(icon: .listening, text: nil).image.isTemplate)
        #expect(MenuBarLabel(icon: .columns(.filled, badge: true), text: nil).image.isTemplate)
    }

    /// The menu bar asks for its label twice a second: each look is drawn once, the circle of a detected meeting
    /// too (finding of 16/11), so its image changes only with the state.
    @Test func eachLookIsDrawnOnce() {
        _ = NSApplication.shared
        for icon in [MenuBarLabel.Icon.recording, .listening, .columns(.filled, badge: false), .columns(.outline, badge: true)] {
            #expect(MenuBarLabel(icon: icon, text: nil).image === MenuBarLabel(icon: icon, text: "7 s").image)
        }
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

    /// The HUD as tall as its words (lot 9, 20/11): in the panel's 15 and 13 points, a prompt keeps its 76 points, and a
    /// long alert takes two lines for its title and two for its explanation instead of « Polhub ne lit plus les… ».
    @Test func theHUDIsAsTallAsItsWords() {
        _ = NSApplication.shared
        func size(_ kind: HUDModel.Kind, _ title: String, _ subtitle: String, action: String = "") -> CGSize {
            let model = HUDModel()
            model.kind = kind
            model.title = title
            model.subtitle = subtitle
            model.actionTitle = action
            model.remaining = 7
            return HUDPanelController.size(fitting: NSHostingView(rootView: HUDView(model: model)))
        }
        #expect(size(.prompt, HUDText.promptTitle("Point"), "") == HUDPanelController.panelSize)
        #expect(size(.toast, "Réunion enregistrée", "Point hebdo · 42 min") == HUDPanelController.panelSize)
        let alert = HUDText.alert(.tabsUnreadable)
        let tall = size(.alert, alert.title, alert.message, action: alert.action)
        #expect(tall.width == HUDPanelController.panelSize.width && tall.height > 76 && tall.height <= HUDPanelController.maxHeight, "\(tall)")
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

/// The menu bar's own icon: the three columns of Polhub's icon (Paul, 14/11), filled at rest, in outline when Polhub
/// does not watch, with a cut-out badge when a recording is at risk (« Coup d'œil », 15/11).
@MainActor @Suite struct MenuBarGlyphTests {
    @Test func theColumnsAreATemplateImageOfTheMenuBarsHeight() throws {
        for style in [MenuBarGlyph.Style.filled, .outline] {
            for badge in [false, true] {
                let image = MenuBarGlyph.image(style: style, badge: badge)
                #expect(image.isTemplate)
                // The badge spills past the corner: its image is wider.
                #expect(image.size.height == 16 && image.size.width == (badge ? 22 : 18))
            }
        }
        let rects = MenuBarGlyph.columns(in: NSRect(x: 0, y: 0, width: 18, height: 16))
        #expect(rects.count == 3)
        // The icon's proportions: the first the tallest, the middle one the shortest.
        #expect(rects[0].height > rects[2].height)
        #expect(rects[2].height > rects[1].height)
        #expect(rects.allSatisfy { $0.minX >= 0 && $0.maxX <= 18 && $0.minY >= 0 && $0.maxY <= 16 })
    }

    /// The image drawn at 4 pixels per point: the ink at a point, from 0 to 1.
    private func ink(style: MenuBarGlyph.Style, badge: Bool) throws -> (CGFloat, CGFloat) -> CGFloat {
        let scale: CGFloat = 4
        let size = MenuBarGlyph.size(badge: badge)
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        MenuBarGlyph.image(style: style, badge: badge).draw(in: NSRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
        NSGraphicsContext.restoreGraphicsState()
        // AppKit's points count from the bottom, the bitmap's rows from the top.
        return { x, y in rep.colorAt(x: Int(x * scale), y: Int((16 - y) * scale))?.alphaComponent ?? 0 }
    }

    @Test func filledTheColumnsAreInkedThrough() throws {
        let column = MenuBarGlyph.columns(in: NSRect(x: 0, y: 0, width: 18, height: 16))[0]
        let filled = try ink(style: .filled, badge: false)
        let outline = try ink(style: .outline, badge: false)
        #expect(filled(column.midX, column.midY) > 0.9)
        // In outline, the middle of a column is empty and its edge inked.
        #expect(outline(column.midX, column.midY) < 0.1)
        #expect(outline(column.minX + 0.6, column.midY) > 0.5)
        // Rounded at 0.3 of the width: the very corner stays empty.
        #expect(filled(column.minX + 0.1, column.maxY - 0.1) < 0.5)
    }

    @Test func theBadgeIsCutOutOfTheColumns() throws {
        let plain = try ink(style: .filled, badge: false)
        let badged = try ink(style: .filled, badge: true)
        let center = MenuBarGlyph.badgeCenter
        #expect(badged(center.x, center.y) > 0.9)
        // A ring cut around it, on its side of the third column, where the column was inked.
        let ring = NSPoint(x: center.x - MenuBarGlyph.badgeRadius - MenuBarGlyph.badgeGap / 2, y: center.y)
        #expect(plain(ring.x, ring.y) > 0.9)
        #expect(badged(ring.x, ring.y) < 0.2)
        // The first two columns are untouched.
        let columns = MenuBarGlyph.columns(in: NSRect(x: 0, y: 0, width: 18, height: 16))
        #expect(badged(columns[0].midX, columns[0].maxY - 1) > 0.9)
        #expect(badged(columns[1].maxX - 0.3, columns[1].maxY - 1.5) > 0.9)
    }

    /// The badge sits on the corner, mostly outside the third column, which keeps its full height: centred on it, the
    /// column became a stem under a dot, an « i » at real size (finding of 16/11).
    @Test func theBadgeSitsOnTheCornerNotOnTheColumn() throws {
        let badged = try ink(style: .filled, badge: true)
        let third = MenuBarGlyph.columns(in: NSRect(x: 0, y: 0, width: 18, height: 16))[2]
        #expect(MenuBarGlyph.badgeCenter.x > third.maxX)
        // The column's left edge still reaches its top, beside the badge.
        #expect(badged(third.minX + 0.6, third.maxY - 1.2) > 0.5)
        #expect(badged(third.minX + 0.6, third.midY) > 0.9)
    }
}
