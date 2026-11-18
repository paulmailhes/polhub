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

    @Test func dueSettersSaysWhoSetTheDateLast() throws {
        let (database, store, martin) = try world()
        let nord = try store.addProject(name: "Studio Nord", status: .priorite1, at: now)
        let atelier = try store.addProject(name: "Atelier Dupont", status: .priorite1, at: now)
        _ = try store.signed(.colin, source: "event:a").setDue(martin.id, to: monday, journal: nil, at: now)
        _ = try store.setDue(martin.id, to: monday.addingTimeInterval(86_400), journal: nil, at: now.addingTimeInterval(120))
        _ = try store.signed(.colin, source: "event:b").setDue(nord.id, to: monday, journal: nil, at: now)
        let setters = try ProjectChanges(database).dueSetters()
        #expect(setters[martin.id] == .paul)
        #expect(setters[nord.id] == .colin)
        #expect(setters[atelier.id] == nil)
    }

    /// Final review: « Livré » then « Annuler » on a date Colin set leaves it Colin's — the call stays a call.
    @Test func anUndoneGestureLeavesTheSetterAsItWas() throws {
        let (database, store, martin) = try world()
        _ = try store.signed(.colin, source: "event:a").setDue(martin.id, to: monday, journal: nil, at: now)
        // An hour later: no earlier keystroke of Paul's to merge with.
        let undo = try #require(try store.setDue(martin.id, to: nil, journal: "Livré le 18/11", at: now.addingTimeInterval(3_600)))
        try store.revert(undo, at: now.addingTimeInterval(3_605))
        #expect(try store.project(id: martin.id)?.dueDate == monday)
        #expect(try ProjectChanges(database).dueSetters()[martin.id] == .colin)
    }

    @MainActor @Test func dueSettersAreObserved() async throws {
        let (database, store, martin) = try world()
        final class Box: @unchecked Sendable { var setters: [UUID: ChangeAuthor] = [:] }
        let box = Box()
        let observation = ProjectChanges(database).observeDueSetters { box.setters = $0 }
        _ = try store.signed(.colin, source: "event:a").setDue(martin.id, to: monday, journal: nil, at: now)
        for _ in 0..<100 where box.setters[martin.id] != .colin { try await Task.sleep(for: .milliseconds(20)) }
        #expect(box.setters[martin.id] == .colin)
        observation.cancel()
    }

    @MainActor @Test func firstOpenActionsSkipTheDone() async throws {
        let (_, store, martin) = try world()
        var done = ActionRow(projectID: martin.id, text: "Relire la maquette", position: 0, createdAt: now)
        done.done = true
        try store.saveAction(done)
        try store.saveAction(ActionRow(projectID: martin.id, text: "Envoyer le devis", position: 1, createdAt: now))
        final class Box: @unchecked Sendable { var first: [UUID: String] = [:] }
        let box = Box()
        let observation = store.observeFirstOpenActions { box.first = $0 }
        for _ in 0..<100 where box.first.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(box.first == [martin.id: "Envoyer le devis"])
        observation.cancel()
    }
}
