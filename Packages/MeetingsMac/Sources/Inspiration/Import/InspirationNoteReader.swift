import Foundation
import Persistence

/// One note read from the vault, before it meets the base: the item without its images, and the image files
/// it names, the cover first.
struct ImportedNote {
    var item: InspirationItemRow
    var imageFiles: [URL]
    /// Read from the second folder (the old copy n8n still writes to).
    var fromExtra: Bool
    /// The note's title, the only thing of it a warning says.
    var name: String

    /// Branding: the same project from two pages has the same title and studio.
    var signature: String? {
        guard item.kind == .branding, let studio = item.studio, !studio.isEmpty else { return nil }
        return InspirationKeys.fold(item.title) + "|" + InspirationKeys.fold(studio)
    }
}

/// Reads the notes of one collection of one vault folder, read-only.
struct InspirationNoteReader {
    enum Outcome {
        case note(ImportedNote, warnings: [String])
        case skipped(warning: String)
    }

    let kind: InspirationKind
    /// The folder that holds `Websites`, `Branding`, `Mockups` (the vault's `database`).
    let database: URL
    let vocabulary: InspirationVocabulary
    /// The slugs of every LinkedIn page known: tags, not categories.
    let sourceSlugs: Set<String>
    let fromExtra: Bool
    let now: Date

    static func folderName(_ kind: InspirationKind) -> String {
        switch kind {
        case .website: "Websites"
        case .branding: "Branding"
        case .mockup: "Mockups"
        }
    }

    static func imageFolderName(_ kind: InspirationKind) -> String {
        switch kind {
        case .website: "_og"
        case .branding: "_media"
        case .mockup: "_previews"
        }
    }

    var folder: URL { database.appending(path: Self.folderName(kind), directoryHint: .isDirectory) }

