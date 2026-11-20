import Foundation

/// Runs an AppleScript in `/usr/bin/osascript`, off this app's main thread. A reading of Dia's tabs takes
/// about 0.3 s (phase 0, measure 4): run on the main thread, it would freeze the menu bar and the pop-up.
/// macOS attributes the Apple Events of a child process to the app that started it, so the "Automation of
/// Dia" permission already granted to hub applies (to be measured: étape 1, task 1).
public enum OsascriptRunner {
    public static func run(_ source: String, timeout: Double = 3) async -> Result<String, ScriptFailure> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runBlocking(source, timeout: timeout))
            }
        }
    }

    /// The error number osascript prints last, as `(-1743)`; -1 when there is none.
    public static func failure(stderr: String, status: Int32) -> ScriptFailure {
        let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = message.matches(of: /\((-?\d+)\)/).last.flatMap { Int($0.output.1) } ?? -1
        return ScriptFailure(code: code, message: message.isEmpty ? "osascript a échoué (code \(status))" : message)
    }

    private final class Collected: @unchecked Sendable {
        var data = Data()
    }

    static func runBlocking(_ source: String, timeout: Double) -> Result<String, ScriptFailure> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-"]
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            return .failure(ScriptFailure(code: -1, message: "osascript ne démarre pas : \(error.localizedDescription)"))
        }
        // osascript may already be gone: writing must neither raise nor kill the app (SIGPIPE is ignored).
        try? input.fileHandleForWriting.write(contentsOf: Data(source.utf8))
        try? input.fileHandleForWriting.close()

        // Both pipes are drained at once: a full pipe would block osascript for ever.
        let out = Collected(), err = Collected()
        let group = DispatchGroup()
        for (pipe, box) in [(output, out), (errors, err)] {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                box.data = pipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
        }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            group.wait()
            return .failure(ScriptFailure(code: -1712, message: "Dia n'a pas répondu en \(timeout) s"))   // errAETimeout
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return .failure(failure(stderr: String(decoding: err.data, as: UTF8.self), status: process.terminationStatus))
        }
        var text = String(decoding: out.data, as: UTF8.self)
        if text.hasSuffix("\n") { text.removeLast() }
        return .success(text)
    }
}
