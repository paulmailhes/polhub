import Foundation
import GRDB

/// A dictation (base v22, 20/11): what was pasted, what Whisper heard, where it went, how long it lasted.
public struct DictationRow: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable, Identifiable {
    public static let databaseTableName = "dictation"
    public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy { .lowercaseString }

    public var id: UUID
    public var text: String
    public var raw: String
    /// The app that was in front, by its name.
    public var app: String?
    public var seconds: Double
    public var createdAt: Date
    /// The file it was written from (« Transcrire un fichier », base v23), by its name; nil for a dictation.
    public var file: String?

    public init(id: UUID = UUID(), text: String, raw: String, app: String?, seconds: Double, createdAt: Date, file: String? = nil) {
        self.id = id
        self.text = text
        self.raw = raw
        self.app = app
        self.seconds = seconds
        self.createdAt = createdAt
        self.file = file
    }
}

/// A word of the memory that Paul added himself; those of his projects and contacts are read where they are.
public struct DictationWordRow: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable, Identifiable {
    public static let databaseTableName = "dictation_word"
    /// The word in small letters: the same word once.
    public var id: String
    public var word: String
    public var createdAt: Date
}

/// A correction of the memory: what Whisper hears, and what Paul means.
public struct DictationReplacementRow: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable, Identifiable {
    public static let databaseTableName = "dictation_replacement"
    /// What is heard, in small letters: one correction for it.
    public var id: String
    public var heard: String
    public var written: String
    public var createdAt: Date
}

enum DictationSchema {
    static func create(_ db: Database) throws {
        try db.create(table: "dictation") { t in
            t.primaryKey("id", .text)
            t.column("text", .text).notNull()
            t.column("raw", .text).notNull()
            t.column("app", .text)
            t.column("seconds", .double).notNull()
            t.column("createdAt", .datetime).notNull().indexed()
        }
        try db.create(table: "dictation_word") { t in
            t.primaryKey("id", .text)
            t.column("word", .text).notNull()
            t.column("createdAt", .datetime).notNull()
        }
        try db.create(table: "dictation_replacement") { t in
            t.primaryKey("id", .text)
            t.column("heard", .text).notNull()
            t.column("written", .text).notNull()
            t.column("createdAt", .datetime).notNull()
        }
        // What was set up once: the first corrections, put on the first installation only.
        try db.create(table: "dictation_setting") { t in
            t.primaryKey("key", .text)
            t.column("value", .text).notNull()
        }
    }

    /// 20/11 in the evening: « Transcrire un fichier ».
    static func addFile(_ db: Database) throws {
        try db.alter(table: "dictation") { t in t.add(column: "file", .text) }
    }
}

/// What the Dictée keeps (20/11): its history, and the memory Paul tends.
public struct DictationStore: Sendable {
    public let database: AppDatabase
    private var writer: any DatabaseWriter { database.writer }

    public init(_ database: AppDatabase) {
        self.database = database
    }

