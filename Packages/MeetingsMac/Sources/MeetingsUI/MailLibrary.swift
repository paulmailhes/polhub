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

/// Where the list looks: the inbox, what Paul sent, the drafts, the mails he programmed, every thread, the
/// senders he can leave, then Gmail's spam and trash; in the sidebar, under « Mails », in Gmail's order (Paul,
/// 15/11). « Programmés » shows only while a mail waits there (wave B).
public enum MailFolder: String, Hashable, Sendable, CaseIterable {
    // Paul, 15/11: Notifications is a folder like the others, next to Abonnements; « Tous les messages » at the
    // bottom, after the trash: he seldom goes there.
    case inbox, sent, drafts, scheduled, notifications, subscriptions, spam, trash, all

    var title: String {
        switch self {
        case .inbox: "Boîte de réception"
        case .sent: "Envoyés"
        case .drafts: "Brouillons"
        case .scheduled: "Programmés"
        case .notifications: "Notifications"
        case .all: "Tous les messages"
        case .subscriptions: "Abonnements"
        case .spam: "Spam"
        case .trash: "Corbeille"
        }
    }

    var icon: String {
        switch self {
        case .inbox: "tray"
        case .sent: "paperplane"
        case .drafts: "doc"
        case .scheduled: "clock"
        case .notifications: "bell"
        case .all: "tray.full"
        case .subscriptions: "newspaper"
        case .spam: "xmark.bin"
        case .trash: "trash"
        }
    }

    /// Gmail's spam or trash: threads put aside, which only come back.
    var aside: MailAside? {
        switch self {
        case .spam: .spam
        case .trash: .trash
        default: nil
        }
    }

    /// The gestures on a thread's line (on hover, in its menu): in the trash or the spam, only the way back
    /// (wave B, 15/11).
    func gestures(for thread: MailThreadRow) -> [MailGestureKind] {
        if let aside { return [aside.gesture] }
        return [thread.inInbox ? .archive : .unarchive, .trash, thread.unread ? .markRead : .markUnread]
    }

    /// The gestures on the ticked threads.
    var selectionGestures: [MailGestureKind] {
        aside.map { [$0.gesture] } ?? [.archive, .trash, .markRead, .markUnread]
    }
}

/// A thread put aside whole: in Gmail's trash or in its spam (wave B, Paul's yes of 15/11). Gmail empties both
/// after 30 days; Polhub only brings a thread back, never deletes it for good (that needs a wider Google
/// permission): no reply, no forward, no case from there.
public enum MailAside: String, Hashable, Sendable, CaseIterable {
    case trash, spam

    /// Gmail's label.
    var label: String { self == .trash ? "TRASH" : "SPAM" }
    var folder: MailFolder { self == .trash ? .trash : .spam }
    /// The one gesture there: « Restaurer », « Pas un spam ».
    var gesture: MailGestureKind { self == .trash ? .untrash : .notSpam }
    /// « dans la corbeille »: a search's count, an empty folder.
    var place: String { self == .trash ? "dans la corbeille" : "dans le spam" }
    /// What an open thread says, in its banner.
    var banner: String {
        switch self {
        case .trash: "Ce fil est dans la corbeille. Gmail le supprime au bout de 30 jours."
        case .spam: "Ce fil est dans le spam. Ses images ne s'affichent jamais."
        }
    }
    /// The line above the list.
    var notice: String {
        switch self {
        case .trash: "Gmail supprime les mails de la corbeille au bout de 30 jours."
        case .spam: "Gmail supprime les mails du spam au bout de 30 jours. Leurs images ne s'affichent jamais."
        }
    }
    /// The folder of Gmail's own page.
    var gmailFolder: String { self == .trash ? "trash" : "spam" }

    /// Where messages put aside whole sit: the spam wins, as in Gmail.
    static func of(_ messages: [MailMessageRow]) -> MailAside? {
        if messages.contains(where: { $0.labels.contains("SPAM") }) { return .spam }
        if messages.contains(where: { $0.labels.contains("TRASH") }) { return .trash }
        return nil
    }
}

extension MailGestureKind {
    /// Its name on a button, in a menu: for the ticked threads, `plural`.
    func title(plural: Bool = false) -> String {
        switch self {
        case .archive: "Archiver"
        case .unarchive: "Remettre en boîte de réception"
        case .markRead: plural ? "Marquer comme lus" : "Marquer comme lu"
        case .markUnread: plural ? "Marquer comme non lus" : "Marquer comme non lu"
        case .trash: "Supprimer"
        case .untrash: "Restaurer"
        case .spam: "Signaler comme spam"
        case .notSpam: "Pas un spam"
        }
    }

    var icon: String {
        switch self {
        case .archive: "archivebox"
        case .unarchive: "tray.and.arrow.down"
        case .markRead: "envelope.open"
        case .markUnread: "envelope.badge"
        case .trash: "trash"
        case .untrash: "arrow.uturn.backward"
        case .spam: "xmark.octagon"
        case .notSpam: "checkmark.shield"
        }
    }

    /// Read or unread is no move: it has no « Annuler » for one thread.
    var undoableAlone: Bool { self != .markRead && self != .markUnread }
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

/// The programmed sends, from the engine to the library, in their order: an older list never comes after a newer.
final class MailScheduleRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var entries: (@MainActor ([ScheduledSend], Int) -> Void)?
    var outcome: (@MainActor (ScheduleOutcome) -> Void)?

    func next() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}

/// What a programmed send tells Paul when it is over, or waits for him: a notification, even window closed.
public struct MailScheduleNotice: Equatable, Sendable {
    public var title: String
    public var body: String
    /// Its thread (a reply), else the folder a click opens.
    public var threadKey: String?
    public var folder: MailFolder?
}

/// The mails, for the window: what the copy holds, and Paul's gestures (14/11).
@MainActor
public final class MailLibrary: ObservableObject {
    /// The inbox of every mailbox, as the copy holds it.
    @Published public private(set) var inbox: [MailThreadRow] = []
    @Published public private(set) var cursors: [String: MailCursorRow] = [:]
    @Published public private(set) var senders: [String: MailSenderRow] = [:]
    /// The inbox shows the people's mails; the folder « Notifications » the rest (Paul, 15/11: one list each, no
    /// tabs).
    public var tab: MailTab {
        get { folder == .notifications ? .notifications : .personnes }
        set { folder = newValue == .notifications ? .notifications : .inbox }
    }
    /// The mailboxes Paul hid from the list.
    @Published public var hidden: Set<String> {
        didSet {
            defaults.set(hidden.sorted(), forKey: Preferences.Key.mailHiddenAccounts)
            refreshFolders()
            filterCopy()
        }
    }
    /// What a search found: in the copy as Paul types, plus Gmail's on Enter; `nil` out of a search.
    @Published public private(set) var found: [MailThreadRow]?
    /// Among `found`, the threads only Gmail found (their words are in the bodies).
    @Published public private(set) var foundInGmail = 0
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
    /// A programmed mail that left late, waits for Paul or did not leave (wave B), for the notifications.
    public var onScheduleNotice: ((MailScheduleNotice) -> Void)?
    /// The mails Paul programmed (wave B), by draft: the Keychain's list, as the engine holds it.
    @Published public private(set) var scheduled: [String: ScheduledSend] = [:]
    private var scheduleVersion = 0

