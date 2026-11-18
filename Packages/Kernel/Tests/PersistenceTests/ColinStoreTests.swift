import Foundation
import Testing
@testable import Persistence

/// What Paul sets aside on the Accueil (base v16, 18/11): one line by subject, replaced when he sets it aside again.
@Suite struct ColinStoreTests {
    let now = Date(timeIntervalSince1970: 1_794_960_000)
    let thread = "moi@exemple.fr|t1"

    @Test func aDismissalIsKeptReplacedAndRestored() throws {
        let store = ColinStore(try AppDatabase.inMemory())
        let first = ColinDismissalRow(kind: "reply", subject: thread, reason: .notNeeded, createdAt: now)
        #expect(first.id == "reply:moi@exemple.fr|t1")
        try store.dismiss(first)
        #expect(try store.dismissals() == [first])
        var second = first
        second.reason = .later
        second.createdAt = now.addingTimeInterval(60)
        try store.dismiss(second)
        #expect(try store.dismissals() == [second])
        try store.restore(first.id)
        #expect(try store.dismissals().isEmpty)
        // Restoring what is not there is nothing.
        try store.restore("reply:inconnu")
    }

    @Test func eachKindAndEachSubjectHasItsOwnLine() throws {
        let store = ColinStore(try AppDatabase.inMemory())
        let project = UUID()
        try store.dismiss(ColinDismissalRow(kind: "reply", subject: thread, reason: .notNeeded, createdAt: now))
        try store.dismiss(ColinDismissalRow(kind: "silent", subject: thread, reason: .answeredElsewhere, projectID: project, createdAt: now.addingTimeInterval(1)))
        try store.dismiss(ColinDismissalRow(kind: "unfiled", subject: "evenement-1", reason: .later, createdAt: now.addingTimeInterval(2)))
        let rows = try store.dismissals()
        #expect(rows.map(\.id) == ["reply:moi@exemple.fr|t1", "silent:moi@exemple.fr|t1", "unfiled:evenement-1"])
        #expect(rows[1].projectID == project && rows[1].reason == .answeredElsewhere)
        #expect(rows[0].projectID == nil)
    }

    @Test func theDismissalsAreObserved() async throws {
        let store = ColinStore(try AppDatabase.inMemory())
        let seen = Seen()
        let observation = store.observeDismissals { rows in seen.set(rows.map(\.id)) }
        for _ in 0..<200 where seen.value == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(seen.value == [])
        try store.dismiss(ColinDismissalRow(kind: "reply", subject: thread, reason: .later, createdAt: now))
        for _ in 0..<200 where seen.value?.isEmpty != false { try await Task.sleep(for: .milliseconds(10)) }
        #expect(seen.value == ["reply:moi@exemple.fr|t1"])
        observation.cancel()
    }

    final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var ids: [String]?
        var value: [String]? { lock.withLock { ids } }
        func set(_ ids: [String]) { lock.withLock { self.ids = ids } }
    }
}
