import Domain
import Foundation
import GRDB
import Persistence
import VaultImport

/// The projects of the window, kept up to date from the base.
@MainActor
public final class ProjectLibrary: ObservableObject {
    @Published public private(set) var projects: [ProjectRow] = []
    /// The newest meeting filed in each project, in the app.
    @Published public private(set) var lastAppMeetings: [UUID: Date] = [:]
    /// False until the base has been read once: no « Aucun projet » flash at opening.
    @Published public private(set) var loaded = false
    /// The project whose page is open.
    @Published public var selected: UUID?
    /// Set by the window: opens a meeting from a project's page.
    public var openMeeting: ((UUID) -> Void)?
    public let store: ProjectStore
    public let meetings: MeetingStore
    private let defaults: UserDefaults
    private var observations: [AnyDatabaseCancellable] = []

    public static let vaultKey = "vaultPath"

    public init(store: ProjectStore, meetings: MeetingStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.meetings = meetings
        self.defaults = defaults
        observations.append(store.observeProjects { [weak self] rows in
            self?.projects = rows
            self?.loaded = true
        })
        // Filing a meeting changes « À surveiller » at once (review, minor 9).
        observations.append(store.observeLastMeetings { [weak self] last in self?.lastAppMeetings = last })
    }

    /// The vault the import reads (read-only), chosen once by Paul: no path is written in the code.
    public var vaultPath: String? {
        get { defaults.string(forKey: Self.vaultKey) }
        set { defaults.set(newValue, forKey: Self.vaultKey) }
    }

    public func move(_ id: UUID, to status: ProjectStatus, before: UUID?) {
        try? store.move(id, to: status, before: before)
    }

    @discardableResult
    public func add(name: String, status: ProjectStatus) -> ProjectRow? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try? store.addProject(name: trimmed, status: status, at: Date())
    }

    /// A change made on a project's page. A new status sends the card to the bottom of its new column,
    /// as a move on the board does (review, minor 8).
    public func save(_ project: ProjectRow) {
        var project = project
        if let stored = try? store.project(id: project.id), stored.status != project.status {
            try? store.move(project.id, to: project.status, before: nil)
            if let moved = try? store.project(id: project.id) { project.kanbanOrder = moved.kanbanOrder }
        }
        try? store.save(project, at: Date())
    }

    /// The vault, read off the main thread.
    public func readVault() async throws -> VaultSnapshot {
        guard let vaultPath else { throw VaultError.notAVault("(aucun dossier choisi)") }
        let vault = URL(fileURLWithPath: vaultPath, isDirectory: true)
        return try await Task.detached(priority: .userInitiated) { try VaultReader.read(vault: vault) }.value
    }

    public func apply(_ snapshot: VaultSnapshot) throws -> ImportReport {
        try ProjectImport.apply(snapshot, store: store, now: Date())
    }

    /// Replaces every project of the app with those of the vault.

    public func project(_ id: UUID?) -> ProjectRow? {
        id.flatMap { id in projects.first { $0.id == id } }
    }
}
