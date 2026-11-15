import Foundation
import MeetingDetection
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
        // Without the agenda, « Ouvrir Polhub » opens Réunions.
        context.openHome()
        #expect(router.section == .meetings && shown.count == 6)
        #expect(!context.isReady)
    }

    @Test func aNewEventIsARequestCalendrierUsesOnce() {
        let router = WindowRouter()
        let context = CoupDoeilContext(app: AppModel(), router: router)
        context.newEvent()
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
