import Agenda
import Persistence
import HubDesign
import SwiftUI

/// A row of the sidebar's list: a section, or one of the mails' folders under « Mails » (Paul, 15/11). Inspiration is one
/// row, its pages in its toolbar; Contacts and Réglages live at the bottom, apart from the list (lot 4, 19/11).
enum SidebarRow: Hashable {
    case section(SidebarItem)
    case mail(MailFolder)

    /// The row lit in the list of the work: the folder shown under « Mails » open, « Mails » itself when closed; none
    /// for Contacts and Réglages, which have their rows at the bottom.
    static func selected(section: SidebarItem, folder: MailFolder?, mailsOpen: Bool) -> SidebarRow? {
        switch section {
        case .settings, .contacts: nil
        case .mails: (mailsOpen ? folder : nil).map(SidebarRow.mail) ?? .section(.mails)
        default: .section(section)
        }
    }

    /// « Plus » unfolded: as Paul left it, and always on the folder shown, so that the folder open is in sight (lot 4,
    /// 19/11).
    static func moreOpen(stored: Bool, section: SidebarItem, folder: MailFolder?) -> Bool {
        stored || (section == .mails && folder?.isMore == true)
    }
}

/// A line of the sidebar's list, top to bottom (21/11: the list is drawn by hand, from these lines).
enum SidebarLine: Hashable {
    case section(SidebarItem)
    case folder(MailFolder)
    /// « Plus », which unfolds the rarer folders.
    case more

    /// The sections; under « Mails » open, its three folders and « Plus », then the others while « Plus » is open.
    static func lines(items: [SidebarItem], hasMails: Bool, mailsOpen: Bool, moreOpen: Bool, showingScheduled: Bool) -> [SidebarLine] {
        items.flatMap { item -> [SidebarLine] in
            guard item == .mails, hasMails, mailsOpen else { return [.section(item)] }
            return [.section(.mails)] + MailFolder.sidebar.map(SidebarLine.folder) + [.more]
                + (moreOpen ? MailFolder.more(showingScheduled: showingScheduled).map(SidebarLine.folder) : [])
        }
    }
}

extension MailFolder {
    /// Under « Mails », always (lot 4, 19/11: « Mails court »): the three Paul goes to.
    static let sidebar: [MailFolder] = [.inbox, .drafts, .sent]
    /// Under « Plus »: the rarer ones, Programmés only while a mail waits there (wave B).
    static let more: [MailFolder] = [.notifications, .subscriptions, .scheduled, .spam, .trash, .all]

    static func more(showingScheduled: Bool) -> [MailFolder] {
        more.filter { $0 != .scheduled || showingScheduled }
    }

    var isMore: Bool { Self.more.contains(self) }
}

/// The counts of the sidebar (15/11).
enum SidebarCounts {
    /// Calendrier: today's events not over yet, the one under way included; neither whole days nor declined ones.
    static func eventsLeftToday(_ events: [CalendarEventRow], now: Date, calendar: Calendar = .current) -> Int {
        events.filter { event in
            !event.allDay && event.endAt > now && calendar.isDate(event.startAt, inSameDayAs: now)
                && event.attendees.first(where: \.isSelf)?.response != "declined"
        }
        .count
    }
}

extension MailLibrary {
    /// « Nouveau mail » and ⌘N: the mail being written is kept (or dropped when blank) before a new one opens
    /// over Mails; two clicks never leave an empty draft behind (15/11).
    func writeNewMail(router: WindowRouter) {
        closeComposer()
        newMail()
        router.section = .mails
    }

    /// A folder, from the top: no thread open over it, no search left from before. The sidebar's rows and ⌘5 (lot 4,
    /// 19/11).
    func show(_ folder: MailFolder, router: WindowRouter) {
        router.section = .mails
        router.mailSelection = nil
        if !query.isEmpty { query = "" }
        endSearch()
        self.folder = folder
    }
}

