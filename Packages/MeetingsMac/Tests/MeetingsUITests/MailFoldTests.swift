import AppKit
import Foundation
import Mail
import Testing
import WebKit

/// Paul, 19/11: in an open thread, each message shows what was written; the quoted history and the signature fold
/// behind a small button each, and the headers of a quoted or forwarded mail are made light. The app's own script does
/// it in a web view that never comes on screen. Every name, address and number is invented; the shapes are real ones.
@MainActor @Suite struct MailFoldTests {
    /// A page as a message is shown, its script run, and a way to ask it what shows.
    @MainActor final class Page {
        let view: WKWebView

        init(_ body: String, isHTML: Bool = true, collapseQuote: Bool = true) async throws {
            let configuration = WKWebViewConfiguration()
            let preferences = WKWebpagePreferences()
            preferences.allowsContentJavaScript = false
            configuration.defaultWebpagePreferences = preferences
            configuration.userContentController.addUserScript(WKUserScript(source: MailHTML.readerScript, injectionTime: .atDocumentEnd,
                                                                           forMainFrameOnly: true, in: .defaultClient))
            view = WKWebView(frame: NSRect(x: 0, y: 0, width: 700, height: 600), configuration: configuration)
            view.load(Data(MailHTML.document(body: body, isHTML: isHTML, images: false, collapseQuote: collapseQuote).utf8),
                      mimeType: "text/html", characterEncodingName: "UTF-8", baseURL: URL(string: "about:blank")!)
            for _ in 0..<100 {
                let ready = try? await view.callAsyncJavaScript("return document.readyState === 'complete' && document.body.getAttribute('data-polhub-folded') === '1'",
                                                                arguments: [:], in: nil, contentWorld: .defaultClient) as? Bool
                if ready == true { return }
                try await Task.sleep(for: .milliseconds(100))
            }
            Issue.record("La page n'a pas fini de se plier.")
        }

        func run(_ script: String, _ arguments: [String: Any] = [:]) async throws -> Any? {
            try await view.callAsyncJavaScript(script, arguments: arguments, in: nil, contentWorld: .defaultClient)
        }

        /// Whether the element shows: a folded one, or one inside a folded part, has no box.
        func shows(_ id: String) async throws -> Bool {
            try await run("var e = document.getElementById(id); return !!e && e.getClientRects().length > 0", ["id": id]) as? Bool ?? false
        }

        /// The buttons of the page, by kind (« quote », « signature »).
        func buttons() async throws -> [String] {
            (try await run("return Array.prototype.map.call(document.querySelectorAll('button[data-polhub-fold]'), function (b) { return b.getAttribute('data-polhub-fold'); })")
                as? [String]) ?? []
        }

        func press(_ kind: String) async throws {
            _ = try await run("document.querySelector('button[data-polhub-fold=\"' + kind + '\"]').click()", ["kind": kind])
        }

        func isLight(_ id: String) async throws -> Bool {
            try await run("var e = document.getElementById(id); return !!e && (e.closest('.polhub-light') !== null || e.querySelector('.polhub-light') !== null)", ["id": id]) as? Bool ?? false
        }

        var text: String {
            get async throws { try await run("return document.body.innerText") as? String ?? "" }
        }
    }

    /// Outlook on Windows: no class nor id, a header block under a grey rule; the signature has no marker either.
    static let outlook = """
    <div class=WordSection1><p class=MsoNormal id="neuf">Bonjour Paul, voici le devis signé.</p>
    <p class=MsoNormal id="formule">Bien à vous,</p><p class=MsoNormal id="prenom">Camille</p>
    <p class=MsoNormal id="sig1">Studio Exemple</p><p class=MsoNormal id="sig2">T +33 1 23 45 67 89 | M +33 6 12 34 56 78</p>
    <p class=MsoNormal id="sig3">www.exemple.fr</p><p class=MsoNormal id="legal">Ce message et ses pièces jointes sont confidentiels.</p>
    <div style="border:none;border-top:solid #E1E1E1 1.0pt;padding:3.0pt 0cm 0cm 0cm"><p class=MsoNormal id="entete"><b>De&nbsp;:</b> Léa Durand &lt;lea@exemple.fr&gt;<br>
    <b>Envoyé&nbsp;:</b> jeudi 5 novembre 2026 14:20<br><b>À&nbsp;:</b> Camille Martin<br><b>Objet&nbsp;:</b> RE: Devis</p></div>
    <p class=MsoNormal id="ancien">Bonjour Camille, pouvez-vous m'envoyer le devis ?</p></div>
    """

