import Domain
import Foundation
import GRDB
import Persistence

/// The projects of the window, kept up to date from the base.
@MainActor
public final class ProjectLibrary: ObservableObject {
    @Published public private(set) var projects: [ProjectRow] = []
    /// The newest meeting filed in each project, in the app.
    @Published public private(set) var lastAppMeetings: [UUID: Date] = [:]
    /// The next event of each project, from the calendar (15/11).
    @Published public private(set) var nextEvents: [UUID: Date] = [:]
    /// False until the base has been read once: no « Aucun projet » flash at opening.
    @Published public private(set) var loaded = false
    /// The project whose page is open.
    @Published public var selected: UUID?
    /// Set by the window: opens a meeting from a project's page.
    public var openMeeting: ((UUID) -> Void)?
    /// Opens a contact, in Contacts (14/11).
    public var openContact: ((UUID) -> Void)?
    /// Opens a mail thread, in Mails (step « Ranger »).
    public var openMail: ((String) -> Void)?
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
        observations.append(store.observeNextEvents { [weak self] next in self?.nextEvents = next })
    }

    /// The vault the history import reads (read-only), chosen once by Paul: no path is written in the code.
    public var vaultPath: String? {
        get { defaults.string(forKey: Self.vaultKey) }
        set { defaults.set(newValue, forKey: Self.vaultKey) }
    }

    /// « Supprimer le projet » (15/11): off the board and every list; its page closes.
    public func trash(_ id: UUID) {
        try? store.moveToTrash(projectID: id, at: Date())
        if selected == id { selected = nil }
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

    /// A project made in the creation window, with every field it was given, at the bottom of its column.
    @discardableResult
    public func create(_ draft: ProjectRow) -> ProjectRow? {
        guard let added = add(name: draft.name, status: draft.status) else { return nil }
        var filled = draft
        filled.id = added.id
        filled.name = added.name
        filled.kanbanOrder = added.kanbanOrder
        filled.createdAt = added.createdAt
        filled.createdOn = draft.createdOn ?? added.createdAt
        try? store.saveChanges(from: added, to: filled, at: Date())
        return (try? store.project(id: added.id)) ?? nil
    }

    /// A change made on a project's page. A new status sends the card to the bottom of its new column,
    /// as a move on the board does (review, minor 8).
    /// A change on the project's page: only the fields that differ go over the stored project.
    public func save(from previous: ProjectRow, to changed: ProjectRow) {
        if previous.status != changed.status { try? store.move(changed.id, to: changed.status, before: nil) }
        try? store.saveChanges(from: previous, to: changed, at: Date())
    }

    public func save(_ project: ProjectRow) {
        var project = project
        if let stored = try? store.project(id: project.id), stored.status != project.status {
            try? store.move(project.id, to: project.status, before: nil)
            if let moved = try? store.project(id: project.id) { project.kanbanOrder = moved.kanbanOrder }
        }
        try? store.save(project, at: Date())
    }

    public func project(_ id: UUID?) -> ProjectRow? {
        id.flatMap { id in projects.first { $0.id == id } }
    }
}
