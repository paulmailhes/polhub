import Foundation
import Persistence
import Testing
@testable import Colin

/// The words of Colin's actions (the Accueil's pass, 18/11): what he is doing in the present, what he did in the past,
/// in words Paul reads — never a tool's name. Every name is invented.
@Suite struct ColinStepTextTests {
    func step(_ tool: String, _ arguments: [String: String] = [:], id: String = UUID().uuidString, state: ColinStep.State = .done,
              position: Int = 0) -> ColinStep {
        ColinStep(id: id, tool: tool, arguments: arguments, state: state, position: position)
    }

    /// A thread is said by its subject and its project, as the Accueil's base knows them.
    func subject(_ step: ColinStep) -> StepSubject {
        step.tool == "mail" ? StepSubject(title: "Devis · Claire Morel", project: "Cabinet Martin") : StepSubject(title: nil, project: step.arguments["projet"])
    }

    func said(_ steps: [ColinStep]) -> (present: String, past: String) {
        let group = StepGroup(steps: steps)
        return (ColinStepText.present(group, subject: subject), ColinStepText.past(group, subject: subject))
    }

    @Test func readsFold() {
        let groups = ColinStepText.groups([step("mail", position: 4), step("mail", position: 4), step("mail", position: 4),
                                           step("contexte", ["projet": "Studio Nord"], position: 4)])
        #expect(groups.map(\.steps.count) == [3, 1])
        // Final review (18/11): reads with text between them stay apart, each at its place.
        #expect(ColinStepText.groups([step("mail", position: 4), step("mail", position: 30)]).map(\.position) == [4, 30])
        #expect(groups.first?.position == 4)
        #expect(ColinStepText.past(groups[0], subject: subject) == "A lu 3 fils · Cabinet Martin")
    }

    @Test func aWriteStandsAlone() {
        let groups = ColinStepText.groups([step("projet", ["projet": "Studio Nord"]), step("projet", ["projet": "Studio Nord"]), step("brouillon")])
        #expect(groups.map(\.steps.count) == [1, 1, 1])
    }

    @Test func eachToolHasItsWords() {
        #expect(said([step("mails", ["projet": "Cabinet Martin"])]) == ("Cherche dans tes mails · Cabinet Martin…", "A cherché dans tes mails · Cabinet Martin"))
        #expect(said([step("mail")]) == ("Lit le fil « Devis · Claire Morel »…", "A lu le fil « Devis · Claire Morel »"))
        #expect(said([step("contexte", ["projet": "Studio Nord"])]) == ("Lit le projet Studio Nord…", "A lu le projet Studio Nord"))
        #expect(said([step("contexte", ["projet": "Studio Nord"]), step("contexte", ["projet": "Maison Leroy"])]) == ("Lit 2 projets…", "A lu 2 projets"))
        #expect(said([step("projets")]) == ("Regarde tes projets…", "A regardé tes projets"))
        #expect(said([step("actions", ["projet": "Studio Nord"])]) == ("Lit les actions de Studio Nord…", "A lu les actions de Studio Nord"))
        #expect(said([step("reunions")]) == ("Cherche tes réunions…", "A cherché tes réunions"))
        #expect(said([step("reunion")]) == ("Lit une réunion…", "A lu une réunion"))
        #expect(said([step("chercher", ["texte": "maquette"])]) == ("Cherche « maquette »…", "A cherché « maquette »"))
        #expect(said([step("agenda")]) == ("Regarde ton agenda…", "A regardé ton agenda"))
        #expect(said([step("contacts", ["texte": "Claire"])]) == ("Cherche « Claire »…", "A cherché « Claire »"))
        #expect(said([step("brouillon")]) == ("Écrit un brouillon…", "A écrit un brouillon"))
        #expect(said([step("fait", ["projet": "Studio Nord"])]) == ("Met à jour Studio Nord…", "A mis à jour Studio Nord"))
        #expect(said([step("autre")]) == ("Travaille…", "A travaillé"))
    }

    @Test func aFailedStepSaysIt() {
        #expect(said([step("brouillon", state: .failed)]).past == "A écrit un brouillon (raté)")
    }

    @Test func argumentsAreShort() {
        let long = String(repeating: "m", count: 300)
        #expect(said([step("chercher", ["texte": long])]).past == "A cherché « \(String(repeating: "m", count: 59))… »")
    }

    @Test func eachToolHasItsSymbol() {
        #expect(ColinStepText.symbol("mails") == "envelope" && ColinStepText.symbol("agenda") == "calendar" && ColinStepText.symbol("projet") == "checklist")
        #expect(ColinStepText.symbol("autre") == "sparkle")
    }
}
