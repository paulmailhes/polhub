import Domain
import Foundation
import FoundationModels
import Persistence
import Testing
@testable import Summarization

/// 15/11: the model's limits of the moment wait a minute, never counted as failures; a refusal and a window
/// overflow are told apart, so that the pipeline can deal with them part by part.
@Suite struct AppleErrorsTests {
    @Test func aBusyModelIsUnavailableForAMinute() {
        let busy = SummaryError.unavailable(AppleSummaryEngine.busy)
        #expect(AppleSummaryEngine.mapped(LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "limite"))) as? SummaryError == busy)
        #expect(AppleSummaryEngine.mapped(LanguageModelSession.Error.concurrentRequests) as? SummaryError == busy)
        #expect(AppleSummaryEngine.mapped(LanguageModelSession.GenerationError.rateLimited(.init(debugDescription: "limite"))) as? SummaryError == busy)
        #expect(AppleSummaryEngine.mapped(LanguageModelSession.GenerationError.concurrentRequests(.init(debugDescription: "deux"))) as? SummaryError == busy)
    }

    @Test func refusalsAndOverflowsAreToldApart() {
        #expect(AppleSummaryEngine.mapped(LanguageModelError.guardrailViolation(.init(debugDescription: "non"))) as? SummaryError == .refused)
        #expect(AppleSummaryEngine.mapped(LanguageModelSession.GenerationError.guardrailViolation(.init(debugDescription: "non"))) as? SummaryError == .refused)
        #expect(AppleSummaryEngine.mapped(LanguageModelError.contextSizeExceeded(.init(contextSize: 8_192, tokenCount: 9_000, debugDescription: "trop")))
                as? SummaryError == .tooLong)
        #expect(AppleSummaryEngine.mapped(LanguageModelSession.GenerationError.exceededContextWindowSize(.init(debugDescription: "trop")))
                as? SummaryError == .tooLong)
    }
}

/// The summary of a meeting, made on the Mac by Apple's model (14/11): the pure parts.
@Suite struct SummaryPlanTests {
    let id = UUID()

    func line(_ speaker: Speaker, _ seconds: Int, _ text: String) -> UtteranceRow {
        UtteranceRow(meetingID: id, speaker: speaker, startMs: seconds * 1_000, endMs: seconds * 1_000 + 900, text: text, doubtful: false)
    }

    @Test func linesSayWhoAndWhen() {
        #expect(SummaryPlan.lines([line(.moi, 65, "On part sur la maquette."), line(.autres, 3_725, "D'accord.")])
                == ["[01:05] Moi : On part sur la maquette.", "[62:05] Les autres : D'accord."])
        #expect(SummaryPlan.lines([line(.unknown, 0, "Un paragraphe importé.")]) == ["Un paragraphe importé."])
    }

    @Test func chunksCutBetweenLinesAndNeverLoseOne() {
        let lines = (0..<10).map { "ligne \($0) " + String(repeating: "x", count: 40) }
        let chunks = SummaryPlan.chunks(lines, maxCharacters: 150)
        #expect(chunks.count == 4)
        #expect(chunks.allSatisfy { $0.count <= 150 })
        #expect(chunks.joined().components(separatedBy: "\n").filter { !$0.isEmpty } == lines)
    }

    @Test func aLineLongerThanAChunkIsCutAlone() {
        let chunks = SummaryPlan.chunks(["court", String(repeating: "y", count: 250)], maxCharacters: 100)
        #expect(chunks.count == 4)
        #expect(chunks.allSatisfy { $0.count <= 100 })
    }
}

@Suite struct SummaryChecksTests {
    let transcript = "[00:10] Les autres : Irène envoie la charte vendredi.\n[00:20] Moi : Je prépare le plan du site."

    @Test func ownersAreMeAKnownNameOrNoOne() {
        let summary = MeetingSummary(overview: "Un point.", decisions: [], actions: [
            SummaryAction(text: "préparer le plan", owner: "Moi"),
            SummaryAction(text: "envoyer la charte", owner: "Irène"),
            SummaryAction(text: "relancer le client", owner: "Gaston"),
            SummaryAction(text: "valider la maquette", owner: "Camille Martin"),
            SummaryAction(text: "choisir les photos", owner: "l'équipe"),
            SummaryAction(text: "écrire les textes", owner: " "),
        ])
        let clean = SummaryChecks.clean(summary, transcript: transcript, participants: ["Camille Martin"])
        #expect(clean.actions.map(\.owner) == ["Moi", "Irène", "Interlocuteur", "Camille Martin", nil, nil])
        #expect(clean.actions.first?.text == "Préparer le plan")
    }

