import Agenda
import AppKit
import Domain
import Foundation
import GRDB
import Persistence
import ProjectsUI
import PolhubDesign
import SwiftUI
import VaultImport

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
    @Published public private(set) var contacts: [ContactRow] = []
    @Published public private(set) var projects: [ProjectRow] = []
    @Published public private(set) var syncing = false
    @Published public private(set) var importing = false
    /// The last thing to tell Paul: a sync error, an import's report.
    @Published public var message: String?
    /// Set by the app: the notifications follow each reading of the calendars (14/11).
    public weak var notifications: NotificationHub?

    public let database: AppDatabase
    let session: GoogleSession
    let sync: CalendarSync
    /// The vault's folder, as chosen for the projects' import.
    let vaultPath: @MainActor () -> String?
    private var observations: [AnyDatabaseCancellable] = []

    public init(database: AppDatabase, session: GoogleSession = GoogleSession(), sync: CalendarSync = CalendarSync(),
                vaultPath: @escaping @MainActor () -> String? = { nil }) {
        self.database = database
        self.session = session
        self.sync = sync
        self.vaultPath = vaultPath
        observations = [
            CalendarStore(database).observeEvents { [weak self] in self?.events = $0 },
            CalendarStore(database).observeAccounts { [weak self] in self?.accounts = $0 },
            ContactStore(database).observeContacts { [weak self] in self?.contacts = $0 },
            ProjectStore(database).observeProjects { [weak self] in self?.projects = $0 },
        ]
    }

    private func refreshShown() {
        shown = EventCopies.merge(events, accounts: accounts)
        colors = AccountStyle.colors(for: accounts)
    }

    public var hasGoogleKey: Bool { FileManager.default.fileExists(atPath: GoogleClientConfig.file.path(percentEncoded: false)) }

    // MARK: - Google

    /// Opens Google's page in the browser; the account comes back connected, then synced.
    public func connect() async {
        do {
            let email = try await session.connect(open: { url in Task { @MainActor in NSWorkspace.shared.open(url) } })
            try CalendarStore(database).addAccount(email: email, at: Date())
            message = "Compte \(email) connecté."
            await syncAll()
        } catch {
            message = "Connexion impossible : \(error)"
        }
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
        let before = Set(((try? store.allEvents()) ?? []).map(\.id))
        let firstReading = Set(accounts.filter { $0.lastSyncAt == nil }.map(\.email))
        for account in accounts {
            do {
                let token = try await session.accessToken(for: account.email)
                try await sync.sync(account: account.email, accessToken: token, store: store, now: Date())
            } catch {
                try? store.recordSync(email: account.email, syncToken: nil, error: "\(error)", at: Date())
            }
        }
        await runLinks()
        await notifications?.afterSync(before: before, firstReading: firstReading)
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
            notifications?.madeFromPolhub(row.id)
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
        contacts.first { $0.email == email.lowercased() }
    }

    // MARK: - The vault's history

    /// The vault's contacts and old meetings, added without replacing anything.
    public func importHistory() async {
        guard let path = vaultPath() else {
            message = "Choisis d'abord le dossier du coffre (Réglages › Projets)."
            return
        }
        importing = true
        defer { importing = false }
        let database = database
        do {
            let report = try await Task.detached(priority: .userInitiated) {
                let report = try HistoryImport.apply(try HistoryReader.read(vault: URL(fileURLWithPath: path, isDirectory: true)), database: database, now: Date())
                try LinkRunner(database: database).run(now: Date())
                return report
            }.value
            message = "Historique importé : \(report.summary)."
        } catch {
            message = "L'import n'a pas pu se faire : \(error)"
        }
    }
}
