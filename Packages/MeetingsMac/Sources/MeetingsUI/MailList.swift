import Agenda
import AppKit
import Mail
import MailFormat
import Persistence
import PolhubDesign
import ProjectsUI
import SwiftUI

/// The list, as Gmail's (Paul, 15/11: « il faut vraiment que tu calques ce qu'a fait Gmail »): a bar of
/// gestures, then one line per thread, the mailboxes together. The folders are in the sidebar, under « Mails »; the
/// mailboxes in the bar's « Boîtes » (lot 4, 19/11). Every folder under the same bar, on the same grid (lot 6, 19/11).
struct MailListView: View {
    @ObservedObject var mails: MailLibrary
    @ObservedObject var router: WindowRouter
    @FocusState private var listFocused: Bool
    @AppStorage(Preferences.Key.mailDensity) private var density = MailDensity.defaut.rawValue
    @AppStorage(Preferences.Key.mailDays) private var days = false

    private func open(_ key: String) {
        mails.focused = key
        router.mailSelection = key
    }

    private var subtitle: String {
        if mails.found != nil { return "Résultats" }
        return mails.folder.title
    }

    /// « Nouveau mail » is the screen's principal button over the list; over a thread or a draft open on it, it steps
    /// down: « Répondre », « Envoyer » or « Pas un spam » is the one (lot 6, 19/11).
    static func newMailIsPrincipal(composing: String?, thread: String?) -> Bool {
        composing == nil && thread == nil
    }

