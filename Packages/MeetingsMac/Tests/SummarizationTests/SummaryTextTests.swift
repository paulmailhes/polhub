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

    /// Correctifs du 15/11 : la ligne de la liste, de l'Accueil et de la page d'un projet n'a ni Markdown ni lien du
    /// coffre ; elle vient du « Résumé » s'il y en a un, sinon du début du texte, dans son ordre.
    @Test func theFirstLineHasNoMarksNorLinks() {
        #expect(SummaryText.overview("## Résumé\n\nLe client *valide* la refonte.\nDeuxième ligne.\n\n## Décisions\n\n- Garder WordPress.")
                == "Le client valide la refonte. Deuxième ligne.")
        #expect(SummaryText.overview("## Résumé\n\n") == nil)
        #expect(SummaryText.overview("Avec [[Atelier Nord|l'atelier]] et [[Camille]], voir [le devis](https://exemple.fr/devis) `v2`.")
                == "Avec l'atelier et Camille, voir le devis v2.")
        #expect(SummaryText.overview("> [!note] Notes de Paul\n> À relancer **vite**.") == "Notes de Paul À relancer vite.")
        // The « Résumé » of the vault's shape wins over a paragraph further down.
        #expect(SummaryText.overview("### Résumé\n\n- Le client valide la refonte.\n- Le blog attendra.\n\n### Notes de Paul\n\nPenser aux photos.")
                == "Le client valide la refonte.")
    }

    @Test func theListShowsTheFirstLines() {
        #expect(SummaryText.overview(written) == "Le client valide la refonte. La maquette part vendredi.")
        #expect(SummaryText.overview(vault) == "Budget à revoir")
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
