import Foundation
import Testing
@testable import Colin

/// The real launcher, with small scripts standing for Claude Code.
@Suite struct ClaudeProcessTests {
    let folder: URL
    let oneShot = ClaudeCommand(model: "haiku", systemPrompt: "x", prompt: "y")
    let streaming = ClaudeCommand(model: "opus", systemPrompt: "x")

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "colin-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func script(_ body: String) throws -> URL {
        let url = folder.appending(path: "claude-\(UUID().uuidString).sh")
        try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path(percentEncoded: false))
        return url
    }

    func collect(_ session: any ClaudeSession) async -> [ClaudeEvent] {
        var all: [ClaudeEvent] = []
        for await event in session.events { all.append(event) }
        return all
    }

    func start(_ body: String, _ command: ClaudeCommand, environment: [String: String] = ["PATH": "/usr/bin:/bin"]) throws -> any ClaudeSession {
        try LiveClaudeLauncher(environment: environment).start(command, binary: try script(body), directory: folder)
    }

    var note: URL { folder.appending(path: "note.txt") }
    func noted() -> String { (try? String(contentsOf: note, encoding: .utf8)) ?? "" }

    /// A file a script writes once it listens: under load, a shell may take long to get there, and a signal sent
    /// before its `trap` would kill it for another reason than the one the test names.
    func signal() -> URL { folder.appending(path: "pret-\(UUID().uuidString).txt") }
    func says(_ file: URL) -> String { #"echo pret > "\#(file.path(percentEncoded: false))""# }
    func wait(for file: URL) async throws {
        for _ in 0..<500 where !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) { try await Task.sleep(for: .milliseconds(10)) }
        try #require(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    /// Raised from another thread.
    final class Raised: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isRaised: Bool { lock.withLock { value } }
        func raise() { lock.withLock { value = true } }
    }

    @Test func aOneShotProcessGivesItsEventsThenItsExit() async throws {
        let session = try start(#"echo '{"type":"result","subtype":"success","result":"ok"}'; echo "bruit" >&2; exit 0"#, oneShot)
        let events = await collect(session)
        #expect(events == [.result(ClaudeResult(subtype: "success", text: "ok")), .exited(code: 0, errors: "bruit\n")], "\(events)")
    }

    @Test func aLineCutInTwoWritesIsOneEvent() async throws {
        let session = try start(#"printf '{"type":"result","subtype":"suc'; sleep 0.2; printf 'cess","result":"ok"}\n'"#, oneShot)
        let events = await collect(session)
        #expect(events == [.result(ClaudeResult(subtype: "success", text: "ok")), .exited(code: 0, errors: "")], "\(events)")
    }

    @Test func aLastLineWithoutItsEndStillCounts() async throws {
        let session = try start(#"printf '{"type":"result","subtype":"success"}'; exit 2"#, oneShot)
        let events = await collect(session)
        #expect(events == [.result(ClaudeResult(subtype: "success")), .exited(code: 2, errors: "")], "\(events)")
    }

    @Test func whatIsSentReachesTheStandardInput() async throws {
        let session = try start(#"while IFS= read -r line; do printf '%s\n' "$line" >> "\#(note.path(percentEncoded: false))"; done"#, streaming)
        session.send("Bonjour")
        session.interrupt("r1")
        session.closeInput()
        let events = await collect(session)
        #expect(events == [.exited(code: 0, errors: "")], "\(events)")
        #expect(noted() == ClaudeCommand.userLine("Bonjour") + "\n" + ClaudeCommand.interruptLine("r1") + "\n")
    }

    @Test func theArgumentsAndTheEnvironmentAreTheCommands() async throws {
        var command = oneShot
        command.configDirectory = URL(fileURLWithPath: "/tmp/compte")
        let session = try start(#"printf '%s|%s|%s|%s' "$1" "$2" "$CLAUDE_CONFIG_DIR" "$ANTHROPIC_API_KEY" > "\#(note.path(percentEncoded: false))""#, command,
                                environment: ["ANTHROPIC_API_KEY": "sk-x", "PATH": "/usr/bin:/bin"])
        _ = await collect(session)
        #expect(noted() == "-p|y|/tmp/compte|")
    }

    @Test func theWorkingDirectoryIsTheOneGiven() async throws {
        let session = try start(#"/bin/pwd -P > "\#(note.path(percentEncoded: false))""#, oneShot)
        _ = await collect(session)
        // `pwd -P` says « /private/var/… » where the folder's own path says « /var/… »: the same place.
        let said = noted().trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(said.hasSuffix(folder.path(percentEncoded: false).trimmingSuffix("/")), "\(said)")
    }

    @Test func stopEndsItWithinSeconds() async throws {
        // Deaf to the request: it is killed a second later.
        let ready = signal()
        let session = try start("trap '' INT TERM; \(says(ready)); exec sleep 30", oneShot)
        try await wait(for: ready)
        let began = Date()
        session.stop()
        let events = await collect(session)
        #expect(Date().timeIntervalSince(began) < 3)
        #expect(Date().timeIntervalSince(began) > 0.8)
        #expect(events.count == 1)
        guard case .exited(let code, _) = events.last else { Issue.record("\(events)"); return }
        #expect(code == SIGKILL)
    }

    @Test func aChildHoldingTheOutputDoesNotHoldTheEnd() async throws {
        // The shell dies, its `sleep` keeps the pipe open: the end is told all the same.
        let ready = signal()
        let session = try start("trap '' INT TERM; \(says(ready)); sleep 30", oneShot)
        try await wait(for: ready)
        let began = Date()
        session.stop()
        let events = await collect(session)
        #expect(Date().timeIntervalSince(began) < 3)
        guard case .exited = events.last else { Issue.record("\(events)"); return }
    }

    @Test func writingToAProcessThatHasEndedDoesNotKillTheApp() async throws {
        let session = try start("exit 0", streaming)
        let events = await collect(session)
        #expect(events == [.exited(code: 0, errors: "")])
        session.send("trop tard")
        session.interrupt("r1")
        session.closeInput()
        session.stop()
    }

    @Test func theProcessHasAnIdentifier() async throws {
        let session = try start("exit 0", oneShot)
        #expect(session.pid > 0)
        _ = await collect(session)
    }

    @Test func aShortToolGivesItsCodeAndItsOutput() async throws {
        let version = try script("echo '2.1.304 (Claude Code)'; exit 0")
        let answer = await ClaudeTool.run(version, arguments: ["--version"], environment: ["PATH": "/usr/bin:/bin"], timeout: 5)
        #expect(answer?.code == 0)
        #expect(answer?.output == "2.1.304 (Claude Code)\n")
        let failing = try script("echo non; exit 3")
        #expect(await ClaudeTool.run(failing, arguments: [], environment: [:], timeout: 5)?.code == 3)
    }

    @Test func aToolThatNeverEndsIsGivenUp() async throws {
        let slow = try script("exec sleep 30")
        let began = Date()
        let answer = await ClaudeTool.run(slow, arguments: [], environment: ["PATH": "/usr/bin:/bin"], timeout: 0.3)
        #expect(answer == nil)
        #expect(Date().timeIntervalSince(began) < 3)
    }

    @Test func aToolWhoseChildKeepsTheOutputStillAnswers() async throws {
        // The tool ends, a child of its own keeps its output open: what it printed is given without waiting for the child.
        let tool = try script("sleep 8 &\necho fait")
        let began = Date()
        let answer = await ClaudeTool.run(tool, arguments: [], environment: ["PATH": "/usr/bin:/bin"], timeout: 5)
        #expect(answer?.code == 0)
        #expect(answer?.output == "fait\n")
        #expect(Date().timeIntervalSince(began) < 3)
    }

    @Test func aBinaryThatDoesNotExistCannotStart() {
        #expect(throws: (any Error).self) {
            _ = try LiveClaudeLauncher(environment: [:]).start(oneShot, binary: URL(fileURLWithPath: "/nulle/part/claude"), directory: folder)
        }
    }

    @Test func stopAsksBeforeItKills() async throws {
        // The process hears the request to stop, says so and leaves by itself: it was asked, not killed.
        // (Claude Code 2.1.304 leaves within 0.7 s of SIGINT, with its turn ended in error: measured on 17/11.)
        let ready = signal()
        let heard = #"echo entendu > "\#(note.path(percentEncoded: false))""#
        let session = try start("trap '\(heard); kill $child 2>/dev/null; exit 0' INT; sleep 30 & child=$!; \(says(ready)); wait", oneShot)
        // The script says when it listens: under load, a shell may take long to get there.
        try await wait(for: ready)
        let began = Date()
        session.stop()
        let events = await collect(session)
        #expect(Date().timeIntervalSince(began) < 2)
        #expect(noted() == "entendu\n")
        guard case .exited(let code, _) = events.last else { Issue.record("\(events)"); return }
        #expect(code == 0)
    }

    @Test func everyProcessStillRunningIsStoppedWhenTheAppGoes() async throws {
        let processes = ClaudeProcesses()
        let launcher = LiveClaudeLauncher(environment: ["PATH": "/usr/bin:/bin"], processes: processes)
        let first = signal(), second = signal()
        let heard = #"echo entendu > "\#(note.path(percentEncoded: false))""#
        let obedient = try launcher.start(oneShot, binary: try script("trap '\(heard); kill $child 2>/dev/null; exit 0' INT; sleep 30 & child=$!; \(says(first)); wait"),
                                          directory: folder)
        let deaf = try launcher.start(oneShot, binary: try script("trap '' INT TERM; \(says(second)); exec sleep 30"), directory: folder)
        try await wait(for: first)
        try await wait(for: second)
        #expect(processes.count == 2)
        let began = Date()
        // Two seconds for the one that listens: under load, its shell may take long to run its trap.
        processes.stopAll(within: 2)
        // Asked, waited for, then killed: nothing is left when this returns.
        #expect(Date().timeIntervalSince(began) < 5)
        #expect(kill(obedient.pid, 0) != 0)
        #expect(kill(deaf.pid, 0) != 0)
        // The one that listens was asked, and left by itself; the deaf one had to be killed.
        #expect(noted() == "entendu\n")
        guard case .exited(let asked, _) = await collect(obedient).last, case .exited(let killed, _) = await collect(deaf).last else {
            Issue.record("sans fin")
            return
        }
        #expect(asked == 0)
        #expect(killed == SIGKILL)
        #expect(processes.count == 0)
        // Once the app is going, nothing new is launched.
        let late = try script("exit 0")
        #expect(throws: (any Error).self) { _ = try launcher.start(oneShot, binary: late, directory: folder) }
    }

    @Test func stopDoesNotWaitForAWriteThatIsStuck() async throws {
        // A process that reads nothing: a long message fills the pipe, and its write waits. Stopping does not wait
        // for it: the signal goes first, and the write gives up once the process is gone.
        let ready = signal()
        let session = try start("trap '' INT; \(says(ready)); exec sleep 30", streaming)
        try await wait(for: ready)
        let written = Raised()
        Thread.detachNewThread {
            session.send(String(repeating: "x", count: 1_000_000))
            written.raise()
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(!written.isRaised)
        let began = Date()
        session.stop()
        #expect(Date().timeIntervalSince(began) < 0.5)
        let events = await collect(session)
        #expect(Date().timeIntervalSince(began) < 3)
        guard case .exited = events.last else { Issue.record("\(events)"); return }
        for _ in 0..<300 where !written.isRaised { try await Task.sleep(for: .milliseconds(10)) }
        #expect(written.isRaised)
    }

    @Test func aProcessThatEndedLeavesTheList() async throws {
        let processes = ClaudeProcesses()
        let session = try LiveClaudeLauncher(environment: [:], processes: processes).start(oneShot, binary: try script("exit 0"), directory: folder)
        _ = await collect(session)
        #expect(processes.count == 0)
    }

    @Test func aCancelledToolIsKilledAtOnce() async throws {
        let slow = try script("exec sleep 30")
        let processes = ClaudeProcesses()
        let task = Task { await ClaudeTool.run(slow, arguments: [], environment: ["PATH": "/usr/bin:/bin"], timeout: 20, processes: processes) }
        for _ in 0..<200 where processes.count == 0 { try await Task.sleep(for: .milliseconds(10)) }
        let began = Date()
        task.cancel()
        let answer = await task.value
        #expect(answer == nil)
        #expect(Date().timeIntervalSince(began) < 2)
        #expect(processes.count == 0)
    }

    @Test func aToolCancelledBeforeItsStartNeverRuns() async throws {
        let witness = folder.appending(path: "temoin-\(UUID().uuidString).txt")
        let tool = try script(#"echo lance > "\#(witness.path(percentEncoded: false))"; exec sleep 5"#)
        let processes = ClaudeProcesses()
        let began = Date()
        let answered = await Task { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            return await ClaudeTool.run(tool, arguments: [], environment: ["PATH": "/usr/bin:/bin"], timeout: 20, processes: processes) != nil
        }.value
        #expect(!answered)
        #expect(Date().timeIntervalSince(began) < 1)
        try await Task.sleep(for: .milliseconds(200))
        #expect(!FileManager.default.fileExists(atPath: witness.path(percentEncoded: false)))
        #expect(processes.count == 0)
    }

    @Test func aToolThatDoesNotExistIsNil() async {
        #expect(await ClaudeTool.run(URL(fileURLWithPath: "/nulle/part/claude"), arguments: [], environment: [:], timeout: 1) == nil)
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String { hasSuffix(suffix) && count > 1 ? String(dropLast(suffix.count)) : self }
}
