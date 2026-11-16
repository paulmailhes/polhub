import AppKit
import Foundation
import Persistence
import SwiftUI
import Testing
@testable import MeetingsUI

/// The hero of « Coup d'œil » measured off screen, with made-up meetings: its height stays in the brief's range, so the
/// grid under it moves little from one state to the next (finding of 16/11).
@MainActor @Suite struct PanelHeroTests {
    let now = Date(timeIntervalSince1970: 1_763_220_000)
    /// The panel's width less its margins.
    static let width: CGFloat = 360 - 2 * 14

    private var event: CalendarEventRow {
        CalendarEventRow(account: "paul@atelier-nord.fr", eventID: "revue", title: "Revue de maquettes", startAt: now.addingTimeInterval(480),
                         endAt: now.addingTimeInterval(2_280), meetCode: "abc-defg-hij", updatedAt: now)
    }

    private func report(_ stage: PanelModel.Report.Stage, since: Date? = nil) -> PanelModel.Hero {
        .report(PanelModel.Report(meetingID: UUID(), title: "Revue de maquettes", seconds: 38 * 60, stage: stage, since: since, summaryToCome: true))
    }

    private var heroes: [(String, PanelModel.Hero)] {
        let detail = "16:30 – 17:00 · Refonte du site · 3 invités"
        return [
            ("détectée", .detected(title: "Revue de maquettes", deadline: now.addingTimeInterval(8), canForget: true)),
            ("détectée sans code Meet", .detected(title: "Revue de maquettes", deadline: now.addingTimeInterval(8), canForget: false)),
            ("enregistrement", .recording(title: "Revue de maquettes", since: now.addingTimeInterval(-767),
                                          detail: "Refonte du site · Atelier Nord · 3 invités", meetingID: UUID())),
            ("fin présumée", .presumedEnded(title: "Revue de maquettes", stopsAt: now.addingTimeInterval(500), meetingID: UUID(), canForget: true)),
            ("dans 8 min", .upcoming(PanelModel.Upcoming(event: event, started: false, detail: detail, pausedThrough: false))),
            ("pas enregistrée", .upcoming(PanelModel.Upcoming(event: event, started: true, detail: detail, pausedThrough: false))),
            ("suspendue", .paused(until: now.addingTimeInterval(1_800), missed: nil)),
            ("suspendue, un Meet manqué", .paused(until: now.addingTimeInterval(1_800), missed: event)),
            ("compte rendu en préparation", report(.transcribing(0.58))),
            ("résumé prêt", report(.ready(overview: "Maquettes validées ; reste la page tarifs, à livrer jeudi. Camille envoie les photos lundi."),
                                   since: now.addingTimeInterval(-240))),
            ("transcription échouée", report(.transcriptionFailed("moteur absent"), since: now.addingTimeInterval(-240))),
            ("la journée", .day(title: "Dimanche 15 novembre", line: "Libre jusqu'à 16:30")),
        ]
    }

    /// From 90 to 130 points; one exception, « Réunion détectée » with a Meet link: the five lines of the brief's mockup
    /// (the countdown, the title, « S'enregistre seule dans 7 s », the two answers, « Jamais pour ce lien ») do not fit
    /// in 130, for its ten seconds.
    @Test func everyHeroStaysBetween90And130Points() {
        _ = NSApplication.shared
        let context = CoupDoeilContext(app: AppModel(), router: WindowRouter())
        for (name, hero) in heroes {
            let view = PanelHero(hero: hero, now: now, context: context, agenda: nil, library: nil).frame(width: Self.width)
            let height = NSHostingController(rootView: view).view.fittingSize.height
            let range: ClosedRange<CGFloat> = name == "détectée" ? 90...150 : 90...130
            #expect(range.contains(height), "\(name) : \(height) pt")
        }
    }

    /// Paul's capture of 16/11, during a real recording: the menu bar's window was shorter than the panel, the hero
    /// gave up its height down to its 90 points and its buttons spilled over the tiles. Offered less room, a hero keeps
    /// its whole height.
    @Test func aHeroNeverGivesUpItsHeight() {
        _ = NSApplication.shared
        let context = CoupDoeilContext(app: AppModel(), router: WindowRouter())
        for (name, hero) in heroes {
            let host = NSHostingController(rootView: PanelHero(hero: hero, now: now, context: context, agenda: nil, library: nil).frame(width: Self.width))
            let whole = host.sizeThatFits(in: CGSize(width: Self.width, height: 10_000)).height
            let squeezed = host.sizeThatFits(in: CGSize(width: Self.width, height: 40)).height
            #expect(abs(squeezed - whole) < 0.5, "\(name) : \(squeezed) pt au lieu de \(whole)")
        }
    }

    /// The whole panel, while a meeting records: it never takes less than its own height, so the window under the logo
    /// grows to it instead of squeezing the hero.
    @Test func thePanelNeverTakesLessThanItsHeight() {
        _ = NSApplication.shared
        let app = AppModel()
        app.status = .recording(title: "Revue de maquettes", since: now.addingTimeInterval(-57))
        let host = NSHostingController(rootView: MenuBarPanel(context: CoupDoeilContext(app: app, router: WindowRouter())).environment(\.panelNow, now))
        let whole = host.sizeThatFits(in: CGSize(width: MenuBarPanel.width, height: 10_000)).height
        let squeezed = host.sizeThatFits(in: CGSize(width: MenuBarPanel.width, height: 120)).height
        #expect(whole > 200 && abs(squeezed - whole) < 0.5, "\(squeezed) pt au lieu de \(whole)")
    }
}
