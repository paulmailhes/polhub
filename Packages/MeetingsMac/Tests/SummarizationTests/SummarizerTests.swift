import Domain
import Foundation
import Persistence
import Testing
@testable import Summarization

/// 15/11: parts sized to the model's window, a refused part that no longer sinks the summary, the progress part
/// by part. With an invented transcript and a stand-in model.
@Suite struct SummarizerTests {
    let id = UUID()

    /// `count` lines of about 520 characters, two voices.
    func lines(_ count: Int) -> [UtteranceRow] {
        (0..<count).map { index in
            UtteranceRow(meetingID: id, speaker: index % 2 == 0 ? .moi : .autres, startMs: index * 30_000, endMs: index * 30_000 + 25_000,
                         text: String(repeating: "On reprend la maquette de l'accueil et le devis. ", count: 10), doubtful: false)
        }
    }

    @Test func theProgressGoesPartByPartThenTheSummary() async throws {
        let steps = Steps()
        _ = try await Summarizer.make(lines: lines(30), title: "Atelier", participants: [], engine: FakeEngine(), maxCharacters: 4_000,
                                      onProgress: { steps.all.append($0) })
        let total = try #require(steps.all.first?.total)
        #expect(total == SummaryPlan.chunks(SummaryPlan.lines(lines(30)), maxCharacters: 4_000).count && total > 2)
        #expect(steps.all.map(\.done) == Array(0...total) + [total])
        #expect(steps.all.dropLast().allSatisfy { !$0.finishing } && steps.all.last?.finishing == true)
        #expect(steps.all.map(\.fraction) == steps.all.map(\.fraction).sorted() && (steps.all.last?.fraction ?? 1) < 1)
    }

    @Test func aRefusedPartLeavesTheSummaryPartialInsteadOfSinkingIt() async throws {
        let engine = FakeEngine()
        engine.refusedParts = [2]
        let summary = try #require(try await Summarizer.make(lines: lines(30), title: "Atelier", participants: [], engine: engine, maxCharacters: 4_000))
        let count = SummaryPlan.chunks(SummaryPlan.lines(lines(30)), maxCharacters: 4_000).count
        #expect(summary.overview == "Atelier : \(count - 1) parties.")
        #expect(summary.missing == "la partie 2 sur \(count) n'a pas pu être résumée (refusée par le modèle d'Apple)")
        #expect(SummaryText.markdown(summary).hasSuffix("\n\n_Partiel : la partie 2 sur \(count) n'a pas pu être résumée (refusée par le modèle d'Apple)._"))
    }

