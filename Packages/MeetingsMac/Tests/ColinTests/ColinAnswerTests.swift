import Foundation
import Testing
@testable import Colin

/// An answer of Colin's as the thread shows it (18/11): its text, a message to copy, a line to keep; and no link
/// written by the model is ever clickable.
@Suite struct ColinAnswerTests {
    @Test func aMessageToCopyAndALineToKeepAreBlocks() {
        let answer = """
            Voilà pour Marc.
            ```message
            Salut Marc, je t'envoie la maquette ce soir.
            Bonne journée !
            ```
            Et je retiens ceci :
            ```retenir
            Marc préfère WhatsApp.
            ```
            """
        #expect(ColinAnswer.blocks(answer) == [.text("Voilà pour Marc."), .message("Salut Marc, je t'envoie la maquette ce soir.\nBonne journée !"),
                                               .text("Et je retiens ceci :"), .keep("Marc préfère WhatsApp.")])
        #expect(ColinAnswer.blocks("Trois projets.") == [.text("Trois projets.")])
        // Any other fenced block is text.
        #expect(ColinAnswer.blocks("```\ncode\n```") == [.text("```\ncode\n```")])
    }

    @Test func anUnclosedBlockStaysText() {
        #expect(ColinAnswer.blocks("Voilà :\n```message\nSalut Marc") == [.text("Voilà :\n```message\nSalut Marc")])
        #expect(ColinAnswer.blocks("") == [])
    }

    @Test func aLinkInAnAnswerIsPlainText() {
        for text in ["Regarde [ici](https://exemple.fr/x) puis réponds.", "Le lien : <https://exemple.fr/rdv>.", "Brut : https://exemple.fr/y"] {
            let shown = ColinAnswer.inline(text)
            #expect(shown.runs.allSatisfy { $0.link == nil }, "\(text)")
        }
        #expect(String(ColinAnswer.inline("Regarde [ici](https://exemple.fr/x).").characters) == "Regarde ici (https://exemple.fr/x).")
        #expect(String(ColinAnswer.inline("Le lien : <https://exemple.fr/rdv>.").characters) == "Le lien : https://exemple.fr/rdv.")
        // The rest of the markdown stays: bold, italics.
        let bold = ColinAnswer.inline("C'est **urgent**.")
        #expect(String(bold.characters) == "C'est urgent.")
        #expect(bold.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    }

    /// The Accueil's pass (18/11): while Colin writes, a block begun is already its card; done, a block never closed is
    /// text.
    @Test func anOpenBlockShowsWhileWritten() {
        let writing = "Voilà.\n```message\nSalut Marc, je t'envoie"
        #expect(ColinAnswer.blocks(writing, open: true) == [.text("Voilà."), .message("Salut Marc, je t'envoie")])
        #expect(ColinAnswer.blocks(writing) == [.text("Voilà.\n```message\nSalut Marc, je t'envoie")])
    }
}
