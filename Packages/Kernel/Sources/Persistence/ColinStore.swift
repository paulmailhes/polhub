import Foundation
import GRDB

/// What Colin keeps in the base (18/11). For now: the lines of the Accueil that Paul set aside.
public struct ColinStore: Sendable {
    public let database: AppDatabase
    private var writer: any DatabaseWriter { database.writer }

    public init(_ database: AppDatabase) {
        self.database = database
    }

    /// Sets a line aside; a row of the same line is replaced.
    public func dismiss(_ row: ColinDismissalRow) throws {
        try writer.write { try row.save($0) }
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
}
