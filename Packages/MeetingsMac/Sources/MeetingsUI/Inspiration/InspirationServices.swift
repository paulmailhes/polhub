import Foundation
import Inspiration
import Persistence

// What the pages of « Inspiration » ask of the collection (16/11): add a site or a mock-up, collect now, propose
// the categories of an item, say how the last runs went. The app wires these to the collection (target
// `Inspiration`, `Collect/` and `Tagging/`); until it does, each one says « pas encore branché ».

/// The collection, as the pages see it: async closures the app injects.
public struct InspirationServices: Sendable {
    /// Adds a site by its address: Polhub reads its title, its description and its image. Returns the item's id
    /// (the one already there when the site was known).
    public var addSite: @Sendable (URL) async throws -> UUID
    /// Adds a mock-up from its folder on the Mac (its preview made by Quick Look). Returns the item's id.
    public var addMockup: @Sendable (_ folder: URL) async throws -> UUID
    /// Collects now: Awwwards' site of the day, then the new posts of every LinkedIn page.
    public var collectNow: @Sendable () async throws -> Void
    /// How the last runs went, one line per place read (Awwwards, each LinkedIn page).
    public var status: @Sendable () async -> [InspirationStatusLine]
    /// Asks Apple's on-device model for an item's categories; never for one whose categories Paul chose.
    public var tag: @Sendable (_ itemID: UUID) async throws -> Void
    /// An import ended (finished or stopped): the vault's vocabulary is read again, and the items without
    /// categories are tagged in the background. Called without waiting for it.
    public var imported: @Sendable () async -> Void

    public init(
        addSite: @escaping @Sendable (URL) async throws -> UUID = { _ in throw InspirationServicesError.notConnected },
        addMockup: @escaping @Sendable (_ folder: URL) async throws -> UUID = { _ in throw InspirationServicesError.notConnected },
        collectNow: @escaping @Sendable () async throws -> Void = { throw InspirationServicesError.notConnected },
        status: @escaping @Sendable () async -> [InspirationStatusLine] = { [] },
        tag: @escaping @Sendable (_ itemID: UUID) async throws -> Void = { _ in throw InspirationServicesError.notConnected },
        imported: @escaping @Sendable () async -> Void = {}
    ) {
        self.addSite = addSite
        self.addMockup = addMockup
        self.collectNow = collectNow
        self.status = status
        self.tag = tag
        self.imported = imported
    }

    /// Nothing wired yet: every action says so.
    public static let notConnected = InspirationServices()

    /// The app's collection (target `Inspiration`): every gesture goes to `automation`; the LinkedIn pages are read
    /// from `database` to put each page's line on its row.
    public static func collection(_ automation: InspirationAutomation, database: AppDatabase) -> InspirationServices {
        let store = InspirationStore(database)
        return InspirationServices(
            addSite: { url in try await automation.addSite(url: url) },
            addMockup: { folder in try await automation.addMockup(folder: folder) },
            collectNow: { await automation.collectNow() },
            status: { InspirationStatusLine.lines(await automation.statuses(), sources: (try? store.sources()) ?? []) },
            tag: { id in try await automation.tag(id: id) },
            imported: { await automation.imported() }
        )
    }
}

/// The last run on one place: Awwwards, or a LinkedIn page.
public struct InspirationStatusLine: Identifiable, Equatable, Sendable {
    /// `awwwards`, or the page's link (`InspirationSourceRow.link`): the line of a page shows on its row.
    public var id: String
    /// « Awwwards », « Studio Exemple ».
    public var name: String
    public var lastRun: Date?
    /// What went wrong, in plain words (« LinkedIn demande une connexion ») ; `nil` when it went well.
    public var problem: String?
    /// The items this run added; `nil` when not known (a reading restored from the base, a problem).
    public var added: Int?

    public init(id: String, name: String, lastRun: Date? = nil, problem: String? = nil, added: Int? = nil) {
        self.id = id
        self.name = name
        self.lastRun = lastRun
        self.problem = problem
        self.added = added
    }

    /// The collection's readings as Réglages shows them: Awwwards under `awwwards`, a LinkedIn page under its link
    /// (a page no longer followed is left out).
    public static func lines(_ statuses: [CollectionStatus], sources: [InspirationSourceRow]) -> [InspirationStatusLine] {
        let links = Dictionary(sources.map { ($0.id, $0.link) }, uniquingKeysWith: { first, _ in first })
        return statuses.compactMap { status in
            let id: String
            switch status.source {
            case .awwwards: id = "awwwards"
            case .linkedIn(let page):
                guard let link = links[page] else { return nil }
                id = link
            }
            var added: Int?
            if case .read(let count?) = status.outcome { added = count }
            return InspirationStatusLine(id: id, name: status.name, lastRun: status.date, problem: status.problem, added: added)
        }
    }
}

public enum InspirationServicesError: Error, Equatable, LocalizedError, CustomStringConvertible {
    case notConnected

    public var description: String {
        switch self {
        case .notConnected: "Pas encore branché."
        }
    }

    public var errorDescription: String? { description }
}
