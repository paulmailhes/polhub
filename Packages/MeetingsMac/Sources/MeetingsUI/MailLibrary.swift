import Agenda
import AppKit
import Combine
import Domain
import GRDB
import Mail
import MailFormat
import Persistence
import PolhubDesign
import SwiftUI
import UniformTypeIdentifiers

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

/// Where the list looks: the inbox, the drafts, what Paul sent (14/11).
public enum MailFolder: String, Hashable, Sendable, CaseIterable {
    case inbox, drafts, sent, subscriptions

    var title: String {
        switch self {
        case .inbox: "Boîte de réception"
        case .drafts: "Brouillons"
        case .sent: "Envoyés"
        case .subscriptions: "Abonnements"
        }
    }

    var icon: String {
        switch self {
        case .inbox: "tray"
        case .drafts: "doc"
        case .sent: "paperplane"
        case .subscriptions: "newspaper"
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
    /// A mail that did not leave, for the notifications (set by the app): its subject, its thread.
    public var onSendFailed: ((String, String?) -> Void)?

    // Writing (step « Écrire »)
    @Published public var folder: MailFolder = .inbox { didSet { selected = []; refreshFolders() } }
    @Published public private(set) var drafts: [MailDraftRow] = []
    /// The drafts Gmail holds that Polhub did not make.
    @Published public private(set) var gmailDrafts: [MailMessageRow] = []
    @Published public private(set) var sent: [MailThreadRow] = []
    /// The draft open over the list: a new mail, a draft taken from the list.
    @Published public var composing: String?
    /// The mail leaving: Paul has ten seconds to call it back.
    @Published public private(set) var sending: (draftID: String, subject: String, at: Date)?
    /// New mails written while several mailboxes show: they leave only once Paul has chosen the mailbox.
    @Published public private(set) var unconfirmed: Set<String> = []
    /// The search field's text.
    @Published public var query = ""
    /// Only the unread threads of the tab.
    @Published public var unreadOnly = false
    /// The senders Paul could leave (the « Abonnements »), the busiest first.
    @Published public private(set) var subscriptions: [MailSubscription] = []
    /// The senders Paul left from Polhub, with the day.
    @Published public private(set) var unsubscribed: [String: Date] = [:]
    private var pushes: [String: Task<Void, Never>] = [:]
    private var sendTask: Task<Void, Never>?

    public let agenda: AgendaLibrary
    let store: MailStore
    let engine: MailEngine
    private let defaults: UserDefaults
    private var observations: [AnyDatabaseCancellable] = []
    private var cancellables: Set<AnyCancellable> = []
    private var undoToken = 0
    /// The anchor of a ⇧-click.
    private var anchor: String?

    public init(agenda: AgendaLibrary, root: URL, defaults: UserDefaults = .standard, flavor: AppFlavor = .current) {
        self.agenda = agenda
        self.defaults = defaults
        self.store = MailStore(agenda.database)
        self.hidden = Set(defaults.stringArray(forKey: Preferences.Key.mailHiddenAccounts) ?? [])
        self.unsubscribed = (defaults.dictionary(forKey: Preferences.Key.mailUnsubscribed) as? [String: Date]) ?? [:]
        let relay = MailArrivalRelay()
        self.engine = MailEngine(database: agenda.database, root: root, sendFor: { [agenda] account in
            { build in try await agenda.mailSend(for: account)(build) }
        }, flavor: flavor, onNew: { rows in Task { @MainActor in relay.handler?(rows) } })
        relay.handler = { [weak self] rows in self?.arrived(rows) }
        observations = [
            store.observeInbox { [weak self] in
                self?.inbox = $0
                self?.refreshFolders()
            },
            store.observeDrafts { [weak self] in self?.drafts = $0 },
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
        .store(in: &cancellables)
        for (name, front) in [(NSApplication.didBecomeActiveNotification, true), (NSApplication.didResignActiveNotification, false)] {
            NotificationCenter.default.publisher(for: name).sink { [weak self] _ in
                guard let self else { return }
                Task { await self.engine.setForeground(front) }
                if front { self.refresh() }
            }
            .store(in: &cancellables)
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
        return visible(inbox).filter { tab(of: $0) == tab && (!unreadOnly || $0.unread) }
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
        case .spam: return "\(what) signalé\(plural ? "s" : "") comme spam"
        case .notSpam: return "\(what) sorti\(plural ? "s" : "") du spam"
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

    // MARK: - Writing (step « Écrire », 14/11)

    /// Paul's own addresses.
    var mine: Set<String> { Set(agenda.accounts.map(\.email)) }

    /// A mail leaving, or about to: the app's updates wait for it.
    public var isSending: Bool { sending != nil }

    func refreshFolders() {
        guard folder != .inbox else { return }
        let shownAccounts = Set(accounts.map(\.email)).subtracting(hidden)
        sent = (try? store.sentThreads(accounts: shownAccounts)) ?? []
        gmailDrafts = ((try? store.gmailOnlyDrafts()) ?? []).filter { !hidden.contains($0.account) }
        if folder == .subscriptions {
            subscriptions = (try? store.subscriptions(since: Date().addingTimeInterval(-90 * 86_400), accounts: shownAccounts)) ?? []
        }
    }

    /// Who Paul writes to: his contacts and his correspondents, matching what he types.
    public func suggestions(for text: String) -> [MailAddress] {
        let query = text.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard query.count >= 2 else { return [] }
        var seen: Set<String> = [], result: [MailAddress] = []
        let people = agenda.contacts.compactMap { contact in contact.email.map { MailAddress(name: contact.name, email: $0) } }
            + inbox.flatMap(\.senders)
        for person in people where !mine.contains(person.email) && !seen.contains(person.email) {
            let haystack = "\(person.name ?? "") \(person.email)".folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            guard haystack.contains(query) else { continue }
            seen.insert(person.email)
            result.append(person)
            if result.count == 6 { break }
        }
        return result
    }

    /// A new mail, from the mailbox shown if only one is; otherwise Paul chooses it before it can leave.
    public func newMail() {
        let shown = accounts.filter { !hidden.contains($0.email) }
        guard let account = (shown.count == 1 ? shown.first : shown.first ?? accounts.first)?.email else { return }
        let draft = MailDraftRow(account: account, mode: .new, createdAt: Date())
        try? store.saveDraft(draft)
        if shown.count != 1 { unconfirmed.insert(draft.id) }
        composing = draft.id
    }

    /// The mailbox a new mail leaves from; it moves with its files.
    public func setAccount(_ account: String, for draftID: String) {
        unconfirmed.remove(draftID)
        edit(draftID) { $0.account = account }
    }

    /// Reply, reply to all, forward: a draft below the thread, its people and its quote ready. A draft already
    /// begun for the same message is taken up.
    public func startReply(_ mode: MailDraftRow.Mode, to message: MailMessageRow, in thread: MailThreadRow) async -> String? {
        if let existing = drafts.first(where: { $0.replyToKey == message.id && $0.mode == mode }) { return existing.id }
        do {
            let source = try await engine.replySource(for: message)
            let people = ReplyBuilder.recipients(mode, source: source, mine: mine)
            let threading = ReplyBuilder.threading(source)
            var draft = MailDraftRow(account: thread.account, mode: mode, threadKey: thread.id, replyToKey: message.id, to: people.to, cc: people.cc,
                                     subject: ReplyBuilder.subject(mode, original: message.subject), quoteHTML: ReplyBuilder.quoteHTML(mode, source: source),
                                     quoteText: ReplyBuilder.quoteText(mode, source: source), inReplyTo: threading.inReplyTo,
                                     references: threading.references, createdAt: Date())
            if mode == .forward {
                // The files go with a forward, as in Gmail.
                let folder = engine.files.draftFolder(draft)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for file in message.files {
                    let source = try await engine.file(file, of: message)
                    let target = folder.appending(path: AttachmentSafety.cleanName(file.filename))
                    try? FileManager.default.removeItem(at: target)
                    try FileManager.default.copyItem(at: source, to: target)
                    draft.files.append(MailDraftFile(filename: target.lastPathComponent, mimeType: file.mimeType, size: file.size))
                }
            }
            try store.saveDraft(draft)
            return draft.id
        } catch {
            self.message = "Réponse impossible : \(error)"
            return nil
        }
    }

    /// Paul changed a draft: kept on the Mac now, given to Gmail three seconds after his last change. Only the
    /// fields he writes are taken: what Gmail answered meanwhile stays.
    public func edit(_ draftID: String, _ change: (inout MailDraftRow) -> Void) {
        guard var draft = try? store.draft(draftID) else { return }
        let before = draft
        change(&draft)
        guard draft != before else { return }
        draft.updatedAt = Date()
        draft.lastError = nil
        try? store.saveDraft(draft)
        schedulePush(draftID)
    }

    private func schedulePush(_ draftID: String, after delay: Duration = .seconds(3)) {
        pushes[draftID]?.cancel()
        pushes[draftID] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            do {
                try await self.engine.push(draftID)
            } catch GoogleError.readOnlyBuild {
            } catch {
                try? self.store.markDraftError(draftID, error: "\(error)")
            }
            self.pushes[draftID] = nil
        }
    }

    /// Files joined to a draft: copied beside it, 25 Mo in all at most (Gmail's limit).
    public func attach(_ urls: [URL], to draftID: String) {
        guard let draft = try? store.draft(draftID) else { return }
        let folder = engine.files.draftFolder(draft)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var files = draft.files, total = draft.files.reduce(0) { $0 + $1.size }
        for url in urls {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard total + size <= MIMEBuilder.maximumFiles else {
                message = "« \(url.lastPathComponent) » dépasserait 25 Mo de pièces jointes, la limite de Gmail."
                continue
            }
            var name = AttachmentSafety.cleanName(url.lastPathComponent)
            if files.contains(where: { $0.filename == name }) { name = "\(UUID().uuidString.prefix(4))-\(name)" }
            let target = folder.appending(path: name)
            do {
                try FileManager.default.copyItem(at: url, to: target)
            } catch {
                message = "« \(url.lastPathComponent) » n'a pas pu être joint : \(error.localizedDescription)"
                continue
            }
            let type = UTType(filenameExtension: (name as NSString).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            files.append(MailDraftFile(filename: name, mimeType: type, size: size))
            total += size
        }
        edit(draftID) { $0.files = files }
    }

    public func removeFile(_ file: MailDraftFile, from draftID: String) {
        guard let draft = try? store.draft(draftID) else { return }
        try? FileManager.default.removeItem(at: engine.files.draftFolder(draft).appending(path: file.filename))
        edit(draftID) { $0.files.removeAll { $0 == file } }
    }

    /// Why a draft cannot leave yet; `nil` when it can.
    public func sendProblem(_ draft: MailDraftRow) -> String? {
        if unconfirmed.contains(draft.id) { return "Choisis la boîte d'envoi (De)." }
        if (draft.to + draft.cc + draft.bcc).isEmpty { return "Ajoute un destinataire." }
        if let bad = (draft.to + draft.cc + draft.bcc).first(where: { !MIMEBuilder.isValid($0.email) }) { return "L'adresse « \(bad.email) » n'est pas valide." }
        if !draft.isSendable { return "Le mail est vide." }
        return nil
    }

    /// Paul's click: the mail leaves in ten seconds, unless he calls it back. Nothing of it is kept in the base:
    /// if Polhub quits meanwhile, nothing leaves and the draft stays.
    public func send(_ draftID: String) {
        guard sending == nil, let draft = try? store.draft(draftID) else { return }
        if let problem = sendProblem(draft) {
            message = problem
            return
        }
        pushes[draftID]?.cancel()
        pushes[draftID] = nil
        if composing == draftID { composing = nil }
        let subject = draft.subject.isEmpty ? "(sans objet)" : draft.subject
        sending = (draftID, subject, Date().addingTimeInterval(10))
        sendTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self else { return }
            do {
                try await self.engine.send(draftID)
                self.sending = nil
                self.message = "Mail envoyé : « \(subject) »."
            } catch {
                self.sending = nil
                try? self.store.markDraftError(draftID, error: "\(error)")
                self.message = "Mail non envoyé : \(error). Il t'attend dans Brouillons."
                self.onSendFailed?(subject, draft.threadKey)
            }
            self.sendTask = nil
        }
    }

    /// « Annuler » while the mail waits: it stays a draft.
    public func cancelSend() {
        guard let sending else { return }
        sendTask?.cancel()
        sendTask = nil
        self.sending = nil
        message = "Envoi annulé : le mail t'attend dans Brouillons."
        if (try? store.draft(sending.draftID))?.threadKey == nil { composing = sending.draftID }
    }

    /// The draft goes, here and in Gmail.
    public func discard(_ draftID: String) {
        pushes[draftID]?.cancel()
        pushes[draftID] = nil
        unconfirmed.remove(draftID)
        if composing == draftID { composing = nil }
        Task {
            do { try await engine.discard(draftID) } catch { message = "Brouillon impossible à supprimer : \(error)" }
        }
    }

    /// Closing a new mail keeps it as a draft, unless nothing was written.
    public func closeComposer() {
        guard let id = composing else { return }
        composing = nil
        if let draft = try? store.draft(id), (draft.to + draft.cc + draft.bcc).isEmpty, draft.subject.isEmpty,
           draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, draft.files.isEmpty {
            discard(id)
        }
    }

    /// A draft from the list: a reply opens in its thread, a new mail over the list.
    public func open(_ draft: MailDraftRow, router: WindowRouter) {
        if let thread = draft.threadKey, (try? store.thread(thread)) != nil {
            router.mailSelection = thread
        } else {
            composing = draft.id
        }
    }

    /// A draft written in Gmail (the phone), taken up here.
    public func resume(_ message: MailMessageRow, router: WindowRouter) {
        Task {
            do {
                let draft = try await engine.resume(gmailDraft: message)
                refreshFolders()
                open(draft, router: router)
            } catch {
                self.message = "Brouillon impossible à reprendre : \(error)"
            }
        }
    }

    /// The signature a mailbox adds, as text, to show under a draft.
    public func signature(of account: String) -> String? {
        cursors[account]?.signature.map(HTMLText.plain).flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: - Tidying up (14/11)

    /// Every unread thread of the tab, read; one « Annuler » for them all.
    public func markAllRead() {
        perform(.markRead, on: shown.filter(\.unread))
    }

    /// Every mail of a sender, as Gmail finds them: to archive or delete in one go.
    public func showAll(from sender: String) {
        router?.mailSelection = nil
        folder = .inbox
        query = "from:\(sender)"
        Task { await search(query) }
    }

    /// Set by the window: what the library opens.
    public weak var router: WindowRouter?

    /// A request to leave a list, waiting for Paul's confirmation.
    public struct UnsubscribeRequest: Identifiable {
        public var sender: String
        public var name: String
        public var method: UnsubscribeMethod
        public var id: String { sender }
    }

    @Published public var unsubscribeRequest: UnsubscribeRequest?
    /// « Afficher l'original »: its title and its text, while shown.
    @Published public var original: (title: String, text: String)?

    public func askUnsubscribe(sender: MailAddress, method: UnsubscribeMethod) {
        unsubscribeRequest = UnsubscribeRequest(sender: sender.email, name: sender.display, method: method)
    }

    public func showOriginal(_ message: MailMessageRow) {
        Task {
            let text = await original(of: message)
            original = (message.subject, text)
        }
    }

    public func reportSpam(_ thread: MailThreadRow) {
        perform(.spam, on: thread)
    }

    /// How to leave this sender's list, from its own headers.
    public func unsubscribeMethod(listUnsubscribe: String?, post: String?, authenticated: Bool, spam: Bool = false) -> UnsubscribeMethod? {
        guard !spam else { return nil }
        return UnsubscribeMethod.from(listUnsubscribe: listUnsubscribe, post: post, authenticated: authenticated)
    }

    public func unsubscribeMethod(_ subscription: MailSubscription) -> UnsubscribeMethod? {
        unsubscribeMethod(listUnsubscribe: subscription.listUnsubscribe, post: subscription.listUnsubscribePost, authenticated: subscription.authenticated)
    }

    /// Leaves a list, once Paul confirmed: one click sends the sender's own request (never from the development
    /// build); a mail is prepared for Paul to send; a page opens in the browser.
    public func unsubscribe(from sender: String, by method: UnsubscribeMethod, flavor: AppFlavor = .current) {
        switch method {
        case .oneClick(let url):
            guard flavor == .prod else {
                message = "La version de développement ne se désabonne de rien."
                return
            }
            Task {
                do {
                    let session = URLSession(configuration: .ephemeral)
                    let (_, response) = try await session.data(for: UnsubscribeMethod.oneClickRequest(url))
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<400).contains(status) else { throw GoogleError.http(status) }
                    remember(unsubscribedFrom: sender)
                    message = "Désabonné de \(sender). Les mails déjà reçus restent ; « Tout archiver » les range."
                } catch {
                    message = "Désabonnement refusé par \(method.domain) (\(error)). Ouvre un de ses mails : le lien en bas fait la même chose."
                }
            }
        case .mail(let to, let subject):
            guard let account = accounts.first(where: { account in inbox.contains { $0.account == account.email && $0.senders.contains { $0.email == sender } } })?.email
                    ?? accounts.first?.email else { return }
            let draft = MailDraftRow(account: account, mode: .new, to: [MailAddress(email: to)], subject: subject ?? "unsubscribe",
                                     body: "Merci de me retirer de cette liste.", signature: false, createdAt: Date())
            try? store.saveDraft(draft)
            composing = draft.id
            remember(unsubscribedFrom: sender)
        case .page(let url):
            NSWorkspace.shared.open(url)
            remember(unsubscribedFrom: sender)
        }
    }

    private func remember(unsubscribedFrom sender: String) {
        unsubscribed[sender.lowercased()] = Date()
        defaults.set(unsubscribed, forKey: Preferences.Key.mailUnsubscribed)
    }

    /// Every thread of this sender still in the inbox, archived.
    public func archiveAll(_ subscription: MailSubscription) {
        perform(.archive, on: (try? store.threads(keys: subscription.inboxThreads)) ?? [])
        refreshFolders()
    }

    /// « Afficher l'original ».
    public func original(of message: MailMessageRow) async -> String {
        do { return try await engine.original(of: message) } catch { return "Original indisponible : \(error)" }
    }
}
