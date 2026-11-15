import AppKit
import Domain
import Foundation
import GRDB
import Persistence
import PolhubDesign
import SwiftUI

/// What Polhub keeps of a project's site and logo, in `Logos/sites.json`, outside the base (15/11).
public struct SiteEntry: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// Guessed from the contacts: kept to show it, guessed again when they change.
        case guessed = "deviné"
        /// Typed by Paul; no site when `site` is empty.
        case chosen = "choisi"
        /// Paul dropped an image: it wins over the site's icon. `site` is the one he typed, if any.
        case image
    }

    public var site: String?
    public var source: Source

    public init(site: String?, source: Source) {
        self.site = site
        self.source = source
    }
}

/// The site a project's logo comes from, and whether Polhub guessed it.
public struct ProjectSite: Equatable, Sendable {
    public let domain: String
    public let guessed: Bool
}

/// One look at a site for its icon: when, and whether it gave one.
struct LogoAttempt: Codable, Equatable, Sendable {
    let at: Date
    let ok: Bool

    /// At most one look a week at a site that answered, one a day at one that did not.
    static func allowsAnother(after attempt: LogoAttempt?, now: Date) -> Bool {
        guard let attempt else { return true }
        return now.timeIntervalSince(attempt.at) >= (attempt.ok ? 7 : 1) * 86_400
    }
}

/// The projects' logos (15/11): Paul's own image, else the icon of the project's site, asked lazily, the first time
/// a logo shows, never for a project Terminé, never with « Logos des sites des clients » off. Files in
/// `Application Support/Polhub/Logos`: `<domain>.png`, `<project>.png` (Paul's images), `sites.json`, `essais.json`.
@MainActor
public final class ProjectLogos: ObservableObject {
    /// Paul's choices, and the guesses shown.
    @Published public private(set) var entries: [UUID: SiteEntry] = [:]
    /// The sites guessed from the contacts, as the base says now.
    @Published public private(set) var guesses: [UUID: String] = [:]
    /// Bumped when a logo is written or removed: the views draw again.
    @Published public private(set) var revision = 0
    /// Bumped by « Rafraîchir les logos »: the logos on display ask their site again.
    @Published public private(set) var refreshes = 0

    public let folder: URL
    private let fetcher: any LogoFetching
    private let defaults: UserDefaults
    private let now: () -> Date
    private var attempts: [String: LogoAttempt] = [:]
    private var images: [String: NSImage?] = [:]
    private var waiting: [String] = []
    private var fetching = false
    private var observation: AnyDatabaseCancellable?

    public init(folder: URL, database: AppDatabase?, fetcher: any LogoFetching = LiveLogoFetcher(), defaults: UserDefaults = .standard,
                now: @escaping () -> Date = Date.init) {
        self.folder = folder
        self.fetcher = fetcher
        self.defaults = defaults
        self.now = now
        entries = Self.read([String: SiteEntry].self, folder.appending(path: Self.sitesFile)).reduce(into: [:]) { result, pair in
            if let id = UUID(uuidString: pair.key) { result[id] = pair.value }
        }
        attempts = Self.read([String: LogoAttempt].self, folder.appending(path: Self.attemptsFile))
        if let database {
            observation = ValueObservation.tracking(Self.readGuesses)
                .start(in: database.writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { [weak self] guesses in
                    MainActor.assumeIsolated { self?.apply(guesses: guesses) }
                })
        }
    }

    static let sitesFile = "sites.json"
    static let attemptsFile = "essais.json"

    /// The contacts' domains, read from the base: the links Paul did not remove, of the projects not in the bin.
    nonisolated static func readGuesses(_ db: Database) throws -> [UUID: String] {
        let links = try Row.fetchAll(db, sql: """
            SELECT contact.email AS email, contact_project.projectID AS projectID FROM contact_project
            JOIN contact ON contact.id = contact_project.contactID
            JOIN project ON project.id = contact_project.projectID
            WHERE contact_project.excluded = 0 AND contact.email IS NOT NULL AND project.deletedAt IS NULL
            """).compactMap { row -> ProjectSites.Link? in
            guard let email: String = row["email"], let id = (row["projectID"] as String?).flatMap(UUID.init(uuidString:)) else { return nil }
            return ProjectSites.Link(email: email, projectID: id)
        }
        let mine = Set(try String.fetchAll(db, sql: "SELECT lower(email) FROM google_account"))
        return ProjectSites.guesses(links, mine: mine)
    }

    /// New guesses: shown at once, and kept in `sites.json` for the projects Paul left to them.
    func apply(guesses: [UUID: String]) {
        self.guesses = guesses
        var changed = entries
        for (id, entry) in entries where entry.source == .guessed && guesses[id] == nil { changed[id] = nil }
        for (id, site) in guesses where changed[id] == nil || changed[id]?.source == .guessed {
            changed[id] = SiteEntry(site: site, source: .guessed)
        }
        if changed != entries {
            entries = changed
            saveEntries()
        }
    }

