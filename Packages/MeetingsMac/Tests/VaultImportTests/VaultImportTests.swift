import Foundation
import Testing
@testable import VaultImport

/// A synthetic vault in the repository: the structure of Paul's notes, none of their content.
let fixtureVault = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/coffre", directoryHint: .isDirectory)

func day(_ text: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = text.count > 10 ? "yyyy-MM-dd'T'HH:mm" : "yyyy-MM-dd"
    return formatter.date(from: text)!
}

func fixtureNote(_ name: String) throws -> String {
    try String(contentsOf: fixtureVault.appending(path: "database/Projets/\(name).md"), encoding: .utf8)
}

@Suite struct NoteParserTests {
    @Test func frontmatterBecomesProperties() throws {
        let (project, warning) = NoteParser.parse(try fixtureNote("Alpha"), name: "Alpha")
        #expect(warning == nil)
        #expect(project.status == "priorité 2" && project.client == "Atelier Nord" && project.todo == "Envoyer la maquette de la page d'accueil")
        #expect(project.dueDate == day("2026-11-20") && project.createdOn == day("2026-10-01"))
        #expect(project.contacts == ["Camille Exemple"] && project.icon == "🎯" && project.color == "blue")
        #expect(project.codeFolder == "/Users/exemple/Code/alpha")
    }

    @Test func twoNotesSectionsAreJoined() throws {
        let (project, _) = NoteParser.parse(try fixtureNote("Alpha"), name: "Alpha")
        #expect(project.notes == "- **6 nov.** — Premier rendez-vous avec Camille, voir Alpha.\n\nDeuxième feuille de notes.")
    }

    @Test func actionsKeepTheirDoneStateAndDate() throws {
        let (project, _) = NoteParser.parse(try fixtureNote("Alpha"), name: "Alpha")
        #expect(project.actions == [
            ImportedAction(text: "Lire la fiche du client", done: false, addedOn: day("2026-11-06")),
            ImportedAction(text: "Envoyer le devis", done: true, addedOn: day("2026-11-07")),
        ])
    }

    @Test func journalEntriesKeepDateTitleAndBody() throws {
        let (project, _) = NoteParser.parse(try fixtureNote("Alpha"), name: "Alpha")
        #expect(project.journal == [
            ImportedJournalEntry(date: day("2026-11-06"), title: "Note projet créée",
                                 body: "- Créée à partir de l'agenda.\n- Retour arrière : supprimer la note."),
            ImportedJournalEntry(date: day("2026-11-08"), title: "Maquette envoyée", body: "- Deux pages."),
        ])
    }

    @Test func generatedSectionsAreIgnored() throws {
        let (project, _) = NoteParser.parse(try fixtureNote("Alpha"), name: "Alpha")
        let everything = project.notes + project.actions.map(\.text).joined() + project.journal.map { $0.title + $0.body }.joined()
        for generated in ["Pour une IA", "file.inFolder", "bloc: messages", "Texte généré"] {
            #expect(!everything.contains(generated))
        }
    }

    @Test func aNoteWithoutPropertiesStillComes() throws {
        let (project, warning) = NoteParser.parse(try fixtureNote("Sans propriétés"), name: "Sans propriétés")
        #expect(project.name == "Sans propriétés" && project.status == nil && project.notes == "Une note sans en-tête.")
        #expect(warning == nil)
    }

    @Test func brokenYAMLGivesAWarningNotAFailure() throws {
        let (project, warning) = NoteParser.parse(try fixtureNote("YAML cassé"), name: "YAML cassé")
        #expect(project.status == nil && project.notes == "Le corps reste lisible.")
        #expect(warning?.contains("YAML cassé") == true)
    }
}

// Revue finale du module Projets.
@Suite struct NoteParserReviewTests {
    @Test func emptyPropertiesAreNone() {
        let (project, _) = NoteParser.parse("---\nstatut: priorité 1\ntodo:\nicone:\ncontacts:\nclient: [[Atelier Nord]]\n---\n", name: "Vide")
        #expect(project.todo == nil && project.icon == nil && project.contacts.isEmpty)
        #expect(project.client == "Atelier Nord")
    }

    @Test func paulsOwnSectionsStayInTheNotes() {
        let text = "> [!info]- généré\n\n## Réunions\ngénéré\n\n## Notes\nIntro\n\n## Brief client\nTexte important\n\n## Actions\n- [ ] Faire\n\n## Journal\n### 2026-11-06 — Fait\n- oui\n\n## Annexe\nSuite"
        let (project, _) = NoteParser.parse(text, name: "Sections")
        #expect(project.notes == "Intro\n\n## Brief client\nTexte important\n\n## Annexe\nSuite")
        #expect(project.actions.map(\.text) == ["Faire"] && project.journal.map(\.title) == ["Fait"])
    }

    @Test func windowsLineEndingsAndABOMAreRead() {
        let text = "\u{FEFF}---\r\nstatut: idée\r\n---\r\n## Notes\r\nUne ligne.\r\n## Actions\r\n- [ ] Faire · 2026-11-06\r\n"
        let (project, _) = NoteParser.parse(text, name: "CRLF")
        #expect(project.status == "idée" && project.notes == "Une ligne.")
        #expect(project.actions.map(\.text) == ["Faire"])
    }

    @Test func otherCheckboxMarksAreActions() {
        let (project, _) = NoteParser.parse("## Actions\n- [/] En cours\n- [-] Abandonnée\n+ [ ] Plus\n1. [ ] Numérotée", name: "Cases")
        #expect(project.actions.map(\.text) == ["En cours", "Abandonnée", "Plus", "Numérotée"])
        #expect(project.actions.map(\.done) == [true, true, false, false])
    }
}

@Suite struct VaultReaderTests {
    @Test func theKanbanViewGivesTheCardOrder() throws {
        let base = try String(contentsOf: fixtureVault.appending(path: "Projets.base"), encoding: .utf8)
        let order = BaseOrder.cardOrder(baseYAML: base)
        #expect(order["priorité 2"] == ["Beta Studio", "Alpha"])
        #expect(order["idée"] == ["Gamma"])
    }

    @Test func meetDatesComeFromTheProjectPropertyAndLinks() throws {
        let snapshot = try VaultReader.read(vault: fixtureVault)
        #expect(snapshot.lastMeetings["Alpha"] == day("2026-11-05T14:30"))
        #expect(snapshot.lastMeetings["Beta Studio"] == day("2026-11-05T14:30"))
        #expect(snapshot.lastMeetings["Gamma"] == nil)
    }

    @Test func theWholeVaultIsRead() throws {
        let snapshot = try VaultReader.read(vault: fixtureVault)
        #expect(snapshot.projects.map(\.name).sorted() == ["Alpha", "Beta Studio", "Delta", "Gamma", "Sans propriétés", "YAML cassé"])
        #expect(snapshot.projects.first { $0.name == "Alpha" }?.relativePath == "database/Projets/Alpha.md")
        #expect(snapshot.warnings.count == 1)
    }

    @Test func aFolderWithoutProjectsIsNotAVault() {
        #expect(throws: VaultError.self) { try VaultReader.read(vault: fixtureVault.appending(path: "database")) }
    }

    @Test func wikiLinksBecomePlainText() {
        #expect(WikiLinks.plain("Voir [[Alpha]] et [[Beta Studio|Beta]], [[Gamma#Notes]].") == "Voir Alpha et Beta, Gamma.")
    }
}
