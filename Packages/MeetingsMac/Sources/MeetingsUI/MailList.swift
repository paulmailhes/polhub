import Agenda
import AppKit
import Mail
import MailFormat
import Persistence
import PolhubDesign
import ProjectsUI
import SwiftUI

/// The list, as Gmail's (Paul, 15/11: « il faut vraiment que tu calques ce qu'a fait Gmail »): a bar of
/// gestures, the tabs in the inbox, then one line per thread, the mailboxes together. Folders and mailboxes are
/// in the sidebar, under « Mails ».
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

    var body: some View {
        let mine = Set(mails.agenda.accounts.map(\.email))
        VStack(spacing: 0) {
            if mails.found == nil, mails.folder == .drafts {
                MailDraftListView(mails: mails, router: router)
            } else if mails.found == nil, mails.folder == .scheduled {
                MailScheduledListView(mails: mails, router: router)
            } else if mails.found == nil, mails.folder == .subscriptions {
                MailSubscriptionsView(mails: mails)
            } else {
                MailListBar(mails: mails)
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
                Button { mails.writeNewMail(router: router) } label: {
                    Label("Nouveau mail", systemImage: "square.and.pencil").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.glassProminent)
                .help("Écrire un nouveau mail (⌘N)")
            }
        }
        // One bar (15/11): the copy is filtered as Paul types; Enter also asks Gmail, which reads the bodies.
        .searchable(text: $mails.query, placement: .toolbar, prompt: "Chercher dans tes mails")
        .onSubmit(of: .search) { Task { await mails.search(mails.query) } }
        .windowTitle("Mails", subtitle: subtitle)
    }

    @ViewBuilder
    private func content(_ threads: [MailThreadRow], mine: Set<String>) -> some View {
        VStack(spacing: 0) {
            if let failure = mails.failure {
                HStack(spacing: Space.s) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text("\(AccountStyle.label(for: failure.account)) : \(failure.text)").foregroundStyle(.secondary).lineLimit(2)
                    Spacer(minLength: Space.m)
                    Button("Comptes Google") { router.openSettings(.accounts) }
                }
                .font(.meta)
                .padding(.horizontal, Space.xl).padding(.vertical, Space.m)
                .overlay(alignment: .bottom) { MailLine() }
            }
            if threads.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: mails.found != nil ? "magnifyingglass" : mails.folder.icon,
                                       description: Text(mails.found != nil || (mails.folder != .inbox && mails.folder != .notifications) ? "" : mails.tab.explanation))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list(threads, mine: mine)
            }
        }
    }

    private var emptyTitle: String {
        if mails.found != nil { return "Aucun mail trouvé" }
        if let aside = mails.folder.aside {
            if mails.readingAside { return "Lecture de Gmail…" }
            return aside == .spam ? "Aucun spam" : "Rien dans la corbeille"
        }
        if mails.progress != nil { return "Lecture de tes boîtes…" }
        return mails.unreadOnly ? "Aucun non lu" : "Rien ici"
    }

    private func list(_ threads: [MailThreadRow], mine: Set<String>) -> some View {
        let density = MailDensity(rawValue: density) ?? .defaut
        return ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: days ? .sectionHeaders : []) {
                    if days {
                        ForEach(MailText.sections(threads), id: \.title) { section in
                            Section {
                                rows(section.threads, mine: mine, density: density)
                            } header: {
                                Text(section.title)
                                    .font(.meta.weight(.semibold)).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, MailRow.boxEnd).padding(.trailing, Space.l)
                                    .padding(.top, Space.l).padding(.bottom, Space.s)
                                    .background(MailSurface.unread)
                                    .overlay(alignment: .bottom) { MailLine() }
                            }
                        }
                    } else {
                        rows(threads, mine: mine, density: density)
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

    private func rows(_ threads: [MailThreadRow], mine: Set<String>, density: MailDensity) -> some View {
        ForEach(threads) { thread in
            MailRow(thread: thread, mails: mails, mine: mine, density: density) { open(thread.id) }
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

/// The thin line between two threads, as Gmail's.
struct MailLine: View {
    var body: some View { Rectangle().fill(MailSurface.line).frame(height: 1) }
}

/// During a search, in place of the tabs: how many threads, and what Enter does (15/11).
struct MailSearchLine: View {
    let text: String
    let searching: Bool
    var icon = "magnifyingglass"

    var body: some View {
        HStack(spacing: Space.s) {
            if searching {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: icon).foregroundStyle(.secondary)
            }
            Text(text).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.meta)
        .frame(height: 20)
        .padding(.leading, MailRow.boxStart + 7).padding(.trailing, Space.l).padding(.vertical, Space.m)
        .overlay(alignment: .bottom) { MailLine() }
    }
}

/// Above the list, as Gmail's: the box that ticks every thread, then the gestures on the threads ticked, or
/// « Relever » and « Plus »; « Non lus » on the right.
struct MailListBar: View {
    @ObservedObject var mails: MailLibrary

    var body: some View {
        let shown = mails.shown
        let count = mails.selected.count
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
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        .frame(width: 18, height: 32)
                }
                .menuStyle(.button).buttonStyle(.hover(.capsule)).menuIndicator(.hidden).fixedSize()
                .help("Sélectionner les lus, les non lus")
            }
            .padding(.leading, MailRow.boxStart + 7)
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
                    if mails.folder == .inbox || mails.folder == .notifications, mails.found == nil {
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
            if mails.folder.aside == nil {
                Toggle(isOn: $mails.unreadOnly) {
                    Label("Non lus", systemImage: "line.3.horizontal.decrease")
                }
                .toggleStyle(.button)
                .help(mails.unreadOnly ? "Afficher tous les mails" : "N'afficher que les non lus")
                .padding(.trailing, Space.l)
            }
        }
        .frame(height: 48)
    }
}

