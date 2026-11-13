import Foundation
import Transcription

/// A running `polhub-calcul`: its messages, until it ends; `stop()` ends it at once.
public protocol CalculProcess: Sendable {
    var messages: AsyncStream<CalculMessage> { get }
    func stop()
}

public protocol CalculLaunching: Sendable {
    func start(_ request: CalculRequest) throws -> any CalculProcess
}

/// Launches the `polhub-calcul` embedded in the app, at a low priority so the Mac stays responsive.
public struct LiveCalculLauncher: CalculLaunching {
    public let executable: URL

    public init(executable: URL) {
        self.executable = executable
    }

    public func start(_ request: CalculRequest) throws -> any CalculProcess {
        try LiveCalculProcess(executable: executable, request: request)
    }
}

final class LiveCalculProcess: CalculProcess, @unchecked Sendable {
    let messages: AsyncStream<CalculMessage>
    private let continuation: AsyncStream<CalculMessage>.Continuation
    private let process = Process()
    private let lock = NSLock()
    private var buffer = Data()
    private var sawEnd = false
    private var stopped = false

    init(executable: URL, request: CalculRequest) throws {
        (messages, continuation) = AsyncStream.makeStream()
        process.executableURL = executable
        process.arguments = [String(decoding: try JSONEncoder().encode(request), as: UTF8.self)]
        process.qualityOfService = .utility
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        // A blocking read on a thread of its own: `readabilityHandler` lost short outputs on this Mac.
        DispatchQueue.global(qos: .utility).async { [self] in
            let handle = output.fileHandleForReading
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                receive(data)
            }
            process.waitUntilExit()
            ended(status: process.terminationStatus)
        }
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        let lines: [Data] = lock.withLock {
            buffer.append(data)
            var lines: [Data] = []
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                lines.append(buffer[buffer.startIndex..<newline])
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            return lines
        }
        for line in lines {
            guard let message = try? JSONDecoder().decode(CalculMessage.self, from: line) else { continue }
            if case .finished = message { lock.withLock { sawEnd = true } }
            if case .failed = message { lock.withLock { sawEnd = true } }
            continuation.yield(message)
        }
    }

    /// A process that died without saying why is a failure, unless it was asked to stop.
    private func ended(status: Int32) {
        let (sawEnd, stopped) = lock.withLock { (self.sawEnd, self.stopped) }
        if !sawEnd && !stopped {
            continuation.yield(.failed("Le calcul s'est arrêté sans finir (code \(status))."))
        }
        continuation.finish()
    }

    /// The stream ends at once: nothing that comes after a stop counts.
    func stop() {
        lock.withLock { stopped = true }
        continuation.finish()
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [process] in
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }
}