    /// The notes of the collection, by name; the pages whose name starts with `_` (`_sources.md`) are not notes.
    func notes() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension.lowercased() == "md" && !$0.lastPathComponent.hasPrefix("_") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func read(_ url: URL) -> Outcome {
        let name = url.deletingPathExtension().lastPathComponent.precomposedStringWithCanonicalMapping
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return .skipped(warning: "« \(name) » : note illisible, laissée de côté.")
        }
        let properties: [String: Any], body: String
        switch VaultFrontmatter.read(raw) {
        case .success(let read): (properties, body) = read
        case .failure(.none): return .skipped(warning: "« \(name) » : pas de propriétés, laissée de côté.")
        case .failure(.unreadable): return .skipped(warning: "« \(name) » : propriétés illisibles, laissée de côté.")
        }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let relativePath = "database/\(Self.folderName(kind))/\(url.lastPathComponent)".precomposedStringWithCanonicalMapping
        let note = Note(name: name, properties: properties, body: body, relativePath: relativePath, modified: modified ?? now)
        switch kind {
        case .website: return website(note)
        case .branding: return branding(note)
        case .mockup: return mockup(note)
        }
    }

    private struct Note {
        let name: String
        let properties: [String: Any]
        let body: String
        let relativePath: String
        let modified: Date

        subscript(_ key: String) -> Any? { properties[key] }
        func text(_ key: String) -> String? { VaultFrontmatter.text(properties[key]) }
        func list(_ key: String) -> [String] { VaultFrontmatter.list(properties[key]) }
    }

    // MARK: - The three collections

    private func website(_ note: Note) -> Outcome {
        let address = note.text("site") ?? note.text("source").flatMap { VaultFrontmatter.isRemote($0) ? $0 : nil } ?? note.text("url")
        guard let address, let key = InspirationKeys.website(address) else {
            return .skipped(warning: "« \(note.name) » : pas d'adresse de site, laissée de côté.")
        }
        var warnings: [String] = []
        var extra = InspirationExtra(notion: note.text("notion"))
        let projects = note.list("projets").map { WikiText.plain($0) }.filter { !$0.isEmpty }
        extra.projects = projects.isEmpty ? nil : projects
        let files = images([note.text("image")].compactMap { $0 }, note: note, extra: &extra, warnings: &warnings)
        if files.isEmpty, extra.imageURL != nil {
            // A Web Clipper note: the collection downloads it afterwards (`InspirationCollector.completeImages`).
            warnings.append("« \(note.name) » : image en ligne, téléchargée ensuite par la collecte.")
        }
        let tags = note.list("tags")
        var item = InspirationItemRow(
            kind: .website, key: key, title: note.name,
            text: note.text("description") ?? Self.bodyText(note.body), url: address,
            date: VaultFrontmatter.date(note["date"]) ?? note.modified,
            categories: vocabulary.categories(fromTags: tags, ignoring: ["site", "sotd"]),
            categoriesByPaul: VaultFrontmatter.bool(note["ia_manuel"]),
            fonts: note.list("police"), client: note.text("client"), extra: extra, importedFrom: note.relativePath, createdAt: now)
        item.title = item.title.isEmpty ? key : item.title
        return .note(ImportedNote(item: item, imageFiles: files, fromExtra: fromExtra, name: note.name), warnings: warnings)
    }

    private func branding(_ note: Note) -> Outcome {
        guard let urn = InspirationKeys.linkedInPost(urn: note.text("urn"), link: note.text("linkedin")) else {
            return .skipped(warning: "« \(note.name) » : pas d'identifiant LinkedIn, laissée de côté.")
        }
        var warnings: [String] = []
        let source = note.text("source")
        var extra = InspirationExtra(hiddenImages: VaultFrontmatter.int(note["images_cachees"]))
        let hashtags = note.list("hashtags").map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
        extra.hashtags = hashtags.isEmpty ? nil : hashtags
        // The cover (the first still image), then the others in their order.
        let links = ([note.text("image")].compactMap { $0 } + note.list("images"))
        let files = images(links, note: note, extra: &extra, warnings: &warnings)
        let fallbackTitle = note.name.replacing(#/^\d{4}-\d{2}-\d{2}\s+/#, with: "")
        let ignored = sourceSlugs.union(source.map { [InspirationKeys.kebab($0)] } ?? [])
        let item = InspirationItemRow(
            kind: .branding, key: urn, title: note.text("titre") ?? (fallbackTitle.isEmpty ? note.name : fallbackTitle),
            text: Self.postText(note.body),
            url: note.text("linkedin") ?? "https://www.linkedin.com/feed/update/urn:li:activity:\(urn)/",
            links: InspirationMerge.union(note.list("liens"), []),
            date: InspirationKeys.publicationDate(urn: urn) ?? VaultFrontmatter.date(note["date"]) ?? note.modified,
            sources: source.map { [$0] } ?? [], studio: note.text("studio"),
            categories: vocabulary.categories(fromTags: note.list("tags"), ignoring: ignored.union(["branding"])),
            categoriesByPaul: VaultFrontmatter.bool(note["ia_manuel"]),
            fonts: note.list("police"), client: note.text("client"), extra: extra, importedFrom: note.relativePath, createdAt: now)
        return .note(ImportedNote(item: item, imageFiles: files, fromExtra: fromExtra, name: note.name), warnings: warnings)
    }

    private func mockup(_ note: Note) -> Outcome {
        var warnings: [String] = []
        let preview = note.text("image").map(VaultFrontmatter.linkTarget)
        let key = InspirationKeys.mockupFolder(
            folderLink: note.text("dossier"), fileLink: note.text("fichier"), previewLink: note.text("apercu"),
            previewImage: preview.flatMap { VaultFrontmatter.isRemote($0) ? nil : ($0 as NSString).lastPathComponent }) ?? note.name
        var extra = InspirationExtra(folderURL: note.text("dossier"), fileURL: note.text("fichier"), previewURL: note.text("apercu"),
                                     sizeMB: VaultFrontmatter.double(note["taille_mo"]))
        let files = images([note.text("image")].compactMap { $0 }, note: note, extra: &extra, warnings: &warnings)
        let source = note.text("source")
        let types = (note.text("type") ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        // The tags that repeat `type` and `source` (the vault's old system) are not categories.
        var ignored: Set<String> = ["mockup"]
        ignored.formUnion(types.map(InspirationKeys.kebab))
        ignored.insert(InspirationKeys.kebab(types.joined(separator: " ")))
        if let source { ignored.insert(InspirationKeys.kebab(source)) }
        var categories = vocabulary.categories(fromTags: note.list("tags"), ignoring: ignored)
        let typeFamily = InspirationVocabulary.typeFamily
        categories[typeFamily] = InspirationMerge.union(types, categories[typeFamily] ?? [])
        let item = InspirationItemRow(
            kind: .mockup, key: key, title: note.name, text: note.text("description") ?? "",
            date: VaultFrontmatter.date(note["date"]) ?? note.modified, studio: source,
            categories: InspirationMerge.cleaned(categories), extra: extra, importedFrom: note.relativePath, createdAt: now)
        return .note(ImportedNote(item: item, imageFiles: files, fromExtra: fromExtra, name: note.name), warnings: warnings)
    }

    // MARK: - Images and text

    /// The files the image links name, in their order, each once. An address is kept as an address (the import
    /// never goes on the network); a file not found is said.
    private func images(_ links: [String], note: Note, extra: inout InspirationExtra, warnings: inout [String]) -> [URL] {
        var files: [URL] = []
        var missing = 0
        for link in links {
            let target = VaultFrontmatter.linkTarget(link)
            guard !target.isEmpty else { continue }
            if VaultFrontmatter.isRemote(target) {
                if extra.imageURL == nil { extra.imageURL = target }
                continue
            }
            if let file = resolve(target) {
                if !files.contains(file) { files.append(file) }
            } else {
                missing += 1
            }
        }
        if missing > 0 {
            warnings.append("« \(note.name) » : \(missing == 1 ? "image introuvable" : "\(missing) images introuvables") dans le coffre, fiche gardée sans \(missing == 1 ? "elle" : "elles").")
        }
        return files
    }

    /// `database/Branding/_media/x.jpg` from the vault's root, else from the collection's folder or its images'.
    private func resolve(_ target: String) -> URL? {
        let manager = FileManager.default
        let name = (target as NSString).lastPathComponent
        let candidates = [
            database.deletingLastPathComponent().appending(path: target),
            folder.appending(path: target),
            folder.appending(path: Self.imageFolderName(kind), directoryHint: .isDirectory).appending(path: name),
            folder.appending(path: name),
        ]
        return candidates.first { url in
            var isFolder: ObjCBool = false
            return manager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isFolder) && !isFolder.boolValue
        }?.standardizedFileURL
    }

    /// A post's words: without the image embeds, the « no image » apology, nor the closing LinkedIn link.
    static func postText(_ body: String) -> String {
        clean(body) { line in
            line.hasPrefix("*Aucune image récupérée") || line.hasPrefix("[Voir sur LinkedIn](")
        }
    }

    /// A site's words when it has no description: without embeds nor the closing link to the site.
    static func bodyText(_ body: String) -> String {
        clean(body) { line in line.wholeMatch(of: #/\[[^\]]*\]\(https?://[^)\s]+\)/#) != nil }
    }

    private static func clean(_ body: String, dropping drop: (String) -> Bool) -> String {
        body.components(separatedBy: "\n")
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !(trimmed.hasPrefix("![[") && trimmed.hasSuffix("]]")) && !drop(trimmed)
            }
            .joined(separator: "\n")
            .replacing(#/\n{3,}/#, with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// `[[X]]` → X, `[[X|Y]]` → Y.
enum WikiText {
    static func plain(_ text: String) -> String {
        text.replacing(#/\[\[([^\]|#]+)(#[^\]|]*)?(\|([^\]]+))?\]\]/#) { match in
            String(match.output.4 ?? match.output.1)
        }.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
