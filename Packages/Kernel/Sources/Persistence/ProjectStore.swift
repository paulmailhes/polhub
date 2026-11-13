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

    /// The notes, written by a session (`polhub mcp`): not a change of Paul's, so `lastEditedAt` stays.
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

    /// A new import: every project of the app is replaced, with its actions and journal. A meeting filed
    /// in a project goes to the new project of the same name, or to none.
    public func replaceAll(_ projects: [ProjectRow], actions: [ActionRow], journal: [ProjectJournalRow]) throws {
        try writer.write { db in
            let filed = try Row.fetchAll(db, sql: """
                SELECT meeting.id AS meetingID, project.name AS name FROM meeting JOIN project ON project.id = meeting.projectID
                """).map { (meetingID: $0["meetingID"] as String, name: $0["name"] as String) }
            try db.execute(sql: "UPDATE meeting SET projectID = NULL WHERE projectID IS NOT NULL")
            // The actions of a meeting's summary (step 3) stay; those of the vault go with their project.
            try db.execute(sql: "DELETE FROM action WHERE projectID IS NOT NULL AND meetingID IS NULL")
            try db.execute(sql: "UPDATE action SET projectID = NULL WHERE projectID IS NOT NULL")
            try db.execute(sql: "DELETE FROM project_journal")
            try db.execute(sql: "DELETE FROM project")
            for project in projects { try project.insert(db) }
            for action in actions { try action.insert(db) }
            for entry in journal { try entry.insert(db) }
            let byName = Dictionary(projects.map { ($0.name, $0.id) }, uniquingKeysWith: { first, _ in first })
            for (meetingID, name) in filed {
                guard let id = byName[name] else { continue }
                try db.execute(sql: "UPDATE meeting SET projectID = ? WHERE id = ?", arguments: [Self.key(id), meetingID])
            }
            // The actions of a meeting follow its project (base v4: the vault's old meetings have some).
            try db.execute(sql: """
                UPDATE action SET projectID = (SELECT meeting.projectID FROM meeting WHERE meeting.id = action.meetingID)
                WHERE meetingID IS NOT NULL
                """)
        }
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

    public func setProject(meetingID: UUID, projectID: UUID?) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE meeting SET projectID = ? WHERE id = ?", arguments: [projectID.map(Self.key), Self.key(meetingID)])
        }
    }
}
