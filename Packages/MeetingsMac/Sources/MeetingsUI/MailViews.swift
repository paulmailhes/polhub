import Agenda
import AppKit
import GRDB
import Mail
import Persistence
import PolhubDesign
import QuickLook
import SwiftUI

/// The section « Mails » (Paul, 14/11): the list takes the whole width; a click opens the thread in its place.
struct MailSectionView: View {
    @ObservedObject var mails: MailLibrary
    @ObservedObject var router: WindowRouter

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
            } else if let key = router.mailSelection {
                MailThreadView(key: key, mails: mails, router: router).id(key)
            } else {
                MailListView(mails: mails, router: router)
            }
        }
        .overlay(alignment: .bottom) { MailUndoBar(mails: mails) }
    }
}

/// « Fil archivé · Annuler », for a few seconds; or what went wrong.
struct MailUndoBar: View {
    @ObservedObject var mails: MailLibrary

    var body: some View {
        if let undo = mails.undoable {
            HStack(spacing: Space.m) {
                Text(undo.text)
                Button("Annuler") { mails.undo() }.buttonStyle(.glass).keyboardShortcut("z", modifiers: .command)
            }
            .padding(.horizontal, Space.l).padding(.vertical, Space.s)
            .glassEffect(.regular, in: Capsule())
            .padding(.bottom, Space.l)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let message = mails.message {
            HStack(spacing: Space.m) {
                Text(message).fixedSize(horizontal: false, vertical: true)
                Button { mails.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
            .padding(.horizontal, Space.l).padding(.vertical, Space.s)
            .glassEffect(.regular, in: Capsule())
            .padding(.bottom, Space.l)
        }
    }
}

enum MailText {
    /// « 14:02 » today, « 12 nov. » this year, « 12/11/25 » before.
    static func date(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let locale = Locale(identifier: "fr_FR")
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(.dateTime.hour().minute().locale(locale)) }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) { return date.formatted(.dateTime.day().month(.abbreviated).locale(locale)) }
        return date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.twoDigits).locale(locale))
    }

    /// « Camille, moi (3) ».
    static func senders(_ thread: MailThreadRow, mine: Set<String>) -> String {
        let names = thread.senders.map { mine.contains($0.email) ? "moi" : ($0.name?.components(separatedBy: " ").first ?? $0.email) }
        return names.joined(separator: ", ") + (thread.messageCount > 1 ? " (\(thread.messageCount))" : "")
    }

    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// The list: one line per thread, the three mailboxes together, the two tabs, the search.
struct MailListView: View {
    @ObservedObject var mails: MailLibrary
    @ObservedObject var router: WindowRouter
    @State private var query = ""

    var body: some View {
        let threads = mails.shown
        let mine = Set(mails.agenda.accounts.map(\.email))
        VStack(spacing: 0) {
            if let failure = mails.failure {
                HStack(spacing: Space.s) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text("\(AccountStyle.label(for: failure.account)) : \(failure.text)").font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Comptes Google") { router.openSettings(.accounts) }
                }
                .padding(.horizontal, Space.l).padding(.vertical, Space.s)
                Divider()
            }
            if threads.isEmpty {
                ContentUnavailableView(mails.found != nil ? "Aucun mail trouvé" : (mails.progress != nil ? "Lecture de tes boîtes…" : "Rien ici"),
                                       systemImage: mails.found != nil ? "magnifyingglass" : "tray")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(threads) { thread in
                            MailRow(thread: thread, mails: mails, mine: mine) { router.mailSelection = thread.id }
                            Divider().padding(.leading, Space.l + 20)
                        }
                    }
                }
            }
            if let progress = mails.progress {
                Divider()
                Text(progress).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.l).padding(.vertical, 6)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Onglet", selection: $mails.tab) {
                    ForEach(MailTab.allCases, id: \.self) { tab in
                        let unread = mails.unread(in: tab)
                        Text(unread > 0 ? "\(tab.title) · \(unread)" : tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(mails.found != nil)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                ForEach(mails.accounts) { account in
                    let shown = !mails.hidden.contains(account.email)
                    Button {
                        if shown { mails.hidden.insert(account.email) } else { mails.hidden.remove(account.email) }
                    } label: {
                        Label(AccountStyle.label(for: account.email), systemImage: shown ? "circle.fill" : "circle")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(shown ? mails.color(for: account.email) : .secondary)
                    }
                    .help(shown ? "Masquer la boîte \(account.email)" : "Afficher la boîte \(account.email)")
                }
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Chercher dans Gmail")
        .onSubmit(of: .search) { Task { await mails.search(query) } }
        .onChange(of: query) { _, text in if text.isEmpty { mails.endSearch() } }
        .windowTitle("Mails", subtitle: mails.searching ? "Recherche…" : (mails.found != nil ? "Résultats de la recherche" : mails.tab.title))
    }
}

