import Agenda
import Persistence
import PolhubDesign
import SwiftUI

/// A row of the sidebar: a section, or one of the mails' folders under « Mails » (Paul, 15/11).
enum SidebarRow: Hashable {
    case section(SidebarItem)
    case mail(MailFolder)

    /// The row lit in the list of the work: the folder shown under « Mails » open, « Mails » itself when closed;
    /// none for Réglages, which has its own row at the bottom.
    static func selected(section: SidebarItem, folder: MailFolder?, mailsOpen: Bool) -> SidebarRow? {
        switch section {
        case .settings: nil
        case .mails: (mailsOpen ? folder : nil).map(SidebarRow.mail) ?? .section(.mails)
        default: .section(section)
        }
    }
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
}

/// The sidebar, one for every window: the sections of the work, « Mails » open on its folders when there are
/// mails, Réglages at the bottom (Paul, 14/11 and 15/11). Larger rows, a color per section, as Mail's and the
/// Finder's.
struct Sidebar: View {
    @ObservedObject var router: WindowRouter
    @ObservedObject var library: MeetingLibrary
    let agenda: AgendaLibrary?
    let mails: MailLibrary?
    let items: [SidebarItem]
    @AppStorage(Preferences.Key.mailSidebarOpen) private var mailsOpen = true

    var body: some View {
        Group {
            if let mails {
                Observing(mails) { list(mails: $0) }
            } else {
                list(mails: nil)
            }
        }
        // Réglages at the bottom, apart from the work (Paul, 14/11), drawn as the rows above (15/11), and lined up with
        // them: the « Mails » group moves the rows above to the right (correctifs, 15/11). A bar, not an inset: when the
        // rows run longer than the window (« Spam » and « Corbeille », wave B), they scroll under it behind the
        // system's edge effect instead of showing through.
        .safeAreaBar(edge: .bottom, spacing: 0) { SidebarFooter(router: router, indent: mails != nil ? SidebarFooterMetrics.outlineIndent : 0) }
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
            case .section(.mails)?:
                if let mails { show(.inbox, in: mails) } else { router.section = .mails }
            case .section(let item)?: router.section = item
            case .mail(let folder)?: if let mails { show(folder, in: mails) }
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

    /// « Mails » open on Gmail's folders (Paul, 15/11: « quand on clique dessus on a des sous-menus : boîte de
    /// réception, envoyés… »), then the mailboxes to show or hide. « Nouveau mail » is in the toolbar of Mails
    /// (Paul, 15/11: not in the sidebar).
    private func mailsGroup(_ mails: MailLibrary) -> some View {
        DisclosureGroup(isExpanded: $mailsOpen) {
            // « Programmés » only while a mail waits there, as Gmail's (wave B).
            ForEach(MailFolder.allCases.filter { $0 != .scheduled || mails.showsScheduled }, id: \.self) { folder in
                Label(folder.title, systemImage: folder.icon)
                    .listItemTint(.monochrome)
                    .badge(count(folder, in: mails))
                    .tag(SidebarRow.mail(folder))
            }
            if mails.accounts.count > 1 {
                Text("Boîtes").font(.meta.weight(.semibold)).foregroundStyle(.secondary).padding(.top, Space.s)
                ForEach(mails.accounts) { account in box(account.email, in: mails) }
            }
        } label: {
            SidebarLabel(item: .mails, count: mailsOpen ? 0 : mails.unreadCount).tag(SidebarRow.section(.mails))
        }
    }

    /// A folder, from the top: no thread open over it, no search left from before.
    private func show(_ folder: MailFolder, in mails: MailLibrary) {
        router.section = .mails
        router.mailSelection = nil
        if !mails.query.isEmpty { mails.query = "" }
        mails.endSearch()
        mails.folder = folder
        mailsOpen = true
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

    /// A mailbox, ticked in its color when the list shows it, as the calendars in Apple's Calendar.
    private func box(_ email: String, in mails: MailLibrary) -> some View {
        let shown = !mails.hidden.contains(email)
        return Button {
            if shown { mails.hidden.insert(email) } else { mails.hidden.remove(email) }
        } label: {
            Label {
                Text(AccountStyle.label(for: email)).foregroundStyle(shown ? Color.primary : Color.secondary).lineLimit(1)
            } icon: {
                Image(systemName: shown ? "checkmark.square.fill" : "square").foregroundStyle(mails.color(for: email))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.hover(.rounded))
        .help(shown ? "\(email) — cliquer pour masquer cette boîte" : "\(email) — masquée, cliquer pour l'afficher")
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
                        .foregroundStyle(.red)
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
    }

    private var label: some View {
        Label(item.title, systemImage: item.icon).symbolRenderingMode(.hierarchical)
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

/// Réglages, at the bottom: a list of its own, so its row looks and answers as the rows of the work above.
/// Clicking it again goes back to the families.
struct SidebarFooter<Accessory: View>: View {
    @ObservedObject var router: WindowRouter
    /// How far the rows of the work move right once the list holds a group that opens (« Mails »): the room of
    /// its disclosure arrow, which this list has not (measured on 15/11, macOS 27: 9 points).
    var indent: CGFloat = 0
    /// What sits beside Réglages, on the right (the notifications, 0.17.1).
    let accessory: Accessory
    /// A large row (40 points) and room above and below for its highlight (Paul, 15/11: the bar was too low and
    /// cut the hover).
    static var height: CGFloat { 64 }

    init(router: WindowRouter, indent: CGFloat = 0, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.router = router
        self.indent = indent
        self.accessory = accessory()
    }

    var body: some View {
        VStack(spacing: 0) {
            // A line across the whole sidebar sets Réglages (and what will join it) apart from the work.
            Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
            HStack(spacing: 0) {
                List(selection: Binding { router.section == .settings ? SidebarItem.settings : nil } set: { item in
                    if item == .settings { router.openSettings(nil) }
                }) {
                    SidebarLabel(item: .settings)
                        .padding(.leading, indent)
                        .tag(SidebarItem.settings)
                        .simultaneousGesture(TapGesture().onEnded { router.openSettings(nil) })
                }
                .listStyle(.sidebar)
                .scrollDisabled(true)
                .scrollContentBackground(.hidden)
                .contentMargins(.vertical, 12, for: .scrollContent)
                accessory.padding(.trailing, Space.m)
            }
            .frame(height: Self.height)
        }
    }
}

enum SidebarFooterMetrics {
    static let outlineIndent: CGFloat = 9
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
