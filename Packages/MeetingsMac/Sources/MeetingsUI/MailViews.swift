import Agenda
import AppKit
import GRDB
import Mail
import MailFormat
import Persistence
import PolhubDesign
import ProjectsUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// The section « Mails » (Paul, 14/11): the list takes the whole width; a thread opens over it, in a floating
/// panel (the list stays in sight), or in its place (Réglages › Général).
struct MailSectionView: View {
    @ObservedObject var mails: MailLibrary
    @ObservedObject var router: WindowRouter
    @AppStorage(Preferences.Key.floatingPages) private var floating = true

    private func close() { router.mailSelection = nil }

    var body: some View {
        Group {
            if mails.accounts.isEmpty {
                ContentUnavailableView {
                    Label("Aucune boîte autorisée", systemImage: "envelope")
                } description: {
                    Text("Autorise les mails d'un compte Google pour les lire ici.")
                } actions: {
                    Button("Ouvrir Réglages › Comptes Google") { router.openSettings(.accounts) }
                }
                .windowTitle("Mails")
            } else if !floating, let key = router.mailSelection {
                MailThreadView(key: key, mails: mails, router: router, close: nil).id(key)
            } else {
                MailListView(mails: mails, router: router)
                    .overlay {
                        if floating, let key = router.mailSelection {
                            FloatingPanel(close: close) {
                                MailThreadView(key: key, mails: mails, router: router, close: close).id(key)
                            }
                        }
                    }
            }
        }
        .overlay {
            if let draft = mails.composing {
                FloatingPanel(close: { mails.closeComposer() }) { NewMailPanel(draftID: draft, mails: mails).id(draft) }
            }
        }
        .animation(Motion.standard, value: router.mailSelection)
        .animation(Motion.standard, value: mails.composing)
        .overlay(alignment: .bottom) { MailUndoBar(mails: mails) }
        // One Quick Look for the list's chips and the open thread's files (15/11): two would fight over the
        // window's single preview panel.
        .quickLookPreview($mails.preview)
        // ⌘N writes a new mail from Mails only; the button is at the top of « Mails », in the sidebar (15/11).
        .background {
            Button("Nouveau mail") { mails.writeNewMail(router: router) }
                .keyboardShortcut("n", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onAppear { mails.router = router }
        .confirmationDialog("Se désabonner de \(mails.unsubscribeRequest?.name ?? "") ?",
                            isPresented: Binding(get: { mails.unsubscribeRequest != nil }, set: { if !$0 { mails.unsubscribeRequest = nil } }),
                            presenting: mails.unsubscribeRequest) { request in
            Button("Se désabonner") { mails.unsubscribe(from: request.sender, by: request.method) }
        } message: { request in
            switch request.method {
            case .oneClick: Text("La demande part vers \(request.method.domain), le serveur de l'expéditeur. Les mails déjà reçus restent.")
            case .mail(let to, _): Text("Un mail de désinscription vers \(to) est préparé : tu l'envoies toi-même.")
            case .page: Text("La page de désinscription de \(request.method.domain) s'ouvre dans ton navigateur.")
            }
        }
        .sheet(isPresented: Binding(get: { mails.original != nil }, set: { if !$0 { mails.original = nil } })) {
            if let original = mails.original { MailOriginalSheet(title: original.title, text: original.text) { mails.original = nil } }
        }
    }
}

/// « Fil archivé · Annuler », for a few seconds; or what went wrong.
struct MailUndoBar: View {
    @ObservedObject var mails: MailLibrary

    var body: some View {
        Group {
            if let sending = mails.sending {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let left = max(0, Int(sending.at.timeIntervalSince(context.date).rounded(.up)))
                    HStack(spacing: Space.m) {
                        Image(systemName: "paperplane.fill").foregroundStyle(Color.accentColor)
                        Text(left > 0 ? "« \(sending.subject) » part dans \(left) s" : "Envoi de « \(sending.subject) »…").lineLimit(1)
                        if !sending.leaving {
                            Button("Annuler") { mails.cancelSend() }.buttonStyle(.glass).keyboardShortcut("z", modifiers: .command).disabled(left == 0)
                        }
                    }
                }
            } else if let undo = mails.undoable {
                HStack(spacing: Space.m) {
                    Text(undo.text)
                    Button("Annuler") { mails.undo() }.buttonStyle(.glass).keyboardShortcut("z", modifiers: .command)
                }
            } else if let message = mails.message {
                HStack(spacing: Space.m) {
                    Text(message).fixedSize(horizontal: false, vertical: true)
                    IconButton("xmark", help: "Fermer", size: 13) { mails.message = nil }
                }
            }
        }
        .font(.rowBody)
        .padding(.horizontal, Space.xl).padding(.vertical, Space.m)
        .glassEffect(.regular, in: Capsule())
        .padding(.bottom, Space.l)
        .opacity(mails.undoable == nil && mails.message == nil && mails.sending == nil ? 0 : 1)
        .animation(.snappy, value: mails.undoable?.text)
    }
}

enum MailText {
    static let locale = Locale(identifier: "fr_FR")

