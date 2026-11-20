import Foundation
import MeetingDetection
import Observation
import Persistence
import Pipeline
import Testing
@testable import MeetingsUI

/// The model of the menu bar and of « Coup d'œil » (15/11), with made-up events.
@MainActor @Suite struct AppModelTests {
    let now = Date(timeIntervalSince1970: 1_763_200_000)

    @Test func thePromptShowsOnlyWhileTheHUDShowsIt() {
        let model = AppModel()
        model.status = .prompting(title: "Revue de maquettes")
        #expect(model.prompt == nil)
        let deadline = now.addingTimeInterval(10)
        model.setPromptDeadline(deadline)
        #expect(model.prompt == DetectedPrompt(title: "Revue de maquettes", deadline: deadline))
        // The HUD closed (a click there or in the panel): both hide together.
        model.setPromptDeadline(nil)
        #expect(model.prompt == nil)
        // A deadline left behind never shows once the meeting records.
        model.setPromptDeadline(deadline)
        model.status = .recording(title: "Revue de maquettes", since: now)
        #expect(model.prompt == nil)
    }

    @Test func neverForThisLinkNeedsAMeetCode() {
        let model = AppModel()
        model.setMeetCode("abc-defg-hij")
        #expect(!model.canForgetLink)
        for status in [RecorderStatus.prompting(title: "Point"), .recording(title: "Point", since: now), .presumedEnded(title: "Point")] {
            model.status = status
            #expect(model.canForgetLink)
        }
        model.setMeetCode(nil)
        #expect(!model.canForgetLink)
    }

    @Test func theAlertsGoOnceTheirCauseIsGone() {
        let model = AppModel()
        #expect(!model.recordingsAtRisk && model.alert == nil)
        model.raise(.diskLow(freeGB: 15))
        model.raise(.tabsUnreadable)
        model.raise(.diskLow(freeGB: 12))
        // One of each kind, the riskiest first.
        #expect(model.alerts == [.tabsUnreadable, .diskLow(freeGB: 12)])
        #expect(model.alert == .tabsUnreadable && model.recordingsAtRisk)
        model.resolve(.tabsUnreadable)
        #expect(model.alerts == [.diskLow(freeGB: 12)])
        model.checkDisk(availableBytes: 12_000_000_000)
        model.checkDisk(availableBytes: nil)
        #expect(model.alerts == [.diskLow(freeGB: 12)])
        model.checkDisk(availableBytes: 80_000_000_000)
        #expect(model.alerts.isEmpty && !model.recordingsAtRisk)
    }

    /// A summary put away stays away once hub restarts; the list keeps only the latest ones.
    @Test func aSummaryPutAwayStaysAwayAfterARestart() throws {
        let defaults = try #require(UserDefaults(suiteName: "polhub.tests.\(UUID().uuidString)"))
        let first = UUID()
        let model = AppModel(defaults: defaults)
        model.putAway(report: first)
        #expect(model.reportsPutAway.contains(first))
        #expect(AppModel(defaults: defaults).reportsPutAway.contains(first))
        for _ in 0..<AppModel.reportsKept { model.putAway(report: UUID()) }
        #expect(AppModel(defaults: defaults).reportsPutAway.count == AppModel.reportsKept && !model.reportsPutAway.contains(first))
    }

    /// The disk alert follows the free space (finding of 16/11): its figure while space shrinks, gone once there is
    /// room, back in the same meeting when the disk fills again (without its pop-up, the coordinator's, once a
    /// meeting).
    @Test func theDiskAlertFollowsTheFreeSpace() {
        let model = AppModel()
        #expect(!model.needsDiskCheck)
        model.status = .recording(title: "Revue de maquettes", since: now)
        #expect(model.needsDiskCheck)
        model.raise(.diskLow(freeGB: 15))
        model.checkDisk(availableBytes: 9_000_000_000)
        #expect(model.alerts == [.diskLow(freeGB: 9)])
        // The Trash emptied: it goes.
        model.checkDisk(availableBytes: 25_000_000_000)
        #expect(model.alerts.isEmpty)
        // A download fills the disk during the same meeting: it comes back.
        model.checkDisk(availableBytes: 4_000_000_000)
        #expect(model.alerts == [.diskLow(freeGB: 4)])
        // Between meetings, an alert still up keeps following the disk; with none, nothing is checked.
        model.status = .idle
        #expect(model.needsDiskCheck)
        model.checkDisk(availableBytes: 3_000_000_000)
        #expect(model.alerts == [.diskLow(freeGB: 3)])
        model.resolve(.diskLow)
        #expect(!model.needsDiskCheck)
        model.checkDisk(availableBytes: 3_000_000_000)
        #expect(model.alerts.isEmpty)
    }

