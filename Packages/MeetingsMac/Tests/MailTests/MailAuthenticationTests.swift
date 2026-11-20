import Foundation
import Persistence
import Testing
@testable import Mail

/// « Vérifié par Gmail » (audit of 19/11): only Gmail's own DMARC verdict counts, and only for the domain the From
/// shows. The headers have Gmail's shape; every name and address is invented.
@Suite struct MailAuthenticationTests {
    /// A message as Gmail gives it, with this From and this Authentication-Results: is it verified?
    func verified(_ results: String?, from: String?) throws -> Bool {
        var headers: [[String: String]] = []
        if let from { headers.append(["name": "From", "value": "Camille Martin <\(from)>"]) }
        if let results { headers.append(["name": "Authentication-Results", "value": results]) }
        let json: [String: Any] = ["id": "m1", "threadId": "t1", "payload": ["mimeType": "text/plain", "filename": "", "headers": headers]]
        let message = try GmailAPI.decode(GmailAPI.Message.self, from: try JSONSerialization.data(withJSONObject: json))
        return MailParser.parse(message, account: "moi@exemple.fr").row.authenticated
    }

    @Test func gmailsPassForTheFromsDomainIsVerified() throws {
        let results = "mx.google.com;\r\n       dkim=pass header.i=@studio.exemple header.s=s1 header.b=AbC;\r\n       spf=pass (google.com: domain of "
            + "camille@studio.exemple designates 192.0.2.1 as permitted sender) smtp.mailfrom=camille@studio.exemple;\r\n       "
            + "dmarc=pass (p=QUARANTINE sp=QUARANTINE dis=NONE) header.from=studio.exemple"
        #expect(try verified(results, from: "camille@studio.exemple"))
        #expect(try verified(results, from: "Camille@Studio.Exemple"))
    }

    /// The scenario of the audit: a stranger writes « dmarc=pass » where Gmail copies what he sent.
    @Test func aPassWrittenElsewhereInTheHeaderIsNot() throws {
        let envelope = "mx.google.com; spf=pass (google.com: domain of dmarc=pass@piege.exemple designates 192.0.2.9 as permitted sender) "
            + "smtp.mailfrom=dmarc=pass@piege.exemple; dmarc=fail (p=NONE sp=NONE dis=NONE) header.from=studio.exemple"
        #expect(try !verified(envelope, from: "camille@studio.exemple"))
        // An envelope sender in quotes, which carries a « ; ».
        let quoted = #"mx.google.com; spf=pass smtp.mailfrom="x;dmarc=pass header.from=studio.exemple"@piege.exemple; dmarc=fail header.from=studio.exemple"#
        #expect(try !verified(quoted, from: "camille@studio.exemple"))
        // In a comment.
        let comment = "mx.google.com; spf=neutral (x; dmarc=pass header.from=studio.exemple) smtp.mailfrom=x@piege.exemple; dmarc=none header.from=studio.exemple"
        #expect(try !verified(comment, from: "camille@studio.exemple"))
    }

    @Test func aPassForAnotherDomainOrFromAnotherServerIsNot() throws {
        #expect(try !verified("mx.google.com; dmarc=pass (p=NONE) header.from=piege.exemple", from: "camille@studio.exemple"))
        #expect(try !verified("mx.piege.exemple; dmarc=pass header.from=studio.exemple", from: "camille@studio.exemple"))
        #expect(try !verified("mx.google.com; dmarc=pass", from: "camille@studio.exemple"))
        #expect(try !verified(nil, from: "camille@studio.exemple"))
        #expect(try !verified("mx.google.com; dmarc=pass header.from=studio.exemple", from: nil))
    }
}

/// Lot 10 (20/11): a message without a subject is kept with the base's word for it, a format never reworded; the code
/// asks `hasNoSubject`, never compares the words.
@Suite struct MailNoSubjectTests {
    @Test func aMessageWithoutASubjectSaysItByItsState() throws {
        let json: [String: Any] = ["id": "m1", "threadId": "t1", "payload": ["mimeType": "text/plain", "filename": "",
                                                                          "headers": [["name": "Subject", "value": "  "]]]]
        let message = try GmailAPI.decode(GmailAPI.Message.self, from: try JSONSerialization.data(withJSONObject: json))
        let row = MailParser.parse(message, account: "moi@exemple.fr").row
        #expect(row.subject == "(sans objet)" && row.hasNoSubject)
        let named = MailMessageRow(account: "moi@exemple.fr", messageID: "m2", threadID: "t2", date: Date(timeIntervalSince1970: 0),
                                   sender: nil, subject: "Devis", snippet: "", labels: [])
        #expect(!named.hasNoSubject)
    }
}

