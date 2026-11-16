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
}