    var body: some View {
        let mine = Set(mails.agenda.accounts.map(\.email))
        VStack(spacing: 0) {
            // The bar in every folder, at the same height (lot 6, 19/11): the first line never jumps from one to another.
            MailListBar(mails: mails)
            if mails.found == nil, mails.folder == .drafts {
                MailDraftListView(mails: mails, router: router)
            } else if mails.found == nil, mails.folder == .scheduled {
                MailScheduledListView(mails: mails, router: router)
            } else if mails.found == nil, mails.folder == .subscriptions {
                MailSubscriptionsView(mails: mails)
            } else {
                if let summary = mails.searchSummary {
                    MailSearchLine(text: summary, searching: mails.searching)
                } else if let aside = mails.folder.aside {
                    // As Gmail's line over its trash and its spam; a wheel while Gmail's list comes.
                    MailSearchLine(text: aside.notice, searching: mails.readingAside, icon: aside == .spam ? "exclamationmark.octagon" : "clock")
                }
                content(mails.shown, mine: mine)
            }
            if let progress = mails.progress {
                Divider()
                Text(progress).font(.meta).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.xl).padding(.vertical, Space.s)
            }
        }
        .background(MailSurface.unread)
        // « Nouveau mail » in the toolbar of every folder (Paul, 15/11: « dans toute ma partie mail, dans la barre »).
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if Self.newMailIsPrincipal(composing: mails.composing, thread: router.mailSelection) {
                    newMail.buttonStyle(.glassProminent)
                } else {
                    newMail.buttonStyle(.glass)
                }
            }
        }
        // One bar (15/11): the copy is filtered as Paul types; Enter also asks Gmail, which reads the bodies.
        .searchable(text: $mails.query, placement: .toolbar, prompt: "Chercher dans tes mails")
        .onSubmit(of: .search) { Task { await mails.search(mails.query) } }
        .windowTitle("Mails", subtitle: subtitle)
    }

    private var newMail: some View {
        Button { mails.writeNewMail(router: router) } label: {
            Label { Text("Nouveau mail") } icon: { AppIconImage(.newMail, size: 16) }.labelStyle(.titleAndIcon)
        }
        .help("Écrire un nouveau mail (⌘N)")
    }

    @ViewBuilder
    private func content(_ threads: [MailThreadRow], mine: Set<String>) -> some View {
        VStack(spacing: 0) {
            if let failure = mails.failure {
                // A mailbox that fails: the icon at the attention's color, the sentence grey (design system v2, 19/11).
                HStack(spacing: Space.s) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Tint.attention)
                    Text("\(AccountStyle.label(for: failure.account)) : \(failure.text)").foregroundStyle(.secondary).lineLimit(2)
                    Spacer(minLength: Space.m)
                    Button("Comptes Google") { router.openSettings(.accounts) }
                        .buttonStyle(.secondary)
                        .controlSize(.small)
                }
                .font(.meta)
                .padding(.horizontal, Space.xl).padding(.vertical, Space.m)
                .overlay(alignment: .bottom) { MailLine() }
            }
            if threads.isEmpty {
                MailEmptyView(state: mails.emptyState, mails: mails)
            } else {
                list(threads, mine: mine)
            }
        }
    }

    private func list(_ threads: [MailThreadRow], mine: Set<String>) -> some View {
        let density = MailDensity(rawValue: density) ?? .defaut
        let stripes = MailGrid.showsStripes(accounts: mails.accounts.map(\.email), hidden: mails.hidden)
        return ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: days ? .sectionHeaders : []) {
                    if days {
                        ForEach(MailText.sections(threads), id: \.title) { section in
                            Section {
                                rows(section.threads, mine: mine, density: density, stripes: stripes)
                            } header: {
                                Text(section.title)
                                    .font(.meta.weight(.semibold)).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, MailGrid.boxEnd).padding(.trailing, MailGrid.trailing)
                                    .padding(.top, Space.l).padding(.bottom, Space.s)
                                    .background(MailSurface.unread)
                                    .overlay(alignment: .bottom) { MailLine() }
                            }
                        }
                    } else {
                        rows(threads, mine: mine, density: density, stripes: stripes)
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
                // In the trash or the spam, Suppr does nothing: only « Restaurer », « Pas un spam » (wave B).
                if mails.folder.aside != nil {
                    return .ignored
                } else if !mails.selected.isEmpty {
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
                guard !mails.selected.isEmpty else { return .ignored }
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

    private func rows(_ threads: [MailThreadRow], mine: Set<String>, density: MailDensity, stripes: Bool) -> some View {
        ForEach(threads) { thread in
            MailRow(thread: thread, mails: mails, mine: mine, density: density, stripes: stripes) { open(thread.id) }
                .id(thread.id)
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
}

/// The one grid of the mails' lists (lot 6, 19/11): every folder lines up on it, the bar above and the day titles with
/// them — the mailbox's stripe, the box to tick (or what stands in its place), who, the subject, then the end column,
/// which holds the date at rest and the gestures under the pointer, so that nothing covers the subject.
enum MailGrid {
    static let stripeStart: CGFloat = Space.m
    static let stripeWidth: CGFloat = 3
    /// Where the box to tick starts, then where it ends: the bar's box and the day titles line up on them.
    static let boxStart: CGFloat = stripeStart + stripeWidth
    static let boxWidth: CGFloat = 44
    static let boxEnd: CGFloat = boxStart + boxWidth
    static let sendersWidth: CGFloat = 210
    /// Between who and the subject.
    static let gap: CGFloat = Space.l
    /// Where the subject starts: the files line up under it.
    static let subjectStart: CGFloat = boxEnd + sendersWidth + gap
    /// One round gesture (`IconButton`), and the room between two.
    static let gestureSide: CGFloat = 32
    static let gestureSpacing: CGFloat = 2

    static func gesturesWidth(_ count: Int) -> CGFloat {
        CGFloat(count) * gestureSide + CGFloat(max(0, count - 1)) * gestureSpacing
    }

    /// The end column: archive, delete, read and the case side by side, the most a line offers under the pointer.
    static let endWidth: CGFloat = gesturesWidth(4)
    /// The height of a line's content: the box, the avatar of a sender.
    static let lineHeight: CGFloat = 28
    static let trailing: CGFloat = Space.l

    /// The stripe says which mailbox a line comes from: only when the list shows two of them or more.
    static func showsStripes(accounts: [String], hidden: Set<String>) -> Bool {
        accounts.filter { !hidden.contains($0) }.count > 1
    }
}

/// One line on the grid (lot 6, 19/11): every folder draws its lines with it, so that they all line up. The stripe keeps
/// its room when it does not show: a box hidden never moves the lines.
struct MailGridLine<Box: View, Senders: View, Subject: View, End: View>: View {
    let stripe: Color?
    let stripeHelp: String
    /// `nil`: the end column takes what it holds (the senders' two buttons in « Abonnements »).
    let endWidth: CGFloat?
    let box: Box
    let senders: Senders
    let subject: Subject
    let end: End

    init(stripe: Color?, stripeHelp: String = "", endWidth: CGFloat? = MailGrid.endWidth, @ViewBuilder box: () -> Box,
         @ViewBuilder senders: () -> Senders, @ViewBuilder subject: () -> Subject, @ViewBuilder end: () -> End) {
        self.stripe = stripe
        self.stripeHelp = stripeHelp
        self.endWidth = endWidth
        self.box = box()
        self.senders = senders()
        self.subject = subject()
        self.end = end()
    }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let stripe {
                    Capsule().fill(stripe).frame(width: MailGrid.stripeWidth, height: 22).help(stripeHelp)
                } else {
                    Color.clear.frame(width: MailGrid.stripeWidth, height: 1)
                }
            }
            .padding(.leading, MailGrid.stripeStart)
            box.frame(width: MailGrid.boxWidth)
            senders
                .frame(width: MailGrid.sendersWidth, alignment: .leading)
                .padding(.trailing, MailGrid.gap)
            subject.frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if let endWidth {
                    end.frame(width: endWidth, alignment: .trailing)
                } else {
                    end.fixedSize()
                }
            }
            .padding(.leading, Space.s)
        }
        .frame(minHeight: MailGrid.lineHeight)
    }
}

