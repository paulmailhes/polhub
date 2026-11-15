import Domain
import Foundation
import GRDB

/// The projects, their actions and journal, and the meetings filed in them.
public struct ProjectStore: Sendable {
    public let database: AppDatabase
    private var writer: any DatabaseWriter { database.writer }

    public init(_ database: AppDatabase) {
        self.database = database
    }

    private static func key(_ id: UUID) -> String { id.uuidString.lowercased() }

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
        project.lastEditedAt = date
        project.updatedAt = date
        try writer.write { try project.save($0) }
    }

    /// What Paul changed on the project's page, and only that, over the project as it is now: a note a
    /// session wrote meanwhile stays (review, Important 7).
    public func saveChanges(from original: ProjectRow, to edited: ProjectRow, at date: Date) throws {
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        func fields(_ project: ProjectRow) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: encoder.encode(project)) as? [String: Any] ?? [:]
        }
        try writer.write { db in
            guard let current = try ProjectRow.fetchOne(db, key: Self.key(edited.id)) else { return }
            let before = try fields(original), after = try fields(edited)
            var merged = try fields(current)
            for key in Set(before.keys).union(after.keys) where !Self.same(before[key], after[key]) {
                merged[key] = after[key] ?? NSNull()
            }
            var project = try decoder.decode(ProjectRow.self, from: JSONSerialization.data(withJSONObject: merged))
            project.lastEditedAt = date
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
        try writer.write { db in
            try db.execute(sql: "UPDATE project SET deletedAt = ?, updatedAt = ? WHERE id = ?", arguments: [date, date, Self.key(projectID)])
        }
    }

    public func restore(projectID: UUID, at date: Date) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE project SET deletedAt = NULL, updatedAt = ? WHERE id = ?", arguments: [date, Self.key(projectID)])
        }
    }

    public func saveNotes(_ project: ProjectRow) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE project SET notes = ?, updatedAt = ? WHERE id = ?",
                           arguments: [project.notes, project.updatedAt, Self.key(project.id)])
        }
    }

    /// A new project at the bottom of its column.
    @discardableResult
    public func addProject(name: String, status: ProjectStatus, at date: Date) throws -> ProjectRow {
        try writer.write { db in
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
        try writer.write { db in
            guard var project = try ProjectRow.fetchOne(db, key: Self.key(id)) else { return }
            var column = try ProjectRow
                .filter(Column("status") == status.rawValue && Column("deletedAt") == nil && Column("id") != Self.key(id))
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
            project.lastEditedAt = date
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
        try writer.write { db in
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
        try writer.write { try action.save($0) }
    }

    public func deleteAction(id: UUID) throws {
        _ = try writer.write { try ActionRow.deleteOne($0, key: Self.key(id)) }
    }

    /// The newest first.
    public func journal(projectID: UUID) throws -> [ProjectJournalRow] {
        try writer.read {
            try ProjectJournalRow.filter(Column("projectID") == Self.key(projectID)).order(Column("date").desc, Column("createdAt").desc).fetchAll($0)
        }
    }

    public func addJournal(_ entry: ProjectJournalRow) throws {
        try writer.write { try entry.insert($0) }
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
        try writer.write { db in
            try db.execute(sql: "UPDATE meeting SET projectID = ? WHERE id = ?", arguments: [projectID.map(Self.key), Self.key(meetingID)])
        }
    }
}