    /// « 14:02 » today, « 12 nov. » this year, « 12/11/25 » before.
    static func date(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(.dateTime.hour().minute().locale(locale)) }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) { return date.formatted(.dateTime.day().month(.abbreviated).locale(locale)) }
        return date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.twoDigits).locale(locale))
    }

    /// « 14 nov. 2026 à 14:02 (il y a 2 heures) ».
    static func longDate(_ date: Date, now: Date = Date()) -> String {
        let full = date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(locale))
        guard now.timeIntervalSince(date) < 7 * 86_400 else { return full }
        return "\(full) (\(date.formatted(.relative(presentation: .named).locale(locale))))"
    }

    /// « Camille, moi (3) »; one sender alone keeps the whole name (« La Lettre du design »), as in Gmail.
    static func senders(_ thread: MailThreadRow, mine: Set<String>) -> String {
        names(thread, mine: mine) + (thread.messageCount > 1 ? " (\(thread.messageCount))" : "")
    }

    /// « Camille, moi », without the count, which the list shows apart, lighter.
    static func names(_ thread: MailThreadRow, mine: Set<String>) -> String {
        people(thread.senders, mine: mine)
    }

    /// « Camille, Jules » after « À : » in « Envoyés » (15/11): who Paul wrote to, by the same rule.
    static func recipients(_ people: [MailAddress], mine: Set<String>) -> String {
        self.people(people, mine: mine)
    }

    /// One person keeps the whole name (« La Lettre du design »), several their first names, as in Gmail.
    private static func people(_ people: [MailAddress], mine: Set<String>) -> String {
        if people.count == 1, let only = people.first {
            return mine.contains(only.email) ? "moi" : only.display
        }
        return people.map { mine.contains($0.email) ? "moi" : ($0.name?.components(separatedBy: " ").first ?? $0.email) }.joined(separator: ", ")
    }

    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// The same color for a sender everywhere.
    static func tint(for email: String) -> Color {
        let colors = [Palette.violet, Palette.green, Palette.orange, Palette.blue, Palette.pink, Palette.teal, Palette.red, Palette.brown]
        let sum = email.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Color(hex: colors[sum % colors.count])
    }

    /// The list cut by day: « Aujourd'hui », « Hier », « Cette semaine », « Ce mois-ci », then the months.
    static func sections(_ threads: [MailThreadRow], now: Date = Date(), calendar: Calendar = .current) -> [(title: String, threads: [MailThreadRow])] {
        var result: [(title: String, threads: [MailThreadRow])] = []
        let today = calendar.startOfDay(for: now)
        for thread in threads {
            let day = calendar.startOfDay(for: thread.lastMessageAt)
            let days = calendar.dateComponents([.day], from: day, to: today).day ?? 0
            let title: String
            if days <= 0 {
                title = "Aujourd'hui"
            } else if days == 1 {
                title = "Hier"
            } else if days < 7 {
                title = "Cette semaine"
            } else if calendar.isDate(day, equalTo: today, toGranularity: .month) {
                title = "Ce mois-ci"
            } else {
                let sameYear = calendar.isDate(day, equalTo: today, toGranularity: .year)
                let month = thread.lastMessageAt.formatted(sameYear ? .dateTime.month(.wide).locale(locale) : .dateTime.month(.wide).year().locale(locale))
                title = month.prefix(1).uppercased() + month.dropFirst()
            }
            if result.last?.title == title { result[result.count - 1].threads.append(thread) } else { result.append((title, [thread])) }
        }
        return result
    }
}

/// « Ranger dans » (step « Ranger »): the projects under way, the others apart; Perso; the automatic cases;
/// « Aucune case ». Kept for the thread and for its sender's next mails. On the ticked threads (15/11), one case
/// for all, then the ticks go.
struct MailFilingMenu: View {
    let threads: [MailThreadRow]
    @ObservedObject var mails: MailLibrary
    /// The ticked threads, not one thread.
    let selection: Bool

    init(thread: MailThreadRow, mails: MailLibrary) {
        threads = [thread]
        self.mails = mails
        selection = false
    }

    init(selection threads: [MailThreadRow], mails: MailLibrary) {
        self.threads = threads
        self.mails = mails
        selection = true
    }

