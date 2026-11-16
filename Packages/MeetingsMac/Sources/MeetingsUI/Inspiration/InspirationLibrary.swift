import Foundation
import GRDB
import Inspiration
import Persistence
import PolhubDesign
import ProjectsUI

/// The vault's import, as Réglages › Inspiration shows it.
public enum InspirationImportState: Equatable, Sendable {
    case idle
    /// `total` is 0 while the notes are counted.
    case running(done: Int, total: Int)
    case finished(InspirationImportReport)
    /// Stopped by Paul: what was imported stays.
    case cancelled
    case failed(String)
}

/// « Supprimer », while « Annuler » can bring the item back.
public struct InspirationUndo: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let text: String
    public let itemID: UUID
}

/// The three pages of « Inspiration » (16/11): the items of each kind kept up to date from the base, the search
/// and the filters of each page, the LinkedIn pages, and the gestures (categories, « Supprimer » with « Annuler »,
/// the additions through the collection, the vault's import). The page shown and the item open live in the
/// window's router (`WindowRouter.inspirationPage`, `.inspirationItem`), as Mails' folder and thread.
@MainActor
public final class InspirationLibrary: ObservableObject {
    @Published public private(set) var items: [InspirationKind: [InspirationItemRow]] = [:]
    /// The kinds read once from the base: no « Aucun site » flash at opening.
    @Published public private(set) var loaded: Set<InspirationKind> = []
    @Published public private(set) var sources: [InspirationSourceRow] = []
    /// Each page's search.
    @Published public private(set) var queries: [InspirationKind: String] = [:]
    /// Each page's filters: family → the one value chosen.
    @Published public private(set) var filters: [InspirationKind: [String: String]] = [:]
    /// What each page shows, and its rows of chips: worked out when the items, the search or the filters change,
    /// never while drawing.
    @Published public private(set) var shown: [InspirationKind: [InspirationItemRow]] = [:]
    @Published private(set) var chips: [InspirationKind: [InspirationBrowse.ChipRow]] = [:]
    @Published public private(set) var undoable: InspirationUndo?
    /// One line at the bottom of the page: what an addition or a collection answered.
    @Published public var message: String?
    @Published public private(set) var importState: InspirationImportState = .idle
    /// The last import's one line and its day, kept from one launch to the next.
    @Published public private(set) var lastImport: (summary: String, date: Date)?
    /// How the last collection went, place by place.
    @Published public private(set) var status: [InspirationStatusLine] = []
    @Published public private(set) var collecting = false
    /// An addition under way (« Ajouter un site », « Ajouter un mock-up »).
    @Published public private(set) var adding = false

    public let database: AppDatabase
    public let store: InspirationStore
    public let paths: AppPaths
    /// The collection; the app sets it once wired.
    public var services: InspirationServices
    let defaults: UserDefaults
    private var haystacks: [InspirationKind: [UUID: String]] = [:]
    private var vocabularies: [InspirationKind: InspirationVocabulary] = [:]
    private var observations: [AnyDatabaseCancellable] = []
    private var importTask: Task<Void, Never>?
    private var undoToken = 0

    /// The sidebar's « Inspiration », open or closed (a view's state, not a setting).
    public static let sidebarOpenKey = "inspiration.barreOuverte"
    /// The last import: « <seconds since 1970>|<summary> ».
    static let lastImportKey = "inspiration.dernierImport"

    public init(database: AppDatabase, paths: AppPaths, services: InspirationServices = .notConnected, defaults: UserDefaults = .standard) {
        self.database = database
        self.store = InspirationStore(database)
        self.paths = paths
        self.services = services
        self.defaults = defaults
        lastImport = Self.readLastImport(defaults)
        for kind in InspirationKind.allCases {
            observations.append(store.observeItems(kind: kind) { [weak self] rows in self?.received(rows, kind: kind) })
        }
        observations.append(store.observeSources { [weak self] rows in
            guard let self else { return }
            sources = rows
            recompute(.branding)
        })
    }

    // MARK: - Reading

    public func items(_ kind: InspirationKind) -> [InspirationItemRow] { items[kind] ?? [] }
    public func shown(_ kind: InspirationKind) -> [InspirationItemRow] { shown[kind] ?? [] }
    func chips(_ kind: InspirationKind) -> [InspirationBrowse.ChipRow] { chips[kind] ?? [] }

    /// An item in the lists (not one in the bin).
    public func item(_ id: UUID?) -> InspirationItemRow? {
        guard let id else { return nil }
        for kind in InspirationKind.allCases {
            if let item = items[kind]?.first(where: { $0.id == id }) { return item }
        }
        return nil
    }