/// The sidebar, one for every window (lot 4, 19/11: « Mails court »): the sections of the work, « Mails » open on three
/// folders and « Plus », Inspiration on one row; Contacts and Réglages at the bottom. Larger rows, a badge per section.
/// The notifications' bell is up in the toolbar, beside the sidebar's button.
///
/// Its rows are drawn by hand since 21/11 (Paul: « Boîte de réception, Brouillons… encore en orange quand je rentre dans
/// Mail… il faut l'enlever »): a native list lit the row chosen in the Mac's accent color whenever it had the focus, and
/// nothing in SwiftUI changes that color. The row shown is now a soft grey, focus or not, as Contacts and Réglages at the
/// bottom always were.
struct Sidebar: View {
    @ObservedObject var router: WindowRouter
    @ObservedObject var library: MeetingLibrary
    let agenda: AgendaLibrary?
    let mails: MailLibrary?
    let items: [SidebarItem]
    /// The rows at the bottom: Contacts (with the agenda), then Réglages.
    var footer: [SidebarItem] = [.settings]
    /// Vigie, when installed (21/11): its row counts what waits for Paul.
    var vigie: VigieLibrary?
    @AppStorage(Preferences.Key.mailSidebarOpen) private var mailsOpen = true
    @AppStorage(Preferences.Key.mailMoreOpen) private var moreOpen = false

    var body: some View {
        // Contacts and Réglages at the bottom, apart from the work (Paul, 14/11 and 15/11; lot 4, 19/11), BELOW the list
        // rather than over it: no row can run under them, seen through or blurred (Paul, 15/11: « pas bien aligné »).
        VStack(spacing: 0) {
            Group {
                if let mails {
                    Observing(mails) { list(mails: $0) }
                } else {
                    list(mails: nil)
                }
            }
            SidebarFooter(router: router, items: footer) { item in
                router.show(item, mails: mails)
            }
        }
    }

    private func list(mails: MailLibrary?) -> some View {
        let selected = SidebarRow.selected(section: router.section, folder: mails?.folder, mailsOpen: mailsOpen)
        let more = SidebarRow.moreOpen(stored: moreOpen, section: router.section, folder: mails?.folder)
        let lines = SidebarLine.lines(items: items, hasMails: mails != nil, mailsOpen: mailsOpen, moreOpen: more,
                                      showingScheduled: mails?.showsScheduled ?? false)
        return ScrollView {
            VStack(alignment: .leading, spacing: SidebarFooterMetrics.rowGap) {
                ForEach(lines, id: \.self) { line in
                    switch line {
                    case .section(.mails):
                        if let mails { mailsRow(mails, selected: selected) }
                    case .section(let item):
                        SidebarRowButton(selected: selected == .section(item), help: SidebarLabel.help(item)) {
                            router.show(item, mails: mails)
                        } label: {
                            label(item)
                        }
                    case .folder(let folder):
                        if let mails { folderRow(folder, in: mails, selected: selected) }
                    case .more:
                        moreRow(open: more)
                    }
                }
            }
            .padding(.horizontal, SidebarFooterMetrics.listInset)
            .padding(.vertical, Space.s)
        }
        .scrollIndicators(.never)
    }

    @ViewBuilder
    private func label(_ item: SidebarItem) -> some View {
        switch item {
        case .calendar:
            if let agenda {
                CalendarSidebarLabel(agenda: agenda)
            } else {
                SidebarLabel(item: item)
            }
        case .meetings:
            SidebarLabel(item: item, recording: library.meetingActive)
        case .vigie:
            if let vigie {
                Observing(vigie) { SidebarLabel(item: item, count: $0.waiting.count) }
            } else {
                SidebarLabel(item: item)
            }
        default:
            SidebarLabel(item: item)
        }
    }

