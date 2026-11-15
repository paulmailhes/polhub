import SwiftUI
import Testing
@testable import PolhubDesign

/// 15/11: everything clickable answers, and a list is never cut in silence.
@Suite struct InteractionTests {
    /// « Voir les 4 autres », « Voir l'autre », then « Voir moins ».
    @Test func showMoreSaysHowManyAreHidden() {
        #expect(ShowMoreButton.title(hidden: 4, expanded: false) == "Voir les 4 autres")
        #expect(ShowMoreButton.title(hidden: 1, expanded: false) == "Voir l'autre")
        #expect(ShowMoreButton.title(hidden: 4, expanded: true) == "Voir moins")
        #expect(ShowMoreButton.title(hidden: 1, expanded: true) == "Voir moins")
    }

    @Test func aListShowsItsFirstRowsThenEverything() {
        let items = Array(1...7)
        #expect(ShowMore.visible(items, limit: 5, expanded: false) == [1, 2, 3, 4, 5])
        #expect(ShowMore.visible(items, limit: 5, expanded: true) == items)
        #expect(ShowMore.hidden(count: 7, limit: 5) == 2)
        // Nothing hidden: no button.
        #expect(ShowMore.hidden(count: 3, limit: 5) == 0)
        #expect(ShowMore.visible([1, 2, 3], limit: 5, expanded: false) == [1, 2, 3])
        #expect(ShowMore.hidden(count: 3, limit: -1) == 3 && ShowMore.visible([1, 2], limit: -1, expanded: false).isEmpty)
    }

    struct Row: Identifiable, Equatable {
        let id: Int
    }

    /// Correctifs du 15/11 : ce que Paul vient d'ajouter se voit, même au-delà des premières lignes.
    @Test func aRowJustAddedShowsEvenPastTheLimit() {
        let rows = (1...8).map(Row.init)
        #expect(ShowMore.visible(rows, limit: 5, expanded: false, alwaysShown: [8]).map(\.id) == [1, 2, 3, 4, 5, 8])
        #expect(ShowMore.hidden(rows, limit: 5, alwaysShown: [8]) == 2)
        #expect(ShowMore.hidden(rows, limit: 5, alwaysShown: [2]) == 3)
        #expect(ShowMore.visible(rows, limit: 5, expanded: true, alwaysShown: [8]) == rows)
    }

    /// The selection wins over the hover; nothing at rest.
    @Test func aRowLightsUpUnderThePointer() {
        #expect(HoverRow.fill(selected: false, hovering: false) == .clear)
        #expect(HoverRow.fill(selected: false, hovering: true) == Surface.fill)
        #expect(HoverRow.fill(selected: true, hovering: false) == Surface.selected)
        #expect(HoverRow.fill(selected: true, hovering: true) == Surface.selected)
    }

    /// 15/11: a row that is a button darkens a step while pressed; the selection still wins.
    @Test func aRowButtonDarkensWhilePressed() {
        #expect(HoverRow.fill(selected: false, hovering: true, pressed: true) == Surface.raised)
        #expect(HoverRow.fill(selected: false, hovering: false, pressed: true) == Surface.raised)
        #expect(HoverRow.fill(selected: true, hovering: true, pressed: true) == Surface.selected)
        #expect(HoverRow.fill(selected: false, hovering: false, pressed: false) == .clear)
    }

    @Test func motionsGoFromQuickToGentle() {
        #expect(Motion.quick != Motion.standard && Motion.standard != Motion.gentle)
    }
}
