import Foundation
import GRDB

/// What Colin keeps in the base (18/11): the lines of the Accueil that Paul set aside, his thread, and what he knows.
public struct ColinStore: Sendable {
    public let database: AppDatabase
    private var writer: any DatabaseWriter { database.writer }

    public init(_ database: AppDatabase) {
        self.database = database
    }

    /// Sets a line aside; a row of the same line is replaced. « Elle a répondu ailleurs » said again of the same
    /// line counts once more: twice on a project, and Colin stops saying it of that project.
    public func dismiss(_ row: ColinDismissalRow) throws {
        try writer.write { db in
            var row = row
            // The same thing said again of the same project. The same click received twice (the same message before
            // Paul's eyes) is one saying; a thread moved to another project starts again.
            if row.reason == .answeredElsewhere, let known = try ColinDismissalRow.fetchOne(db, key: row.id),
               known.reason == .answeredElsewhere, known.projectID == row.projectID {
                row.times = known.lastMessageAt == row.lastMessageAt && row.lastMessageAt != nil ? known.times : known.times + 1
            }
            try row.save(db)
        }
    }

    /// The line may show again.
    public func restore(_ id: String) throws {
        _ = try writer.write { try ColinDismissalRow.deleteOne($0, key: id) }
    }

    /// Every line set aside, the oldest first.
    public func dismissals() throws -> [ColinDismissalRow] {
        try writer.read { try ColinDismissalRow.order(Column("createdAt"), Column("id")).fetchAll($0) }
    }

    /// Calls `onChange` on the main queue with every line set aside: now, and after every change.
    public func observeDismissals(onChange: @escaping @MainActor @Sendable ([ColinDismissalRow]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { try ColinDismissalRow.order(Column("createdAt"), Column("id")).fetchAll($0) }
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { rows in
                MainActor.assumeIsolated { onChange(rows) }
            })
    }

    // MARK: - Colin's thread (v17)

    public func add(_ message: ColinMessageRow) throws {
        try writer.write { try message.insert($0) }
    }

    public func update(_ message: ColinMessageRow) throws {
        try writer.write { try message.update($0) }
    }

    /// The `limit` messages before `date` (the last ones when nil), the oldest first.
    public func messages(before date: Date?, limit: Int) throws -> [ColinMessageRow] {
        try writer.read { db in
            var request = ColinMessageRow.order(Column("createdAt").desc, Column("id").desc).limit(limit)
            if let date { request = request.filter(Column("createdAt") < date) }
            return try request.fetchAll(db).reversed()
        }
    }

    /// The last `count` messages that ended well, the oldest first: what a fresh context recalls.
    public func exchanges(last count: Int) throws -> [ColinMessageRow] {
        try writer.read { db in
            try ColinMessageRow.filter(Column("state") == ColinMessageRow.State.done.rawValue)
                .order(Column("createdAt").desc, Column("id").desc).limit(count).fetchAll(db).reversed()
        }
    }

    /// Colin's answers since `date`: how many, and what they cost.
    public func answers(since date: Date) throws -> (count: Int, costUSD: Double) {
        try writer.read { db in
            let rows = try ColinMessageRow.filter(Column("author") == ColinMessageRow.Author.colin.rawValue && Column("createdAt") >= date
                                                  && Column("state") == ColinMessageRow.State.done.rawValue).fetchAll(db)
            return (rows.count, rows.compactMap(\.costUSD).reduce(0, +))
        }
    }

    /// At launch: an answer a crash left under way is interrupted.
    public func closeUnfinished() throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE colin_message SET state = ? WHERE state = ?",
                           arguments: [ColinMessageRow.State.interrupted.rawValue, ColinMessageRow.State.answering.rawValue])
        }
    }

    /// Calls `onChange` on the main queue with the last `limit` messages, the oldest first: now, and after every change.
    public func observeMessages(limit: Int, onChange: @escaping @MainActor @Sendable ([ColinMessageRow]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { try ColinMessageRow.order(Column("createdAt").desc, Column("id").desc).limit(limit).fetchAll($0).reversed() as [ColinMessageRow] }
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { rows in
                MainActor.assumeIsolated { onChange(rows) }
            })
    }

    /// « Ce que Colin sait »; empty until Paul writes it.
    public func knowledge() throws -> String {
        try writer.read { try ColinKnowledgeRow.fetchOne($0, key: 1)?.text ?? "" }
    }

    public func saveKnowledge(_ text: String, at date: Date) throws {
        try writer.write { try ColinKnowledgeRow(text: text, updatedAt: date).save($0) }
    }
}
