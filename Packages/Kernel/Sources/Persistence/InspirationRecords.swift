import Foundation
import GRDB

// « Inspiration » (16/11): the three collections Paul browses for ideas — the sites awarded by Awwwards, the
// branding posted by design studios on LinkedIn, the mock-ups he bought — and the LinkedIn pages followed.
// The images live in files beside the base (`AppPaths.inspirationImages`), never here.

/// The three collections, one page each under « Inspiration ».
public enum InspirationKind: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case website, branding, mockup

    /// The folder of its images, under `AppPaths.inspiration`.
    public var folderName: String {
        switch self {
        case .website: "websites"
        case .branding: "branding"
        case .mockup: "mockups"
        }
    }
}

/// What an item carries beyond the common fields, as one JSON object; a field left `nil` is not written.
public struct InspirationExtra: Codable, Equatable, Hashable, Sendable {
    /// Mock-ups: the folder in Nextcloud (web link), its main file and its preview (WebDAV links), its weight.
    public var folderURL: String?
    public var fileURL: String?
    public var previewURL: String?
    public var sizeMB: Double?
    /// Mock-ups added by hand: the folder on the Mac.
    public var localFolder: String?
    /// Branding: the post's hashtags, and the images LinkedIn hides behind « +12 ».
    public var hashtags: [String]?
    public var hiddenImages: Int?
    /// Websites: the Notion page it came from, the vault projects it was linked to.
    public var notion: String?
    public var projects: [String]?
    /// An image known only by its address (a Web Clipper note): never fetched by the import.
    public var imageURL: String?
    /// The keys of the duplicates merged into this item (the same project posted by two studios): seen again,
    /// they land here.
    public var aliases: [String]?

    public init(folderURL: String? = nil, fileURL: String? = nil, previewURL: String? = nil, sizeMB: Double? = nil,
                localFolder: String? = nil, hashtags: [String]? = nil, hiddenImages: Int? = nil, notion: String? = nil,
                projects: [String]? = nil, imageURL: String? = nil, aliases: [String]? = nil) {
        self.folderURL = folderURL
        self.fileURL = fileURL
        self.previewURL = previewURL
        self.sizeMB = sizeMB
        self.localFolder = localFolder
        self.hashtags = hashtags
        self.hiddenImages = hiddenImages
        self.notion = notion
        self.projects = projects
        self.imageURL = imageURL
        self.aliases = aliases
    }

    /// `other` over `self`: each field `other` has wins; the lists add up.
    public func merging(_ other: InspirationExtra) -> InspirationExtra {
        func union(_ a: [String]?, _ b: [String]?) -> [String]? {
            let all = InspirationMerge.union(a ?? [], b ?? [])
            return all.isEmpty ? nil : all
        }
        return InspirationExtra(
            folderURL: other.folderURL ?? folderURL, fileURL: other.fileURL ?? fileURL, previewURL: other.previewURL ?? previewURL,
            sizeMB: other.sizeMB ?? sizeMB, localFolder: other.localFolder ?? localFolder,
            hashtags: union(hashtags, other.hashtags), hiddenImages: other.hiddenImages ?? hiddenImages,
            notion: other.notion ?? notion, projects: union(projects, other.projects), imageURL: other.imageURL ?? imageURL,
            aliases: union(aliases, other.aliases))
    }
}

/// One site, one branding post or one mock-up.
public struct InspirationItemRow: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "inspiration_item"
    public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy { .lowercaseString }

    public var id: UUID
    public var kind: InspirationKind
    /// Unique within its kind: the site's normalised address, the LinkedIn `urn` (text, 19 digits), the
    /// mock-up's folder.
    public var key: String
    public var title: String
    public var text: String
    /// The site, the LinkedIn post.
    public var url: String?
    public var links: [String]
    /// When it was published (branding) or collected (sites, mock-ups).
    public var date: Date
    /// The LinkedIn pages it came from, by name (branding).
    public var sources: [String]
    /// The studio that made it (branding), the vendor (mock-ups).
    public var studio: String?
    /// Family → values (`secteur`, `style`…; the mock-ups' types under `type`; unknown tags under `autres`).
    public var categories: [String: [String]]
    /// Paul chose them: no import and no AI ever changes them, nor the fonts and the client.
    public var categoriesByPaul: Bool
    public var fonts: [String]
    public var client: String?
    /// File names in the kind's image folder, the cover first.
    public var images: [String]
    public var extra: InspirationExtra
    /// The vault note it came from, relative to the vault.
    public var importedFrom: String?
    public var createdAt: Date
    public var updatedAt: Date
    /// In the bin: off every list, never brought back by an import or a collection; « Annuler » restores it.
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(), kind: InspirationKind, key: String, title: String, text: String = "", url: String? = nil,
        links: [String] = [], date: Date, sources: [String] = [], studio: String? = nil, categories: [String: [String]] = [:],
        categoriesByPaul: Bool = false, fonts: [String] = [], client: String? = nil, images: [String] = [],
        extra: InspirationExtra = InspirationExtra(), importedFrom: String? = nil, createdAt: Date, updatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.key = key
        self.title = title
        self.text = text
        self.url = url
        self.links = links
        self.date = date
        self.sources = sources
        self.studio = studio
        self.categories = categories
        self.categoriesByPaul = categoriesByPaul
        self.fonts = fonts
        self.client = client
        self.images = images
        self.extra = extra
        self.importedFrom = importedFrom
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }

    /// The image of its card.
    public var cover: String? { images.first }

    /// Its key and the keys merged into it.
    public var allKeys: [String] { [key] + (extra.aliases ?? []) }
}