    // MARK: - Reading

    /// What Paul typed, else the guess; nothing when Paul said « no site ».
    public func site(for id: UUID) -> ProjectSite? {
        switch entries[id] {
        case let entry? where entry.source != .guessed:
            if let site = entry.site { return ProjectSite(domain: site, guessed: false) }
            // An image without a site of Paul's still shows the guess.
            if entry.source == .image, let guess = guesses[id] { return ProjectSite(domain: guess, guessed: true) }
            return nil
        default:
            return guesses[id].map { ProjectSite(domain: $0, guessed: true) }
        }
    }

    public func hasOwnImage(_ id: UUID) -> Bool { entries[id]?.source == .image }

    /// Paul's image, else the site's icon when the logos are on.
    public func image(for project: ProjectRow, online: Bool) -> NSImage? {
        if hasOwnImage(project.id), let own = loaded(Self.fileName(project: project.id)) { return own }
        guard online, let site = site(for: project.id), let name = Self.fileName(domain: site.domain) else { return nil }
        return loaded(name)
    }

    /// `exemple.fr.png`; nothing for a typed site that is not a site's name, which never becomes a path
    /// (correctifs, 15/11).
    static func fileName(domain: String) -> String? {
        ProjectSites.isFetchable(domain) ? "\(domain).png" : nil
    }
    static func fileName(project: UUID) -> String { "\(project.uuidString.lowercased()).png" }

    private func loaded(_ name: String) -> NSImage? {
        if let cached = images[name] { return cached }
        let url = folder.appending(path: name)
        let image = FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? NSImage(contentsOf: url) : nil
        images[name] = .some(image)
        return image
    }

    // MARK: - Asking the sites

    /// A logo shows: its site is asked, if it may be (logos on, not Terminé, not asked lately).
    public func request(_ project: ProjectRow) {
        guard Preferences(defaults: defaults).projectLogos, project.status != .termine, !hasOwnImage(project.id),
              let site = site(for: project.id), ProjectSites.isFetchable(site.domain),
              LogoAttempt.allowsAnother(after: attempts[site.domain], now: now()),
              !waiting.contains(site.domain) else { return }
        waiting.append(site.domain)
        pump()
    }

    /// « Logos des sites des clients » turned off: the sites still waiting are not asked (correctifs, 15/11).
    public func cancelPending() {
        // The site being asked stays first: its answer takes it off.
        let asked = fetching ? waiting.first : nil
        waiting = asked.map { [$0] } ?? []
    }

    /// One site at a time; none once the logos are off.
    private func pump() {
        guard !fetching else { return }
        guard Preferences(defaults: defaults).projectLogos else {
            waiting = []
            return
        }
        guard let domain = waiting.first else { return }
        fetching = true
        let fetcher = fetcher
        Task {
            let png = await fetcher.logo(for: domain)
            self.received(png, for: domain)
        }
    }

    /// A failure leaves the icon already there: it stays until a new one is written.
    private func received(_ png: Data?, for domain: String) {
        let ok = png.flatMap { png in Self.fileName(domain: domain).flatMap { try? write(png, name: $0) } } != nil
        attempts[domain] = LogoAttempt(at: now(), ok: ok)
        Self.write(attempts, to: folder.appending(path: Self.attemptsFile))
        waiting.removeAll { $0 == domain }
        fetching = false
        if ok { revision += 1 }
        pump()
    }

