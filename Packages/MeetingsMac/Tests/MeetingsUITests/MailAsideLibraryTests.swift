import Agenda
import Foundation
import GoogleKit
import Mail
import MailFormat
import Persistence
import HubDesign
import Testing
@testable import MeetingsUI

/// A Gmail of made-up mails for « Spam » and « Corbeille » (wave B): it lists a folder, gives a mail's headers,
/// then its body. Anything else is refused: no test here reaches Google.
final class AsideGmail: @unchecked Sendable {
    struct Mail {
        var thread: String
        var labels: [String]
        var from: String
        var subject: String
        var snippet: String
        var hours: Double
        var html: String
        var account = "moi@exemple.fr"
    }

    private let lock = NSLock()
    private let mails: [(id: String, mail: Mail)]
    private var log: [String] = []

    init(_ mails: [(id: String, mail: Mail)]) {
        self.mails = mails
    }

    var calls: [String] { lock.withLock { log } }

    /// Gmail as one mailbox sees it: its own mails only.
    func send(for account: String) -> MailProbe.Send {
        let mails = self.mails.filter { $0.mail.account == account.lowercased() }
        return { [self] build in
            let request = build("jeton")
            guard let url = request.url else { throw GoogleError.badAnswer }
            let path = url.path().replacingOccurrences(of: "/gmail/v1/users/me", with: "")
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
            lock.withLock { self.log.append("\(request.httpMethod ?? "GET") \(path)" + (value("format").map { " \($0)" } ?? "")) }
            guard request.httpMethod == "GET" else { throw GoogleError.http(599) }
            if path == "/messages" {
                let label = value("labelIds") ?? ""
                let aside = value("includeSpamTrash") == "true"
                let ids = mails.filter { $0.mail.labels.contains(label) && (aside || !$0.mail.labels.contains { ["SPAM", "TRASH"].contains($0) }) }
                    .sorted { $0.mail.hours < $1.mail.hours }.map(\.id)
                return Data(#"{"messages":[\#(ids.map { #"{"id":"\#($0)"}"# }.joined(separator: ","))]}"#.utf8)
            }
            guard path.hasPrefix("/messages/"), let found = mails.first(where: { $0.id == url.lastPathComponent }) else { throw GoogleError.notFound }
            let mail = found.mail
            let date = Int(Date().addingTimeInterval(-mail.hours * 3_600).timeIntervalSince1970 * 1_000)
            let labels = "[" + mail.labels.map { "\"\($0)\"" }.joined(separator: ",") + "]"
            var text = #"{"id":"\#(found.id)","threadId":"\#(mail.thread)","labelIds":\#(labels),"snippet":"\#(mail.snippet)","internalDate":"\#(date)","payload":{"#
            let headers = #"[{"name":"From","value":"\#(mail.from)"},{"name":"To","value":"\#(mail.account)"},{"name":"Subject","value":"\#(mail.subject)"}]"#
            if value("format") == "full" {
                let body = Data(mail.html.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "=", with: "")
                text += #""mimeType":"text/html","filename":"","headers":\#(headers),"body":{"size":\#(mail.html.utf8.count),"data":"\#(body)"}}}"#
            } else {
                text += #""headers":\#(headers)}}"#
            }
            return Data(text.utf8)
        }
    }
}

/// Wave B (15/11): the folders « Spam » and « Corbeille » show the copy at once, then Gmail's list; only the way back.
@MainActor
@Suite struct MailAsideLibraryTests {
    let account = "moi@exemple.fr"

    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<150 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
        #expect(condition())
    }

    func library(_ messages: [MailMessageRow], gmail: AsideGmail, images: MailImages = .connus) async throws -> (MailLibrary, MailStore, URL) {
        let database = try AppDatabase.inMemory()
        let calendar = CalendarStore(database)
        try calendar.addAccount(email: account, at: Date())
        try calendar.setGrantedScopes(email: account, scopes: "openid https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/gmail.modify")
        let store = MailStore(database)
        try store.apply(account: account, upserts: messages)
        let root = FileManager.default.temporaryDirectory.appending(path: "a-part-\(UUID().uuidString)", directoryHint: .isDirectory)
        let defaults = try #require(UserDefaults(suiteName: "a-part-\(UUID().uuidString)"))
        defaults.set(images.rawValue, forKey: Preferences.Key.mailImages)
        let mails = MailLibrary(agenda: AgendaLibrary(database: database), root: root, defaults: defaults, flavor: .dev, send: { gmail.send(for: $0) })
        try await waitUntil { mails.accounts.count == 1 && !mails.rules.mine.isEmpty }
        return (mails, store, root)
    }

