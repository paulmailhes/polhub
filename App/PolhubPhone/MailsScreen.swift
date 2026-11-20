import PolhubLink
import QuickLook
import SwiftUI
import WebKit

/// Mails: the Mac's folders, its lists, its threads (20/11). Read only in this version.
struct MailsScreen: View {
    @Environment(PhoneSession.self) private var session
    @State private var folder = "inbox"
    @State private var folders: [LinkFolder] = []
    @State private var threads: [LinkThread] = []
    @State private var keptAt: Date?
    @State private var problem: String?
    @State private var loaded = false
    /// The thread open; `-fil` opens the first one at launch (the captures).
    @State private var path: [LinkThread] = []

    private var title: String { folders.first { $0.id == folder }?.title ?? "Boîte de réception" }

    var body: some View {
        NavigationStack(path: $path) {
            List(threads) { thread in
                NavigationLink(value: thread) { ThreadRow(thread: thread) }
            }
            .listStyle(.plain)
            .overlay {
                if loaded, threads.isEmpty, problem == nil {
                    ContentUnavailableView("Aucun mail", systemImage: "tray", description: Text("Ce dossier est vide."))
                }
            }
            .navigationTitle(title)
            .navigationDestination(for: LinkThread.self) { ThreadScreen(thread: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Dossier", selection: $folder) {
                            ForEach(folders) { folder in
                                Text(folder.unread > 0 ? "\(folder.title) (\(folder.unread))" : folder.title).tag(folder.id)
                            }
                        }
                    } label: {
                        Label("Dossiers", systemImage: "tray.2")
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { StateLine(keptAt: keptAt, problem: problem) }
            .refreshable { await load() }
            .task(id: folder) { await load() }
        }
    }

    private func load() async {
        do throws(LinkFailure) {
            let fetched = try await session.fetch([LinkThread].self, LinkAPI.Path.threads, query: ["dossier": folder, "limite": "150"])
            threads = fetched.value
            keptAt = fetched.keptAt
            problem = nil
            folders = (try? await session.fetch([LinkFolder].self, LinkAPI.Path.folders).value) ?? folders
            if path.isEmpty, ProcessInfo.processInfo.arguments.contains("-fil"), let first = threads.first { path = [first] }
        } catch {
            problem = error.message
        }
        loaded = true
    }
}

/// A line of the list: who, the subject and its beginning, the date; bold while unread.
struct ThreadRow: View {
    let thread: LinkThread

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                // « Camille, moi », the count lighter, as on the Mac.
                (Text(thread.people).fontWeight(thread.unread ? .semibold : .regular)
                    + Text(thread.messages > 1 ? " \(thread.messages)" : "").foregroundStyle(.secondary))
                    .lineLimit(1)
                Spacer()
                Text(LinkWords.listDate(thread.date)).font(.footnote).foregroundStyle(thread.unread ? .primary : .secondary)
            }
            Text(thread.subject).font(.subheadline).fontWeight(thread.unread ? .semibold : .regular).lineLimit(1)
            HStack(spacing: 6) {
                if let project = thread.project {
                    Text(project).font(.caption.weight(.medium)).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
                Text(thread.snippet).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if thread.hasFiles { Image(systemName: "paperclip").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .padding(.vertical, 2)
    }
}

/// A thread whole: its messages, the last ones open, their files.
struct ThreadScreen: View {
    let thread: LinkThread
    @Environment(PhoneSession.self) private var session
    @Environment(\.colorScheme) private var scheme
    @State private var detail: LinkThreadDetail?
    @State private var keptAt: Date?
    @State private var problem: String?
    @State private var preview: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(thread.subject).font(.title2.weight(.semibold))
                if let project = thread.project { Text(project).font(.subheadline).foregroundStyle(.secondary) }
                if let detail {
                    ForEach(Array(detail.messages.enumerated()), id: \.element.id) { index, message in
                        MessageView(message: message, open: index >= detail.messages.count - 1) { file in
                            Task {
                                do throws(LinkFailure) { preview = try await session.file(message: message.id, part: file.id, name: file.name) }
                                catch { problem = error.message }
                            }
                        }
                        if index < detail.messages.count - 1 { Divider() }
                    }
                } else if problem == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) { StateLine(keptAt: keptAt, problem: problem) }
        .quickLookPreview($preview)
        .task(id: scheme) {
            do throws(LinkFailure) {
                let fetched = try await session.fetch(LinkThreadDetail.self, LinkAPI.Path.thread,
                                                      query: ["fil": thread.id, "sombre": scheme == .dark ? "1" : "0"])
                detail = fetched.value
                keptAt = fetched.keptAt
            } catch {
                problem = error.message
            }
        }
    }
}

/// One message: who, when, and its body; an older one folded to its first line until touched.
struct MessageView: View {
    let message: LinkMessage
    @State var open: Bool
    let openFile: (LinkFile) -> Void
    @State private var height: CGFloat = 60

    init(message: LinkMessage, open: Bool, openFile: @escaping (LinkFile) -> Void) {
        self.message = message
        _open = State(initialValue: open)
        self.openFile = openFile
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation { open.toggle() } } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(message.from?.shown ?? "Inconnu").fontWeight(.semibold)
                            if message.authenticated { Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(.blue) }
                        }
                        if open, !message.to.isEmpty {
                            Text("à " + message.to.map(\.shown).joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    Text(LinkWords.listDate(message.date)).font(.footnote).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                MailBody(html: message.html, height: $height).frame(height: height)
                ForEach(message.files) { file in
                    Button { openFile(file) } label: {
                        Label("\(file.name) · \(ByteCountFormatStyle(style: .file, locale: LinkWords.locale).format(Int64(file.size)))",
                              systemImage: "doc")
                            .font(.subheadline).lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

/// A body as the Mac made it safe: no script, no remote image (its policy); a link opens in Safari. As tall as its text.
struct MailBody: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.navigationDelegate = context.coordinator
        context.coordinator.watch(view)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loaded != html else { return }
        context.coordinator.loaded = html
        view.loadHTMLString(Self.transparent(html), baseURL: nil)
    }

    /// The Mac's page on the iPhone: the phone's width (the Mac's page has none, and would show at 980 points, tiny),
    /// images and tables never wider than the screen, the iPhone's own ground under it.
    static func transparent(_ html: String) -> String {
        let style = "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
            + "<style>html,body{background:transparent!important}img{max-width:100%!important;height:auto!important}"
            + "table{max-width:100%!important}</style>"
        if let head = html.range(of: "</head>", options: .caseInsensitive) { return html.replacingCharacters(in: head, with: style + "</head>") }
        return style + html
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var height: Binding<CGFloat>
        var loaded: String?

        init(height: Binding<CGFloat>) {
            self.height = height
        }

        func watch(_ view: WKWebView) {}

        /// The text's own height, read in the app's own world: the page's scripts stay off.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                let value = try? await webView.callAsyncJavaScript("return document.body.scrollHeight", arguments: [:], in: nil,
                                                                   contentWorld: .defaultClient)
                if let size = (value as? NSNumber)?.doubleValue, size > 0 { self.height.wrappedValue = CGFloat(size) }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            if action.navigationType == .linkActivated, let url = action.request.url {
                await UIApplication.shared.open(url)
                return .cancel
            }
            return action.request.url?.scheme == "about" || action.navigationType == .other ? .allow : .cancel
        }
    }
}
