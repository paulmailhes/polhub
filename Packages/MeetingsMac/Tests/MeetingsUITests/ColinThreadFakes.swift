import Colin
import Foundation

/// A Claude Code that answers from a script (copied from the probe's tests: a test target cannot import another).
final class FakeSession: ClaudeSession, @unchecked Sendable {
    let events: AsyncStream<ClaudeEvent>
    let pid: Int32 = 4242
    private let continuation: AsyncStream<ClaudeEvent>.Continuation
    private let lock = NSLock()
    private var ended = false
    private var _sent: [String] = []
    private var _stopped = false
    private let onSend: @Sendable (String, Int) -> [ClaudeEvent]
    private let onInterrupt: @Sendable (String) -> [ClaudeEvent]
    private let onClose: @Sendable () -> [ClaudeEvent]
    private let onStop: @Sendable () -> [ClaudeEvent]
    private let endsWhenClosed: Bool
    private let errors: String
    private let stopCode: Int32
    private let stopDelay: Double

    var sent: [String] { lock.withLock { _sent } }
    var stopped: Bool { lock.withLock { _stopped } }
    /// Its process is gone.
    var isOver: Bool { lock.withLock { ended } }

    /// - Parameters:
    ///   - code: the launch answers `first` and ends with this code at once. `nil`: it stays open (a conversation,
    ///     or a Claude Code that never answers).
    ///   - errors: the end of its error output, told as it leaves.
    ///   - stopCode: the code it leaves with once stopped; `stopDelay`: how long it takes to leave.
    ///   - onClose, onStop: what it still writes when its input closes, and when it is stopped.
    init(_ first: [ClaudeEvent] = [], code: Int32? = nil, endsWhenClosed: Bool = true, errors: String = "",
         stopCode: Int32 = 130, stopDelay: Double = 0,
         onSend: @escaping @Sendable (String, Int) -> [ClaudeEvent] = { _, _ in [] },
         onInterrupt: @escaping @Sendable (String) -> [ClaudeEvent] = { _ in [] },
         onClose: @escaping @Sendable () -> [ClaudeEvent] = { [] },
         onStop: @escaping @Sendable () -> [ClaudeEvent] = { [] }) {
        (events, continuation) = AsyncStream.makeStream()
        self.onSend = onSend
        self.onInterrupt = onInterrupt
        self.onClose = onClose
        self.onStop = onStop
        self.endsWhenClosed = endsWhenClosed
        self.errors = errors
        self.stopCode = stopCode
        self.stopDelay = stopDelay
        for event in first { continuation.yield(event) }
        if let code { end(code) }
    }

    func send(_ text: String) {
        let count = lock.withLock { _sent.append(text); return _sent.count }
        for event in onSend(text, count) { continuation.yield(event) }
    }

    func interrupt(_ requestID: String) {
        for event in onInterrupt(requestID) { continuation.yield(event) }
    }

    func closeInput() {
        for event in onClose() { continuation.yield(event) }
        if endsWhenClosed { end(0) }
    }

    func stop() {
        let first = lock.withLock { if _stopped { return false }; _stopped = true; return true }
        guard first else { return }
        for event in onStop() { continuation.yield(event) }
        if stopDelay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + stopDelay) { [self] in end(stopCode) }
        } else {
            end(stopCode)
        }
    }

    private func end(_ code: Int32) {
        let first = lock.withLock { if ended { return false }; ended = true; return true }
        guard first else { return }
        continuation.yield(.exited(code: code, errors: errors))
        continuation.finish()
    }
}

/// Answers each launch from the command it receives, and keeps the commands in order.
final class FakeLauncher: ClaudeLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [ClaudeCommand] = []
    private var sessions: [FakeSession] = []
    private var folders: [URL] = []
    private var files: [Bool] = []
    private let failing: Set<Int>
    private let respond: @Sendable (ClaudeCommand, Int) -> FakeSession
    /// Called as each launch is asked, with its rank, before it starts or fails.
    var onStart: (@Sendable (Int) -> Void)?

    /// `failing`: the launches, by their rank, that cannot start at all.
    init(failing: Set<Int> = [], _ respond: @escaping @Sendable (ClaudeCommand, Int) -> FakeSession) {
        self.failing = failing
        self.respond = respond
    }

    var started: [ClaudeCommand] { lock.withLock { commands } }
    var all: [FakeSession] { lock.withLock { sessions } }
    var directories: [URL] { lock.withLock { folders } }
    /// For each launch: was a file of instructions waiting in its folder?
    var instructions: [Bool] { lock.withLock { files } }

    func start(_ command: ClaudeCommand, binary: URL, directory: URL) throws -> any ClaudeSession {
        let waiting = FileManager.default.fileExists(atPath: directory.appending(path: "CLAUDE.md").path(percentEncoded: false))
        let index = lock.withLock { folders.append(directory); files.append(waiting); return commands.count }
        onStart?(index)
        if failing.contains(index) {
            lock.withLock { commands.append(command) }
            throw CocoaError(.fileNoSuchFile)
        }
        let session = respond(command, index)
        lock.withLock { commands.append(command); sessions.append(session) }
        return session
    }
}
