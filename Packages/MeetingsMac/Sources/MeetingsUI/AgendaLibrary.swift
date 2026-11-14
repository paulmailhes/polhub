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
        for account in accounts {
            do {
                let token = try await session.accessToken(for: account.email)
                try await sync.sync(account: account.email, accessToken: token, store: store, now: Date())
            } catch {
                try? store.recordSync(email: account.email, syncToken: nil, error: "\(error)", at: Date())
            }
        }
        await runLinks()
    }

    /// The calendar's name for a recording that starts: the event of the same Meet code at that time (14/11).
    public nonisolated static func eventTitle(in database: AppDatabase, code: String?, at date: Date) -> String? {
        guard let code, let events = try? CalendarStore(database).events(meetCode: code) else { return nil }
        return Linker.event(forCode: code, at: date, among: events)?.title
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
