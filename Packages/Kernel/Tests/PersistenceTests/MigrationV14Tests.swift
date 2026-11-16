import Foundation
import GRDB
import Testing
@testable import Persistence

/// Base v14 (16/11): an agent's draft may carry files and a formatted text, and a draft keeps the agent's HTML apart
/// from the message it quotes. The drops and the drafts already there stay as they were.
@Suite struct MigrationV14Tests {
    let now = Date(timeIntervalSince1970: 1_794_822_000)   // 16/11/2026

    @Test func aBaseAtV13GetsTheAgentsFilesAndFormatAndKeepsItsDrafts() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-v14 \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "Polhub.sqlite").path(percentEncoded: false)
        do {
            let queue = try DatabaseQueue(path: path)
            try AppDatabase.migrator.migrate(queue, upTo: "v13")
            try queue.write { db in
                try db.execute(sql: "INSERT INTO google_account (email, addedAt) VALUES ('moi@exemple.fr', ?)", arguments: [now])
                try db.execute(sql: """
                    INSERT INTO mail_agent_draft (id, mode, account, "to", cc, subject, body, createdAt)
                    VALUES ('d1', 'new', 'moi@exemple.fr', '[]', '[]', 'Devis', 'Bonjour', ?)
                    """, arguments: [now])
                try db.execute(sql: """
                    INSERT INTO mail_draft (id, account, mode, "to", cc, bcc, subject, body, signature, files, origin, createdAt, updatedAt)
                    VALUES ('b1', 'moi@exemple.fr', 'new', '[]', '[]', '[]', 'Devis', 'Bonjour', 1, '[]', 'paul', ?, ?)
                    """, arguments: [now, now])
            }
        }
        // The helper never migrates: on a base the app has not opened yet, it knows a drop would not fit.
        let before = MailStore(try AppDatabase.forTools(path: path))
        #expect(try before.acceptsAgentDrafts() && !before.agentDraftsTakeFiles())
        let store = MailStore(try AppDatabase(path: path))
        #expect(try store.agentDraftsTakeFiles())
        let drop = try #require(try store.agentDrafts().first)
        #expect(drop.files.isEmpty && drop.format == .plain && drop.body == "Bonjour")
        let draft = try #require(try store.draft("b1"))
        #expect(draft.bodyHTML == nil && draft.body == "Bonjour")
        // The new columns take what the agent and the app write.
        let file = MailDraftFile(filename: "devis.pdf", mimeType: "application/pdf", size: 14)
        try store.drop(MailAgentDraftRow(id: "d2", mode: .new, account: "moi@exemple.fr", subject: "Plan", body: "**Bonjour**", createdAt: now,
                                         files: [file], format: .markdown))
        #expect(try store.agentDrafts().last?.files == [file] && store.agentDrafts().last?.format == .markdown)
        var formatted = draft
        formatted.bodyHTML = "<p><b>Bonjour</b></p>"
        try store.saveDraft(formatted)
        #expect(try store.draft("b1")?.bodyHTML == "<p><b>Bonjour</b></p>")
    }
}
