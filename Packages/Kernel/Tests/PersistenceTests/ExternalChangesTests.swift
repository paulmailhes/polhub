import Domain
import Foundation
import GRDB
import Testing
@testable import Persistence

/// The `polhub` command writes in the base while the app runs: the app must see it (13/11).
@Suite struct ExternalChangesTests {
    func temporaryBase() throws -> (URL, String) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "base \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (folder, folder.appending(path: "Polhub.sqlite").path(percentEncoded: false))
    }

    @Test func aWriteFromTheToolsReachesTheAppsObservers() async throws {
        let (folder, path) = try temporaryBase()
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = try AppDatabase(path: path)
        let tools = try AppDatabase.forTools(path: path)
        let store = ProjectStore(app)
        let project = try store.addProject(name: "Alpha", status: .priorite1, at: Date())

        let seen = Counter()
        let observation = ValueObservation.tracking { try ActionRow.fetchCount($0) }
        let cancellable = observation.start(in: app.writer, scheduling: .async(onQueue: DispatchQueue(label: "observation")),
                                            onError: { _ in }, onChange: { seen.set($0) })
        defer { cancellable.cancel() }
        for _ in 0..<50 where seen.value != 0 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(seen.value == 0)

        try ProjectStore(tools).saveAction(ActionRow(projectID: project.id, text: "Relire la maquette", position: 0, createdAt: Date()))
        try await Task.sleep(for: .milliseconds(200))
        #expect(seen.value == 0)   // another process: GRDB cannot see it alone

        try app.notifyExternalChanges()
        for _ in 0..<50 where seen.value != 1 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(seen.value == 1)
    }

    @Test func theToolsNeverMigrateTheBase() throws {
        let (folder, path) = try temporaryBase()
        defer { try? FileManager.default.removeItem(at: folder) }
        // A base the app has never opened: the tools must not create its tables.
        _ = try DatabaseQueue(path: path)
        let tools = try AppDatabase.forTools(path: path)
        #expect(try tools.writer.read { try $0.tableExists("project") } == false)
        #expect(try tools.hasProjects() == false)
        _ = try AppDatabase(path: path)
        #expect(try tools.hasProjects() == true)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var current = -1
    var value: Int { lock.withLock { current } }
    func set(_ value: Int) { lock.withLock { current = value } }
}

@Suite struct ExternalChangeSignalTests {
    @Test func aPostedSignalReachesTheListener() async throws {
        let name = "fr.paulmailhes.polhub.essai.\(UUID().uuidString)"
        let heard = Counter()
        let listener = ExternalChangeSignal.listen(name: name, queue: DispatchQueue(label: "signal")) { heard.set(1) }
        defer { listener.cancel() }
        ExternalChangeSignal.post(name: name)
        for _ in 0..<50 where heard.value != 1 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(heard.value == 1)
    }
}

/// hub closed: SQLite removed the base's `-wal` and `-shm`, and a read-only opening fails (13/11).
@Suite struct ReadingAClosedBaseTests {
    @Test func theCommandReadsTheBaseEvenWhenTheAppIsClosed() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "fermée \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "Source.sqlite").path(percentEncoded: false)
        let app = try AppDatabase(path: source)
        _ = try ProjectStore(app).addProject(name: "Alpha", status: .priorite1, at: Date())
        try app.writer.writeWithoutTransaction { try $0.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)") }
        // The main file alone, in WAL mode, as SQLite leaves it once every connection is closed.
        let path = folder.appending(path: "Polhub.sqlite").path(percentEncoded: false)
        try FileManager.default.copyItem(atPath: source, toPath: path)
        #expect(!FileManager.default.fileExists(atPath: path + "-shm"))
        #expect(throws: (any Error).self) { try AppDatabase.readOnly(path: path).isAtStep2() }
        let reading = try AppDatabase.forReading(path: path)
        #expect(try reading.isAtStep2())
        #expect(try ProjectStore(reading).projects().map(\.name) == ["Alpha"])
    }
}