    /// The case every thread shares, ticked in the menu; none when they differ.
    static func shared(_ cases: [MailFiling?]) -> MailFiling? {
        guard let first = cases.first, cases.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    var body: some View {
        let current = Self.shared(threads.map { mails.filing(of: $0)?.filing })
        let projects = mails.filingProjects
        ForEach(projects.current) { project in item(project.name, .project(project.id), current) }
        if !projects.others.isEmpty {
            Menu("Autres projets") {
                ForEach(projects.others) { project in item(project.name, .project(project.id), current) }
            }
        }
        Divider()
        item("Perso", .perso, current)
        Divider()
        ForEach([MailFiling.newsletters, .payments, .services], id: \.self) { filing in item(filing.title ?? "", filing, current) }
        Divider()
        item("Aucune case", .none, current)
    }

    @ViewBuilder
    private func item(_ title: String, _ filing: MailFiling, _ current: MailFiling?) -> some View {
        Button {
            if selection { mails.fileSelection(as: filing) } else if let thread = threads.first { mails.file(thread, as: filing) }
        } label: {
            if current == filing { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }
}

/// A thread's case, small, next to its subject; a click changes it (step « Ranger »). The cases its tab
/// already says (Newsletters, Services) show only when `always`, which also offers « Ranger » to a thread
/// without one.
struct MailFilingChip: View {
    let thread: MailThreadRow
    @ObservedObject var mails: MailLibrary
    var always = false

    var body: some View {
        let found = mails.filing(of: thread)
        if let label = label(found?.filing) {
            Menu { MailFilingMenu(thread: thread, mails: mails) } label: {
                Text(label.text).font(.tag.weight(.medium)).lineLimit(1)
                    .padding(.horizontal, Space.s).padding(.vertical, 3)
                    .foregroundStyle(label.color)
                    .background(label.color.opacity(0.14), in: Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(found.map { "\($0.origin.explanation) · cliquer pour changer" } ?? "Ranger ce fil dans un projet ou une case")
        }
    }

    private func label(_ filing: MailFiling?) -> (text: String, color: Color)? {
        switch filing {
        case .project(let id)?:
            let project = mails.project(id)
            return (project?.name ?? "Projet", project.map(ProjectViews.tint) ?? .accentColor)
        case .perso?: return ("Perso", .pink)
        case .payments?: return ("Paiements", .green)
        case .services? where always: return ("Services", .secondary)
        case .newsletters? where always: return ("Newsletters", .secondary)
        default: return always ? ("Ranger", .secondary) : nil
        }
    }
}

/// What an open thread shows: its messages as the copy holds them, their bodies, which are unfolded.
@MainActor
final class MailThreadModel: ObservableObject {
    @Published var messages: [MailMessageRow] = []
    @Published var bodies: [String: String] = [:]
    @Published var expanded: Set<String> = []
    /// The messages whose remote images Paul asked to see.
    @Published var allowed: Set<String> = []
    /// The messages shown on their own light background, in dark mode.
    @Published var light: Set<String> = []
    /// The folded messages in the middle of a long thread are shown.
    @Published var showAll = false
    @Published var failed: [String: String] = [:]

    let key: String
    let library: MailLibrary
    private var observation: AnyDatabaseCancellable?
    private var opened = false

    init(key: String, library: MailLibrary) {
        self.key = key
        self.library = library
        observation = library.store.observeMessages(threadKey: key) { [weak self] rows in self?.update(rows) }
    }

    private func update(_ rows: [MailMessageRow]) {
        // A reply that arrives while the thread is open unfolds itself.
        let known = Set(messages.map(\.id))
        messages = rows
        if !opened, !rows.isEmpty {
            opened = true
            expanded = Set(rows.filter(\.isUnread).map(\.id)).union(rows.suffix(1).map(\.id))
        } else {
            expanded.formUnion(rows.filter { !known.contains($0.id) }.map(\.id))
        }
        for message in rows where expanded.contains(message.id) { load(message) }
    }

    /// The first message, a « N messages » line for a long middle, the last two; unread ones always show.
    var items: [MailThreadItem] {
        guard !showAll, messages.count >= 5 else { return messages.map { .message($0) } }
        let middle = messages[1..<(messages.count - 2)]
        let hidden = middle.filter { !expanded.contains($0.id) && !$0.isUnread }
        guard hidden.count >= 2 else { return messages.map { .message($0) } }
        var result: [MailThreadItem] = [.message(messages[0])]
        var inserted = false
        for message in middle {
            if hidden.contains(where: { $0.id == message.id }) {
                if !inserted { result.append(.more(hidden.count)); inserted = true }
            } else {
                result.append(.message(message))
            }
        }
        return result + messages.suffix(2).map { .message($0) }
    }

    func toggle(_ message: MailMessageRow) {
        if expanded.contains(message.id) { expanded.remove(message.id) } else {
            expanded.insert(message.id)
            load(message)
        }
    }

    private func load(_ message: MailMessageRow) {
        guard bodies[message.id] == nil else { return }
        Task {
            do { bodies[message.id] = try await library.engine.body(of: message) } catch { failed[message.id] = "\(error)" }
        }
    }

    /// An image the mail carries, by its content id.
    func inline(_ contentID: String, of message: MailMessageRow) async -> (Data, String)? {
        guard let attachment = message.attachments.first(where: { $0.contentID?.caseInsensitiveCompare(contentID) == .orderedSame }),
              let url = try? await library.engine.file(attachment, of: message), let data = try? Data(contentsOf: url) else { return nil }
        return (data, attachment.mimeType)
    }

    /// A click on a file: an image, a PDF or a document opens in Quick Look; anything else is only saved. The
    /// library does it, as for the chips of the list: one Quick Look for the whole section (15/11).
    func open(_ attachment: MailAttachment, of message: MailMessageRow) {
        library.open(attachment, of: message)
    }

    func save(_ attachment: MailAttachment, of message: MailMessageRow) {
        library.save(attachment, of: message)
    }

    /// Every file of a message, in one folder Paul chooses.
    func saveAll(of message: MailMessageRow) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Enregistrer ici"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        Task {
            for file in message.files {
                do {
                    let url = try await library.engine.file(file, of: message)
                    let target = folder.appending(path: url.lastPathComponent)
                    try? FileManager.default.removeItem(at: target)
                    try FileManager.default.copyItem(at: url, to: target)
                } catch {
                    library.message = "Pièce jointe indisponible : \(error)"
                }
            }
        }
    }
}

enum MailThreadItem: Identifiable {
    case message(MailMessageRow)
    case more(Int)

    var id: String {
        switch self {
        case .message(let message): message.id
        case .more: "plus"
        }
    }
}

/// An open thread: its subject and mailbox, the way to the previous and next threads, the gestures, then its
/// messages (the read ones folded). In a floating panel it closes itself; in a page, the toolbar leads back.
struct MailThreadView: View {
    let key: String
    @ObservedObject var mails: MailLibrary
    @ObservedObject var router: WindowRouter
    let close: (() -> Void)?
    @StateObject private var model: MailThreadModel
    @State private var thread: MailThreadRow?
    /// The draft just begun: the page scrolls to it.
    @State private var replying: String?
    /// A reply below has the keyboard.
    @FocusedValue(\.writingMail) private var writing

    init(key: String, mails: MailLibrary, router: WindowRouter, close: (() -> Void)?) {
        self.key = key
        self.mails = mails
        self.router = router
        self.close = close
        _model = StateObject(wrappedValue: MailThreadModel(key: key, library: mails))
    }

    private func back() {
        if let close { close() } else { router.mailSelection = nil }
    }

    /// The last message of the thread, the one a reply answers.
    private var last: MailMessageRow? { model.messages.last }

    private func reply(_ mode: MailDraftRow.Mode, to message: MailMessageRow? = nil) {
        guard let thread, let message = message ?? last else { return }
        Task {
            if let id = await mails.startReply(mode, to: message, in: thread) { replying = id }
        }
    }

    private func go(_ offset: Int) {
        guard let next = mails.neighbor(of: key, offset: offset) else { return }
        mails.focused = next
        router.mailSelection = next
    }

    /// Archived or deleted: what Réglages › Mails says, as Gmail's « Avance automatique » — the next thread by
    /// default, as Apple Mail; back to the list after the last one.
    private func gesture(_ kind: MailGestureKind) {
        guard let thread else { return }
        let next: String?
        switch Preferences().mailAfterGesture {
        case .suivant: next = mails.neighbor(of: key, offset: 1) ?? mails.neighbor(of: key, offset: -1)
        case .precedent: next = mails.neighbor(of: key, offset: -1) ?? mails.neighbor(of: key, offset: 1)
        case .liste: next = nil
        }
        mails.perform(kind, on: thread)
        if kind == .markUnread || next == nil { back() } else {
            mails.focused = next
            router.mailSelection = next
        }
    }

    var body: some View {
        let mine = Set(mails.agenda.accounts.map(\.email))
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.items) { item in
                        switch item {
                        case .message(let message):
                            MailMessageView(message: message, thread: thread, model: model, mails: mails, mine: mine,
                                            collapseQuote: message.id != model.messages.first?.id, reply: { mode in reply(mode, to: message) })
                        case .more(let count):
                            Button { model.showAll = true } label: {
                                Text("\(count) messages plus anciens").font(.meta.weight(.medium))
                                    .padding(.horizontal, Space.m).padding(.vertical, 5)
                                    .background(Surface.raised, in: Capsule())
                            }
                            .buttonStyle(.hover(.capsule))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Space.s)
                        }
                        Divider()
                    }
                    ForEach(mails.drafts.filter { $0.threadKey == key }) { draft in
                        ComposeView(draftID: draft.id, mails: mails)
                            .padding(.top, Space.l)
                            .id(draft.id)
                    }
                    if thread != nil, last != nil {
                        HStack(spacing: Space.s) {
                            Button { reply(.reply) } label: { Label("Répondre", systemImage: "arrowshape.turn.up.left") }
                                .keyboardShortcut("r", modifiers: .command)
                                .help("Répondre (⌘R)")
                            Button { reply(.replyAll) } label: { Label("Répondre à tous", systemImage: "arrowshape.turn.up.left.2") }
                                .keyboardShortcut("r", modifiers: [.command, .shift])
                                .help("Répondre à tous (⇧⌘R)")
                            Button { reply(.forward) } label: { Label("Transférer", systemImage: "arrowshape.turn.up.right") }
                                .help("Transférer")
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .padding(.top, Space.xl)
                    }
                }
                .padding(.horizontal, PageMetrics.horizontal)
                .padding(.bottom, PageMetrics.bottom + 40)
                .frame(maxWidth: PageMetrics.readingWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: replying) { _, id in
                guard let id else { return }
                withAnimation { scroll.scrollTo(id, anchor: .top) }
            }
            }
        }
        .toolbar {
            if close == nil {
                ToolbarItem(placement: .navigation) {
                    Button(action: back) { Label("Mails", systemImage: "chevron.left") }.help("Revenir à la liste (Échap)")
                }
            }
        }
        .onExitCommand(perform: back)
        .onDeleteCommand { gesture(.trash) }
        .windowTitle("Mails", subtitle: close == nil ? (thread?.subject ?? "") : mails.tab.title)
        .task(id: key) {
            thread = try? mails.store.thread(key)
            if let thread { mails.markRead(thread) }
        }
        .onChange(of: mails.inbox) { _, _ in thread = (try? mails.store.thread(key)) ?? thread }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Space.m) {
            if let close { PanelCloseButton(action: close) }
            VStack(alignment: .leading, spacing: 4) {
                Text(thread?.subject ?? model.messages.first?.subject ?? "")
                    .font(.title.bold()).lineLimit(2).textSelection(.enabled)
                if let thread {
                    HStack(spacing: 6) {
                        ColorDot(mails.color(for: thread.account), size: 8)
                        Text(AccountStyle.label(for: thread.account))
                        Text("·")
                        Text(model.messages.count > 1 ? "\(model.messages.count) messages" : "1 message")
                        Text("·")
                        MailFilingChip(thread: thread, mails: mails, always: true)
                    }
                    .font(.rowBody).foregroundStyle(.secondary)
                    // Its people, and who of them is in its project (15/11).
                    ThreadPeopleRow(thread: thread, messages: model.messages, mails: mails, router: router)
                        .padding(.top, Space.xs)
                }
            }
            Spacer(minLength: Space.m)
            HStack(spacing: Space.xs) {
                if let position = mails.position(of: key) { Text(position).font(.meta).foregroundStyle(.secondary).monospacedDigit() }
                IconButton("chevron.up", help: "Fil précédent (↑)") { go(-1) }
                    .disabled(mails.neighbor(of: key, offset: -1) == nil)
                    // While a reply is written, the arrows stay in it (15/11).
                    .keyboardShortcut(writing == true ? nil : KeyboardShortcut(.upArrow, modifiers: []))
                IconButton("chevron.down", help: "Fil suivant (↓)") { go(1) }
                    .disabled(mails.neighbor(of: key, offset: 1) == nil)
                    .keyboardShortcut(writing == true ? nil : KeyboardShortcut(.downArrow, modifiers: []))
                Divider().frame(height: 18)
                IconButton("archivebox", help: "Archiver") { gesture(.archive) }
                IconButton("trash", help: "Supprimer") { gesture(.trash) }
                IconButton("envelope.badge", help: "Marquer comme non lu") { gesture(.markUnread) }
                IconMenu("ellipsis", help: "Plus") {
                    if let thread {
                        Button("Répondre") { reply(.reply) }
                        Button("Répondre à tous") { reply(.replyAll) }
                        Button("Transférer") { reply(.forward) }
                        Divider()
                        Menu("Ranger dans") { MailFilingMenu(thread: thread, mails: mails) }
                        if let message = model.messages.last(where: { $0.listUnsubscribe != nil }), let sender = message.sender,
                           let method = mails.unsubscribeMethod(listUnsubscribe: message.listUnsubscribe, post: message.listUnsubscribePost,
                                                                authenticated: message.authenticated) {
                            Button("Se désabonner de \(sender.display)…") { mails.askUnsubscribe(sender: sender, method: method) }
                        }
                        Button("Signaler comme spam") {
                            mails.reportSpam(thread)
                            back()
                        }
                        Divider()
                        Button("Ouvrir dans Gmail") { NSWorkspace.shared.open(mails.gmailURL(thread)) }
                    }
                }
            }
            .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
            .glassEffect(.regular, in: Capsule())
        }
        .padding(.horizontal, Space.xl).padding(.vertical, Space.l)
    }
}

