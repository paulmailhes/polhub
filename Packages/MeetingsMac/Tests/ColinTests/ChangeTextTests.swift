import Domain
import Foundation
import Persistence
import Testing
@testable import Colin

/// How a change of Colin's reads in his thread (step 3, 18/11): one sentence, the project first, what it was and what
/// it became. Every name is invented.
@Suite struct ChangeTextTests {
    let now = Date(timeIntervalSince1970: 1_794_992_400)
    let project = UUID()

    var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    func row(_ field: ProjectChangeField, _ before: String?, _ after: String?, detail: String? = nil) -> ProjectChangeRow {
        ProjectChangeRow(id: 1, projectID: project, field: field, subject: nil, before: before, after: after, detail: detail, who: .colin, batch: "b",
                         reason: nil, source: nil, at: now, undoneAt: nil)
    }

    func line(_ rows: [ProjectChangeRow], reason: String? = nil) -> ProjectChangeLine {
        ProjectChangeLine(id: "c1", projectID: project, projectName: "Cabinet Martin", who: .colin, at: now, reason: reason, rows: rows, undoneAt: nil)
    }

    @Test func aRuleAfterAMail() {
        let said = ChangeText.sentence(line([row(.status, "priorité 2", "priorité 1"), row(.todo, nil, "En attente retour de Claire"),
                                             row(.journalAdded, nil, "Mail envoyé à Claire le 18/11")], reason: "Après ton mail à Claire, 9:50"), calendar: paris)
        #expect(said == "« Cabinet Martin » : priorité 2 → priorité 1, tâche « En attente retour de Claire », journal « Mail envoyé à Claire le 18/11 ».")
        #expect(ChangeText.note(line([], reason: "Après ton mail à Claire, 9:50")) == "Après ton mail à Claire, 9:50")
    }

    /// A deadline is a day of Paris, whatever the hour it is kept at.
    @Test func eachKindSaysItself() {
        func said(_ rows: [ProjectChangeRow]) -> String { ChangeText.sentence(line(rows), calendar: paris) }
        #expect(said([row(.dueDate, nil, "2026-11-18 23:00:00.000")]) == "« Cabinet Martin » : échéance 19/11.")
        #expect(said([row(.dueDate, "2026-11-18 23:00:00.000", "2026-11-26 23:00:00.000")]) == "« Cabinet Martin » : échéance 19/11 → 27/11.")
        #expect(said([row(.dueDate, "2026-11-18 23:00:00.000", nil)]) == "« Cabinet Martin » : échéance retirée.")
        #expect(said([row(.todo, "Appeler Claire", nil)]) == "« Cabinet Martin » : tâche retirée.")
        #expect(said([row(.client, nil, "Cabinet Martin SARL")]) == "« Cabinet Martin » : client « Cabinet Martin SARL ».")
        #expect(said([row(.notes, "a", "b")]) == "« Cabinet Martin » : notes réécrites.")
        #expect(said([row(.actionAdded, nil, "Relancer Claire")]) == "« Cabinet Martin » : action « Relancer Claire » ajoutée.")
        #expect(said([row(.actionAdded, nil, "Relancer Claire"), row(.actionAdded, nil, "Payer")]) == "« Cabinet Martin » : 2 actions ajoutées.")
        #expect(said([row(.actionDone, "0", "1", detail: #"{"text":"Envoyer le devis"}"#)]) == "« Cabinet Martin » : action « Envoyer le devis » cochée.")
        #expect(said([row(.actionText, "Appeler", "Appeler Claire")]) == "« Cabinet Martin » : action reformulée, « Appeler Claire ».")
        #expect(said([row(.actionRemoved, "Payer", nil)]) == "« Cabinet Martin » : action « Payer » retirée.")
        #expect(said([row(.journalAdded, nil, "Devis relu"), row(.journalAdded, nil, "Maquette")]) == "« Cabinet Martin » : 2 entrées au journal.")
    }

    /// Behind « Voir », who made each change and when, then why.
    @Test func whoMadeIt() {
        var agents = line([row(.todo, nil, "Relire")])
        agents.who = .agent
        #expect(ChangeText.byline(agents, now: now, calendar: paris) == "Un agent, aujourd'hui 10:00")
        #expect(ChangeText.byline(line([], reason: "Rendez-vous du jeudi 19/11"), now: now.addingTimeInterval(86_400), calendar: paris)
                == "Colin, hier 10:00 · Rendez-vous du jeudi 19/11")
    }

    /// The Accueil's pass (18/11): a change as a small card, a line by field, before → after.
    @Test func fieldsSayBeforeAndAfter() {
        let fields = ChangeText.fields(line([row(.status, "priorité 2", "priorité 1"), row(.dueDate, nil, "2026-11-18 23:00:00.000"),
                                             row(.todo, "Appeler", nil), row(.actionDone, "0", "1", detail: #"{"text":"Envoyer le devis"}"#),
                                             row(.journalAdded, nil, "Devis relu")]), calendar: paris)
        #expect(fields == [
            ChangeField(label: "Statut", before: "priorité 2", after: "priorité 1"),
            ChangeField(label: "Échéance", before: nil, after: "19/11"),
            ChangeField(label: "Tâche", before: "Appeler", after: nil),
            ChangeField(label: "Action", before: "Envoyer le devis", after: "faite"),
            ChangeField(label: "Journal", before: nil, after: "Devis relu"),
        ])
    }

    /// 19/11: a project Colin created reads as one: its column, client and deadline, never « before ».
    @Test func aCreatedProjectSaysItsFields() {
        let created = line([row(.created, nil, "Cabinet Martin", detail: "priorité 1"), row(.dueDate, nil, "2026-12-03 23:00:00.000"),
                            row(.client, nil, "Studio Nord")])
        #expect(ChangeText.isCreation(created))
        #expect(!ChangeText.isCreation(line([row(.todo, nil, "Relire")])))
        #expect(ChangeText.sentence(created, calendar: paris) == "Nouveau projet « Cabinet Martin » : priorité 1, échéance 04/12, client « Studio Nord ».")
        #expect(ChangeText.fields(created, calendar: paris) == [
            ChangeField(label: "Statut", before: nil, after: "priorité 1"),
            ChangeField(label: "Échéance", before: nil, after: "04/12"),
            ChangeField(label: "Client", before: nil, after: "Studio Nord"),
        ])
        #expect(ChangeText.sentence(line([row(.created, nil, "Cabinet Martin", detail: "priorité 2")]), calendar: paris)
                == "Nouveau projet « Cabinet Martin » : priorité 2.")
    }

    @Test func whatAnUndoDid() {
        #expect(ChangeText.undone(.undone) == "Annulé.")
        #expect(ChangeText.undone(.partly(kept: 1)) == "Annulé, sauf ce qui a changé depuis.")
        #expect(ChangeText.undone(.changedSince) == "Rien à annuler : ça a changé depuis.")
    }
}