    /// The categories' vocabulary of a kind: Polhub's copy of the vault's (brought by the import), else the one
    /// shipped with Polhub.
    public func vocabulary(_ kind: InspirationKind) -> InspirationVocabulary {
        if let vocabulary = vocabularies[kind] { return vocabulary }
        let vocabulary = InspirationVocabulary.load(kind, paths: paths)
        vocabularies[kind] = vocabulary
        return vocabulary
    }

    /// The file of an item's image.
    public func imageURL(_ item: InspirationItemRow, index: Int = 0) -> URL? {
        guard item.images.indices.contains(index) else { return nil }
        return paths.inspirationImages(item.kind).appending(path: item.images[index])
    }

    public func imageURLs(_ item: InspirationItemRow) -> [URL] {
        item.images.indices.compactMap { imageURL(item, index: $0) }
    }

    /// The color of a branding's dot.
    public func sourceColor(_ item: InspirationItemRow) -> String? {
        InspirationBrowse.sourceColor(item, sources: sources)
    }

    private func received(_ rows: [InspirationItemRow], kind: InspirationKind) {
        var index: [UUID: String] = [:]
        let previous = haystacks[kind] ?? [:]
        let before = Dictionary((items[kind] ?? []).map { ($0.id, $0.updatedAt) }, uniquingKeysWith: { first, _ in first })
        for row in rows {
            index[row.id] = before[row.id] == row.updatedAt ? previous[row.id] ?? InspirationBrowse.haystack(row) : InspirationBrowse.haystack(row)
        }
        haystacks[kind] = index
        items[kind] = rows
        loaded.insert(kind)
        recompute(kind)
    }

    private func recompute(_ kind: InspirationKind) {
        let rows = items[kind] ?? []
        let query = queries[kind] ?? ""
        let chosen = filters[kind] ?? [:]
        let index = haystacks[kind] ?? [:]
        shown[kind] = InspirationBrowse.filter(rows, query: query, filters: chosen, haystacks: index)
        // The values the filters chosen leave, counted without the words typed: what the search suggests and detects.
        chips[kind] = InspirationBrowse.chipRows(rows, kind: kind, vocabulary: vocabulary(kind), sources: sources, query: "",
                                                 filters: chosen, haystacks: index)
    }

    // MARK: - Search and filters

    public func query(_ kind: InspirationKind) -> String { queries[kind] ?? "" }

    /// What Paul types; a value typed in full, then a space, becomes a filter (« minimal », « Beyond Branding »).
    public func setQuery(_ query: String, for kind: InspirationKind) {
        guard queries[kind] ?? "" != query else { return }
        if let detected = InspirationBrowse.detect(query, in: chips(kind)) {
            var chosen = filters[kind] ?? [:]
            chosen[detected.token.family] = detected.token.value
            filters[kind] = chosen
            queries[kind] = detected.rest
        } else {
            queries[kind] = query
        }
        recompute(kind)
    }