/// One thread in the list: the mailbox's dot, who, the subject and an extract, the date; the gestures on hover.
struct MailRow: View {
    let thread: MailThreadRow
    @ObservedObject var mails: MailLibrary
    let mine: Set<String>
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Space.m) {
            ColorDot(mails.color(for: thread.account), size: 8)
            Text(MailText.senders(thread, mine: mine))
                .fontWeight(thread.unread ? .semibold : .regular)
                .lineLimit(1)
                .frame(width: 190, alignment: .leading)
            (Text(thread.subject).fontWeight(thread.unread ? .semibold : .regular)
                + Text(thread.snippet.isEmpty ? "" : "  \(thread.snippet)").foregroundStyle(.secondary))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if thread.hasAttachment { Image(systemName: "paperclip").font(.caption).foregroundStyle(.secondary) }
            if hovering {
                HStack(spacing: Space.xs) {
                    Button { mails.perform(.archive, on: thread) } label: { Image(systemName: "archivebox") }.help("Archiver")
                    Button { mails.perform(.trash, on: thread) } label: { Image(systemName: "trash") }.help("Supprimer")
                    Button { mails.perform(thread.unread ? .markRead : .markUnread, on: thread, undoable: false) } label: {
                        Image(systemName: thread.unread ? "envelope.open" : "envelope.badge")
                    }
                    .help(thread.unread ? "Marquer comme lu" : "Marquer comme non lu")
                }
                .buttonStyle(.borderless)
                .frame(width: 84, alignment: .trailing)
            } else {
                Text(MailText.date(thread.lastMessageAt))
                    .font(.callout).fontWeight(thread.unread ? .semibold : .regular)
                    .foregroundStyle(thread.unread ? .primary : .secondary)
                    .frame(width: 84, alignment: .trailing)
            }
        }
        .font(.callout)
        .padding(.horizontal, Space.l)
        .frame(height: 38)
        .background(hovering ? Surface.fill : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Archiver") { mails.perform(.archive, on: thread) }
            Button("Supprimer") { mails.perform(.trash, on: thread) }
            Button(thread.unread ? "Marquer comme lu" : "Marquer comme non lu") { mails.perform(thread.unread ? .markRead : .markUnread, on: thread, undoable: false) }
            Divider()
            MailTabChoice(thread: thread, mails: mails)
            Button("Ouvrir dans Gmail") { NSWorkspace.shared.open(mails.gmailURL(thread)) }
        }
    }
}

/// « Déplacer vers Principale », kept for the sender; or back to Gmail's own filing.
struct MailTabChoice: View {
    let thread: MailThreadRow
    @ObservedObject var mails: MailLibrary

