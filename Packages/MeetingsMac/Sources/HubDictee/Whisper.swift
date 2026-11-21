import Compute
import Foundation

/// Why Whisper could not write.
struct WhisperUnavailable: Error, CustomStringConvertible {
    let description: String
}

/// Whisper, loaded once in the background and used by one caller at a time, in the order they came (21/11). The helper
/// takes its orders from its first second: a dictation said while Whisper loads is written as soon as it is there.
actor WhisperBox {
    private var engine: WhisperEngine?
    private var failure: String?
    private var waiting: [CheckedContinuation<Void, Never>] = []
    /// The end of the line: each call waits for the one before.
    private var last: Task<Void, Never>?

    var isLoaded: Bool { engine != nil }

    func loaded(_ engine: WhisperEngine) {
        self.engine = engine
        wake()
    }

    func failed(_ why: String) {
        failure = why
        wake()
    }

    private func wake() {
        let waiting = waiting
        self.waiting = []
        for continuation in waiting { continuation.resume() }
    }

    private func ready() async throws -> WhisperEngine {
        while true {
            if let engine { return engine }
            if let failure { throw WhisperUnavailable(description: failure) }
            await withCheckedContinuation { waiting.append($0) }
        }
    }

    /// Runs `work` with Whisper once it is loaded and free.
    func run<Value: Sendable>(_ work: @escaping @Sendable (WhisperEngine) async throws -> Value) async throws -> Value {
        let before = last
        // Someone waits for every text Whisper writes here: never behind the Mac's background work.
        let task = Task(priority: .userInitiated) { () throws -> Value in
            await before?.value
            return try await work(try await self.ready())
        }
        last = Task { _ = try? await task.value }
        return try await task.value
    }
}

/// A call to Whisper that can be told to stop: a text nobody waits for any more.
final class StopFlag: @unchecked Sendable {
    private var stopped = false
    private let lock = NSLock()

    var isStopped: Bool { lock.withLock { stopped } }

    func stop() {
        lock.withLock { stopped = true }
    }
}
