import Foundation
import Testing
@testable import MailFormat

/// Paul, 17/11: « une mise en forme comme si j'étais sur Gmail, et que je puisse la modifier ». What the editor gives
/// is kept to simple formatting before it is saved or sent.
@Suite struct MailRichTextTests {
    /// Bold, italic, underline, lists, quotes and links stay; everything else goes or keeps only its text.
    @Test func onlySimpleFormattingStays() {
        #expect(MailRichText.clean("<div>Bonjour <b>Camille</b>,</div><div><i>merci</i> <u>vraiment</u></div>")
                == "<div>Bonjour <b>Camille</b>,</div><div><i>merci</i> <u>vraiment</u></div>")
        #expect(MailRichText.clean("<ul><li>la maquette</li><li>le devis</li></ul><ol start=\"3\"><li>trois</li></ol>")
                == "<ul><li>la maquette</li><li>le devis</li></ul><ol start=\"3\"><li>trois</li></ol>")
        #expect(MailRichText.clean(#"<p>Voir <a href="https://exemple.fr/planning">le planning</a></p>"#)
                == #"<p>Voir <a href="https://exemple.fr/planning">le planning</a></p>"#)
        #expect(MailRichText.clean("<blockquote>cité</blockquote><strong>fort</strong><em>penché</em>")
                == "<blockquote>cité</blockquote><strong>fort</strong><em>penché</em>")
    }

    /// Scripts, styles, images, handlers, colours, fonts and dangerous links never pass.
    @Test func nothingElsePasses() {
        #expect(MailRichText.clean("<p onclick=\"x()\" style=\"color:red\" class=\"c\">texte</p>") == "<p>texte</p>")
        #expect(MailRichText.clean("<p>a<script>alert(1)</script><style>p{}</style>b</p>") == "<p>ab</p>")
        #expect(MailRichText.clean(#"<p>logo <img src="https://pisteur.exemple/x.gif"> fin</p>"#) == "<p>logo  fin</p>")
        #expect(MailRichText.clean(#"<span style="font-weight:bold"><font color="red">rouge</font></span>"#) == "rouge")
        #expect(MailRichText.clean(#"<a href="javascript:alert(1)">piège</a> <a href="mailto:camille@exemple.fr">écrire</a>"#)
                == #"piège <a href="mailto:camille@exemple.fr">écrire</a>"#)
        #expect(MailRichText.clean("<iframe src=\"https://exemple.fr\"></iframe><p>reste</p>") == "<p>reste</p>")
        #expect(MailRichText.clean("ligne<br>suivante") == "ligne<br>suivante")
    }

    /// The text part of the mail: paragraphs and line breaks kept, lists as bullets, a link's address kept.
    @Test func theTextPartFollows() {
        #expect(MailRichText.plain("<div>Bonjour <b>Camille</b>,</div><div><br></div><ul><li>la maquette</li><li>le devis</li></ul><div>À bientôt</div>")
                == "Bonjour Camille,\n\n• la maquette\n• le devis\nÀ bientôt")
        #expect(MailRichText.plain(#"Voir <a href="https://exemple.fr/planning">le planning</a>."#) == "Voir le planning (https://exemple.fr/planning).")
        #expect(MailRichText.plain(#"<a href="https://exemple.fr">https://exemple.fr</a>"#) == "https://exemple.fr")
    }

    /// A plain draft opens in the editor as it is: its lines, its addresses as links, nothing to interpret.
    @Test func aPlainDraftOpensAsItIs() {
        #expect(MailRichText.html(fromPlain: "Bonjour <Camille>,\n\nVoir https://exemple.fr/devis\nMerci")
                == "<div>Bonjour &lt;Camille&gt;,</div><div><br></div><div>Voir <a href=\"https://exemple.fr/devis\">https://exemple.fr/devis</a></div><div>Merci</div>")
        #expect(MailRichText.html(fromPlain: "") == "")
    }
}

/// What an agent reads of a draft Paul formatted (17/11), to give it back changed without losing its formatting.
@Suite struct MailRichTextMarkdownTests {
    @Test func aFormattedDraftReadsAsTheAgentsMarkdown() {
        let html = #"<p><b>Bonjour</b> Camille,</p><p>Voici <i>le devis</i> et <u>la date</u> :</p><ul><li>la maquette</li><li><a href="https://exemple.fr/plan">le planning</a></li></ul><ol><li>relire</li><li>signer</li></ol>"#
        #expect(MailRichText.markdown(html) == "**Bonjour** Camille,\n\nVoici *le devis* et la date :\n\n- la maquette\n- [le planning](https://exemple.fr/plan)\n\n1. relire\n2. signer")
        // Written in the editor: a block a line.
        #expect(MailRichText.markdown("<div>Bonjour Nina,</div><div><br></div><div>À <b>jeudi</b>.</div>") == "Bonjour Nina,\n\nÀ **jeudi**.")
        // And back: the same HTML as the agent's markdown makes.
        #expect(MailMarkdown.html(MailRichText.markdown(html)).contains("<b>Bonjour</b>"))
    }
}
