import Domain
import Foundation
import GRDB
import Testing
@testable import Persistence

/// « Reporter » and « Livré » on the Accueil (0.36.0, 18/11): Paul sets a deadline from « À faire », and takes it back
/// with « Annuler »; the list knows who set each deadline last, and the first thing left to do on each project.
@Suite(.timeLimit(.minutes(1))) struct ProjectDueTests {
    let now = Date(timeIntervalSince1970: 1_794_992_400)   // Wednesday 18/11/2026, 10:00 in Paris
    var yesterday: Date { now.addingTimeInterval(-86_400) }
    var monday: Date { now.addingTimeInterval(5 * 86_400) }

    func world() throws -> (AppDatabase, ProjectStore, ProjectRow) {
        let database = try AppDatabase.inMemory(author: .paul)
        let store = ProjectStore(database)
        var martin = try store.addProject(name: "Cabinet Martin", status: .priorite2, at: now)
        martin.dueDate = yesterday
        try store.save(martin, at: now)
        return (database, store, martin)
    }

    @Test func setDueWritesTheDateAndTheJournal() throws {
        let (_, store, martin) = try world()
        let undo = try #require(try store.setDue(martin.id, to: nil, journal: "Livré le 18/11", at: now))
        #expect(try store.project(id: martin.id)?.dueDate == nil)
        #expect(try store.journal(projectID: martin.id).map(\.title) == ["Livré le 18/11"])
        #expect(undo.projectID == martin.id && undo.before == yesterday && undo.after == nil && undo.journalID != nil)
        // A project that is gone: nothing is written.
        #expect(try store.setDue(UUID(), to: monday, journal: nil, at: now) == nil)
    }

    @Test func revertPutsBackOnlyWhatItWrote() throws {
        let (_, store, martin) = try world()
        let undo = try #require(try store.setDue(martin.id, to: nil, journal: "Livré le 18/11", at: now))
        try store.revert(undo, at: now)
        #expect(try store.project(id: martin.id)?.dueDate == yesterday)
        #expect(try store.journal(projectID: martin.id).isEmpty)

        // Changed again since: the date stays as it is now, the journal line still goes.
        let first = try #require(try store.setDue(martin.id, to: nil, journal: "Livré le 18/11", at: now))
        _ = try store.setDue(martin.id, to: monday, journal: nil, at: now.addingTimeInterval(120))
        try store.revert(first, at: now.addingTimeInterval(180))
        #expect(try store.project(id: martin.id)?.dueDate == monday)
        #expect(try store.journal(projectID: martin.id).isEmpty)
    }

    @Test func paulDeadlinesAreTheDatesHeSetHimself() throws {
        let (database, store, martin) = try world()
        let nord = try store.addProject(name: "Studio Nord", status: .priorite1, at: now)
        let atelier = try store.addProject(name: "Atelier Dupont", status: .priorite1, at: now)
        _ = try store.signed(.colin, source: "event:a").setDue(martin.id, to: monday, journal: nil, at: now.addingTimeInterval(3_600))
        _ = try store.setDue(martin.id, to: monday.addingTimeInterval(86_400), journal: nil, at: now.addingTimeInterval(7_200))
        _ = try store.signed(.colin, source: "event:b").setDue(nord.id, to: monday, journal: nil, at: now)
        let deadlines = try ProjectChanges(database).paulDeadlines()
        #expect(deadlines.contains(martin.id))
        #expect(!deadlines.contains(nord.id) && !deadlines.contains(atelier.id))
    }

    /// 0.37.0: « Livré, prochaine échéance : call jeudi » — a date Paul takes from a meeting is the call, not his deadline.
    @Test func aDateFromAMeetingIsNoDeadlineOfPauls() throws {
        let (database, store, martin) = try world()
        _ = try store.signed(.paul, reason: "Livré", source: "event:x").setDue(martin.id, to: monday, journal: "Livré le 18/11", at: now.addingTimeInterval(3_600))
        #expect(try !ProjectChanges(database).paulDeadlines().contains(martin.id))
        _ = try store.setDue(martin.id, to: monday.addingTimeInterval(86_400), journal: nil, at: now.addingTimeInterval(7_200))
        #expect(try ProjectChanges(database).paulDeadlines().contains(martin.id))
    }

    /// Final review of 0.36.0: « Livré » then « Annuler » on a date Colin set leaves it Colin's — the call stays a call.
    @Test func anUndoneGestureLeavesTheDeadlineAsItWas() throws {
        let (database, store, martin) = try world()
        _ = try store.signed(.colin, source: "event:a").setDue(martin.id, to: monday, journal: nil, at: now)
        // An hour later: no earlier keystroke of Paul's to merge with.
        let undo = try #require(try store.setDue(martin.id, to: nil, journal: "Livré le 18/11", at: now.addingTimeInterval(3_600)))
        try store.revert(undo, at: now.addingTimeInterval(3_605))
        #expect(try store.project(id: martin.id)?.dueDate == monday)
        #expect(try !ProjectChanges(database).paulDeadlines().contains(martin.id))
    }

    /// Final review of 0.37.0: Paul's date gestures a few seconds apart merge into one change, which takes the last
    /// one's source — a date from the next call stays the call's, a date of his own stays his.
    @Test func aMergedGestureTakesTheLastSource() throws {
        let (database, store, martin) = try world()
        let t = now.addingTimeInterval(3_600)
        let first = try #require(try store.setDue(martin.id, to: nil, journal: "Livré le 18/11", at: t))
        try store.revert(first, at: t.addingTimeInterval(5))
        _ = try store.signed(.paul, reason: "Livré", source: "event:x").setDue(martin.id, to: monday, journal: "Livré le 18/11", at: t.addingTimeInterval(10))
        #expect(try !ProjectChanges(database).paulDeadlines().contains(martin.id))
        _ = try store.setDue(martin.id, to: monday.addingTimeInterval(86_400), journal: nil, at: t.addingTimeInterval(20))
        #expect(try ProjectChanges(database).paulDeadlines().contains(martin.id))
    }

    /// Final review of 0.37.0: « Livré, prochaine échéance » onto the day already set by Paul still makes it the call's;
    /// « Annuler » makes it his again.
    @Test func aSameDayCallMarksTheDate() throws {
        let (database, store, martin) = try world()
        _ = try store.setDue(martin.id, to: monday, journal: nil, at: now.addingTimeInterval(3_600))
        #expect(try ProjectChanges(database).paulDeadlines().contains(martin.id))
        let undo = try #require(try store.signed(.paul, reason: "Livré", source: "event:x")
            .setDue(martin.id, to: monday, journal: "Livré le 18/11", at: now.addingTimeInterval(7_200)))
        #expect(try store.project(id: martin.id)?.dueDate == monday)
        #expect(try !ProjectChanges(database).paulDeadlines().contains(martin.id))
        try store.revert(undo, at: now.addingTimeInterval(7_205))
        #expect(try ProjectChanges(database).paulDeadlines().contains(martin.id))
        #expect(try store.journal(projectID: martin.id).isEmpty)
    }

    @MainActor @Test func paulDeadlinesAreObserved() async throws {
        let (database, store, martin) = try world()
        final class Box: @unchecked Sendable { var deadlines: Set<UUID> = [] }
        let box = Box()
        let observation = ProjectChanges(database).observePaulDeadlines { box.deadlines = $0 }
        _ = try store.setDue(martin.id, to: monday, journal: nil, at: now.addingTimeInterval(3_600))
        for _ in 0..<100 where !box.deadlines.contains(martin.id) { try await Task.sleep(for: .milliseconds(20)) }
        #expect(box.deadlines.contains(martin.id))
        observation.cancel()
    }

    @MainActor @Test func openActionsInOrder() async throws {
        let (_, store, martin) = try world()
        var done = ActionRow(projectID: martin.id, text: "première", position: 0, createdAt: now)
        done.done = true
        try store.saveAction(done)
        try store.saveAction(ActionRow(projectID: martin.id, text: "troisième", position: 2, createdAt: now))
        try store.saveAction(ActionRow(projectID: martin.id, text: "deuxième", position: 1, createdAt: now))
        final class Box: @unchecked Sendable { var open: [UUID: [String]] = [:] }
        let box = Box()
        let observation = store.observeOpenActions { box.open = $0 }
        for _ in 0..<100 where box.open.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(box.open == [martin.id: ["deuxième", "troisième"]])
        observation.cancel()
    }
}
