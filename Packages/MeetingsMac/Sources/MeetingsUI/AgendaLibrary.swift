import Agenda
import AppKit
import Domain
import Foundation
import GRDB
import Mail
import Persistence
import ProjectsUI
import PolhubDesign
import SwiftUI

/// Calendars, contacts and the loop, for the window: what the base holds, and Paul's gestures (13/11).
@MainActor
public final class AgendaLibrary: ObservableObject {
    /// Every copy, as the base holds them; the views show `shown`.
    @Published public private(set) var events: [CalendarEventRow] = [] { didSet { refreshShown() } }
    @Published public private(set) var accounts: [GoogleAccountRow] = [] { didSet { refreshShown() } }
    /// One row per Google event, under the account to join it with (14/11).
    @Published public private(set) var shown: [CalendarEventRow] = []
    /// Address → `#RRGGBB`.
    @Published public private(set) var colors: [String: String] = [:]
    @Published public private(set) var contacts: [ContactRow] = [] {
        didSet { contactsByEmail = Dictionary(contacts.compactMap { contact in contact.email.map { ($0, contact) } }, uniquingKeysWith: { first, _ in first }) }
    }
    /// Every link between a contact and a project, removed ones included (15/11).
    @Published public private(set) var links: [ContactProjectRow] = [] {
        didSet {
            var index: [UUID: [UUID: Bool]] = [:]
            for link in links { index[link.contactID, default: [:]][link.projectID] = link.excluded }
            linkIndex = index
        }
    }
    /// Contact → project → removed by Paul.
    private(set) var linkIndex: [UUID: [UUID: Bool]] = [:]
    private var contactsByEmail: [String: ContactRow] = [:]
    /// The mails, when Paul has some: the calendar writes to a guest and suggests whom to invite with them.
    weak var mails: MailLibrary?
    @Published public private(set) var projects: [ProjectRow] = []
    @Published public private(set) var syncing = false
    /// The last thing to tell Paul: a sync error, an account connected.
    @Published public var message: String?
    /// Set by the app: the notifications follow each reading of the calendars (14/11).
    public weak var notifications: NotificationHub?

    public let database: AppDatabase
    let session: GoogleSession
    let sync: CalendarSync
    private var observations: [AnyDatabaseCancellable] = []

    public init(database: AppDatabase, session: GoogleSession? = nil, sync: CalendarSync = CalendarSync()) {
        self.database = database
        // One session for the calendar and the mails; what each account granted is kept in the base (14/11).
        self.session = session ?? GoogleSession(onGrant: { email, scopes in
            try? CalendarStore(database).setGrantedScopes(email: email, scopes: scopes)
        })
        self.sync = sync
        observations = [
            CalendarStore(database).observeEvents { [weak self] in self?.events = $0 },
            CalendarStore(database).observeAccounts { [weak self] in self?.accounts = $0 },
            ContactStore(database).observeContacts { [weak self] in self?.contacts = $0 },
            ContactStore(database).observeLinks { [weak self] in self?.links = $0 },
            ProjectStore(database).observeProjects { [weak self] in self?.projects = $0 },
        ]
    }

    private func refreshShown() {
        shown = EventCopies.merge(events, accounts: accounts)
        colors = AccountStyle.colors(for: accounts)
    }

    public var hasGoogleKey: Bool { FileManager.default.fileExists(atPath: GoogleClientConfig.file.path(percentEncoded: false)) }

    // MARK: - Google

    /// Opens Google's page in the browser; the account comes back connected, then synced. A new account is asked
    /// for its calendar and its mails at once; it is kept as soon as it grants the calendar.
    public func connect() async {
        do {
            let email = try await session.connect(open: { url in Task { @MainActor in NSWorkspace.shared.open(url) } },
                                                  requesting: [.calendarEvents, .gmailModify], mustKeep: [.calendarEvents])
            try await keep(email)
            message = "Compte \(email) connecté."
            await syncAll()
        } catch {
            message = "Connexion impossible : \(error)"
        }
    }

    /// The account is in the base, with what it has just granted.
    private func keep(_ email: String) async throws {
        let store = CalendarStore(database)
        try store.addAccount(email: email, at: Date())
        if let scopes = await session.scopes(for: email) { try store.setGrantedScopes(email: email, scopes: scopes) }
    }

    // MARK: - Mails (14/11)

    /// Whether this account granted the mails, from its last token.
    public func mailGranted(_ account: GoogleAccountRow) -> Bool {
        GoogleOAuth.grants(.gmailModify, in: account.grantedScopes)
    }