    static func key(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    // MARK: - The history

    public func add(_ row: DictationRow) throws {
        try writer.write { try row.insert($0) }
    }

    public func recent(limit: Int) throws -> [DictationRow] {
        try writer.read { try DictationRow.order(Column("createdAt").desc).limit(limit).fetchAll($0) }
    }

    public func last() throws -> DictationRow? {
        try recent(limit: 1).first
    }

    public func delete(_ id: UUID) throws {
        _ = try writer.write { try DictationRow.deleteOne($0, key: id) }
    }

    /// The text written again (« Retranscrire »).
    public func setText(_ id: UUID, text: String, raw: String) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE dictation SET text = ?, raw = ? WHERE id = ?", arguments: [text, raw, id.uuidString.lowercased()])
        }
    }

    /// The dictations whose words hold `text`, whatever the case, the newest first.
    public func search(_ text: String, limit: Int) throws -> [DictationRow] {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return try recent(limit: limit) }
        let pattern = "%" + words.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_") + "%"
        return try writer.read { db in
            try DictationRow.fetchAll(db, sql: "SELECT * FROM dictation WHERE text LIKE ? ESCAPE '\\' OR file LIKE ? ESCAPE '\\' ORDER BY createdAt DESC LIMIT ?",
                                      arguments: [pattern, pattern, limit])
        }
    }

    /// « Garder l'historique 30 jours »: the dictations made before `date` go; their ids, for their sounds.
    @discardableResult
    public func deleteOlder(than date: Date) throws -> [UUID] {
        try writer.write { db in
            let ids = try UUID.fetchAll(db, sql: "SELECT id FROM dictation WHERE createdAt < ?", arguments: [date])
            try db.execute(sql: "DELETE FROM dictation WHERE createdAt < ?", arguments: [date])
            return ids
        }
    }

    /// Every id, to find the sounds left without their dictation.
    public func ids() throws -> Set<UUID> {
        try writer.read { Set(try UUID.fetchAll($0, sql: "SELECT id FROM dictation")) }
    }

    /// Calls `onChange` on the main queue with the newest dictations: now, and after every change.
    public func observeRecent(limit: Int, onChange: @escaping @MainActor @Sendable ([DictationRow]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { try DictationRow.order(Column("createdAt").desc).limit(limit).fetchAll($0) }
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { rows in
                MainActor.assumeIsolated { onChange(rows) }
            })
    }

    // MARK: - The memory

    public func words() throws -> [DictationWordRow] {
        try writer.read { try DictationWordRow.order(Column("createdAt").desc, Column("id")).fetchAll($0) }
    }

    public func addWord(_ word: String, at date: Date) throws {
        let word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        try writer.write { db in
            guard try DictationWordRow.fetchOne(db, key: Self.key(word)) == nil else { return }
            try DictationWordRow(id: Self.key(word), word: word, createdAt: date).insert(db)
        }
    }

    public func removeWord(_ word: String) throws {
        _ = try writer.write { try DictationWordRow.deleteOne($0, key: Self.key(word)) }
    }

    public func replacements() throws -> [DictationReplacementRow] {
        try writer.read { try DictationReplacementRow.order(Column("createdAt"), Column("id")).fetchAll($0) }
    }

    /// One correction for what is heard: a new one replaces the one before.
    public func setReplacement(heard: String, written: String, at date: Date) throws {
        let heard = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty else { return }
        try writer.write { db in
            try DictationReplacementRow(id: Self.key(heard), heard: heard, written: written.trimmingCharacters(in: .whitespacesAndNewlines),
                                        createdAt: date).save(db)
        }
    }

    public func removeReplacement(_ heard: String) throws {
        _ = try writer.write { try DictationReplacementRow.deleteOne($0, key: Self.key(heard)) }
    }

    /// The first corrections, put once: those Paul removes do not come back.
    public func seed(_ corrections: [(heard: String, written: String)], at date: Date) throws {
        let done = try writer.read { try String.fetchOne($0, sql: "SELECT value FROM dictation_setting WHERE key = 'premieres-corrections'") }
        guard done == nil else { return }
        for correction in corrections { try setReplacement(heard: correction.heard, written: correction.written, at: date) }
        try writer.write { try $0.execute(sql: "INSERT OR REPLACE INTO dictation_setting (key, value) VALUES ('premieres-corrections', '1')") }
    }

    /// Calls `onChange` with the memory (Paul's words, his corrections): now, and after every change.
    public func observeMemory(onChange: @escaping @MainActor @Sendable ([DictationWordRow], [DictationReplacementRow]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { db in
                (try DictationWordRow.order(Column("createdAt").desc, Column("id")).fetchAll(db),
                 try DictationReplacementRow.order(Column("createdAt"), Column("id")).fetchAll(db))
            }
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { memory in
                MainActor.assumeIsolated { onChange(memory.0, memory.1) }
            })
    }
}
