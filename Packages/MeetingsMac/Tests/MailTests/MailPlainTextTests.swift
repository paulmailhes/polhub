import Foundation
import Testing
@testable import Mail

/// Paul, 19/11: in an open thread, the quoted history and the signatures take all the room. A mail in plain text is cut
/// in three — what was written, the signature, the history — and the page folds the last two. Every name, address and
/// number here is invented; the shapes are those of real mails (Gmail, Outlook, Apple Mail, in French and English).
@Suite struct MailPlainTextTests {
    @Test func aGmailReplyLeavesItsHistory() {
        let body = """
        Bonjour Camille,

        C'est noté, je regarde demain.

        Le jeu. 8 oct. 2026 à 17:28, Camille Martin <camille@exemple.fr> a écrit :
        > Bonjour Paul,
        > Voici nos commentaires.
        """
        let parts = MailPlainText.parts(body)
        #expect(parts.text == "Bonjour Camille,\n\nC'est noté, je regarde demain.")
        #expect(parts.quote?.hasPrefix("Le jeu. 8 oct. 2026 à 17:28") == true)
        #expect(parts.signature == nil)
    }

    /// The attribution can wrap before « a écrit : », and come in English with an RFC date.
    @Test func wrappedAndEnglishAttributions() {
        let wrapped = "Merci !\n\nLe lun. 19 oct. 2026 à 17:45, Léa Durand <lea@exemple.fr>\n> a écrit :\n> Bonjour\n"
        #expect(MailPlainText.parts(wrapped).text == "Merci !")
        let english = "Top.\n\nOn Tue, 09 Jun 2026 16:13:18 GMT Camille Martin <camille@exemple.fr> wrote:\nBonsoir à tous,\n"
        #expect(MailPlainText.parts(english).text == "Top.")
        #expect(MailPlainText.parts(english).quote?.hasPrefix("On Tue, 09 Jun 2026") == true)
    }

    /// Outlook's header block, in French (Envoyé or Date) and in English after a line of underscores.
    @Test func outlookHeaderBlocks() {
        let french = """
        Bien reçu, merci.

        De : Camille Martin <camille@exemple.fr>
        Envoyé : jeudi 5 novembre 2026 14:20
        À : Durand, Léa <lea@exemple.fr>; Petit, Hugo <hugo@exemple.fr>
        Objet : RE: Suite de notre call

        Bonjour,
        """
        #expect(MailPlainText.parts(french).text == "Bien reçu, merci.")
        #expect(MailPlainText.parts(french).quote?.hasPrefix("De : Camille Martin") == true)
        let english = """
        Great, thanks.

        Sent from Outlook for iOS
        ________________________________
        From: Camille Martin <camille@exemple.fr>
        Sent: Thursday, 08 October 2026 17:32:24
        To: Léa Durand <lea@exemple.fr>
        Subject: Re: Website
        """
        let parts = MailPlainText.parts(english)
        #expect(parts.text == "Great, thanks.")
        #expect(parts.signature == "Sent from Outlook for iOS")
        #expect(parts.quote?.hasPrefix("________________________________") == true)
    }

    /// A signature after a closing and a first name: the closing and the name stay; the block with a phone, a site or a
    /// legal notice is folded. The standard « -- » delimiter too.
    @Test func signaturesAfterAClosingOrADelimiter() {
        let closing = """
        Bonjour Paul,

        Voici le devis signé.

        Bien à vous,

        Camille
        Studio Exemple
        T +33 1 23 45 67 89 | M +33 6 12 34 56 78
        12 rue de l'Exemple, 75001 Paris
        www.exemple.fr
        Ce message et ses pièces jointes sont confidentiels.
        """
        let parts = MailPlainText.parts(closing)
        #expect(parts.text == "Bonjour Paul,\n\nVoici le devis signé.\n\nBien à vous,\n\nCamille")
        #expect(parts.signature?.hasPrefix("Studio Exemple") == true && parts.signature?.hasSuffix("confidentiels.") == true)
        let delimited = "Merci pour tout.\n\n-- \nCamille Martin\nStudio Exemple\n"
        #expect(MailPlainText.parts(delimited).text == "Merci pour tout.")
        #expect(MailPlainText.parts(delimited).signature == "-- \nCamille Martin\nStudio Exemple")
    }

    /// What must stay whole: prose that says « a écrit », a short « Merci / Camille », a mail made only of a quote, a
    /// forward, and a closing followed by lines that are no signature.
    @Test func whatIsNeverFolded() {
        let prose = "Le directeur a écrit : il faut finir vendredi.\nJe m'en occupe."
        #expect(MailPlainText.parts(prose) == MailPlainText.Parts(text: prose, signature: nil, quote: nil))
        let short = "Merci,\nCamille"
        #expect(MailPlainText.parts(short) == MailPlainText.Parts(text: short, signature: nil, quote: nil))
        let onlyQuote = "On Mon, 9 Nov 2026 08:14:32 +0000, Camille Martin <camille@exemple.fr> wrote:\nBonjour,\nla suite.\n"
        #expect(MailPlainText.parts(onlyQuote).quote == nil)
        let forward = """
        Pour info.

        ---------- Message transféré ---------
        De : Camille Martin <camille@exemple.fr>
        Date : ven. 25 sept. 2026 à 17:31
        Objet : Planning
        À : Paul <paul@exemple.fr>

        Le planning est en pièce jointe.
        """
        #expect(MailPlainText.parts(forward).quote == nil)
        let notASignature = "Merci beaucoup,\nCamille\nPS : je serai en retard demain.\nOn se voit après."
        #expect(MailPlainText.parts(notASignature).signature == nil)
    }

    /// No-break spaces (Outlook's « De : ») and a trailing run of « > » lines.
    @Test func noBreakSpacesAndTrailingQuotes() {
        let outlook = "Ok.\n\nDe\u{00A0}: Camille Martin\nEnvoyé\u{00A0}: mardi 21 avril 2026 18:00\nÀ\u{00A0}: Paul\nObjet\u{00A0}: RE: RDV\n"
        #expect(MailPlainText.parts(outlook).text == "Ok.")
        let marked = "Vu.\n\n> Bonjour,\n> le fichier est prêt.\n> Camille\n"
        #expect(MailPlainText.parts(marked).text == "Vu.")
        #expect(MailPlainText.parts(marked).quote?.hasPrefix("> Bonjour") == true)
        let two = "Vu.\n> une ligne\n> deux lignes\n"
        #expect(MailPlainText.parts(two).quote == nil)
    }
}