/// The thin line between two threads, as Gmail's.
struct MailLine: View {
    var body: some View { Rectangle().fill(MailSurface.line).frame(height: 1) }
}

/// A line above the list, on the grid (lot 6, 19/11): during a search, how many threads and what Enter does (15/11);
/// over the trash, the spam, « Programmés » and « Abonnements », what the folder is. Its icon in the box's column, its
/// text on the senders'.
struct MailSearchLine: View {
    let text: String
    let searching: Bool
    var icon = "magnifyingglass"

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if searching {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: icon).foregroundStyle(.secondary)
                }
            }
            .frame(width: MailGrid.boxWidth)
            .padding(.leading, MailGrid.boxStart)
            Text(text).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.meta)
        .frame(height: 20)
        .padding(.trailing, MailGrid.trailing).padding(.vertical, Space.m)
        .overlay(alignment: .bottom) { MailLine() }
        .help(text)
    }
}

/// What an empty list says, and the one thing to do about it (lot 6, 19/11): an empty folder says what arrives there and
/// how to write; a list emptied by a filter (« Non lus », a mailbox hidden) says so and offers to lift it. Never « Rien ici ».
struct MailEmptyState: Equatable {
    enum Action: Equatable {
        case showRead, showEveryBox

        var title: String {
            switch self {
            case .showRead: "Afficher tous les mails"
            case .showEveryBox: "Afficher toutes les boîtes"
            }
        }
    }

    let title: String
    let systemImage: String
    let detail: String?
    let action: Action?

    static func of(folder: MailFolder, searching: Bool, reading: Bool, readingAside: Bool, unreadOnly: Bool, hiddenBoxes: Int) -> MailEmptyState {
        let hidden: (detail: String, action: Action)? = hiddenBoxes > 0
            ? (hiddenBoxes == 1 ? "1 boîte est masquée." : "\(hiddenBoxes) boîtes sont masquées.", .showEveryBox) : nil
        if searching {
            return MailEmptyState(title: "Aucun mail trouvé", systemImage: "magnifyingglass", detail: hidden?.detail, action: hidden?.action)
        }
        if folder.aside != nil, readingAside { return MailEmptyState(title: "Lecture de Gmail…", systemImage: folder.icon, detail: nil, action: nil) }
        if folder.aside == nil, reading { return MailEmptyState(title: "Lecture de tes boîtes…", systemImage: folder.icon, detail: nil, action: nil) }
        if unreadOnly, MailListBar.filtersUnread(folder: folder, searching: false) {
            return MailEmptyState(title: "Tout est lu", systemImage: "envelope.open", detail: nil, action: .showRead)
        }
        let own = own(folder)
        if let hidden { return MailEmptyState(title: own.title, systemImage: folder.icon, detail: hidden.detail, action: hidden.action) }
        return MailEmptyState(title: own.title, systemImage: folder.icon, detail: own.detail, action: nil)
    }