    func mail(_ id: String, thread: String, subject: String, labels: [String], minutes: Double) -> MailMessageRow {
        MailMessageRow(account: account, messageID: id, threadID: thread, date: Date().addingTimeInterval(-minutes * 60),
                       sender: MailAddress(name: "Camille Martin", email: "camille@exemple-studio.fr"), subject: subject, snippet: "Extrait de \(subject)",
                       labels: labels, hasBody: false)
    }

    var gmail: AsideGmail {
        AsideGmail([
            ("g1", .init(thread: "corbeille-gmail", labels: ["TRASH"], from: "Jules Durand <jules@atelier.exemple>", subject: "Facture refaite",
                         snippet: "La facture corrigée", hours: 0.5, html: "<p>La facture corrigée</p>")),
            ("g2", .init(thread: "spam-gmail", labels: ["SPAM"], from: "Gagnant <gagnant@loterie.exemple>", subject: "Vous avez gagné",
                         snippet: "Cliquez vite", hours: 1, html: #"<p>Cliquez vite</p><img src="https://pirate.exemple/pixel.gif">"#)),
        ])
    }

    /// The copy's trash shows at once; Gmail's list joins it, the most recent first. The spam is apart, and neither
    /// shows in the inbox nor counts as unread.
    @Test func theTrashShowsTheCopyThenGmails() async throws {
        let gmail = self.gmail
        let (mails, _, root) = try await library([
            mail("m1", thread: "boite", subject: "Maquette v2", labels: ["INBOX", "UNREAD", "CATEGORY_PERSONAL"], minutes: 5),
            mail("c1", thread: "corbeille-copie", subject: "Ancien devis", labels: ["TRASH", "UNREAD"], minutes: 300),
        ], gmail: gmail)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(mails.unreadCount == 1)
        mails.folder = .trash
        #expect(mails.shown.map(\.threadID) == ["corbeille-copie"])
        try await waitUntil { mails.shown.count == 2 && !mails.readingAside }
        #expect(mails.shown.map(\.threadID) == ["corbeille-gmail", "corbeille-copie"])
        #expect(gmail.calls.contains("GET /messages") && gmail.calls.contains("GET /messages/g1 metadata") && !gmail.calls.contains { $0.hasSuffix(" full") })
        mails.folder = .spam
        try await waitUntil { mails.shown.map(\.threadID) == ["spam-gmail"] }
        mails.folder = .inbox
        #expect(mails.shown.map(\.threadID) == ["boite"] && mails.unreadCount == 1 && mails.unread(in: .notifications) == 0)
        #expect(mails.searchSummary == nil)
    }

    /// Only the way back: « Restaurer » in the trash, « Pas un spam » in the spam; Gmail's gestures elsewhere.
    @Test func eachFolderOffersItsGestures() throws {
        let thread = try #require(MailThreadRow.aggregate(account: account, threadID: "t", messages: [mail("m1", thread: "t", subject: "Maquette",
                                                                                                        labels: ["INBOX", "UNREAD"], minutes: 0)], mine: [account]))
        #expect(MailFolder.trash.gestures(for: thread) == [.untrash] && MailFolder.trash.selectionGestures == [.untrash])
        #expect(MailFolder.spam.gestures(for: thread) == [.notSpam] && MailFolder.spam.selectionGestures == [.notSpam])
        #expect(MailFolder.inbox.gestures(for: thread) == [.archive, .trash, .markRead])
        var archived = thread
        archived.inInbox = false
        archived.unread = false
        #expect(MailFolder.all.gestures(for: archived) == [.unarchive, .trash, .markUnread])
        #expect(MailFolder.inbox.selectionGestures == [.archive, .trash, .markRead, .markUnread])
        #expect(MailGestureKind.untrash.title() == "Restaurer" && MailGestureKind.notSpam.title() == "Pas un spam")
        #expect(MailGestureKind.untrash.undoableAlone && MailGestureKind.notSpam.undoableAlone && !MailGestureKind.markRead.undoableAlone)
        // In the sidebar after « Abonnements », then « Tous les messages » last (Paul, 15/11).
        #expect(MailFolder.allCases.suffix(4) == [.subscriptions, .spam, .trash, .all])
        #expect(MailFolder.spam.title == "Spam" && MailFolder.trash.title == "Corbeille" && MailFolder.spam.icon == "xmark.bin" && MailFolder.trash.icon == "trash")
        #expect(MailFolder.allCases.filter { $0.aside != nil } == [.spam, .trash])
    }

    /// A search typed in the trash filters the trash only; Enter never asks Gmail from there.
    @Test func aSearchInTheTrashStaysInTheTrash() async throws {
        let gmail = AsideGmail([])
        let (mails, _, root) = try await library([
            mail("m1", thread: "boite", subject: "Facture de novembre", labels: ["INBOX"], minutes: 5),
            mail("c1", thread: "corbeille", subject: "Facture refaite", labels: ["TRASH"], minutes: 10),
            mail("c2", thread: "corbeille-2", subject: "Planning", labels: ["TRASH"], minutes: 20),
            mail("s1", thread: "spam", subject: "Facture impayée", labels: ["SPAM"], minutes: 30),
        ], gmail: gmail)
        defer { try? FileManager.default.removeItem(at: root) }
        mails.folder = .trash
        try await waitUntil { !mails.readingAside }
        mails.query = "facture"
        #expect(mails.found?.map(\.threadID) == ["corbeille"] && mails.searchSummary == "1 fil dans la corbeille")
        mails.query = "from:camille planning"
        #expect(mails.found?.map(\.threadID) == ["corbeille-2"])
        let asked = gmail.calls.count
        await mails.search("facture")
        #expect(gmail.calls.count == asked && !mails.searching)
        mails.query = "rien"
        #expect(mails.found == [] && mails.searchSummary == "Aucun fil dans la corbeille")
        mails.query = ""
        #expect(mails.found == nil && mails.searchSummary == nil && mails.shown.count == 2)
        // In the inbox, the same words never reach the trash nor the spam.
        mails.folder = .inbox
        mails.query = "facture"
        try await waitUntil { mails.found != nil }
        #expect(mails.found?.map(\.threadID) == ["boite"])
    }

    /// A spam opens with its body fetched from Gmail and kept nowhere, as HTML; its images never load, whatever
    /// the setting.
    @Test func aSpamOpensFromGmailWithoutItsImages() async throws {
        let gmail = self.gmail
        // « Tout afficher » in Réglages: never for a spam.
        let (mails, store, root) = try await library([], gmail: gmail, images: .afficher)
        defer { try? FileManager.default.removeItem(at: root) }
        mails.folder = .spam
        try await waitUntil { mails.shown.count == 1 }
        let thread = try #require(mails.shown.first)
        let model = MailThreadModel(key: thread.id, library: mails)
        #expect(model.aside == .spam)
        try await waitUntil { model.bodies.count == 1 }
        let message = try #require(model.messages.first)
        #expect(model.html[message.id] == true && model.bodies[message.id]?.contains("Cliquez vite") == true)
        #expect(try !message.hasBody && store.message(message.id)?.hasBody == false)
        #expect(gmail.calls.filter { $0 == "GET /messages/g2 full" }.count == 1)
        #expect(!FileManager.default.fileExists(atPath: MailFiles(root: root).body(of: message).path(percentEncoded: false)))
        #expect(!mails.showsImages(of: message, in: thread))
        #expect(await model.inline("logo", of: message) == nil)
        // A thread that is not put aside opens as before.
        let inbox = MailThreadModel(key: MailThreadRow.key(account: account, threadID: "nulle-part"), library: mails)
        #expect(inbox.aside == nil)
    }
}
