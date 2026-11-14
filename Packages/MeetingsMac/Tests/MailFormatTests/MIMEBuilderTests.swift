import Foundation
import Persistence
import Testing
@testable import MailFormat

/// 14/11, step « Écrire »: the message Gmail sends is exactly what Polhub builds.
@Suite struct MIMEBuilderTests {
    let date = Date(timeIntervalSince1970: 1_794_562_920)
    let me = MailAddress(name: "Moi", email: "moi@exemple.fr")
    let camille = MailAddress(name: "Camille Martin", email: "camille@exemple.fr")

    func boundaries() -> () -> String {
        final class Counter: @unchecked Sendable { var value = 0 }
        let counter = Counter()
        return { counter.value += 1; return "B\(counter.value)" }
    }

    func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    @Test func aSimpleMailIsExactlyWhatGmailNeeds() throws {
        let mail = OutgoingMail(from: me, to: [camille], subject: "Maquette", text: "Bonjour", html: "<div>Bonjour</div>", date: date)
        let raw = text(try MIMEBuilder.build(mail, boundary: boundaries()))
        let head = raw.components(separatedBy: "\r\n").prefix(7)
        #expect(head.first == "From: Moi <moi@exemple.fr>")
        #expect(head.contains("To: Camille Martin <camille@exemple.fr>"))
        #expect(head.contains("Subject: Maquette"))
        #expect(head.contains { $0.hasPrefix("Date: ") && $0.contains("2026") })
        #expect(raw.contains("MIME-Version: 1.0\r\nContent-Type: multipart/alternative; boundary=\"B1\"\r\n\r\n--B1\r\nContent-Type: text/plain; charset=\"UTF-8\""))
        #expect(raw.contains("\r\n\r\nBonjour\r\n--B1\r\nContent-Type: text/html"))
        #expect(raw.hasSuffix("--B1--\r\n"))
        // Never a bare LF, never a line beyond 998.
        #expect(!raw.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
        #expect(raw.components(separatedBy: "\r\n").allSatisfy { $0.utf8.count <= 998 })
    }

    @Test func accentsTravelEncoded() throws {
        let subject = "Réunion de lundi — l'accès à l'espace client, les éléments à prévoir et la suite"
        let mail = OutgoingMail(from: me, to: [MailAddress(name: "Élodie Ç.", email: "elodie@exemple.fr")], subject: subject,
                                text: "À bientôt, café ☕️", html: "<p>À bientôt</p>", date: date)
        let raw = text(try MIMEBuilder.build(mail, boundary: boundaries()))
        #expect(raw.contains("To: =?UTF-8?B?"))
        #expect(!raw.contains("Réunion") && !raw.contains("À bientôt"))
        // The subject comes back word for word, folded on several lines of at most 76 characters.
        let subjectLines = raw.components(separatedBy: "\r\n").drop { !$0.hasPrefix("Subject:") }.prefix { $0.hasPrefix("Subject:") || $0.hasPrefix(" ") }
        #expect(subjectLines.count > 1 && subjectLines.allSatisfy { $0.count <= 76 + 9 })
        let decoded = subjectLines.joined().replacingOccurrences(of: "Subject: ", with: "").components(separatedBy: " ")
            .map { word -> String in
                let base64 = word.replacingOccurrences(of: "=?UTF-8?B?", with: "").replacingOccurrences(of: "?=", with: "")
                return String(decoding: Data(base64Encoded: base64) ?? Data(), as: UTF8.self)
            }.joined()
        #expect(decoded == subject)
        #expect(raw.contains("=C3=80 bient=C3=B4t, caf=C3=A9"))
    }

    /// A subject, a name or a file name carrying a line break could add a header (a Bcc, say): they never do.
    @Test func aLineBreakNeverMakesAHeader() throws {
        let mail = OutgoingMail(from: me, to: [MailAddress(name: "Pirate\r\nBcc: espion@exemple.fr", email: "a@exemple.fr")],
                                subject: "Bonjour\r\nBcc: espion@exemple.fr", text: "x", html: "x",
                                files: [OutgoingFile(filename: "a\r\nBcc: espion@exemple.fr.pdf", mimeType: "application/pdf", data: Data([1]))], date: date)
        let raw = text(try MIMEBuilder.build(mail, boundary: boundaries()))
        #expect(!raw.components(separatedBy: "\r\n").contains { $0.hasPrefix("Bcc:") })
    }

