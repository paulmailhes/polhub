import CryptoKit
import Foundation
import Persistence

/// The notes that are one item: the same key twice (in one folder, or in the vault and its old copy), and on
/// Branding the same project posted by two pages.
enum InspirationGrouping {
    struct Candidate {
        var note: ImportedNote
        /// Every note of it came from the second folder.
        var onlyInExtra: Bool
    }

    /// One candidate per key. The vault's own note leads (the old copy only completes it), then the one with
    /// the most images, then the longest text. Duplicates: the notes of one folder beyond the first.
    static func byKey(_ notes: [ImportedNote]) -> (candidates: [Candidate], duplicates: Int) {
        var groups: [String: [ImportedNote]] = [:]
        var order: [String] = []
        for note in notes {
            if groups[note.item.key] == nil { order.append(note.item.key) }
            groups[note.item.key, default: []].append(note)
        }
        var duplicates = 0
        let candidates = order.map { key -> Candidate in
            let group = groups[key] ?? []
            let fromVault = group.filter { !$0.fromExtra }.count
            duplicates += max(0, fromVault - 1) + max(0, group.count - fromVault - 1)
            let sorted = group.sorted { a, b in
                if a.fromExtra != b.fromExtra { return !a.fromExtra }
                if a.imageFiles.count != b.imageFiles.count { return a.imageFiles.count > b.imageFiles.count }
                if a.item.text.count != b.item.text.count { return a.item.text.count > b.item.text.count }
                return (a.item.importedFrom ?? "") < (b.item.importedFrom ?? "")
            }
            let lead = sorted.dropFirst().reduce(sorted[0]) { combine($0, $1) }
            return Candidate(note: lead, onlyInExtra: group.allSatisfy(\.fromExtra))
        }
        return (candidates, duplicates)
    }

    /// Branding: the same project posted by two pages (same title and studio; or same title and the very same
    /// cover) is one item — the one with the most images, then the longest text — with both pages on it and the
    /// other ids as aliases.
    static func sameProject(_ candidates: [Candidate]) -> (candidates: [Candidate], duplicates: Int) {
        var parent = Array(candidates.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while parent[index] != index {
                parent[index] = parent[parent[index]]
                index = parent[index]
            }
            return index
        }
        func join(_ a: Int, _ b: Int) { parent[root(b)] = root(a) }
        var bySignature: [String: Int] = [:]
        for (index, candidate) in candidates.enumerated() {
            guard let signature = candidate.note.signature else { continue }
            if let first = bySignature[signature] { join(first, index) } else { bySignature[signature] = index }
        }
        // The same title without a common studio: the same cover, byte for byte. Only those titles are hashed.
        let byTitle = Dictionary(grouping: candidates.indices) { InspirationKeys.fold(candidates[$0].note.item.title) }
        for indices in byTitle.values where indices.count > 1 {
            var byCover: [String: Int] = [:]
            for index in indices {
                guard let cover = candidates[index].note.imageFiles.first, let data = try? Data(contentsOf: cover, options: .mappedIfSafe) else { continue }
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                if let first = byCover[hash] { join(first, index) } else { byCover[hash] = index }
            }
        }
        let groups = Dictionary(grouping: candidates.indices, by: root)
        var duplicates = 0
        let merged = groups.keys.sorted().map { key -> Candidate in
            let members = groups[key, default: []].map { candidates[$0] }
            guard members.count > 1 else { return members[0] }
            duplicates += members.count - 1
            let sorted = members.sorted { a, b in
                if a.note.imageFiles.count != b.note.imageFiles.count { return a.note.imageFiles.count > b.note.imageFiles.count }
                if a.note.item.text.count != b.note.item.text.count { return a.note.item.text.count > b.note.item.text.count }
                if a.note.item.date != b.note.item.date { return a.note.item.date < b.note.item.date }
                return a.note.item.key < b.note.item.key
            }
            let lead = sorted.dropFirst().reduce(sorted[0].note) { combine($0, $1.note) }
            return Candidate(note: lead, onlyInExtra: members.allSatisfy(\.onlyInExtra))
        }
        return (merged, duplicates)
    }

    /// `secondary` folded into `lead`: the lead's fields win, the lists add up (`InspirationMerge`), the
    /// secondary's key becomes an alias; Paul's categories win, the lead's first; the richer images list stays,
    /// the lead's when they tie. A vault note completed by its old copy keeps its own words and links: Paul may
    /// have shortened them in Obsidian since the switch (review of 16/11).
    static func combine(_ lead: ImportedNote, _ secondary: ImportedNote) -> ImportedNote {
        var item = InspirationMerge.merge(secondary.item, with: lead.item)
        item.id = lead.item.id
        item.key = lead.item.key
        item.createdAt = lead.item.createdAt
        item.updatedAt = lead.item.updatedAt
        // The lists add up, the lead's first.
        let union = InspirationMerge.union
        let vaultOverOldCopy = !lead.fromExtra && secondary.fromExtra
        item.sources = union(lead.item.sources, secondary.item.sources)
        item.links = vaultOverOldCopy ? lead.item.links : union(lead.item.links, secondary.item.links)
        if vaultOverOldCopy, !lead.item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { item.text = lead.item.text }
        let hashtags = union(lead.item.extra.hashtags ?? [], secondary.item.extra.hashtags ?? [])
        item.extra.hashtags = hashtags.isEmpty ? nil : hashtags
        let projects = union(lead.item.extra.projects ?? [], secondary.item.extra.projects ?? [])
        item.extra.projects = projects.isEmpty ? nil : projects
        var aliases = InspirationMerge.union(lead.item.extra.aliases ?? [], secondary.item.extra.aliases ?? [])
        if secondary.item.key != lead.item.key { aliases = InspirationMerge.union(aliases, [secondary.item.key]) }
        aliases.removeAll { $0 == lead.item.key }
        item.extra.aliases = aliases.isEmpty ? nil : aliases
        if lead.item.categoriesByPaul {
            item.categories = InspirationMerge.cleaned(lead.item.categories)
            item.categoriesByPaul = true
            item.fonts = lead.item.fonts
            item.client = lead.item.client
        }
        item.importedFrom = lead.item.importedFrom ?? secondary.item.importedFrom
        let files = lead.imageFiles.count >= secondary.imageFiles.count ? lead.imageFiles : secondary.imageFiles
        return ImportedNote(item: item, imageFiles: files, fromExtra: lead.fromExtra && secondary.fromExtra, name: lead.name)
    }
}
