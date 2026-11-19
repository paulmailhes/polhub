import AppKit
import Domain
import Foundation
import Mail
import Network
import Persistence
import PolhubDesign
import SwiftUI
import Testing
import WebKit
@testable import MeetingsUI
import ProjectsUI
import MailFormat
import Notifications

/// A local server that answers any request with a tiny image and remembers the paths asked.
final class CountingServer: @unchecked Sendable {
    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [String] = []
        func add(_ path: String) { lock.withLock { asked.append(path) } }
        var all: [String] { lock.withLock { asked } }
    }

    private let log = Log()
    private let listener: NWListener
    let port: UInt16

    var paths: [String] { log.all }

    init() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        final class Box: @unchecked Sendable { var resumed = false }
        let box = Box()
        port = try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                guard !box.resumed else { return }
                switch state {
                case .ready: box.resumed = true; continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error): box.resumed = true; continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { _ in }
            listener.start(queue: .global())
        }
        listener.newConnectionHandler = { [log] connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                let line = String(decoding: data ?? Data(), as: UTF8.self).components(separatedBy: "\r\n").first ?? ""
                let path = line.split(separator: " ").dropFirst().first.map(String.init) ?? "?"
                log.add(path)
                let gif = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")!
                var response = Data("HTTP/1.1 200 OK\r\nContent-Type: image/gif\r\nContent-Length: \(gif.count)\r\nConnection: close\r\n\r\n".utf8)
                response.append(gif)
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }

    func stop() { listener.cancel() }
}

/// 14/11, step « Lire »: a mail shows as its sender wrote it, and loads nothing Paul did not allow.
@MainActor @Suite struct MailBodyTests {
    final class Heights: @unchecked Sendable {
        private let lock = NSLock()
        private var value: CGFloat = 0
        func set(_ height: CGFloat) { lock.withLock { value = height } }
        var last: CGFloat { lock.withLock { value } }
    }

    struct Host: View {
        let document: String
        let images: Bool
        let heights: Heights
        @State private var height: CGFloat = 10

        var body: some View {
            MailBodyView(document: document, images: images, inline: { _ in nil }, onLink: { _ in }, height: $height)
                .frame(width: 600, height: max(height, 10))
                .onChange(of: height) { _, new in heights.set(new) }
        }
    }

