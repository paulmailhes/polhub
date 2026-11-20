import Foundation
import Testing
@testable import MeetingsUI

/// Réglages › Colin (18/11): the line that says what Colin did this week, read-only.
@Suite struct ColinSettingsTests {
    @Test func theFooterSaysEverythingThatLeaves() {
        #expect(ColinSettingsText.footer.contains("les lignes de l'Accueil"))
        #expect(ColinSettingsText.footer.contains("Anthropic") && ColinSettingsText.footer.contains("Jamais l'audio"))
    }

    /// Step 3 (18/11): the switch says its two rules, what they never touch, and where they are undone.
    @Test func theKanbanSwitchSaysItsTwoRules() {
        #expect(ColinSettingsText.kanban.contains("« Attend le retour de … »") && ColinSettingsText.kanban.contains("l'échéance"))
        #expect(ColinSettingsText.kanban.contains("en pause ou terminé") && ColinSettingsText.kanban.contains("Annuler"))
        #expect(ColinSettingsText.footer.contains("quand tu le lui demandes"))
    }

    @Test func theStatusLineSaysTheWeek() {
        #expect(ColinSettingsText.week(count: 12, costUSD: 0.42) == "Cette semaine : 12 réponses de Colin, l'équivalent de 0,42 $.")
        #expect(ColinSettingsText.week(count: 1, costUSD: 0.031) == "Cette semaine : 1 réponse de Colin, l'équivalent de 0,03 $.")
        #expect(ColinSettingsText.week(count: 0, costUSD: 0) == "Cette semaine : aucune réponse de Colin.")
    }
}
