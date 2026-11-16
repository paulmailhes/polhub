import Domain
import Foundation
import Persistence
import Summarization
import Testing
@testable import MeetingsUI

/// « Exporter » (Paul, 16/11: « exporter en .md facilement… pour les envoyer à des gens »): one Markdown page with
/// the summary, its actions and the clean dialogue. Invented meeting.
@Suite struct MeetingExportTests {
    let meetingID = UUID()
    let start = Date(timeIntervalSince1970: 1_794_562_200)

    func line(_ speaker: Speaker, _ seconds: Int, _ text: String) -> UtteranceRow {
        UtteranceRow(meetingID: meetingID, speaker: speaker, startMs: seconds * 1_000, endMs: seconds * 1_000 + 2_000, text: text, doubtful: false)
    }

    var summary: String {
        SummaryText.markdown(MeetingSummary(overview: "Le client valide la refonte du site.", points: ["Le blog attendra **janvier**."],
                                            decisions: ["Garder WordPress."], actions: [], missing: nil))
    }

    @Test func thePageHoldsTheSummaryThenTheDialogue() {
        let lines = [line(.moi, 0, "Bonjour à tous."), line(.moi, 3, "On commence ?"), line(.autres, 12, "Oui, allons-y."),
                     line(.moi, 75, "Parfait.")]
        let actions = [ActionRow(meetingID: meetingID, text: "Envoyer la maquette", owner: "Camille", position: 0, createdAt: start),
                       ActionRow(meetingID: meetingID, text: "Relire le devis", done: true, position: 1, createdAt: start)]
        let page = MeetingExport.markdown(title: "Refonte du site — Studio Exemple", date: "Lundi 16 novembre 2026 à 14:30", duration: "27 min",
                                          participants: ["Camille Exemple", "Léo Exemple"], summary: summary, actions: actions,
                                          lines: lines, me: "Paul")
        #expect(page == """
            # Refonte du site — Studio Exemple

            Lundi 16 novembre 2026 à 14:30 · 27 min
            Participants : Camille Exemple, Léo Exemple

            ## Résumé

            Le client valide la refonte du site.

            ## Points clés

            - Le blog attendra janvier.

            ## Décisions

            - Garder WordPress.

            ## Actions

            - [ ] Envoyer la maquette — Camille
            - [x] Relire le devis

            ## Transcription

            **Paul** · 0:00
            Bonjour à tous. On commence ?

            **Les autres** · 0:12
            Oui, allons-y.

            **Paul** · 1:15
            Parfait.

            """)
    }

    /// Without a summary nor participants, the page starts with the dialogue; an imported one has no voices.
    @Test func whatIsMissingLeavesNoEmptyPart() {
        let page = MeetingExport.markdown(title: "Point", date: "Mardi 3 novembre 2026 à 9:00", duration: "12 min", participants: [],
                                          summary: nil, actions: [], lines: [line(.unknown, 0, "Texte importé."), line(.unknown, 30, "Suite.")],
                                          me: "Paul")
        #expect(page == "# Point\n\nMardi 3 novembre 2026 à 9:00 · 12 min\n\n## Transcription\n\nTexte importé.\n\nSuite.\n")
    }

    /// « 2026-11-16 Refonte du site.md »: no character a folder refuses.
    @Test func theFileIsNamedAfterTheDayAndTheTitle() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 14, minute: 30))!
        #expect(MeetingExport.fileName(title: "Refonte : site/blog", date: day, calendar: calendar) == "2026-11-16 Refonte - site-blog.md")
        #expect(MeetingExport.fileName(title: "  ", date: day, calendar: calendar) == "2026-11-16 Réunion.md")
    }

    /// The first name of the Mac's account stands for « Moi » in a page sent to others.
    @Test func meIsTheFirstName() {
        #expect(MeetingExport.firstName("Paul Exemple") == "Paul")
        #expect(MeetingExport.firstName("") == "Moi")
    }
}
