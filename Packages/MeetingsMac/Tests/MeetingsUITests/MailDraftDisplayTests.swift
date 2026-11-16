import Foundation
import Persistence
import Testing
@testable import MeetingsUI

/// Paul, 16/11: « je vois le brouillon… mais pas le texte ». A draft written in Gmail with formatting shows its
/// text as the draft's, never folded as a quote.
@Suite struct MailDraftDisplayTests {
    @Test func aFormattedGmailDraftIsTheDraftNotAQuote() {
        let date = Date(timeIntervalSince1970: 1_794_562_920)
        let gmail = MailDraftRow(account: "moi@exemple.fr", mode: .new, subject: "Devis", body: "", quoteHTML: "<p><b>Bonjour</b></p>",
                                 quoteText: "Bonjour", origin: .gmail, createdAt: date)
        #expect(gmail.isFormattedGmailDraft)
        let reply = MailDraftRow(account: "moi@exemple.fr", mode: .reply, subject: "Re: Devis", body: "Merci", quoteHTML: "<div class=\"gmail_quote\">cité</div>",
                                 quoteText: "> cité", createdAt: date)
        #expect(!reply.isFormattedGmailDraft)
        let plain = MailDraftRow(account: "moi@exemple.fr", mode: .new, subject: "Devis", body: "Bonjour", origin: .gmail, createdAt: date)
        #expect(!plain.isFormattedGmailDraft)
        #expect(gmail.formattedText == nil && plain.formattedText == nil)
    }

    /// Paul, 16/11: an agent's formatted draft leaves as the agent formatted it. The composer shows its text whole
    /// with a caption, not in the editor; « Repasser en texte simple » gives the plain version to edit as usual.
    @Test func anAgentsFormattedDraftShowsWholeUntilPaulMakesItPlain() throws {
        let date = Date(timeIntervalSince1970: 1_794_562_920)
        var draft = MailDraftRow(account: "moi@exemple.fr", mode: .reply, subject: "Re: Devis", body: "Bonjour Camille,\n\n- le devis",
                                 bodyHTML: "<p><b>Bonjour</b> Camille,</p><ul><li>le devis</li></ul>", quoteHTML: "<div class=\"gmail_quote\">cité</div>",
                                 quoteText: "> cité", origin: .agent, createdAt: date)
        #expect(draft.formattedText == "Bonjour Camille,\n\n- le devis" && !draft.isFormattedGmailDraft)
        // The caption says what Paul sees: the text without its formatting, which leaves formatted (review of 16/11).
        #expect(MailDraftRow.agentFormattedCaption == "Mis en forme par l'agent (gras, listes, liens) : il part ainsi. Ici, son texte sans la mise en forme.")
        let setAside = draft.makePlain()
        #expect(draft.formattedText == nil && draft.bodyHTML == nil && draft.body == "Bonjour Camille,\n\n- le devis" && draft.quoteHTML != nil)
        // Taken back while Paul has not written in the text: « Remettre la mise en forme » (review of 16/11).
        #expect(setAside == "<p><b>Bonjour</b> Camille,</p><ul><li>le devis</li></ul>")
        draft.formatAgain(try #require(setAside))
        #expect(draft.formattedText == "Bonjour Camille,\n\n- le devis")
    }
}