    /// Shows the page in a window that never comes on screen, and waits for it to settle: until the app's own script
    /// measured it (10 s at most, under load), then a moment for what it might have tried to load. A fixed wait failed
    /// once while ten suites of captures ran at the same time (19/11).
    func render(_ body: String, images: Bool, heights: Heights = Heights()) async throws {
        let document = MailHTML.document(body: body, isHTML: true, images: images, collapseQuote: false)
        let window = NSWindow(contentViewController: NSHostingController(rootView: Host(document: document, images: images, heights: heights)))
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 600, height: 400))
        window.layoutIfNeeded()
        let deadline = ContinuousClock.now + .seconds(10)
        while heights.last <= 10, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        try await Task.sleep(for: .milliseconds(800))
        window.close()
    }

    /// Scripts, frames, forms, style sheets, a refresh, fonts, a video: a hostile mail gets nothing out. With the
    /// images allowed, only its images load.
    @Test func aHostileMailLoadsNothingButItsImagesWhenAllowed() async throws {
        let server = try await CountingServer()
        defer { server.stop() }
        let base = "http://127.0.0.1:\(server.port)"
        let hostile = """
        <html><head><script src="\(base)/script.js"></script><link rel="stylesheet" href="\(base)/style.css">
        <meta http-equiv="refresh" content="0;url=\(base)/refresh"><link rel="dns-prefetch" href="\(base)/prefetch">
        <style>@font-face{font-family:x;src:url(\(base)/police.woff)} @import url(\(base)/import.css); p{font-family:x}</style></head>
        <body background="\(base)/fond.gif" onload="fetch('\(base)/onload')"><p>Bonjour</p><img src="\(base)/pixel.gif" width="1" height="1">
        <iframe src="\(base)/cadre.html"></iframe><form action="\(base)/formulaire" method="post"><input name="a"><input type="submit"></form>
        <div style="background:url(\(base)/css-fond.gif)">x</div><video src="\(base)/video.mp4" autoplay></video>
        <object data="\(base)/objet"></object><embed src="\(base)/embed"><script>new Image().src='\(base)/js-image'</script>
        <img src="\(base)/track/open?u=42" width="1" height="1"></body></html>
        """
        let heights = Heights()
        try await render(hostile, images: false, heights: heights)
        #expect(server.paths == [])
        // The app's own script ran all the same: it measured the page.
        #expect(heights.last > 10)
        // The known spy pixels (simplify-trackers) stay blocked, images allowed or not; the list compiles.
        #expect(await MailContentRules.list(images: true) != nil && MailTrackers.filters.count > 250)
        try await render(hostile, images: true)
        // Images allowed, the local network still gets nothing (audit of 19/11): this server is the Mac itself.
        #expect(server.paths == [])
    }

    /// Remote images are allowed by their own rule; the local network never (audit of 19/11): the Mac itself, the
    /// NAS, the router, a name without a dot, a number written whole. WebKit reads each rule as a pattern without « | ».
    @Test func remoteImagesAreAllowedAndTheLocalNetworkNever() throws {
        let rules = try #require(try JSONSerialization.jsonObject(with: Data(MailHTML.contentRules(images: true).utf8)) as? [[String: Any]])
        let filters = rules.map { rule in
            (((rule["trigger"] as? [String: Any])?["url-filter"] as? String) ?? "", ((rule["action"] as? [String: Any])?["type"] as? String) ?? "")
        }
        let allowed = try #require(filters.firstIndex { $0.0 == "^https?://" && $0.1 == "ignore-previous-rules" })
        let blocks = filters[(allowed + 1)...].filter { $0.1 == "block" }.compactMap { try? NSRegularExpression(pattern: $0.0, options: .caseInsensitive) }
        func blocked(_ url: String) -> Bool { blocks.contains { $0.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil } }
        for local in ["http://127.0.0.1:8080/a.png", "http://localhost/a.png", "http://LOCALHOST:3000/a.png", "http://192.168.1.10/a.png",
                      "http://10.0.0.2/a.png", "http://172.16.4.1/a.png", "http://172.31.0.1/a.png", "http://169.254.1.1/a.png",
                      "http://100.101.102.103/a.png", "http://nas/a.png", "http://3232235777/a.png", "http://nas.local/a.png",
                      "http://box.lan/a.png", "http://[::1]/a.png", "http://0.0.0.0/a.png", "http://moi@192.168.1.1/a.png",
                      "https://nas.exemple.ts.net/a.png", "http://routeur.home.arpa/a.png"] {
            #expect(blocked(local), "\(local)")
        }
        for remote in ["https://images.exemple.fr/a.png", "http://172.40.1.1/a.png", "https://cdn.exemple.com:443/a.png", "https://100.exemple.fr/a.png"] {
            #expect(!blocked(remote), "\(remote)")
        }
    }

    /// 14/11, Paul in dark mode: a light newsletter takes the app's background, its texts go light, its dark
    /// header stays, its light borders fade.
    @Test func aLightNewsletterGoesDark() async throws {
        let letter = """
        <table id="lettre" width="600" style="border:1px solid #eee"><tr><td id="tete" style="background:#1f2a44;color:#fff">La Lettre</td></tr>
        <tr><td id="corps" bgcolor="#ffffff" style="color:#333"><p id="texte">Bonjour</p><a id="lien" href="https://exemple.fr">lien</a>
        <div id="encart" style="background:#e8f0fe;color:#1a0dab">Encart</div>
        <a id="bouton" href="https://exemple.fr" style="display:block;background:#d4f04a;color:#000">Prendre rendez-vous</a></td></tr></table>
        """
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = false
        configuration.defaultWebpagePreferences = preferences
        configuration.userContentController.addUserScript(WKUserScript(source: MailHTML.readerScript, injectionTime: .atDocumentEnd,
                                                                       forMainFrameOnly: true, in: .defaultClient))
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 700, height: 400), configuration: configuration)
        view.appearance = NSAppearance(named: .darkAqua)
        view.load(Data(MailHTML.document(body: letter, isHTML: true, images: false, collapseQuote: false, dark: true).utf8),
                  mimeType: "text/html", characterEncodingName: "UTF-8", baseURL: URL(string: "about:blank")!)
        try await waitForPage(view, element: "bouton")
        func style(_ id: String, _ property: String) async throws -> String {
            try await view.callAsyncJavaScript("return getComputedStyle(document.getElementById(id))[property]", arguments: ["id": id, "property": property],
                                               in: nil, contentWorld: .defaultClient) as? String ?? "?"
        }
        let corps = try await style("corps", "backgroundColor"), texte = try await style("texte", "color")
        let tete = try await style("tete", "backgroundColor"), encart = try await style("encart", "backgroundColor")
        let lien = try await style("lien", "color"), bord = try await style("lettre", "borderTopColor")
        print("MESURE sombre : corps \(corps) · texte \(texte) · tête \(tete) · encart \(encart) · lien \(lien) · bord \(bord)")
        #expect(corps == "rgba(0, 0, 0, 0)")
        #expect(tete == "rgb(31, 42, 68)")
        #expect(bord != "rgb(238, 238, 238)")
        func brightness(_ text: String) -> Double {
            let numbers = text.split(whereSeparator: { !"0123456789.".contains($0) }).compactMap { Double($0) }
            return numbers.prefix(3).reduce(0, +) / 3
        }
        #expect(brightness(texte) > 170 && brightness(lien) > 140)
        #expect(brightness(encart) < 90)
        #expect(try await style("lettre", "visibility") == "visible")
        // A brand's vivid button keeps its color, and its dark text stays readable on it.
        #expect(try await style("bouton", "backgroundColor") == "rgb(212, 240, 74)")
        #expect(try await style("bouton", "color") == "rgb(0, 0, 0)")
    }

    /// A measure for macOS's Lockdown Mode on the mail view: which image formats still show. Read its output.
    @Test func whatLockdownModeDoesToImages() async throws {
        let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
        let webp = "UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEADsD+JaQAA3AAAAAA"
        let gif = "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"
        let html = #"<img id="png" src="data:image/png;base64,\#(png)"><img id="webp" src="data:image/webp;base64,\#(webp)"><img id="gif" src="data:image/gif;base64,\#(gif)">"#
        for lockdown in [false, true] {
            let configuration = WKWebViewConfiguration()
            let preferences = WKWebpagePreferences()
            preferences.allowsContentJavaScript = false
            preferences.isLockdownModeEnabled = lockdown
            configuration.defaultWebpagePreferences = preferences
            let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 300, height: 200), configuration: configuration)
            view.loadHTMLString(MailHTML.document(body: html, isHTML: true, images: false, collapseQuote: false), baseURL: nil)
            try await waitForPage(view, element: "gif")
            let widths = try await view.callAsyncJavaScript(
                "return ['png','webp','gif'].map(function (id) { return id + '=' + document.getElementById(id).naturalWidth; }).join(' ')",
                arguments: [:], in: nil, contentWorld: .defaultClient) as? String ?? "?"
            print("MESURE mode Isolement \(lockdown ? "actif" : "inactif") : \(widths)")
            #expect(widths.contains("png=1") && widths.contains("gif=1"))
        }
    }
}