    /// Opens Google's page to add the mails to an account already connected. An answer without the calendar is
    /// thrown away: asking for the mails never costs the account its calendar.
    public func authorizeMail(_ email: String) async {
        do {
            let granted = try await session.connect(open: { url in Task { @MainActor in NSWorkspace.shared.open(url) } },
                                                    requesting: [.calendarEvents, .gmailModify], mustKeep: [.calendarEvents], loginHint: email)
            try await keep(granted)
            let mails = await session.grants(.gmailModify, for: granted) ?? false
            if granted != email.lowercased() {
                message = "C'est \(granted) qui a été autorisé, pas \(email)."
            } else if mails {
                message = "Mails autorisés pour \(granted)."
            } else {
                message = "Google n'a pas donné l'accès aux mails de \(granted) : la case des mails est restée décochée."
            }
            await syncAll()
        } catch {
            message = "Autorisation impossible : \(error)"
        }
    }

    /// Sends Gmail requests under an account; a refusal says why (`GmailAPI.error`).
    func mailSend(for email: String) -> MailProbe.Send {
        { [session] build in try await session.send(build, for: email, mapping: { GmailAPI.error(status: $0, data: $1) }) }
    }

    public func disconnect(_ email: String) async {
        await session.forget(email)
        try? CalendarStore(database).removeAccount(email: email)
    }

