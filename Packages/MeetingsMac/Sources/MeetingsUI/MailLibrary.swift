import Agenda
import AppKit
import Combine
import Domain
import GRDB
import Mail
import Persistence
import PolhubDesign
import SwiftUI

/// The three tabs of the list (Paul, 14/11): what people wrote; what services send on their own; the
/// newsletters and promotions. Gmail's own categories decide, unless Paul moved a sender.
public enum MailTab: String, Hashable, Sendable, CaseIterable {
    case personnes, notifications, newsletters

    var title: String {
        switch self {
        case .personnes: "Personnes"
        case .notifications: "Notifications"
        case .newsletters: "Newsletters"
        }
    }

    /// What the tab holds, said where Paul sees it.
    var explanation: String {
        switch self {
        case .personnes: "Les mails écrits par des personnes : clients, collègues, proches."
        case .notifications: "Ce que des services envoient tout seuls : reçus, confirmations, alertes, rappels. Rien n'y attend de réponse."
        case .newsletters: "Les lettres d'information, les promotions et les réseaux sociaux."
        }
    }

    /// Gmail's category of a mail: notifications are Gmail's « Notifications », newsletters its « Promotions »
    /// and « Réseaux sociaux »; everything else (« Principale », « Forums », none) is people.
    static func of(category: String?) -> MailTab {
        switch category {
        case "updates": .notifications
        case "promotions", "social": .newsletters
        default: .personnes
        }
    }
}

/// When remote images load (Paul, 14/11): for the senders he knows, when he asks, or always.
public enum MailImages: String, Hashable, Sendable, CaseIterable {
    case connus, demander, afficher

    var title: String {
        switch self {
        case .connus: "Pour les expéditeurs connus"
        case .demander: "Toujours demander"
        case .afficher: "Tout afficher"
        }
    }
}

/// Passes the engine's news to the library once it exists.
final class MailArrivalRelay: @unchecked Sendable {
    var handler: (@MainActor ([MailMessageRow]) -> Void)?
}

/// The mails, for the window: what the copy holds, and Paul's gestures (14/11).
@MainActor
public final class MailLibrary: ObservableObject {
    /// The inbox of every mailbox, as the copy holds it.
    @Published public private(set) var inbox: [MailThreadRow] = []
    @Published public private(set) var cursors: [String: MailCursorRow] = [:]
    @Published public private(set) var senders: [String: MailSenderRow] = [:]
    @Published public var tab: MailTab = .personnes { didSet { selected = [] } }
    /// The mailboxes Paul hid from the list.
    @Published public var hidden: Set<String> { didSet { defaults.set(hidden.sorted(), forKey: Preferences.Key.mailHiddenAccounts) } }
    /// What a search found at Gmail's; `nil` out of a search.
    @Published public private(set) var found: [MailThreadRow]?
    @Published public private(set) var searching = false
    /// The threads ticked for a gesture on all of them at once.
    @Published public var selected: Set<String> = []
    /// The checkboxes show, even before a first tick.
    @Published public var selecting = false
    /// The line the arrow keys are on.
    @Published public var focused: String?
    /// The last gesture, while it can be undone: one line, one or several threads.
    @Published public private(set) var undoable: (text: String, gestures: [MailGestureRow])?
    @Published public var message: String?
    /// The new mails of the main tab, for the notifications (set by the app).
    public var onArrival: (([(threadKey: String, sender: String, subject: String)]) -> Void)?

    public let agenda: AgendaLibrary
    let store: MailStore
    let engine: MailEngine
    private let defaults: UserDefaults
    private var observations: [AnyDatabaseCancellable] = []
    private var subscriptions: Set<AnyCancellable> = []
    private var undoToken = 0
    /// The anchor of a ⇧-click.
    private var anchor: String?

    public init(agenda: AgendaLibrary, root: URL, defaults: UserDefaults = .standard, flavor: AppFlavor = .current) {
        self.agenda = agenda
        self.defaults = defaults
        self.store = MailStore(agenda.database)
        self.hidden = Set(defaults.stringArray(forKey: Preferences.Key.mailHiddenAccounts) ?? [])
        let relay = MailArrivalRelay()
        self.engine = MailEngine(database: agenda.database, root: root, sendFor: { [agenda] account in
            { build in try await agenda.mailSend(for: account)(build) }
        }, flavor: flavor, onNew: { rows in Task { @MainActor in relay.handler?(rows) } })
        relay.handler = { [weak self] rows in self?.arrived(rows) }
        observations = [
            store.observeInbox { [weak self] in self?.inbox = $0 },
            store.observeCursors { [weak self] rows in self?.cursors = Dictionary(uniqueKeysWithValues: rows.map { ($0.account, $0) }) },
            store.observeSenders { [weak self] in self?.senders = $0 },
        ]
    }