    @Test func aPauseEndsWhenItsTimeComes() {
        let model = AppModel()
        model.pausedUntil = now.addingTimeInterval(3_600)
        model.tick(now: now)
        #expect(model.isPaused && model.shownStatus == .paused(until: now.addingTimeInterval(3_600)))
        // A pause while a meeting records: the meeting shows, the pause stays known.
        model.status = .recording(title: "Point", since: now)
        #expect(model.shownStatus == .recording(title: "Point", since: now) && model.isPaused)
        model.status = .idle
        model.tick(now: now.addingTimeInterval(3_600))
        #expect(!model.isPaused && model.shownStatus == .idle)
    }

    /// 19/11, measured: read from the clock, the menu bar's label was redrawn twice a second, and macOS redrew the icon
    /// on every screen each time (three quarters of the app's work at rest). The label shown is stored and replaced
    /// only when it changes: a tick that changes nothing wakes no view.
    @Test func theShownLabelChangesOnlyWhenWhatItShowsDoes() {
        let model = AppModel()
        model.detectionOn = true
        model.updateNextMeet([event("Revue de maquettes", in: 7.5)], now: now)
        model.tick(now: now)
        #expect(model.shownMenuBarLabel(meetMinutes: true) == MenuBarLabel(icon: .columns(.filled, badge: false), text: "8 min"))
        #expect(model.shownMenuBarLabel(meetMinutes: false) == MenuBarLabel(icon: .columns(.filled, badge: false), text: nil))
        func wakes(_ change: () -> Void) -> Bool {
            let woken = Woken()
            withObservationTracking {
                _ = model.shownMenuBarLabel(meetMinutes: true)
            } onChange: {
                woken.set()
            }
            change()
            return woken.value
        }
        // Half a second later, the same « 8 min »: nothing to redraw.
        #expect(!wakes { model.tick(now: now.addingTimeInterval(0.5)) })
        #expect(!wakes { model.tick(now: now.addingTimeInterval(20)) })
        // The minute turns: redrawn once.
        #expect(wakes { model.tick(now: now.addingTimeInterval(40)) })
        #expect(model.shownMenuBarLabel(meetMinutes: true).text == "7 min")
        // A recording: its clock turns every second, never twice in one.
        model.status = .recording(title: "Point", since: now.addingTimeInterval(60))
        #expect(wakes { model.tick(now: now.addingTimeInterval(61)) })
        #expect(model.shownMenuBarLabel(meetMinutes: true) == MenuBarLabel(icon: .recording, text: "0:01"))
        #expect(!wakes { model.tick(now: now.addingTimeInterval(61.5)) })
        #expect(wakes { model.tick(now: now.addingTimeInterval(62)) })
    }

    final class Woken: @unchecked Sendable {
        private let lock = NSLock()
        private var woken = false
        var value: Bool { lock.withLock { woken } }
        func set() { lock.withLock { woken = true } }
    }

    private func event(_ title: String, in minutes: Double, meet: Bool = true, allDay: Bool = false, declined: Bool = false) -> CalendarEventRow {
        let start = now.addingTimeInterval(minutes * 60)
        return CalendarEventRow(account: "paul@exemple.fr", eventID: title, title: title, startAt: start, endAt: start.addingTimeInterval(1_800),
                                allDay: allDay, meetCode: meet ? "abc-defg-hij" : nil,
                                attendees: declined ? [Attendee(email: "paul@exemple.fr", response: "declined", isSelf: true)] : [],
                                updatedAt: now)
    }

