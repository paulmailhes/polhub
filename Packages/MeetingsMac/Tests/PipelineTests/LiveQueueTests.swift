import Domain
import Foundation
import Persistence
import Recording
import Testing
@testable import Pipeline

/// The whole chain on a copy of a real meeting folder: the queue, the `transcriptor-calcul` of the app,
/// the real models, the import. Not part of `make check`:
/// `TRANSCRIPTOR_LIVE_MEETING=<dossier> TRANSCRIPTOR_CALCUL=<outil> swift test --filter LiveQueueTests`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TRANSCRIPTOR_LIVE_MEETING"] != nil))
struct LiveQueueTests {
    @Test func aRealMeetingIsTranscribedEndToEnd() async throws {
        let environment = ProcessInfo.processInfo.environment
        let source = URL(fileURLWithPath: try #require(environment["TRANSCRIPTOR_LIVE_MEETING"]), isDirectory: true)
        let helper = URL(fileURLWithPath: try #require(environment["TRANSCRIPTOR_CALCUL"]))
        let file = try MeetingFile.decoder.decode(MeetingFile.self, from: Data(contentsOf: source.appending(path: "meeting.json")))

        let root = FileManager.default.temporaryDirectory.appending(path: "chaîne \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root, logs: root.appending(path: "logs"))
        try FileManager.default.createDirectory(at: paths.meetings, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: paths.meetingFolder(file.id))

        let database = try AppDatabase.inMemory()
        let meetings = MeetingStore(database)
        let transcripts = TranscriptStore(database)
        try meetings.save(MeetingRow(id: file.id, createdAt: file.startedAt, status: .ended, source: .dia, candidateKey: "t/live",
                                     title: file.title, startedAt: file.startedAt, endedAt: file.endedAt))
        let queue = TranscriptionQueue(meetings: meetings, transcripts: transcripts, paths: paths, launcher: LiveCalculLauncher(executable: helper))
        let began = Date()
        await queue.wake()
        var job: JobRow?
        for _ in 0..<600 {
            job = try transcripts.job(for: file.id)
            if job?.state == .done || job?.state == .failed { break }
            try await Task.sleep(for: .milliseconds(500))
        }
        let lines = try transcripts.utterances(meetingID: file.id)
        let folder = paths.meetingFolder(file.id)
        let archive = try #require(TrackRenderer.prepared(in: folder))
        print("chaîne : \(String(format: "%.1f", Date().timeIntervalSince(began))) s, état \(job?.state.rawValue ?? "?"), \(lines.count) répliques, à vérifier \(job?.doubtful ?? false), archive \(String(format: "%.1f", archive.seconds)) s, moi \(archive.moi != nil), brut effacé \(!FileManager.default.fileExists(atPath: folder.appending(path: "audio").path(percentEncoded: false)))")
        for line in lines.prefix(3) { print("  [\(line.startMs / 1_000) s] \(line.speaker.label) : \(line.text.prefix(60))") }
        #expect(job?.state == .done, "\(job?.error ?? "")")
        #expect(!lines.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "audio").path(percentEncoded: false)))
    }
}