    /// Starts following the mailboxes that granted the mails, and keeps following as accounts come and go.
    /// Gmail is asked more often while the app is in front.
    public func start() {
        agenda.$accounts.sink { [weak self] accounts in
            guard let self else { return }
            let granted = accounts.filter(self.agenda.mailGranted).map(\.email)
            Task { await self.engine.follow(accounts: granted) }
        }
        .store(in: &subscriptions)
        for (name, front) in [(NSApplication.didBecomeActiveNotification, true), (NSApplication.didResignActiveNotification, false)] {
            NotificationCenter.default.publisher(for: name).sink { [weak self] _ in
                guard let self else { return }
                Task { await self.engine.setForeground(front) }
                if front { self.refresh() }
            }
            .store(in: &subscriptions)
        }
    }

    /// Asks Gmail what is new, now.
    public func refresh() {
        for account in accounts { Task { await engine.kick(account.email) } }
    }

    /// Mails just arrived in an inbox: those of the main tab are told.
    private func arrived(_ rows: [MailMessageRow]) {
        let told = rows.filter { tab(of: $0) == .personnes && !hidden.contains($0.account) }
            .map { (threadKey: $0.threadKey, sender: $0.sender?.display ?? "Nouveau mail", subject: $0.subject) }
        if !told.isEmpty { onArrival?(told) }
    }

    // MARK: - What the list shows

    /// The mailboxes: the accounts that granted the mails.
    public var accounts: [GoogleAccountRow] { agenda.accounts.filter(agenda.mailGranted) }

    /// The tab of a thread: a thread Paul wrote in is people's; a sender Paul moved stays where he put it;
    /// otherwise Gmail's category of the last mail received.
    public func tab(of thread: MailThreadRow) -> MailTab {
        if thread.paulWrote { return .personnes }
        if let chosen = thread.lastSender.flatMap({ senders[$0]?.tab }).flatMap(MailTab.init(rawValue:)) { return chosen }
        return MailTab.of(category: thread.category)
    }

    func tab(of message: MailMessageRow) -> MailTab {
        if let chosen = message.sender.flatMap({ senders[$0.email]?.tab }).flatMap(MailTab.init(rawValue:)) { return chosen }
        let label = message.labels.first { $0.hasPrefix("CATEGORY_") }
        return MailTab.of(category: label.map { String($0.dropFirst("CATEGORY_".count)).lowercased() })
    }

    /// Not written by a person: the notifications and the newsletters.
    public func isAutomatic(_ thread: MailThreadRow) -> Bool {
        tab(of: thread) != .personnes
    }

    private func visible(_ threads: [MailThreadRow]) -> [MailThreadRow] {
        threads.filter { !hidden.contains($0.account) }
    }

    /// The threads of the tab, or of the search under way.
    public var shown: [MailThreadRow] {
        if let found { return found }
        return visible(inbox).filter { tab(of: $0) == tab }
    }

    /// The unread threads of the people's tab: what waits for Paul.
    public var unreadCount: Int {
        visible(inbox).filter { $0.unread && tab(of: $0) == .personnes }.count
    }

    public func unread(in tab: MailTab) -> Int {
        visible(inbox).filter { $0.unread && self.tab(of: $0) == tab }.count
    }

    /// « Lecture de la boîte : 1 240 sur 6 000 », while a first reading is under way.
    public var progress: String? {
        let reading = accounts.compactMap { cursors[$0.email] }.filter { $0.finishedAt == nil && $0.total > 0 }
        guard !reading.isEmpty else { return nil }
        let done = reading.reduce(0) { $0 + $1.done }, total = reading.reduce(0) { $0 + $1.total }
        let format = IntegerFormatStyle<Int>.number.locale(Locale(identifier: "fr_FR"))
        return "Lecture \(reading.count > 1 ? "des boîtes" : "de la boîte") : \(done.formatted(format)) sur \(total.formatted(format))"
    }

    /// A mailbox that cannot be read, and why.
    public var failure: (account: String, text: String)? {
        accounts.compactMap { account in cursors[account.email]?.lastError.map { (account.email, $0) } }.first
    }

    public func color(for account: String) -> Color { agenda.color(for: account) }

    /// The thread before or after this one in the list shown.
    public func neighbor(of key: String, offset: Int) -> String? {
        let keys = shown.map(\.id)
        guard let index = keys.firstIndex(of: key), keys.indices.contains(index + offset) else { return nil }
        return keys[index + offset]
    }

    /// Where the thread stands in the list: « 3 sur 42 ».
    public func position(of key: String) -> String? {
        let keys = shown.map(\.id)
        return keys.firstIndex(of: key).map { "\($0 + 1) sur \(keys.count)" }
    }

    // MARK: - Selection

    /// A click with ⌘ ticks one more; with ⇧, every thread from the last one ticked.
    public func select(_ key: String, extend: Bool) {
        if extend, let anchor, let from = shown.firstIndex(where: { $0.id == anchor }), let to = shown.firstIndex(where: { $0.id == key }) {
            selected.formUnion(shown[min(from, to)...max(from, to)].map(\.id))
        } else if selected.contains(key) {
            selected.remove(key)
        } else {
            selected.insert(key)
        }
        anchor = key
    }

