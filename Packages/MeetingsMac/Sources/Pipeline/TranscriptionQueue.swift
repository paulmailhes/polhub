import Domain
import Foundation
import Observability
import Persistence
import Transcription

/// The work after the meetings. One job at a time, never during a meeting: as soon as a Meet shows, the
/// running `polhub-calcul` is stopped and its job goes back to the queue; the chunks it finished stay
/// on disk and are not done again.
public actor TranscriptionQueue {
    public static let automaticAttempts = 3
    public static let defaultLanguage = "fr"

    private let meetings: MeetingStore
    private let transcripts: TranscriptStore
    private let paths: AppPaths
    private let launcher: any CalculLaunching
    private let now: @Sendable () -> Date
    /// The language of new meetings: Réglages › Réunions (14/11); `nil` lets the engine detect it.
    private let language: @Sendable () -> String?
    private let log: TraceWriter?

    private var busy = false
    private var current: Running?
    /// Nothing starts before this: at launch the app does not yet know whether a meeting is resuming.
    private var holdUntil: Date?

    private struct Running {
        var job: JobRow
        let process: any CalculProcess
        var tracks: [Speaker: (done: Int, total: Int)] = [:]
        /// Set when the app stopped it (a Meet, a new language): its end is not a failure.
        var stoppedOnPurpose = false
        var outcome: Outcome?
    }

    private enum Outcome {
        case finished
        case failed(String)
    }

    public init(
        meetings: MeetingStore, transcripts: TranscriptStore, paths: AppPaths, launcher: any CalculLaunching,
        now: @escaping @Sendable () -> Date = Date.init, log: TraceWriter? = nil,
        language: @escaping @Sendable () -> String? = { TranscriptionQueue.defaultLanguage }
    ) {
        self.language = language
        self.meetings = meetings
        self.transcripts = transcripts
        self.paths = paths
        self.launcher = launcher
        self.now = now
        self.log = log
    }

    /// A computation is under way: an update waits for its end.
    public var isRunning: Bool { current != nil }

    /// At launch: what was running when the app stopped goes back to the queue. Nothing starts for
    /// `holdSeconds`: a meeting the app is resuming after a crash shows up only after the first readings of
    /// Dia (review, Important 5).
    public func start(holdSeconds: Double = 0) {
        _ = try? transcripts.resetRunning(at: now())
        holdUntil = holdSeconds > 0 ? now().addingTimeInterval(holdSeconds) : nil
        wake()
    }

    /// `true` from the pop-up to the end of a meeting.
    public func meetingActivity(_ busy: Bool) {
        self.busy = busy
        if busy {
            stopCurrent()
        } else {
            wake()
        }
    }

    /// Queues the meetings waiting for their transcription, then starts the oldest job if nothing runs.
    public func wake() {
        guard !busy, current == nil else { return }
        if let holdUntil, now() < holdUntil { return }
        let date = now()
        for row in (try? transcripts.meetingsAwaitingTranscription()) ?? [] {
            _ = try? transcripts.enqueue(meetingID: row.id, language: language(), at: date)
        }
        guard let job = try? transcripts.nextQueued() else { return }
        launch(job)
    }

    /// « Réessayer »: a failed job gets its automatic attempts back.
    public func retry(meetingID: UUID) {
        guard var job = try? transcripts.job(for: meetingID), job.state == .failed else { return }
        job.state = .queued
        job.attempts = 0
        job.error = nil
        job.updatedAt = now()
        try? transcripts.save(job)
        wake()
    }

    /// A meeting put in the Trash: its running computation stops, and it is never picked again.
    public func forget(meetingID: UUID) {
        if current?.job.meetingID == meetingID {
            stopCurrent()
        }
        wake()
    }

    /// « Retranscrire »: another language, from scratch. The running job of this meeting is stopped first.
    public func retranscribe(meetingID: UUID, language: String?) {
        if current?.job.meetingID == meetingID {
            stopCurrent()
        }
        try? FileManager.default.removeItem(at: paths.meetingFolder(meetingID).appending(path: "transcription", directoryHint: .isDirectory))
        _ = try? transcripts.enqueue(meetingID: meetingID, language: language, at: now())
        wake()
    }

    // MARK: - Running

    private func launch(_ queued: JobRow) {
        var job = queued
        let request = CalculRequest(folder: paths.meetingFolder(job.meetingID).path(percentEncoded: false), language: job.language)
        let process: any CalculProcess
        do {
            process = try launcher.start(request)
        } catch {
            fail(job, "Le calcul ne démarre pas : \(error.localizedDescription)")
            return
        }
        job.state = .running
        job.startedAt = now()
        job.updatedAt = now()
        job.progress = 0
        try? transcripts.save(job)
        current = Running(job: job, process: process)
        record("calcul-start", job)
        let jobID = job.id
        Task {
            for await message in process.messages {
                self.receive(message, jobID: jobID)
            }
            self.ended(jobID: jobID)
        }
    }

    private func receive(_ message: CalculMessage, jobID: UUID) {
        guard var running = current, running.job.id == jobID else { return }
        switch message {
        case .progress(let track, let done, let total):
            running.tracks[track] = (done, total)
            let totals = running.tracks.values.reduce((0, 0)) { ($0.0 + $1.done, $0.1 + $1.total) }
            running.job.progress = totals.1 > 0 ? Double(totals.0) / Double(totals.1) : 0
            running.job.updatedAt = now()
            try? transcripts.save(running.job)
        case .chunk:
            break
        case .finished:
            running.outcome = .finished
        case .failed(let message):
            running.outcome = .failed(message)
        }
        current = running
    }

    private func ended(jobID: UUID) {
        guard let running = current, running.job.id == jobID else { return }
        current = nil
        switch running.outcome {
        case .finished?:
            finish(running.job)
        case .failed(let message)?:
            fail(running.job, message)
        case nil where running.stoppedOnPurpose:
            break
        case nil:
            fail(running.job, "Le calcul s'est arrêté sans finir.")
        }
        wake()
    }

    private func stopCurrent() {
        guard var running = current else { return }
        running.stoppedOnPurpose = true
        current = running
        running.process.stop()
        // Back to the queue, without counting an attempt: the chunks done stay on disk.
        var job = running.job
        job.state = .queued
        job.updatedAt = now()
        try? transcripts.save(job)
        current = nil
        record("calcul-stop", job)
    }

    private func finish(_ running: JobRow) {
        var job = running
        do {
            let summary = try TranscriptImport.run(
                folder: paths.meetingFolder(job.meetingID), meetingID: job.meetingID, language: job.language,
                transcripts: transcripts, meetings: meetings, now: now()
            )
            job.state = .done
            job.progress = 1
            job.doubtful = summary.doubtful
            job.finishedAt = now()
            job.updatedAt = now()
            try? transcripts.save(job)
            record("calcul-done", job)
        } catch {
            fail(job, "Le dialogue n'a pas pu être enregistré : \(error.localizedDescription)")
        }
    }

    private func fail(_ failed: JobRow, _ message: String) {
        var job = failed
        job.attempts += 1
        job.error = message
        job.state = job.attempts < Self.automaticAttempts ? .queued : .failed
        job.updatedAt = now()
        try? transcripts.save(job)
        record("calcul-failed", job)
    }

    private struct JobRecord: Encodable, Sendable {
        let job: String
        let meeting: String
        let state: String
        let attempts: Int
        let error: String?
    }

    private func record(_ kind: String, _ job: JobRow) {
        guard let log else { return }
        let record = JobRecord(job: job.id.uuidString.lowercased(), meeting: job.meetingID.uuidString.lowercased(),
                               state: job.state.rawValue, attempts: job.attempts, error: job.error)
        Task { try? await log.write(kind: kind, record) }
    }
}
