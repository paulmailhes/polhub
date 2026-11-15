import Domain
import Foundation
import GRDB

/// The contacts, their projects and the meetings they took part in.
public struct ContactStore: Sendable {
    public let database: AppDatabase
    private var writer: any DatabaseWriter { database.writer }

    public init(_ database: AppDatabase) {
        self.database = database
    }

    static func key(_ id: UUID) -> String { id.uuidString.lowercased() }

    public func contacts() throws -> [ContactRow] {
        try writer.read { try ContactRow.filter(Column("deletedAt") == nil).order(Column("name")).fetchAll($0) }
    }

    public func contact(id: UUID) throws -> ContactRow? {
        try writer.read { try ContactRow.fetchOne($0, key: Self.key(id)) }
    }

    public func contact(email: String) throws -> ContactRow? {
        try writer.read { try ContactRow.filter(Column("email") == email.lowercased()).fetchOne($0) }
    }

    /// The contact with this address, created if needed; a known contact only gets what it lacks.
    @discardableResult
    public func upsert(email: String, name: String, company: String?, at date: Date) throws -> ContactRow {
        try writer.write { db in
            if var known = try ContactRow.filter(Column("email") == email.lowercased()).fetchOne(db) {
                var changed = false
                if known.company == nil, let company { known.company = company; changed = true }
                if known.name.isEmpty || known.name.lowercased() == known.email { known.name = name; changed = true }
                if known.deletedAt != nil { known.deletedAt = nil; changed = true }
                if changed { known.updatedAt = date; try known.update(db) }
                return known
            }
            let contact = ContactRow(name: name, email: email, company: company, createdAt: date)
            try contact.insert(db)
            return contact
        }
    }

    public func save(_ contact: ContactRow, at date: Date) throws {
        var contact = contact
        contact.updatedAt = date
        try writer.write { try contact.save($0) }
    }

    // MARK: - Projects

    /// The project's contacts, without those Paul removed.
    public func contacts(projectID: UUID) throws -> [ContactRow] {
        try writer.read { db in
            try ContactRow.fetchAll(db, sql: """
                SELECT contact.* FROM contact JOIN contact_project ON contact_project.contactID = contact.id
                WHERE contact_project.projectID = ? AND NOT contact_project.excluded AND contact.deletedAt IS NULL
                ORDER BY contact.name
                """, arguments: [Self.key(projectID)])
        }
    }

    public func projects(contactID: UUID) throws -> [ProjectRow] {
        try writer.read { db in
            try ProjectRow.fetchAll(db, sql: """
                SELECT project.* FROM project JOIN contact_project ON contact_project.projectID = project.id
                WHERE contact_project.contactID = ? AND NOT contact_project.excluded AND project.deletedAt IS NULL
                ORDER BY project.name
                """, arguments: [Self.key(contactID)])
        }
    }

    /// Every link, removed ones included: what the automatic links must respect.
    public func links() throws -> [ContactProjectRow] {
        try writer.read { try ContactProjectRow.fetchAll($0) }
    }

    /// An automatic link: nothing happens when it exists, removed by Paul or not.
    public func link(contactID: UUID, projectID: UUID, origin: LinkOrigin, at date: Date) throws {
        try writer.write { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO contact_project (contactID, projectID, origin, excluded, createdAt) VALUES (?, ?, ?, 0, ?)
                """, arguments: [Self.key(contactID), Self.key(projectID), origin.rawValue, date])
        }
    }

    /// A link taken back (« Annuler » after filing a mail): as if it never was.
    public func unlink(contactID: UUID, projectID: UUID) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM contact_project WHERE contactID = ? AND projectID = ?", arguments: [Self.key(contactID), Self.key(projectID)])
        }
    }

    /// A contact made a moment ago and taken back: its links and meetings go with it.
    public func delete(contactID: UUID) throws {
        _ = try writer.write { try ContactRow.deleteOne($0, key: Self.key(contactID)) }
    }

    /// Paul removes a contact from a project: it stays removed.
    public func exclude(contactID: UUID, projectID: UUID, at date: Date) throws {
        try setLink(contactID: contactID, projectID: projectID, excluded: true, at: date)
    }

    /// Paul adds a contact to a project.
    public func include(contactID: UUID, projectID: UUID, at date: Date) throws {
        try setLink(contactID: contactID, projectID: projectID, excluded: false, at: date)
    }

    private func setLink(contactID: UUID, projectID: UUID, excluded: Bool, at date: Date) throws {
        try writer.write { db in
            try db.execute(sql: """
                INSERT INTO contact_project (contactID, projectID, origin, excluded, createdAt) VALUES (?, ?, 'paul', ?, ?)
                ON CONFLICT(contactID, projectID) DO UPDATE SET origin = 'paul', excluded = excluded.excluded
                """, arguments: [Self.key(contactID), Self.key(projectID), excluded, date])
        }
    }

    // MARK: - Meetings

    public func participants(meetingID: UUID) throws -> [ContactRow] {
        try writer.read { db in
            try ContactRow.fetchAll(db, sql: """
                SELECT contact.* FROM contact JOIN meeting_participant ON meeting_participant.contactID = contact.id
                WHERE meeting_participant.meetingID = ? AND contact.deletedAt IS NULL ORDER BY contact.name
                """, arguments: [Self.key(meetingID)])
        }
    }

    public func setParticipants(meetingID: UUID, contactIDs: [UUID]) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM meeting_participant WHERE meetingID = ?", arguments: [Self.key(meetingID)])
            for id in Set(contactIDs) {
                try db.execute(sql: "INSERT INTO meeting_participant (meetingID, contactID) VALUES (?, ?)",
                               arguments: [Self.key(meetingID), Self.key(id)])
            }
        }
    }

    /// The meetings the contact took part in, newest first.
    public func meetings(contactID: UUID) throws -> [MeetingRow] {
        try writer.read { db in
            try MeetingRow.fetchAll(db, sql: """
                SELECT meeting.* FROM meeting JOIN meeting_participant ON meeting_participant.meetingID = meeting.id
                WHERE meeting_participant.contactID = ? AND meeting.deletedAt IS NULL ORDER BY meeting.startedAt DESC
                """, arguments: [Self.key(contactID)])
        }
    }

    /// Calls `onChange` on the main queue with every link, removed ones included, now and after every change
    /// (15/11: who is in an event's or a thread's project shows at once).
    public func observeLinks(onChange: @escaping @MainActor @Sendable ([ContactProjectRow]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { try ContactProjectRow.fetchAll($0) }
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { rows in
                MainActor.assumeIsolated { onChange(rows) }
            })
    }

    /// Calls `onChange` on the main queue with every contact, now and after every change.
    public func observeContacts(onChange: @escaping @MainActor @Sendable ([ContactRow]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { try ContactRow.filter(Column("deletedAt") == nil).order(Column("name")).fetchAll($0) }
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { rows in
                MainActor.assumeIsolated { onChange(rows) }
            })
    }
}
