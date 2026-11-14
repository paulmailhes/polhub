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
        .animation(.snappy(duration: 0.25), value: router.mailSelection)
        .animation(.snappy(duration: 0.25), value: mails.composing)
        .overlay(alignment: .bottom) { MailUndoBar(mails: mails) }
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
                    Button { mails.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }
            }
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.s)
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
        let count = thread.messageCount > 1 ? " (\(thread.messageCount))" : ""
        if thread.senders.count == 1, let only = thread.senders.first {
            return (mine.contains(only.email) ? "moi" : only.display) + count
        }
        let names = thread.senders.map { mine.contains($0.email) ? "moi" : ($0.name?.components(separatedBy: " ").first ?? $0.email) }
        return names.joined(separator: ", ") + count
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

/// The list: one line per thread, the mailboxes together, cut by day; ticks for gestures on several threads.
struct MailListView: View {
    @ObservedObject var mails: MailLibrary
    @ObservedObject var router: WindowRouter
    @FocusState private var listFocused: Bool

    private func open(_ key: String) {
        mails.focused = key
        router.mailSelection = key
    }

    var body: some View {
        let threads = mails.folder == .sent ? mails.sent : mails.shown
        let mine = Set(mails.agenda.accounts.map(\.email))
        VStack(spacing: 0) {
            if mails.folder == .drafts {
                MailDraftListView(mails: mails, router: router)
            } else if mails.folder == .subscriptions {
                MailSubscriptionsView(mails: mails)
            } else {
                content(threads, mine: mine)
            }
            if let progress = mails.progress {
                Divider()
                Text(progress).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.l).padding(.vertical, 6)
            }
        }
        .toolbar { toolbar }
        .searchable(text: $mails.query, placement: .toolbar, prompt: "Chercher dans Gmail")
        .onSubmit(of: .search) { Task { await mails.search(mails.query) } }
        .onChange(of: mails.query) { _, text in if text.isEmpty { mails.endSearch() } }
        .windowTitle("Mails", subtitle: mails.searching ? "Recherche…" : (mails.found != nil ? "Résultats de la recherche"
                                                                          : (mails.folder == .inbox ? mails.tab.title : mails.folder.title)))
    }

    @ViewBuilder
    private func content(_ threads: [MailThreadRow], mine: Set<String>) -> some View {
        VStack(spacing: 0) {
            if let failure = mails.failure {
                banner(icon: "exclamationmark.triangle", tint: .orange, text: "\(AccountStyle.label(for: failure.account)) : \(failure.text)") {
                    Button("Comptes Google") { router.openSettings(.accounts) }
                }
            }
            if mails.found == nil, mails.folder == .inbox, mails.tab != .personnes {
                banner(icon: "info.circle", tint: .secondary,
                       text: "\(mails.tab.explanation) Un mail qui n'a rien à faire ici : clic droit › « Ranger dans ».") { EmptyView() }
            }
            if threads.isEmpty {
                ContentUnavailableView(mails.found != nil ? "Aucun mail trouvé"
                                       : (mails.progress != nil ? "Lecture de tes boîtes…" : (mails.unreadOnly && mails.folder == .inbox ? "Aucun non lu" : "Rien ici")),
                                       systemImage: mails.found != nil ? "magnifyingglass" : mails.folder.icon,
                                       description: Text(mails.found != nil || mails.folder != .inbox ? "" : mails.tab.explanation))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list(threads, mine: mine)
            }
        }
    }

    /// One line above the list. (A text left free to grow in height here kept the whole window from drawing.)
    private func banner(icon: String, tint: Color, text: String, @ViewBuilder action: () -> some View) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.s) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(text).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: Space.m)
                action()
            }
            .padding(.horizontal, Space.l).padding(.vertical, Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
        }
    }

    private func list(_ threads: [MailThreadRow], mine: Set<String>) -> some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(MailText.sections(threads), id: \.title) { section in
                        Section {
                            ForEach(section.threads) { thread in
                                MailRow(thread: thread, mails: mails, mine: mine) { open(thread.id) }
                                    .id(thread.id)
                                Divider().padding(.leading, 64)
                            }
                        } header: {
                            Text(section.title)
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Space.l).padding(.top, Space.m).padding(.bottom, 6)
                                .background(.bar)
                        }
                    }
                }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($listFocused)
            .onAppear { listFocused = true }
            .onKeyPress(.downArrow) { move(1, in: threads, scroll: scroll) }
            .onKeyPress(.upArrow) { move(-1, in: threads, scroll: scroll) }
            .onKeyPress(.return) {
                guard let key = mails.focused else { return .ignored }
                open(key)
                return .handled
            }
            .onKeyPress(.space) {
                guard let key = mails.focused else { return .ignored }
                mails.select(key, extend: false)
                return .handled
            }
            .onKeyPress(keys: [.delete, .deleteForward]) { _ in
                if !mails.selected.isEmpty {
                    mails.performOnSelection(.trash)
                } else if let thread = threads.first(where: { $0.id == mails.focused }) {
                    mails.focused = mails.neighbor(of: thread.id, offset: 1) ?? mails.neighbor(of: thread.id, offset: -1)
                    mails.perform(.trash, on: thread)
                } else {
                    return .ignored
                }
                return .handled
            }
            .onKeyPress(.escape) {
                guard mails.selecting || !mails.selected.isEmpty else { return .ignored }
                mails.endSelection()
                return .handled
            }
            .onKeyPress(characters: CharacterSet(charactersIn: "aA")) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                mails.selectAll()
                return .handled
            }
        }
    }

    private func move(_ step: Int, in threads: [MailThreadRow], scroll: ScrollViewProxy) -> KeyPress.Result {
        guard !threads.isEmpty else { return .ignored }
        let index = threads.firstIndex { $0.id == mails.focused }.map { $0 + step } ?? (step > 0 ? 0 : threads.count - 1)
        let key = threads[min(max(index, 0), threads.count - 1)].id
        mails.focused = key
        scroll.scrollTo(key)
        return .handled
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Menu {
                Picker("Dossier", selection: $mails.folder) {
                    ForEach(MailFolder.allCases, id: \.self) { folder in
                        let count = folder == .drafts ? mails.drafts.count + mails.gmailDrafts.count : 0
                        Label(count > 0 ? "\(folder.title) (\(count))" : folder.title, systemImage: folder.icon).tag(folder)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(mails.folder.title, systemImage: mails.folder.icon).labelStyle(.titleAndIcon)
            }
            .help("Boîte de réception, Brouillons, Envoyés")
        }
        if mails.folder == .inbox {
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
            .help(MailTab.allCases.map { "\($0.title) : \($0.explanation)" }.joined(separator: "\n"))
        }
        }
        if mails.selecting || !mails.selected.isEmpty {
            ToolbarItemGroup(placement: .primaryAction) {
                let count = mails.selected.count
                Text(count == 0 ? "Coche des mails" : "\(count) sélectionné\(count > 1 ? "s" : "")")
                    .foregroundStyle(.secondary).fixedSize()
                Group {
                    Button { mails.performOnSelection(.archive) } label: { Label("Archiver", systemImage: "archivebox") }.help("Archiver")
                    Button { mails.performOnSelection(.trash) } label: { Label("Supprimer", systemImage: "trash") }.help("Supprimer")
                    Button { mails.performOnSelection(.markRead) } label: { Label("Lu", systemImage: "envelope.open") }.help("Marquer comme lus")
                    Button { mails.performOnSelection(.markUnread) } label: { Label("Non lu", systemImage: "envelope.badge") }.help("Marquer comme non lus")
                }
                .disabled(count == 0)
                Button { count == mails.shown.count ? mails.selected.removeAll() : mails.selectAll() } label: {
                    Label(count == mails.shown.count ? "Tout désélectionner" : "Tout sélectionner", systemImage: "checklist.checked")
                }
                .help(count == mails.shown.count ? "Tout désélectionner" : "Tout sélectionner (⌘A)")
                Button { mails.endSelection() } label: { Label("Terminer", systemImage: "xmark") }.help("Terminer la sélection (Échap)")
            }
        } else {
            ToolbarItemGroup(placement: .primaryAction) {
                ForEach(mails.accounts) { account in
                    let shown = !mails.hidden.contains(account.email)
                    // A dot per mailbox, in its color: full when shown, empty when hidden; its name on hover.
                    Button {
                        if shown { mails.hidden.insert(account.email) } else { mails.hidden.remove(account.email) }
                    } label: {
                        Label(AccountStyle.label(for: account.email), systemImage: shown ? "circle.fill" : "circle")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(mails.color(for: account.email))
                    }
                    .help(shown ? "\(AccountStyle.label(for: account.email)) · \(account.email) — cliquer pour masquer cette boîte"
                                : "\(AccountStyle.label(for: account.email)) · \(account.email) — masquée, cliquer pour l'afficher")
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { mails.newMail() } label: { Label("Nouveau mail", systemImage: "square.and.pencil") }
                    .help("Nouveau mail (⌘N)")
                    .keyboardShortcut("n", modifiers: .command)
                if mails.folder == .inbox {
                    Toggle(isOn: $mails.unreadOnly) {
                        Label("Non lus", systemImage: mails.unreadOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .help(mails.unreadOnly ? "Afficher tous les mails" : "N'afficher que les non lus")
                }
                Menu {
                    Button("Relever les mails maintenant") { mails.refresh() }
                    if mails.folder == .inbox {
                        Button("Sélectionner plusieurs mails") { mails.selecting = true }
                        Button("Tout marquer comme lu dans « \(mails.tab.title) »") { mails.markAllRead() }
                            .disabled(mails.unread(in: mails.tab) == 0)
                        if mails.tab != .personnes {
                            Button("Tout archiver dans « \(mails.tab.title) »") { mails.archiveTab() }
                                .disabled(mails.shown.isEmpty)
                        }
                    }
                    Divider()
                    Button("Abonnements") { mails.folder = .subscriptions }
                } label: {
                    Label("Plus", systemImage: "ellipsis.circle")
                }
                .help("Relever, sélectionner, tout marquer comme lu, abonnements")
            }
        }
    }
}

/// One thread in the list: the mailbox's color, who, the subject and an extract, the date. Unread: a dot, in
/// bold; read: quieter. On hover, a box to tick and the gestures.
struct MailRow: View {
    let thread: MailThreadRow
    @ObservedObject var mails: MailLibrary
    let mine: Set<String>
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        let ticked = mails.selected.contains(thread.id)
        let boxes = mails.selecting || !mails.selected.isEmpty || hovering
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5).fill(mails.color(for: thread.account)).frame(width: 3, height: 22)
                .padding(.leading, Space.m)
                .help(thread.account)
            ZStack {
                if boxes {
                    Image(systemName: ticked ? "checkmark.square.fill" : "square")
                        .font(.body)
                        .foregroundStyle(ticked ? Color.accentColor : .secondary)
                        .contentShape(Rectangle())
                        .onTapGesture { mails.select(thread.id, extend: NSEvent.modifierFlags.contains(.shift)) }
                        .help("Sélectionner")
                } else if thread.unread {
                    Circle().fill(Color.accentColor).frame(width: 9, height: 9).help("Non lu")
                }
            }
            .frame(width: 40)
            Text(MailText.senders(thread, mine: mine))
                .fontWeight(thread.unread ? .semibold : .regular)
                .foregroundStyle(thread.unread ? .primary : .secondary)
                .lineLimit(1)
                .frame(width: 190, alignment: .leading)
            MailFilingChip(thread: thread, mails: mails, always: hovering && mails.filing(of: thread) == nil && mails.tab(of: thread) == .personnes)
                .padding(.leading, Space.s)
            (Text(thread.subject).fontWeight(thread.unread ? .semibold : .regular).foregroundStyle(thread.unread ? Color.primary : Color.primary.opacity(0.8))
                + Text(thread.snippet.isEmpty ? "" : "  —  \(thread.snippet)").foregroundStyle(thread.unread ? .secondary : .tertiary))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Space.s)
            if thread.hasAttachment { Image(systemName: "paperclip").font(.caption).foregroundStyle(.secondary).padding(.leading, Space.s) }
            Group {
                if hovering, !boxes || mails.selected.isEmpty {
                    HStack(spacing: Space.xs) {
                        Button { mails.perform(.archive, on: thread) } label: { Image(systemName: "archivebox") }.help("Archiver")
                        Button { mails.perform(.trash, on: thread) } label: { Image(systemName: "trash") }.help("Supprimer")
                        Button { mails.perform(thread.unread ? .markRead : .markUnread, on: thread, undoable: false) } label: {
                            Image(systemName: thread.unread ? "envelope.open" : "envelope.badge")
                        }
                        .help(thread.unread ? "Marquer comme lu" : "Marquer comme non lu")
                    }
                    .buttonStyle(.borderless)
                } else {
                    Text(MailText.date(thread.lastMessageAt))
                        .font(.callout).fontWeight(thread.unread ? .semibold : .regular)
                        .foregroundStyle(thread.unread ? .primary : .secondary)
                }
            }
            .frame(width: 92, alignment: .trailing)
            .padding(.trailing, Space.l)
        }
        .font(.callout)
        .frame(height: 40)
        .background(ticked ? Surface.selected : (mails.focused == thread.id ? Surface.raised : (hovering ? Surface.fill : .clear)))
        .contentShape(Rectangle())
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            if flags.contains(.command) || flags.contains(.shift) || mails.selecting || !mails.selected.isEmpty {
                mails.select(thread.id, extend: flags.contains(.shift))
            } else {
                open()
            }
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Archiver") { mails.perform(.archive, on: thread) }
            Button("Supprimer") { mails.perform(.trash, on: thread) }
            Button(thread.unread ? "Marquer comme lu" : "Marquer comme non lu") { mails.perform(thread.unread ? .markRead : .markUnread, on: thread, undoable: false) }
            Button(ticked ? "Désélectionner" : "Sélectionner") { mails.select(thread.id, extend: false) }
            Divider()
            Menu("Ranger dans") { MailFilingMenu(thread: thread, mails: mails) }
            if let sender = thread.lastSender {
                Button("Tous les mails de cet expéditeur") { mails.showAll(from: sender) }
            }
            Button("Signaler comme spam") { mails.reportSpam(thread) }
            Divider()
            Button("Ouvrir dans Gmail") { NSWorkspace.shared.open(mails.gmailURL(thread)) }
        }
    }
}