    /// The filters chosen, as tokens of the search field, in the families' order.
    func tokens(_ kind: InspirationKind) -> [InspirationBrowse.InspirationToken] {
        let chosen = filters[kind] ?? [:]
        let order = InspirationBrowse.families(kind, vocabulary: vocabulary(kind), items: items(kind))
        let titles = Dictionary(order.map { ($0.name, $0.title) }, uniquingKeysWith: { first, _ in first })
        let rank = Dictionary(order.enumerated().map { ($0.element.name, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return chosen.sorted { (rank[$0.key] ?? .max, $0.key) < (rank[$1.key] ?? .max, $1.key) }.map { family, value in
            InspirationBrowse.InspirationToken(family: family, familyTitle: titles[family] ?? InspirationBrowse.label(family), value: value, count: 0,
                                               color: family == InspirationBrowse.sourceFamily ? InspirationBrowse.color(ofSource: value, in: sources) : nil)
        }
    }

    /// The field's tokens changed (one removed, one chosen in the suggestions): one value per family, the last one.
    func setTokens(_ tokens: [InspirationBrowse.InspirationToken], for kind: InspirationKind) {
        var chosen: [String: String] = [:]
        for token in tokens { chosen[token.family] = token.value }
        guard chosen != filters[kind] ?? [:] else { return }
        filters[kind] = chosen
        recompute(kind)
    }

    /// The filters to suggest for what is being typed.
    func suggestions(_ kind: InspirationKind) -> [InspirationBrowse.InspirationToken] {
        InspirationBrowse.suggestions(chips(kind), text: query(kind))
    }

    public func filter(_ kind: InspirationKind, family: String) -> String? { filters[kind]?[family] }

    /// One value per family; `nil` for « Tout ».
    public func setFilter(_ value: String?, family: String, for kind: InspirationKind) {
        var chosen = filters[kind] ?? [:]
        chosen[family] = value.flatMap { $0.isEmpty ? nil : $0 }
        filters[kind] = chosen
        recompute(kind)
    }

    /// « Tout afficher »: no filter, no search.
    public func clearFilters(_ kind: InspirationKind) {
        filters[kind] = [:]
        queries[kind] = ""
        recompute(kind)
    }

    public func hasFilters(_ kind: InspirationKind) -> Bool {
        !(filters[kind] ?? [:]).isEmpty || !InspirationBrowse.words(query(kind)).isEmpty
    }

    // MARK: - Gestures on an item

    /// Paul's categories: his from now on, never changed by an import nor by the AI.
    public func setCategories(_ item: InspirationItemRow, _ categories: [String: [String]]) {
        do {
            try store.setCategories(id: item.id, categories, at: Date())
        } catch {
            message = "Les catégories n'ont pas pu être enregistrées : \(Self.text(error))"
        }
    }

    public func toggleCategory(_ item: InspirationItemRow, family: String, value: String) {
        setCategories(item, InspirationBrowse.toggling(item.categories, family: family, value: value))
    }

    /// « Supprimer »: off the page, « Annuler » for a few seconds.
    public func moveToTrash(_ item: InspirationItemRow) {
        do {
            try store.moveToTrash(id: item.id, at: Date())
        } catch {
            message = "« \(item.title) » n'a pas pu être supprimé : \(Self.text(error))"
            return
        }
        undoToken += 1
        let token = undoToken
        undoable = InspirationUndo(text: "« \(item.title) » supprimé", itemID: item.id)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, undoToken == token else { return }
            undoable = nil
        }
    }

    public func undo() {
        guard let undo = undoable else { return }
        undoable = nil
        try? store.restore(id: undo.itemID, at: Date())
    }

    /// Apple's model proposes the item's categories.
    public func tag(_ item: InspirationItemRow) async {
        do {
            try await services.tag(item.id)
        } catch {
            message = Self.text(error)
        }
    }

    // MARK: - Additions and collection

    /// « Ajouter un site »: the address typed (`exemple.fr` reads as `https://exemple.fr`). Returns the item's id;
    /// throws what went wrong, in plain words.
    @discardableResult
    public func addSite(_ text: String) async throws -> UUID {
        guard let url = Self.siteURL(text) else { throw InspirationAddError.notAWebAddress }
        adding = true
        defer { adding = false }
        return try await services.addSite(url)
    }

    /// « Ajouter un mock-up »: its folder on the Mac. Returns the item's id.
    @discardableResult
    public func addMockup(folder: URL) async throws -> UUID {
        adding = true
        defer { adding = false }
        return try await services.addMockup(folder)
    }

    /// An address as typed: a scheme added when missing, a public site's only (the collection's own rule).
    nonisolated static func siteURL(_ text: String) -> URL? {
        InspirationCollector.siteURL(from: text)
    }

    public func collectNow() async {
        guard !collecting else { return }
        collecting = true
        defer { collecting = false }
        do {
            try await services.collectNow()
        } catch {
            message = Self.text(error)
        }
        await refreshStatus()
    }

    public func refreshStatus() async {
        status = await services.status()
    }

    /// The line of a place (« awwwards », a page's link).
    public func status(for id: String) -> InspirationStatusLine? {
        status.first { $0.id == id }
    }

    // MARK: - LinkedIn pages

    /// Adds a page, or changes the one of `id`: its link written one way (`InspirationSourceRow.normalizedLink`);
    /// a link that is not a company page is refused. Returns the problem, in plain words, or `nil`.
    @discardableResult
    public func saveSource(id: UUID? = nil, name: String, link: String, color: String?) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Donne un nom à la page." }
        let normalized = InspirationSourceRow.normalizedLink(link)
        guard normalized.hasPrefix("https://www.linkedin.com/company/") else {
            return "Ce lien n'est pas une page LinkedIn d'entreprise (linkedin.com/company/…)."
        }
        if let other = sources.first(where: { $0.link == normalized }), other.id != id {
            return "« \(other.name) » suit déjà cette page."
        }
        let existing = id.flatMap { id in sources.first { $0.id == id } }
        var row = existing ?? InspirationSourceRow(name: name, link: normalized, createdAt: Date())
        row.name = name
        row.link = normalized
        row.color = color.flatMap { InspirationBrowse.isHex($0) ? $0.uppercased() : nil }
        do {
            try store.saveSource(row)
            return nil
        } catch {
            return "La page n'a pas pu être enregistrée : \(Self.text(error))"
        }
    }

    public func deleteSource(_ source: InspirationSourceRow) {
        do {
            try store.deleteSource(id: source.id)
        } catch {
            message = "« \(source.name) » n'a pas pu être retirée : \(Self.text(error))"
        }
    }

    // MARK: - The vault's import

    /// The vault's folder, the one of Réglages › Projets (`ProjectLibrary.vaultKey`).
    public var vaultPath: String? {
        get { defaults.string(forKey: ProjectLibrary.vaultKey).flatMap { $0.isEmpty ? nil : $0 } }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: ProjectLibrary.vaultKey)
        }
    }

    /// « Ancienne copie (n8n) »: the old copy of the vault the n8n flows still write to.
    public var oldCopyPath: String? {
        get { Preferences(defaults: defaults).inspirationOldCopyFolder }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Preferences.Key.inspirationOldCopyFolder)
        }
    }

    public var importing: Bool {
        if case .running = importState { return true }
        return false
    }

    /// « Importer depuis le coffre »: reads the vault (and the old copy), never writes there. Run twice, it adds
    /// nothing.
    public func runImport() {
        guard importTask == nil else { return }
        guard !meetingUnderWay else {
            importState = .failed(Self.notDuringMeeting)
            return
        }
        guard let vault = vaultPath else {
            importState = .failed("Choisis d'abord le dossier du coffre.")
            return
        }
        let extra = oldCopyPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let database = database, paths = paths
        importState = .running(done: 0, total: 0)
        // The library lives as long as the app: the import holds it until it ends. Utility priority: it decodes
        // images on several cores, and Paul keeps working meanwhile (review of 16/11).
        importTask = Task(priority: .utility) {
            var state: InspirationImportState
            do {
                let report = try await InspirationImport.run(
                    vault: URL(fileURLWithPath: vault, isDirectory: true), extra: extra, database: database, paths: paths,
                    progress: { done, total in Task { @MainActor in self.progressed(done: done, total: total) } })
                state = .finished(report)
            } catch is CancellationError {
                state = .cancelled
            } catch {
                state = .failed("L'import n'a pas pu se faire : \(Self.text(error))")
            }
            if stoppedForMeeting { state = .failed(Self.stoppedByMeeting) }
            finishImport(state)
        }
    }

    public func cancelImport() {
        importTask?.cancel()
    }

    /// A meeting under way, from the pop-up to its end: no import.
    private var meetingUnderWay = false
    /// The import under way was stopped by a meeting.
    private var stoppedForMeeting = false
    static let stoppedByMeeting = "Import arrêté : une réunion a commencé. Relance-le à la fin, ce qui est fait reste."
    static let notDuringMeeting = "Pas d'import pendant une réunion : relance-le à la fin."

    /// A meeting starts or ends (the app's recorder): the import, which decodes images on several cores, stops, and
    /// none starts until the end (review of 16/11: it made the Mac lag during a call). Run again, it goes on.
    public func meetingActivity(_ busy: Bool) {
        meetingUnderWay = busy
        guard busy, importTask != nil else { return }
        stoppedForMeeting = true
        importTask?.cancel()
    }

    private func progressed(done: Int, total: Int) {
        guard importTask != nil, case .running(let before, _) = importState, done >= before else { return }
        importState = .running(done: done, total: total)
    }

    private func finishImport(_ state: InspirationImportState) {
        importTask = nil
        stoppedForMeeting = false
        importState = state
        // What was imported, even by an import stopped midway: the collection reads the vocabulary again and tags
        // the items without categories, in the background.
        switch state {
        case .finished, .cancelled:
            let services = services
            Task { await services.imported() }
        default:
            break
        }
        guard case .finished(let report) = state else { return }
        // The import brings the vault's live vocabulary into Polhub: the menus read it from now on.
        vocabularies = [:]
        InspirationKind.allCases.forEach(recompute)
        let now = Date()
        lastImport = (report.summary, now)
        defaults.set("\(Int(now.timeIntervalSince1970))|\(report.summary)", forKey: Self.lastImportKey)
    }

    static func readLastImport(_ defaults: UserDefaults) -> (summary: String, date: Date)? {
        guard let text = defaults.string(forKey: lastImportKey), let bar = text.firstIndex(of: "|"),
              let seconds = Double(text[..<bar]) else { return nil }
        return (String(text[text.index(after: bar)...]), Date(timeIntervalSince1970: seconds))
    }

    nonisolated static func text(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}