/// One message of a thread: a line when folded; unfolded, who and when, the body on the app's background, and
/// the files.
struct MailMessageView: View {
    let message: MailMessageRow
    let thread: MailThreadRow?
    @ObservedObject var model: MailThreadModel
    @ObservedObject var mails: MailLibrary
    let mine: Set<String>
    let collapseQuote: Bool
    /// Reply, reply to all, forward: to this message.
    var reply: (MailDraftRow.Mode) -> Void = { _ in }
    @Environment(\.colorScheme) private var scheme
    @State private var height: CGFloat = 60
    @State private var details = false
    /// The script found a mail made of images: on a light card, even in dark mode.
    @State private var imagesMail = false
    /// The pointer is on the header: « + » shows by the sender (15/11).
    @State private var hoveringHeader = false

    private var isMine: Bool { message.sender.map { mine.contains($0.email) } ?? false }
    /// A contact's name as Paul spelled it, else the mail's.
    private var sender: String {
        if isMine { return "Moi" }
        if let email = message.sender?.email, let name = mails.agenda.contact(email: email)?.name, !name.isEmpty, name.lowercased() != email { return name }
        return message.sender?.display ?? "Expéditeur inconnu"
    }
    /// The thread's project: who is in it shows.
    private var projectID: UUID? { thread.flatMap { mails.filing(of: $0)?.filing.projectID } }
    private var initial: String { String(sender.prefix(1)).uppercased() }
    private var tint: Color { MailText.tint(for: message.sender?.email ?? "") }

