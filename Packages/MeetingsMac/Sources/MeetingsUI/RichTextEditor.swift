import AppKit
import MailFormat
import PolhubDesign
import SwiftUI
import WebKit

/// The text of a draft, written with formatting as in Gmail (Paul, 17/11: « une mise en forme comme si j'étais sur
/// Gmail, et que je puisse la modifier »): bold, italic, underline, lists, links, ⌘B ⌘I ⌘U ⌘K. A web view of its own
/// page, which loads nothing (its rules forbid every request), never follows a link, and keeps no cookie; what it
/// gives is kept to simple formatting (`MailRichText.clean`) before it is saved.
@MainActor
final class RichTextController: ObservableObject {
    fileprivate weak var webView: WKWebView?
    /// The editor holds the keyboard: ⌘↩ sends the draft being written.
    @Published var isFocused = false
    /// ⌘K or the toolbar's link button asked for an address.
    @Published var askingLink = false

    func run(_ script: String) {
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    func bold() { run("polhub.command('bold')") }
    func italic() { run("polhub.command('italic')") }
    func underline() { run("polhub.command('underline')") }
    func bulletList() { run("polhub.command('insertUnorderedList')") }
    func numberedList() { run("polhub.command('insertOrderedList')") }
    func removeFormat() { run("polhub.command('removeFormat'); polhub.command('unlink')") }

    /// The address typed for a link: on the words chosen, or written as the link's words.
    func link(_ typed: String) {
        guard let address = Self.address(typed) else { return }
        let quoted = (try? JSONSerialization.data(withJSONObject: [address]))
            .flatMap { String(data: $0, encoding: .utf8) }.map { String($0.dropFirst().dropLast()) } ?? "\"\""
        run("polhub.link(\(quoted))")
    }

    /// « exemple.fr/devis » → `https://exemple.fr/devis`; an address → `mailto:`; never `javascript:` nor a file.
    static func address(_ typed: String) -> String? {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }
        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("mailto:") { return text }
        if text.contains("@"), !text.contains("/") { return "mailto:" + text }
        if lower.contains(":") { return nil }
        return "https://" + text
    }
}

struct RichTextEditor: NSViewRepresentable {
    /// What the editor opens with; read once, never pushed again over what Paul types.
    let initialHTML: String
    let placeholder: String
    let isEditable: Bool
    /// A reply puts the caret in its text at once.
    var focusOnStart = false
    let controller: RichTextController
    @Binding var height: CGFloat
    /// The editor's HTML, as Paul writes (not yet cleaned).
    let onChange: (String) -> Void

