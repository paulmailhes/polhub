import Domain
import Foundation
import Persistence
import Testing
@testable import VaultImport

@Suite struct ProjectImportTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)

    func stores() throws -> (ProjectStore, MeetingStore) {
        let database = try AppDatabase.inMemory()
        return (ProjectStore(database), MeetingStore(database))
    }

    @Test func importingTheFixtureVaultFillsTheBoard() throws {
        let (store, _) = try stores()
        let report = try ProjectImport.run(vault: fixtureVault, store: store, now: now)
        #expect(report.projects == 6 && report.actions == 2 && report.journalEntries == 2)
        #expect(report.withoutStatus == 3)   // Delta (« à voir »), Sans propriétés, YAML cassé
        #expect(report.warnings.count == 1)
        #expect(report.summary == "6 projets, 2 actions, 2 entrées de journal ; 3 sans statut ; 1 avertissement")
        let projects = try store.projects()
        let column = projects.filter { $0.status == .priorite2 }.sorted { $0.kanbanOrder < $1.kanbanOrder }.map(\.name)
        #expect(column == ["Beta Studio", "Alpha"])
        let alpha = try #require(projects.first { $0.name == "Alpha" })
        #expect(alpha.lastMeetingImported == day("2026-11-05T14:30") && alpha.importedFrom == "database/Projets/Alpha.md")
        #expect(alpha.noteModifiedAt != nil && alpha.lastEditedAt == nil && alpha.notes.hasPrefix("- **6 nov.**"))
        #expect(try store.actions(projectID: alpha.id).map(\.text) == ["Lire la fiche du client", "Envoyer le devis"])
        #expect(try store.journal(projectID: alpha.id).first?.title == "Maquette envoyée")
    }

    @Test func reimportingKeepsMeetingsFiledByName() throws {
        let (store, meetings) = try stores()
        _ = try ProjectImport.run(vault: fixtureVault, store: store, now: now)
        let alpha = try #require(try store.projects().first { $0.name == "Alpha" })
        let lonely = try store.addProject(name: "Créé dans l'app", status: .idee, at: now)
        let filed = MeetingRow(createdAt: now, status: .ended, source: .dia, candidateKey: "t/a", title: "Point Alpha", startedAt: now)
        let orphan = MeetingRow(createdAt: now, status: .ended, source: .dia, candidateKey: "t/b", title: "Autre", startedAt: now)
        try meetings.save(filed)
        try meetings.save(orphan)
        try store.setProject(meetingID: filed.id, projectID: alpha.id)
        try store.setProject(meetingID: orphan.id, projectID: lonely.id)

        _ = try ProjectImport.run(vault: fixtureVault, store: store, now: now)
        let newAlpha = try #require(try store.projects().first { $0.name == "Alpha" })
        #expect(try store.meetings(projectID: newAlpha.id).map(\.title) == ["Point Alpha"])
        #expect(try meetings.meeting(id: orphan.id)?.projectID == nil)
        #expect(try store.projects().count == 6)
    }

    @Test func aMissingVaultLeavesTheProjectsUntouched() throws {
        let (store, _) = try stores()
        _ = try store.addProject(name: "Gardé", status: .idee, at: now)
        #expect(throws: VaultError.self) {
            try ProjectImport.run(vault: fixtureVault.appending(path: "nulle part"), store: store, now: now)
        }
        #expect(try store.projects().map(\.name) == ["Gardé"])
    }

    @Test func theVaultIsNeverWritten() throws {
        let copy = FileManager.default.temporaryDirectory.appending(path: "coffre \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: copy) }
        try FileManager.default.copyItem(at: fixtureVault, to: copy)
        func state() throws -> [String: String] {
            let files = FileManager.default.enumerator(at: copy, includingPropertiesForKeys: [.contentModificationDateKey])?.allObjects as? [URL] ?? []
            return try Dictionary(uniqueKeysWithValues: files.filter { !$0.hasDirectoryPath }.map { url in
                let date = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return (url.lastPathComponent, (try String(contentsOf: url, encoding: .utf8)) + "\(date?.timeIntervalSince1970 ?? 0)")
            })
        }
        let before = try state()
        let (store, _) = try stores()
        _ = try ProjectImport.run(vault: copy, store: store, now: now)
        #expect(try state() == before)
    }
}
