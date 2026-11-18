import Foundation
import Domain
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
        second.lastMessageAt = now.addingTimeInterval(7 * 86_400)
        try store.dismiss(second)
        let rows = try store.dismissals()
        #expect(rows.count == 1 && rows.first?.times == 2 && rows.first?.createdAt == second.createdAt)
        // The same click received twice (the same message before Paul's eyes) is one saying.
        try store.dismiss(second)
        #expect(try store.dismissals().first?.times == 2)
        // The thread moved to another project: what was said of the first project is not carried over.
        var moved = second
        moved.projectID = UUID()
        moved.lastMessageAt = now.addingTimeInterval(20 * 86_400)
        try store.dismiss(moved)
        #expect(try store.dismissals().first?.times == 1)
        try store.dismiss(second)
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

    // MARK: - Colin's thread (v17)

    func message(_ text: String, _ author: ColinMessageRow.Author = .paul, minutes: Double, state: ColinMessageRow.State = .done,
                 cost: Double? = nil) -> ColinMessageRow {
        ColinMessageRow(author: author, text: text, state: state, createdAt: now.addingTimeInterval(minutes * 60), costUSD: cost)
    }

    @Test func theThreadIsReadPageByPage() throws {
        let store = ColinStore(try AppDatabase.inMemory())
        for index in 0..<5 { try store.add(message("m\(index)", minutes: Double(index))) }
        let last = try store.messages(before: nil, limit: 2)
        #expect(last.map(\.text) == ["m3", "m4"])
        #expect(try store.messages(before: last[0].createdAt, limit: 2).map(\.text) == ["m1", "m2"])
        #expect(try store.messages(before: now, limit: 10).isEmpty)
    }

    @Test func aMessageIsUpdatedInPlace() throws {
        let store = ColinStore(try AppDatabase.inMemory())
        var answer = message("", .colin, minutes: 1, state: .answering)
        try store.add(answer)
        answer.text = "Trois projets t'attendent."
        answer.state = .done
        answer.costUSD = 0.02
        answer.drafts = ["d1", "d2"]
        try store.update(answer)
        #expect(try store.messages(before: nil, limit: 5) == [answer])
    }

    @Test func onlyFinishedMessagesAreRecalled() throws {
        let store = ColinStore(try AppDatabase.inMemory())
        try store.add(message("Où on en est ?", minutes: 0))
        try store.add(message("Coupé", .colin, minutes: 1, state: .interrupted))
        try store.add(message("Raté", .colin, minutes: 2, state: .failed))
        try store.add(message("Et Cabinet Martin ?", minutes: 3))
        try store.add(message("Il attend Claire.", .colin, minutes: 4))
        #expect(try store.exchanges(last: 2).map(\.text) == ["Et Cabinet Martin ?", "Il attend Claire."])
        #expect(try store.exchanges(last: 10).map(\.text) == ["Où on en est ?", "Et Cabinet Martin ?", "Il attend Claire."])
    }

    @Test func whatColinCostIsCountedSinceADate() throws {
        let store = ColinStore(try AppDatabase.inMemory())
        try store.add(message("Avant", .colin, minutes: -10, cost: 0.02))
        try store.add(message("Une", .colin, minutes: 1, cost: 0.02))
        try store.add(message("Deux", .colin, minutes: 2, cost: 0.02))
        try store.add(message("Question", minutes: 3))
        try store.add(message("Sans coût", .colin, minutes: 4, state: .failed))
        let week = try store.answers(since: now)
        #expect(week.count == 2 && abs(week.costUSD - 0.04) < 1e-9)
    }

    @Test func aCrashLeavesNoAnswerUnderWay() throws {
        let store = ColinStore(try AppDatabase.inMemory())
        try store.add(message("À moitié", .colin, minutes: 1, state: .answering))
        try store.add(message("Fini", .colin, minutes: 2))
        try store.closeUnfinished()
        #expect(try store.messages(before: nil, limit: 5).map(\.state) == [.interrupted, .done])
    }

    @Test func whatColinKnowsIsKeptWhole() throws {
        let store = ColinStore(try AppDatabase.inMemory())
        #expect(try store.knowledge() == "")
        let text = String(repeating: "Écrire court, à mon ton.\nLe lien de rendez-vous : https://exemple.fr/rdv\n", count: 60)
        try store.saveKnowledge(text, at: now)
        #expect(try store.knowledge() == text)
        try store.saveKnowledge("Autre chose", at: now.addingTimeInterval(60))
        #expect(try store.knowledge() == "Autre chose")
    }

    @Test func theThreadIsObserved() async throws {
        let store = ColinStore(try AppDatabase.inMemory())
        let seen = Seen()
        let observation = store.observeMessages(limit: 2) { rows in seen.set(rows.map(\.text)) }
        for _ in 0..<200 where seen.value == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(seen.value == [])
        for index in 0..<3 { try store.add(message("m\(index)", minutes: Double(index))) }
        for _ in 0..<200 where seen.value != ["m1", "m2"] { try await Task.sleep(for: .milliseconds(10)) }
        #expect(seen.value == ["m1", "m2"])
        observation.cancel()
    }

    @Test func colinsToolsAreElevenAndNamedAsClaudeCodeNamesThem() {
        #expect(ColinTool.allowed.count == 11)
        #expect(ColinTool.allowed.first == "mcp__polhub__projets")
        #expect(ColinTool.brouillon.allowedName == "mcp__polhub__brouillon")
        #expect(ColinTool.lockMark == "Verrou de Colin")
    }

    final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var ids: [String]?
        var value: [String]? { lock.withLock { ids } }
        func set(_ ids: [String]) { lock.withLock { self.ids = ids } }
    }
}
