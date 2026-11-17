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
    }

    /// Paul, 17/11: « une mise en forme comme si j'étais sur Gmail, et que je puisse la modifier ». An agent's formatted
    /// draft opens formatted in the editor; a plain one opens as its lines; what Paul writes keeps its formatting and
    /// its plain text beside it.
    @Test func theEditorOpensTheDraftFormattedAndKeepsWhatPaulWrites() {
        let date = Date(timeIntervalSince1970: 1_794_562_920)
        var draft = MailDraftRow(account: "moi@exemple.fr", mode: .reply, subject: "Re: Devis", body: "Bonjour Camille,\n\n• le devis",
                                 bodyHTML: "<p><b>Bonjour</b> Camille,</p><ul><li>le devis</li></ul>", quoteHTML: "<div class=\"gmail_quote\">cité</div>",
                                 quoteText: "> cité", origin: .agent, createdAt: date)
        #expect(draft.editorHTML == "<p><b>Bonjour</b> Camille,</p><ul><li>le devis</li></ul>" && !draft.isFormattedGmailDraft)
        draft.write(html: #"<p><b>Bonjour</b> Camille,</p><ul><li>le devis</li><li><i>la maquette</i></li></ul><p style="color:red">À lundi</p>"#)
        #expect(draft.bodyHTML == "<p><b>Bonjour</b> Camille,</p><ul><li>le devis</li><li><i>la maquette</i></li></ul><p>À lundi</p>")
        #expect(draft.body == "Bonjour Camille,\n• le devis\n• la maquette\nÀ lundi" && draft.quoteHTML != nil)
        // All taken out: no formatted text is left behind.
        draft.write(html: "<div><br></div>")
        #expect(draft.bodyHTML == nil && draft.body.isEmpty)
        let plain = MailDraftRow(account: "moi@exemple.fr", mode: .new, subject: "Devis", body: "Bonjour\n\nhttps://exemple.fr", createdAt: date)
        #expect(plain.editorHTML == "<div>Bonjour</div><div><br></div><div><a href=\"https://exemple.fr\">https://exemple.fr</a></div>")
    }

    /// What Paul types for a link: a web address made whole, a mail address made a mailto, nothing that runs.
    @MainActor @Test func theLinkPromptTakesWhatPaulTypes() {
        #expect(RichTextController.address("exemple.fr/devis") == "https://exemple.fr/devis")
        #expect(RichTextController.address(" https://exemple.fr ") == "https://exemple.fr")
        #expect(RichTextController.address("camille@exemple.fr") == "mailto:camille@exemple.fr")
        #expect(RichTextController.address("javascript:alert(1)") == nil)
        #expect(RichTextController.address("file:///etc/passwd") == nil)
        #expect(RichTextController.address("deux mots") == nil)
    }
}