    var body: some View {
        if mails.isAutomatic(thread) {
            Button("Déplacer vers Principale") { mails.setPrincipal(true, for: thread) }
        } else if let sender = thread.lastSender, mails.senders[sender]?.principal == true {
            Button("Laisser Gmail classer cet expéditeur") { mails.setPrincipal(false, for: thread) }
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
    @Published var failed: [String: String] = [:]
    @Published var preview: URL?

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

    /// A click on a file: an image, a PDF or a document opens in Quick Look; anything else is only saved.
    func open(_ attachment: MailAttachment, of message: MailMessageRow) {
        Task {
            do {
                let url = try await library.engine.file(attachment, of: message)
                if AttachmentSafety.canOpen(name: attachment.filename) { preview = url } else { save(url) }
            } catch {
                library.message = "Pièce jointe indisponible : \(error)"
            }
        }
    }

    func save(_ attachment: MailAttachment, of message: MailMessageRow) {
        Task {
            do { save(try await library.engine.file(attachment, of: message)) } catch { library.message = "Pièce jointe indisponible : \(error)" }
        }
    }

    private func save(_ url: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        guard panel.runModal() == .OK, let target = panel.url else { return }
        try? FileManager.default.removeItem(at: target)
        do { try FileManager.default.copyItem(at: url, to: target) } catch { library.message = "Enregistrement impossible : \(error.localizedDescription)" }
    }
}

/// An open thread, in the list's place: its subject, its messages (the read ones folded), and the gestures.
struct MailThreadView: View {
    let key: String
    @ObservedObject var mails: MailLibrary
    @ObservedObject var router: WindowRouter
    @StateObject private var model: MailThreadModel
    @State private var thread: MailThreadRow?

    init(key: String, mails: MailLibrary, router: WindowRouter) {
        self.key = key
        self.mails = mails
        self.router = router
        _model = StateObject(wrappedValue: MailThreadModel(key: key, library: mails))
    }

    private func back() { router.mailSelection = nil }

    var body: some View {
        let mine = Set(mails.agenda.accounts.map(\.email))
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(thread?.subject ?? model.messages.first?.subject ?? "").font(.title2.bold()).textSelection(.enabled)
                    Spacer()
                    if let thread {
                        ColorDot(mails.color(for: thread.account), size: 9)
                        Text(AccountStyle.label(for: thread.account)).font(.callout).foregroundStyle(.secondary)
                    }
                }
                ForEach(model.messages) { message in
                    MailMessageView(message: message, thread: thread, model: model, mails: mails, mine: mine,
                                    collapseQuote: message.id != model.messages.first?.id)
                }
                if let thread {
                    Button { NSWorkspace.shared.open(mails.gmailURL(thread)) } label: { Label("Répondre dans Gmail", systemImage: "arrowshape.turn.up.left") }
                        .buttonStyle(.glass)
                        .help("L'écriture arrive à la prochaine étape ; d'ici là, la réponse s'écrit dans Gmail.")
                }
            }
            .padding(.horizontal, PageMetrics.horizontal)
            .padding(.top, PageMetrics.top)
            .padding(.bottom, PageMetrics.bottom + 40)
            .frame(maxWidth: PageMetrics.readingWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: back) { Label("Mails", systemImage: "chevron.left") }.help("Revenir à la liste")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if let thread {
                    Button { mails.perform(.archive, on: thread); back() } label: { Label("Archiver", systemImage: "archivebox") }.help("Archiver")
                    Button { mails.perform(.trash, on: thread); back() } label: { Label("Supprimer", systemImage: "trash") }.help("Supprimer")
                    Button { mails.perform(.markUnread, on: thread, undoable: false); back() } label: { Label("Non lu", systemImage: "envelope.badge") }
                        .help("Marquer comme non lu")
                    Menu {
                        Button("Ouvrir dans Gmail") { NSWorkspace.shared.open(mails.gmailURL(thread)) }
                        MailTabChoice(thread: thread, mails: mails)
                    } label: {
                        Label("Plus", systemImage: "ellipsis")
                    }
                }
            }
        }
        .onExitCommand(perform: back)
        .onDeleteCommand { if let thread { mails.perform(.trash, on: thread); back() } }
        .quickLookPreview($model.preview)
        .windowTitle("Mails", subtitle: thread?.subject ?? "")
        .task(id: key) {
            thread = try? mails.store.thread(key)
            if let thread { mails.markRead(thread) }
        }
        .onChange(of: mails.inbox) { _, _ in thread = (try? mails.store.thread(key)) ?? thread }
    }
}

