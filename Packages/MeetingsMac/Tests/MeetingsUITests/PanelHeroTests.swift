import AppKit
import Foundation
import Persistence
import HubDesign
import SwiftUI
import Testing
@testable import MeetingsUI

/// The hero of « Coup d'œil » measured off screen, with made-up meetings: its height stays in the brief's range, so the
/// grid under it moves little from one state to the next (finding of 16/11).
@MainActor @Suite struct PanelHeroTests {
    let now = Date(timeIntervalSince1970: 1_763_220_000)
    /// The panel's width less its margins.
    static let width: CGFloat = MenuBarPanel.width - 2 * MenuBarPanel.margin

    /// On the scale (lot 9, 20/11: margins 14, gaps 10, tiles of 161 and a hero 12 above and 10 under its text before):
    /// margins 16 and gaps 8, two tiles of 160 × 80 with 12 inside, the hero 16 from its edge on every side.
    @Test func thePanelSitsOnTheScale() {
        #expect(MenuBarPanel.margin == Space.l && MenuBarPanel.gap == Space.s)
        #expect(PanelTiles.size == CGSize(width: 160, height: 80) && PanelTiles.padding == Space.m)
        #expect(HeroMetrics.padding == EdgeInsets(top: Space.l, leading: Space.l, bottom: Space.l, trailing: Space.l))
    }

    /// A hero's buttons hold on one line (lot 9, 20/11: « Arrêter maintenant » broke on two beside « Jamais pour ce lien »
    /// or « Voir la réunion », on the captures of 19/11 and 20/11, though both fit): with its second action beside it, the
    /// presumed end is no taller than with « Arrêter maintenant » alone.
    @Test func aHerosButtonsHoldOnOneLine() {
        _ = NSApplication.shared
        let context = CoupDoeilContext(app: AppModel(), router: WindowRouter())
        func height(_ hero: PanelModel.Hero, width: CGFloat = Self.width) -> CGFloat {
            NSHostingController(rootView: PanelHero(hero: hero, now: now, context: context, agenda: nil, library: nil))
                .sizeThatFits(in: CGSize(width: width, height: 10_000)).height
        }
        let alone = height(.presumedEnded(title: "Revue de maquettes", stopsAt: now.addingTimeInterval(500), meetingID: nil, canForget: false))
        let withLink = height(.presumedEnded(title: "Revue de maquettes", stopsAt: now.addingTimeInterval(500), meetingID: nil, canForget: true))
        let withMeeting = height(.presumedEnded(title: "Revue de maquettes", stopsAt: now.addingTimeInterval(500), meetingID: UUID(), canForget: false))
        #expect(abs(withLink - alone) < 0.5, "« Jamais pour ce lien » : \(withLink) pt au lieu de \(alone)")
        #expect(abs(withMeeting - alone) < 0.5, "« Voir la réunion » : \(withMeeting) pt au lieu de \(alone)")
        // A summary on its way: where it stands and « Ouvrir la réunion » on one line when they fit (« Transcription 58 % »),
        // nothing moves with room to spare; when they do not (« Transcription en attente », « Compte rendu en attente »),
        // the button goes whole under it, a row of its own, instead of breaking on two lines (8 points) or cutting the
        // words (none). Lot 10, 20/11: « Résumé en attente », which fitted, says « Compte rendu en attente ».
        func report(_ stage: PanelModel.Report.Stage) -> PanelModel.Hero {
            .report(PanelModel.Report(meetingID: UUID(), title: "Revue de maquettes", seconds: 9 * 60, stage: stage, since: nil, summaryToCome: true))
        }
        let fits = report(.transcribing(0.58))
        #expect(abs(height(fits) - height(fits, width: 600)) < 0.5, "« Transcription 58 % » : \(height(fits)) pt au lieu de \(height(fits, width: 600))")
        for waiting in [report(.transcriptionWaiting), report(.summaryWaiting)] {
            let narrow = height(waiting), wide = height(waiting, width: 600)
            #expect(narrow - wide >= RoleButton.height, "« Ouvrir la réunion » : \(narrow) pt, \(wide) pt avec de la place")
        }
    }

    /// A tile's value takes a second line when it has no detail under it (lot 9, 20/11): under « Libre jusqu'à 16:30 »,
    /// the Calendrier tile names « Revue de maquettes » whole instead of « Revue de maque… ».
    @Test func aTileWithoutDetailGivesItsValueTwoLines() {
        #expect(PanelTile.valueLines(PanelModel.Tile(value: "Revue de maquettes", count: 2)) == 2)
        #expect(PanelTile.valueLines(PanelModel.Tile(value: "Appel Hugo", detail: "Ensuite à 18:30", count: 2)) == 1)
    }

    /// What floats over every app reads as the panel (lot 9, 20/11: 13 and 11 points before, under the app's floor of
    /// 12): the card before a visio and the HUD, a title of 15 points and its line of 13, 16 points from their edge.
    @Test func theFloatingCardsReadAsThePanel() {
        #expect(FloatingMetrics.title == Font.rowTitle.weight(.semibold))
        #expect(FloatingMetrics.meta == Font.meta)
        #expect(FloatingMetrics.margin == Space.l)
    }

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

    /// From 90 to 145 points (lot 9, 20/11: 130 before, when the card had 12 above its text and 10 under it, and its
    /// buttons touched the text; now 16 on every side and 8 above the buttons, the tallest, « Résumé prêt », is 144);
    /// one exception, « Réunion détectée » with a Meet link: the five lines of the brief's mockup (the countdown, the
    /// title, « S'enregistre seule dans 7 s », the two answers, « Jamais pour ce lien ») do not fit, for its ten seconds.
    @Test func everyHeroStaysBetween90And145Points() {
        _ = NSApplication.shared
        let context = CoupDoeilContext(app: AppModel(), router: WindowRouter())
        for (name, hero) in heroes {
            let view = PanelHero(hero: hero, now: now, context: context, agenda: nil, library: nil).frame(width: Self.width)
            let height = NSHostingController(rootView: view).view.fittingSize.height
            let range: ClosedRange<CGFloat> = name == "détectée" ? 90...165 : 90...145
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
