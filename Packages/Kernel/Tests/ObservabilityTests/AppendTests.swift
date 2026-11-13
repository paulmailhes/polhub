import Foundation
import Testing
@testable import Observability

@Suite struct AppendTests {
    struct Payload: Encodable, Sendable { let n: Int }

    // Remarque différée de la phase 0 : deux copies de l'app peuvent écrire le même journal.
    @Test func twoWritersAppendWithoutOverwriting() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "append-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = try TraceWriter(fileURL: url)
        let second = try TraceWriter(fileURL: url)
        for n in 0..<100 {
            try await first.write(kind: "a", Payload(n: n))
            try await second.write(kind: "b", Payload(n: n))
        }
        await first.close()
        await second.close()
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 200)
        #expect(lines.allSatisfy { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) != nil })
    }
}

@Suite struct EncodingFailureTests {
    struct Bad: Encodable, Sendable { let value: Double }
    struct Good: Encodable, Sendable { let value: Int }

    // Revue finale, Important 2 : un niveau non fini (NaN) ne doit pas condamner toute la trace.
    @Test func anUnencodableLineDoesNotBreakTheTrace() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "nan-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let trace = try TraceWriter(fileURL: url)
        await #expect(throws: (any Error).self) { try await trace.write(kind: "x", Bad(value: .nan)) }
        try await trace.write(kind: "y", Good(value: 1))
        #expect(await trace.failure == nil)
        await trace.close()
        #expect(try String(contentsOf: url, encoding: .utf8).split(separator: "\n").count == 1)
    }
}