    public func selectAll() {
        selected = Set(shown.map(\.id))
        selecting = true
    }

    public func endSelection() {
        selected = []
        selecting = false
        anchor = nil
    }

    public var selectedThreads: [MailThreadRow] { shown.filter { selected.contains($0.id) } }

    // MARK: - Gestures

    private static func done(_ kind: MailGestureKind, count: Int) -> String {
        let plural = count > 1
        let what = plural ? "\(count) fils" : "Fil"
        switch kind {
        case .archive: return "\(what) archivé\(plural ? "s" : "")"
        case .unarchive: return "\(what) remis en boîte de réception"
        case .markRead: return plural ? "\(count) fils marqués comme lus" : "Marqué comme lu"
        case .markUnread: return plural ? "\(count) fils marqués comme non lus" : "Marqué comme non lu"
        case .trash: return "\(what) supprimé\(plural ? "s" : "")"
        case .untrash: return "\(what) rétabli\(plural ? "s" : "")"
        }
    }

    /// The gesture shows at once; Gmail follows. « Annuler » stays a few seconds, for all the threads at once.
    public func perform(_ kind: MailGestureKind, on threads: [MailThreadRow], undoable canUndo: Bool = true) {
        guard !threads.isEmpty else { return }
        Task {
            var made: [MailGestureRow] = []
            do {
                for thread in threads {
                    if let gesture = try await engine.perform(kind, threadKey: thread.id) { made.append(gesture) }
                }
            } catch {
                message = "Geste impossible : \(error)"
            }
            guard canUndo, !made.isEmpty else { return }
            undoToken += 1
            let token = undoToken
            undoable = (Self.done(kind, count: made.count), made)
            try? await Task.sleep(for: .seconds(8))
            if undoToken == token { undoable = nil }
        }
    }

    public func perform(_ kind: MailGestureKind, on thread: MailThreadRow, undoable canUndo: Bool = true) {
        perform(kind, on: [thread], undoable: canUndo)
    }

    /// The ticked threads; the selection ends.
    public func performOnSelection(_ kind: MailGestureKind) {
        let threads = selectedThreads
        perform(kind, on: threads, undoable: kind == .archive || kind == .trash || threads.count > 1)
        endSelection()
    }

    public func undo() {
        guard let gestures = undoable?.gestures else { return }
        undoable = nil
        Task {
            do { for gesture in gestures { try await engine.undo(gesture) } } catch { message = "Annulation impossible : \(error)" }
        }
    }

    /// Opening a thread reads it.
    public func markRead(_ thread: MailThreadRow) {
        guard thread.unread else { return }
        perform(.markRead, on: thread, undoable: false)
    }

    /// « Déplacer vers… » a tab: kept for the sender's next mails; `nil` gives it back to Gmail's category.
    public func move(_ thread: MailThreadRow, to tab: MailTab?) {
        guard let sender = thread.lastSender else { return }
        try? store.remember(address: sender, tab: .some(tab?.rawValue), at: Date())
        message = tab.map { "Les mails de \(sender) iront dans « \($0.title) »." } ?? "Les mails de \(sender) suivent de nouveau le classement de Gmail."
    }

    /// The thread in Gmail's own page, under its account.
    public func gmailURL(_ thread: MailThreadRow) -> URL {
        GmailLink.thread(thread.threadID, account: thread.account)
    }

    // MARK: - Search

    /// Paul's text goes to Gmail as he typed it, on the mailboxes shown.
    public func search(_ text: String) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            found = nil
            return
        }
        searching = true
        defer { searching = false }
        do {
            let keys = try await engine.search(query, accounts: accounts.map(\.email).filter { !hidden.contains($0) })
            found = try store.threads(keys: keys).filter { !$0.hidden }
        } catch {
            message = "Recherche impossible : \(error)"
        }
    }

    public func endSearch() {
        found = nil
    }

    // MARK: - Images

    public var imagesMode: MailImages {
        MailImages(rawValue: defaults.string(forKey: Preferences.Key.mailImages) ?? "") ?? .connus
    }

    /// Whether this message's remote images load without asking: its sender is known and Gmail confirmed the
    /// mail comes from him. Known: a contact, someone Paul wrote to in this thread, or « Toujours ».
    public func showsImages(of message: MailMessageRow, in thread: MailThreadRow) -> Bool {
        switch imagesMode {
        case .afficher: return true
        case .demander: return false
        case .connus:
            if message.labels.contains("SENT") { return true }
            guard message.authenticated, let sender = message.sender?.email else { return false }
            return senders[sender]?.images == true || thread.paulWrote || agenda.contact(email: sender) != nil
        }
    }

    /// « Toujours pour cet expéditeur ».
    public func alwaysShowImages(from sender: String) {
        try? store.remember(address: sender, images: true, at: Date())
    }
}
