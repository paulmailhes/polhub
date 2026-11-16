import Foundation
import Persistence

/// The vault's three inspiration collections brought into Polhub (16/11): `database/Websites`,
/// `database/Branding` (and its `_sources.md`, the LinkedIn pages followed), `database/Mockups`.
///
/// - The vault is only read: files are opened for reading, nothing is written, moved or deleted there.
/// - An optional second folder (the old copy n8n still writes to) brings what the vault missed; the vault's own
///   notes win the rest.
/// - Merged by key (the site's address, the post's id, the mock-up's folder) and by `InspirationStore.upsert`:
///   run twice, it adds nothing and converts nothing; Paul's categories and deleted items stay as he left them.
/// - Images made light by `ImageShrinker` into `AppPaths.inspirationImages`, at most five per post.
/// - The vault's live vocabularies (with the tags Paul added) are copied into Polhub's folder.
public enum InspirationImport {
    public struct Options: Sendable, Equatable {
        /// The images a branding post keeps, its cover first (the public LinkedIn page shows five).
        public var maxBrandingImages: Int
        /// The collections to import.
        public var kinds: [InspirationKind]
        /// What all the images may weigh (the design: « moins d'1 Go »).
        public var imageBudget: Int
        /// The weight is projected after this many conversions, then again after as many more.
        public var projectionAfter: Int

        public init(maxBrandingImages: Int = 5, kinds: [InspirationKind] = InspirationKind.allCases, imageBudget: Int = 1_000_000_000,
                    projectionAfter: Int = 50) {
            self.maxBrandingImages = maxBrandingImages
            self.kinds = kinds
            self.imageBudget = imageBudget
            self.projectionAfter = projectionAfter
        }
    }

    /// Imports `vault` (the folder chosen in Réglages › Projets) and, when given, `extra` (« Ancienne copie »).
    /// Either may be the vault's root or its `database` folder. Runs off the main thread; `progress(done, total)`
    /// is called from there after each item (`total`: the items found, duplicates folded). Cancelling the task
    /// stops it between two items with `CancellationError`; what was imported stays, and the next run goes on.
    /// Throws `InspirationImportError.notAVault` when `vault` holds none of the three collections.
    @concurrent
    public static func run(vault: URL, extra: URL? = nil, database: AppDatabase, paths: AppPaths, options: Options = Options(),
                           now: Date = Date(),
                           progress: @escaping @Sendable (_ done: Int, _ total: Int) -> Void = { _, _ in }) async throws -> InspirationImportReport {
        try Task.checkCancellation()
        guard let main = databaseFolder(vault) else { throw InspirationImportError.notAVault(vault.path(percentEncoded: false)) }
        var report = InspirationImportReport()
        // The old copy first, the vault last: on the same key, the vault's note leads.
        var roots: [(folder: URL, fromExtra: Bool)] = []
        if let extra {
            if let folder = databaseFolder(extra) {
                if folder.standardizedFileURL.path != main.standardizedFileURL.path { roots.append((folder, true)) }
            } else {
                report.warnings.append("L'ancienne copie choisie n'a pas de dossier « database » : elle est laissée de côté.")
            }
        }
        roots.append((main, false))
        let store = InspirationStore(database)

        // The LinkedIn pages: those Polhub does not know yet. A page Paul changed in Polhub stays as he left it, and
        // one he no longer follows is not followed again (review of 16/11).
        var pages: [SourcesTable.Page] = []
        for root in roots {
            let table = root.folder.appending(path: "Branding/_sources.md")
            if let text = try? String(contentsOf: table, encoding: .utf8) { pages += SourcesTable.parse(text) }
        }
        let knownPages = try store.sources(includingRemoved: true)
        if options.kinds.contains(.branding) {
            var links = Set(knownPages.map(\.link))
            for page in pages where !links.contains(page.link) {
                try store.saveSource(InspirationSourceRow(name: page.name, link: page.link, color: page.color, createdAt: now))
                links.insert(page.link)
                report.sourcesAdded += 1
            }
        }
        let slugs = Set((knownPages.map(\.name) + pages.map(\.name)).map(InspirationKeys.kebab))

        // The vocabularies: the vault's live copy comes along, so that Paul's tags outlive Obsidian.
        for kind in options.kinds {
            guard let copy = InspirationVocabulary.vaultCopy(kind, vault: vault),
                  let data = try? Data(contentsOf: copy), (try? InspirationVocabulary.parse(data, kind: kind)) != nil else { continue }
            let target = InspirationVocabulary.appCopy(kind, paths: paths)
            try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: target, options: .atomic)
        }