    /// The editor's height before its text grows it.
    static let minimumHeight: CGFloat = 180

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(WeakHandler(context.coordinator), name: "polhub")
        let view = EditorWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        view.allowsMagnification = false
        controller.webView = view
        context.coordinator.view = view
        view.loadHTMLString(Self.page, baseURL: nil)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.setEditable(isEditable)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "polhub")
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: RichTextEditor
        weak var view: WKWebView?
        private var ready = false
        private var editable: Bool?

        init(_ parent: RichTextEditor) { self.parent = parent }

        func setEditable(_ on: Bool) {
            guard ready, editable != on else { return }
            editable = on
            view?.evaluateJavaScript("polhub.setEditable(\(on))", completionHandler: nil)
        }

        /// Only its own page: a link clicked, a drop, a redirect go nowhere.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            action.navigationType == .other && action.request.url?.absoluteString == "about:blank" ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !ready else { return }
            ready = true
            let payload = (try? JSONSerialization.data(withJSONObject: [parent.initialHTML, parent.placeholder]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\",\"\"]"
            webView.evaluateJavaScript("polhub.start(...\(payload))", completionHandler: nil)
            setEditable(parent.isEditable)
            if parent.focusOnStart, parent.isEditable {
                webView.window?.makeFirstResponder(webView)
                webView.evaluateJavaScript("document.getElementById('texte').focus()", completionHandler: nil)
            }
        }

        /// The line being typed stays in sight, above the draft's bar fixed at the bottom of the page: the editor
        /// never scrolls itself, the page around it does (17/11).
        private func follow(caretBottom: CGFloat) {
            guard let view else { return }
            let y = view.isFlipped ? caretBottom : view.bounds.height - caretBottom
            let margin: CGFloat = 96
            view.scrollToVisible(NSRect(x: 0, y: view.isFlipped ? y - 28 : y - margin, width: 1, height: 28 + margin))
        }

        func received(_ message: [String: Any]) {
            switch message["type"] as? String {
            case "change": if let html = message["html"] as? String { parent.onChange(html) }
            case "height": if let value = message["value"] as? Double { parent.height = CGFloat(value) }
            case "focus": parent.controller.isFocused = message["value"] as? Bool ?? false
            case "link": parent.controller.askingLink = true
            case "caret": if let bottom = message["bottom"] as? Double { follow(caretBottom: CGFloat(bottom)) }
            default: break
            }
        }
    }

    /// The page's messages, without the page holding the coordinator.
    final class WeakHandler: NSObject, WKScriptMessageHandler {
        weak var coordinator: Coordinator?
        init(_ coordinator: Coordinator) { self.coordinator = coordinator }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            MainActor.assumeIsolated { coordinator?.received(body) }
        }
    }

    /// A first click in the editor places the caret even when Polhub is not in front. The wheel goes to the page
    /// around it: the editor grows with its text and has nothing to scroll (Paul, 17/11: « je ne peux plus scroll »).
    final class EditorWebView: WKWebView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func scrollWheel(with event: NSEvent) { nextResponder?.scrollWheel(with: event) }
    }

    /// The editor's page: no request of any kind (its policy), a block that edits, the system's font and colours.
    static let page = """
    <!doctype html><html><head><meta charset="utf-8">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src 'none'">
    <style>
    :root { color-scheme: light dark; }
    html, body { margin: 0; padding: 0; background: transparent; }
    body { font: \(Int(TextSize.reading))px -apple-system, system-ui, sans-serif; line-height: 1.45; color: CanvasText; overflow: hidden; }
    #texte { outline: none; min-height: 170px; padding: 2px 5px 8px; overflow-wrap: anywhere; }
    #texte:empty::before { content: attr(data-placeholder); color: GrayText; pointer-events: none; }
    #texte p { margin: 0 0 0.7em; }
    #texte ul, #texte ol { margin: 0.2em 0 0.7em; padding-left: 1.6em; }
    #texte blockquote { margin: 0.3em 0 0.7em; padding-left: 0.8em; border-left: 2px solid GrayText; color: GrayText; }
    #texte a { color: LinkText; }
    </style></head><body><div id="texte" contenteditable="false" spellcheck="true"></div>
    <script>
    (function () {
      const texte = document.getElementById('texte');
      const post = (message) => { try { window.webkit.messageHandlers.polhub.postMessage(message); } catch (e) {} };
      let timer = null, saved = null;
      const size = () => post({ type: 'height', value: Math.ceil(document.documentElement.scrollHeight) });
      const flush = () => { clearTimeout(timer); timer = null; post({ type: 'change', html: texte.innerHTML }); };
      const caret = () => {
        const chosen = window.getSelection();
        if (!chosen || chosen.rangeCount === 0 || !texte.contains(chosen.focusNode)) return;
        const range = chosen.getRangeAt(0).cloneRange();
        range.collapse(false);
        let box = range.getBoundingClientRect();
        if (box.bottom === 0 && box.top === 0) {
          const node = chosen.focusNode.nodeType === 1 ? chosen.focusNode : chosen.focusNode.parentElement;
          box = node.getBoundingClientRect();
        }
        post({ type: 'caret', bottom: box.bottom });
      };
      const changed = () => { clearTimeout(timer); timer = setTimeout(flush, 250); size(); caret(); };
      const keep = new Set(['B', 'STRONG', 'I', 'EM', 'U', 'A', 'UL', 'OL', 'LI', 'P', 'DIV', 'BR', 'BLOCKQUOTE']);
      const drop = new Set(['SCRIPT', 'STYLE', 'META', 'LINK', 'TITLE', 'IFRAME', 'OBJECT', 'EMBED', 'IMG', 'SVG', 'VIDEO', 'AUDIO', 'FORM', 'INPUT', 'BUTTON', 'TEMPLATE']);
      function clean(html) {
        const page = new DOMParser().parseFromString(html, 'text/html');
        const walk = (node) => {
          for (const child of Array.from(node.childNodes)) {
            if (child.nodeType === 1) {
              if (drop.has(child.tagName)) { child.remove(); continue; }
              walk(child);
              if (!keep.has(child.tagName)) { child.replaceWith(...Array.from(child.childNodes)); continue; }
              for (const attribute of Array.from(child.attributes)) {
                const ok = (child.tagName === 'A' && attribute.name === 'href' && /^(https?:|mailto:)/i.test(attribute.value.trim()))
                  || (child.tagName === 'OL' && attribute.name === 'start');
                if (!ok) child.removeAttribute(attribute.name);
              }
              if (child.tagName === 'A' && !child.hasAttribute('href')) child.replaceWith(...Array.from(child.childNodes));
            } else if (child.nodeType !== 3) {
              child.remove();
            }
          }
        };
        walk(page.body);
        return page.body.innerHTML;
      }
      function selection() {
        const chosen = window.getSelection();
        return chosen && chosen.rangeCount > 0 && texte.contains(chosen.anchorNode) ? chosen.getRangeAt(0).cloneRange() : null;
      }
      function restore() {
        if (!saved) return;
        const chosen = window.getSelection();
        chosen.removeAllRanges();
        chosen.addRange(saved);
      }
      texte.addEventListener('input', changed);
      texte.addEventListener('focus', () => post({ type: 'focus', value: true }));
      texte.addEventListener('blur', () => { saved = selection(); if (timer) flush(); post({ type: 'focus', value: false }); });
      texte.addEventListener('keyup', (event) => { if (event.key.startsWith('Arrow') || event.key.startsWith('Page')) caret(); });
      texte.addEventListener('keydown', (event) => {
        if (!event.metaKey || event.altKey || event.ctrlKey) return;
        const key = event.key.toLowerCase();
        const run = { b: 'bold', i: 'italic', u: 'underline' }[key];
        if (run) { event.preventDefault(); window.polhub.command(run); }
        else if (key === 'k') { event.preventDefault(); saved = selection(); post({ type: 'link' }); }
      });
      texte.addEventListener('paste', (event) => {
        event.preventDefault();
        const html = event.clipboardData.getData('text/html');
        if (html) document.execCommand('insertHTML', false, clean(html));
        else document.execCommand('insertText', false, event.clipboardData.getData('text/plain'));
      });
      texte.addEventListener('drop', (event) => event.preventDefault());
      new ResizeObserver(size).observe(texte);
      window.polhub = {
        start(html, placeholder) { texte.innerHTML = clean(html); texte.setAttribute('data-placeholder', placeholder); size(); },
        setEditable(on) { texte.contentEditable = on ? 'true' : 'false'; },
        command(name, value) {
          if (document.activeElement !== texte) { texte.focus(); restore(); }
          document.execCommand(name, false, value === undefined ? null : value);
          changed();
        },
        link(address) {
          texte.focus();
          restore();
          const chosen = window.getSelection();
          if (chosen && chosen.rangeCount > 0 && !chosen.isCollapsed) document.execCommand('createLink', false, address);
          else document.execCommand('insertHTML', false, '<a href="' + address.replace(/"/g, '&quot;') + '">' + address.replace(/&/g, '&amp;').replace(/</g, '&lt;') + '</a>');
          changed();
        },
        html() { return texte.innerHTML; },
        clean: clean,
      };
    })();
    </script></body></html>
    """
}