    @Test func vagueDueDatesGoAway() {
        let summary = MeetingSummary(overview: "", decisions: [], actions: [
            SummaryAction(text: "a", due: "non spécifiée"), SummaryAction(text: "b", due: "À déterminer"), SummaryAction(text: "c", due: "vendredi"),
            SummaryAction(text: "d", due: "Non précisée"), SummaryAction(text: "e", due: ""),
        ])
        #expect(SummaryChecks.clean(summary, transcript: "", participants: []).actions.map(\.due) == [nil, nil, "vendredi", nil, nil])
    }

    /// 14/11, first real summary: « (vide) », « (à venir) », « (dans pas longtemps) », and a date the action
    /// already says.
    @Test func dueDatesThatSayNothingOrRepeatTheActionGoAway() {
        let summary = MeetingSummary(overview: "", decisions: [], actions: [
            SummaryAction(text: "a", due: "vide"), SummaryAction(text: "b", due: "à venir"), SummaryAction(text: "c", due: "dans pas longtemps"),
            SummaryAction(text: "d", due: "Bientôt"), SummaryAction(text: "e", due: "prochainement"),
            SummaryAction(text: "Aller voir en début de semaine prochaine", due: "début de semaine prochaine"),
            SummaryAction(text: "Vérifier le suivi", due: "demain"),
        ])
        #expect(SummaryChecks.clean(summary, transcript: "", participants: []).actions.map(\.due) == [nil, nil, nil, nil, nil, nil, "demain"])
    }

    @Test func duplicatesGoAndListsStayShort() {
        let decisions = ["Garder WordPress.", "garder wordpress", ""] + (1...12).map { "Décision \($0)" }
        let actions = (1...14).map { SummaryAction(text: "Action \($0)") } + [SummaryAction(text: "action 1")]
        let clean = SummaryChecks.clean(MeetingSummary(overview: "  Résumé.  ", decisions: decisions, actions: actions), transcript: "", participants: [])
        #expect(clean.overview == "Résumé.")
        #expect(clean.decisions.count == SummaryChecks.maxDecisions && clean.decisions.prefix(2) == ["Garder WordPress.", "Décision 1"])
        #expect(clean.actions.count == SummaryChecks.maxActions && Set(clean.actions.map(\.text)).count == SummaryChecks.maxActions)
    }

    @Test func theTextHasTheSummaryAndTheDecisions() {
        let text = SummaryText.markdown(MeetingSummary(overview: "On lance la refonte.", decisions: ["Garder WordPress."], actions: [SummaryAction(text: "X")]))
        #expect(text == "## Résumé\n\nOn lance la refonte.\n\n## Décisions\n\n- Garder WordPress.")
        #expect(SummaryText.markdown(MeetingSummary(overview: "Court.", decisions: [], actions: [])) == "## Résumé\n\nCourt.")
    }

    /// 15/11: « Points clés » between the summary and the decisions, without repeats nor decisions said again.
    @Test func keyPointsComeBetweenTheSummaryAndTheDecisions() {
        let summary = MeetingSummary(overview: "On lance la refonte.", points: ["le client veut un site plus simple.", "Le client veut un site plus simple",
                                                                            "Garder WordPress.", " ", "Le blog attendra."] + (1...8).map { "Point \($0)" },
                                     decisions: ["Garder WordPress."], actions: [])
        let clean = SummaryChecks.clean(summary, transcript: "", participants: [])
        #expect(clean.points.prefix(2) == ["Le client veut un site plus simple.", "Le blog attendra."] && clean.points.count == SummaryChecks.maxPoints)
        let text = SummaryText.markdown(MeetingSummary(overview: "On lance la refonte.", points: ["Le blog attendra."], decisions: ["Garder WordPress."], actions: []))
        #expect(text == "## Résumé\n\nOn lance la refonte.\n\n## Points clés\n\n- Le blog attendra.\n\n## Décisions\n\n- Garder WordPress.")
    }

    /// A summary written before 15/11, without its key points, still reads.
    @Test func anOlderSummaryWithoutKeyPointsDecodes() throws {
        let data = Data(#"{"overview":"Un point.","decisions":["A"],"actions":[]}"#.utf8)
        let summary = try JSONDecoder().decode(MeetingSummary.self, from: data)
        #expect(summary.points.isEmpty && summary.missing == nil && summary.decisions == ["A"])
    }

    @Test func actionsBecomeRowsWithTheirDueDateInTheText() {
        let now = Date(timeIntervalSince1970: 1_794_562_920)
        let rows = SummaryText.actionRows([SummaryAction(text: "Envoyer la charte", owner: "Irène", due: "vendredi"), SummaryAction(text: "Relire")], at: now)
        #expect(rows.map(\.text) == ["Envoyer la charte (vendredi)", "Relire"])
        #expect(rows.map(\.owner) == ["Irène", nil])
        #expect(rows.map(\.position) == [0, 1])
    }
}
