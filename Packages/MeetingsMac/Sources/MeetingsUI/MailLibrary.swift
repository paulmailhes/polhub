import Agenda
import AppKit
import Combine
import Domain
import GRDB
import Mail
import Persistence
import PolhubDesign
import SwiftUI

/// The two tabs of the list (Paul, 14/11): the people and the projects; the automatic mails.
public enum MailTab: String, Hashable, Sendable, CaseIterable {
    case principale, automatiques

    var title: String {
        switch self {
        case .principale: "Principale"
        case .automatiques: "Automatiques"
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

/// The mails, for the window: what the copy holds, and Paul's gestures (14/11).
@MainActor
public final class MailLibrary: ObservableObject {
    /// The inbox of every mailbox, as the copy holds it.
    @Published public private(set) var inbox: [MailThreadRow] = []
    @Published public private(set) var cursors: [String: MailCursorRow] = [:]
    @Published public private(set) var senders: [String: MailSenderRow] = [:]
    @Published public var tab: MailTab = .principale
    /// The mailboxes Paul hid from the list.
    @Published public var hidden: Set<String> { didSet { defaults.set(hidden.sorted(), forKey: Preferences.Key.mailHiddenAccounts) } }
    /// What a search found at Gmail's; `nil` out of a search.
    @Published public private(set) var found: [MailThreadRow]?
    @Published public private(set) var searching = false
    /// The last gesture, while it can be undone.
    @Published public private(set) var undoable: (text: String, gesture: MailGestureRow)?
    @Published public var message: String?

    public let agenda: AgendaLibrary
    let store: MailStore
    let engine: MailEngine
    private let defaults: UserDefaults
    private var observations: [AnyDatabaseCancellable] = []
    private var subscriptions: Set<AnyCancellable> = []
    private var undoToken = 0

    public init(agenda: AgendaLibrary, root: URL, defaults: UserDefaults = .standard, flavor: AppFlavor = .current) {
        self.agenda = agenda
        self.defaults = defaults
        self.store = MailStore(agenda.database)
        self.hidden = Set(defaults.stringArray(forKey: Preferences.Key.mailHiddenAccounts) ?? [])
        self.engine = MailEngine(database: agenda.database, root: root, sendFor: { [agenda] account in
            { build in try await agenda.mailSend(for: account)(build) }
        }, flavor: flavor)
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
                if front { for account in self.accounts { Task { await self.engine.kick(account.email) } } }
            }
            .store(in: &subscriptions)
        }
    }

    // MARK: - What the list shows

    /// The mailboxes: the accounts that granted the mails.
    public var accounts: [GoogleAccountRow] { agenda.accounts.filter(agenda.mailGranted) }

    /// Gmail files it as a notification, a promotion or a social mail, Paul never wrote in it and never said
    /// its sender belongs to the main tab.
    public func isAutomatic(_ thread: MailThreadRow) -> Bool {
        guard let category = thread.category, MailThreadRow.automaticCategories.contains(category), !thread.paulWrote else { return false }
        return thread.lastSender.flatMap { senders[$0]?.principal } != true
    }

    private func visible(_ threads: [MailThreadRow]) -> [MailThreadRow] {
        threads.filter { !hidden.contains($0.account) }
    }

    /// The threads of the tab, or of the search under way.
    public var shown: [MailThreadRow] {
        if let found { return found }
        return visible(inbox).filter { isAutomatic($0) == (tab == .automatiques) }
    }

    /// The unread threads of the main tab: what waits for Paul.
    public var unreadCount: Int {
        visible(inbox).filter { $0.unread && !isAutomatic($0) }.count
    }

    public func unread(in tab: MailTab) -> Int {
        visible(inbox).filter { $0.unread && isAutomatic($0) == (tab == .automatiques) }.count
    }

    /// « Lecture de la boîte : 1 240 sur 6 000 », while a first reading is under way.
    public var progress: String? {
        let reading = accounts.compactMap { cursors[$0.email] }.filter { $0.finishedAt == nil && $0.total > 0 }
        guard !reading.isEmpty else { return nil }
        let done = reading.reduce(0) { $0 + $1.done }, total = reading.reduce(0) { $0 + $1.total }
        return "Lecture \(reading.count > 1 ? "des boîtes" : "de la boîte") : \(done.formatted(.number.locale(Locale(identifier: "fr_FR")))) sur \(total.formatted(.number.locale(Locale(identifier: "fr_FR"))))"
    }

    /// A mailbox that cannot be read, and why.
    public var failure: (account: String, text: String)? {
        accounts.compactMap { account in cursors[account.email]?.lastError.map { (account.email, $0) } }.first
    }

    public func color(for account: String) -> Color { agenda.color(for: account) }

    // MARK: - Gestures

    private static func done(_ kind: MailGestureKind) -> String {
        switch kind {
        case .archive: "Fil archivé"
        case .unarchive: "Fil remis en boîte de réception"
        case .markRead: "Marqué comme lu"
        case .markUnread: "Marqué comme non lu"
        case .trash: "Fil supprimé"
        case .untrash: "Fil rétabli"
        }
    }

    /// The gesture shows at once; Gmail follows. « Annuler » stays a few seconds.
    public func perform(_ kind: MailGestureKind, on thread: MailThreadRow, undoable canUndo: Bool = true) {
        Task {
            do {
                guard let gesture = try await engine.perform(kind, threadKey: thread.id), canUndo else { return }
                undoToken += 1
                let token = undoToken
                undoable = (Self.done(kind), gesture)
                try? await Task.sleep(for: .seconds(8))
                if undoToken == token { undoable = nil }
            } catch {
                message = "Geste impossible : \(error)"
            }
        }
    }

    public func undo() {
        guard let gesture = undoable?.gesture else { return }
        undoable = nil
        Task {
            do { try await engine.undo(gesture) } catch { message = "Annulation impossible : \(error)" }
        }
    }

    /// Opening a thread reads it.
    public func markRead(_ thread: MailThreadRow) {
        guard thread.unread else { return }
        perform(.markRead, on: thread, undoable: false)
    }

    /// « Déplacer vers Principale » (or back): kept for the sender's next mails.
    public func setPrincipal(_ principal: Bool, for thread: MailThreadRow) {
        guard let sender = thread.lastSender else { return }
        try? store.remember(address: sender, principal: principal, at: Date())
        message = principal ? "Les mails de \(sender) iront dans Principale." : "Les mails de \(sender) suivent de nouveau le classement de Gmail."
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