    // Writing (step « Écrire »)
    @Published public var folder: MailFolder = .inbox {
        didSet {
            selected = []
            refreshFolders()
            if folder.aside != nil { readAside() }
        }
    }
    /// « Spam » or « Corbeille » (wave B, 15/11): what the copy holds at once, then what Gmail lists.
    @Published public private(set) var aside: [MailThreadRow] = []
    /// Gmail's list of the spam or the trash is on its way.
    @Published public private(set) var readingAside = false
    private var asideToken = 0
    @Published public private(set) var drafts: [MailDraftRow] = []
    /// The drafts Gmail holds that Polhub did not make.
    @Published public private(set) var gmailDrafts: [MailMessageRow] = []
    @Published public private(set) var sent: [MailThreadRow] = []
    /// « Tous les messages »: the copy, archived threads too (15/11).
    @Published public private(set) var all: [MailThreadRow] = []
    /// The files of the threads listed, shown under their line (Gmail's « Par défaut »), each with its message.
    @Published public private(set) var files: [String: [MailListedFile]] = [:]
    /// Who Paul wrote to in each thread of « Envoyés » (15/11).
    @Published public private(set) var sentTo: [String: [MailAddress]] = [:]
    /// The file Quick Look shows, over the list or an open thread: one for the whole section (15/11).
    @Published public var preview: URL?
    /// The files on their way from Gmail (`MailListedFile.id`): their chip turns meanwhile.
    @Published public private(set) var opening: Set<String> = []
    /// The draft open over the list: a new mail, a draft taken from the list.
    @Published public var composing: String?
    /// The mail leaving: Paul has ten seconds to call it back; once `leaving`, it is on its way to Gmail.
    @Published public private(set) var sending: (draftID: String, subject: String, at: Date, leaving: Bool)?
    /// New mails written while several mailboxes show: they reach Gmail and leave only once Paul has chosen the
    /// mailbox. Kept across launches.
    @Published public private(set) var unconfirmed: Set<String> = [] {
        didSet { defaults.set(unconfirmed.sorted(), forKey: Preferences.Key.mailUnconfirmed) }
    }
    /// The people Paul wrote to: an address among them, or a contact, is known.
    @Published public private(set) var correspondents: Set<String> = []
    /// What decides a thread's case and tab (step « Ranger »).
    @Published public private(set) var rules = MailFilingRules.empty
    /// The search field's text: from two letters, the list shows what the copy holds that answers (15/11).
    @Published public var query = "" {
        didSet { if query != oldValue { queryChanged() } }
    }
    /// Only the unread threads of the tab.
    @Published public var unreadOnly = false
    /// The senders Paul could leave (the « Abonnements »), the busiest first.
    @Published public private(set) var subscriptions: [MailSubscription] = []
    /// The senders Paul left from Polhub, with the day.
    @Published public private(set) var unsubscribed: [String: Date] = [:]
    /// What Gmail found for a text, on Enter: its threads join the copy's.
    private var gmailFound: (text: String, keys: [String])?
    /// The copy as the search reads it, and the version of the copy it was read at.
    private var searchIndex: [MailSearchEntry]?
    private var copyVersion = 0
    private var indexedVersion = -1
    private var indexing = false
    /// Changes with the text: Gmail's answer to an older text is dropped.
    private var searchToken = 0
    private var pushes: [String: (token: Int, task: Task<Void, Never>)] = [:]
    private var pushCount = 0
    private var pendingChecked = false
    private var sendTask: Task<Void, Never>?

    public let agenda: AgendaLibrary
    let store: MailStore
    let engine: MailEngine
    private let defaults: UserDefaults
    private var observations: [AnyDatabaseCancellable] = []
    private var cancellables: Set<AnyCancellable> = []
    private var undoToken = 0
    /// What « Annuler » does when the last change was not a gesture (a case chosen).
    private var undoRestore: (() -> Void)?
    /// The anchor of a ⇧-click.
    private var anchor: String?
    /// Who Paul may write to, ranked (15/11, People.swift).
    lazy var people = PeopleDirectory(mails: self)

    /// Where the programmed sends are kept (wave B): the Keychain for the app, memory for the tests and the
    /// screens (nothing of them survives a launch). The development build never touches the Keychain anyway.
    public enum ScheduleKeeping: Sendable {
        case memory, keychain
    }

