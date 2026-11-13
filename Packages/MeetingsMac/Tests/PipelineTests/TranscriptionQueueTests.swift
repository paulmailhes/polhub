import AVFoundation
import Domain
import Foundation
import Persistence
import Recording
import Testing
import Transcription
@testable import Pipeline

/// A process whose messages the test writes; it may write result lines first, as `transcriptor-calcul` does.
final class FakeCalcul: CalculProcess, @unchecked Sendable {
    let messages: AsyncStream<CalculMessage>
    private let continuation: AsyncStream<CalculMessage>.Continuation
    private let lock = NSLock()
    private var stops = 0
    var stopCount: Int { lock.withLock { stops } }

    init() {
        (messages, continuation) = AsyncStream.makeStream()
    }

    func send(_ message: CalculMessage) { continuation.yield(message) }
    func end() { continuation.finish() }

    func stop() {
        lock.withLock { stops += 1 }
        continuation.finish()
    }
}

final class FakeLauncher: CalculLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private var started: [(CalculRequest, FakeCalcul)] = []
    var requests: [CalculRequest] { lock.withLock { started.map(\.0) } }
    var processes: [FakeCalcul] { lock.withLock { started.map(\.1) } }

    func start(_ request: CalculRequest) throws -> any CalculProcess {
        let process = FakeCalcul()
        lock.withLock { started.append((request, process)) }
        return process
    }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var now: Date {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

/// Waits until `condition` holds, two seconds at most.
func eventually(_ condition: @Sendable () async throws -> Bool) async rethrows -> Bool {
    for _ in 0..<200 {
        if try await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}

@Suite struct TranscriptionQueueTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)
    let paths: AppPaths
    let meetings: MeetingStore
    let transcripts: TranscriptStore
    let launcher = FakeLauncher()

    init() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "file d'attente \(UUID().uuidString)", directoryHint: .isDirectory)
        paths = AppPaths(root: root, logs: root.appending(path: "logs"))
        let database = try AppDatabase.inMemory()
        meetings = MeetingStore(database)
        transcripts = TranscriptStore(database)
    }

    func queue() -> TranscriptionQueue {
        TranscriptionQueue(meetings: meetings, transcripts: transcripts, paths: paths, launcher: launcher, now: { [now] in now })
    }

    /// An ended meeting with its `meeting.json` and its archive marker.
    func endedMeeting() throws -> MeetingRow {
        let row = MeetingRow(createdAt: now, status: .ended, source: .dia, candidateKey: "t/abc", title: "Point hebdo", startedAt: now)
        try meetings.save(row)
        let folder = paths.meetingFolder(row.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var file = MeetingFile(id: row.id, title: row.title, meetCode: nil, mode: .dia, startedAt: now, endedAt: now, endReason: "tabClosed")
        file.endNanos = 60_000_000_000
        try MeetingFile.encoder.encode(file).write(to: folder.appending(path: "meeting.json"))
        return row
    }

    /// What `transcriptor-calcul` would have written for one chunk.
    func writeResult(_ row: MeetingRow, track: Speaker, index: Int, text: String) throws {
        let result = ChunkResult(track: track, chunk: Chunk(index: index, start: Double(index) * 10, end: Double(index) * 10 + 5), segments: [
            EngineSegment(start: Double(index) * 10 + 1, end: Double(index) * 10 + 3, text: text, avgLogprob: -0.2, compressionRatio: 1.1, noSpeechProb: 0.1),
        ])
        try ChunkResultFile.append(result, to: paths.meetingFolder(row.id).appending(path: "transcription/\(track.rawValue).jsonl"))
    }

    @Test func anEndedMeetingIsQueuedAndTranscribed() async throws {
        let row = try endedMeeting()
        let queue = queue()
        await queue.wake()
        #expect(await eventually { launcher.requests.count == 1 })
        #expect(launcher.requests.first == CalculRequest(folder: paths.meetingFolder(row.id).path(percentEncoded: false), language: "fr"))
        #expect(try transcripts.job(for: row.id)?.state == .running)

        try writeResult(row, track: .autres, index: 0, text: "Bonjour à tous.")
        try writeResult(row, track: .moi, index: 1, text: "Salut.")
        let process = try #require(launcher.processes.first)
        process.send(.progress(track: .autres, done: 1, total: 1))
        process.send(.finished)
        process.end()
        #expect(try await eventually { try transcripts.job(for: row.id)?.state == .done })
        #expect(try transcripts.utterances(meetingID: row.id).map(\.text) == ["Bonjour à tous.", "Salut."])
        #expect(try meetings.meeting(id: row.id)?.transcribedAt != nil)
    }

    @Test func aMeetStartingStopsTheCalculAndItResumesAfter() async throws {
        let row = try endedMeeting()
        let queue = queue()
        await queue.wake()
        #expect(await eventually { launcher.requests.count == 1 })
        await queue.meetingActivity(true)
        let first = try #require(launcher.processes.first)
        #expect(first.stopCount == 1)
        #expect(try await eventually { try transcripts.job(for: row.id)?.state == .queued })
        #expect(try transcripts.job(for: row.id)?.attempts == 0)

        await queue.wake()
        #expect(launcher.requests.count == 1)   // nothing starts while a meeting is active
        await queue.meetingActivity(false)
        #expect(await eventually { launcher.requests.count == 2 })
        #expect(launcher.requests[0] == launcher.requests[1])
    }

    // Mises à jour : l'app ne s'installe pas pendant une transcription.
    @Test func theQueueSaysWhenItIsComputing() async throws {
        _ = try endedMeeting()
        let queue = queue()
        #expect(await !queue.isRunning)
        await queue.wake()
        #expect(await eventually { launcher.requests.count == 1 })
        #expect(await queue.isRunning)
        let process = try #require(launcher.processes.first)
        process.send(.failed("arrêt"))
        process.end()
        #expect(await eventually { await !queue.isRunning || launcher.requests.count > 1 })
    }

    @Test func nothingStartsWhileAMeetingIsActive() async throws {
        _ = try endedMeeting()
        let queue = queue()
        await queue.meetingActivity(true)
        await queue.wake()
        try await Task.sleep(for: .milliseconds(100))
        #expect(launcher.requests.isEmpty)
    }

    // Revue finale, Important 5 : au lancement, l'app ne sait pas encore si une réunion reprend.
    @Test func nothingStartsDuringTheLaunchHold() async throws {
        _ = try endedMeeting()
        let clock = TestClock(now)
        let queue = TranscriptionQueue(meetings: meetings, transcripts: transcripts, paths: paths, launcher: launcher, now: { clock.now })
        await queue.start(holdSeconds: 30)
        await queue.wake()
        await queue.meetingActivity(false)
        try await Task.sleep(for: .milliseconds(100))
        #expect(launcher.requests.isEmpty)
        clock.now = now.addingTimeInterval(31)
        await queue.wake()
        #expect(await eventually { launcher.requests.count == 1 })
    }

    // Revue finale, mineur 13 regradé : une réunion mise à la Corbeille n'est plus transcrite.
    @Test func aDeletedMeetingIsNeverTranscribed() async throws {
        let row = try endedMeeting()
        let queue = queue()
        await queue.wake()
        #expect(await eventually { launcher.requests.count == 1 })
        try meetings.softDelete(id: row.id, at: now)
        await queue.forget(meetingID: row.id)
        #expect(launcher.processes.first?.stopCount == 1)
        await queue.wake()
        try await Task.sleep(for: .milliseconds(100))
        #expect(launcher.requests.count == 1)
    }

    @Test func aFailureIsRetriedTwiceThenWaitsForRetry() async throws {
        let row = try endedMeeting()
        let queue = queue()
        await queue.wake()
        for attempt in 1...3 {
            #expect(await eventually { launcher.requests.count == attempt })
            let process = launcher.processes[attempt - 1]
            process.send(.failed("Le moteur a planté."))
            process.end()
            #expect(try await eventually { try transcripts.job(for: row.id)?.attempts == attempt })
            await queue.wake()
        }
        let job = try #require(try transcripts.job(for: row.id))
        #expect(job.state == .failed && job.error == "Le moteur a planté.")
        try await Task.sleep(for: .milliseconds(100))
        #expect(launcher.requests.count == 3)

        await queue.retry(meetingID: row.id)
        #expect(await eventually { launcher.requests.count == 4 })
    }

    @Test func retranscribingStopsTheRunningJobAndClearsPartialResults() async throws {
        let row = try endedMeeting()
        let queue = queue()
        await queue.wake()
        #expect(await eventually { launcher.requests.count == 1 })
        try writeResult(row, track: .autres, index: 0, text: "Hello everyone.")
        await queue.retranscribe(meetingID: row.id, language: "en")
        #expect(launcher.processes.first?.stopCount == 1)
        #expect(!FileManager.default.fileExists(atPath: paths.meetingFolder(row.id).appending(path: "transcription").path(percentEncoded: false)))
        #expect(await eventually { launcher.requests.count == 2 })
        #expect(launcher.requests.last?.language == "en")
        #expect(try transcripts.jobs(for: row.id).filter { $0.state != .done }.count == 1)
    }
}