    /// Every account, then the loop. Errors stay on the account (shown in Calendrier).
    public func syncAll() async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        let store = CalendarStore(database)
        // What the notifications compare with: the events before this reading, the accounts never read yet.
        let before = Set(((try? store.allEvents()) ?? []).map(\.eventID))
        let firstReading = Set(accounts.filter { $0.lastSyncAt == nil }.map(\.email))
        // The end of each account's previous reading window: what lies beyond only entered the sliding window.
        let windowEnds = Dictionary(accounts.compactMap { account in account.lastSyncAt.map { (account.email, $0.addingTimeInterval(CalendarSync.future)) } },
                                    uniquingKeysWith: { first, _ in first })
        for account in accounts {
            do {
                let token = try await session.accessToken(for: account.email)
                try await sync.sync(account: account.email, accessToken: token, store: store, now: Date())
            } catch {
                try? store.recordSync(email: account.email, syncToken: nil, error: "\(error)", at: Date())
            }
        }
        await runLinks()
        await notifications?.afterSync(before: before, firstReading: firstReading, windowEnds: windowEnds)
    }

    // MARK: - Writing (14/11)

    /// The description and Google's list of guests, read before changing an event; `nil` when Google could not
    /// be read (the description is then never sent: review of 14/11).
    public func details(of event: CalendarEventRow) async -> EventDetails? {
        let id = event.eventID
        guard let data = try? await session.send({ CalendarWrite.getRequest(accessToken: $0, eventID: id) }, for: event.account) else { return nil }
        return CalendarWrite.details(from: data)
    }

    /// Creates the event in the account's calendar, or changes it; Google sends the invitations.
    public func save(_ draft: EventDraft, account: String, editing: CalendarEventRow?, original: EventDraft? = nil,
                     details: EventDetails? = nil) async throws {
        await waitForSync()
        let requestID = UUID().uuidString, zone = TimeZone.current
        let data = try await session.send({ token in
            if let editing {
                return CalendarWrite.patchRequest(accessToken: token, event: editing, original: original ?? EventDraft(event: editing, notes: ""),
                                                  draft: draft, details: details, timeZone: zone, requestID: requestID)
            }
            return CalendarWrite.insertRequest(accessToken: token, draft: draft, timeZone: zone, requestID: requestID)
        }, for: account)
        if let row = try CalendarWrite.event(from: data, account: account) {
            notifications?.madeFromPolhub(row.eventID)
            try CalendarStore(database).applyGoogle(account: account, changed: [row], cancelled: [], at: Date())
        }
        // The copies in Paul's other calendars follow at once (review of 14/11).
        await waitForSync()
        await syncAll()
    }

    /// Deletes the event; its guests are told by Google.
    public func delete(_ event: CalendarEventRow) async throws {
        await waitForSync()
        let id = event.eventID
        _ = try await session.send({ CalendarWrite.deleteRequest(accessToken: $0, eventID: id) }, for: event.account)
        try CalendarStore(database).applyGoogle(account: event.account, changed: [], cancelled: [id], at: Date())
        await waitForSync()
        await syncAll()
    }

    /// A sync that reads Google while Polhub writes would put back what it read: writes wait for it (review of 14/11).
    private func waitForSync() async {
        for _ in 0..<300 where syncing { try? await Task.sleep(for: .milliseconds(100)) }
    }

    // MARK: - The agents' events (16/11)

    private var agentEvents: AgentEventMaker?
    private var agentRequests: ExternalChangeSignal.Listener?
    private var servingAgents = false
    private var serveAgentsAgain = false

    /// The events the agents ask for (`rendez_vous`; `polhub mcp` has no network): made at their signal, and those
    /// left from before at the launch. Réglages › Calendrier gives the default agenda and length.
    public func startAgentEvents(root: URL, flavor: AppFlavor = .current) {
        agentEvents = AgentEventMaker(database: database, root: root, flavor: flavor,
                                      send: { [session] account, build in try await session.send(build, for: account) },
                                      settings: {
                                          let settings = Preferences()
                                          return AgentEventMaker.Settings(defaultAccount: settings.defaultAccount,
                                                                          lastAccount: UserDefaults.standard.string(forKey: "dernierAgenda"),
                                                                          minutes: settings.eventMinutes)
                                      })
        agentRequests = ExternalChangeSignal.listen(name: AgentEventFiles.signal, queue: .main) { [weak self] in
            Task { @MainActor in await self?.serveAgentEvents() }
        }
        Task { await serveAgentEvents() }
    }

    /// One pass at a time; a signal during a pass makes it run once more. Paul is told of each event made. No wait for
    /// a sync under way: the agent waits only 25 s, and a sync keeps what Polhub writes meanwhile (review of 14/11).
    public func serveAgentEvents() async {
        guard let agentEvents else { return }
        if servingAgents {
            serveAgentsAgain = true
            return
        }
        servingAgents = true
        defer { servingAgents = false }
        repeat {
            serveAgentsAgain = false
            let made = await agentEvents.serve()
            guard let last = made.last else { continue }
            message = "Un agent a créé « \(last.title) » dans ton agenda."
            await runLinks()
        } while serveAgentsAgain
    }

    /// The calendar's name for a recording that starts: the event of the same Meet code at that time (14/11).
    public nonisolated static func eventTitle(in database: AppDatabase, code: String?, at date: Date) -> String? {
        guard let code, let events = try? CalendarStore(database).events(meetCode: code) else { return nil }
        // An untitled event leaves the tab's title (review of 14/11).
        return Linker.event(forCode: code, at: date, among: events).map(\.title).flatMap { $0 == "(sans titre)" ? nil : $0 }
    }

    /// The loop of 13/11, away from the main thread.
    public func runLinks() async {
        let database = database
        try? await Task.detached(priority: .utility) { try LinkRunner(database: database).run(now: Date()) }.value
    }

    // MARK: - Paul's gestures

    /// Paul files an event: it wins over every rule, in each calendar that has it, and its recording follows.
    public func setProject(_ event: CalendarEventRow, projectID: UUID?) async {
        try? CalendarStore(database).setProject(googleEventID: event.eventID, projectID: projectID, origin: .paul)
        for meetingID in Set(copies(of: event).compactMap(\.meetingID) + [event.meetingID].compactMap { $0 }) {
            try? ProjectStore(database).setProject(meetingID: meetingID, projectID: projectID)
        }
        await runLinks()
    }

    public func copies(of event: CalendarEventRow) -> [CalendarEventRow] {
        events.filter { $0.eventID == event.eventID }
    }

    /// The Meet, in Dia (whose meetings record themselves), under the event's account.
    public func join(_ event: CalendarEventRow) {
        guard let code = event.meetCode else { return }
        let url = MeetJoin.url(code: code, account: event.account)
        if let dia = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "company.thebrowser.dia") {
            NSWorkspace.shared.open([url], withApplicationAt: dia, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// A notification's « Rejoindre »: the Meet, in Dia, under that account.
    public func joinMeet(code: String, account: String) {
        let url = MeetJoin.url(code: code, account: account)
        if let dia = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "company.thebrowser.dia") {
            NSWorkspace.shared.open([url], withApplicationAt: dia, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    public func color(for account: String) -> Color {
        Color(hex: colors[account] ?? AccountStyle.gray)
    }

    public func setColor(_ hex: String?, for account: String) {
        try? CalendarStore(database).setColor(email: account, hex: hex)
    }

    public func remove(contact: ContactRow, from projectID: UUID) {
        try? ContactStore(database).exclude(contactID: contact.id, projectID: projectID, at: Date())
        objectWillChange.send()
    }

    public func add(contact: ContactRow, to projectID: UUID) {
        try? ContactStore(database).include(contactID: contact.id, projectID: projectID, at: Date())
        objectWillChange.send()
    }

    public func save(_ contact: ContactRow) {
        try? ContactStore(database).save(contact, at: Date())
    }

    public func projects(of contact: ContactRow) -> [ProjectRow] {
        (try? ContactStore(database).projects(contactID: contact.id)) ?? []
    }

    public func meetings(of contact: ContactRow) -> [MeetingRow] {
        (try? ContactStore(database).meetings(contactID: contact.id)) ?? []
    }

    public func events(of contact: ContactRow) -> [CalendarEventRow] {
        guard let email = contact.email else { return [] }
        return shown.filter { $0.attendees.contains { $0.email == email } }.reversed()
    }

    public func contact(email: String) -> ContactRow? {
        contactsByEmail[email.lowercased()]
    }
}