    @Test func aMeetingWhoseEveryPartIsRefusedHasNoSummary() async throws {
        let engine = FakeEngine()
        engine.refusedParts = [1]
        await #expect(throws: SummaryError.refused) {
            try await Summarizer.make(lines: lines(4), title: "Atelier", participants: [], engine: engine, maxCharacters: 4_000)
        }
    }

    /// Correctifs du 15/11 : le compte rendu refusé ne fait plus tout perdre. Il est redemandé sans les notes que
    /// le modèle n'a données qu'avec des garde-fous relâchés, et la partie qu'elles portaient est dite manquante.
    @Test func aRefusedSummaryIsAskedAgainWithoutTheRelaxedNotes() async throws {
        let engine = FakeEngine()
        engine.relaxedParts = [2]
        engine.refusesSummary = { notes in notes.contains { $0.hasPrefix("relâchées") } }
        let summary = try #require(try await Summarizer.make(lines: lines(30), title: "Atelier", participants: [], engine: engine, maxCharacters: 4_000))
        let count = SummaryPlan.chunks(SummaryPlan.lines(lines(30)), maxCharacters: 4_000).count
        #expect(engine.summaries.count == 2)
        #expect(summary.overview == "Atelier : \(count - 1) parties.")
        #expect(summary.missing == "la partie 2 sur \(count) n'a pas pu être résumée (refusée par le modèle d'Apple)")
    }

    /// Sans notes relâchées, le compte rendu refusé est redemandé avec les premières parties seulement.
    @Test func aRefusedSummaryWithoutRelaxedNotesKeepsTheFirstParts() async throws {
        let engine = FakeEngine()
        let count = SummaryPlan.chunks(SummaryPlan.lines(lines(30)), maxCharacters: 4_000).count
        engine.refusesSummary = { notes in notes.count == count }
        let summary = try #require(try await Summarizer.make(lines: lines(30), title: "Atelier", participants: [], engine: engine, maxCharacters: 4_000))
        #expect(summary.overview == "Atelier : \(count / 2) parties.")
        #expect(summary.missing == SummaryText.missing(dropped: Array((count / 2 + 1)...count), of: count, shortened: false))
    }

    /// Refusé deux fois, le compte rendu échoue comme avant : une seule nouvelle demande.
    @Test func aSummaryRefusedTwiceFails() async throws {
        let engine = FakeEngine()
        engine.refusesSummary = { _ in true }
        await #expect(throws: SummaryError.refused) {
            try await Summarizer.make(lines: lines(30), title: "Atelier", participants: [], engine: engine, maxCharacters: 4_000)
        }
        #expect(engine.summaries.count == 2)
    }

    /// Les groupes de notes à fusionner se coupent comme les parties, et savent d'où ils viennent.
    @Test func groupsOfNotesAreCutLikeChunksAndKnowTheirParts() {
        let notes = (1...6).map { Summarizer.Note(text: String(repeating: "n", count: 1_500), parts: [$0], relaxed: $0 == 3) }
        let groups = SummaryPlan.groups(notes, maxCharacters: 4_000)
        #expect(groups.map(\.text) == SummaryPlan.chunks(notes.map(\.text), maxCharacters: 4_000))
        #expect(groups.map(\.parts) == [[1, 2], [3, 4], [5, 6]])
        #expect(groups.map(\.relaxed) == [false, true, false])
    }

    @Test func aPartTooLongForTheWindowIsCutInTwoAndNothingIsLost() async throws {
        let engine = FakeEngine()
        engine.window = 2_500
        let summary = try #require(try await Summarizer.make(lines: lines(30), title: "Atelier", participants: [], engine: engine, maxCharacters: 4_000))
        #expect(summary.missing == nil)
        #expect(engine.read.allSatisfy { $0 <= 2_500 } && engine.read.count > 3)
        let transcript = SummaryPlan.lines(lines(30)).joined(separator: "\n").count
        #expect(engine.read.reduce(0, +) >= transcript)
    }

    @Test func thePartsFollowTheModelsBudget() async throws {
        let engine = FakeEngine()
        engine.budget = 3_000
        _ = try await Summarizer.make(lines: lines(30), title: "Atelier", participants: [], engine: engine)
        #expect(!engine.read.isEmpty && engine.read.allSatisfy { $0 <= 3_000 })
    }

    @Test func longNotesAreMergedByTheirOwnRequest() async throws {
        let engine = FakeEngine()
        engine.notesLength = 1_500
        let summary = try #require(try await Summarizer.make(lines: lines(60), title: "Atelier", participants: [], engine: engine, maxCharacters: 4_000))
        #expect(engine.merges > 0)
        #expect(engine.mergedLength <= 4_000)
        #expect(summary.points == ["La maquette avance."])
    }

    @Test func theBudgetComesFromTheWindowAndStaysWithinBounds() {
        // 4 characters per token: (8 192 − 600 − 1 240) × 4 × 0,9 is more than measured: 10 000.
        #expect(SummaryPlan.characterBudget(contextSize: 8_192, fixedTokens: 600, sampleCharacters: 400, sampleTokens: 100) == 10_000)
        #expect(SummaryPlan.characterBudget(contextSize: 4_096, fixedTokens: 600, sampleCharacters: 400, sampleTokens: 100) == 8_121)
        #expect(SummaryPlan.characterBudget(contextSize: 1_500, fixedTokens: 600, sampleCharacters: 400, sampleTokens: 100) == SummaryPlan.minimumCharacters)
    }

    @Test func aPartIsCutInTwoBetweenLinesOrAtASpace() {
        let (first, second) = SummaryPlan.halves("ligne une\nligne deux\nligne trois\nligne quatre\n")
        #expect(first == "ligne une\nligne deux\n" && second == "ligne trois\nligne quatre\n")
        let (left, right) = SummaryPlan.halves("un deux trois quatre cinq six")
        #expect(left + " " + right == "un deux trois quatre cinq six" && !left.isEmpty && !right.isEmpty)
    }

    @Test func notesThatDoNotFitLoseTheirPointsFirstAndSaySo() {
        let one = SummaryNotes.text(part: 1, points: ["Un point assez long pour compter."], decisions: ["Garder WordPress."], actions: ["Envoyer le devis"])
        let two = SummaryNotes.text(part: 2, points: ["Un autre point assez long."], decisions: [], actions: ["Relire la maquette"])
        #expect(SummaryNotes.fit([one, two], budget: 1_000) == ([one, two], false))
        let budget = [one, two].joined(separator: "\n\n").count - 10
        let (fitted, shortened) = SummaryNotes.fit([one, two], budget: budget)
        #expect(shortened && fitted == [one, "Partie 2\nPoints :\nDécisions :\n\nActions :\n- Relire la maquette"])
        let (cut, alsoShortened) = SummaryNotes.fit([one, two], budget: 30)
        #expect(alsoShortened && cut.count == 1 && cut[0].count == 30)
    }

    @Test func whatIsMissingIsSaidForPaul() {
        #expect(SummaryText.missing(dropped: [], of: 5, shortened: false) == nil)
        #expect(SummaryText.missing(dropped: [2, 4, 5], of: 5, shortened: true)
                == "les parties 2, 4 et 5 sur 5 n'ont pas pu être résumées (refusées par le modèle d'Apple) ; les notes ont été raccourcies pour tenir dans la fenêtre du modèle")
    }
}