/// « Ranger dans » (step « Ranger »): the projects under way, the others apart; Perso; the automatic cases;
/// « Aucune case ». Kept for the thread and for its sender's next mails.
struct MailFilingMenu: View {
    let thread: MailThreadRow
    @ObservedObject var mails: MailLibrary

    var body: some View {
        let current = mails.filing(of: thread)?.filing
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
        Button { mails.file(thread, as: filing) } label: {
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
                Text(label.text).font(.caption.weight(.medium)).lineLimit(1)
                    .padding(.horizontal, 7).padding(.vertical, 2)
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
            return (project?.name ?? "Projet", ProjectViews.cardHex(project?.color).map(Color.init(hex:)) ?? .accentColor)
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

    private func save(_ url: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        guard panel.runModal() == .OK, let target = panel.url else { return }
        try? FileManager.default.removeItem(at: target)
        do { try FileManager.default.copyItem(at: url, to: target) } catch { library.message = "Enregistrement impossible : \(error.localizedDescription)" }
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

    /// Archived or deleted: on to the next thread, as Apple Mail does; back to the list after the last one.
    private func gesture(_ kind: MailGestureKind) {
        guard let thread else { return }
        let next = mails.neighbor(of: key, offset: 1) ?? mails.neighbor(of: key, offset: -1)
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
                                Text("\(count) messages plus anciens").font(.callout.weight(.medium))
                                    .padding(.horizontal, Space.m).padding(.vertical, 4)
                                    .background(Surface.raised, in: Capsule())
                            }
                            .buttonStyle(.plain)
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
                        .padding(.top, Space.l)
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
        .quickLookPreview($model.preview)
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
                    .font(.title2.bold()).lineLimit(2).textSelection(.enabled)
                if let thread {
                    HStack(spacing: 6) {
                        ColorDot(mails.color(for: thread.account), size: 8)
                        Text(AccountStyle.label(for: thread.account))
                        Text("·")
                        Text(model.messages.count > 1 ? "\(model.messages.count) messages" : "1 message")
                        Text("·")
                        MailFilingChip(thread: thread, mails: mails, always: true)
                    }
                    .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Space.m)
            HStack(spacing: Space.xs) {
                if let position = mails.position(of: key) { Text(position).font(.caption).foregroundStyle(.secondary).monospacedDigit() }
                Button { go(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(mails.neighbor(of: key, offset: -1) == nil).help("Fil précédent (↑)")
                    .keyboardShortcut(.upArrow, modifiers: [])
                Button { go(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(mails.neighbor(of: key, offset: 1) == nil).help("Fil suivant (↓)")
                    .keyboardShortcut(.downArrow, modifiers: [])
                Divider().frame(height: 18)
                Button { gesture(.archive) } label: { Image(systemName: "archivebox") }.help("Archiver")
                Button { gesture(.trash) } label: { Image(systemName: "trash") }.help("Supprimer")
                Button { gesture(.markUnread) } label: { Image(systemName: "envelope.badge") }.help("Marquer comme non lu")
                Menu {
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
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Plus")
            }
            .buttonStyle(.borderless)
            .font(.body)
            .padding(.horizontal, Space.m).padding(.vertical, 6)
            .glassEffect(.regular, in: Capsule())
        }
        .padding(.horizontal, Space.xl).padding(.vertical, Space.m)
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

    private var isMine: Bool { message.sender.map { mine.contains($0.email) } ?? false }
    private var sender: String { isMine ? "Moi" : (message.sender?.display ?? "Expéditeur inconnu") }
    private var initial: String { String(sender.prefix(1)).uppercased() }
    private var tint: Color { MailText.tint(for: message.sender?.email ?? "") }

    var body: some View {
        if model.expanded.contains(message.id) {
            VStack(alignment: .leading, spacing: Space.m) {
                header
                content.padding(.leading, 46)
            }
            .padding(.vertical, Space.l)
        } else {
            HStack(spacing: Space.m) {
                Avatar(initial, size: 30, tint: tint)
                Text(sender).fontWeight(message.isUnread ? .semibold : .medium).lineLimit(1).frame(width: 170, alignment: .leading)
                Text(message.snippet).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                if !message.files.isEmpty { Image(systemName: "paperclip").font(.caption).foregroundStyle(.secondary) }
                Text(MailText.date(message.date)).font(.callout).foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.vertical, Space.m)
            .contentShape(Rectangle())
            .onTapGesture { model.toggle(message) }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Avatar(initial, size: 34, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(sender).fontWeight(.semibold)
                    if let email = message.sender?.email, !isMine { Text(email).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                }
                Button { details.toggle() } label: {
                    HStack(spacing: 3) {
                        let people = (message.to + message.cc).map { mine.contains($0.email) ? "moi" : ($0.name ?? $0.email) }
                        Text(people.isEmpty ? "détails" : "à \(people.joined(separator: ", "))").lineLimit(1)
                        Image(systemName: details ? "chevron.up" : "chevron.down").font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .font(.caption).foregroundStyle(.secondary)
                if details { detailGrid }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.toggle(message) }
            Spacer(minLength: Space.m)
            Text(MailText.longDate(message.date)).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: Space.xs) {
                Button { reply(.reply) } label: { Image(systemName: "arrowshape.turn.up.left") }
                    .help("Répondre à ce message")
                Menu {
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
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .buttonStyle(.borderless)
        }
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
        Grid(alignment: .leading, horizontalSpacing: Space.m, verticalSpacing: 3) {
            ForEach(detailRows, id: \.0) { title, value in
                GridRow {
                    Text(title).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    Text(value).textSelection(.enabled)
                }
            }
        }
        .font(.caption)
        .padding(Space.s)
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
                        Text("Images masquées : leur expéditeur verrait que tu as ouvert le mail.").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Afficher") { model.allowed.insert(message.id) }
                        if message.authenticated, let email = message.sender?.email {
                            Button("Toujours pour cet expéditeur") {
                                model.allowed.insert(message.id)
                                mails.alwaysShowImages(from: email)
                            }
                        }
                    }
                    .controlSize(.small)
                    .padding(.horizontal, Space.m).padding(.vertical, 6)
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
            Label("Ce message n'a pas pu être lu : \(failure)", systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private var files: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(message.files.count > 1 ? "\(message.files.count) pièces jointes" : "1 pièce jointe").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if message.files.count > 1 {
                    Button("Tout enregistrer…") { model.saveAll(of: message) }.buttonStyle(.link).font(.caption)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 260), spacing: Space.s)], alignment: .leading, spacing: Space.s) {
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
        HStack(spacing: Space.s) {
            Image(nsImage: NSWorkspace.shared.icon(for: type)).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.filename).font(.callout).lineLimit(1).truncationMode(.middle)
                Text(MailText.size(file.size)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if hovering {
                Button(action: save) { Image(systemName: "arrow.down.circle") }.buttonStyle(.borderless).help("Enregistrer…")
            }
        }
        .padding(Space.s)
        .background(hovering ? Surface.raised : Surface.fill, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hovering = $0 }
        .contextMenu { Button("Enregistrer…", action: save) }
        .help(AttachmentSafety.canOpen(name: file.filename) ? "Aperçu" : "Ce type de fichier ne s'ouvre pas dans Polhub : il s'enregistre.")
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
                Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
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
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
                    ForEach(mails.subscriptions) { subscription in
                        row(subscription)
                        Divider().padding(.leading, 64)
                    }
                }
            }
        }
    }

    private func row(_ subscription: MailSubscription) -> some View {
        let method = mails.unsubscribeMethod(subscription)
        let left = mails.unsubscribed[subscription.sender.email]
        return HStack(spacing: Space.m) {
            Avatar(String(subscription.sender.display.prefix(1)).uppercased(), size: 30, tint: MailText.tint(for: subscription.sender.email))
                .padding(.leading, Space.l)
            VStack(alignment: .leading, spacing: 2) {
                Text(subscription.sender.display).fontWeight(.medium).lineLimit(1)
                Text(subscription.sender.email).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 280, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(subscription.count) mail\(subscription.count > 1 ? "s" : "")" + (subscription.unread > 0 ? " · \(subscription.unread) non lu\(subscription.unread > 1 ? "s" : "")" : ""))
                Text("Dernier : \(MailText.date(subscription.lastAt))").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !subscription.inboxThreads.isEmpty {
                Button("Tout archiver (\(subscription.inboxThreads.count))") { mails.archiveAll(subscription) }
                    .help("Archiver ses mails encore en boîte de réception")
            }
            if let left {
                Label("Désabonné le \(left.formatted(.dateTime.day().month(.abbreviated).locale(MailText.locale)))", systemImage: "checkmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
            } else if let method {
                Button("Se désabonner") { mails.askUnsubscribe(sender: subscription.sender, method: method) }
                    .help({
                        switch method {
                        case .oneClick: "En un clic, auprès de \(method.domain)"
                        case .mail: "Par un mail que tu enverras toi-même"
                        case .page: "Sur la page de \(method.domain)"
                        }
                    }())
            }
        }
        .font(.callout)
        .padding(.trailing, Space.l)
        .frame(height: 54)
    }
}
