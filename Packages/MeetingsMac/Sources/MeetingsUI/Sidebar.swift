import Agenda
import Persistence
import PolhubDesign
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
/// folders and « Plus », Inspiration on one row; Contacts and Réglages at the bottom. Larger rows, a color per section,
/// as Mail's and the Finder's. The notifications' bell is up in the toolbar, beside the sidebar's button.
struct Sidebar: View {
    @ObservedObject var router: WindowRouter
    @ObservedObject var library: MeetingLibrary
    let agenda: AgendaLibrary?
    let mails: MailLibrary?
    let items: [SidebarItem]
    /// The rows at the bottom: Contacts (with the agenda), then Réglages.
    var footer: [SidebarItem] = [.settings]
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
            SidebarFooter(router: router, indent: mails != nil ? SidebarFooterMetrics.outlineIndent : 0, items: footer) { item in
                router.show(item, mails: mails)
            }
        }
        .environment(\.sidebarRowSize, .large)
    }

    private func list(mails: MailLibrary?) -> some View {
        List(selection: selection(mails)) {
            ForEach(items, id: \.self) { item in
                if item == .mails, let mails {
                    mailsGroup(mails)
                } else {
                    row(item)
                }
            }
        }
    }

    private func selection(_ mails: MailLibrary?) -> Binding<SidebarRow?> {
        Binding {
            SidebarRow.selected(section: router.section, folder: mails?.folder, mailsOpen: mailsOpen)
        } set: { row in
            switch row {
            case .section(let item)?:
                router.show(item, mails: mails)
                if item == .mails { mailsOpen = true }
            case .mail(let folder)?:
                guard let mails else { return }
                mails.show(folder, router: router)
                mailsOpen = true
            case nil: break
            }
        }
    }

    @ViewBuilder
    private func row(_ item: SidebarItem) -> some View {
        switch item {
        case .calendar:
            if let agenda {
                CalendarSidebarLabel(agenda: agenda).tag(SidebarRow.section(item))
            } else {
                SidebarLabel(item: item).tag(SidebarRow.section(item))
            }
        case .meetings:
            SidebarLabel(item: item, recording: library.meetingActive).tag(SidebarRow.section(item))
        default:
            SidebarLabel(item: item).tag(SidebarRow.section(item))
        }
    }

    /// « Mails » open on Boîte de réception, Brouillons and Envoyés, then « Plus » on the others (lot 4, 19/11; Paul,
    /// 15/11: « quand on clique dessus on a des sous-menus : boîte de réception, envoyés… »). The boxes are a menu of the
    /// list's bar; « Nouveau mail » is in its toolbar (Paul, 15/11: not in the sidebar).
    private func mailsGroup(_ mails: MailLibrary) -> some View {
        let more = SidebarRow.moreOpen(stored: moreOpen, section: router.section, folder: mails.folder)
        return DisclosureGroup(isExpanded: $mailsOpen) {
            ForEach(MailFolder.sidebar, id: \.self) { folder in folderRow(folder, in: mails) }
            // « Plus » unfolds the others under it, at the same depth, as Gmail's: a third depth cut their names in a
            // sidebar of 224 points.
            moreRow(open: more)
            if more {
                ForEach(MailFolder.more(showingScheduled: mails.showsScheduled), id: \.self) { folder in folderRow(folder, in: mails) }
            }
        } label: {
            SidebarLabel(item: .mails, count: mailsOpen ? 0 : mails.unreadCount).tag(SidebarRow.section(.mails))
        }
    }

    /// « Plus »: not a place, a click unfolds it; it stays unfolded on a folder of its own shown.
    private func moreRow(open: Bool) -> some View {
        Button { moreOpen = !open } label: {
            HStack(spacing: Space.s) {
                AppLabel("Plus", icon: .more)
                Spacer(minLength: 0)
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listItemTint(.monochrome)
        // « Verbe + objet »: « Voir » unfolds in place, « Voir moins » folds back (lot 10, 20/11; the folders' list was no
        // verb).
        .help(open ? "Voir moins" : "Voir les autres dossiers")
    }

    /// A folder: its name keeps whole in 224 points, a hair smaller if it must (« Boîte de réception » and its count).
    private func folderRow(_ folder: MailFolder, in mails: MailLibrary) -> some View {
        Label {
            Text(folder.title).lineLimit(1).minimumScaleFactor(0.85).allowsTightening(true)
        } icon: {
            AppIconImage(folder.appIcon, size: AppLabel.sidebarSize)
        }
        .listItemTint(.monochrome)
        .badge(count(folder, in: mails))
        .tag(SidebarRow.mail(folder))
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

/// A section's row: its symbol in its color, its count, a red dot while a meeting records.
struct SidebarLabel: View {
    let item: SidebarItem
    var count = 0
    var recording = false

    var body: some View {
        Group {
            if recording {
                HStack(spacing: Space.s) {
                    label
                    Spacer(minLength: 0)
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        // The red of the recording, its only meaning (design system v2, 19/11).
                        .foregroundStyle(Tint.recording)
                        .symbolEffect(.pulse)
                        .help("Enregistrement en cours")
                        .accessibilityLabel("Enregistrement en cours")
                }
            } else {
                label
            }
        }
        .listItemTint(.fixed(Color(hex: item.tint)))
        .badge(count)
        .help(Self.help(item))
    }

    private var label: some View {
        AppLabel(item.title, icon: item.appIcon)
    }

    /// The row's key in its help (lot 4, 19/11): « Calendrier (⌘4) », « Réglages (⌘,) », written by `Words.help` (lot 10,
    /// 20/11).
    static func help(_ item: SidebarItem) -> String {
        if item == .settings { return Words.help("Réglages", .command(",")) }
        return item.shortcut.map { Words.help(item.title, .command("\($0)")) } ?? item.title
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

/// Contacts and Réglages, at the bottom (lot 4, 19/11): drawn by hand, they look and answer as the rows of the list
/// above. Clicking Réglages again goes back to the families.
struct SidebarFooter: View {
    @ObservedObject var router: WindowRouter
    /// How far the rows of the work move right once the list holds a group that opens (« Mails »): the room of
    /// its disclosure arrow (measured on 15/11, macOS 27: 9 points).
    var indent: CGFloat = 0
    let items: [SidebarItem]
    let open: (SidebarItem) -> Void

    init(router: WindowRouter, indent: CGFloat = 0, items: [SidebarItem] = [.settings], open: @escaping (SidebarItem) -> Void) {
        self.router = router
        self.indent = indent
        self.items = items
        self.open = open
    }

    var body: some View {
        VStack(spacing: 0) {
            // A line across the whole sidebar, with room above and below: the bottom sits apart from the work
            // (Paul, 15/11: « la barre un peu plus haut, un bel alignement »).
            Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
            VStack(spacing: Space.xs) {
                ForEach(items, id: \.self) { item in
                    Button { open(item) } label: {
                        HStack(spacing: SidebarFooterMetrics.iconGap) {
                            AppIconImage(item.appIcon, size: AppLabel.sidebarSize)
                                .foregroundStyle(Color(hex: item.tint))
                            Text(item.title).font(SidebarFooterMetrics.font)
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, SidebarFooterMetrics.rowPadding + indent)
                        .frame(height: SidebarFooterMetrics.rowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SidebarRowButtonStyle(selected: router.section == item))
                    .help(SidebarLabel.help(item))
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
    static let outlineIndent: CGFloat = 9
    /// The list's own margin on each side, then a row's padding before its icon (measured on 15/11, macOS 27).
    static let listInset: CGFloat = 10
    static let rowPadding: CGFloat = 10
    static let iconGap: CGFloat = 6
    /// A large row of the sidebar and its text.
    static let rowHeight: CGFloat = 36
    static let font = Font.system(size: 15)
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
