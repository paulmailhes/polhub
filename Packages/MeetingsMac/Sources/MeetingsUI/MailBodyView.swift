import AppKit
import Mail
import SwiftUI
import WebKit

/// WebKit's content rules, compiled once for each of the two cases (images allowed or not).
@MainActor
enum MailContentRules {
    private static var lists: [Bool: WKContentRuleList] = [:]

    static func list(images: Bool) async -> WKContentRuleList? {
        if let list = lists[images] { return list }
        let list = try? await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "polhub-mails-\(images ? "images" : "sans-images")-2",
                                                                                     encodedContentRuleList: MailHTML.contentRules(images: images))
        lists[images] = list
        return list
    }
}

/// The scroll wheel goes to the page around: a mail never scrolls inside itself.
final class MailWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}

/// One message's body, as its sender wrote it, behind four locks (14/11): the mail's scripts are off, a content
/// policy and WebKit's content rules let nothing load but what Paul allowed, nothing is kept (no cookie), and
/// any click leaves for the browser. The app's own script measures the page and folds the quoted text.
struct MailBodyView: NSViewRepresentable {
    /// The page, from `MailHTML.document`.
    let document: String
    /// Whether remote images may load (the page's policy says the same).
    let images: Bool
    /// macOS's Lockdown Mode for this view.
    var lockdown = true
    /// The page is adapted to dark mode; otherwise the view itself is light, so that a mail's own dark style
    /// stays off too.
    var dark = false
    /// The script found a mail made of images: the app shows it on a light card.
    var prefersLight: Binding<Bool>? = nil
    /// The bytes and the type of an image joined to the mail, by its content id.
    let inline: @MainActor (String) async -> (Data, String)?
    let onLink: (URL) -> Void
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> MailWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = false
        preferences.isLockdownModeEnabled = lockdown
        configuration.defaultWebpagePreferences = preferences
        configuration.setURLSchemeHandler(context.coordinator, forURLScheme: "cid")
        configuration.userContentController.addUserScript(WKUserScript(source: MailHTML.readerScript, injectionTime: .atDocumentEnd,
                                                                       forMainFrameOnly: true, in: .defaultClient))
        configuration.userContentController.add(context.coordinator, contentWorld: .defaultClient, name: "polhub")
        let view = MailWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        // No background of its own: the mail sits on the app's, light or dark (Paul, 14/11).
        view.setValue(false, forKey: "drawsBackground")
        view.underPageBackgroundColor = .clear
        view.allowsMagnification = false
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        context.coordinator.load(document, images: images, in: view)
        return view
    }

    func updateNSView(_ view: MailWebView, context: Context) {
        context.coordinator.parent = self
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        context.coordinator.load(document, images: images, in: view)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKURLSchemeHandler {
        var parent: MailBodyView
        private var loaded: String?
        private var stopped: Set<ObjectIdentifier> = []

        init(_ parent: MailBodyView) {
            self.parent = parent
        }

        /// Loads the page once; the content rules are in place before anything can load.
        func load(_ document: String, images: Bool, in view: WKWebView) {
            guard loaded != document else { return }
            loaded = document
            Task { @MainActor in
                let controller = view.configuration.userContentController
                controller.removeAllContentRuleLists()
                if let rules = await MailContentRules.list(images: images) { controller.add(rules) }
                guard self.loaded == document else { return }
                view.load(Data(document.utf8), mimeType: "text/html", characterEncodingName: "UTF-8", baseURL: URL(string: "about:blank")!)
            }
        }

        // Only the page itself loads. A click on a link leaves for the browser; nothing else navigates.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            if action.navigationType == .linkActivated {
                if let url = action.request.url, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") { parent.onLink(url) }
                return .cancel
            }
            let isPage = action.targetFrame?.isMainFrame == true && action.navigationType == .other
                && (action.request.url?.absoluteString == "about:blank" || action.request.url == nil)
            return isPage ? .allow : .cancel
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            if body["light"] as? Bool == true, let prefersLight = parent.prefersLight, !prefersLight.wrappedValue { prefersLight.wrappedValue = true }
            guard let height = body["height"] as? Double, height > 0 else { return }
            // A page cannot ask for an endless frame.
            let fitted = min(CGFloat(height), 60_000)
            if abs(parent.height - fitted) > 0.5 { parent.height = fitted }
        }

        // `cid:` — the images the mail carries with it.
        func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
            guard let url = task.request.url else { return }
            let id = (url.absoluteString.dropFirst("cid:".count).removingPercentEncoding ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            let key = ObjectIdentifier(task)
            Task { @MainActor in
                let found = await self.parent.inline(id)
                guard !self.stopped.contains(key) else {
                    self.stopped.remove(key)
                    return
                }
                guard let (data, type) = found else {
                    task.didFailWithError(URLError(.fileDoesNotExist))
                    return
                }
                task.didReceive(URLResponse(url: url, mimeType: type, expectedContentLength: data.count, textEncodingName: nil))
                task.didReceive(data)
                task.didFinish()
            }
        }

        func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
            stopped.insert(ObjectIdentifier(task))
        }
    }
}
