import Foundation
import GRDB

/// The items of « Inspiration » (sites, branding, mock-ups) and the LinkedIn pages followed.
public struct InspirationStore: Sendable {
    public let database: AppDatabase
    private var writer: any DatabaseWriter { database.writer }

    public init(_ database: AppDatabase) {
        self.database = database
    }

    private static func key(_ id: UUID) -> String { id.uuidString.lowercased() }

    // MARK: - Items

    /// Whether the base has Inspiration's tables (migration `v13`): `polhub mcp` never migrates, and a base the app
    /// has not opened since its update has not got them yet.
    public func isAvailable() throws -> Bool {
        try writer.read { try $0.tableExists("inspiration_item") }
    }

    /// The newest first, without the deleted.
    static func live(_ kind: InspirationKind) -> QueryInterfaceRequest<InspirationItemRow> {
        InspirationItemRow
            .filter(Column("kind") == kind.rawValue && Column("deletedAt") == nil)
            .order(Column("date").desc, Column("createdAt").desc)
    }

    public func items(kind: InspirationKind) throws -> [InspirationItemRow] {
        try writer.read { try Self.live(kind).fetchAll($0) }
    }

    /// Every item of a kind, deleted ones included, newest first: what an import compares itself with.
    public func allItems(kind: InspirationKind) throws -> [InspirationItemRow] {
        try writer.read {
            try InspirationItemRow.filter(Column("kind") == kind.rawValue).order(Column("date").desc, Column("createdAt").desc).fetchAll($0)
        }
    }

    /// Calls `onChange` on the main queue with the items of a kind, newest first, without the deleted: now and
    /// after every change of that list. The region is constant (the list is read off the writer, review of 16/11),
    /// and a write that leaves this kind's list as it was (another kind's item) is not told.
    public func observeItems(kind: InspirationKind, onChange: @escaping @MainActor @Sendable ([InspirationItemRow]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .trackingConstantRegion { try Self.live(kind).fetchAll($0) }
            .removeDuplicates()
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { rows in
                MainActor.assumeIsolated { onChange(rows) }
            })
    }

    /// Any item, deleted ones included.
    public func item(id: UUID) throws -> InspirationItemRow? {
        try writer.read { try InspirationItemRow.fetchOne($0, key: Self.key(id)) }
    }

    /// The item of a key, or the one a duplicate of that key was merged into; deleted ones included.
    public func item(kind: InspirationKind, key: String) throws -> InspirationItemRow? {
        try writer.read { try Self.find(kind: kind, keys: [key], in: $0) }
    }

    /// The row of the first key (the item's own) when there is one, else of one of the others, else the one whose
    /// aliases hold one of them.
    static func find(kind: InspirationKind, keys: [String], in db: Database) throws -> InspirationItemRow? {
        let keys = keys.filter { !$0.isEmpty }
        guard let own = keys.first else { return nil }
        let ofKind = InspirationItemRow.filter(Column("kind") == kind.rawValue)
        if let row = try ofKind.filter(Column("key") == own).fetchOne(db) { return row }
        if keys.count > 1, let row = try ofKind.filter(keys.dropFirst().contains(Column("key"))).fetchOne(db) {
            return row
        }
        // Few items have aliases (the duplicates of branding): they are read, then looked into.
        let merged = try InspirationItemRow
            .filter(Column("kind") == kind.rawValue && Column("extra").like("%\"aliases\"%"))
            .fetchAll(db)
        return merged.first { row in keys.contains { row.extra.aliases?.contains($0) == true } }
    }

    /// Adds an item, or merges it into the one the base holds under its key (or one of its aliases), by
    /// `InspirationMerge`: Paul's categories stay, a deleted item stays deleted, the richer images list stays,
    /// the sources add up. `updatedAt` moves only when something changed.
    @discardableResult
    public func upsert(_ item: InspirationItemRow, at date: Date = Date()) throws -> InspirationUpsertResult {
        try writer.write { db in
            guard let existing = try Self.find(kind: item.kind, keys: item.allKeys, in: db) else {
                var row = item
                row.categories = InspirationMerge.cleaned(row.categories)
                try row.insert(db)
                return InspirationUpsertResult(outcome: .added, item: row)
            }
            var merged = InspirationMerge.merge(existing, with: item)
            guard merged != existing else { return InspirationUpsertResult(outcome: .unchanged, item: existing) }
            merged.updatedAt = date
            try merged.update(db)
            return InspirationUpsertResult(outcome: .updated, item: merged)
        }
    }