/// Waits until the page is loaded, its images too, up to 10 s: a fixed pause of 1.5 s was not enough while the Mac
/// was busy with a call (16/11), and the page's elements were not there yet.
@MainActor private func waitForPage(_ view: WKWebView, element id: String) async throws {
    for _ in 0..<100 {
        let ready = try? await view.callAsyncJavaScript("return document.readyState === 'complete' && document.getElementById(id) !== null",
                                                        arguments: ["id": id], in: nil, contentWorld: .defaultClient) as? Bool
        if ready == true { return }
        try await Task.sleep(for: .milliseconds(100))
    }
}

/// The mail screens with made-up mails (14/11): `POLHUB_LIVE=1 POLHUB_SNAPSHOTS=<dossier> swift test --filter MailScreenTests`.
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"] != nil))
struct MailScreenTests {
    @Test func theMailScreens() async throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"]), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appending(path: "mails \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase.inMemory()
        let calendar = CalendarStore(database)
        let both = "openid https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/gmail.modify"
        for (index, email) in ["moi@exemple.fr", "perso@gmail.com", "paul@atelier-nord.fr"].enumerated() {
            try calendar.addAccount(email: email, at: Date().addingTimeInterval(Double(index)))
            try calendar.setGrantedScopes(email: email, scopes: both)
        }
        let store = MailStore(database), files = MailFiles(root: root)
        func mail(_ id: String, _ account: String, thread: String, from: MailAddress, subject: String, snippet: String, hours: Double,
                  labels: [String], html: String, files attached: [MailAttachment] = [], list: String? = nil) throws -> MailMessageRow {
            let row = MailMessageRow(account: account, messageID: id, threadID: thread, date: Date().addingTimeInterval(-hours * 3_600), sender: from,
                                     to: [MailAddress(email: account)], subject: subject, snippet: snippet, labels: labels, authenticated: true,
                                     listUnsubscribe: list, listUnsubscribePost: list == nil ? nil : "List-Unsubscribe=One-Click",
                                     hasBody: true, bodyIsHTML: true, attachments: attached)
            let url = files.body(of: row)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(html.utf8).write(to: url)
            return row
        }
        let camille = MailAddress(name: "Camille Martin", email: "camille.martin@exemple-studio.fr")
        let jules = MailAddress(name: "Jules Durand", email: "jules@atelier-nord.fr")
        let pdf = MailAttachment(partID: "2", filename: "maquette-v2.pdf", mimeType: "application/pdf", size: 1_240_000, attachmentID: "a", contentID: nil, inline: false)
        let letter = """
        <table width="600" align="center" style="font-family:Georgia,serif;border:1px solid #eee"><tr><td style="background:#1f2a44;color:#fff;padding:24px;font-size:22px">La Lettre du design</td></tr>
        <tr><td style="padding:24px"><img src="https://images.exemple.fr/une.jpg" width="552" height="120" alt=""><h2>Cinq tendances pour le printemps</h2>
        <p>Des grilles plus libres, des couleurs franches, et le retour des empattements.</p>
        <p><a href="https://pirate.exemple/suivi">www.lettre-du-design.exemple</a></p></td></tr></table>
        """
        try store.apply(account: "moi@exemple.fr", upserts: [
            try mail("a1", "moi@exemple.fr", thread: "a", from: camille, subject: "Maquette v2 du site", snippet: "Bonjour, voici la deuxième version de la maquette.",
                     hours: 30, labels: ["CATEGORY_PERSONAL"], html: "<p>Bonjour,</p><p>Voici la <b>deuxième version</b> de la maquette. Le pied de page a changé.</p><p>Camille</p>", files: [pdf]),
            try mail("a2", "moi@exemple.fr", thread: "a", from: MailAddress(name: "Moi", email: "moi@exemple.fr"), subject: "Re: Maquette v2 du site",
                     snippet: "Merci, je regarde ça demain matin.", hours: 26, labels: ["SENT"], html: "<p>Merci, je regarde ça demain matin.</p>"),
            try mail("a3", "moi@exemple.fr", thread: "a", from: camille, subject: "Re: Maquette v2 du site", snippet: "Parfait. J'ai aussi corrigé la page contact.",
                     hours: 1, labels: ["INBOX", "UNREAD", "CATEGORY_PERSONAL"],
                     html: #"<div>Parfait. J'ai aussi corrigé la page contact, dis-moi si le formulaire te convient.</div><div class="gmail_quote"><blockquote>Merci, je regarde ça demain matin.</blockquote></div>"#),
            try mail("b1", "moi@exemple.fr", thread: "b", from: MailAddress(name: "La Lettre du design", email: "lettre@lettre-du-design.exemple"),
                     subject: "Cinq tendances pour le printemps", snippet: "Des grilles plus libres, des couleurs franches…", hours: 5,
                     labels: ["INBOX", "UNREAD", "CATEGORY_PROMOTIONS"], html: letter, list: "<https://lettre-du-design.exemple/depart>"),
            try mail("b2", "moi@exemple.fr", thread: "b2", from: MailAddress(name: "La Lettre du design", email: "lettre@lettre-du-design.exemple"),
                     subject: "Le numéro d'hiver", snippet: "Rétrospective de l'année…", hours: 24 * 9,
                     labels: ["INBOX", "CATEGORY_PROMOTIONS"], html: letter, list: "<https://lettre-du-design.exemple/depart>"),
        ])
        try store.apply(account: "perso@gmail.com", upserts: [
            try mail("c1", "perso@gmail.com", thread: "c", from: MailAddress(name: "Paiements Exemple", email: "recus@paiements.exemple"),
                     subject: "Votre reçu n° 1042", snippet: "Merci pour votre paiement de 24,00 €.", hours: 3, labels: ["INBOX", "CATEGORY_UPDATES"],
                     html: "<p>Merci pour votre paiement de <b>24,00 €</b>.</p>", list: "<mailto:depart@paiements.exemple?subject=desinscription>"),
            try mail("d1", "perso@gmail.com", thread: "d", from: MailAddress(name: "Nina Roche", email: "nina.roche@exemple.fr"),
                     subject: "Photos du week-end", snippet: "Je t'envoie les photos de dimanche, elles sont superbes.", hours: 20,
                     labels: ["INBOX", "CATEGORY_PERSONAL"], html: "<p>Je t'envoie les photos de dimanche, elles sont superbes.</p>"),
        ])
        try store.apply(account: "paul@atelier-nord.fr", upserts: [
            try mail("e1", "paul@atelier-nord.fr", thread: "e", from: jules, subject: "Planning de mars", snippet: "Voici le planning mis à jour pour mars.",
                     hours: 50, labels: ["INBOX", "CATEGORY_PERSONAL"], html: "<p>Voici le planning mis à jour pour mars.</p>"),
            try mail("f1", "paul@atelier-nord.fr", thread: "f", from: jules, subject: "Devis signé", snippet: "Le client a signé, on peut lancer.",
                     hours: 8, labels: ["INBOX", "UNREAD", "CATEGORY_PERSONAL"], html: "<p>Le client a signé, on peut lancer.</p>"),
        ])
        // Step « Ranger »: Camille is a contact of the project « Site vitrine »; her threads go there.
        var site = try ProjectStore(database).addProject(name: "Site vitrine", status: .priorite1, at: Date())
        site.color = "blue"
        try ProjectStore(database).save(site, at: Date())
        let contactCamille = try ContactStore(database).upsert(email: camille.email, name: "Camille Martin", company: nil, at: Date())
        try ContactStore(database).link(contactID: contactCamille.id, projectID: site.id, origin: .paul, at: Date())
        // Wave B: one trashed thread in the copy; Gmail's trash and spam, made up, read live when their folder opens.
        try store.apply(account: "moi@exemple.fr", upserts: [
            try mail("t1", "moi@exemple.fr", thread: "corbeille-copie", from: camille, subject: "Ancien devis du site", snippet: "Voici le devis de septembre, remplacé depuis.",
                     hours: 72, labels: ["TRASH", "CATEGORY_PERSONAL"], html: "<p>Voici le devis de septembre, remplacé depuis par la version d'octobre.</p><p>Camille</p>"),
        ])
        let gmail = AsideGmail([
            ("g1", .init(thread: "corbeille-gmail", labels: ["TRASH"], from: "Jules Durand <jules@atelier-nord.fr>", subject: "Planning de février",
                         snippet: "L'ancien planning, avant le report du chantier.", hours: 30, html: "<p>L'ancien planning, avant le report du chantier.</p>",
                         account: "paul@atelier-nord.fr")),
            ("g2", .init(thread: "corbeille-lettre", labels: ["TRASH", "CATEGORY_PROMOTIONS"], from: "La Lettre du design <lettre@lettre-du-design.exemple>",
                         subject: "Le numéro d'automne", snippet: "Rétrospective de la saison…", hours: 24 * 12, html: letter)),
            ("s1", .init(thread: "spam-colis", labels: ["SPAM", "UNREAD"], from: "Service Livraison <suivi@colis-express.exemple>",
                         subject: "Votre colis est bloqué", snippet: "Des frais de 1,99 € sont à régler avant la livraison.", hours: 2,
                         html: """
                         <table width="600" style="font-family:Arial"><tr><td style="background:#d4001a;color:#fff;padding:20px;font-size:20px">Colis Express</td></tr>
                         <tr><td style="padding:20px"><img src="https://pixel.colis-express.exemple/ouvert.gif" width="1" height="1">
                         <p>Votre colis n° 4471 est bloqué : des frais de <b>1,99 €</b> sont à régler avant la livraison.</p>
                         <p><a href="https://pirate.exemple/paiement">https://www.suivi-colis.exemple/4471</a></p></td></tr></table>
                         """)),
            ("s2", .init(thread: "spam-loterie", labels: ["SPAM"], from: "Grand Tirage <gagnant@loterie.exemple>", subject: "Vous avez gagné un téléphone",
                         snippet: "Félicitations ! Réclamez votre lot avant ce soir.", hours: 20, html: "<p>Félicitations ! Réclamez votre lot avant ce soir.</p>",
                         account: "perso@gmail.com")),
        ])
        let agenda = AgendaLibrary(database: database)
        // Wave B: the programmed sends in memory, never the Keychain.
        let vault = MemoryScheduleVault()
        let mails = MailLibrary(agenda: agenda, root: root, defaults: UserDefaults(suiteName: "mails-\(UUID().uuidString)")!, send: { gmail.send(for: $0) },
                                vault: vault)
        let projects = ProjectLibrary(store: ProjectStore(database), meetings: MeetingStore(database))
        let library = MeetingLibrary(store: MeetingStore(database))
        let router = WindowRouter()
        router.section = .mails
        try await Task.sleep(for: .milliseconds(500))
        var shownMails = mails
        // The bell beside Réglages, with two notifications not seen yet (15/11).
        let inbox = NotificationInbox(file: nil)
        for (id, title) in [("n1", "Compte rendu prêt"), ("n2", "Camille Martin")] {
            inbox.record(PlannedNotice(id: id, fireDate: Date(), title: title, body: "Exemple", eventID: nil, meetCode: nil, account: nil, kind: .newEvent),
                         at: Date())
        }
        let hub = NotificationHub(agenda: agenda, client: SilentNotifications(), inbox: inbox)
        func capture(_ name: String, dark: Bool = false, width: CGFloat = 1_180, wait: Duration = .milliseconds(1_500)) async throws {
            try await LiveWindow.capture(MainWindowView(library: library, projects: projects, agenda: agenda, mails: shownMails, notifications: hub,
                                                        router: router, paths: AppPaths(root: root, logs: root)) { EmptyView() },
                                         to: output.appending(path: "\(name).png"), size: NSSize(width: width, height: 780), dark: dark, wait: wait)
        }
        UserDefaults.standard.set(true, forKey: Preferences.Key.floatingPages)
        try await capture("mails-personnes")
        try await capture("mails-personnes-sombre", dark: true)
        // Lot 6 (19/11): a line under the pointer — its gestures in the end column, in the date's place — among lines at rest.
        let mineAccounts = Set(agenda.accounts.map(\.email))
        let inboxThreads = Array(mails.shown.prefix(4))
        for dark in [false, true] {
            try await LiveWindow.capture(VStack(spacing: 0) {
                ForEach(Array(inboxThreads.enumerated()), id: \.element.id) { index, thread in
                    MailRow(thread: thread, mails: mails, mine: mineAccounts, density: .defaut, stripes: true, hovering: index == 1) {}
                }
                Spacer(minLength: 0)
            }
            .background(MailSurface.unread), to: output.appending(path: "mails-survol\(dark ? "-sombre" : "").png"),
            size: NSSize(width: 956, height: 300), dark: dark)
        }
        // 15/11: two tabs; the newsletters are among the notifications.
        mails.tab = .notifications
        try await capture("mails-notifications")
        mails.tab = .personnes
        mails.selecting = true
        mails.selected = [MailThreadRow.key(account: "moi@exemple.fr", threadID: "a"), MailThreadRow.key(account: "paul@atelier-nord.fr", threadID: "f")]
        try await capture("mails-selection")
        mails.endSelection()
        router.mailSelection = MailThreadRow.key(account: "moi@exemple.fr", threadID: "a")
        try await capture("mails-fil-flottant")
        try await capture("mails-fil-flottant-sombre", dark: true)
        // 19/11: a narrow window: « 1 sur 6 », the arrows and the gestures go above the subject, never squeezed.
        try await capture("mails-fil-etroit", width: MainWindowView<EmptyView>.minimumWidth)
        UserDefaults.standard.set(false, forKey: Preferences.Key.floatingPages)
        try await capture("mails-fil-page-etroit", width: MainWindowView<EmptyView>.minimumWidth)
        UserDefaults.standard.set(true, forKey: Preferences.Key.floatingPages)
        mails.tab = .notifications
        router.mailSelection = MailThreadRow.key(account: "moi@exemple.fr", threadID: "b")
        try await capture("mails-lettre-sombre", dark: true)
        // 14/11, step « Écrire »: a reply below its thread, a new mail over the list, the drafts.
        mails.tab = .personnes
        try store.saveDraft(MailDraftRow(account: "moi@exemple.fr", mode: .reply, threadKey: MailThreadRow.key(account: "moi@exemple.fr", threadID: "a"),
                                         replyToKey: "moi@exemple.fr|a3", to: [camille], subject: "Re: Maquette v2 du site",
                                         body: "Merci Camille, c'est parfait.\nJe valide la page contact.", quoteText: "> Parfait. J'ai aussi corrigé la page contact.",
                                         createdAt: Date()))
        try await Task.sleep(for: .milliseconds(300))
        router.mailSelection = MailThreadRow.key(account: "moi@exemple.fr", threadID: "a")
        try await capture("mails-reponse")
        // Review of 17/11: a message stays above the draft's bar, never over it.
        mails.message = "Mail envoyé : « Re: Maquette v2 du site »."
        try await capture("mails-reponse-message")
        mails.message = nil
        router.mailSelection = nil
        mails.newMail()
        try await capture("mails-nouveau")
        mails.closeComposer()
        // Lot 6 (19/11): a contact, a stranger (« ? ») and an invalid address (the triangle): never a color alone.
        let addresses = MailDraftRow(account: "moi@exemple.fr", mode: .new, to: [camille, jules, MailAddress(name: "Nina", email: "nina.roche@")],
                                     subject: "Revue du site", body: "Bonjour à tous,", signature: false, createdAt: Date())
        try store.saveDraft(addresses)
        try await Task.sleep(for: .milliseconds(300))
        mails.composing = addresses.id
        try await capture("mails-adresses")
        try await capture("mails-adresses-sombre", dark: true)
        mails.composing = nil
        try store.deleteDraft(addresses.id)
        // Review of 14/11: a draft changed on the phone waits for Paul's choice; a stranger shows in full.
        let changed = MailDraftRow(account: "moi@exemple.fr", mode: .new, to: [MailAddress(name: "camille@exemple-studio.fr", email: "inconnu@pirate.exemple")],
                                   subject: "Devis", body: "Voici le devis.", createdAt: Date(), conflict: .modifie)
        try store.saveDraft(changed)
        try await Task.sleep(for: .milliseconds(300))
        mails.composing = changed.id
        try await capture("mails-conflit")
        mails.composing = nil
        try store.saveDraft(MailDraftRow(account: "moi@exemple.fr", mode: .new, to: [MailAddress(name: "Jules Durand", email: "jules@atelier-nord.fr")],
                                         subject: "Planning d'avril", body: "Bonjour Jules, voici une proposition de planning.", origin: .agent, createdAt: Date()))
        mails.folder = .drafts
        try await capture("mails-brouillons")
        mails.folder = .subscriptions
        try await capture("mails-abonnements")
        try await capture("mails-abonnements-sombre", dark: true)
        // 15/11, « comme Gmail »: every thread, the compact list, Réglages › Mails.
        mails.folder = .all
        try await capture("mails-tous")
        // 15/11: « À : » in « Envoyés »; one search bar, the whole copy filtered as Paul types.
        mails.folder = .sent
        try await capture("mails-envoyes")
        // Wave B, 15/11: « Corbeille » and « Spam », the copy then Gmail's; only the way back; a spam without images.
        mails.folder = .trash
        for _ in 0..<100 where mails.readingAside { try await Task.sleep(for: .milliseconds(20)) }
        try await capture("mails-corbeille")
        mails.selecting = true
        mails.selected = [MailThreadRow.key(account: "moi@exemple.fr", threadID: "corbeille-copie")]
        try await capture("mails-corbeille-selection")
        mails.endSelection()
        router.mailSelection = MailThreadRow.key(account: "moi@exemple.fr", threadID: "corbeille-copie")
        try await capture("mails-corbeille-fil")
        try await capture("mails-corbeille-fil-sombre", dark: true)
        router.mailSelection = nil
        mails.folder = .spam
        for _ in 0..<100 where mails.readingAside { try await Task.sleep(for: .milliseconds(20)) }
        try await capture("mails-spam")
        try await capture("mails-spam-sombre", dark: true)
        router.mailSelection = MailThreadRow.key(account: "moi@exemple.fr", threadID: "spam-colis")
        try await capture("mails-spam-fil", wait: .milliseconds(2_500))
        try await capture("mails-spam-fil-sombre", dark: true, wait: .milliseconds(2_500))
        router.mailSelection = nil
        mails.query = "colis"
        try await capture("mails-spam-recherche")
        mails.query = ""
        mails.folder = .inbox
        mails.query = "maquette"
        try await capture("mails-recherche")
        mails.query = ""
        UserDefaults.standard.set(MailDensity.compacte.rawValue, forKey: Preferences.Key.mailDensity)
        UserDefaults.standard.set(true, forKey: Preferences.Key.mailDays)
        try await capture("mails-compacte-jours")
        UserDefaults.standard.removeObject(forKey: Preferences.Key.mailDensity)
        UserDefaults.standard.removeObject(forKey: Preferences.Key.mailDays)
        // Wave B, 15/11: « Programmer l'envoi » next to « Envoyer »; the mail locked, « Programmés », one that waits for Paul.
        let planning = MailDraftRow(account: "moi@exemple.fr", mode: .new, to: [MailAddress(name: "Jules Durand", email: "jules@atelier-nord.fr")],
                                    subject: "Planning de mai", body: "Bonjour Jules,\nVoici le planning de mai, avec la livraison le 12.", signature: false,
                                    createdAt: Date())
        try store.saveDraft(planning)
        try await Task.sleep(for: .milliseconds(300))
        mails.folder = .inbox
        mails.composing = planning.id
        try await capture("mails-envoyer-programmer")
        let tomorrow = try #require(SchedulePresets.options(now: Date()).first?.date)
        mails.schedule(planning.id, at: tomorrow)
        for _ in 0..<100 where mails.scheduled[planning.id] == nil { try await Task.sleep(for: .milliseconds(20)) }
        try await capture("mails-programme-annulable")
        let reply = try #require(mails.drafts.first { $0.threadKey == MailThreadRow.key(account: "moi@exemple.fr", threadID: "a") })
        mails.schedule(reply.id, at: try #require(SchedulePresets.options(now: Date()).last?.date))
        for _ in 0..<100 where mails.scheduled[reply.id] == nil { try await Task.sleep(for: .milliseconds(20)) }
        try await capture("mails-programme-ligne")
        mails.folder = .scheduled
        try await capture("mails-programmes")
        try await capture("mails-programmes-sombre", dark: true)
        mails.composing = planning.id
        try await capture("mails-programme-verrouille")
        mails.composing = nil
        router.mailSelection = reply.threadKey
        try await capture("mails-programme-reponse", wait: .milliseconds(2_000))
        router.mailSelection = nil
        // Security review of wave B: a reply programmed before its thread went to the trash still shows there, locked.
        let trashedReply = MailDraftRow(account: "moi@exemple.fr", mode: .reply, threadKey: MailThreadRow.key(account: "moi@exemple.fr", threadID: "corbeille-copie"),
                                        replyToKey: "moi@exemple.fr|t1", to: [camille], subject: "Re: Ancien devis du site",
                                        body: "Merci, je garde la version d'octobre.", signature: false, createdAt: Date())
        try store.saveDraft(trashedReply)
        try await Task.sleep(for: .milliseconds(300))
        mails.schedule(trashedReply.id, at: tomorrow)
        for _ in 0..<100 where mails.scheduled[trashedReply.id] == nil { try await Task.sleep(for: .milliseconds(20)) }
        mails.folder = .trash
        for _ in 0..<100 where mails.readingAside { try await Task.sleep(for: .milliseconds(20)) }
        router.mailSelection = trashedReply.threadKey
        try await capture("mails-corbeille-reponse-programmee", wait: .milliseconds(2_000))
        router.mailSelection = nil
        mails.folder = .scheduled
        // A launch later, thirteen hours late: it waits for Paul.
        try vault.save(vault.all.map { entry in
            var late = entry
            if entry.draftID == planning.id {
                late.state = .held
                late.sendAt = Date().addingTimeInterval(-13 * 3_600)
            }
            return late
        })
        let later = MailLibrary(agenda: agenda, root: root, defaults: UserDefaults(suiteName: "mails-\(UUID().uuidString)")!, send: { gmail.send(for: $0) },
                                vault: vault)
        for _ in 0..<100 where later.scheduled.count < 2 { try await Task.sleep(for: .milliseconds(20)) }
        later.folder = .scheduled
        shownMails = later
        try await capture("mails-programmes-en-retard")
        later.composing = planning.id
        try await capture("mails-programme-en-retard")
        try await capture("mails-programme-en-retard-sombre", dark: true)
        later.composing = nil
        // A reply that waits for Paul too: its thread's line says « En retard », in red (security review of wave B).
        try vault.save(vault.all.map { entry in
            var late = entry
            if entry.draftID == reply.id {
                late.state = .held
                late.sendAt = Date().addingTimeInterval(-14 * 3_600)
                late.firstTriedAt = late.sendAt.addingTimeInterval(20)
            }
            return late
        })
        let latest = MailLibrary(agenda: agenda, root: root, defaults: UserDefaults(suiteName: "mails-\(UUID().uuidString)")!, send: { gmail.send(for: $0) },
                                 vault: vault)
        for _ in 0..<100 where latest.scheduled.values.filter({ $0.state == .held }).count < 2 { try await Task.sleep(for: .milliseconds(20)) }
        shownMails = latest
        latest.folder = .inbox
        try await capture("mails-programme-ligne-en-retard")
        router.mailSelection = reply.threadKey
        try await capture("mails-programme-reponse-en-retard", wait: .milliseconds(2_000))
        router.mailSelection = nil
        shownMails = mails
        agenda.mails = mails
        try await LiveWindow.capture(SchedulePicker(now: Date()) { _ in }.background(Color(nsColor: .windowBackgroundColor)),
                                     to: output.appending(path: "mails-programmer-date.png"), size: NSSize(width: 320, height: 560))
        for id in [planning.id, reply.id, trashedReply.id] { mails.unschedule(id) }
        for _ in 0..<100 where !mails.scheduled.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        mails.message = nil
        try store.deleteDraft(planning.id)
        try store.deleteDraft(trashedReply.id)
        mails.folder = .inbox
        try store.remember(address: "lettre@lettre-du-design.exemple", tab: .some("personnes"), at: Date())
        router.openSettings(.mails)
        try await capture("reglages-mails", wait: .milliseconds(2_000))
        router.section = .mails
        mails.unreadOnly = true
        try await capture("mails-non-lus")
        mails.unreadOnly = false
        // Lot 6 (19/11): empty lists that say what to do — everything read, a folder emptied by hidden boxes —; one box
        // shown, no stripe on the lines.
        mails.hidden = ["moi@exemple.fr", "paul@atelier-nord.fr"]
        mails.folder = .all
        mails.unreadOnly = true
        try await capture("mails-vide-tout-lu")
        mails.unreadOnly = false
        mails.folder = .sent
        try await capture("mails-vide-boites")
        mails.hidden = ["perso@gmail.com", "paul@atelier-nord.fr"]
        mails.folder = .inbox
        try await capture("mails-une-boite")
        mails.hidden = []
        // The project's page shows its mails.
        UserDefaults.standard.set(false, forKey: Preferences.Key.floatingPages)
        router.section = .projects
        projects.selected = site.id
        try await capture("projet-mails")
        projects.selected = nil
        router.section = .mails
        try await capture("mails-lettre-page-sombre", dark: true)
        try await capture("mails-lettre-page")
        UserDefaults.standard.set(true, forKey: Preferences.Key.floatingPages)
        // Lot 6 (19/11), last: the reply leaving says « Envoyé · Annuler » in its own bar, nothing over it; « Annuler » keeps
        // it. Last, because the call back hands the draft to the made-up Gmail, which refuses it and marks it.
        let leaving = try #require(mails.drafts.first { $0.threadKey == MailThreadRow.key(account: "moi@exemple.fr", threadID: "a") })
        router.section = .mails
        router.mailSelection = leaving.threadKey
        mails.message = nil
        try await Task.sleep(for: .milliseconds(300))
        mails.send(leaving.id)
        try await capture("mails-envoye-annuler", wait: .milliseconds(1_200))
        mails.cancelSend(quietly: true)
        router.mailSelection = nil
    }

    /// 16/11: a draft an agent formatted and joined a file to, as the app adopts it (its HTML made by Polhub from the
    /// agent's markdown, its plain version shown whole), in the compose view.
    @Test func anAgentsFormattedDraft() async throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"]), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appending(path: "mails-agent \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase.inMemory()
        let account = "moi@exemple.fr"
        try CalendarStore(database).addAccount(email: account, at: Date())
        try CalendarStore(database).setGrantedScopes(email: account, scopes: "openid https://www.googleapis.com/auth/gmail.modify")
        let store = MailStore(database), files = MailFiles(root: root)
        let camille = MailAddress(name: "Camille Martin", email: "camille.martin@exemple-studio.fr")
        let received = MailMessageRow(account: account, messageID: "a1", threadID: "a", date: Date().addingTimeInterval(-3_600), sender: camille,
                                      to: [MailAddress(email: account)], subject: "Devis du site vitrine", snippet: "Peux-tu m'envoyer le devis ?",
                                      labels: ["INBOX", "CATEGORY_PERSONAL"], authenticated: true, hasBody: true, bodyIsHTML: true)
        try FileManager.default.createDirectory(at: files.body(of: received).deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("<p>Bonjour, peux-tu m'envoyer le devis ?</p><p>Camille</p>".utf8).write(to: files.body(of: received))
        try store.apply(account: account, upserts: [received])
        let markdown = """
        Bonjour Camille,

        Voici le **devis** du site vitrine, comme convenu :

        - la maquette des *trois pages* ;
        - l'intégration et la mise en ligne ;
        - [le planning détaillé](https://exemple.fr/planning).

        Belle journée,
        """
        let draft = MailDraftRow(account: account, mode: .new, to: [camille], subject: "Devis du site vitrine", body: MailMarkdown.plain(markdown),
                                 bodyHTML: MailMarkdown.html(markdown),
                                 files: [MailDraftFile(filename: "devis-site-vitrine.pdf", mimeType: "application/pdf", size: 182_000)],
                                 origin: .agent, createdAt: Date())
        try store.saveDraft(draft)
        let agenda = AgendaLibrary(database: database)
        let mails = MailLibrary(agenda: agenda, root: root, defaults: try #require(UserDefaults(suiteName: "mails-agent-\(UUID().uuidString)")),
                                flavor: .dev, send: { AsideGmail([]).send(for: $0) }, vault: MemoryScheduleVault())
        for _ in 0..<150 where !mails.drafts.contains(where: { $0.id == draft.id }) { try await Task.sleep(for: .milliseconds(20)) }
        let router = WindowRouter()
        router.section = .mails
        mails.composing = draft.id
        for dark in [false, true] {
            try await LiveWindow.capture(MainWindowView(library: MeetingLibrary(store: MeetingStore(database)), agenda: agenda, mails: mails, router: router,
                                                        paths: AppPaths(root: root, logs: root)) { EmptyView() },
                                         to: output.appending(path: "mails-brouillon-agent-mis-en-forme\(dark ? "-sombre" : "").png"),
                                         size: NSSize(width: 1_180, height: 780), dark: dark, wait: .milliseconds(1_500))
        }
    }
}

/// Real mails, on Paul's Mac only, to check their rendering: `POLHUB_VRAIS_MAILS=<fichier.html>:<fichier.html>`
/// with `POLHUB_LIVE=1 POLHUB_SNAPSHOTS=<dossier hors du dépôt>`. Nothing of them is kept in the repository.
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["POLHUB_VRAIS_MAILS"] != nil))
struct RealMailRenderingTests {
    struct Host: View {
        let body_: String
        let dark: Bool
        @State private var height: CGFloat = 60
        @State private var light = false

