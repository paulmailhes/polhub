import Foundation
import Testing
import Transcription
@testable import Pipeline

/// The real launcher, with small scripts standing for `transcriptor-calcul`.
@Suite struct LiveCalculLauncherTests {
    func script(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "calcul-\(UUID().uuidString).sh")
        try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path(percentEncoded: false))
        return url
    }

    func collect(_ process: any CalculProcess) async -> [CalculMessage] {
        var all: [CalculMessage] = []
        for await message in process.messages { all.append(message) }
        return all
    }

    let request = CalculRequest(folder: "/tmp/réunion test", language: "fr")

    @Test func aProcessThatPrintsFinishedEndsCleanly() async throws {
        let url = try script(#"echo '{"progress":{"track":"moi","done":1,"total":2}}'; echo '{"finished":{}}'"#)
        defer { try? FileManager.default.removeItem(at: url) }
        let messages = await collect(try LiveCalculLauncher(executable: url).start(request))
        #expect(messages == [.progress(track: .moi, done: 1, total: 2), .finished], "\(messages)")
    }

    @Test func aProcessThatDiesSilentlyIsAFailure() async throws {
        let url = try script("exit 3")
        defer { try? FileManager.default.removeItem(at: url) }
        let messages = await collect(try LiveCalculLauncher(executable: url).start(request))
        #expect(messages == [.failed("Le calcul s'est arrêté sans finir (code 3).")])
    }

    @Test func stopEndsItWithinASecondAndIsNoFailure() async throws {
        let url = try script("trap '' TERM; sleep 30")
        defer { try? FileManager.default.removeItem(at: url) }
        let process = try LiveCalculLauncher(executable: url).start(request)
        try await Task.sleep(for: .milliseconds(200))
        let began = Date()
        process.stop()
        let messages = await collect(process)
        #expect(Date().timeIntervalSince(began) < 1.8)
        #expect(messages.isEmpty)
    }
}