    /// « Mails » (lot 4, 19/11; Paul, 15/11: « quand on clique dessus on a des sous-menus : boîte de réception,
    /// envoyés… »): open on Boîte de réception, Brouillons and Envoyés, then « Plus » on the others. The boxes are a menu of
    /// the list's bar; « Nouveau mail » is in its toolbar. A click on « Mails » opens it and shows its folder; its arrow
    /// only folds or unfolds it.
    private func mailsRow(_ mails: MailLibrary, selected: SidebarRow?) -> some View {
        ZStack(alignment: .trailing) {
            SidebarRowButton(selected: selected == .section(.mails), help: SidebarLabel.help(.mails)) {
                router.show(.mails, mails: mails)
                mailsOpen = true
            } label: {
                SidebarLabel(item: .mails, count: mailsOpen ? 0 : mails.unreadCount, room: SidebarFooterMetrics.arrowRoom)
            }
            Button { mailsOpen.toggle() } label: {
                Image(systemName: mailsOpen ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: SidebarFooterMetrics.arrowRoom, height: SidebarFooterMetrics.rowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help(mailsOpen ? "Replier Mails" : "Déplier Mails")
        }
    }

    /// « Plus »: not a place, a click unfolds it; it stays unfolded on a folder of its own shown.
    private func moreRow(open: Bool) -> some View {
        // « Verbe + objet »: « Voir » unfolds in place, « Voir moins » folds back (lot 10, 20/11).
        SidebarRowButton(selected: false, help: open ? "Voir moins" : "Voir les autres dossiers") {
            moreOpen = !open
        } label: {
            SidebarFolderLabel(title: "Plus", icon: .more) {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// A folder, under « Mails »: its name keeps whole in 224 points, a hair smaller if it must.
    private func folderRow(_ folder: MailFolder, in mails: MailLibrary, selected: SidebarRow?) -> some View {
        SidebarRowButton(selected: selected == .mail(folder), help: folder.title) {
            mails.show(folder, router: router)
            mailsOpen = true
        } label: {
            SidebarFolderLabel(title: folder.title, icon: folder.appIcon) {
                let count = count(folder, in: mails)
                if count > 0 { SidebarCount(count) }
            }
        }
    }

    private func count(_ folder: MailFolder, in mails: MailLibrary) -> Int {
        switch folder {
        case .inbox: mails.unreadCount
        case .notifications: mails.unread(in: .notifications)
        case .drafts: mails.draftCount
        case .scheduled: mails.scheduledDrafts.count
        default: 0
        }
    }
}

/// A row of the sidebar: the whole width answers; a soft grey under the pointer, a stronger one when it is the page
/// shown — never the Mac's accent color, and no focus ring.
struct SidebarRowButton<Label: View>: View {
    let selected: Bool
    let help: String
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: action) { label() }
            .buttonStyle(SidebarRowButtonStyle(selected: selected))
            .focusEffectDisabled()
            .help(help)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A section's row: its badge, its name, its count or a red dot while a meeting records.
struct SidebarLabel: View {
    let item: SidebarItem
    var count = 0
    var recording = false
    /// Room kept free on the right, for « Mails »' arrow.
    var room: CGFloat = 0

    var body: some View {
        HStack(spacing: SidebarFooterMetrics.iconGap) {
            // Its badge, as everywhere (21/11, Paul: « utiliser plus ce système de couleurs… dans les icônes sur la gauche »).
            ToolBadge(item.appIcon, color: item.tint, size: .sidebar)
            Text(item.title).font(SidebarFooterMetrics.font).lineLimit(1)
            Spacer(minLength: Space.xs)
            if recording {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    // The red of the recording, its only meaning (design system v2, 19/11).
                    .foregroundStyle(Tint.recording)
                    .symbolEffect(.pulse)
                    .help("Enregistrement en cours")
                    .accessibilityLabel("Enregistrement en cours")
            } else if count > 0 {
                SidebarCount(count)
            }
        }
        .padding(.leading, SidebarFooterMetrics.rowPadding)
        .padding(.trailing, SidebarFooterMetrics.rowPadding + room)
        .frame(height: SidebarFooterMetrics.rowHeight)
        .contentShape(Rectangle())
    }

    /// The row's key in its help (lot 4, 19/11): « Calendrier (⌘4) », « Réglages (⌘,) », written by `Words.help` (lot 10,
    /// 20/11).
    static func help(_ item: SidebarItem) -> String {
        if item == .settings { return Words.help("Réglages", .command(",")) }
        return item.shortcut.map { Words.help(item.title, .command("\($0)")) } ?? item.title
    }
}

/// A folder's row under « Mails »: its grey glyph under « Mails »' name, its name, then what it shows on the right.
struct SidebarFolderLabel<Trailing: View>: View {
    let title: String
    let icon: AppIcon
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: SidebarFooterMetrics.iconGap) {
            AppIconImage(icon, size: SidebarFooterMetrics.folderIcon)
                .foregroundStyle(.secondary)
            // A step smaller than the sections: the folders sit under « Mails », and « Boîte de réception » keeps whole
            // beside its count.
            HStack(spacing: Space.xs) {
                Text(title).font(.rowBody).lineLimit(1).minimumScaleFactor(0.85).allowsTightening(true)
                Spacer(minLength: Space.xs)
                trailing()
            }
        }
        .padding(.leading, SidebarFooterMetrics.rowPadding + SidebarFooterMetrics.folderIndent)
        .padding(.trailing, SidebarFooterMetrics.rowPadding)
        .frame(height: SidebarFooterMetrics.rowHeight)
        .contentShape(Rectangle())
    }
}

/// A count on the right of a row: unread mails, events left today, what waits in Vigie.
struct SidebarCount: View {
    let count: Int

    init(_ count: Int) {
        self.count = count
    }

    var body: some View {
        Text("\(count)").font(.meta.monospacedDigit()).foregroundStyle(.secondary)
    }
}

/// Calendrier and what is left of the day; the count follows the clock.
struct CalendarSidebarLabel: View {
    @ObservedObject var agenda: AgendaLibrary
    @State private var now = Date()

    var body: some View {
        SidebarLabel(item: .calendar, count: SidebarCounts.eventsLeftToday(agenda.shown, now: now))
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    now = Date()
                }
            }
    }
}

/// Contacts and Réglages, at the bottom (lot 4, 19/11), drawn as the rows above. Clicking Réglages again goes back to
/// the families.
struct SidebarFooter: View {
    @ObservedObject var router: WindowRouter
    let items: [SidebarItem]
    let open: (SidebarItem) -> Void

