import Foundation
import Testing
@testable import Observability

@Suite struct TraceWriterTests {
    let tmpDir: URL

    init() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "polhub-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    private func lines(of url: URL) throws -> [Substring] {
        try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
    }

    @Test func writesOneJSONLinePerEvent() async throws {
        let url = tmpDir.appending(path: "a/b/trace.jsonl")
        let w = try TraceWriter(fileURL: url)
        try await w.write(kind: "tabs", ["code": "abc-defg-hij"])
        try await w.write(kind: "tabs", ["code": "abc-defg-hij"])
        await w.close()
        let lines = try lines(of: url)
        #expect(lines.count == 2)
        let o = try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as! [String: Any]
        #expect(o["kind"] as? String == "tabs")
        #expect((o["t"] as? String)?.hasSuffix("Z") == true)
        #expect(o["up"] is Double)
        #expect((o["data"] as? [String: String])?["code"] == "abc-defg-hij")
    }

    @Test func appendsToExistingFile() async throws {
        let url = tmpDir.appending(path: "trace.jsonl")
        let first = try TraceWriter(fileURL: url)
        try await first.write(kind: "a", ["n": 1])
        await first.close()
        let second = try TraceWriter(fileURL: url)
        try await second.write(kind: "b", ["n": 2])
        await second.close()
        let lines = try lines(of: url)
        #expect(lines.count == 2)
        #expect(lines[0].contains("\"kind\":\"a\""))
        #expect(lines[1].contains("\"kind\":\"b\""))
    }

    // Review Focus 5 : dossier non inscriptible → erreur visible.
    @Test func unwritableDirectoryThrows() {
        #expect(throws: TraceError.self) {
            _ = try TraceWriter(fileURL: URL(filePath: "/System/Library/trace.jsonl"))
        }
    }

    @Test func sessionDirectoryIsUTCStamped() {
        let d = TracePaths.sessionDirectory(root: URL(filePath: "/tmp/m"), probe: "tabs", at: Date(timeIntervalSince1970: 0))
        #expect(d.path == "/tmp/m/19700101-000000Z-tabs")
    }
}

@Suite struct TraceWriterFailureTests {
    struct DiskFull: Error {}

    // Review Focus 5, en cours de route : un disque plein ne doit pas passer inaperçu.
    @Test func remembersTheFirstWriteFailure() async {
        let writer = TraceWriter(path: "/essai/trace.jsonl", sink: { _ in throw DiskFull() })
        #expect(await writer.failure == nil)
        await #expect(throws: TraceError.self) { try await writer.write(kind: "a", ["n": 1]) }
        let first = await writer.failure
        #expect(first != nil)
        await #expect(throws: TraceError.self) { try await writer.write(kind: "b", ["n": 2]) }
        #expect(await writer.failure == first)
    }

    @Test func aHealthyTraceHasNoFailure() async throws {
        let lines = LockedLines()
        let writer = TraceWriter(path: "/essai/trace.jsonl", sink: { lines.append($0) })
        try await writer.write(kind: "a", ["n": 1])
        #expect(await writer.failure == nil)
        #expect(lines.count == 1)
    }

    // Une écriture tardive sur une trace fermée n'est pas une panne de disque.
    @Test func writingAfterCloseIsNotADiskFailure() async {
        let writer = TraceWriter(path: "/essai/trace.jsonl", sink: { _ in })
        await writer.close()
        await #expect(throws: TraceError.self) { try await writer.write(kind: "a", ["n": 1]) }
        #expect(await writer.failure == nil)
    }
}

final class LockedLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [Data] = []
    func append(_ data: Data) { lock.withLock { lines.append(data) } }
    var count: Int { lock.withLock { lines.count } }
}
