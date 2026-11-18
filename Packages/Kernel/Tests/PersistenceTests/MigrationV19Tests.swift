import Foundation
import GRDB
import Testing
@testable import Persistence

/// Base v19 (the Accueil's pass, 18/11): an answer of Colin's keeps what he did (its steps) and how long he worked.
/// Two columns on his thread; an answer of before reads with none.
@Suite struct MigrationV19Tests {
    let now = Date(timeIntervalSince1970: 1_794_992_400)   // 18/11/2026

    @Test func aBaseAtV18GainsStepsAndDuration() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-v19 \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "Polhub.sqlite").path(percentEncoded: false)
        let queue = try DatabaseQueue(path: path)
        try AppDatabase.migrator.migrate(queue, upTo: "v18")
        try queue.write { db in
            try db.execute(sql: "INSERT INTO colin_message (id, author, text, state, createdAt, drafts) VALUES ('m1', 'colin', 'Trois projets.', 'done', ?, '[]')",
                           arguments: [now])
        }
        let base = try AppDatabase(path: path)
        let columns = try base.writer.read { try $0.columns(in: "colin_message").map(\.name) }
        #expect(columns.contains("steps") && columns.contains("durationMs"))
        let old = try #require(try ColinStore(base).messages(before: nil, limit: 10).first)
        #expect(old.steps == [] && old.durationMs == nil && old.text == "Trois projets.")
        // An answer of after keeps its steps.
        var answer = ColinMessageRow(author: .colin, text: "Deux mails.", createdAt: now.addingTimeInterval(60), durationMs: 1_200)
        answer.steps = [ColinStep(id: "t1", tool: "mails", arguments: ["projet": "Cabinet Martin"], state: .done, position: 0)]
        try ColinStore(base).add(answer)
        let kept = try #require(try ColinStore(base).messages(before: nil, limit: 10).first { $0.id == answer.id })
        #expect(kept.steps == answer.steps && kept.durationMs == 1_200)
        let backups = try FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "Sauvegardes").path(percentEncoded: false))
        #expect(backups.contains { $0.hasPrefix("Polhub-avant-v19-") })
    }
}