        // The notes, folded into one candidate per item.
        var candidates: [InspirationGrouping.Candidate] = []
        var skipped = Set<String>()
        for kind in options.kinds {
            let vocabulary = InspirationVocabulary.load(kind, vault: vault, paths: paths)
            var notes: [ImportedNote] = []
            for root in roots {
                let reader = InspirationNoteReader(kind: kind, database: root.folder, vocabulary: vocabulary, sourceSlugs: slugs,
                                                   fromExtra: root.fromExtra, now: now)
                for url in reader.notes() {
                    try Task.checkCancellation()
                    switch reader.read(url) {
                    case .note(let note, let warnings):
                        notes.append(note)
                        report.warnings += warnings
                    case .skipped(let warning):
                        // The same note in the vault and its copy is left aside once.
                        if skipped.insert("\(kind.rawValue)/\(url.lastPathComponent)").inserted {
                            report[kind].skipped += 1
                            report.warnings.append(warning)
                        }
                    }
                }
            }
            var (found, duplicates) = InspirationGrouping.byKey(notes)
            if kind == .branding {
                let projects = InspirationGrouping.sameProject(found)
                found = projects.candidates
                duplicates += projects.duplicates
            }
            report[kind].duplicates += duplicates
            // The old copy is the vault as it was at the switch to LiveSync, plus what n8n wrote since: a note only
            // it has, older than the vault's newest, may be one Paul deleted in Obsidian. It comes in (it may as well
            // be a post of the hole), and is said (review of 16/11).
            if let newest = notes.filter({ !$0.fromExtra }).map(\.item.date).max() {
                for candidate in found where candidate.onlyInExtra && candidate.note.item.date < newest {
                    report.warnings.append("« \(candidate.note.name) » : seulement dans l'ancienne copie, et plus ancienne que le coffre : peut-être supprimée dans Obsidian.")
                }
            }
            candidates += found.sorted { $0.note.item.date < $1.note.item.date }
        }

