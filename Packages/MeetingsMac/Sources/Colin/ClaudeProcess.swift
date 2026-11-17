import Foundation

/// A running Claude Code: what it says, until it ends, and what can be said to it.
public protocol ClaudeSession: Sendable {
    /// Every event in order; the last one is `.exited`, then the stream ends.
    var events: AsyncStream<ClaudeEvent> { get }
    var pid: Int32 { get }
    /// A message of the user (a conversation only: a one-shot launch has no input).
    func send(_ text: String)
    /// Stops the turn under way; the conversation stays open.
    func interrupt(_ requestID: String)
    /// Nothing more will be said: the process ends once its turn is over.
    func closeInput()
    /// Ends the process: asked first, killed a second later.
    func stop()
}

public protocol ClaudeLaunching: Sendable {
    func start(_ command: ClaudeCommand, binary: URL, directory: URL) throws -> any ClaudeSession
}

public enum ClaudeProcessError: Error {
    /// The app is going: nothing new is launched.
    case closing
}

/// Every Claude Code that Polhub launched and that still runs. When the app goes, none is left behind: `stopAll` asks
/// each to stop, waits a little, and kills what is left.
public final class ClaudeProcesses: @unchecked Sendable {
    public static let shared = ClaudeProcesses()

    private let lock = NSLock()
    private var running: [Int32: Process] = [:]
    private var closing = false

    public init() {}

    public var count: Int { lock.withLock { running.count } }

    /// Starts the process and keeps it until it ends. Throws when it cannot start, or once the app is going.
    func launch(_ process: Process) throws {
        try lock.withLock {
            guard !closing else { throw ClaudeProcessError.closing }
            try process.run()
            running[process.processIdentifier] = process
        }
    }

    func ended(_ pid: Int32) {
        lock.withLock { running[pid] = nil }
    }

    /// The app is going. Every process is asked to stop (Claude Code 2.1.304 leaves within 0.7 s of it, its turn
    /// ended in error: measured on 17/11), waited for `seconds` at most, then killed; nothing is launched after.
    /// It does not return before they are gone.
    public func stopAll(within seconds: Double = 1.5) {
        let processes = lock.withLock { () -> [Process] in
            closing = true
            return Array(running.values)
        }
        for process in processes where process.isRunning { kill(process.processIdentifier, SIGINT) }
        Self.wait(for: processes, seconds: seconds)
        for process in processes where process.isRunning { kill(process.processIdentifier, SIGKILL) }
        // Killed: the system needs an instant to say so.
        Self.wait(for: processes, seconds: 0.5)
    }

    private static func wait(for processes: [Process], seconds: Double) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline, processes.contains(where: \.isRunning) { usleep(20_000) }
    }
}

/// Launches the Claude Code of this Mac, at a low priority, with the command's own environment.
public struct LiveClaudeLauncher: ClaudeLaunching {
    private let environment: [String: String]
    private let processes: ClaudeProcesses

    /// `environment`: the app's, of which the command keeps only what it lets through.
    public init(environment: [String: String] = ProcessInfo.processInfo.environment, processes: ClaudeProcesses = .shared) {
        self.environment = environment
        self.processes = processes
    }

    public func start(_ command: ClaudeCommand, binary: URL, directory: URL) throws -> any ClaudeSession {
        try LiveClaudeSession(command: command, binary: binary, directory: directory, environment: command.environment(from: environment),
                              processes: processes)
    }
}

final class LiveClaudeSession: ClaudeSession, @unchecked Sendable {
    let events: AsyncStream<ClaudeEvent>
    private let continuation: AsyncStream<ClaudeEvent>.Continuation
    private let process = Process()
    private let processes: ClaudeProcesses
    private let input: FileHandle?
    private let readers = DispatchGroup()
    private let lock = NSLock()
    private var buffer = Data()
    private var errors = Data()
    private let inputLock = NSLock()
    private var inputOpen: Bool

    /// What is kept of the error output: its end.
    private static let errorBytes = 600

    var pid: Int32 { process.processIdentifier }

    init(command: ClaudeCommand, binary: URL, directory: URL, environment: [String: String], processes: ClaudeProcesses) throws {
        (events, continuation) = AsyncStream.makeStream()
        self.processes = processes
        let output = Pipe(), errorOutput = Pipe()
        if command.prompt == nil {
            let pipe = Pipe()
            // A line written after the process ended fails quietly: it must never end the app (SIGPIPE).
            _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
            process.standardInput = pipe
            input = pipe.fileHandleForWriting
        } else {
            process.standardInput = FileHandle.nullDevice
            input = nil
        }
        inputOpen = input != nil
        process.executableURL = binary
        process.arguments = command.arguments
        process.environment = environment
        process.currentDirectoryURL = directory
        process.qualityOfService = .utility
        process.standardOutput = output
        process.standardError = errorOutput
        process.terminationHandler = { [self] process in ended(process) }
        // Counted before the launch: a process that ends at once still waits for what it wrote to be read.
        readers.enter()
        readers.enter()
        do {
            try processes.launch(process)
        } catch {
            readers.leave()
            readers.leave()
            process.terminationHandler = nil
            throw error
        }
        // A blocking read on a thread of its own: `readabilityHandler` lost short outputs on this Mac (CalculLauncher).
        read(output.fileHandleForReading) { [self] in receive($0) }
        read(errorOutput.fileHandleForReading) { [self] in keep($0) }
    }

