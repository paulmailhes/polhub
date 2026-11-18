import Domain
import Foundation
import GRDB
import Persistence
import Testing

/// The entry test of step 3 (18/11): a helper of before the journal — still running in the sessions opened before an
/// update, with its program of before — writes a base of v18, and its writes are journaled as an agent's, with
/// `lastEditedAt` left as it was. Only with `POLHUB_OLD_HELPER`, the path of such a `polhub`: `make check` never runs
/// a program from outside.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["POLHUB_OLD_HELPER"] != nil), .timeLimit(.minutes(1)))
struct OldHelperTests {
    @Test func anOldHelpersWriteIsJournaled() throws {
        let helper = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["POLHUB_OLD_HELPER"]))
        let folder = FileManager.default.temporaryDirectory.appending(path: "ancien-programme \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "Polhub.sqlite").path(percentEncoded: false)
        let edited = Date(timeIntervalSince1970: 1_794_992_400)
        let projectID: UUID
        do {
            let base = try AppDatabase(path: path)
            let store = ProjectStore(base)
            let project = try store.addProject(name: "Cabinet Martin", status: .priorite2, at: edited)
            var touched = project
            touched.todo = "Envoyer le devis"
            try store.saveChanges(from: project, to: touched, at: edited)
            projectID = project.id
        }
        let process = Process()
        process.executableURL = helper
        process.arguments = ["mcp", "--base", path]
        process.currentDirectoryURL = folder
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let calls = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"essai","version":"1"}}}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"projet","arguments":{"projet":"Cabinet Martin","statut":"priorité 1","tache":"Relancer Claire"}}}"#,
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"action","arguments":{"projet":"Cabinet Martin","texte":"Appeler Claire"}}}"#,
        ]
        input.fileHandleForWriting.write(Data((calls.joined(separator: "\n") + "\n").utf8))
        try input.fileHandleForWriting.close()
        let answers = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(!answers.contains(#""isError":true"#), "\(answers)")
        let tools = try AppDatabase.forTools(path: path)
        let rows = try tools.writer.read { try ProjectChangeRow.filter(Column("who") == "agent").order(Column("id")).fetchAll($0) }
        #expect(Set(rows.map(\.field)) == [.status, .todo, .actionAdded])
        #expect(rows.allSatisfy { $0.batch == nil && $0.projectID == projectID })
        let lines = try ProjectChanges(tools).lines(since: .distantPast, authors: [.agent])
        #expect(lines.count == 1)
        let project = try #require(try ProjectStore(tools).project(id: projectID))
        #expect(project.status == .priorite1 && project.todo == "Relancer Claire")
        #expect(project.lastEditedAt == edited)
        // And it is undone.
        let line = try #require(lines.first)
        #expect(try ProjectChanges(AppDatabase.forTools(path: path, author: .paul)).undo(line, at: edited.addingTimeInterval(60)) == .undone)
        let back = try #require(try ProjectStore(tools).project(id: projectID))
        #expect(back.status == .priorite2 && back.todo == "Envoyer le devis")
        #expect(try ProjectStore(tools).actions(projectID: projectID).isEmpty)
    }
}
