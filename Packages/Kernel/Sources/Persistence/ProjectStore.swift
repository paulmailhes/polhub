import Domain
import Foundation
import GRDB

public enum ProjectStoreError: Error, Equatable, LocalizedError, CustomStringConvertible {
    /// A helper newer than the base: the app has not opened it since its update, and the base cannot yet say who
    /// changes a project.
    case needsApp

    public var errorDescription: String? {
        switch self {
        case .needsApp: "Polhub doit être ouvert une fois : sa base n'a pas encore le journal des changements. Rien n'a été écrit."
        }
    }
    /// What a session reads when a tool fails.
    public var description: String { errorDescription ?? "" }
}

/// The projects, their actions and journal, and the meetings filed in them.
/// Every write says who makes it (step 3 of Colin, 18/11): the base journals the change with it.
public struct ProjectStore: Sendable {
    public let database: AppDatabase
    private var writer: any DatabaseWriter { database.writer }
    /// Who writes through this store, and in which batch.
    public private(set) var stamp: ChangeStamp

    public init(_ database: AppDatabase) {
        self.database = database
        stamp = ChangeStamp(author: database.author)
    }

    /// The same store, writing as `author`, in a batch of its own: what it writes is one change, undone together.
    public func signed(_ author: ChangeAuthor, reason: String? = nil, source: String? = nil) -> ProjectStore {
        var store = self
        store.stamp = ChangeStamp(author: author, batch: UUID().uuidString.lowercased(), reason: reason, source: source)
        return store
    }

    /// The same author, a new batch: one tool call, one gesture.
    public func batch() -> ProjectStore {
        signed(stamp.author, reason: stamp.reason, source: stamp.source)
    }

    /// Whether the author is Paul: only his writes are a sign of his life on the project (`lastEditedAt`).
    private var byPaul: Bool { stamp.author == .paul }

    /// A write that says who makes it: the stamp first, the change, and the stamp gone, in one transaction — none is
    /// ever left for the next writer, a helper of before, to pass for. A base not yet journaled takes only Paul's
    /// writes (the app migrates it as it opens); a helper has to wait for the app.
    func write<T>(at date: Date = Date(), _ body: (Database) throws -> T) throws -> T {
        try writer.write { db in
            let journaled = try db.tableExists("change_stamp")
            guard journaled || byPaul else { throw ProjectStoreError.needsApp }
            if journaled {
                try db.execute(sql: "INSERT OR REPLACE INTO change_stamp (id, who, batch, reason, source, at) VALUES (1, ?, ?, ?, ?, ?)",
                               arguments: [stamp.author.rawValue, stamp.batch, stamp.reason, stamp.source, date])
            }
            let result = try body(db)
            if journaled { try db.execute(sql: "DELETE FROM change_stamp") }
            return result
        }
    }

    static func key(_ id: UUID) -> String { id.uuidString.lowercased() }

    // MARK: - Projects

    public func projects() throws -> [ProjectRow] {
        try writer.read { try ProjectRow.filter(Column("deletedAt") == nil).order(Column("kanbanOrder"), Column("name")).fetchAll($0) }
    }

    public func project(id: UUID) throws -> ProjectRow? {
        try writer.read { try ProjectRow.fetchOne($0, key: Self.key(id)) }
    }

    /// A change made by Paul in the app: it counts as a sign of life.
    public func save(_ project: ProjectRow, at date: Date) throws {
        var project = project
        if byPaul { project.lastEditedAt = date }
        project.updatedAt = date
        try write(at: date) { try project.save($0) }
    }