    /// A display name with a comma, taken from a mail received, never adds a recipient.
    @Test func aCommaInANameStaysInTheName() throws {
        let mail = OutgoingMail(from: me, to: [MailAddress(name: "Durand, Jules <jules@pirate.exemple>", email: "jules@exemple.fr")],
                                subject: "x", text: "x", html: "x", date: date)
        let raw = text(try MIMEBuilder.build(mail, boundary: boundaries()))
        #expect(raw.contains(#"To: "Durand, Jules <jules@pirate.exemple>" <jules@exemple.fr>"#))
    }

    @Test func filesGoInAMixedMessage() throws {
        let data = Data((0..<200).map { UInt8($0) })
        let mail = OutgoingMail(from: me, to: [camille], cc: [MailAddress(email: "jules@exemple.fr")], bcc: [MailAddress(email: "moi2@exemple.fr")],
                                subject: "Devis", text: "Ci-joint", html: "Ci-joint",
                                files: [OutgoingFile(filename: "devis été.pdf", mimeType: "application/pdf", data: data)], date: date)
        let raw = text(try MIMEBuilder.build(mail, boundary: boundaries()))
        #expect(raw.contains("Cc: jules@exemple.fr\r\nBcc: moi2@exemple.fr"))
        #expect(raw.contains("Content-Type: multipart/mixed; boundary=\"B2\"\r\n\r\n--B2\r\nContent-Type: multipart/alternative; boundary=\"B1\""))
        #expect(raw.contains("Content-Disposition: attachment; filename*=UTF-8''devis%20%C3%A9t%C3%A9.pdf"))
        #expect(raw.contains("Content-Transfer-Encoding: base64"))
        let base64 = raw.components(separatedBy: "Content-Transfer-Encoding: base64\r\n\r\n")[1].components(separatedBy: "\r\n--B2--")[0]
        #expect(Data(base64Encoded: base64.replacingOccurrences(of: "\r\n", with: "")) == data)
        #expect(base64.components(separatedBy: "\r\n").allSatisfy { $0.count <= 76 })
    }

    @Test func aReplyStaysInItsThread() throws {
        let mail = OutgoingMail(from: me, to: [camille], subject: "Re: Maquette", text: "Merci", html: "Merci",
                                inReplyTo: "<b@exemple.fr>", references: "<a@exemple.fr> <b@exemple.fr>", date: date)
        let raw = text(try MIMEBuilder.build(mail, boundary: boundaries()))
        #expect(raw.contains("In-Reply-To: <b@exemple.fr>\r\nReferences: <a@exemple.fr> <b@exemple.fr>\r\n"))
    }

    @Test func whatGmailWouldRefuseIsRefusedFirst() {
        let base = OutgoingMail(from: me, to: [], subject: "x", text: "x", html: "x", date: date)
        #expect(throws: MIMEBuilder.Failure.noRecipient) { try MIMEBuilder.build(base) }
        var bad = base
        bad.to = [MailAddress(email: "camille@")]
        #expect(throws: MIMEBuilder.Failure.badAddress("camille@")) { try MIMEBuilder.build(bad) }
        var big = base
        big.to = [camille]
        big.files = [OutgoingFile(filename: "gros.bin", mimeType: "application/octet-stream", data: Data(count: 25_000_001))]
        #expect(throws: MIMEBuilder.Failure.tooLarge) { try MIMEBuilder.build(big) }
        #expect(MIMEBuilder.isValid("prenom.nom+tag@sous.exemple.fr") && !MIMEBuilder.isValid("a b@exemple.fr") && !MIMEBuilder.isValid("a@b"))
    }

    @Test func quotedPrintableKeepsLinesShortAndSpacesSafe() {
        let long = String(repeating: "é", count: 60) + "=fin "
        let encoded = MIMEBuilder.quotedPrintable(long + "\nligne deux")
        #expect(encoded.components(separatedBy: "\r\n").allSatisfy { $0.count <= 76 })
        #expect(encoded.contains("=3Dfin=20\r\nligne deux"))
        #expect(MIMEBuilder.base64URL(Data([0xfb, 0xff])) == "-_8")
    }
}

@Suite struct ReplyBuilderTests {
    let date = Date(timeIntervalSince1970: 1_794_562_920)
    let mine: Set<String> = ["moi@exemple.fr", "moi@perso.exemple"]
    let camille = MailAddress(name: "Camille Martin", email: "camille@exemple.fr")
    let jules = MailAddress(name: "Jules", email: "jules@exemple.fr")
    let me = MailAddress(name: "Moi", email: "moi@exemple.fr")