/// One message of a thread: a line when folded; unfolded, its header, its body and its files.
struct MailMessageView: View {
    let message: MailMessageRow
    let thread: MailThreadRow?
    @ObservedObject var model: MailThreadModel
    @ObservedObject var mails: MailLibrary
    let mine: Set<String>
    let collapseQuote: Bool
    @State private var height: CGFloat = 80

    private var sender: String { message.sender.map { mine.contains($0.email) ? "Moi" : $0.display } ?? "Expéditeur inconnu" }

    var body: some View {
        let unfolded = model.expanded.contains(message.id)
        VStack(alignment: .leading, spacing: Space.m) {
            Button { model.toggle(message) } label: {
                HStack(alignment: .top, spacing: Space.m) {
                    Avatar(String(sender.prefix(1)).uppercased(), size: 30, tint: mails.color(for: message.account))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Space.s) {
                            Text(sender).fontWeight(.semibold)
                            if unfolded, let email = message.sender?.email { Text(email).font(.caption).foregroundStyle(.secondary) }
                        }
                        if unfolded {
                            let people = (message.to + message.cc).map { mine.contains($0.email) ? "moi" : $0.display }
                            if !people.isEmpty { Text("à \(people.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        } else {
                            Text(message.snippet).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    if !message.files.isEmpty, !unfolded { Image(systemName: "paperclip").font(.caption).foregroundStyle(.secondary) }
                    Text(MailText.date(message.date)).font(.callout).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if unfolded {
                content
            }
        }
        .padding(Space.l)
        .cardSurface()
    }

    @ViewBuilder
    private var content: some View {
        if let body = model.bodies[message.id] {
            let known = thread.map { mails.showsImages(of: message, in: $0) } ?? false
            let images = known || model.allowed.contains(message.id)
            if !images, message.bodyIsHTML, MailHTML.hasRemoteImages(body) {
                HStack(spacing: Space.s) {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                    Text("Les images distantes sont masquées.").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Afficher les images") { model.allowed.insert(message.id) }
                    if message.authenticated, let email = message.sender?.email {
                        Button("Toujours pour cet expéditeur") {
                            model.allowed.insert(message.id)
                            mails.alwaysShowImages(from: email)
                        }
                    }
                }
                .controlSize(.small)
            }
            // The mail on white, as in Gmail, whatever the app's theme.
            MailBodyView(document: MailHTML.document(body: body, isHTML: message.bodyIsHTML, images: images, collapseQuote: collapseQuote),
                         images: images, inline: { id in await model.inline(id, of: message) },
                         onLink: { NSWorkspace.shared.open($0) }, height: $height)
                .frame(height: height)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            if !message.files.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.s) {
                        ForEach(message.files, id: \.partID) { file in
                            Button { model.open(file, of: message) } label: {
                                Label("\(file.filename) · \(MailText.size(file.size))", systemImage: "paperclip").lineLimit(1)
                            }
                            .buttonStyle(.bordered)
                            .contextMenu { Button("Enregistrer…") { model.save(file, of: message) } }
                            .help(AttachmentSafety.canOpen(name: file.filename) ? "Aperçu" : "Ce type de fichier ne s'ouvre pas dans Polhub : il s'enregistre.")
                        }
                    }
                }
            }
        } else if let failure = model.failed[message.id] {
            Label("Ce message n'a pas pu être lu : \(failure)", systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
        } else {
            ProgressView().controlSize(.small)
        }
    }
}

/// Réglages › Mails (14/11): when remote images load.
struct MailSettingsPane: View {
    @AppStorage(Preferences.Key.mailImages) private var images = MailImages.connus.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Images distantes", selection: $images) {
                    ForEach(MailImages.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
            } footer: {
                Text("Une image distante qui se charge montre à son expéditeur l'adresse IP de ton Mac et l'heure d'ouverture. « Pour les expéditeurs connus » : tes contacts, les personnes à qui tu as écrit, et ceux pour qui tu as dit « Toujours », quand Gmail confirme que le mail vient bien d'eux. Les images jointes au mail s'affichent toujours.")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640)
    }
}