    /// What Paul changed on the project's page, and only that, over the project as it is now: a note a
    /// session wrote meanwhile stays (review, Important 7).
    public func saveChanges(from original: ProjectRow, to edited: ProjectRow, at date: Date) throws {
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        func fields(_ project: ProjectRow) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: encoder.encode(project)) as? [String: Any] ?? [:]
        }
        try write(at: date) { db in
            guard let current = try ProjectRow.fetchOne(db, key: Self.key(edited.id)) else { return }
            let before = try fields(original), after = try fields(edited)
            var merged = try fields(current)
            for key in Set(before.keys).union(after.keys) where !Self.same(before[key], after[key]) {
                merged[key] = after[key] ?? NSNull()
            }
            var project = try decoder.decode(ProjectRow.self, from: JSONSerialization.data(withJSONObject: merged))
            if byPaul { project.lastEditedAt = date }
            project.updatedAt = date
            try project.update(db)
        }
    }

    static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): (a as? NSObject)?.isEqual(b) ?? false
        default: false
        }
    }


    /// The notes, written by a session (`polhub mcp`): not a change of Paul's, so `lastEditedAt` stays.
    /// « Supprimer le projet » (15/11): it leaves the board and every list, its meetings, mails and contacts stay;
    /// `restore` brings it back as it was.
    public func moveToTrash(projectID: UUID, at date: Date) throws {
        try write(at: date) { db in
            try db.execute(sql: "UPDATE project SET deletedAt = ?, updatedAt = ? WHERE id = ?", arguments: [date, date, Self.key(projectID)])
        }
    }

    public func restore(projectID: UUID, at date: Date) throws {
        try write(at: date) { db in
            try db.execute(sql: "UPDATE project SET deletedAt = NULL, updatedAt = ? WHERE id = ?", arguments: [date, Self.key(projectID)])
        }
    }

    public func saveNotes(_ project: ProjectRow) throws {
        try write(at: project.updatedAt) { db in
            try db.execute(sql: "UPDATE project SET notes = ?, updatedAt = ? WHERE id = ?",
                           arguments: [project.notes, project.updatedAt, Self.key(project.id)])
        }
    }

    /// Something of the project changed beside its row (a contact linked by a session, 16/11): its row says so, and the
    /// page open on it hears it. Not a change of Paul's: `lastEditedAt` stays.
    public func touch(_ id: UUID, at date: Date) throws {
        try write(at: date) { db in
            try db.execute(sql: "UPDATE project SET updatedAt = ? WHERE id = ?", arguments: [date, Self.key(id)])
        }
    }

    /// A new project at the bottom of its column.
    @discardableResult
    public func addProject(name: String, status: ProjectStatus, at date: Date) throws -> ProjectRow {
        try write(at: date) { db in
            let last = try Double.fetchOne(db, sql: "SELECT MAX(kanbanOrder) FROM project WHERE status = ? AND deletedAt IS NULL",
                                           arguments: [status.rawValue])
            let project = ProjectRow(name: name, status: status, kanbanOrder: (last ?? -1) + 1, createdAt: date)
            try project.insert(db)
            return project
        }
    }

    /// Drops a card in a column, just above `before`, or at the bottom.
    /// A move is Paul's doing: it counts as a sign of life, as a change of the note does in Obsidian.
    public func move(_ id: UUID, to status: ProjectStatus, before: UUID?, at date: Date = Date()) throws {
        guard before != id else { return }
        let edited = byPaul
        try write(at: date) { db in try Self.place(db, id, to: status, before: before, at: date, edited: edited) }
    }

    /// The card in its column, just above `before`, or at the bottom, inside a transaction: a move, and the undoing of
    /// a change of status. `edited`: a sign of Paul's life on the project.
    static func place(_ db: Database, _ id: UUID, to status: ProjectStatus, before: UUID?, at date: Date, edited: Bool) throws {
        guard before != id, var project = try ProjectRow.fetchOne(db, key: key(id)) else { return }
        var column = try ProjectRow
            .filter(Column("status") == status.rawValue && Column("deletedAt") == nil && Column("id") != key(id))
            .order(Column("kanbanOrder"), Column("name")).fetchAll(db)
        let index = before.flatMap { target in column.firstIndex { $0.id == target } } ?? column.count
        let previous = index > 0 ? column[index - 1].kanbanOrder : nil
        let next = index < column.count ? column[index].kanbanOrder : nil
        let position: Double = switch (previous, next) {
        case let (p?, n?): (p + n) / 2
        case let (nil, n?): n - 1
        case let (p?, nil): p + 1
        case (nil, nil): 0
        }
        project.status = status
        project.kanbanOrder = position
        if edited { project.lastEditedAt = date }
        project.updatedAt = date
        if let p = previous, let n = next, n - p < 1e-6 {
            // Too close: the column is numbered again, the card in its place.
            column.insert(project, at: index)
            for (rank, var card) in column.enumerated() {
                card.kanbanOrder = Double(rank)
                try card.update(db)
            }
        } else {
            try project.update(db)
        }
    }

    /// A change of a rule (step 3 of Colin, 18/11), in one transaction and one batch of `author`'s: the status (the card
    /// at the bottom of its new column), the task, the deadline, a line in the journal. Its event is answered once:
    /// `false` when it already was (undone or not), or when the card is in the trash. Not a sign of Paul's life.
    @discardableResult
    public func edit(_ edit: KanbanEdit, by author: ChangeAuthor, at date: Date) throws -> Bool {
        let store = signed(author, reason: edit.reason, source: edit.source)
        return try store.write(at: date) { db in
            if try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM project_change WHERE source = ?)", arguments: [edit.source]) == true { return false }
            guard let project = try ProjectRow.fetchOne(db, key: Self.key(edit.projectID)), project.deletedAt == nil else { return false }
            if let status = edit.status, status != project.status {
                try Self.place(db, edit.projectID, to: status, before: nil, at: date, edited: false)
            }
            if let todo = edit.todo, todo != project.todo {
                try db.execute(sql: "UPDATE project SET todo = ?, updatedAt = ? WHERE id = ?", arguments: [todo, date, Self.key(edit.projectID)])
            }
            if let due = edit.dueDate, due != project.dueDate {
                try db.execute(sql: "UPDATE project SET dueDate = ?, updatedAt = ? WHERE id = ?", arguments: [due, date, Self.key(edit.projectID)])
            }
            if let journal = edit.journal {
                try ProjectJournalRow(projectID: edit.projectID, date: date, title: journal, body: "", createdAt: date).insert(db)
            }
            return true
        }
    }

    public func observeProjects(onChange: @escaping @MainActor @Sendable ([ProjectRow]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { try ProjectRow.filter(Column("deletedAt") == nil).order(Column("kanbanOrder"), Column("name")).fetchAll($0) }
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { rows in
                MainActor.assumeIsolated { onChange(rows) }
            })
    }

    // MARK: - Actions and journal

    public func actions(projectID: UUID) throws -> [ActionRow] {
        try writer.read { try ActionRow.filter(Column("projectID") == Self.key(projectID)).order(Column("position")).fetchAll($0) }
    }

    /// The actions of a meeting's summary, replaced together, in the meeting's project.
    public func replaceMeetingActions(meetingID: UUID, projectID: UUID?, actions: [ActionRow]) throws {
        try write { db in
            try db.execute(sql: "DELETE FROM action WHERE meetingID = ?", arguments: [Self.key(meetingID)])
            for var action in actions {
                action.meetingID = meetingID
                action.projectID = projectID
                try action.insert(db)
            }
        }
    }

    public func actions(meetingID: UUID) throws -> [ActionRow] {
        try writer.read { try ActionRow.filter(Column("meetingID") == Self.key(meetingID)).order(Column("position")).fetchAll($0) }
    }

    public func saveAction(_ action: ActionRow) throws {
        try write(at: action.updatedAt) { try action.save($0) }
    }

    public func deleteAction(id: UUID) throws {
        _ = try write { try ActionRow.deleteOne($0, key: Self.key(id)) }
    }

    /// The newest first.
    public func journal(projectID: UUID) throws -> [ProjectJournalRow] {
        try writer.read {
            try ProjectJournalRow.filter(Column("projectID") == Self.key(projectID)).order(Column("date").desc, Column("createdAt").desc).fetchAll($0)
        }
    }

    public func addJournal(_ entry: ProjectJournalRow) throws {
        try write(at: entry.createdAt) { try entry.insert($0) }
    }

    // MARK: - Meetings

    public func meetings(projectID: UUID) throws -> [MeetingRow] {
        try writer.read {
            try MeetingRow.filter(Column("projectID") == Self.key(projectID) && Column("deletedAt") == nil)
                .order(Column("startedAt").desc).fetchAll($0)
        }
    }

    /// The newest meeting filed in each project.
    public func lastMeetings() throws -> [UUID: Date] {
        try writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT projectID, MAX(startedAt) AS last FROM meeting
                WHERE projectID IS NOT NULL AND deletedAt IS NULL GROUP BY projectID
                """)
            return Dictionary(uniqueKeysWithValues: rows.compactMap { row -> (UUID, Date)? in
                guard let id = UUID(uuidString: row["projectID"]), let last: Date = row["last"] else { return nil }
                return (id, last)
            })
        }
    }

    /// Calls `onChange` on the main queue with the newest meeting of each project, now and after every change.
    public func observeLastMeetings(onChange: @escaping @MainActor @Sendable ([UUID: Date]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { db in
                try Row.fetchAll(db, sql: "SELECT projectID, MAX(startedAt) AS last FROM meeting WHERE projectID IS NOT NULL AND deletedAt IS NULL GROUP BY projectID")
                    .compactMap { row -> (UUID, Date)? in
                        guard let id = UUID(uuidString: row["projectID"]), let last: Date = row["last"] else { return nil }
                        return (id, last)
                    }
            }
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { pairs in
                let last = Dictionary(pairs, uniquingKeysWith: { a, _ in a })
                MainActor.assumeIsolated { onChange(last) }
            })
    }

    /// The next event of each project in the calendar (one not over yet): the meeting a card announces first
    /// (Paul, 15/11: « savoir quand c'est que j'ai la réunion, c'est très important »).
    public func observeNextEvents(onChange: @escaping @MainActor @Sendable ([UUID: Date]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { db in
                try Row.fetchAll(db, sql: """
                    SELECT projectID, MIN(startAt) AS next FROM calendar_event
                    WHERE projectID IS NOT NULL AND allDay = 0 AND endAt >= ? GROUP BY projectID
                    """, arguments: [Date()])
                    .compactMap { row -> (UUID, Date)? in
                        guard let text: String = row["projectID"], let id = UUID(uuidString: text), let next: Date = row["next"] else { return nil }
                        return (id, next)
                    }
            }
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { pairs in
                let next = Dictionary(pairs, uniquingKeysWith: { a, _ in a })
                MainActor.assumeIsolated { onChange(next) }
            })
    }

    public func setProject(meetingID: UUID, projectID: UUID?) throws {
        try write { db in
            try db.execute(sql: "UPDATE meeting SET projectID = ? WHERE id = ?", arguments: [projectID.map(Self.key), Self.key(meetingID)])
        }
    }
}