    var source: ReplySource {
        ReplySource(from: camille, to: [me, jules], cc: [MailAddress(email: "moi@perso.exemple"), MailAddress(email: "nina@exemple.fr")], date: date,
                    subject: "Maquette v2", messageID: "<b@exemple.fr>", references: "<a@exemple.fr>",
                    body: "<p>Voici la maquette.</p><p>Camille</p>", isHTML: true)
    }

    @Test func aReplyGoesToTheSenderAReplyToAllToEveryoneElse() {
        #expect(ReplyBuilder.recipients(.reply, source: source, mine: mine).to == [camille])
        let all = ReplyBuilder.recipients(.replyAll, source: source, mine: mine)
        #expect(all.to == [camille] && all.cc.map(\.email) == ["jules@exemple.fr", "nina@exemple.fr"])
        // The address the sender asked replies at wins.
        var asked = source
        asked.replyTo = [MailAddress(email: "equipe@exemple.fr")]
        #expect(ReplyBuilder.recipients(.reply, source: asked, mine: mine).to.map(\.email) == ["equipe@exemple.fr"])
        // Replying to Paul's own message writes again to its recipients.
        var mineSource = source
        mineSource.from = me
        mineSource.to = [camille, jules]
        mineSource.cc = []
        #expect(ReplyBuilder.recipients(.reply, source: mineSource, mine: mine).to == [camille, jules])
        #expect(ReplyBuilder.recipients(.forward, source: source, mine: mine).to.isEmpty)
    }

    @Test func theSubjectIsPrefixedOnce() {
        #expect(ReplyBuilder.subject(.reply, original: "Maquette") == "Re: Maquette")
        #expect(ReplyBuilder.subject(.replyAll, original: "RE: Maquette") == "RE: Maquette")
        #expect(ReplyBuilder.subject(.forward, original: "Maquette") == "Fwd: Maquette")
        #expect(ReplyBuilder.subject(.forward, original: "TR : Maquette") == "TR : Maquette")
    }

    @Test func theThreadAndTheQuoteAreGmails() throws {
        let threading = ReplyBuilder.threading(source)
        #expect(threading.inReplyTo == "<b@exemple.fr>" && threading.references == "<a@exemple.fr> <b@exemple.fr>")
        let quote = try #require(ReplyBuilder.quoteHTML(.reply, source: source))
        #expect(quote.hasPrefix("<div class=\"gmail_quote\"><div dir=\"ltr\" class=\"gmail_attr\">Le "))
        #expect(quote.contains("Camille Martin &lt;camille@exemple.fr&gt; a écrit :") && quote.contains("<p>Voici la maquette.</p>"))
        let text = try #require(ReplyBuilder.quoteText(.reply, source: source))
        #expect(text.hasSuffix("> Voici la maquette.\n> Camille"))
        let forward = try #require(ReplyBuilder.quoteText(.forward, source: source))
        #expect(forward.hasPrefix("---------- Message transféré ---------\nDe : Camille Martin <camille@exemple.fr>"))
        #expect(forward.contains("Objet : Maquette v2"))
    }

    @Test func paulsTextComesFirstThenHisSignatureThenTheQuote() {
        let html = ReplyBuilder.html(body: "Merci <3\nhttps://exemple.fr/maquette", signature: "<b>Paul</b>", quote: "<div class=\"gmail_quote\">Q</div>")
        #expect(html == "<div dir=\"ltr\">Merci &lt;3<br><a href=\"https://exemple.fr/maquette\">https://exemple.fr/maquette</a></div>"
            + "<br><div dir=\"ltr\" class=\"gmail_signature\"><b>Paul</b></div><br><div class=\"gmail_quote\">Q</div>")
        #expect(ReplyBuilder.text(body: "Merci", signature: "<b>Paul</b><br>Studio", quote: "> Q") == "Merci\n\n-- \nPaul\nStudio\n\n> Q")
    }

    @Test func htmlBecomesItsWords() {
        let html = "<html><head><style>p{color:red}</style></head><body><p>Bonjour&nbsp;Camille,</p><div>Voici&#39;l&eacute;t&#xE9;&amp;co</div><ul><li>un</li></ul><br><br><br>fin</body></html>"
        #expect(HTMLText.plain(html) == "Bonjour Camille,\nVoici'lété&co\n• un\n\nfin")
    }
}