    /// The folder empty as it is: what arrives there, and how to act.
    private static func own(_ folder: MailFolder) -> (title: String, detail: String?) {
        switch folder {
        case .inbox: ("Boîte de réception vide", "Les mails des personnes arrivent ici. ⌘N pour écrire.")
        case .notifications: ("Aucune notification", "Les reçus, les alertes et les lettres d'information arrivent ici.")
        case .sent: ("Aucun mail envoyé", "⌘N pour écrire un mail.")
        case .drafts: ("Aucun brouillon", "Un mail commencé et pas encore envoyé t'attend ici. ⌘N pour écrire.")
        case .scheduled: ("Aucun envoi programmé", "La flèche à côté d'« Envoyer » programme un mail : il attend ici son heure.")
        case .subscriptions: ("Aucun abonnement", "Les expéditeurs dont tu peux te désabonner apparaissent ici, les plus bavards d'abord.")
        case .spam: ("Aucun spam", nil)
        case .trash: ("Corbeille vide", nil)
        case .all: ("Aucun mail", nil)
        }
    }
}

extension MailLibrary {
    /// What the list of the folder says when it is empty (lot 6, 19/11).
    var emptyState: MailEmptyState {
        MailEmptyState.of(folder: folder, searching: found != nil, reading: progress != nil, readingAside: readingAside, unreadOnly: unreadOnly,
                          hiddenBoxes: accounts.filter { hidden.contains($0.email) }.count)
    }
}

/// An empty list: what it is, and its one action, secondary.
struct MailEmptyView: View {
    let state: MailEmptyState
    @ObservedObject var mails: MailLibrary