    @Test func outlookHistoryAndSignatureFold() async throws {
        let page = try await Page(Self.outlook)
        for id in ["neuf", "formule", "prenom"] {
            let shown = try await page.shows(id)
            #expect(shown, "\(id)")
        }
        for id in ["sig1", "sig2", "sig3", "legal", "entete", "ancien"] {
            let shown = try await page.shows(id)
            #expect(!shown, "\(id)")
        }
        let buttons = try await page.buttons()
        #expect(buttons == ["signature", "quote"])
        try await page.press("quote")
        let ancien = try await page.shows("ancien"), entete = try await page.shows("entete"), light = try await page.isLight("entete")
        #expect(ancien && entete && light, "ancien \(ancien) entete \(entete) light \(light)")
        try await page.press("signature")
        let phone = try await page.shows("sig2"), legal = try await page.shows("legal")
        #expect(phone && legal)
    }

    /// The first message of a thread keeps its history, its signature folds all the same.
    @Test func theFirstMessageKeepsItsHistory() async throws {
        let page = try await Page(Self.outlook, collapseQuote: false)
        let ancien = try await page.shows("ancien"), neuf = try await page.shows("neuf"), phone = try await page.shows("sig2")
        #expect(ancien && neuf && !phone)
        let buttons = try await page.buttons()
        #expect(buttons == ["signature"])
    }

    @Test func gmailMarkersFold() async throws {
        let page = try await Page("""
        <div dir="ltr" id="neuf">Merci !</div><br clear="all"><span class="gmail_signature_prefix">-- </span><br>
        <div dir="ltr" class="gmail_signature" data-smartmail="gmail_signature" id="sig">Camille<br>Studio Exemple</div>
        <div class="gmail_quote"><div dir="ltr" class="gmail_attr" id="attr">Le jeu. 8 oct. 2026 à 17:28, Léa Durand &lt;lea@exemple.fr&gt; a écrit :<br></div>
        <blockquote class="gmail_quote" id="ancien">Bonjour Camille,</blockquote></div>
        """)
        let neuf = try await page.shows("neuf"), sig = try await page.shows("sig"), ancien = try await page.shows("ancien"), attr = try await page.shows("attr")
        #expect(neuf && !sig && !ancien && !attr)
        let text = try await page.text, buttons = try await page.buttons()
        #expect(!text.contains("-- "))
        #expect(buttons == ["signature", "quote"])
    }

    /// A reply with no marker at all: the attribution line, in English with an RFC date, starts the history.
    @Test func anAttributionWithoutMarkerFolds() async throws {
        let page = try await Page("""
        <div id="neuf">Parfait.</div><div id="attr">On Tue, 09 Jun 2026 16:13:18 GMT Camille Martin &lt;camille@exemple.fr&gt; wrote:</div>
        <div id="ancien">Bonsoir à tous,</div>
        """)
        let neuf = try await page.shows("neuf"), attr = try await page.shows("attr"), ancien = try await page.shows("ancien")
        #expect(neuf && !attr && !ancien)
    }

