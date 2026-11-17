import Foundation
import Testing
import WebKit
@testable import MeetingsUI

/// The editor's page in WebKit (17/11): it opens a draft cleaned, formats what is chosen, cleans what is pasted, and
/// loads nothing.
@MainActor @Suite struct RichTextEditorTests {
    func page() async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
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

    /// The page's own policy forbids every request: a pasted image never loads.
    @Test func thePageLoadsNothing() {
        #expect(RichTextEditor.page.contains("default-src 'none'") && RichTextEditor.page.contains("img-src 'none'"))
    }
}