    @Test func eightMinutesBeforeTheNextMeet() {
        let model = AppModel()
        model.detectionOn = true
        model.tick(now: now)
        model.updateNextMeet([event("Déjà commencé", in: -5), event("Sans visio", in: 3, meet: false), event("Refusé", in: 4, declined: true),
                              event("Journée", in: 2, allDay: true), event("Revue de maquettes", in: 7.5), event("Plus tard", in: 40)], now: now)
        #expect(model.nextMeetAt == now.addingTimeInterval(7.5 * 60))
        #expect(model.minutesToMeet == 8)
        #expect(model.menuBarLabel(meetMinutes: true) == MenuBarLabel(icon: .columns(.filled, badge: false), text: "8 min"))
        // Paul's setting off: the logo alone.
        #expect(model.menuBarLabel(meetMinutes: false) == MenuBarLabel(icon: .columns(.filled, badge: false), text: nil))
        // Once it starts, the app looks for the next one.
        model.tick(now: now.addingTimeInterval(8 * 60))
        #expect(model.nextMeetPassed && model.minutesToMeet == nil)
    }

    @Test func theDevelopmentBuildKeepsTheColumnsInOutline() {
        let model = AppModel(isDevelopment: true)
        model.detectionOn = true
        model.tick(now: now)
        #expect(model.menuBarLabel(meetMinutes: true) == MenuBarLabel(icon: .columns(.outline, badge: false), text: nil))
        model.raise(.selfTestFailed)
        #expect(model.menuBarLabel(meetMinutes: true) == MenuBarLabel(icon: .columns(.outline, badge: true), text: nil))
    }
}

/// What « Coup d'œil » opens: through the router, then the window in front.
@MainActor @Suite struct CoupDoeilContextTests {
    @Test func aPlaceOpensThroughTheRouterThenTheWindow() {
        let router = WindowRouter()
        let shown = Tally()
        let context = CoupDoeilContext(app: AppModel(), router: router, actions: CoupDoeilActions(showMainWindow: { shown.count += 1 }))
        context.open(.mail("paul@exemple.fr|t1"))
        #expect(router.section == .mails && router.mailSelection == "paul@exemple.fr|t1" && shown.count == 1)
        context.open(.event("paul@exemple.fr|e1"))
        #expect(router.section == .calendar && router.eventSelection == "paul@exemple.fr|e1")
        let meeting = UUID()
        context.open(.meeting(meeting))
        #expect(router.section == .meetings && router.selection == meeting)
        context.open(.settings(.accounts))
        #expect(router.section == .settings && router.settingsPane == .accounts)
        context.open(.section(.projects))
        #expect(router.section == .projects)
        // Without the agenda, « Ouvrir hub » opens Réunions.
        context.openHome()
        #expect(router.section == .meetings && shown.count == 6)
        #expect(!context.isReady)
    }

    @Test func aNewEventIsARequestCalendrierUsesOnce() {
        let router = WindowRouter()
        let context = CoupDoeilContext(app: AppModel(), router: router)
        context.open(.newEvent)
        let first = router.newEventRequest
        #expect(router.section == .calendar && first != nil)
        router.newEvent()
        #expect(router.newEventRequest != nil && router.newEventRequest != first)
    }

    @Test func theBellIsAskedFor() {
        let router = WindowRouter()
        router.section = .projects
        router.go(to: .notifications)
        #expect(router.notificationsRequested && router.section == .projects)
    }

    @Test func theGesturesOnTheMeetingGoToTheCoordinator() {
        let gestures = Tally()
        let context = CoupDoeilContext(app: AppModel(), router: WindowRouter(), actions: CoupDoeilActions(user: { gestures.actions.append($0) }))
        context.actions.user(.accept)
        context.actions.user(.decline)
        #expect(gestures.actions == [.accept, .decline])
        // No mailbox: « Nouveau mail » does nothing.
        context.newMail()
        #expect(context.router.section == .projects)
    }
}

@MainActor final class Tally {
    var count = 0
    var actions: [UserAction] = []
}