    var body: some View {
        if model.expanded.contains(message.id) {
            VStack(alignment: .leading, spacing: Space.l) {
                header
                content.padding(.leading, 40 + Space.m)
            }
            .padding(.vertical, Space.xl)
        } else {
            Button { model.toggle(message) } label: {
                HStack(spacing: Space.m) {
                    Avatar(initial, size: 36, tint: tint)
                    Text(sender).font(.rowTitle.weight(message.isUnread ? .semibold : .medium)).foregroundStyle(.primary).lineLimit(1)
                        .frame(width: 190, alignment: .leading)
                    Text(message.snippet).font(.rowBody).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    if !message.files.isEmpty { Image(systemName: "paperclip").font(.meta).foregroundStyle(.secondary) }
                    Text(MailText.date(message.date)).font(.meta).foregroundStyle(.secondary)
                }
                .padding(.vertical, Space.m)
                .contentShape(Rectangle())
            }
            .buttonStyle(.row(inset: Space.s))
            .padding(.vertical, Space.xs)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.m) {
            MessagePersonAvatar(person: isMine ? nil : message.sender, initials: initial, tint: tint, project: projectID, agenda: mails.agenda)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(sender).font(.rowTitle.weight(.semibold))
                    if let email = message.sender?.email, !isMine { Text(email).font(.meta).foregroundStyle(.secondary).textSelection(.enabled) }
                    if let person = message.sender, !isMine {
                        MessageAddButton(person: person, project: projectID, mails: mails, visible: hoveringHeader)
                    }
                }
                Button { details.toggle() } label: {
                    HStack(spacing: 3) {
                        let people = (message.to + message.cc).map { mine.contains($0.email) ? "moi" : ($0.name ?? $0.email) }
                        Text(people.isEmpty ? "détails" : "à \(people.joined(separator: ", "))").lineLimit(1)
                        Image(systemName: details ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, Space.s).padding(.vertical, 2)
                }
                .buttonStyle(.hover(.capsule))
                .font(.meta).foregroundStyle(.secondary)
                .padding(.horizontal, -Space.s)
                if details { detailGrid }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.toggle(message) }
            Spacer(minLength: Space.m)
            Text(MailText.longDate(message.date)).font(.meta).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                IconButton("arrowshape.turn.up.left", help: "Répondre à ce message") { reply(.reply) }
                IconMenu("ellipsis", help: "Plus") {
                    Button("Répondre") { reply(.reply) }
                    Button("Répondre à tous") { reply(.replyAll) }
                    Button("Transférer") { reply(.forward) }
                    Divider()
                    if let thread { Button("Ouvrir dans Gmail") { NSWorkspace.shared.open(mails.gmailURL(thread)) } }
                    Button("Afficher l'original") { mails.showOriginal(message) }
                    if let email = message.sender?.email {
                        Button("Copier l'adresse de l'expéditeur") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(email, forType: .string)
                        }
                    }
                    if scheme == .dark, message.bodyIsHTML, !imagesMail {
                        Button(model.light.contains(message.id) ? "Adapter au mode sombre" : "Afficher sur fond clair") {
                            if model.light.contains(message.id) { model.light.remove(message.id) } else { model.light.insert(message.id) }
                        }
                    }
                }
            }
            .padding(.top, -6)
        }
        .onHover { hoveringHeader = $0 }
    }

    private var detailRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let from = message.sender { rows.append(("De", from.name.map { "\($0) <\(from.email)>" } ?? from.email)) }
        if !message.to.isEmpty { rows.append(("À", message.to.map(\.email).joined(separator: ", "))) }
        if !message.cc.isEmpty { rows.append(("Cc", message.cc.map(\.email).joined(separator: ", "))) }
        rows.append(("Date", message.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute().locale(MailText.locale))))
        rows.append(("Boîte", message.account))
        rows.append(("Expéditeur", message.authenticated ? "vérifié par Gmail" : "non vérifié par Gmail"))
        return rows
    }

    private var detailGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: Space.m, verticalSpacing: 4) {
            ForEach(detailRows, id: \.0) { title, value in
                GridRow {
                    Text(title).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    // Who is a contact, and a click for the small menu of each (15/11).
                    if title == "À" || title == "Cc" {
                        MessagePeople(people: title == "À" ? message.to : message.cc, mine: mine, project: projectID, mails: mails)
                    } else {
                        Text(value).textSelection(.enabled)
                    }
                }
            }
        }
        .font(.meta)
        .padding(Space.m)
        .background(Surface.fill, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        if let body = model.bodies[message.id] {
            let known = thread.map { mails.showsImages(of: message, in: $0) } ?? false
            let images = known || model.allowed.contains(message.id)
            let onLight = scheme == .dark && (model.light.contains(message.id) || imagesMail)
            VStack(alignment: .leading, spacing: Space.m) {
                if !images, message.bodyIsHTML, MailHTML.hasRemoteImages(body) {
                    HStack(spacing: Space.s) {
                        Image(systemName: "photo").foregroundStyle(.secondary)
                        Text("Images masquées : leur expéditeur verrait que tu as ouvert le mail.").font(.meta).foregroundStyle(.secondary)
                        Spacer()
                        Button("Afficher") { model.allowed.insert(message.id) }
                        if message.authenticated, let email = message.sender?.email {
                            Button("Toujours pour cet expéditeur") {
                                model.allowed.insert(message.id)
                                mails.alwaysShowImages(from: email)
                            }
                        }
                    }
                    .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                    .background(Surface.fill, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                }
                MailBodyView(document: MailHTML.document(body: body, isHTML: message.bodyIsHTML, images: images, collapseQuote: collapseQuote,
                                                         dark: scheme == .dark && !onLight),
                             images: images, dark: scheme == .dark && !onLight, prefersLight: $imagesMail,
                             inline: { id in await model.inline(id, of: message) },
                             onLink: { NSWorkspace.shared.open($0) }, height: $height)
                    .frame(height: height)
                    .padding(onLight ? Space.m : 0)
                    .background(onLight ? Color.white : .clear, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                if !message.files.isEmpty { files }
            }
        } else if let failure = model.failed[message.id] {
            Label("Ce message n'a pas pu être lu : \(failure)", systemImage: "exclamationmark.triangle").font(.rowBody).foregroundStyle(.orange)
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private var files: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(message.files.count > 1 ? "\(message.files.count) pièces jointes" : "1 pièce jointe").font(.meta.weight(.semibold)).foregroundStyle(.secondary)
                if message.files.count > 1 {
                    TextButton("Tout enregistrer…") { model.saveAll(of: message) }.padding(.leading, Space.s)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 280), spacing: Space.s)], alignment: .leading, spacing: Space.s) {
                ForEach(message.files, id: \.partID) { file in AttachmentTile(file: file) { model.open(file, of: message) } save: { model.save(file, of: message) } }
            }
        }
    }
}

