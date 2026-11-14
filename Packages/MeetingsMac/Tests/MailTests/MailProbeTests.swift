import Domain
import Foundation
import GoogleKit
import Testing
@testable import Mail

/// 14/11, step 0 of the mails: Gmail spoken to directly, and measures that only keep numbers.
@Suite struct MailProbeTests {
    static func base64URL(_ text: String, encoding: String.Encoding = .utf8) -> String {
        (text.data(using: encoding) ?? Data()).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    /// An invented mail: a correspondent, a subject, a body. None of them may reach a report.
    static let secretSubject = "Devis Alpha confidentiel"
    static let secretAddress = "camille@exemple.fr"
    static let secretBody = "Bonjour, voici le devis du projet Beta Studio."

    static func fullMessage(id: String) -> String {
        let html = #"<html><body><p>\#(secretBody)</p><img src="cid:logo"><img src="https://images.exemple.fr/banniere.webp"></body></html>"#
        return #"""
        {"id":"\#(id)","threadId":"t\#(id)","labelIds":["INBOX"],"payload":{"mimeType":"multipart/mixed","headers":[
          {"name":"From","value":"Camille <\#(secretAddress)>"},{"name":"Subject","value":"\#(secretSubject)"},
          {"name":"Authentication-Results","value":"mx.google.com; dkim=pass; dmarc=pass (p=NONE)"},
          {"name":"List-Unsubscribe","value":"<https://exemple.fr/stop>"},{"name":"List-Unsubscribe-Post","value":"List-Unsubscribe=One-Click"}],
          "parts":[{"mimeType":"multipart/alternative","parts":[
            {"mimeType":"text/plain","filename":"","headers":[{"name":"Content-Type","value":"text/plain; charset=\"UTF-8\""}],"body":{"size":10,"data":"\#(base64URL(secretBody))"}},
            {"mimeType":"text/html","filename":"","headers":[{"name":"Content-Type","value":"text/html; charset=ISO-8859-1"}],"body":{"size":90,"data":"\#(base64URL(html, encoding: .isoLatin1))"}}]},
            {"mimeType":"application/pdf","filename":"devis.pdf","body":{"size":245000,"attachmentId":"a1"}}]}}
        """#
    }

    /// Gmail, faked: answers by the path of the request.
    static func gmail(profileStatus: Int = 200) -> MailProbe.Send {
        { build in
            let request = build("jeton")
            let url = request.url!, path = url.path()
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
            if path.hasSuffix("/profile") {
                guard profileStatus == 200 else { throw GmailAPI.error(status: profileStatus, data: Data(#"{"error":{"status":"SERVICE_DISABLED"}}"#.utf8)) }
                return Data(#"{"emailAddress":"moi@exemple.fr","messagesTotal":4200,"threadsTotal":1900,"historyId":"777"}"#.utf8)
            }
            if path.hasSuffix("/labels/INBOX") { return Data(#"{"id":"INBOX","threadsTotal":61,"threadsUnread":12}"#.utf8) }
            if path.contains("/labels/CATEGORY_") { return Data(#"{"id":"x","messagesTotal":50}"#.utf8) }
            if path.hasSuffix("/threads") { return Data(#"{"threads":[{"id":"t1"},{"id":"t2"},{"id":"t3"}]}"#.utf8) }
            if path.hasSuffix("/messages") {
                if value("pageToken") == nil && value("q") == "newer_than:180d" {
                    return Data(#"{"messages":[{"id":"m1"},{"id":"m2"}],"nextPageToken":"suite"}"#.utf8)
                }
                return Data(#"{"messages":[{"id":"m3"}]}"#.utf8)
            }
            if path.hasSuffix("/history") {
                #expect(value("startHistoryId") == "777")
                return Data(#"{"historyId":"778"}"#.utf8)
            }
            if path.contains("/messages/") {
                let id = url.lastPathComponent
                if value("format") == "metadata" {
                    return Data(#"{"id":"\#(id)","payload":{"headers":[{"name":"Authentication-Results","value":"mx.google.com; dmarc=pass"}]}}"#.utf8)
                }
                return Data(fullMessage(id: id).utf8)
            }
            throw GoogleError.http(599)
        }
    }

    static func quickPacer() -> GmailPacer { GmailPacer(unitsPerMinute: 1_000_000) }

    @Test func aMailboxIsMeasuredInNumbers() async throws {
        let report = await MailProbe(send: Self.gmail(), pacer: Self.quickPacer()).run(account: "moi@exemple.fr")
        #expect(report.errors == [])
        #expect(report.messagesTotal == 4_200 && report.threadsTotal == 1_900)
        #expect(report.inboxThreads == 61 && report.inboxUnreadThreads == 12 && report.inboxThreadsOlderThanSixMonths == 3)
        // Two pages: two ids, then one.
        #expect(report.sixMonthsMessages == 3 && report.sixMonthsCounted)
        #expect(report.categories["CATEGORY_UPDATES"] == 50 && report.categories.count == 5)
        #expect(report.historyCursorAccepted)
        #expect(report.paced.reads == 2 && report.paced.quotaRefusals == 0 && report.paced.withAuthenticationHeader == 2)
        let sample = report.sample
        #expect(sample.count == 1 && sample.withHTML == 1 && sample.plainOnly == 0 && sample.undecodable == 0)
        #expect(sample.charsets == ["iso-8859-1": 1])
        #expect(sample.withInlineImages == 1 && sample.withRemoteImages == 1 && sample.withWebPOrAVIF == 1)
        #expect(sample.withAttachments == 1 && sample.largestAttachmentBytes == 245_000)
        #expect(sample.withAuthenticationHeader == 1 && sample.dmarcPass == 1)
        #expect(sample.withListUnsubscribe == 1 && sample.withOneClickUnsubscribe == 1)
    }

    /// The whole point of the probe: what it writes can be read by anyone without showing a mail.
    @Test func aReportNeverCarriesAMail() async throws {
        let report = await MailProbe(send: Self.gmail(), pacer: Self.quickPacer()).run(account: "moi@exemple.fr")
        let json = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        for written in [report.text, json] {
            #expect(!written.contains(Self.secretSubject) && !written.contains(Self.secretAddress))
            #expect(!written.contains("devis.pdf") && !written.contains("Beta Studio") && !written.contains("banniere"))
        }
        #expect(report.text.contains("Boîte moi@exemple.fr"))
    }

    /// The Gmail API is not enabled yet, or the account refuses: one clear code, nothing else is tried.
    @Test func aMailboxThatDoesNotAnswerSaysWhy() async throws {
        let report = await MailProbe(send: Self.gmail(profileStatus: 403), pacer: Self.quickPacer()).run(account: "moi@exemple.fr")
        #expect(report.errors == ["profil : refused"])
        #expect(report.sample.count == 0 && report.paced.reads == 0)
    }

    @Test func bytesThatDoNotFitTheirCharacterSetAreCounted() throws {
        let broken = #"{"id":"m","payload":{"mimeType":"text/html","filename":"","headers":[{"name":"Content-Type","value":"text/html; charset=utf-8"}],"body":{"size":2,"data":"_-A"}}}"#
        let message = try GmailAPI.decode(GmailAPI.Message.self, from: Data(broken.utf8))
        let sample = MailProbe.sample([message])
        #expect(sample.count == 1 && sample.undecodable == 1 && sample.withHTML == 1)
        #expect(MailProbe.text(Data("déjà".utf8), charset: "utf-8") == "déjà")
        #expect(MailProbe.text(Data([0xE9]), charset: "windows-1252") == "é")
        #expect(MailProbe.text(Data("x".utf8), charset: "inconnu") == nil)
    }

    @Test func gmailsRefusalsAreTold() {
        func error(_ status: Int, _ body: String = "") -> GoogleError { GmailAPI.error(status: status, data: Data(body.utf8)) }
        #expect(error(401) == .expired)
        #expect(error(429) == .rateLimited)
        // Google files a quota refusal under 403 too: it is passing, never a final refusal.
        #expect(error(403, #"{"error":{"errors":[{"reason":"userRateLimitExceeded"}]}}"#) == .rateLimited)
        #expect(error(403, #"{"error":{"errors":[{"reason":"rateLimitExceeded"}]}}"#) == .rateLimited)
        #expect(error(403, #"{"error":{"status":"PERMISSION_DENIED","details":[{"reason":"ACCESS_TOKEN_SCOPE_INSUFFICIENT"}]}}"#) == .missingScope(.gmailModify))
        #expect(error(403, #"{"error":{"errors":[{"reason":"accessNotConfigured"}]}}"#) == .refused("l'API Gmail n'est pas activée dans la console Google"))
        #expect(error(404) == .notFound)
        #expect(error(500) == .http(500))
    }

    @Test func requestsAskGmailForWhatTheyMean() throws {
        let list = GmailAPI.messagesRequest(accessToken: "jeton", query: "newer_than:180d", labelIDs: ["INBOX"], pageToken: "p", maxResults: 30)
        let items = URLComponents(url: list.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(list.url?.path() == "/gmail/v1/users/me/messages")
        #expect(items.contains(URLQueryItem(name: "q", value: "newer_than:180d")) && items.contains(URLQueryItem(name: "labelIds", value: "INBOX")))
        #expect(items.contains(URLQueryItem(name: "pageToken", value: "p")) && items.contains(URLQueryItem(name: "maxResults", value: "30")))
        #expect(list.value(forHTTPHeaderField: "Authorization") == "Bearer jeton")
        let metadata = GmailAPI.messageRequest(accessToken: "jeton", id: "m1", format: .metadata, headers: ["List-Unsubscribe"])
        #expect(metadata.url?.absoluteString == "https://gmail.googleapis.com/gmail/v1/users/me/messages/m1?format=metadata&metadataHeaders=List-Unsubscribe")
        // A gesture names its messages: a reply that came meanwhile is never carried along.
        let modify = GmailAPI.batchModifyRequest(accessToken: "jeton", ids: ["m1", "m2"], add: ["TRASH"], remove: ["INBOX"])
        #expect(modify.httpMethod == "POST" && modify.url?.path() == "/gmail/v1/users/me/messages/batchModify")
        #expect(String(decoding: modify.httpBody ?? Data(), as: UTF8.self) == #"{"addLabelIds":["TRASH"],"ids":["m1","m2"],"removeLabelIds":["INBOX"]}"#)
        #expect(GmailLink.thread("abc", account: "moi@exemple.fr").absoluteString == "https://mail.google.com/mail/?authuser=moi@exemple.fr#all/abc")
    }

    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var date = Date(timeIntervalSince1970: 1_794_562_920)
        private var naps: [TimeInterval] = []
        var now: Date { lock.withLock { date } }
        var slept: [TimeInterval] { lock.withLock { naps } }
        func sleep(_ seconds: TimeInterval) { lock.withLock { naps.append(seconds); date += seconds } }
    }

    /// 100 units a minute: the second call of 60 waits for the first to be a minute old.
    @Test func thePacerWaitsRatherThanOverspend() async {
        let clock = Clock()
        let pacer = GmailPacer(unitsPerMinute: 100, now: { clock.now }, sleep: { clock.sleep($0) })
        await pacer.take(60)
        #expect(clock.slept.isEmpty)
        await pacer.take(40)
        #expect(clock.slept.isEmpty)
        await pacer.take(60)
        #expect(clock.slept == [60])
        // A single call larger than the whole budget still goes, alone in its minute.
        await pacer.take(500)
        #expect(clock.slept == [60, 60])
    }

    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String] = []
        func add(_ value: String) { lock.withLock { values.append(value) } }
        var all: [String] { lock.withLock { values } }
    }

    /// The development build only reads real mailboxes: the essay stops before its first request.
    @Test func theDevelopmentBuildNeverWritesToAMailbox() async {
        let calls = Calls()
        let essay = await MailTrashEssay.run(send: { build in
            calls.add(build("jeton").url?.path() ?? "")
            return Data()
        }, flavor: .dev)
        #expect(calls.all.isEmpty)
        #expect(essay.error == "la version de développement n'écrit jamais dans une vraie boîte" && !essay.found)
    }

    @Test func theTrashEssayTrashesThenRestoresTheTestMailOnly() async {
        let calls = Calls()
        let essay = await MailTrashEssay.run(send: { build in
            let request = build("jeton")
            let path = request.url?.path() ?? ""
            calls.add("\(request.httpMethod ?? "GET") \(path)")
            if path.hasSuffix("/messages") { return Data(#"{"messages":[{"id":"essai1"}]}"#.utf8) }
            if path.hasSuffix("/batchModify") {
                #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains(#""ids":["essai1"]"#))
                return Data()
            }
            if path.hasSuffix("/untrash") { return Data(#"{"id":"essai1"}"#.utf8) }
            // Labels: in the trash after the first write, back in the inbox after the undo.
            let undone = calls.all.contains { $0.hasSuffix("/untrash") }
            return Data((undone ? #"{"id":"essai1","labelIds":["INBOX","UNREAD"]}"# : #"{"id":"essai1","labelIds":["TRASH"]}"#).utf8)
        }, flavor: .prod)
        #expect(essay == { var e = MailTrashEssay(); e.found = true; e.trashed = true; e.leftInbox = true; e.restored = true; return e }())
        #expect(calls.all.filter { $0.hasPrefix("POST") } == ["POST /gmail/v1/users/me/messages/batchModify", "POST /gmail/v1/users/me/messages/essai1/untrash"])
    }

    @Test func withoutATestMailTheEssaySaysWhatToDo() async {
        let essay = await MailTrashEssay.run(send: { _ in Data(#"{"resultSizeEstimate":0}"#.utf8) }, flavor: .prod)
        #expect(!essay.found && essay.text.contains("Polhub essai"))
    }
}