@Suite struct TranscriptImportTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)

    func setUp() throws -> (URL, MeetingRow, MeetingStore, TranscriptStore) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "import \(UUID().uuidString)", directoryHint: .isDirectory)
        let database = try AppDatabase.inMemory()
        let meetings = MeetingStore(database)
        let row = MeetingRow(createdAt: now, status: .ended, source: .dia, candidateKey: "t/abc", title: "Point hebdo", startedAt: now)
        try meetings.save(row)
        try FileManager.default.createDirectory(at: folder.appending(path: "audio/autres/b01"), withIntermediateDirectories: true)
        var file = MeetingFile(id: row.id, title: row.title, meetCode: nil, mode: .dia, startedAt: now, endedAt: now, endReason: "tabClosed")
        file.endNanos = 3_000_000_000
        try MeetingFile.encoder.encode(file).write(to: folder.appending(path: "meeting.json"))
        try ChunkResultFile.append(ChunkResult(track: .autres, chunk: Chunk(index: 0, start: 0, end: 3), segments: [
            EngineSegment(start: 0.5, end: 2, text: "On commence.", avgLogprob: -0.2, compressionRatio: 1.1, noSpeechProb: 0.1),
            EngineSegment(start: 2, end: 2.5, text: "Sous-titrage Société Radio-Canada", avgLogprob: -0.9, compressionRatio: 1.2, noSpeechProb: 0.7),
        ]), to: folder.appending(path: "transcription/autres.jsonl"))
        return (folder, row, meetings, TranscriptStore(database))
    }

    /// A 16 kHz archive of `seconds` seconds, as `TrackRenderer` makes it.
    func writeArchive(_ folder: URL, seconds: Double) throws {
        let pistes = folder.appending(path: "pistes", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: pistes, withIntermediateDirectories: true)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatAppleLossless, AVSampleRateKey: 16_000.0, AVNumberOfChannelsKey: 1, AVEncoderBitDepthHintKey: 16]
        let file = try AVAudioFile(forWriting: pistes.appending(path: "autres.caf"), settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(16_000 * seconds))!
        buffer.frameLength = buffer.frameCapacity
        try file.write(from: buffer)
    }

    @Test func importWritesLinesAndStartsTheThirtyDays() throws {
        let (folder, row, meetings, transcripts) = try setUp()
        defer { try? FileManager.default.removeItem(at: folder) }
        try writeArchive(folder, seconds: 3)
        let summary = try TranscriptImport.run(folder: folder, meetingID: row.id, language: "fr", transcripts: transcripts, meetings: meetings, now: now)
        #expect(summary.lines == 1 && summary.removed == 1)
        #expect(try transcripts.utterances(meetingID: row.id).map(\.text) == ["On commence."])
        #expect(try meetings.meeting(id: row.id)?.transcribedAt == now)
        let file = try MeetingFile.decoder.decode(MeetingFile.self, from: Data(contentsOf: folder.appending(path: "meeting.json")))
        #expect(file.version == 2 && file.transcript?.lines.map(\.text) == ["On commence."] && file.transcript?.language == "fr")
    }

    // Revue finale, Important 3 : sans ligne de temps lisible, rien ne prouve que le brut est dans l'archive.
    @Test func rawAudioIsKeptWithoutATimeline() throws {
        let (folder, row, meetings, transcripts) = try setUp()
        defer { try? FileManager.default.removeItem(at: folder) }
        try writeArchive(folder, seconds: 3)
        let summary = try TranscriptImport.run(folder: folder, meetingID: row.id, language: "fr", transcripts: transcripts, meetings: meetings, now: now)
        #expect(!summary.rawAudioDeleted)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "audio").path(percentEncoded: false)))
    }

    @Test func rawAudioIsKeptWhenTheArchiveIsShort() throws {
        let (folder, row, meetings, transcripts) = try setUp()
        defer { try? FileManager.default.removeItem(at: folder) }
        try writeArchive(folder, seconds: 1)
        let summary = try TranscriptImport.run(folder: folder, meetingID: row.id, language: "fr", transcripts: transcripts, meetings: meetings, now: now)
        #expect(!summary.rawAudioDeleted)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "audio").path(percentEncoded: false)))
    }

    @Test func meetingJsonVersion1StillReads() throws {
        let json = """
        {"endNanos":5,"health":{"autresSeconds":1,"errors":[],"gapCount":0,"moiSeconds":1,"rebuilds":0,"selfTestPassed":true},
         "id":"183186B0-646F-4D40-A663-2EA3C9D3E46D","meetCode":"yja-dyex-zqc","mode":"dia","moiSpans":[],"originNanos":1,
         "startedAt":"2026-11-13T12:08:26Z","title":"Google Meet","version":1}
        """
        let file = try MeetingFile.decoder.decode(MeetingFile.self, from: Data(json.utf8))
        #expect(file.version == 1 && file.transcript == nil)
    }
}