/// One thread on one line, as Gmail's (Paul, 15/11): who, then the case, the subject and, lighter, the start of
/// the mail; the date at the end. Unread: on white, in bold; read: on blue-grey. The mailbox's color on the
/// left. Its files under it (« Par défaut »). On hover the gestures cover the date: nothing moves.
struct MailRow: View {
    let thread: MailThreadRow
    @ObservedObject var mails: MailLibrary
    let mine: Set<String>
    let density: MailDensity
    let open: () -> Void
    @State private var hovering = false

    static let sendersWidth: CGFloat = 210
    /// Where the box to tick starts, then where it ends: the bar above and the day titles line up on them.
    static let boxStart: CGFloat = Space.m + 3
    static let boxEnd: CGFloat = boxStart + 44
    /// Where the subject starts: the files line up under it.
    static let subjectStart: CGFloat = boxEnd + sendersWidth + Space.l

    /// What the line says of Paul's drafts in the thread: « Brouillon » (red) while one is under way; « Programmé »
    /// (grey) when his reply waits for its time; « En retard » (red, as in Programmés) when it waits for Paul.
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
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5).fill(mails.color(for: thread.account)).frame(width: 3, height: 22)
                    .padding(.leading, Space.m)
                    .help(thread.account)
                Button { mails.select(thread.id, extend: NSEvent.modifierFlags.contains(.shift)) } label: {
                    Image(systemName: ticked ? "checkmark.square.fill" : "square")
                        .font(.system(size: 16))
                        .foregroundStyle(ticked ? MailSurface.accent : Color.secondary.opacity(0.75))
                        .frame(width: 44, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.hover(.rounded))
                .help("Sélectionner")
                .accessibilityLabel(ticked ? "Désélectionner" : "Sélectionner")
                senders
                    .frame(width: Self.sendersWidth, alignment: .leading)
                    .padding(.trailing, Space.l)
                HStack(spacing: Space.s) {
                    // No case from the trash or the spam (wave B).
                    if mails.folder.aside == nil { MailFilingChip(thread: thread, mails: mails) }
                    (Text(thread.subject.isEmpty ? "(sans objet)" : thread.subject).font(.rowTitle.weight(thread.unread ? .bold : .regular))
                        + Text(thread.snippet.isEmpty ? "" : " — \(thread.snippet)").font(.rowBody).foregroundStyle(.secondary))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if thread.hasAttachment, files.isEmpty {
                    Image(systemName: "paperclip").font(.meta).foregroundStyle(.secondary).padding(.horizontal, Space.s)
                }
                Text(MailText.date(thread.lastMessageAt))
                    .font(.meta.weight(thread.unread ? .bold : .regular))
                    .foregroundStyle(thread.unread ? .primary : .secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(minWidth: 58, alignment: .trailing)
            }
            .overlay(alignment: .trailing) {
                if hovering { actions(over: ground) }
            }
            if !files.isEmpty {
                MailFileChips(files: files, mails: mails, more: open).padding(.leading, Self.subjectStart)
            }
        }
        .padding(.vertical, density.padding)
        .padding(.trailing, Space.l)
        .background {
            Rectangle().fill(ground)
                .overlay { if mails.focused == thread.id, !ticked { MailSurface.accent.opacity(0.07) } }
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

    /// « Camille, moi 3 », and « Brouillon » in red when Paul has one under way, as Gmail says it; « Programmé »
    /// in grey when his reply waits for its time, « En retard » in red when it waits for him (wave B). In
    /// « Envoyés », who Paul wrote to: « À : Camille, Jules » (15/11).
    private var senders: some View {
        let mark = Self.draftMark(mails.drafts.filter { $0.threadKey == thread.id }, scheduled: mails.scheduled)
        let weight: Font.Weight = thread.unread ? .bold : .regular
        let recipients = mails.folder == .sent && mails.found == nil ? (mails.sentTo[thread.id] ?? []) : []
        let names = recipients.isEmpty
            ? Text(MailText.names(thread, mine: mine)).font(.rowTitle.weight(weight))
            : Text("À : ").font(.rowTitle).foregroundStyle(.secondary) + Text(MailText.recipients(recipients, mine: mine)).font(.rowTitle.weight(weight))
        return (names
            + Text(thread.messageCount > 1 ? " \(thread.messageCount)" : "").font(.meta).foregroundStyle(.secondary)
            + Text(mark == .draft ? ", Brouillon" : mark == .late ? ", En retard" : "").font(.rowTitle).foregroundStyle(.red)
            + Text(mark == .planned ? ", Programmé" : "").font(.rowTitle).foregroundStyle(.secondary))
            .lineLimit(1)
    }

    /// Gmail's gestures on hover, over the end of the line, on its own ground.
    private func actions(over ground: Color) -> some View {
        HStack(spacing: 2) {
            // Archive or bring back, delete, read; in the trash or the spam, only the way back (wave B).
            ForEach(mails.folder.gestures(for: thread), id: \.self) { kind in
                IconButton(kind.icon, help: kind.title()) { mails.perform(kind, on: thread, undoable: kind.undoableAlone) }
            }
            if mails.folder.aside == nil {
                IconMenu("folder", help: "Ranger dans un projet ou une case") { MailFilingMenu(thread: thread, mails: mails) }
            }
        }
        .padding(.leading, Space.xxl)
        .background(LinearGradient(stops: [.init(color: ground.opacity(0), location: 0), .init(color: ground, location: 0.3)],
                                   startPoint: .leading, endPoint: .trailing))
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

    static func tint(_ file: MailAttachment) -> Color {
        switch icon(file) {
        case "doc.richtext.fill": Color(hex: Palette.red)
        case "photo.fill": Color(hex: Palette.violet)
        case "tablecells.fill": Color(hex: Palette.green)
        case "doc.zipper": .secondary
        default: Color(hex: Palette.blue)
        }
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
                        Image(systemName: MailFileChips.icon(file)).foregroundStyle(MailFileChips.tint(file))
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
