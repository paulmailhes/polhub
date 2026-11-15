import Domain
import Foundation
import Persistence
import Testing
@testable import Summarization

/// 15/11: the summary read back, for the page (its four parts), the list (its first line) and « Copier le compte
/// rendu ». Invented texts.
@Suite struct SummaryTextTests {
    let written = SummaryText.markdown(MeetingSummary(
        overview: "Le client valide la refonte.\nLa maquette part vendredi.", points: ["Le blog attendra.", "Les photos manquent."],
        decisions: ["Garder WordPress."], actions: [], missing: "la partie 2 sur 4 n'a pas pu être résumée (refusée par le modèle d'Apple)"))
    let vault = "### Notes de Paul\n\n- **Budget** à revoir\n\nLe client hésite encore sur le planning.\n\n> [!note] Rappel\n> Relancer."

    @Test func theAppsSummaryReadsBackInItsParts() throws {
        let sections = try #require(SummaryText.sections(written))
        #expect(sections.overview == "Le client valide la refonte.\nLa maquette part vendredi.")
        #expect(sections.points == ["Le blog attendra.", "Les photos manquent."])
        #expect(sections.decisions == ["Garder WordPress."])
        #expect(sections.missing == "la partie 2 sur 4 n'a pas pu être résumée (refusée par le modèle d'Apple)")
        let plain = try #require(SummaryText.sections("## Résumé\n\nCourt."))
        #expect(plain == SummarySections(overview: "Court."))
    }

    @Test func anotherShapeIsLeftToMarkdown() {
        #expect(SummaryText.sections(vault) == nil)
        #expect(SummaryText.sections("Un texte sans titre.") == nil)
        #expect(SummaryText.sections("## Résumé\n\nA.\n\n## Questions\n\n- B") == nil)
    }

    @Test func theListShowsTheFirstLines() {
        #expect(SummaryText.overview(written) == "Le client valide la refonte. La maquette part vendredi.")
        #expect(SummaryText.overview(vault) == "Le client hésite encore sur le planning.")
        #expect(SummaryText.overview("### Notes\n\n- **Budget** à revoir") == "Budget à revoir")
        #expect(SummaryText.overview("") == nil)
        let long = SummaryText.overview("## Résumé\n\n" + String(repeating: "Une phrase du résumé. ", count: 20), limit: 50)
        #expect(long == "Une phrase du résumé. Une phrase du résumé. Une…")
    }

    @Test func theSummaryCopiesAsTextAndAsHTMLForAMail() {
        let now = Date(timeIntervalSince1970: 1_794_562_920)
        let actions = [ActionRow(text: "Envoyer la maquette (vendredi)", owner: "Moi", position: 0, createdAt: now),
                       ActionRow(text: "Rassembler les photos <HD>", done: true, position: 1, createdAt: now)]
        let (plain, html) = SummaryText.export(title: "Atelier maquette", subtitle: "Jeudi 12 novembre", markdown: written, actions: actions)
        #expect(plain == """
            Atelier maquette
            Jeudi 12 novembre

            Résumé
            Le client valide la refonte.
            La maquette part vendredi.

            Points clés
            - Le blog attendra.
            - Les photos manquent.

            Décisions
            - Garder WordPress.

            Actions
            - Envoyer la maquette (vendredi) — Moi
            - Rassembler les photos <HD> (fait)

            """)
        #expect(html == "<p><b>Atelier maquette</b><br>Jeudi 12 novembre</p><p><b>Résumé</b></p>"
                + "<p>Le client valide la refonte.<br>La maquette part vendredi.</p><p><b>Points clés</b></p>"
                + "<ul><li>Le blog attendra.</li><li>Les photos manquent.</li></ul><p><b>Décisions</b></p><ul><li>Garder WordPress.</li></ul>"
                + "<p><b>Actions</b></p><ul><li>Envoyer la maquette (vendredi) — Moi</li><li>Rassembler les photos &lt;HD&gt; (fait)</li></ul>")
    }
}