/// A LinkedIn company page whose public posts feed Branding.
public struct InspirationSourceRow: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "inspiration_source"
    public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy { .lowercaseString }

    public var id: UUID
    public var name: String
    /// `https://www.linkedin.com/company/<slug>/`, as `normalizedLink` writes it.
    public var link: String
    /// `#e8b923`: its dot on the cards.
    public var color: String?
    public var lastReadAt: Date?
    /// Why the last reading failed, in plain words; `nil` when it went well.
    public var lastError: String?
    public var createdAt: Date
    /// « Ne plus la suivre »: off every list and never read, but remembered, so that an import of the vault's
    /// `_sources.md` does not follow it again. Followed again by hand, it comes back.
    public var removedAt: Date?

    public init(id: UUID = UUID(), name: String, link: String, color: String? = nil, lastReadAt: Date? = nil,
                lastError: String? = nil, createdAt: Date, removedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.link = link
        self.color = color
        self.lastReadAt = lastReadAt
        self.lastError = lastError
        self.createdAt = createdAt
        self.removedAt = removedAt
    }

    /// One spelling per page: `https://www.linkedin.com/company/<slug>/`, lowercase, without `/posts/` nor
    /// what follows `?`. Anything that is not a company page is only trimmed.
    public static func normalizedLink(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.firstMatch(of: #/(?i)^(?:https?://)?(?:[a-z]{2,3}\.)?linkedin\.com/company/([^/?#\s]+)/#) else {
            return trimmed
        }
        return "https://www.linkedin.com/company/\(match.output.1.lowercased())/"
    }
}

/// What `InspirationStore.upsert` did.
public struct InspirationUpsertResult: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable { case added, updated, unchanged }

    public var outcome: Outcome
    /// The item as the base now holds it.
    public var item: InspirationItemRow

    public init(outcome: Outcome, item: InspirationItemRow) {
        self.outcome = outcome
        self.item = item
    }
}

/// How an item seen again (an import run twice, a post collected again, a duplicate) joins the one the base
/// holds. Pure: the store and the import share it.
public enum InspirationMerge {
    /// `incoming` over `existing`. The identity stays (id, key, creation); a deleted item stays deleted;
    /// Paul's categories, fonts and client are never replaced; the richer images list and the longer text
    /// stay; the sources, links and aliases add up; the earliest date stays; any other field `incoming` has
    /// wins.
    public static func merge(_ existing: InspirationItemRow, with incoming: InspirationItemRow) -> InspirationItemRow {
        var merged = existing
        if !incoming.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { merged.title = incoming.title }
        if incoming.text.count > existing.text.count { merged.text = incoming.text }
        merged.url = nonEmpty(incoming.url) ?? existing.url
        merged.links = union(existing.links, incoming.links)
        // Rounded to the millisecond, as the base keeps dates: a date read again never counts as a change.
        if incoming.date.timeIntervalSince(existing.date) < -0.001 { merged.date = incoming.date }
        merged.sources = union(existing.sources, incoming.sources)
        merged.studio = nonEmpty(incoming.studio) ?? existing.studio
        if !existing.categoriesByPaul {
            if incoming.categoriesByPaul {
                merged.categories = cleaned(incoming.categories)
                merged.categoriesByPaul = true
                merged.fonts = incoming.fonts
                merged.client = nonEmpty(incoming.client)
            } else {
                if !cleaned(incoming.categories).isEmpty { merged.categories = cleaned(incoming.categories) }
                if !incoming.fonts.isEmpty { merged.fonts = incoming.fonts }
                merged.client = nonEmpty(incoming.client) ?? existing.client
            }
        }
        if incoming.images.count > existing.images.count { merged.images = incoming.images }
        var extra = existing.extra.merging(incoming.extra)
        let aliases = union(extra.aliases ?? [], incoming.key == existing.key ? [] : [incoming.key]).filter { $0 != existing.key }
        extra.aliases = aliases.isEmpty ? nil : aliases
        merged.extra = extra
        merged.importedFrom = nonEmpty(incoming.importedFrom) ?? existing.importedFrom
        return merged
    }

    /// The families without an empty list.
    public static func cleaned(_ categories: [String: [String]]) -> [String: [String]] {
        categories.filter { !$0.value.isEmpty }
    }

    /// `a`, then what `b` adds, in order, each once.
    public static func union(_ a: [String], _ b: [String]) -> [String] {
        var seen = Set<String>()
        return (a + b).filter { seen.insert($0).inserted }
    }

    static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}