    /// What stays whole: a mail made only of a quote, and prose that says « a écrit ».
    @Test func whatIsNeverFolded() async throws {
        let onlyQuote = try await Page("""
        <div id="attr">On Tue, 09 Jun 2026 16:13:18 GMT Camille Martin &lt;camille@exemple.fr&gt; wrote:</div><div id="ancien">Bonsoir à tous,</div>
        """)
        let kept = try await onlyQuote.shows("ancien"), none = try await onlyQuote.buttons()
        #expect(kept && none.isEmpty)
        let prose = try await Page(#"<p id="a">Le directeur a écrit : il faut finir vendredi.</p><p id="b">Je m'en occupe.</p>"#)
        let a = try await prose.shows("a"), b = try await prose.shows("b"), proseButtons = try await prose.buttons()
        #expect(a && b && proseButtons.isEmpty)
    }

    /// A forward stays readable: its header is made light, the forwarded mail shows.
    @Test func aForwardShowsWithALightHeader() async throws {
        let page = try await Page("""
        <div id="neuf">Pour info.</div><div class="gmail_quote"><div dir="ltr" class="gmail_attr" id="fwd">---------- Message transféré ---------<br>
        De : Camille Martin &lt;camille@exemple.fr&gt;<br>Date : ven. 25 sept. 2026 à 17:31<br>Objet : Planning<br>À : Paul &lt;paul@exemple.fr&gt;<br></div>
        <div id="contenu">Le planning est en pièce jointe.</div></div>
        """)
        let contenu = try await page.shows("contenu"), fwd = try await page.shows("fwd"), light = try await page.isLight("fwd")
        #expect(contenu && fwd && light)
        let buttons = try await page.buttons()
        #expect(!buttons.contains("quote"))
    }

    /// A history pasted flat, in the middle of a paragraph (Outlook for iOS copied over): cut where it starts.
    @Test func aFlatHistoryIsCutInTheMiddle() async throws {
        let page = try await Page("""
        <p id="neuf">Top merci ! Sent from Outlook for iOS&lt;https://aka.ms/o0ukef&gt; ________________________________ From: Camille Martin \
        &lt;camille@exemple.fr&gt; Sent: Thursday, 08 October 2026 17:32:24 To: Léa Durand &lt;lea@exemple.fr&gt; Subject: Re: Website Bonjour, ancien texte.</p>
        """)
        let text = try await page.text, buttons = try await page.buttons()
        #expect(text.contains("Top merci") && !text.contains("ancien texte") && !text.contains("Subject:"))
        #expect(buttons.contains("quote"))
    }

    /// A plain text mail, cut by `MailPlainText`, folds the same way.
    @Test func aPlainTextMailFolds() async throws {
        let page = try await Page("Vu, merci.\n\nBien à vous,\nCamille\nStudio Exemple\nwww.exemple.fr\n06 12 34 56 78\n\nLe jeu. 8 oct. 2026 à 17:28, Léa <lea@exemple.fr> a écrit :\n> Bonjour\n",
                                  isHTML: false)
        let text = try await page.text, buttons = try await page.buttons()
        #expect(text.contains("Vu, merci.") && text.contains("Camille"))
        #expect(!text.contains("Studio Exemple") && !text.contains("Bonjour"))
        #expect(buttons == ["signature", "quote"])
    }
}

/// The folds as Paul sees them (19/11): `POLHUB_LIVE=1 POLHUB_SNAPSHOTS=<dossier hors du dépôt> swift test --filter
/// MailFoldScreenTests`. The windows stay under every other one.
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"] != nil))
struct MailFoldScreenTests {
    static let forward = """
    <div>Pour info, le planning de Camille.</div><div class="gmail_quote"><div dir="ltr" class="gmail_attr">---------- Message transféré ---------<br>
    De : Camille Martin &lt;camille@exemple.fr&gt;<br>Date : ven. 25 sept. 2026 à 17:31<br>Objet : Planning<br>À : Paul &lt;paul@exemple.fr&gt;<br></div><br>
    <div>Bonjour Paul,</div><div>Le planning est en pièce jointe. La livraison reste au 12 octobre.</div><div>Bien à vous,</div><div>Camille</div>
    <div>Studio Exemple</div><div>01 23 45 67 89</div><div>www.exemple.fr</div></div>
    """

    @Test func theFolds() async throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"]), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, body) in [("outlook", MailFoldTests.outlook), ("transfert", Self.forward)] {
            for dark in [false, true] {
                try await LiveWindow.capture(RealMailRenderingTests.Host(body_: body, dark: dark),
                                             to: output.appending(path: "plis-\(name)\(dark ? "-sombre" : "").png"),
                                             size: NSSize(width: 860, height: 560), dark: dark, wait: .milliseconds(2_000))
            }
        }
    }
}