    private func read(_ handle: FileHandle, _ take: @escaping @Sendable (Data) -> Void) {
        DispatchQueue.global(qos: .utility).async { [readers] in
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                take(data)
            }
            readers.leave()
        }
    }

    private func receive(_ data: Data) {
        let lines: [Data] = lock.withLock {
            buffer.append(data)
            var lines: [Data] = []
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                lines.append(Data(buffer[buffer.startIndex..<newline]))
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            return lines
        }
        for line in lines {
            if let event = ClaudeStream.decode(line) { continuation.yield(event) }
        }
    }

    private func keep(_ data: Data) {
        lock.withLock {
            errors.append(data)
            if errors.count > Self.errorBytes { errors = Data(errors.suffix(Self.errorBytes)) }
        }
    }

    /// The process is gone. What it wrote is read first; a child of its own that keeps the pipes open does not
    /// hold the end back for more than half a second.
    private func ended(_ process: Process) {
        processes.ended(process.processIdentifier)
        _ = readers.wait(timeout: .now() + 0.5)
        let (rest, text) = lock.withLock {
            let rest = buffer
            buffer = Data()
            return (rest, String(decoding: errors, as: UTF8.self))
        }
        if !rest.isEmpty, let event = ClaudeStream.decode(rest) { continuation.yield(event) }
        continuation.yield(.exited(code: process.terminationStatus, errors: text))
        continuation.finish()
        process.terminationHandler = nil
    }

    func send(_ text: String) { write(ClaudeCommand.userLine(text)) }

    func interrupt(_ requestID: String) { write(ClaudeCommand.interruptLine(requestID)) }

    private func write(_ line: String) {
        inputLock.withLock {
            guard inputOpen, let input else { return }
            // A process already gone: nothing to say to it.
            try? input.write(contentsOf: Data((line + "\n").utf8))
        }
    }

    func closeInput() {
        inputLock.withLock { closeNow() }
    }

    private func closeNow() {
        guard inputOpen, let input else { return }
        inputOpen = false
        try? input.close()
    }

    func stop() {
        if process.isRunning {
            let pid = process.processIdentifier
            // SIGINT lets Claude Code end its turn properly (gone within 0.7 s, measured on 17/11); SIGTERM would
            // leave the turn unfinished.
            kill(pid, SIGINT)
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [process] in
                if process.isRunning { kill(pid, SIGKILL) }
            }
        }
        // The input closes too, unless a write is still waiting on a process that reads nothing: the signal ends
        // that one, and stopping never waits for it.
        if inputLock.try() {
            closeNow()
            inputLock.unlock()
        }
    }
}

/// A short program whose whole output is wanted: `claude --version`, `claude auth status --json`, `ps`.
public enum ClaudeTool {
    /// Its code and what it printed; `nil` when it could not start, did not end within `timeout`, or when the task
    /// that asked was cancelled (it is then killed at once).
    public static func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: TimeInterval,
                           processes: ClaudeProcesses = .shared) async -> (code: Int32, output: String)? {
        let short = Short()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(returning: short.run(executable, arguments: arguments, environment: environment, timeout: timeout, processes: processes))
                }
            }
        } onCancel: {
            short.giveUp()
        }
    }

    private final class Short: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var gaveUp = false

        /// The delay has passed, or nobody waits for the answer any more: the program is killed.
        func giveUp() {
            lock.withLock {
                gaveUp = true
                if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }

        func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: TimeInterval,
                 processes: ClaudeProcesses) -> (code: Int32, output: String)? {
            let process = Process()
            let output = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.environment = environment
            process.qualityOfService = .utility
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            let started: Bool = lock.withLock {
                guard !gaveUp, (try? processes.launch(process)) != nil else { return false }
                self.process = process
                return true
            }
            guard started else { return nil }
            let deadline = DispatchWorkItem { [self] in giveUp() }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
            // Read on a thread of its own: the end is the program's, not its output's. A child that keeps the output
            // open does not hold the answer for more than half a second.
            let printed = Printed()
            let handle = output.fileHandleForReading
            DispatchQueue.global(qos: .utility).async {
                while true {
                    let data = handle.availableData
                    if data.isEmpty { break }
                    printed.add(data)
                }
                printed.finish()
            }
            process.waitUntilExit()
            deadline.cancel()
            processes.ended(process.processIdentifier)
            printed.wait(0.5)
            return lock.withLock { gaveUp } ? nil : (process.terminationStatus, String(decoding: printed.all, as: UTF8.self))
        }
    }

    /// What a program printed, as it comes.
    private final class Printed: @unchecked Sendable {
        private let lock = NSLock()
        private let ended = DispatchSemaphore(value: 0)
        private var data = Data()
        var all: Data { lock.withLock { data } }
        func add(_ more: Data) { lock.withLock { data.append(more) } }
        func finish() { ended.signal() }
        func wait(_ seconds: Double) { _ = ended.wait(timeout: .now() + seconds) }
    }
}