    var body: some View {
        ContentUnavailableView {
            Label(state.title, systemImage: state.systemImage)
        } description: {
            if let detail = state.detail { Text(detail) }
        } actions: {
            if let action = state.action {
                Button(action.title) { perform(action) }.buttonStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func perform(_ action: MailEmptyState.Action) {
        switch action {
        case .showRead: mails.unreadOnly = false
        case .showEveryBox: mails.hidden = []
        }
    }
}

/// Above the list, as Gmail's: the box that ticks every thread, then the gestures on the threads ticked, or
/// « Relever » and « Plus »; « Boîtes » and « Non lus » on the right. In every folder (lot 6, 19/11): its box greyed
/// where nothing is ticked, « Non lus » only where it filters.
struct MailListBar: View {
    @ObservedObject var mails: MailLibrary

    /// Whether the folder's lines can be ticked: never the drafts, the programmed mails nor the senders, which have their
    /// own gestures; a search shows threads, whatever the folder.
    nonisolated static func ticks(folder: MailFolder, searching: Bool) -> Bool {
        searching || ![MailFolder.drafts, .scheduled, .subscriptions].contains(folder)
    }

    /// Whether « Non lus » filters the folder: the inbox, Notifications, Envoyés and every thread. Never a search (its
    /// results come from every folder), the trash or the spam (a thread put aside is never unread), nor the folders
    /// without threads.
    nonisolated static func filtersUnread(folder: MailFolder, searching: Bool) -> Bool {
        !searching && [MailFolder.inbox, .notifications, .sent, .all].contains(folder)
    }

    var body: some View {
        let shown = mails.shown
        let count = mails.selected.count
        let searching = mails.found != nil
        let ticks = Self.ticks(folder: mails.folder, searching: searching)
        HStack(spacing: Space.xs) {
            HStack(spacing: 0) {
                Button { count == 0 ? mails.selectAll() : mails.endSelection() } label: {
                    Image(systemName: count == 0 ? "square" : (count == shown.count ? "checkmark.square.fill" : "minus.square.fill"))
                        .font(.system(size: 16))
                        .foregroundStyle(count == 0 ? Color.secondary : MailSurface.accent)
                        .frame(width: 30, height: 32)
                }
                .buttonStyle(.hover(.circle))
                .help(count == 0 ? "Tout sélectionner (⌘A)" : "Tout désélectionner (Échap)")
                Menu {
                    Button("Tous") { mails.selectAll() }
                    Button("Aucun") { mails.endSelection() }
                    // A thread put aside is never unread.
                    if mails.folder.aside == nil {
                        Button("Lus") { mails.select(where: { !$0.unread }) }
                        Button("Non lus") { mails.select(where: { $0.unread }) }
                    }
                } label: {
                    Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 18, height: 32)
                }
                .menuStyle(.button).buttonStyle(.hover(.capsule)).menuIndicator(.hidden).fixedSize()
                .help("Sélectionner les lus, les non lus")
            }
            // Nothing to tick in the drafts, the programmed mails or the senders: greyed, never gone (lot 6, 19/11).
            .disabled(!ticks)
            .padding(.leading, MailGrid.boxStart + 7)
            if count > 0 {
                if let aside = mails.folder.aside {
                    // The one gesture of the trash or the spam, in words as Gmail's « Non spam »: an arrow alone
                    // would read as « Annuler ».
                    let kind = aside.gesture
                    Button { mails.performOnSelection(kind) } label: {
                        Label(kind.title(), systemImage: kind.icon).font(.rowBody.weight(.medium))
                            .padding(.horizontal, Space.m).frame(height: 32)
                    }
                    .buttonStyle(.hover(.capsule))
                    .help(aside == .spam ? "Remettre en boîte de réception : Gmail apprend que ce n'est pas un spam" : "Remettre en boîte de réception")
                } else {
                    ForEach(mails.folder.selectionGestures, id: \.self) { kind in
                        IconButton(kind.icon, help: kind.title(plural: true)) { mails.performOnSelection(kind) }
                    }
                }
                // 15/11: the ticked threads in one case, one « Annuler » for all; never from the trash or the spam.
                if mails.folder.aside == nil {
                    IconMenu("folder", help: "Ranger dans un projet ou une case") {
                        MailFilingMenu(selection: mails.selectedThreads, mails: mails)
                    }
                }
                Text("\(count) sélectionné\(count > 1 ? "s" : "")").font(.meta).foregroundStyle(.secondary).padding(.leading, Space.s)
            } else {
                IconButton("arrow.clockwise", help: "Relever les mails maintenant") { mails.refresh() }
                IconMenu("ellipsis", help: "Tout marquer comme lu, tout archiver, réglages") {
                    if mails.folder == .inbox || mails.folder == .notifications, !searching {
                        Button("Tout marquer comme lu dans « \(mails.tab.title) »") { mails.markAllRead() }
                            .disabled(mails.unread(in: mails.tab) == 0)
                        if mails.tab != .personnes {
                            // Never on a search's results: they come from every tab (second review of 14/11).
                            Button("Tout archiver dans « \(mails.tab.title) »") { mails.archiveTab() }
                                .disabled(shown.isEmpty)
                        }
                        Divider()
                    }
                    Button("Réglages des mails…") { mails.router?.openSettings(.mails) }
                }
            }
            Spacer(minLength: Space.m)
            HStack(spacing: Space.s) {
                // The boxes, a filter of the list, beside « Non lus » (lot 4, 19/11): no longer in the sidebar, which
                // lists places only.
                if mails.accounts.count > 1 { boxes }
                if Self.filtersUnread(folder: mails.folder, searching: searching) {
                    Toggle(isOn: $mails.unreadOnly) {
                        Label("Non lus", systemImage: "line.3.horizontal.decrease")
                    }
                    .toggleStyle(.button)
                    .help(mails.unreadOnly ? "Afficher tous les mails" : "N'afficher que les non lus")
                }
            }
            .padding(.trailing, MailGrid.trailing)
        }
        .frame(height: 48)
    }

    /// The mailboxes, ticked when the list shows them, as the calendars in Apple's Calendar: the same effect as the
    /// sidebar's boxes had. The title says when one is hidden.
    private var boxes: some View {
        let accounts = mails.accounts.map(\.email)
        let labels = accounts.map { AccountStyle.label(for: $0) }
        return Menu {
            ForEach(Array(accounts.enumerated()), id: \.element) { index, email in
                let label = labels[index]
                Toggle(labels.filter { $0 == label }.count > 1 ? "\(label) · \(email)" : label,
                       isOn: Binding(get: { !mails.hidden.contains(email) }, set: { Self.show(email, $0, in: mails) }))
            }
        } label: {
            Label(Self.boxesTitle(shown: accounts.filter { !mails.hidden.contains($0) }.count, total: accounts.count), systemImage: "tray.2")
        }
        .menuStyle(.button)
        .fixedSize()
        .help("Choisir les boîtes que la liste montre")
    }

    /// « Boîtes », or « Boîtes : 2 sur 3 » while one is hidden (lot 4, 19/11).
    static func boxesTitle(shown: Int, total: Int) -> String {
        shown == total ? "Boîtes" : "Boîtes : \(shown) sur \(total)"
    }

    /// A mailbox shown in the list, or hidden from it.
    static func show(_ email: String, _ shown: Bool, in mails: MailLibrary) {
        if shown { mails.hidden.remove(email) } else { mails.hidden.insert(email) }
    }
}

/// One thread on one line, as Gmail's (Paul, 15/11): who, then the case, the subject and, lighter, the start of
/// the mail; the date at the end. Unread: on the window's ground, in bold; read: a soft step down. The mailbox's stripe on
/// the left when the list shows several. Its files under it (« Par défaut »). Under the pointer, the gestures take the
/// date's place in the end column, kept for them: nothing moves, nothing covers the subject (lot 6, 19/11).
struct MailRow: View {
    let thread: MailThreadRow
    @ObservedObject var mails: MailLibrary
    let mine: Set<String>
    let density: MailDensity
    /// The mailbox's stripe: only when the list shows several mailboxes (lot 6, 19/11).
    let stripes: Bool
    let open: () -> Void
    @State private var hovering: Bool

    /// `hovering`: the line as under the pointer, for the captures.
    init(thread: MailThreadRow, mails: MailLibrary, mine: Set<String>, density: MailDensity, stripes: Bool, hovering: Bool = false,
         open: @escaping () -> Void) {
        self.thread = thread
        self.mails = mails
        self.mine = mine
        self.density = density
        self.stripes = stripes
        self.open = open
        _hovering = State(initialValue: hovering)
    }

    /// What the line says of Paul's drafts in the thread: « Brouillon » (grey: red says « late » only, design system
    /// v2, 19/11) while one is under way; « Programmé » (grey) when his reply waits for its time; « En retard » (the
    /// late's red, as in Programmés) when it waits for Paul.
    enum DraftMark: Equatable {
        case none, draft, planned, late
    }

    static func draftMark(_ drafts: [MailDraftRow], scheduled: [String: ScheduledSend]) -> DraftMark {
        guard !drafts.isEmpty else { return .none }
        if drafts.contains(where: { scheduled[$0.id] == nil }) { return .draft }
        return drafts.contains { scheduled[$0.id]?.state == .held } ? .late : .planned
    }

    var body: some View {
        let ticked = mails.selected.contains(thread.id)
        let files = density.showsFiles ? (mails.files[thread.id] ?? []) : []
        let ground = ticked ? MailSurface.ticked : (thread.unread ? MailSurface.unread : MailSurface.read)
        VStack(alignment: .leading, spacing: Space.s) {
            MailGridLine(stripe: stripes ? mails.color(for: thread.account) : nil, stripeHelp: thread.account) {
                Button { mails.select(thread.id, extend: NSEvent.modifierFlags.contains(.shift)) } label: {
                    Image(systemName: ticked ? "checkmark.square.fill" : "square")
                        .font(.system(size: 16))
                        .foregroundStyle(ticked ? MailSurface.accent : Color.secondary.opacity(0.75))
                        .frame(width: MailGrid.boxWidth, height: MailGrid.lineHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.hover(.rounded))
                .help("Sélectionner")
                .accessibilityLabel(ticked ? "Désélectionner" : "Sélectionner")
            } senders: {
                senders
            } subject: {
                HStack(spacing: Space.s) {
                    // No case from the trash or the spam (wave B).
                    if mails.folder.aside == nil { MailFilingChip(thread: thread, mails: mails) }
                    (Text(thread.subject.isEmpty ? "(sans objet)" : thread.subject).font(.rowTitle.weight(thread.unread ? .bold : .regular))
                        + Text(thread.snippet.isEmpty ? "" : " — \(thread.snippet)").font(.rowBody).foregroundStyle(.secondary))
                        .lineLimit(1)
                }
            } end: {
                HStack(spacing: Space.s) {
                    if thread.hasAttachment, files.isEmpty {
                        Image(systemName: "paperclip").font(.meta).foregroundStyle(.secondary)
                    }
                    Text(MailText.date(thread.lastMessageAt))
                        // The unread a step above, semibold: the bold of the line already says it (lot 6, 19/11).
                        .font(.meta.weight(thread.unread ? .semibold : .regular))
                        .foregroundStyle(thread.unread ? .primary : .secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .opacity(hovering ? 0 : 1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                // The gestures over the date's place, never over the subject: no gradient needed (lot 6, 19/11).
                .overlay(alignment: .trailing) {
                    if hovering { gestures }
                }
            }
            if !files.isEmpty {
                MailFileChips(files: files, mails: mails, more: open).padding(.leading, MailGrid.subjectStart)
            }
        }
        .padding(.vertical, density.padding)
        .padding(.trailing, MailGrid.trailing)
        .background {
            Rectangle().fill(ground)
                .overlay { if mails.focused == thread.id, !ticked { MailSurface.accent.opacity(0.07) } }
                // Gmail's shadow under the pointer stays (Paul's choice of 15/11, plan of 19/11).
                .shadow(color: .black.opacity(hovering ? 0.2 : 0), radius: hovering ? 3 : 0, y: hovering ? 1 : 0)
        }
        .overlay(alignment: .bottom) { MailLine() }
        .zIndex(hovering ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            if flags.contains(.command) || flags.contains(.shift) {
                mails.select(thread.id, extend: flags.contains(.shift))
            } else {
                open()
            }
        }
        .onHover { hovering = $0 }
        .contextMenu {
            ForEach(mails.folder.gestures(for: thread), id: \.self) { kind in
                Button(kind.title()) { mails.perform(kind, on: thread, undoable: kind.undoableAlone) }
            }
            Button(ticked ? "Désélectionner" : "Sélectionner") { mails.select(thread.id, extend: false) }
            Divider()
            // From the trash or the spam, only the way back and Gmail's own page (wave B).
            if mails.folder.aside == nil {
                Menu("Ranger dans") { MailFilingMenu(thread: thread, mails: mails) }
                if let sender = thread.lastSender {
                    Button("Tous les mails de cet expéditeur") { mails.showAll(from: sender) }
                }
                Button("Signaler comme spam") { mails.reportSpam(thread) }
                Divider()
            }
            Button("Ouvrir dans Gmail") { NSWorkspace.shared.open(mails.gmailURL(thread, in: mails.folder.aside)) }
        }
    }

    /// « Camille, moi 3 », and « Brouillon » in grey when Paul has one under way (Gmail writes it in red, but red now
    /// says « late » only: design system v2, 19/11); « Programmé » in grey when his reply waits for its time,
    /// « En retard » in the late's red when it waits for him (wave B). In « Envoyés », who Paul wrote to:
    /// « À : Camille, Jules » (15/11).
    private var senders: some View {
        let mark = Self.draftMark(mails.drafts.filter { $0.threadKey == thread.id }, scheduled: mails.scheduled)
        let weight: Font.Weight = thread.unread ? .bold : .regular
        let recipients = mails.folder == .sent && mails.found == nil ? (mails.sentTo[thread.id] ?? []) : []
        let names = recipients.isEmpty
            ? Text(MailText.names(thread, mine: mine)).font(.rowTitle.weight(weight))
            : Text("À : ").font(.rowTitle).foregroundStyle(.secondary) + Text(MailText.recipients(recipients, mine: mine)).font(.rowTitle.weight(weight))
        let markColor: Color = mark == .late ? Tint.late : .secondary
        return (names
            + Text(thread.messageCount > 1 ? " \(thread.messageCount)" : "").font(.meta).foregroundStyle(.secondary)
            + Text(mark == .draft ? ", Brouillon" : mark == .late ? ", En retard" : "").font(.rowTitle).foregroundStyle(markColor)
            + Text(mark == .planned ? ", Programmé" : "").font(.rowTitle).foregroundStyle(.secondary))
            .lineLimit(1)
    }

    /// Gmail's gestures under the pointer, in the end column, on the line's own ground: archive or bring back, delete,
    /// read, the case; in the trash or the spam, only the way back (wave B).
    private var gestures: some View {
        HStack(spacing: MailGrid.gestureSpacing) {
            ForEach(mails.folder.gestures(for: thread), id: \.self) { kind in
                IconButton(kind.icon, help: kind.title()) { mails.perform(kind, on: thread, undoable: kind.undoableAlone) }
            }
            if mails.folder.aside == nil {
                IconMenu("folder", help: "Ranger dans un projet ou une case") { MailFilingMenu(thread: thread, mails: mails) }
            }
        }
    }
}

/// The files of a thread under its line, as Gmail's « Par défaut »: three at most. A click shows the file in
/// Quick Look, without opening the thread (15/11); « +2 » opens the thread.
struct MailFileChips: View {
    let files: [MailListedFile]
    @ObservedObject var mails: MailLibrary
    let more: () -> Void

    var body: some View {
        HStack(spacing: Space.s) {
            ForEach(files.prefix(3)) { file in
                MailFileChip(file: file.attachment, opening: mails.opening.contains(file.id)) { mails.open(file) } save: { mails.save(file) }
            }
            if files.count > 3 {
                Button(action: more) {
                    Text("+\(files.count - 3)").font(.meta).foregroundStyle(.secondary)
                        .padding(.horizontal, Space.s).padding(.vertical, 5)
                }
                .buttonStyle(.hover(.capsule))
                .help("Ouvrir le fil et toutes ses pièces jointes")
            }
        }
    }

    /// « un-tres-long-nom…v2.pdf »: a chip keeps the size of its name, up to 28 characters.
    static func short(_ name: String) -> String {
        guard name.count > 28 else { return name }
        return String(name.prefix(18)) + "…" + String(name.suffix(9))
    }

    static func icon(_ file: MailAttachment) -> String {
        let name = file.filename.lowercased(), type = file.mimeType.lowercased()
        if type == "application/pdf" || name.hasSuffix(".pdf") { return "doc.richtext.fill" }
        if type.hasPrefix("image/") { return "photo.fill" }
        if ["xls", "xlsx", "csv", "numbers"].contains(where: { name.hasSuffix("." + $0) }) || type.contains("sheet") { return "tablecells.fill" }
        if ["zip", "rar", "7z"].contains(where: { name.hasSuffix("." + $0) }) { return "doc.zipper" }
        return "doc.text.fill"
    }
}

/// One file under a line: its icon (a wheel while it comes from Gmail), its name; a click previews it, or
/// saves what Polhub never opens (AttachmentSafety).
struct MailFileChip: View {
    let file: MailAttachment
    let opening: Bool
    let open: () -> Void
    let save: () -> Void

    var body: some View {
        let previews = AttachmentSafety.canOpen(name: file.filename)
        Button(action: open) {
            HStack(spacing: Space.s) {
                Group {
                    if opening {
                        ProgressView().controlSize(.mini)
                    } else {
                        // The symbol tells the kind of file; a color per kind was decoration, and red says « late »
                        // now (design system v2, 19/11): grey.
                        Image(systemName: MailFileChips.icon(file)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 16, height: 16)
                Text(MailFileChips.short(file.filename)).lineLimit(1)
            }
            .font(.meta)
            .padding(.horizontal, Space.m).padding(.vertical, 5)
            .fixedSize()
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.16)))
        }
        .buttonStyle(.hover(.capsule))
        .help(previews ? "Aperçu de \(file.filename) · \(MailText.size(file.size))"
            : "\(file.filename) · \(MailText.size(file.size)) : ce type de fichier ne s'ouvre pas dans Polhub, il s'enregistre")
        .contextMenu {
            if previews { Button("Aperçu", action: open) }
            Button("Enregistrer…", action: save)
        }
    }
}
