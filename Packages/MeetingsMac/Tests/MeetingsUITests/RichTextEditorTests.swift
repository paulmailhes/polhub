import AppKit
import Foundation
import Testing
import WebKit
@testable import MeetingsUI

/// The editor's page in WebKit (17/11): it opens a draft cleaned, formats what is chosen, cleans what is pasted, and
/// loads nothing.
@MainActor @Suite struct RichTextEditorTests {
    func page(messages: Messages? = nil) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        if let messages { configuration.userContentController.add(messages, name: "polhub") }
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        view.loadHTMLString(RichTextEditor.page, baseURL: nil)
        for _ in 0..<100 {
            let ready = try? await view.callAsyncJavaScript("return document.readyState === 'complete' && typeof window.polhub === 'object'",
                                                            arguments: [:], in: nil, contentWorld: .page) as? Bool
            if ready == true { return view }
            try await Task.sleep(for: .milliseconds(100))
        }
        Issue.record("la page de l'éditeur ne s'est pas chargée")
        return view
    }

    func run(_ view: WKWebView, _ script: String, _ arguments: [String: Any] = [:]) async throws -> Any? {
        try await view.callAsyncJavaScript(script, arguments: arguments, in: nil, contentWorld: .page)
    }

    @Test func theDraftOpensCleaned() async throws {
        let view = try await page()
        _ = try await run(view, "polhub.start(html, 'Écris ta réponse…'); polhub.setEditable(true)",
                          ["html": #"<p onclick="x()"><b>Bonjour</b> Camille<script>alert(1)</script><img src="https://pisteur.exemple/x.gif"></p><ul><li>le devis</li></ul>"#])
        let html = try await run(view, "return polhub.html()") as? String
        #expect(html == "<p><b>Bonjour</b> Camille</p><ul><li>le devis</li></ul>")
        let placeholder = try await run(view, "return document.getElementById('texte').getAttribute('data-placeholder')") as? String
        #expect(placeholder == "Écris ta réponse…")
    }

    @Test func boldAndListsFormatWhatIsChosen() async throws {
        let view = try await page()
        _ = try await run(view, "polhub.start('<div>la maquette</div>', ''); polhub.setEditable(true)")
        _ = try await run(view, """
            const texte = document.getElementById('texte');
            texte.focus();
            window.getSelection().selectAllChildren(texte);
            polhub.command('bold');
            """)
        let bold = try await run(view, "return polhub.html()") as? String ?? ""
        #expect(bold.contains("<b>la maquette</b>"), "\(bold)")
        _ = try await run(view, "window.getSelection().selectAllChildren(document.getElementById('texte')); polhub.command('insertUnorderedList')")
        let list = try await run(view, "return polhub.html()") as? String ?? ""
        #expect(list.contains("<ul>") && list.contains("<li>"), "\(list)")
    }

    @Test func whatIsPastedIsCleaned() async throws {
        let view = try await page()
        let cleaned = try await run(view, "return polhub.clean(html)",
                                    ["html": #"<meta charset="utf-8"><span style="font-family:Arial;color:#222">Voir <a href="https://exemple.fr" style="color:blue">le site</a></span><a href="javascript:alert(1)">piège</a><style>p{}</style>"#]) as? String
        #expect(cleaned == #"Voir <a href="https://exemple.fr">le site</a>piège"#)
    }

    /// The wheel over the text scrolls the page around it (Paul, 17/11: « je ne peux plus scroll »).
    @Test func theWheelGoesToThePageAround() throws {
        let page = WheelRecorder(frame: CGRect(x: 0, y: 0, width: 600, height: 800))
        let editor = RichTextEditor.EditorWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), configuration: WKWebViewConfiguration())
        page.addSubview(editor)
        let wheel = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -40, wheel2: 0, wheel3: 0))
        editor.scrollWheel(with: try #require(NSEvent(cgEvent: wheel)))
        #expect(page.wheels == 1)
    }

    /// Typing says where the caret is: the page keeps that line in sight, above the bar fixed at the bottom.
    @Test func typingSaysWhereTheCaretIs() async throws {
        let messages = Messages()
        let view = try await page(messages: messages)
        _ = try await run(view, """
            polhub.start('<p>Bonjour Camille,</p><p>la maquette</p>', ''); polhub.setEditable(true);
            const texte = document.getElementById('texte');
            texte.focus();
            const range = document.createRange();
            range.selectNodeContents(texte);
            range.collapse(false);
            window.getSelection().removeAllRanges();
            window.getSelection().addRange(range);
            document.execCommand('insertText', false, ' est prête');
            """)
        for _ in 0..<50 where !messages.received.contains(where: { $0["type"] as? String == "caret" }) {
            try await Task.sleep(for: .milliseconds(50))
        }
        let caret = messages.received.last { $0["type"] as? String == "caret" }
        let bottom = try #require(caret?["bottom"] as? Double)
        #expect(bottom > 30, "le curseur est sur la deuxième ligne : \(bottom)")
    }

    /// Moving with the arrows, held down or with ⌘, follows the caret too (review of 17/11): keyup never comes for ⌘↓.
    @Test func theArrowsFollowTheCaret() async throws {
        let messages = Messages()
        let view = try await page(messages: messages)
        _ = try await run(view, "polhub.start('<p>Bonjour Camille,</p><p>la maquette</p>', ''); polhub.setEditable(true); document.getElementById('texte').focus();")
        messages.received.removeAll()
        _ = try await run(view, "document.getElementById('texte').dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', metaKey: true, bubbles: true }))")
        for _ in 0..<40 where !messages.received.contains(where: { $0["type"] as? String == "caret" }) {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(messages.received.contains { $0["type"] as? String == "caret" })
    }

    /// The page's own policy forbids every request: a pasted image never loads.
    @Test func thePageLoadsNothing() {
        #expect(RichTextEditor.page.contains("default-src 'none'") && RichTextEditor.page.contains("img-src 'none'"))
    }
}

/// The page around the editor: it counts the wheel events it receives.
final class WheelRecorder: NSView {
    var wheels = 0
    override func scrollWheel(with event: NSEvent) { wheels += 1 }
}

/// The page's messages, as the editor's coordinator receives them.
@MainActor final class Messages: NSObject, WKScriptMessageHandler {
    var received: [[String: Any]] = []

    nonisolated func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        MainActor.assumeIsolated { received.append(body) }
    }
}