/// A file of a message: its icon, its name, its size. A click opens it (or saves what Polhub never opens).
struct AttachmentTile: View {
    let file: MailAttachment
    let open: () -> Void
    let save: () -> Void
    @State private var hovering = false

    var body: some View {
        let type = UTType(filenameExtension: (file.filename as NSString).pathExtension) ?? .data
        Button(action: open) {
            HStack(spacing: Space.s) {
                Image(nsImage: NSWorkspace.shared.icon(for: type)).resizable().frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.filename).font(.rowBody).foregroundStyle(.primary).lineLimit(1).truncationMode(.middle)
                    Text(MailText.size(file.size)).font(.meta).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                // Room for « Enregistrer… », laid over the tile: nothing moves when it shows.
                Color.clear.frame(width: 32, height: 1)
            }
            .padding(Space.m)
            .background(Surface.fill, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
        .buttonStyle(.row)
        .overlay(alignment: .trailing) {
            IconButton("arrow.down.circle", help: "Enregistrer…") { save() }
                .padding(.trailing, Space.s)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
        }
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .contextMenu { Button("Enregistrer…", action: save) }
        .help(AttachmentSafety.canOpen(name: file.filename) ? "Aperçu" : "Ce type de fichier ne s'ouvre pas dans Polhub : il s'enregistre.")
    }
}

/// « Afficher l'original »: the message as it travelled, headers first.
struct MailOriginalSheet: View {
    let title: String
    let text: String
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text("Original · \(title)").font(.headline).lineLimit(1)
                Spacer()
                Button("Copier") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Button("Fermer", action: close).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                Text(text).font(.system(size: TextSize.tag, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Space.l)
        .frame(minWidth: 720, minHeight: 520)
    }
}

/// « Abonnements » (14/11): the senders Paul could leave, the busiest first; leave one, or archive all it sent.
struct MailSubscriptionsView: View {
    @ObservedObject var mails: MailLibrary

