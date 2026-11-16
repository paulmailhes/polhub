import Domain
import Foundation
import Persistence
import SwiftUI
import Testing
@testable import MeetingsUI

/// The card before a Meet, captured over a desktop-like background, light and dark (invented events).
/// `POLHUB_LIVE=1 POLHUB_SNAPSHOTS=<dossier> swift test --filter MeetingCardScreenTests` (live: the glass).
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"] != nil), .serialized)
struct MeetingCardScreenTests {
    @Test func theCard() async throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"]), isDirectory: true)
        let now = Date()
        func event(_ id: String, _ title: String, inSeconds: Double, account: String) -> CalendarEventRow {
            CalendarEventRow(account: account, eventID: id, title: title, startAt: now.addingTimeInterval(inSeconds),
                             endAt: now.addingTimeInterval(inSeconds + 1_800), allDay: false, meetCode: "abc-\(id)-xyz", organizer: "client@ailleurs.fr",
                             attendees: [Attendee(email: account, response: "accepted", isSelf: true)], updatedAt: now)
        }
        let colors = ["pro@exemple.fr": Color(red: 0.2, green: 0.45, blue: 0.95), "perso@exemple.fr": Color(red: 0.85, green: 0.35, blue: 0.3)]
        let presenter = MeetingCardPresenter(showsPanel: false, join: { _ in }, color: { colors[$0] ?? .accentColor })
        let events = [event("one", "Atelier de démarrage — Studio Exemple", inSeconds: 100, account: "pro@exemple.fr"),
                      event("two", "Point hebdo avec l'équipe produit", inSeconds: 115, account: "perso@exemple.fr")]
        for (name, shown, dark) in [("carte-rendez-vous", [events[0]], false), ("carte-rendez-vous-sombre", [events[0]], true),
                                    ("carte-rendez-vous-deux", events, false)] {
            presenter.update(events: [], now: now, enabled: true, minutes: 2, meetingCode: nil)
            presenter.update(events: shown, now: now, enabled: true, minutes: 2, meetingCode: nil)
            let desk = ZStack(alignment: .topTrailing) {
                LinearGradient(colors: dark ? [Color(white: 0.12), Color(red: 0.15, green: 0.2, blue: 0.35)]
                                            : [Color(red: 0.75, green: 0.85, blue: 0.95), Color(red: 0.95, green: 0.85, blue: 0.75)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                MeetingCardStack(presenter: presenter).padding(12)
            }
            try await LiveWindow.capture(desk, to: output.appending(path: "\(name).png"), size: NSSize(width: 520, height: 220), dark: dark)
        }
    }
}
