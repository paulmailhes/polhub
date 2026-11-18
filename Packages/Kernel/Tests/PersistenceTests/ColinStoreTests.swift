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

    @Test func aLineSetAsideAgainAsAnsweredElsewhereIsCounted() throws {
        // « Elle a répondu ailleurs », a second time on the same thread: the row is the same, and it counts two.
        let store = ColinStore(try AppDatabase.inMemory())
        let project = UUID()
        let first = ColinDismissalRow(kind: "silent", subject: thread, reason: .answeredElsewhere, projectID: project, createdAt: now)
        try store.dismiss(first)
        #expect(try store.dismissals().first?.times == 1)
        var second = first
        second.createdAt = now.addingTimeInterval(8 * 86_400)
        try store.dismiss(second)
        let rows = try store.dismissals()
        #expect(rows.count == 1 && rows.first?.times == 2 && rows.first?.createdAt == second.createdAt)
        // Another reason starts again from one.
        var later = first
        later.reason = .later
        try store.dismiss(later)
        #expect(try store.dismissals().first?.times == 1)
        try store.dismiss(first)
        #expect(try store.dismissals().first?.times == 1)
    }

    @Test func aDismissalKeepsTheLastMessagePaulHadBeforeHim() throws {
        // The click says « nothing to do about what I see »: what he saw is kept, to the millisecond, beside the row.
        let database = try AppDatabase.inMemory()
        let store = ColinStore(database)
        let seen = now.addingTimeInterval(-3_600.5)
        let project = UUID()
        try store.dismiss(ColinDismissalRow(kind: "reply", subject: thread, reason: .notNeeded, projectID: project, createdAt: now, lastMessageAt: seen))
        #expect(try store.dismissals().first?.lastMessageAt == seen)
        try store.dismiss(ColinDismissalRow(kind: "unfiled", subject: "e1", reason: .later, createdAt: now))
        #expect(try store.dismissals().last?.lastMessageAt == nil)
        // A project is kept as the other tables keep it: its identifier in small letters.
        let stored = try database.writer.read { try String.fetchOne($0, sql: "SELECT projectID FROM colin_dismissal WHERE kind = 'reply'") }
        #expect(stored == project.uuidString.lowercased())
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