    var body: some View {
        if mails.subscriptions.isEmpty {
            ContentUnavailableView("Aucun abonnement", systemImage: "newspaper",
                                   description: Text("Les expéditeurs dont tu peux te désabonner apparaissent ici, les plus bavards d'abord."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    Text("Les 90 derniers jours, des plus bavards aux plus discrets.")
                        .font(.rowBody).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.xl).padding(.top, Space.l).padding(.bottom, Space.m)
                    ForEach(mails.subscriptions) { subscription in
                        row(subscription)
                        Divider().padding(.leading, Space.xl + 40 + Space.m)
                    }
                }
            }
        }
    }

    private func row(_ subscription: MailSubscription) -> some View {
        let method = mails.unsubscribeMethod(subscription)
        let left = mails.unsubscribed[subscription.sender.email]
        return HStack(spacing: Space.m) {
            Avatar(String(subscription.sender.display.prefix(1)).uppercased(), size: 40, tint: MailText.tint(for: subscription.sender.email))
                .padding(.leading, Space.xl)
            VStack(alignment: .leading, spacing: 4) {
                Text(subscription.sender.display).font(.rowTitle.weight(.medium)).lineLimit(1)
                Text(subscription.sender.email).font(.meta).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 300, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(subscription.count) mail\(subscription.count > 1 ? "s" : "")" + (subscription.unread > 0 ? " · \(subscription.unread) non lu\(subscription.unread > 1 ? "s" : "")" : ""))
                    .font(.rowBody)
                Text("Dernier : \(MailText.date(subscription.lastAt))").font(.meta).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !subscription.inboxThreads.isEmpty {
                Button("Tout archiver (\(subscription.inboxThreads.count))") { mails.archiveAll(subscription) }
                    .buttonStyle(.glass)
                    .help("Archiver ses mails encore en boîte de réception")
            }
            if let left {
                Label("Désabonné le \(left.formatted(.dateTime.day().month(.abbreviated).locale(MailText.locale)))", systemImage: "checkmark.circle")
                    .font(.meta).foregroundStyle(.secondary)
            } else if let method {
                Button("Se désabonner") { mails.askUnsubscribe(sender: subscription.sender, method: method) }
                    .buttonStyle(.glass)
                    .help({
                        switch method {
                        case .oneClick: "En un clic, auprès de \(method.domain)"
                        case .mail: "Par un mail que tu enverras toi-même"
                        case .page: "Sur la page de \(method.domain)"
                        }
                    }())
            }
        }
        .padding(.trailing, Space.xl)
        .padding(.vertical, Space.l)
    }
}
