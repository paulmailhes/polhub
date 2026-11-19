import Foundation
import Persistence

/// Why an item could not be added by hand, in plain words.
public enum InspirationAddError: Error, Equatable, Sendable, CustomStringConvertible, LocalizedError {
    /// Not the address of a public site (`file:`, `localhost`, a private address, no domain).
    case notAWebAddress
    case offline
    case notAFolder

    public var description: String {
        switch self {
        case .notAWebAddress: "Cette adresse n'est pas celle d'un site public."
        case .offline: "Pas de connexion à Internet : réessaie plus tard."
        case .notAFolder: "Ce n'est pas un dossier."
        }
    }

    public var errorDescription: String? { description }
}

/// The collection of « Inspiration » (16/11), in the app, without account nor cookie, as n8n did it:
/// - `collectWebsites`: Awwwards' site of the day, its OpenGraph tags and image (else Awwwards' thumbnail);
/// - `collectBranding`: the ten latest posts of each LinkedIn page followed, each new one completed by its public
///   embed page (text, links, up to five still images);
/// - `addSite` and `addMockup`: by hand, from Polhub's pages.
///
/// No timer here: the app calls these when `CollectionSchedule` says a collection is due. Requests go one at a
/// time, with a short pause between two LinkedIn pages; a login wall, a 999 or a 429 skips that page until the next
/// run and is kept in `inspiration_source.lastError`. Two collections of the same kind never overlap. Nothing is
/// ever added twice: the keys the base knows (deleted items and merged duplicates included) are skipped.
public actor InspirationCollector {
    public struct Configuration: Sendable {
        /// An image heavier than this is left aside.
        public var maxImageBytes: Int
        /// A page is read up to this.
        public var maxPageBytes: Int
        /// The images a branding post keeps, the first still image first.
        public var maxBrandingImages: Int
        /// Between two calls to LinkedIn's pages.
        public var linkedInPause: Duration

        public init(maxImageBytes: Int = 30 * 1_048_576, maxPageBytes: Int = 3 * 1_048_576, maxBrandingImages: Int = 5,
                    linkedInPause: Duration = .seconds(2)) {
            self.maxImageBytes = maxImageBytes
            self.maxPageBytes = maxPageBytes
            self.maxBrandingImages = maxBrandingImages
            self.linkedInPause = linkedInPause
        }
    }

    let store: InspirationStore
    let paths: AppPaths
    let http: any InspirationHTTP
    let thumbnailer: any MockupThumbnailing
    let runLog: CollectionRunLog?
    let configuration: Configuration
    let sleep: @Sendable (Duration) async throws -> Void
    private let shrinker = ImageShrinker()
    private var running: Set<CollectionJob> = []
    private var latest: [CollectionStatus.Source: CollectionStatus] = [:]
    private var lastLinkedInCall: Bool = false
    /// Posts that gave neither words nor image: not asked again (the run log keeps them across launches).
    private var unreadable: Set<String> = []
    /// The image addresses of imported sites already asked, whether the image came or not.
    private var imagesAsked: Set<String> = []
    /// What Réglages says of a page whose posts were all found but none could be read.
    public static let unreadablePosts = "Posts illisibles : LinkedIn a peut-être changé sa page"

    /// `runLog`: where the last runs and Awwwards' last state are kept (`nil`: nowhere, as in the tests).
    /// `sleep`: how the pause between LinkedIn calls waits (the tests count it instead).
    public init(database: AppDatabase, paths: AppPaths, http: any InspirationHTTP = LiveInspirationHTTP(),
                thumbnailer: any MockupThumbnailing = QuickLookThumbnailer(), runLog: CollectionRunLog? = nil,
                configuration: Configuration = Configuration(),
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.store = InspirationStore(database)
        self.paths = paths
        self.http = http
        self.thumbnailer = thumbnailer
        self.runLog = runLog
        self.configuration = configuration
        self.sleep = sleep
    }

    // MARK: - Status

    /// The last reading of each source: Awwwards first, then the LinkedIn pages by name. A page not read since the
    /// launch shows what the base kept of its last reading; a page never read has no line.
    public func statuses() -> [CollectionStatus] {
        var result: [CollectionStatus] = []
        if let awwwards = latest[.awwwards] ?? runLog?.awwwards { result.append(awwwards) }
        for page in (try? store.sources()) ?? [] {
            let kept = CollectionStatus(page: page)
            if let fresh = latest[.linkedIn(page.id)], fresh.date >= (kept?.date ?? .distantPast) {
                result.append(fresh)
            } else if let kept {
                result.append(kept)
            }
        }
        return result
    }

    // MARK: - Websites

    /// Awwwards' site of the day, added when the base does not know its address yet.
    public func collectWebsites(now: Date = Date()) async -> CollectionRun {
        guard running.insert(.websites).inserted else { return CollectionRun(job: .websites, skipped: true) }
        defer { running.remove(.websites) }
        var run = CollectionRun(job: .websites)
        let outcome: CollectionStatus.Outcome
        do {
            outcome = try await siteOfTheDay(now: now, run: &run)
        } catch {
            // Stopped (the app quits, a meeting starts): nothing said, nothing counted.
            if error is CancellationError || Task.isCancelled { return run }
            outcome = Self.outcome(of: error, site: "Awwwards")
        }
        let status = CollectionStatus(source: .awwwards, name: "Awwwards", date: now, outcome: outcome)
        latest[.awwwards] = status
        run.statuses = [status]
        runLog?.setAwwwards(status)
        if !run.wasOffline { runLog?.setLastRun(.websites, now) }
        return run
    }

    private func siteOfTheDay(now: Date, run: inout CollectionRun) async throws -> CollectionStatus.Outcome {
        let response = try await http.get(InspirationRequest(url: AwwwardsHome.address, purpose: .page, limit: configuration.maxPageBytes))
        guard response.isSuccess else { return .failed("Awwwards n'a pas répondu (erreur \(response.status)) : réessai au prochain tour") }
        guard let home = AwwwardsHome.parse(response.text, base: response.url), PublicWeb.isAllowed(home.site),
              let key = InspirationKeys.website(home.site.absoluteString) else {
            return .failed("Le site du jour est introuvable sur la page d'Awwwards : réessai au prochain tour")
        }
        guard !(try store.knownKeys(kind: .website)).contains(key) else { return .read(newItems: 0) }
        let item = try await siteItem(url: home.site, key: key, fallbackImage: home.thumbnail, links: home.page.map { [$0.absoluteString] } ?? [], now: now)
        try Task.checkCancellation()
        let result = try store.upsert(item, at: now)
        switch result.outcome {
        case .added: run.added.append(result.item)
        case .updated: run.updated += 1
        case .unchanged: break
        }
        return .read(newItems: run.added.count)
    }

    /// A site's item from its page's OpenGraph tags: its title (else its host), its description, its image made
    /// light (else `fallbackImage`). A page or an image that cannot be read still gives an item, named after its
    /// host; only a lost connection stops, at the image too (audit of 19/11: the site was kept grey for good).
    private func siteItem(url: URL, key: String, fallbackImage: URL?, links: [String], now: Date) async throws -> InspirationItemRow {
        var graph = OpenGraph()
        var base = url
        do {
            let page = try await http.get(InspirationRequest(url: url, purpose: .page, limit: configuration.maxPageBytes))
            if page.isSuccess {
                graph = OpenGraph.parse(page.text)
                base = page.url
            }
        } catch let error as URLError where Self.isOffline(error) {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Refused, too slow: the item stays, with Awwwards' thumbnail when there is one.
        }
        let name = InspirationImageName.website(key: key)
        let destination = paths.inspirationImages(.website).appending(path: name)
        var images: [String] = []
        for candidate in [graph.imageURL(base: base), fallbackImage].compactMap({ $0 }) {
            try Task.checkCancellation()
            do {
                try await fetchImage(candidate, to: destination)
                images = [name]
                break
            } catch let error as URLError where Self.isOffline(error) {
                throw error
            } catch {
                // Not an image, too heavy, refused by its server: the next candidate.
            }
        }
        let host = url.host(percentEncoded: false).map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? key
        return InspirationItemRow(kind: .website, key: key, title: graph.title ?? host, text: graph.description ?? "",
                                  url: url.absoluteString, links: links, date: now, images: images, createdAt: now)
    }

    // MARK: - Branding

    /// The new posts of every LinkedIn page followed.
    public func collectBranding(now: Date = Date()) async -> CollectionRun {
        guard running.insert(.branding).inserted else { return CollectionRun(job: .branding, skipped: true) }
        defer { running.remove(.branding) }
        var run = CollectionRun(job: .branding)
        lastLinkedInCall = false
        let pages: [InspirationSourceRow]
        var known: Set<String>
        var projects: [String: InspirationItemRow]
        unreadable.formUnion(runLog?.unreadablePosts ?? [])
        do {
            pages = try store.sources()
            known = try store.knownKeys(kind: .branding).union(unreadable)
            projects = Self.projectIndex(try store.allItems(kind: .branding))
        } catch {
            return run
        }
        for page in pages {
            if Task.isCancelled { return run }
            let outcome: CollectionStatus.Outcome
            do {
                outcome = try await read(page, known: &known, projects: &projects, run: &run, now: now)
            } catch {
                if error is CancellationError || Task.isCancelled { return run }
                outcome = Self.outcome(of: error, site: "LinkedIn")
            }
            let status = CollectionStatus(source: .linkedIn(page.id), name: page.name, date: now, outcome: outcome)
            latest[status.source] = status
            run.statuses.append(status)
            try? store.markSourceRead(id: page.id, at: now, error: status.problem)
        }
        if !run.wasOffline { runLog?.setLastRun(.branding, now) }
        return run
    }

    private func read(_ page: InspirationSourceRow, known: inout Set<String>, projects: inout [String: InspirationItemRow],
                      run: inout CollectionRun, now: Date) async throws -> CollectionStatus.Outcome {
        guard let address = URL(string: InspirationSourceRow.normalizedLink(page.link)), PublicWeb.isAllowed(address) else {
            return .failed("Lien de la page invalide : vérifie-le")
        }
        let response = try await linkedIn(InspirationRequest(url: address, purpose: .page, limit: configuration.maxPageBytes))
        if let refusal = Self.refusal(response) { return refusal }
        guard response.isSuccess else { return .failed("LinkedIn n'a pas répondu (erreur \(response.status)) : réessai au prochain tour") }
        let articles: [LinkedInPublic.Article]
        switch LinkedInPublic.companyPage(response.text, url: response.url) {
        case .loginWall: return .loginWall
        case .noPosts: return .noPosts
        case .posts(let found): articles = found
        }
        var added = 0
        var embedsAllowed = true
        for article in articles where !known.contains(article.urn) {
            try Task.checkCancellation()
            var content = LinkedInPublic.content(of: article)
            // The embed page gives more: the whole text, five images in high resolution. Refused, the page's own
            // card is enough, and LinkedIn is not asked again for this page this time.
            if embedsAllowed {
                do {
                    let embed = try await linkedIn(InspirationRequest(url: LinkedInPublic.embedURL(urn: article.urn), purpose: .page,
                                                                      limit: configuration.maxPageBytes))
                    if [999, 429].contains(embed.status) || LinkedInPublic.isLoginAddress(embed.url) {
                        embedsAllowed = false
                    } else if embed.isSuccess, let full = LinkedInPublic.embed(embed.text, url: embed.url, urn: article.urn) {
                        content = Self.combine(full, content)
                    }
                } catch let error as URLError where Self.isOffline(error) {
                    throw error
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // The card is enough.
                }
            }
            guard !content.text.isEmpty || !content.images.isEmpty else {
                // Remembered, so that its embed page is not asked at every run.
                unreadable.insert(article.urn)
                known.insert(article.urn)
                runLog?.addUnreadable([article.urn])
                continue
            }
            // The page that posted it is not one of the post's links.
            let ownPage = InspirationSourceRow.normalizedLink(page.link)
            let links = content.links.filter { InspirationSourceRow.normalizedLink($0.hasSuffix("/") ? $0 : $0 + "/") != ownPage }
            let post = LinkedInPublic.post(text: content.text, links: links, urn: article.urn)
            var item = InspirationItemRow(
                kind: .branding, key: article.urn, title: post.title, text: post.body, url: LinkedInPublic.postURL(urn: article.urn),
                links: post.links, date: InspirationKeys.publicationDate(urn: article.urn) ?? now, sources: [page.name],
                studio: post.studio, extra: InspirationExtra(hashtags: post.hashtags.isEmpty ? nil : post.hashtags), createdAt: now)
            // The same project already posted by another page: one item, both pages on it.
            let signature = Self.signature(item)
            let sameProject = signature.flatMap { projects[$0] }
            if let sameProject {
                item.key = sameProject.key
                item.extra.aliases = [article.urn]
            }
            let wanted = min(configuration.maxBrandingImages, content.images.count)
            if sameProject?.deletedAt == nil, wanted > (sameProject?.images.count ?? 0) {
                item.images = try await brandingImages(content.images, key: item.key)
            }
            try Task.checkCancellation()
            let result = try store.upsert(item, at: now)
            switch result.outcome {
            case .added:
                run.added.append(result.item)
                added += 1
            case .updated:
                run.updated += 1
            case .unchanged:
                break
            }
            known.insert(article.urn)
            if let signature { projects[signature] = result.item }
        }
        // Every post of the page unreadable: LinkedIn changed something, said rather than « aucun nouveau post ».
        if !articles.isEmpty, articles.allSatisfy({ unreadable.contains($0.urn) }) { return .failed(Self.unreadablePosts) }
        return .read(newItems: added)
    }

    /// One call to LinkedIn's pages, after a short pause when another came before.
    private func linkedIn(_ request: InspirationRequest) async throws -> InspirationResponse {
        if lastLinkedInCall, configuration.linkedInPause > .zero {
            try await sleep(configuration.linkedInPause)
        }
        lastLinkedInCall = true
        return try await http.get(request)
    }

    /// The post's images made light, the first still image first (a GIF's first frame is often blank), named
    /// `<key>-1.jpg`… in that order. An image that cannot be had is left aside; a lost connection deletes the images
    /// already downloaded and throws, so that the post is not kept without them but read again at the next run
    /// (audit of 19/11: it kept two images out of five for good).
    private func brandingImages(_ candidates: [String], key: String) async throws -> [String] {
        let folder = paths.inspirationImages(.branding)
        var fetched: [(file: URL, animated: Bool)] = []
        for address in candidates {
            guard fetched.count < configuration.maxBrandingImages, !Task.isCancelled else { break }
            guard let url = URL(string: address) else { continue }
            let partial = folder.appending(path: ".\(key)-\(UUID().uuidString).partiel.jpg")
            do {
                let animated = try await fetchImage(url, to: partial)
                fetched.append((partial, animated))
            } catch let error as URLError where Self.isOffline(error) {
                for image in fetched { try? FileManager.default.removeItem(at: image.file) }
                throw error
            } catch {
                // Too heavy, not an image, refused by its server: left aside.
            }
        }
        if let still = fetched.firstIndex(where: { !$0.animated }), still > 0 {
            fetched.insert(fetched.remove(at: still), at: 0)
        }
        var names: [String] = []
        let manager = FileManager.default
        for (index, image) in fetched.enumerated() {
            let name = InspirationImageName.branding(urn: key, index: index + 1)
            let destination = folder.appending(path: name)
            do {
                if manager.fileExists(atPath: destination.path(percentEncoded: false)) {
                    _ = try manager.replaceItemAt(destination, withItemAt: image.file)
                } else {
                    try manager.moveItem(at: image.file, to: destination)
                }
                names.append(name)
            } catch {
                try? manager.removeItem(at: image.file)
            }
        }
        return names
    }

    /// The text the longer of the two, the images and links of both (the embed's first: better defined).
    static func combine(_ embed: LinkedInPublic.Content, _ card: LinkedInPublic.Content) -> LinkedInPublic.Content {
        LinkedInPublic.Content(text: embed.text.count >= card.text.count ? embed.text : card.text,
                               images: LinkedInPublic.bestImages(embed.images + card.images),
                               links: InspirationMerge.union(embed.links, card.links))
    }

    /// Title and studio, folded: the same project posted by two pages.
    static func signature(_ item: InspirationItemRow) -> String? {
        guard let studio = item.studio, !studio.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return InspirationKeys.fold(item.title) + "|" + InspirationKeys.fold(studio)
    }

    static func projectIndex(_ items: [InspirationItemRow]) -> [String: InspirationItemRow] {
        var index: [String: InspirationItemRow] = [:]
        for item in items.reversed() {
            if let signature = signature(item) { index[signature] = item }
        }
        return index
    }

    /// LinkedIn's refusals: 999, 429, a login wall.
    static func refusal(_ response: InspirationResponse) -> CollectionStatus.Outcome? {
        switch response.status {
        case 999: return .refused
        case 429: return .slowDown
        case 404, 410: return .notFound
        default: return LinkedInPublic.isLoginAddress(response.url) ? .loginWall : nil
        }
    }

    // MARK: - Imported images

    /// The sites imported with their image known only by its address (a Web Clipper note): downloaded and made
    /// light as a collected one's, each address once while Polhub runs, whether it came or not (review of 16/11:
    /// those cards stayed grey for good). Returns how many sites got their image.
    public func completeImages(now: Date = Date()) async -> Int {
        guard let items = try? store.allItems(kind: .website) else { return 0 }
        var completed = 0
        for item in items where item.images.isEmpty && item.deletedAt == nil {
            guard !Task.isCancelled else { break }
            guard let address = item.extra.imageURL, imagesAsked.insert(address).inserted, let url = URL(string: address) else { continue }
            let name = InspirationImageName.website(key: item.key)
            guard (try? await fetchImage(url, to: paths.inspirationImages(.website).appending(path: name))) != nil, !Task.isCancelled else { continue }
            var completedItem = item
            completedItem.images = [name]
            if (try? store.upsert(completedItem, at: now)) != nil { completed += 1 }
        }
        return completed
    }

    // MARK: - By hand

    /// The address Paul typed: `exemple.fr`, `https://exemple.fr/projets`; `nil` when it is not a public site's.
    public nonisolated static func siteURL(from text: String) -> URL? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), PublicWeb.isAllowed(url) else { return nil }
        return url
    }

    /// A site by its address: its title, description and image, as a collected one. Known already, it is
    /// brought back from the bin when Paul had deleted it, and completed when it had no image.
    @discardableResult
    public func addSite(url: URL, now: Date = Date()) async throws -> InspirationItemRow {
        guard PublicWeb.isAllowed(url), let key = InspirationKeys.website(url.absoluteString) else { throw InspirationAddError.notAWebAddress }
        if var existing = try store.item(kind: .website, key: key) {
            if existing.deletedAt != nil {
                try store.restore(id: existing.id, at: now)
                existing.deletedAt = nil
            }
            if !existing.images.isEmpty { return existing }
        }
        let item: InspirationItemRow
        do {
            item = try await siteItem(url: url, key: key, fallbackImage: nil, links: [], now: now)
        } catch let error as URLError where Self.isOffline(error) {
            throw InspirationAddError.offline
        }
        return try store.upsert(item, at: now).item
    }

    /// A mock-up by its folder on the Mac: its key is the folder's name (as the vault's mock-ups), its preview the
    /// Finder's thumbnail of its preview image, else of its first image, else of its PSD or PSB. The files stay
    /// where they are. Known already, it keeps its title and image and learns its folder.
    @discardableResult
    public func addMockup(folder: URL, now: Date = Date()) async throws -> InspirationItemRow {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        var isFolder: ObjCBool = false
        guard folder.isFileURL, FileManager.default.fileExists(atPath: folder.path(percentEncoded: false), isDirectory: &isFolder),
              isFolder.boolValue else { throw InspirationAddError.notAFolder }
        let name = folder.standardizedFileURL.lastPathComponent.precomposedStringWithCanonicalMapping
        var existing = try store.item(kind: .mockup, key: name)
        if let found = existing, found.deletedAt != nil {
            try store.restore(id: found.id, at: now)
            existing?.deletedAt = nil
        }
        var images: [String] = []
        if existing?.images.isEmpty != false, let file = MockupFolder.previewFile(in: folder) {
            let preview = InspirationImageName.mockup(folder: name)
            if await makePreview(of: file, to: paths.inspirationImages(.mockup).appending(path: preview)) { images = [preview] }
        }
        let item = InspirationItemRow(kind: .mockup, key: name, title: existing?.title ?? name, date: existing?.date ?? now, images: images,
                                      extra: InspirationExtra(localFolder: folder.standardizedFileURL.path(percentEncoded: false)), createdAt: now)
        return try store.upsert(item, at: now).item
    }

    /// Quick Look's image of the file, else ImageIO's (a PSD reads), made light.
    private func makePreview(of file: URL, to destination: URL) async -> Bool {
        if let png = try? await thumbnailer.thumbnail(of: file, maxSide: ImageShrinker.maxSide),
           (try? shrinker.shrink(data: png, to: destination)) != nil {
            return true
        }
        return (try? shrinker.shrink(file: file, to: destination)) != nil
    }

    // MARK: - Images and errors

    /// Downloads an image (a GIF up to its first frame), checks it is one, writes it light; returns whether it was
    /// animated.
    @discardableResult
    private func fetchImage(_ url: URL, to destination: URL) async throws -> Bool {
        guard PublicWeb.isAllowed(url) else { throw InspirationFetchError.refusedAddress }
        let response = try await http.get(InspirationRequest(url: url, purpose: .image, limit: configuration.maxImageBytes,
                                                             isEnough: GIFData.firstFrameIsComplete))
        guard response.isSuccess, RemoteImage.isAcceptable(response.body, contentType: response.contentType) else {
            throw ImageShrinkError.notAnImage
        }
        try shrinker.shrink(data: response.body, to: destination)
        return RemoteImage.isGIF(response.body)
    }

    static func isOffline(_ error: URLError) -> Bool {
        [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff, .callIsActive].contains(error.code)
    }

    /// A failure in plain words.
    static func outcome(of error: any Error, site: String) -> CollectionStatus.Outcome {
        if let error = error as? URLError {
            if isOffline(error) { return .offline }
            if error.code == .timedOut { return .failed("\(site) n'a pas répondu à temps : réessai au prochain tour") }
            return .failed("\(site) n'a pas pu être lu : réessai au prochain tour")
        }
        return .failed("\(site) n'a pas pu être lu : réessai au prochain tour")
    }
}
