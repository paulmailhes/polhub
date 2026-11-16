import Domain
import Foundation
import Persistence
import Testing
@testable import MeetingsUI

/// The card before a meeting (Paul, 16/11): at the top right, below the menu bar; it stays until Paul joins or
/// closes it.
@MainActor
@Suite struct MeetingCardTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)

    func event(_ id: String, inMinutes: Double, code: String = "abc-defg-hij") -> CalendarEventRow {
        CalendarEventRow(account: "paul@exemple.fr", eventID: id, title: "Point \(id)", startAt: now.addingTimeInterval(inMinutes * 60),
                         endAt: now.addingTimeInterval((inMinutes + 30) * 60), allDay: false, meetCode: code, organizer: "client@ailleurs.fr",
                         attendees: [Attendee(email: "paul@exemple.fr", response: "accepted", isSelf: true)], updatedAt: now)
    }

    /// Against the right edge, under the menu bar (or the notch), as macOS's notifications.
    @Test func theCardSitsAtTheTopRight() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 949)
        let frame = MeetingCardPlacement.frame(screenFrame: screen, visibleFrame: visible, safeAreaTop: 0, size: CGSize(width: 360, height: 72))
        #expect(frame == CGRect(x: 1512 - 360 - 12, y: 982 - 33 - 12 - 72, width: 360, height: 72))
        let notch = MeetingCardPlacement.frame(screenFrame: screen, visibleFrame: visible, safeAreaTop: 38, size: CGSize(width: 360, height: 72))
        #expect(notch.maxY == CGFloat(982 - 38 - 12))
        // A second screen on the left: its own right edge.
        let left = MeetingCardPlacement.frame(screenFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                                              visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1055), safeAreaTop: 0,
                                              size: CGSize(width: 360, height: 72))
        #expect(left.maxX == -12)
    }

    /// Shown when due, closed by its cross for good, gone once Paul joins; turned off in Réglages, nothing.
    @Test func theCardStaysUntilPaulJoinsOrClosesIt() {
        var joined: [String] = []
        let presenter = MeetingCardPresenter(showsPanel: false, join: { joined.append($0.eventID) })
        let events = [event("a", inMinutes: 1.5), event("b", inMinutes: 2, code: "xyz-uvwx-rst")]
        presenter.update(events: events, now: now, enabled: true, minutes: 2, meetingCode: nil)
        #expect(presenter.cards.map(\.eventID) == ["a", "b"])
        presenter.close(events[1])
        presenter.update(events: events, now: now.addingTimeInterval(5), enabled: true, minutes: 2, meetingCode: nil)
        #expect(presenter.cards.map(\.eventID) == ["a"])
        presenter.join(events[0])
        #expect(joined == ["a"] && presenter.cards.isEmpty)
        presenter.update(events: events, now: now.addingTimeInterval(10), enabled: true, minutes: 2, meetingCode: nil)
        #expect(presenter.cards.isEmpty)
        let fresh = MeetingCardPresenter(showsPanel: false, join: { _ in })
        fresh.update(events: events, now: now, enabled: false, minutes: 2, meetingCode: nil)
        #expect(fresh.cards.isEmpty)
    }

    /// The panel's height follows the cards.
    @Test func thePanelFitsItsCards() {
        #expect(MeetingCardMetrics.size(cards: 1) == CGSize(width: MeetingCardMetrics.width, height: MeetingCardMetrics.height))
        #expect(MeetingCardMetrics.size(cards: 2).height == MeetingCardMetrics.height * 2 + MeetingCardMetrics.spacing)
    }
}