        // Each candidate meets the base. The weight of the images is projected on the conversions done, every
        // `projectionAfter` of them: past the budget, the import stops before converting everything (the design:
        // « moins d'1 Go ; mesuré avant de tout convertir »).
        var lookups: [InspirationKind: Lookup] = [:]
        for kind in options.kinds { lookups[kind] = Lookup(try store.allItems(kind: kind)) }
        let total = candidates.count
        let step = max(1, options.projectionAfter)
        var filesToCome = candidates.reduce(0) { $0 + min(imageLimit($1.note.item.kind, options: options), $1.note.imageFiles.count) }
        var nextProjection = step
        for (index, candidate) in candidates.enumerated() {
            try Task.checkCancellation()
            var note = candidate.note
            let kind = note.item.kind
            let existing = lookups[kind]?.find(note)
            if let existing, existing.key != note.item.key {
                var aliases = InspirationMerge.union(note.item.extra.aliases ?? [], [note.item.key])
                aliases.removeAll { $0 == existing.key }
                note.item.key = existing.key
                note.item.extra.aliases = aliases.isEmpty ? nil : aliases
            }
            note.item.images = images(of: note, existing: existing, paths: paths, options: options, report: &report)
            filesToCome -= min(imageLimit(kind, options: options), note.imageFiles.count)
            let result = try store.upsert(note.item, at: now)
            switch result.outcome {
            case .added: report[kind].added += 1
            case .updated: report[kind].updated += 1
            case .unchanged: report[kind].unchanged += 1
            }
            if candidate.onlyInExtra { report[kind].onlyInExtra += 1 }
            lookups[kind]?.add(result.item)
            progress(index + 1, total)
            if report.imagesConverted >= nextProjection, filesToCome > 0 {
                nextProjection = report.imagesConverted + step
                let average = Double(report.bytesWritten) / Double(report.imagesConverted)
                let projected = report.imageBytes + Int(average * Double(filesToCome))
                if projected > options.imageBudget {
                    report.projectedBytes = projected
                    break
                }
            }
        }
        report.warnings = InspirationMerge.union(report.warnings, [])
        return report
    }

    /// The images an item of a kind keeps: five for a post (the public page's), one for the others.
    static func imageLimit(_ kind: InspirationKind, options: Options) -> Int {
        kind == .branding ? max(1, options.maxBrandingImages) : 1
    }

    /// The folder holding the collections: the vault's `database`, or the folder itself.
    static func databaseFolder(_ url: URL) -> URL? {
        let manager = FileManager.default
        func isFolder(_ url: URL) -> Bool {
            var folder: ObjCBool = false
            return manager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &folder) && folder.boolValue
        }
        let names = InspirationKind.allCases.map(InspirationNoteReader.folderName)
        for candidate in [url.appending(path: "database", directoryHint: .isDirectory), url] {
            if names.contains(where: { isFolder(candidate.appending(path: $0, directoryHint: .isDirectory)) }) { return candidate }
        }
        return nil
    }

    /// The item's images in Polhub's folder: those Polhub already has when they are as many, else the note's made
    /// light, all of them. A file already there under the same name is kept only for an item the base does not
    /// have yet (an import stopped midway): for one it has, the file may be another post's (a duplicate that became
    /// the richer, review of 16/11). A deleted item gets nothing new.
    private static func images(of note: ImportedNote, existing: InspirationItemRow?, paths: AppPaths, options: Options,
                               report: inout InspirationImportReport) -> [String] {
        let kind = note.item.kind
        let folder = paths.inspirationImages(kind)
        let files = Array(note.imageFiles.prefix(imageLimit(kind, options: options)))
        let reuseByName = existing == nil
        report.imagesLeftOut += note.imageFiles.count - files.count
        func size(_ name: String) -> Int? {
            let attributes = try? FileManager.default.attributesOfItem(atPath: folder.appending(path: name).path(percentEncoded: false))
            return (attributes?[.size] as? Int).flatMap { $0 > 0 ? $0 : nil }
        }
        if let existing, existing.deletedAt != nil || (!existing.images.isEmpty && existing.images.count >= files.count) {
            let sizes = existing.images.compactMap(size)
            if existing.deletedAt != nil || sizes.count == existing.images.count {
                report.imagesReused += sizes.count
                report.imageBytes += sizes.reduce(0, +)
                return existing.images
            }
        }
        let names = files.indices.map { index -> String in
            switch kind {
            case .website: InspirationImageName.website(key: note.item.key)
            case .branding: InspirationImageName.branding(urn: note.item.key, index: index + 1)
            case .mockup: InspirationImageName.mockup(folder: note.item.key)
            }
        }
        // The images of one item side by side: a post's five decode at once.
        final class Results: @unchecked Sendable {
            let lock = NSLock()
            var outcomes: [Result<(bytes: Int, written: Bool), ImageShrinkError>?]
            init(_ count: Int) { outcomes = Array(repeating: nil, count: count) }
        }
        let results = Results(files.count)
        let shrinker = ImageShrinker()
        DispatchQueue.concurrentPerform(iterations: files.count) { index in
            let outcome: Result<(bytes: Int, written: Bool), ImageShrinkError>
            if reuseByName, let existingSize = size(names[index]) {
                outcome = .success((existingSize, false))
            } else {
                do {
                    outcome = .success((try shrinker.shrink(file: files[index], to: folder.appending(path: names[index])), true))
                } catch let error as ImageShrinkError {
                    outcome = .failure(error)
                } catch {
                    outcome = .failure(.notWritten)
                }
            }
            results.lock.withLock { results.outcomes[index] = outcome }
        }
        var kept: [String] = []
        for (index, outcome) in results.outcomes.enumerated() {
            switch outcome {
            case .success(let done)?:
                kept.append(names[index])
                report.imageBytes += done.bytes
                if done.written {
                    report.imagesConverted += 1
                    report.bytesWritten += done.bytes
                } else {
                    report.imagesReused += 1
                }
            case .failure(let error)?:
                report.warnings.append("« \(note.name) » : image laissée de côté (\(error.reason)).")
            case nil:
                break
            }
        }
        return kept
    }

    /// The items Polhub has, by every key (aliases included) and, on Branding, by title and studio.
    struct Lookup {
        private var byKey: [String: InspirationItemRow] = [:]
        private var bySignature: [String: InspirationItemRow] = [:]

        init(_ items: [InspirationItemRow]) {
            for item in items { add(item) }
        }

        mutating func add(_ item: InspirationItemRow) {
            for key in item.allKeys { byKey[key] = item }
            if item.kind == .branding, let studio = item.studio, !studio.isEmpty {
                bySignature[InspirationKeys.fold(item.title) + "|" + InspirationKeys.fold(studio)] = item
            }
        }

        func find(_ note: ImportedNote) -> InspirationItemRow? {
            if let item = note.item.allKeys.lazy.compactMap({ byKey[$0] }).first { return item }
            return note.signature.flatMap { bySignature[$0] }
        }
    }
}