    /// Paul's choice from the item's page: his from now on, never changed by an import or by the AI.
    public func setCategories(id: UUID, _ categories: [String: [String]], at date: Date) throws {
        try writer.write { db in
            guard var row = try InspirationItemRow.fetchOne(db, key: Self.key(id)) else { return }
            row.categories = InspirationMerge.cleaned(categories)
            row.categoriesByPaul = true
            row.updatedAt = date
            try row.update(db)
        }
    }

    /// What the AI proposes for an item: written only when Paul has not chosen; `false` when it was left alone.
    @discardableResult
    public func applyTagging(id: UUID, categories: [String: [String]], fonts: [String], client: String?, at date: Date) throws -> Bool {
        try writer.write { db in
            guard var row = try InspirationItemRow.fetchOne(db, key: Self.key(id)), !row.categoriesByPaul else { return false }
            row.categories = InspirationMerge.cleaned(categories)
            row.fonts = fonts
            let client = client?.trimmingCharacters(in: .whitespacesAndNewlines)
            row.client = client?.isEmpty == false ? client : nil
            row.updatedAt = date
            try row.update(db)
            return true
        }
    }

    /// « Supprimer »: off every list; `restore` brings it back as it was.
    public func moveToTrash(id: UUID, at date: Date) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE inspiration_item SET deletedAt = ?, updatedAt = ? WHERE id = ?", arguments: [date, date, Self.key(id)])
        }
    }

    public func restore(id: UUID, at date: Date) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE inspiration_item SET deletedAt = NULL, updatedAt = ? WHERE id = ?", arguments: [date, Self.key(id)])
        }
    }

    /// Every key the base knows for a kind, deleted items and merged duplicates included: what a collection
    /// must not add again.
    public func knownKeys(kind: InspirationKind) throws -> Set<String> {
        try writer.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT key, extra FROM inspiration_item WHERE kind = ?", arguments: [kind.rawValue])
            var keys = Set<String>()
            let decoder = JSONDecoder()
            for row in rows {
                keys.insert(row["key"])
                let extra: String = row["extra"]
                if extra.contains("aliases"), let decoded = try? decoder.decode(InspirationExtra.self, from: Data(extra.utf8)) {
                    keys.formUnion(decoded.aliases ?? [])
                }
            }
            return keys
        }
    }

    // MARK: - LinkedIn pages

    /// The pages followed, by name; `includingRemoved` adds those Paul no longer follows.
    static func pages(includingRemoved: Bool = false) -> QueryInterfaceRequest<InspirationSourceRow> {
        let all = InspirationSourceRow.all()
        return (includingRemoved ? all : all.filter(Column("removedAt") == nil))
            .order(Column("name").collating(.localizedCaseInsensitiveCompare))
    }

    /// The pages followed, by name; `includingRemoved` adds those Paul no longer follows (what an import must not
    /// follow again).
    public func sources(includingRemoved: Bool = false) throws -> [InspirationSourceRow] {
        try writer.read { try Self.pages(includingRemoved: includingRemoved).fetchAll($0) }
    }

    public func observeSources(onChange: @escaping @MainActor @Sendable ([InspirationSourceRow]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .trackingConstantRegion { try Self.pages().fetchAll($0) }
            .removeDuplicates()
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { rows in
                MainActor.assumeIsolated { onChange(rows) }
            })
    }

    /// Adds a page or changes it: by its id, else by its link (one row per page, whatever the id). A page Paul
    /// no longer followed is followed again.
    @discardableResult
    public func saveSource(_ source: InspirationSourceRow) throws -> InspirationSourceRow {
        try writer.write { db in
            if try InspirationSourceRow.exists(db, key: Self.key(source.id)) {
                try source.update(db)
                return source
            }
            if var existing = try InspirationSourceRow.filter(Column("link") == source.link).fetchOne(db) {
                existing.name = source.name
                existing.color = source.color ?? existing.color
                existing.lastReadAt = source.lastReadAt ?? existing.lastReadAt
                existing.lastError = source.lastError ?? existing.lastError
                existing.removedAt = source.removedAt
                try existing.update(db)
                return existing
            }
            try source.insert(db)
            return source
        }
    }

    /// « Ne plus la suivre »: off the lists and never read again, but remembered (`removedAt`).
    public func deleteSource(id: UUID, at date: Date = Date()) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE inspiration_source SET removedAt = ? WHERE id = ?", arguments: [date, Self.key(id)])
        }
    }

    /// The end of a page's reading: when, and why it failed (`nil` when it went well).
    public func markSourceRead(id: UUID, at date: Date, error: String?) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE inspiration_source SET lastReadAt = ?, lastError = ? WHERE id = ?", arguments: [date, error, Self.key(id)])
        }
    }
}
