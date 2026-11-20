import Domain
import Foundation
import GRDB

/// Paul's Google accounts and the events of their primary calendars.
public struct CalendarStore: Sendable {
    public let database: AppDatabase
    private var writer: any DatabaseWriter { database.writer }

    public init(_ database: AppDatabase) {
        self.database = database
    }

    static func key(_ id: UUID) -> String { id.uuidString.lowercased() }

    // MARK: - Accounts

    public func accounts() throws -> [GoogleAccountRow] {
        try writer.read { try GoogleAccountRow.order(Column("addedAt")).fetchAll($0) }
    }

    public func addAccount(email: String, at date: Date) throws {
        try writer.write { db in
            if try GoogleAccountRow.fetchOne(db, key: email.lowercased()) == nil {
                try GoogleAccountRow(email: email, addedAt: date).insert(db)
            }
        }
    }

    /// The account and its events go.
    public func removeAccount(email: String) throws {
        try writer.write { db in
            _ = try GoogleAccountRow.deleteOne(db, key: email.lowercased())
            try db.execute(sql: "DELETE FROM calendar_event WHERE account = ?", arguments: [email.lowercased()])
        }
    }

    /// After a sync: the token for the next one (`nil` forces a full sync), or the error that stopped it.
    public func recordSync(email: String, syncToken: String?, error: String?, at date: Date) throws {
        try writer.write { db in
            guard var account = try GoogleAccountRow.fetchOne(db, key: email.lowercased()) else { return }
            if error == nil {
                account.syncToken = syncToken
                account.lastSyncAt = date
            }
            account.lastError = error
            try account.update(db)
        }
    }

    /// Paul's color for an account; `nil` goes back to the default.
    public func setColor(email: String, hex: String?) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE google_account SET color = ? WHERE email = ?", arguments: [hex, email.lowercased()])
        }
    }

    /// What Google says the account granted, at each of its tokens (14/11).
    public func setGrantedScopes(email: String, scopes: String) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE google_account SET grantedScopes = ? WHERE email = ? AND grantedScopes IS NOT ?",
                           arguments: [scopes, email.lowercased(), scopes])
        }
    }

    // MARK: - Events

    /// What Google sent: new or changed events replace their copy, keeping what the app added (project,
    /// recorded meeting); cancelled ones go.
    /// `keepingNewerThan`: a row written after that date (by hub, while a sync was reading Google) stays as it is
    /// (review of 14/11).
    public func applyGoogle(account: String, changed: [CalendarEventRow], cancelled: [String], at date: Date,
                            keepingNewerThan: Date? = nil) throws {
        try writer.write { db in
            for var event in changed {
                if let known = try CalendarEventRow.fetchOne(db, key: event.id) {
                    if let keepingNewerThan, known.updatedAt > keepingNewerThan { continue }
                    event.projectID = known.projectID
                    event.projectOrigin = known.projectOrigin
                    event.meetingID = known.meetingID
                }
                event.updatedAt = date
                try event.save(db)
            }
            for id in cancelled {
                _ = try CalendarEventRow.deleteOne(db, key: CalendarEventRow.key(account: account, eventID: id))
            }
        }
    }

    public func event(id: String) throws -> CalendarEventRow? {
        try writer.read { try CalendarEventRow.fetchOne($0, key: id) }
    }

    /// The events that start in the interval, in order.
    public func events(from start: Date, to end: Date) throws -> [CalendarEventRow] {
        try writer.read {
            try CalendarEventRow.filter(Column("startAt") >= start && Column("startAt") < end).order(Column("startAt")).fetchAll($0)
        }
    }

    /// The events of a Meet code, for a recording that starts (14/11).
    public func events(meetCode: String) throws -> [CalendarEventRow] {
        try writer.read { try CalendarEventRow.filter(Column("meetCode") == meetCode).fetchAll($0) }
    }

    public func allEvents() throws -> [CalendarEventRow] {
        try writer.read { try CalendarEventRow.order(Column("startAt")).fetchAll($0) }
    }

    public func events(projectID: UUID) throws -> [CalendarEventRow] {
        try writer.read { try CalendarEventRow.filter(Column("projectID") == Self.key(projectID)).order(Column("startAt")).fetchAll($0) }
    }

    /// Paul's filing (origin `.paul`), « no project » included: the loop never changes it.
    public func setProject(eventID: String, projectID: UUID?, origin: EventProjectOrigin?) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE calendar_event SET projectID = ?, projectOrigin = ? WHERE id = ?",
                           arguments: [projectID.map(Self.key), origin?.rawValue, eventID])
        }
    }

    /// Paul files a Google event: every copy of it, in each of his calendars, follows.
    public func setProject(googleEventID: String, projectID: UUID?, origin: EventProjectOrigin?) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE calendar_event SET projectID = ?, projectOrigin = ? WHERE eventID = ?",
                           arguments: [projectID.map(Self.key), origin?.rawValue, googleEventID])
        }
    }

    /// A filing found by the loop: never over Paul's, even one he made while the loop was running (review, Important 3).
    public func setAutomaticProject(eventID: String, projectID: UUID?, origin: EventProjectOrigin?) throws {
        try writer.write { db in
            try db.execute(sql: """
                UPDATE calendar_event SET projectID = ?, projectOrigin = ?
                WHERE id = ? AND (projectOrigin IS NULL OR projectOrigin != 'paul')
                """, arguments: [projectID.map(Self.key), projectID == nil ? nil : origin?.rawValue, eventID])
        }
    }

    public func setMeeting(eventID: String, meetingID: UUID?) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE calendar_event SET meetingID = ? WHERE id = ?", arguments: [meetingID.map(Self.key), eventID])
        }
    }

    /// Calls `onChange` on the main queue with every event, now and after every change.
    public func observeEvents(onChange: @escaping @MainActor @Sendable ([CalendarEventRow]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { try CalendarEventRow.order(Column("startAt")).fetchAll($0) }
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { rows in
                MainActor.assumeIsolated { onChange(rows) }
            })
    }

    public func observeAccounts(onChange: @escaping @MainActor @Sendable ([GoogleAccountRow]) -> Void) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { try GoogleAccountRow.order(Column("addedAt")).fetchAll($0) }
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { rows in
                MainActor.assumeIsolated { onChange(rows) }
            })
    }
}