    init(router: WindowRouter, items: [SidebarItem] = [.settings], open: @escaping (SidebarItem) -> Void) {
        self.router = router
        self.items = items
        self.open = open
    }

    var body: some View {
        VStack(spacing: 0) {
            // A line across the whole sidebar, with room above and below: the bottom sits apart from the work
            // (Paul, 15/11: « la barre un peu plus haut, un bel alignement »).
            Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
            VStack(spacing: SidebarFooterMetrics.rowGap) {
                ForEach(items, id: \.self) { item in
                    SidebarRowButton(selected: router.section == item, help: SidebarLabel.help(item)) {
                        open(item)
                    } label: {
                        SidebarLabel(item: item)
                    }
                }
            }
            .padding(.horizontal, SidebarFooterMetrics.listInset)
            .padding(.top, Space.m)
            .padding(.bottom, Space.m + 2)
        }
    }
}

/// A row of the sidebar drawn by hand, as the native ones: a soft grey under the pointer, a stronger one when it is
/// the page shown.
struct SidebarRowButtonStyle: ButtonStyle {
    let selected: Bool
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(Color.primary.opacity(configuration.isPressed ? 0.12 : selected ? 0.09 : hovering ? 0.05 : 0),
                        in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

enum SidebarFooterMetrics {
    /// The sidebar's margin on each side, then a row's padding before its badge (measured on 15/11, macOS 27).
    static let listInset: CGFloat = 10
    static let rowPadding: CGFloat = 10
    static let iconGap: CGFloat = 9
    /// A row of the sidebar and its text.
    static let rowHeight: CGFloat = 36
    static let rowGap: CGFloat = 2
    static let font = Font.system(size: 15)
    /// A folder under « Mails »: its glyph a little smaller than a badge, under « Mails »' name, as the list drew it.
    static let folderIcon: CGFloat = 20
    static let folderIndent: CGFloat = 30
    /// The room of « Mails »' arrow, on the right of its row.
    static let arrowRoom: CGFloat = 22
}

/// Draws `content` again whenever `object` changes: a view can follow an object it may not have.
struct Observing<Object: ObservableObject, Content: View>: View {
    @ObservedObject var object: Object
    let content: (Object) -> Content

    init(_ object: Object, @ViewBuilder content: @escaping (Object) -> Content) {
        self.object = object
        self.content = content
    }

    var body: some View { content(object) }
}