    /// Waits for the sites asked (tests).
    func settle() async {
        while fetching || !waiting.isEmpty { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @discardableResult
    private func write(_ png: Data, name: String) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try png.write(to: url, options: .atomic)
        images[name] = nil
        return url
    }

    // MARK: - Paul's choices

    /// The site Paul typed; empty, the project has none. The site shown, saved as it is (« Changer », then Entrée),
    /// changes nothing: a guess stays a guess (correctifs, 15/11).
    public func setSite(_ text: String, for id: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let domain = trimmed.isEmpty ? nil : ProjectSites.domain(trimmed) ?? trimmed.lowercased()
        guard domain != site(for: id)?.domain else { return }
        entries[id] = SiteEntry(site: domain, source: hasOwnImage(id) ? .image : .chosen)
        saveEntries()
        revision += 1
    }

    /// Back to the guess.
    public func clearSite(for id: UUID) {
        if hasOwnImage(id) {
            entries[id]?.site = nil
        } else {
            entries[id] = guesses[id].map { SiteEntry(site: $0, source: .guessed) }
        }
        saveEntries()
        revision += 1
    }

    /// An image file Paul chose, copied into `Logos/`: it wins over the site's icon. Read away from the main thread,
    /// and only an image file of 20 MB at most: a web address dragged from a browser is refused (correctifs, 15/11).
    @discardableResult
    public func setImage(from url: URL, for id: UUID) async -> Bool {
        guard url.isFileURL else { return false }
        let png = await Task.detached(priority: .userInitiated) { LogoImage.png(fromFileAt: url) }.value
        guard let png else { return false }
        return keep(png, for: id)
    }

    @discardableResult
    public func setImage(data: Data, for id: UUID) -> Bool {
        guard let png = LogoImage.png(fromFile: data) else { return false }
        return keep(png, for: id)
    }

    private func keep(_ png: Data, for id: UUID) -> Bool {
        guard (try? write(png, name: Self.fileName(project: id))) != nil else { return false }
        let typed = entries[id].flatMap { $0.source == .guessed ? nil : $0.site }
        entries[id] = SiteEntry(site: typed, source: .image)
        saveEntries()
        revision += 1
        return true
    }

    public func removeImage(for id: UUID) {
        try? FileManager.default.removeItem(at: folder.appending(path: Self.fileName(project: id)))
        images[Self.fileName(project: id)] = nil
        if let site = entries[id]?.site, entries[id]?.source == .image {
            entries[id] = SiteEntry(site: site, source: .chosen)
        } else {
            entries[id] = guesses[id].map { SiteEntry(site: $0, source: .guessed) }
        }
        saveEntries()
        revision += 1
    }

    /// « Rafraîchir les logos »: the sites are asked again, those on display at once, the others as they show. The
    /// icons stay until new ones are written: offline, or a site down, nothing goes back to initials (correctifs,
    /// 15/11). Paul's images stay.
    public func refreshAll() {
        attempts = [:]
        try? FileManager.default.removeItem(at: folder.appending(path: Self.attemptsFile))
        images = [:]
        refreshes += 1
        revision += 1
    }

    /// « Rafraîchir le logo » of one project: its site is asked again; its icon stays until a new one comes.
    public func refresh(_ project: ProjectRow) {
        guard let site = site(for: project.id), ProjectSites.isFetchable(site.domain) else { return }
        attempts[site.domain] = nil
        Self.write(attempts, to: folder.appending(path: Self.attemptsFile))
        request(project)
    }

    // MARK: - Files

    private func saveEntries() {
        Self.write(Dictionary(uniqueKeysWithValues: entries.map { ($0.key.uuidString.lowercased(), $0.value) }),
                   to: folder.appending(path: Self.sitesFile))
    }

    static func read<Value: Decodable & ExpressibleByDictionaryLiteral>(_ type: Value.Type, _ url: URL) -> Value {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(type, from: data)) ?? [:]
    }

    static func write(_ value: some Encodable, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

extension EnvironmentValues {
    /// The logos, set at the window's root; absent (tests, captures), every project shows its initials.
    @Entry public var projectLogos: ProjectLogos? = nil
}

// MARK: - The view

/// A project's logo: its image on a white plate, else its initials on its color.
public struct ProjectLogo: View {
    let project: ProjectRow
    let size: CGFloat
    @Environment(\.projectLogos) private var logos

    public init(_ project: ProjectRow, size: CGFloat) {
        self.project = project
        self.size = size
    }

    public var body: some View {
        if let logos {
            LiveProjectLogo(project: project, size: size, logos: logos)
        } else {
            ProjectMonogram(project: project, size: size)
        }
    }
}

struct LiveProjectLogo: View {
    let project: ProjectRow
    let size: CGFloat
    @ObservedObject var logos: ProjectLogos
    @AppStorage(Preferences.Key.projectLogos) private var online = true

    var body: some View {
        Group {
            if let image = logos.image(for: project, online: online) {
                let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                // The icon fills its square, without a margin (Paul, 15/11: « tu perds de la place »).
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .background(Color.white)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(Surface.stroke))
            } else {
                ProjectMonogram(project: project, size: size)
            }
        }
        .onAppear { logos.request(project) }
        .onChange(of: logos.refreshes) { logos.request(project) }
        .onChange(of: online) { _, on in
            if on { logos.request(project) } else { logos.cancelPending() }
        }
    }
}

/// The initials of a project, on its color.
struct ProjectMonogram: View {
    let project: ProjectRow
    let size: CGFloat

    var body: some View {
        let initials = ProjectViews.initials(project.name)
        Text(initials.isEmpty ? "·" : initials)
            .font(.system(size: size * (initials.count > 1 ? 0.42 : 0.5), weight: .bold, design: .rounded))
            .shadow(color: .black.opacity(0.18), radius: 0.5, y: 0.5)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(ProjectViews.tint(project).gradient, in: RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .accessibilityHidden(true)
    }
}
