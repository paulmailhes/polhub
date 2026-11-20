import Domain
import Foundation
import Persistence
import SwiftUI
import Testing
@testable import MeetingsUI

/// The card before a Meet, and the HUD (the same panel over every app), captured over a desktop-like background, light
/// and dark (invented events). `POLHUB_LIVE=1 POLHUB_SNAPSHOTS=<dossier> swift test --filter MeetingCardScreenTests`
/// (live: the glass).
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"] != nil), .serialized)
struct MeetingCardScreenTests {
    private var output: URL {
        get throws { URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"]), isDirectory: true) }
    }

    @Test func theCard() async throws {
        let output = try output
        let now = Date()
        func event(_ id: String, _ title: String, inSeconds: Double, account: String) -> CalendarEventRow {
            CalendarEventRow(account: account, eventID: id, title: title, startAt: now.addingTimeInterval(inSeconds),
                             endAt: now.addingTimeInterval(inSeconds + 1_800), allDay: false, meetCode: "abc-\(id)-xyz", organizer: "client@ailleurs.fr",
                             attendees: [Attendee(email: account, response: "accepted", isSelf: true)], updatedAt: now)
        }
        let colors = ["pro@exemple.fr": Color(red: 0.2, green: 0.45, blue: 0.95), "perso@exemple.fr": Color(red: 0.85, green: 0.35, blue: 0.3)]
        let presenter = MeetingCardPresenter(showsPanel: false, join: { _ in }, color: { colors[$0] ?? .secondary })
        let events = [event("one", "Atelier de démarrage — Studio Exemple", inSeconds: 100, account: "pro@exemple.fr"),
                      event("two", "Point hebdo avec l'équipe produit", inSeconds: 115, account: "perso@exemple.fr")]
        for (name, shown, dark) in [("carte-rendez-vous", [events[0]], false), ("carte-rendez-vous-sombre", [events[0]], true),
                                    ("carte-rendez-vous-deux", events, false), ("carte-rendez-vous-deux-sombre", events, true)] {
            presenter.update(events: [], now: now, enabled: true, minutes: 2, meetingCode: nil)
            presenter.update(events: shown, now: now, enabled: true, minutes: 2, meetingCode: nil)
            try await LiveWindow.capture(Desk(dark: dark) { MeetingCardStack(presenter: presenter) }, to: output.appending(path: "\(name).png"),
                                         size: NSSize(width: 520, height: 220), dark: dark)
        }
    }

    /// The HUD in its three kinds (lot 9, 20/11: it had no capture): a meeting detected, a toast, an alert.
    @Test func theHUD() async throws {
        let output = try output
        let states: [(String, HUDModel.Kind, String, String, String)] = [
            ("hud-reunion-detectee", .prompt, HUDText.promptTitle("Revue de maquettes"), "", ""),
            ("hud-message", .toast, "L'enregistrement continue", "Micro : Casque · Sortie : Haut-parleurs", ""),
            ("hud-alerte", .alert, "Polhub ne lit plus les onglets de Dia", "Les réunions sont détectées par le micro seul.", "Diagnostic"),
        ]
        for dark in [false, true] {
            for (name, kind, title, subtitle, action) in states {
                let model = HUDModel()
                model.kind = kind
                model.title = title
                model.subtitle = subtitle
                model.actionTitle = action
                model.remaining = 7
                try await LiveWindow.capture(Desk(dark: dark) { HUDView(model: model) },
                                             to: output.appending(path: "\(name)\(dark ? "-sombre" : "").png"),
                                             size: NSSize(width: 520, height: 140), dark: dark)
            }
        }
    }
}

/// A desktop-like background, the panel at its top right as macOS shows its notifications.
private struct Desk<Content: View>: View {
    let dark: Bool
    let content: Content

    init(dark: Bool, @ViewBuilder content: () -> Content) {
        self.dark = dark
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: dark ? [Color(white: 0.12), Color(red: 0.15, green: 0.2, blue: 0.35)]
                                        : [Color(red: 0.75, green: 0.85, blue: 0.95), Color(red: 0.95, green: 0.85, blue: 0.75)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            content.padding(12)
        }
    }
}