        var body: some View {
            ScrollView {
                MailBodyView(document: MailHTML.document(body: body_, isHTML: true, images: false, collapseQuote: true, dark: dark && !light),
                             images: false, dark: dark && !light, prefersLight: $light, inline: { _ in nil }, onLink: { _ in }, height: $height)
                    .frame(height: height)
                    .padding(light && dark ? 12 : 0)
                    .background(light && dark ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 10))
                    .padding(28)
            }
            .frame(width: 860, height: 980)
        }
    }

    @Test func realMailsRender() async throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"]), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let files = (ProcessInfo.processInfo.environment["POLHUB_VRAIS_MAILS"] ?? "").split(separator: ":").map(String.init)
        for (index, path) in files.enumerated() {
            let text = try String(contentsOfFile: path, encoding: .utf8)
            let fixed = MailParser.repaired(text) ?? text
            for dark in [false, true] {
                try await LiveWindow.capture(Host(body_: fixed, dark: dark), to: output.appending(path: "vrai-\(index)-\(dark ? "sombre" : "clair").png"),
                                             size: NSSize(width: 860, height: 980), dark: dark, wait: .milliseconds(2_000))
            }
        }
    }
}

/// macOS's notification center, silent: the captures show the bell, nothing reaches the screen's corner.
struct SilentNotifications: NotificationCenterClient {
    func pendingIdentifiers() async -> [String] { [] }
    func schedule(_ notice: PlannedNotice, sound: Bool) async {}
    func removePending(_ ids: [String]) async {}
    func deliverNow(_ notice: PlannedNotice, sound: Bool) async {}
}