    /// `send` stands in for Google in the tests (a fake Gmail); the app speaks to Google through the agenda's session.
    public init(agenda: AgendaLibrary, root: URL, defaults: UserDefaults = .standard, flavor: AppFlavor = .current, send: MailEngine.SendFor? = nil,
                schedules: ScheduleKeeping = .memory, vault: (any ScheduleVault)? = nil) {
        self.agenda = agenda
        self.defaults = defaults
        self.store = MailStore(agenda.database)
        self.hidden = Set(defaults.stringArray(forKey: Preferences.Key.mailHiddenAccounts) ?? [])
        self.unsubscribed = (defaults.dictionary(forKey: Preferences.Key.mailUnsubscribed) as? [String: Date]) ?? [:]
        self.unconfirmed = Set(defaults.stringArray(forKey: Preferences.Key.mailUnconfirmed) ?? [])
        let relay = MailArrivalRelay(), planned = MailScheduleRelay()
        let keeping: any ScheduleVault = vault ?? (schedules == .keychain && flavor == .prod ? KeychainScheduleVault(flavor: flavor) : MemoryScheduleVault())
        self.engine = MailEngine(database: agenda.database, root: root, sendFor: send ?? { [agenda] account in
            { build in try await agenda.mailSend(for: account)(build) }
        }, flavor: flavor, onNew: { rows in Task { @MainActor in relay.handler?(rows) } }, schedules: keeping,
        onSchedules: { all in
            let version = planned.next()
            Task { @MainActor in planned.entries?(all, version) }
        }, onScheduleOutcome: { outcome in Task { @MainActor in planned.outcome?(outcome) } })
        relay.handler = { [weak self] rows in self?.arrived(rows) }
        planned.entries = { [weak self] all, version in self?.receive(all, version: version) }
        planned.outcome = { [weak self] outcome in self?.tell(outcome) }
        observations = [
            store.observeInbox { [weak self] in
                guard let self else { return }
                self.inbox = $0
                self.refreshFolders()
                self.copyChanged()
            },
            store.observeDrafts { [weak self] in
                guard let self else { return }
                self.drafts = $0
                if !self.pendingChecked {
                    self.pendingChecked = true
                    self.pushPending()
                }
            },
            store.observeCursors { [weak self] rows in self?.cursors = Dictionary(uniqueKeysWithValues: rows.map { ($0.account, $0) }) },
            store.observeSenders { [weak self] in self?.senders = $0 },
            // What an agent dropped (step « Agents »): the app makes a draft of it at once.
            store.observeAgentDrafts { [weak self] rows in
                guard let self, !rows.isEmpty else { return }
                Task {
                    let adopted = await self.engine.adoptAgentDrafts()
                    if let draft = adopted.last {
                        self.message = "Un agent a préparé « \(draft.subject.isEmpty ? "(sans objet)" : draft.subject) » : il t'attend dans Brouillons."
                    }
                }
            },
            store.observeFilingRules { [weak self] rules in
                self?.rules = rules
                self?.correspondents = rules.correspondents
            },
        ]
        agenda.mails = self
        // What waits in « Programmés » shows from the launch; a Keychain locked now is read again at the next pass.
        let engine = self.engine
        Task { _ = try? await engine.scheduledSends() }
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
        // The Mac wakes: a mail programmed meanwhile leaves now (wave B). Polhub never wakes the Mac itself.
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification).sink { [weak self] _ in
            self?.refresh()
        }
        .store(in: &cancellables)
        // Gmail's answers once kept on disk by the shared session (a spam's body among them) go (wave B review).
        GoogleHTTP.forgetOldCache()
    }

    /// Asks Gmail what is new, now.
    public func refresh() {
        for account in accounts { Task { await engine.kick(account.email) } }
        if folder.aside != nil { readAside() }
        pushPending()
        // An agent's reply left waiting (offline) is taken up again.
        Task { await engine.adoptAgentDrafts() }
    }

    /// Mails just arrived in an inbox: those of the people's tab are told; only those of a project, if Paul
    /// asked so. Judged on their thread, as the list shows it.
    private func arrived(_ rows: [MailMessageRow]) {
        let visible = rows.filter { !hidden.contains($0.account) }
        guard !visible.isEmpty else { return }
        let threads = Dictionary(((try? store.threads(keys: Array(Set(visible.map(\.threadKey))))) ?? []).map { ($0.id, $0) },
                                 uniquingKeysWith: { first, _ in first })
        let projectsOnly = defaults.bool(forKey: Preferences.Key.mailNoticesProjects)
        let told = visible.filter { row in
            guard let thread = threads[row.threadKey], rules.tab(of: thread) == .personnes else { return false }
            return !projectsOnly || rules.filing(of: thread)?.filing.projectID != nil
        }
        .map { (threadKey: $0.threadKey, sender: $0.sender?.display ?? "Nouveau mail", subject: $0.subject) }
        if !told.isEmpty { onArrival?(told) }
    }

    // MARK: - What the list shows

    /// The mailboxes: the accounts that granted the mails.
    public var accounts: [GoogleAccountRow] { agenda.accounts.filter(agenda.mailGranted) }

    /// The tab of a thread: its case's; else a thread Paul wrote in, a contact or someone he wrote to are
    /// people's; else Gmail's category of the last mail received.
    public func tab(of thread: MailThreadRow) -> MailTab {
        rules.tab(of: thread)
    }

    /// The case of a thread, and why.
    public func filing(of thread: MailThreadRow) -> (filing: MailFiling, origin: MailFilingOrigin)? {
        rules.filing(of: thread)
    }

    public func project(_ id: UUID?) -> ProjectRow? {
        id.flatMap { id in agenda.projects.first { $0.id == id } }
    }

    /// The projects a thread can go to: those under way, by name; the others apart.
    public var filingProjects: (current: [ProjectRow], others: [ProjectRow]) {
        let sorted = agenda.projects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let underWay: Set<ProjectStatus> = [.priorite1, .priorite2, .enPause]
        return (sorted.filter { underWay.contains($0.status) }, sorted.filter { !underWay.contains($0.status) })
    }

    /// Paul's case for a thread (step « Ranger »): kept for it and for its sender's next mails. Filed in a
    /// project, the sender becomes one of its contacts, as with the calendar. One « Annuler » takes it all back.
    public func file(_ thread: MailThreadRow, as filing: MailFiling) {
        guard let takeBack = fileOne(thread, as: filing, at: Date(), linking: true) else { return }
        let who = thread.lastSender.map { address in thread.senders.first { $0.email.lowercased() == address.lowercased() }?.display ?? address }
        offerUndo(Self.filedText(filing, project: project(filing.projectID)?.name, sender: who)) { takeBack.reversed().forEach { $0() } }
    }

    /// Several ticked threads in one case (15/11), and one « Annuler » for all. Only people's threads (Paul wrote
    /// in them, or their sender is a person) make their sender a contact of the project: an automatic sender
    /// would otherwise show its images, look known to the agents and pull its next mails into the project.
    public func file(_ threads: [MailThreadRow], as filing: MailFiling) {
        let date = Date()
        var takeBack: [() -> Void] = []
        var filed = 0
        for thread in threads {
            guard let undo = fileOne(thread, as: filing, at: date, linking: Self.isPeople(thread, rules: rules), bringingBack: false) else { break }
            takeBack += undo
            filed += 1
        }
        guard filed > 0 else { return }
        offerUndo(Self.filedText(filing, project: project(filing.projectID)?.name, count: filed)) { takeBack.reversed().forEach { $0() } }
    }

    /// « Ranger dans » on the ticked threads; the ticks go.
    public func fileSelection(as filing: MailFiling) {
        file(selectedThreads, as: filing)
        endSelection()
    }

    /// A thread written by people: Paul wrote in it, or its sender is a contact, someone he wrote to, or
    /// Gmail's « Principale ».
    static func isPeople(_ thread: MailThreadRow, rules: MailFilingRules) -> Bool {
        thread.paulWrote || rules.baseTab(of: thread) == .personnes
    }

    /// The case of one thread, kept for it and for its sender; filed in a project, its sender becomes a contact
    /// of it when `linking`. Someone Paul removed from the project comes back only when `bringingBack` (one thread
    /// filed by hand); several threads at once leave them out, like the other gestures on many people (15/11).
    /// Returns what takes it back; `nil` when nothing could be written.
    private func fileOne(_ thread: MailThreadRow, as filing: MailFiling, at date: Date, linking: Bool, bringingBack: Bool = true) -> [() -> Void]? {
        let previousChoice = rules.choices[thread.id]
        let sender = thread.lastSender?.lowercased()
        let previousMemory = sender.flatMap { rules.senders[$0]?.filing }
        let store = self.store
        do {
            try store.file(threadKey: thread.id, as: filing, at: date)
            if let sender { try store.remember(address: sender, filing: .some(filing.rawValue), at: date) }
        } catch {
            message = "Rangement impossible : \(error)"
            return nil
        }
        var takeBack: [() -> Void] = [{
            try? store.file(threadKey: thread.id, as: previousChoice, at: Date())
            if let sender { try? store.remember(address: sender, filing: .some(previousMemory), at: Date()) }
        }]
        if linking, let projectID = filing.projectID, let sender, !mine.contains(sender), !Self.isRobot(sender) {
            let contacts = ContactStore(agenda.database)
            do {
                var created = false
                let contact: ContactRow
                if let known = try contacts.contact(email: sender) {
                    contact = known
                } else {
                    let name = thread.senders.first { $0.email.lowercased() == sender }?.display ?? sender
                    contact = try contacts.upsert(email: sender, name: name, company: Linker.company(forEmail: sender), at: date)
                    created = true
                }
                let before = try contacts.links().first { $0.contactID == contact.id && $0.projectID == projectID }
                if before?.excluded == true && !bringingBack { return takeBack }
                if before == nil || before?.excluded == true { try contacts.include(contactID: contact.id, projectID: projectID, at: date) }
                takeBack.append {
                    if created {
                        try? contacts.delete(contactID: contact.id)
                    } else if before == nil {
                        try? contacts.unlink(contactID: contact.id, projectID: projectID)
                    } else if before?.excluded == true {
                        try? contacts.exclude(contactID: contact.id, projectID: projectID, at: Date())
                    }
                }
            } catch {
                message = "Le contact n'a pas pu être relié au projet : \(error)"
            }
        }
        return takeBack
    }

    static func filedText(_ filing: MailFiling, project: String?, sender: String?) -> String {
        let next = sender.map { "les prochains mails de \($0)" } ?? "les prochains mails"
        switch filing {
        case .project: return "Rangé dans « \(project ?? "le projet") » : \(next) suivront."
        case .none: return "Sans case : \(next) resteront dans Personnes."
        default: return "Rangé dans \(filing.title ?? "") : \(next) suivront."
        }
    }

    /// « Rangés dans « Site vitrine » : 3 fils ».
    static func filedText(_ filing: MailFiling, project: String?, count: Int) -> String {
        let threads = count > 1 ? "\(count) fils" : "1 fil", filed = count > 1 ? "Rangés" : "Rangé"
        switch filing {
        case .project: return "\(filed) dans « \(project ?? "le projet") » : \(threads)"
        case .none: return "Sans case : \(threads)"
        default: return "\(filed) dans \(filing.title ?? "") : \(threads)"
        }
    }

    /// An address no one answers: never made a contact.
    nonisolated static func isRobot(_ address: String) -> Bool {
        let local = address.split(separator: "@").first.map { $0.lowercased() } ?? ""
        // Anywhere in the name (« compta-noreply », « bounce-123 »), as Gmail's own guess does.
        if ["noreply", "no-reply", "no_reply", "donotreply", "do-not-reply", "do_not_reply", "nepasrepondre", "ne-pas-repondre", "ne_pas_repondre",
            "mailer-daemon", "bounce"].contains(where: local.contains) { return true }
        return ["notification", "notifications", "newsletter", "news"].contains { local == $0 || local.hasPrefix($0 + "+") || local.hasPrefix($0 + ".") }
    }

    func offerUndo(_ text: String, restore: @escaping () -> Void) {
        undoToken += 1
        let token = undoToken
        undoRestore = restore
        undoable = (text, [])
        Task {
            try? await Task.sleep(for: .seconds(8))
            if undoToken == token {
                undoable = nil
                undoRestore = nil
            }
        }
    }

    /// Every thread of an automatic tab, archived at once; one « Annuler ».
    public func archiveTab() {
        guard tab != .personnes, found == nil else { return }
        perform(.archive, on: visible(inbox).filter { tab(of: $0) == tab })
    }

    /// Not written by a person: the Notifications tab (services, letters, promotions).
    public func isAutomatic(_ thread: MailThreadRow) -> Bool {
        tab(of: thread) != .personnes
    }

    private func visible(_ threads: [MailThreadRow]) -> [MailThreadRow] {
        threads.filter { !hidden.contains($0.account) }
    }

    /// The threads the list shows: the search's, else the tab's in the inbox, else the folder's.
    public var shown: [MailThreadRow] {
        if let found { return found }
        let threads: [MailThreadRow]
        switch folder {
        case .inbox, .notifications: threads = visible(inbox).filter { tab(of: $0) == tab }
        case .sent: threads = sent
        case .all: threads = all
        // A thread put aside is never unread: nothing to filter.
        case .spam, .trash: return aside
        case .drafts, .scheduled, .subscriptions: return []
        }
        return unreadOnly ? threads.filter(\.unread) : threads
    }

    /// The drafts waiting: Polhub's and those begun elsewhere. A programmed mail is in « Programmés » only, as in
    /// Gmail.
    public var draftCount: Int { drafts.filter { scheduled[$0.id] == nil }.count + gmailDrafts.count }

    /// The programmed mails of the mailboxes shown, the next to leave first (wave B).
    public var scheduledDrafts: [(draft: MailDraftRow, entry: ScheduledSend)] {
        drafts.compactMap { draft in scheduled[draft.id].map { (draft, $0) } }
            .filter { !hidden.contains($0.draft.account) }
            .sorted { $0.entry.sendAt < $1.entry.sendAt }
    }

    /// « Programmés » in the sidebar: while a mail waits there, or while Paul looks at it.
    public var showsScheduled: Bool { folder == .scheduled || !scheduledDrafts.isEmpty }

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

    /// Gmail's « Lus », « Non lus »: the threads shown that answer.
    public func select(where answers: (MailThreadRow) -> Bool) {
        selected = Set(shown.filter(answers).map(\.id))
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
            undoRestore = nil
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
        perform(kind, on: threads, undoable: kind.undoableAlone || threads.count > 1)
        endSelection()
    }

    public func undo() {
        if let restore = undoRestore {
            undoRestore = nil
            undoable = nil
            restore()
            return
        }
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

    /// The thread in Gmail's own page, under its account; in its spam or its trash when it is put aside there.
    public func gmailURL(_ thread: MailThreadRow, in aside: MailAside? = nil) -> URL {
        GmailLink.thread(thread.threadID, account: thread.account, folder: aside?.gmailFolder ?? "all")
    }

    // MARK: - Search (one bar, 15/11)

    /// The mailboxes the list shows.
    private var shownAccounts: Set<String> { Set(accounts.map(\.email)).subtracting(hidden) }

    /// As Paul types: from two letters, the copy filtered at once; one letter or nothing, the folder again;
    /// a Gmail operator (`from:`…) waits for Enter.
    private func queryChanged() {
        searchToken += 1
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if gmailFound?.text != text {
            gmailFound = nil
            foundInGmail = 0
        }
        if folder.aside != nil { return filterCopy() }
        switch MailSearch.mode(text) {
        case .none: found = nil
        case .tooShort, .gmailOnly: if gmailFound == nil { found = nil }
        case .local: filterCopy()
        }
    }

    /// The copy changed (Gmail's news, a gesture): a search under way reads it again.
    private func copyChanged() {
        copyVersion += 1
        filterCopy()
    }

    /// The threads of the copy that answer the text, every folder and tab of the mailboxes shown, plus those
    /// Gmail found on Enter. The copy is read again, away from the screen, when it changed.
    private func filterCopy() {
        if let aside = folder.aside { return filterAside(aside) }
        guard case .local(let words) = MailSearch.mode(query) else { return }
        if indexedVersion != copyVersion { readCopy() }
        // The first reading takes a moment: the folder stays until it is there.
        guard let index = searchIndex else { return }
        found = merged(MailSearch.filter(index, words: words, accounts: shownAccounts))
        refreshFiles(keepingKnown: true)
    }

    /// In « Spam » or « Corbeille », a search filters that folder's list only: never the rest of the copy, never
    /// Gmail (wave B, 15/11). Its words are those of the threads listed there.
    private func filterAside(_ aside: MailAside) {
        guard let words = MailSearch.localWords(query) else {
            found = nil
            return
        }
        let entries = (try? store.searchEntries(aside: aside.label)) ?? []
        found = MailSearch.filter(entries, words: words, accounts: shownAccounts)
    }

    /// The trash or the spam opened, or « Relever » there: the copy's threads show at once; Gmail's own list,
    /// read as headers only, joins them.
    private func readAside() {
        guard let aside = folder.aside else { return }
        asideToken += 1
        let token = asideToken, accounts = shownAccounts.sorted(), engine = self.engine
        readingAside = true
        Task {
            do {
                try await engine.aside(aside.label, accounts: accounts)
            } catch {
                if token == asideToken { message = "Gmail n'a pas pu donner \(aside == .trash ? "sa corbeille" : "son spam") : \(error). Voici ce que Polhub en a déjà." }
            }
            guard token == asideToken else { return }
            readingAside = false
            refreshFolders()
            if found != nil { filterCopy() }
        }
    }

    private func readCopy() {
        guard !indexing else { return }
        indexing = true
        let version = copyVersion, store = self.store
        Task {
            let entries = await Task.detached { (try? store.searchEntries()) ?? [] }.value
            indexing = false
            searchIndex = entries
            indexedVersion = version
            filterCopy()
        }
    }

    /// The copy's threads and Gmail's, once each, the most recent first.
    private func merged(_ local: [MailThreadRow]) -> [MailThreadRow] {
        guard let gmail = gmailFound else {
            foundInGmail = 0
            return local
        }
        let known = Set(local.map(\.id)), shown = shownAccounts
        let added = ((try? store.threads(keys: gmail.keys)) ?? []).filter { !$0.hidden && !known.contains($0.id) && shown.contains($0.account) }
        foundInGmail = added.count
        return (local + added).sorted { $0.lastMessageAt > $1.lastMessageAt }
    }

    /// Enter: Paul's text also goes to Gmail as he typed it, on the mailboxes shown; Gmail reads the bodies too.
    /// Its threads join those of the copy.
    public func search(_ text: String) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            found = nil
            return
        }
        // Gmail is never asked from the trash or the spam.
        guard folder.aside == nil else { return filterCopy() }
        let token = searchToken
        searching = true
        defer { searching = false }
        do {
            let keys = try await engine.search(query, accounts: accounts.map(\.email).filter { !hidden.contains($0) })
            guard token == searchToken else { return }
            gmailFound = (query, keys)
            if case .local(let words) = MailSearch.mode(query), let index = searchIndex {
                found = merged(MailSearch.filter(index, words: words, accounts: shownAccounts))
            } else {
                found = merged([])
            }
            refreshFiles()
        } catch {
            message = "Recherche impossible : \(error)"
        }
    }

    public func endSearch() {
        gmailFound = nil
        foundInGmail = 0
        found = nil
    }

    /// The line under the bar during a search: how many threads, and what Enter does.
    public var searchSummary: String? {
        if let aside = folder.aside {
            guard let found else { return nil }
            return (found.isEmpty ? "Aucun fil" : (found.count == 1 ? "1 fil" : "\(found.count) fils")) + " \(aside.place)"
        }
        if searching { return "Recherche dans Gmail…" }
        let mode = MailSearch.mode(query)
        guard mode != .none else { return nil }
        guard let found else { return mode == .tooShort ? nil : "Entrée : chercher dans Gmail" }
        let number = found.count.formatted(IntegerFormatStyle<Int>.number.locale(Locale(identifier: "fr_FR")))
        let count = found.isEmpty ? "Aucun fil" : (found.count == 1 ? "1 fil" : "\(number) fils")
        guard gmailFound != nil else { return "\(count) dans tes mails · Entrée : chercher aussi dans Gmail" }
        if foundInGmail == 0 { return found.isEmpty ? "Aucun fil, ni dans tes mails ni dans Gmail" : "\(count) · Gmail n'en a pas trouvé d'autre" }
        let plural = foundInGmail > 1 ? "s" : ""
        if foundInGmail == found.count { return "\(count) trouvé\(plural) dans Gmail" }
        return "\(count), dont \(foundInGmail) trouvé\(plural) dans Gmail"
    }

    // MARK: - Images

    public var imagesMode: MailImages {
        MailImages(rawValue: defaults.string(forKey: Preferences.Key.mailImages) ?? "") ?? .connus
    }

    /// Whether this message's remote images load without asking: its sender is known and Gmail confirmed the
    /// mail comes from him. Known: a contact, someone Paul wrote to in this thread, or « Toujours ».
    public func showsImages(of message: MailMessageRow, in thread: MailThreadRow) -> Bool {
        // Never in the spam, whatever the setting (wave B).
        guard !message.labels.contains("SPAM") else { return false }
        switch imagesMode {
        case .afficher: return true
        case .demander: return false
        case .connus:
            // Paul's own mail may quote a stranger's (review of 14/11): its images load only if everyone else
            // in the thread is known.
            if message.labels.contains("SENT") {
                return thread.senders.map { $0.email.lowercased() }.filter { !mine.contains($0) }
                    .allSatisfy { senders[$0]?.images == true || isKnown($0) }
            }
            guard message.authenticated, let sender = message.sender?.email else { return false }
            return senders[sender]?.images == true || thread.paulWrote || agenda.contact(email: sender) != nil
        }
    }

    /// Réglages › Mails › « Oublier » (15/11): nothing is kept of this sender any more; its mails follow the rules.
    public func forget(_ address: String) {
        do {
            try store.remember(address: address, tab: .some(nil), images: false, filing: .some(nil), at: Date())
        } catch {
            message = "Impossible d'oublier \(address) : \(error)"
        }
    }

    /// « Toujours pour cet expéditeur ».
    public func alwaysShowImages(from sender: String) {
        try? store.remember(address: sender, images: true, at: Date())
    }

    // MARK: - Files (15/11)

    /// A chip under a line of the list: its file shows at once, without opening the thread.
    public func open(_ file: MailListedFile) {
        guard let carrier = try? store.message(file.messageKey) else {
            message = "Pièce jointe indisponible : son mail n'est plus dans la copie."
            return
        }
        open(file.attachment, of: carrier)
    }

    /// A file of a message, downloaded once: an image, a PDF or a document shows in Quick Look; anything else
    /// (HTML, archive, program) is never opened by Polhub, only saved where Paul says.
    public func open(_ attachment: MailAttachment, of carrier: MailMessageRow) {
        let id = MailListedFile(messageKey: carrier.id, attachment: attachment).id
        guard !opening.contains(id) else { return }
        opening.insert(id)
        Task {
            do {
                let url = try await engine.file(attachment, of: carrier)
                opening.remove(id)
                if AttachmentSafety.canOpen(name: attachment.filename) { preview = url } else { saveCopy(of: url) }
            } catch {
                opening.remove(id)
                message = "Pièce jointe indisponible : \(error)"
            }
        }
    }

    /// « Enregistrer… » on a chip.
    public func save(_ file: MailListedFile) {
        guard let carrier = try? store.message(file.messageKey) else { return }
        save(file.attachment, of: carrier)
    }

    public func save(_ attachment: MailAttachment, of carrier: MailMessageRow) {
        Task {
            do { saveCopy(of: try await engine.file(attachment, of: carrier)) } catch { message = "Pièce jointe indisponible : \(error)" }
        }
    }

    /// A copy of a file where Paul chooses.
    func saveCopy(of url: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        guard panel.runModal() == .OK, let target = panel.url else { return }
        try? FileManager.default.removeItem(at: target)
        do { try FileManager.default.copyItem(at: url, to: target) } catch { message = "Enregistrement impossible : \(error.localizedDescription)" }
    }

    // MARK: - Writing (step « Écrire », 14/11)

    /// Paul's own addresses.
    var mine: Set<String> { Set(agenda.accounts.map(\.email)) }

    /// A contact, someone Paul wrote to, or Paul: never a stranger. A stranger's address shows in full in a
    /// draft (review of 14/11).
    public func isKnown(_ email: String) -> Bool {
        let address = email.lowercased()
        return mine.contains(address) || correspondents.contains(address) || agenda.contact(email: address) != nil
    }

    /// A mail leaving, or about to: the app's updates wait for it. A programmed one too, from three minutes
    /// before its time until it left; never one that waits for Paul (wave B).
    public var isSending: Bool { sending != nil || Self.holdsUpdates(Array(scheduled.values), now: Date()) }

    nonisolated static func holdsUpdates(_ entries: [ScheduledSend], now: Date) -> Bool {
        entries.contains { entry in
            switch entry.state {
            case .leaving: true
            case .held: false
            case .waiting: entry.sendAt.timeIntervalSince(now) < 180 && now.timeIntervalSince(entry.sendAt) <= MailEngine.lateLimit
            }
        }
    }

    func refreshFolders() {
        let shownAccounts = shownAccounts
        // The drafts' count shows in the sidebar, whatever the folder.
        gmailDrafts = ((try? store.gmailOnlyDrafts()) ?? []).filter { !hidden.contains($0.account) }
        switch folder {
        case .sent:
            sent = (try? store.sentThreads(accounts: shownAccounts)) ?? []
            sentTo = (try? store.sentRecipients(threadKeys: sent.map(\.id))) ?? [:]
        case .all: all = (try? store.allThreads(accounts: shownAccounts)) ?? []
        case .subscriptions: subscriptions = (try? store.subscriptions(since: Date().addingTimeInterval(-90 * 86_400), accounts: shownAccounts)) ?? []
        // The copy only, at each tick: Gmail's list is asked when the folder opens (readAside).
        case .spam, .trash: aside = (try? store.asideThreads(label: folder.aside?.label ?? "", accounts: shownAccounts)) ?? []
        case .inbox, .notifications, .drafts, .scheduled: break
        }
        refreshFiles()
    }

    /// The files of the threads listed, read again when the list changes. As Paul types, only the threads not
    /// read yet are (`keepingKnown`): the whole copy's files take about 50 ms to read (measured 15/11, 5 600 threads).
    private func refreshFiles(keepingKnown: Bool = false) {
        let keys = Set((found ?? []).map(\.id) + visible(inbox).map(\.id) + (folder == .sent ? sent.map(\.id) : []) + (folder == .all ? all.map(\.id) : []))
        let withFiles = (found ?? []) + inbox + sent + all
        let wanted = Array(Set(withFiles.filter { $0.hasAttachment && keys.contains($0.id) }.map(\.id)))
        guard keepingKnown else {
            files = (try? store.attachments(threadKeys: wanted)) ?? [:]
            return
        }
        let known = files.filter { keys.contains($0.key) }
        let missing = wanted.filter { known[$0] == nil }
        guard !missing.isEmpty || known.count != files.count else { return }
        files = known.merging((try? store.attachments(threadKeys: missing)) ?? [:]) { _, fresh in fresh }
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
        Task {
            do {
                try await engine.changeAccount(draftID, to: account)
            } catch {
                message = "Changement de boîte impossible : \(error)"
            }
            schedulePush(draftID, after: .zero)
        }
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
                var taken: Set<String> = []
                for file in message.files {
                    let source = try await engine.file(file, of: message)
                    let name = AttachmentSafety.uniqueName(file.filename, taken: taken)
                    taken.insert(name)
                    let target = folder.appending(path: name)
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
        // Programmed, it is locked: « Annuler l'envoi programmé » first (wave B).
        guard scheduled[draftID] == nil, let draft = try? store.updateDraft(draftID, at: Date(), change), draft.needsPush else { return }
        schedulePush(draftID)
    }

    /// Calling a push off only stops its wait: once on its way, the engine sees it through (review of 14/11).
    private func schedulePush(_ draftID: String, after delay: Duration = .seconds(3)) {
        guard !unconfirmed.contains(draftID) else { return }
        pushes[draftID]?.task.cancel()
        pushCount += 1
        let token = pushCount
        let task = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            do {
                try await self.engine.push(draftID)
            } catch GoogleError.readOnlyBuild {
            } catch is MailDraftRow.Conflict {
            } catch GoogleError.notFound {
            } catch {
                try? self.store.markDraftError(draftID, error: "\(error)")
            }
            if self.pushes[draftID]?.token == token { self.pushes[draftID] = nil }
        }
        pushes[draftID] = (token, task)
    }

    /// The drafts Gmail does not hold in their last version (a push that failed, Polhub quit too soon).
    private func pushPending() {
        for draft in drafts where draft.needsPush && draft.conflict == nil && draft.origin != .agent && pushes[draft.id] == nil
            && sending?.draftID != draft.id && !Self.isBlank(draft) {
            schedulePush(draft.id, after: .zero)
        }
    }

    /// Nothing written yet: no one, no subject, no text, no file.
    static func isBlank(_ draft: MailDraftRow) -> Bool {
        (draft.to + draft.cc + draft.bcc).isEmpty && draft.subject.isEmpty && draft.files.isEmpty
            && draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// « Le garder », « Garder celui-ci »: Gmail takes this version.
    public func keepDraft(_ draftID: String) {
        Task {
            do {
                try await engine.keepMine(draftID)
                schedulePush(draftID, after: .zero)
            } catch {
                message = "Brouillon impossible à garder : \(error)"
            }
        }
    }

    /// « Le supprimer », « Prendre celui de Gmail »: Polhub lets it go; Gmail's copy, if any, stays among the
    /// drafts begun elsewhere.
    public func forgetDraft(_ draftID: String, gmailKept: Bool) {
        if composing == draftID { composing = nil }
        unconfirmed.remove(draftID)
        Task {
            do {
                try await engine.forgetLocally(draftID)
                if gmailKept { message = "La version de Gmail t'attend dans Brouillons, parmi les brouillons commencés ailleurs." }
            } catch {
                message = "Brouillon impossible à retirer : \(error)"
            }
        }
    }

    /// Files joined to a draft: files only (the one a link points to), never a folder or a bundle; copied
    /// beside it away from the screen's thread; 25 Mo in all at most (Gmail's limit).
    public func attach(_ urls: [URL], to draftID: String) {
        guard scheduled[draftID] == nil, let draft = try? store.draft(draftID) else { return }
        let folder = engine.files.draftFolder(draft)
        var taken = Set(draft.files.map(\.filename)), total = draft.files.reduce(0) { $0 + $1.size }
        var plan: [(source: URL, name: String, size: Int)] = []
        for url in urls {
            do {
                let file = try AttachmentSafety.joinable(url)
                guard total + file.size <= MIMEBuilder.maximumFiles else {
                    message = "« \(url.lastPathComponent) » dépasserait 25 Mo de pièces jointes, la limite de Gmail."
                    continue
                }
                let name = AttachmentSafety.uniqueName(url.lastPathComponent, taken: taken)
                taken.insert(name)
                total += file.size
                plan.append((file.url, name, file.size))
            } catch {
                message = "\(error)"
            }
        }
        guard !plan.isEmpty else { return }
        let work = plan
        Task {
            let copied = await Task.detached { () -> [(name: String, size: Int, error: String?)] in
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                return work.map { item in
                    do {
                        try FileManager.default.copyItem(at: item.source, to: folder.appending(path: item.name))
                        return (item.name, item.size, nil)
                    } catch {
                        return (item.name, item.size, error.localizedDescription)
                    }
                }
            }.value
            var added: [MailDraftFile] = []
            for item in copied {
                if let error = item.error {
                    message = "« \(item.name) » n'a pas pu être joint : \(error)"
                    continue
                }
                let type = UTType(filenameExtension: (item.name as NSString).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                added.append(MailDraftFile(filename: item.name, mimeType: type, size: item.size))
            }
            edit(draftID) { draft in
                for file in added where !draft.files.contains(where: { $0.filename == file.filename }) { draft.files.append(file) }
            }
        }
    }

    public func removeFile(_ file: MailDraftFile, from draftID: String) {
        guard scheduled[draftID] == nil, let draft = try? store.draft(draftID) else { return }
        if let url = try? engine.files.draftFile(file, of: draft) { try? FileManager.default.removeItem(at: url) }
        edit(draftID) { $0.files.removeAll { $0 == file } }
    }

    /// Why a draft cannot leave yet; `nil` when it can.
    public func sendProblem(_ draft: MailDraftRow) -> String? {
        if unconfirmed.contains(draft.id) { return "Choisis la boîte d'envoi (De)." }
        if draft.conflict != nil { return "Choisis d'abord la version à garder." }
        if (draft.to + draft.cc + draft.bcc).isEmpty { return "Ajoute un destinataire." }
        if let bad = (draft.to + draft.cc + draft.bcc).first(where: { !MIMEBuilder.isValid($0.email) }) { return "L'adresse « \(bad.email) » n'est pas valide." }
        if !draft.isSendable { return "Le mail est vide." }
        return nil
    }

    /// Paul's click: the mail leaves in ten seconds, unless he calls it back. Nothing of it is kept in the base:
    /// if Polhub quits meanwhile, nothing leaves and the draft stays.
    public func send(_ draftID: String) {
        // A programmed mail leaves now only through « Envoyer maintenant » (`sendScheduledNow`).
        guard sending == nil, scheduled[draftID] == nil, let draft = try? store.draft(draftID) else { return }
        startSending(draft, programmed: false)
    }

    /// The delay to call it back, then the engine. A programmed mail stays on the list meanwhile: at the end, it
    /// leaves only as Paul sealed it (wave B review); « Annuler » leaves it as it was.
    private func startSending(_ draft: MailDraftRow, programmed: Bool) {
        let draftID = draft.id
        if let problem = sendProblem(draft) {
            message = problem
            return
        }
        // Only the wait is called off: a push on its way ends, and the send waits for it.
        pushes[draftID]?.task.cancel()
        pushes[draftID] = nil
        if composing == draftID { composing = nil }
        let subject = draft.subject.isEmpty ? "(sans objet)" : draft.subject
        // Gmail's delay, chosen in Réglages › Mails (15/11).
        let delay = Preferences(defaults: defaults).mailUndoSeconds
        sending = (draftID, subject, Date().addingTimeInterval(Double(delay)), false)
        sendTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.sending?.draftID == draftID else { return }
            // From here « Annuler » can no longer call it back (review of 14/11).
            self.sending?.leaving = true
            do {
                try await self.engine.send(draftID, programmed: programmed)
                self.message = "Mail envoyé : « \(subject) »."
            } catch {
                if (try? self.store.draft(draftID)) != nil {
                    // Still programmed (Gmail did not answer): it waits in « Programmés », as it was.
                    let waits = (try? await self.engine.scheduledSends())?.contains { $0.draftID == draftID } ?? false
                    if !(error is MailDraftRow.Conflict), !waits { try? self.store.markDraftError(draftID, error: "\(error)") }
                    self.message = "Mail non envoyé : \(error). " + (waits ? "Il attend toujours dans Programmés." : "Il t'attend dans Brouillons.")
                    self.onSendFailed?(subject, draft.threadKey)
                }
            }
            if self.sending?.draftID == draftID {
                self.sending = nil
                self.sendTask = nil
            }
        }
    }

    /// « Annuler » while the mail waits: it stays a draft, and Gmail gets its last version. Too late once it
    /// is on its way.
    public func cancelSend() {
        guard let sending else { return }
        guard !sending.leaving else {
            message = "Trop tard : le mail est déjà en route."
            return
        }
        sendTask?.cancel()
        sendTask = nil
        self.sending = nil
        // « Envoyer maintenant » called back: still programmed, as it was.
        guard scheduled[sending.draftID] == nil else {
            message = "Envoi annulé : le mail attend toujours dans Programmés."
            return
        }
        message = "Envoi annulé : le mail t'attend dans Brouillons."
        if (try? store.draft(sending.draftID))?.threadKey == nil { composing = sending.draftID }
        schedulePush(sending.draftID, after: .zero)
    }

    /// The draft goes, here and in Gmail. A mail waiting to leave is called back first.
    public func discard(_ draftID: String) {
        if let sending, sending.draftID == draftID {
            guard !sending.leaving else { return }
            sendTask?.cancel()
            sendTask = nil
            self.sending = nil
        }
        pushes[draftID]?.task.cancel()
        pushes[draftID] = nil
        unconfirmed.remove(draftID)
        if composing == draftID { composing = nil }
        Task {
            do { try await engine.discard(draftID) } catch { message = "Brouillon impossible à supprimer : \(error)" }
        }
    }

    // MARK: - Programmer l'envoi (wave B, 15/11)

    /// Paul's choice in the menu next to « Envoyer »: the mail leaves at `date`, exactly as it is now. Until then
    /// it is locked here, and Gmail's draft holds this version (edited on the phone, it will not leave). The bar
    /// offers « Annuler » for a few seconds.
    public func schedule(_ draftID: String, at date: Date) {
        guard sending?.draftID != draftID, scheduled[draftID] == nil, let draft = try? store.draft(draftID) else { return }
        if let problem = sendProblem(draft) {
            message = problem
            return
        }
        pushes[draftID]?.task.cancel()
        pushes[draftID] = nil
        let subject = draft.subject.isEmpty ? "(sans objet)" : draft.subject, engine = self.engine
        Task {
            do {
                let entry = try await engine.schedule(draftID, at: date)
                withAnimation(Motion.standard) { scheduled[draftID] = entry }
                if composing == draftID { composing = nil }
                schedulePush(draftID, after: .zero)
                offerUndo("« \(subject) » programmé pour \(MailText.scheduled(date))") { [weak self] in self?.unschedule(draftID, reopen: true) }
            } catch GoogleError.readOnlyBuild {
                message = "La version de développement ne programme aucun envoi."
            } catch {
                message = "Envoi non programmé : \(error)."
            }
        }
    }

    /// « Annuler l'envoi programmé »: the mail is a draft again, in Brouillons. The bar's « Annuler » (`reopen`)
    /// opens a new mail again, as after « Envoyer ».
    public func unschedule(_ draftID: String, reopen: Bool = false) {
        let engine = self.engine
        Task {
            do {
                let entry = try await engine.unschedule(draftID)
                withAnimation(Motion.standard) { scheduled[draftID] = nil }
                if reopen, (try? store.draft(draftID))?.threadKey == nil {
                    composing = draftID
                } else if let entry {
                    message = "« \(entry.subject) » n'est plus programmé : il t'attend dans Brouillons."
                }
            } catch {
                message = "Impossible d'annuler l'envoi programmé : \(error)."
            }
        }
    }

    /// « Envoyer maintenant », on a programmed mail or one that waits for Paul: the usual delay to call it back, then
    /// it leaves as Paul sealed it, never the base's version of the moment (wave B review). It stays on the list
    /// meanwhile: « Annuler » leaves it there.
    public func sendScheduledNow(_ draftID: String) {
        guard sending == nil else {
            message = "Un autre mail part en ce moment : réessaie dans quelques secondes."
            return
        }
        guard scheduled[draftID] != nil, let draft = try? store.draft(draftID) else { return }
        startSending(draft, programmed: true)
    }

    /// The engine's list; an older one never comes after a newer.
    private func receive(_ all: [ScheduledSend], version: Int) {
        guard version > scheduleVersion else { return }
        scheduleVersion = version
        let fresh = Dictionary(all.map { ($0.draftID, $0) }, uniquingKeysWith: { _, last in last })
        guard fresh != scheduled else { return }
        withAnimation(Motion.standard) { scheduled = fresh }
    }

    /// What became of a programmed mail: a line here; a notification when it left late, waits for Paul or did not
    /// leave.
    private func tell(_ outcome: ScheduleOutcome) {
        let texts = Self.texts(for: outcome)
        if let line = texts.line { message = line }
        if let notice = texts.notice { onScheduleNotice?(notice) }
    }

    /// The words of an outcome (Paul, 15/11: « Parti à 9:12 au lieu de 8:00 »; « « Objet » n'est pas parti : le
    /// brouillon a changé depuis que tu l'as programmé »).
    nonisolated static func texts(for outcome: ScheduleOutcome, now: Date = Date(), calendar: Calendar = .current) -> (line: String?, notice: MailScheduleNotice?) {
        switch outcome {
        case .sent(let entry, let at):
            // On time, as in Gmail: no notification.
            guard at.timeIntervalSince(entry.sendAt) > 5 * 60 else { return ("Mail programmé envoyé : « \(entry.subject) ».", nil) }
            // The day too when it left the day after (« au lieu d'hier 23:00 »).
            let planned = calendar.isDate(entry.sendAt, inSameDayAs: at) ? "de \(MailText.clock(entry.sendAt, calendar: calendar))"
                : { let words = MailText.scheduled(entry.sendAt, now: at, calendar: calendar); return words.hasPrefix("hier") ? "d'\(words)" : "de \(words)" }()
            let late = "Parti à \(MailText.clock(at, calendar: calendar)) au lieu \(planned)"
            return ("« \(entry.subject) » : \(late.prefix(1).lowercased() + late.dropFirst()).",
                    MailScheduleNotice(title: "« \(entry.subject) »", body: "\(late) : \(lateReason(entry)).",
                                       threadKey: entry.threadKey, folder: .sent))
        case .held(let entry):
            let planned = MailText.scheduled(entry.sendAt, now: now, calendar: calendar)
            return ("« \(entry.subject) » n'est pas encore parti : il attend ton accord dans Programmés.",
                    MailScheduleNotice(title: "Pas encore parti", body: "« \(entry.subject) » était programmé pour \(planned) : \(lateReason(entry)). Il attend ton accord dans Programmés.",
                                       threadKey: entry.threadKey, folder: .scheduled))
        case .setAside:
            let text = "Polhub a trouvé dans le Trousseau une liste d'envois programmés qu'il n'avait pas écrite : il l'a écartée, rien n'en est parti."
            return (text, MailScheduleNotice(title: "Envois programmés", body: text, threadKey: nil, folder: .scheduled))
        case .stopped(let entry, let stop):
            let text = "« \(entry.subject) » n'est pas parti : \(stop)." + (stop == .vanished ? "" : " Il t'attend dans Brouillons.")
            return (text, MailScheduleNotice(title: "Mail non envoyé", body: text, threadKey: stop == .vanished ? nil : entry.threadKey,
                                             folder: stop == .vanished ? .scheduled : .drafts))
        case .maybeSent(let entry):
            let text = "« \(entry.subject) » est peut-être parti : Polhub s'est arrêté pendant son envoi. Regarde dans Envoyés avant de le renvoyer."
            return (text, MailScheduleNotice(title: "Mail programmé", body: text, threadKey: entry.threadKey, folder: .sent))
        }
    }

    /// Why a programmed mail is late, from when Polhub first tried to send it (wave B review): asleep or closed at its
    /// time, or awake while Gmail or the network did not answer.
    nonisolated static func lateReason(_ entry: ScheduledSend) -> String {
        entry.gmailWasLate ? "Gmail ne répondait pas à l'heure prévue" : "ton Mac était en veille ou Polhub fermé"
    }

    /// A notification's click: its folder, from the top.
    public func show(folderNamed name: String?) {
        guard let folder = name.flatMap(MailFolder.init(rawValue:)) else { return }
        if !query.isEmpty { query = "" }
        endSearch()
        self.folder = folder
    }

    /// Closing a new mail keeps it as a draft, unless nothing was written.
    public func closeComposer() {
        guard let id = composing else { return }
        composing = nil
        if let draft = try? store.draft(id), Self.isBlank(draft) {
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
        guard found == nil else { return }
        perform(.markRead, on: visible(inbox).filter { $0.unread && tab(of: $0) == tab })
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
