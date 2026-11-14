import Domain
import Foundation
import Persistence

/// The summaries, one at a time, newest meeting first; never during a meeting nor a transcription: a meeting
/// that starts stops the one under way, which goes back to the queue (design of 12/11).
public actor SummaryQueue {
    private let store: SummaryStore
    private let database: AppDatabase
    private let engine: any SummaryEngine
    /// A transcription runs: the Mac's computing goes to it first.
    private let otherWork: @Sendable () async -> Bool
    /// Réglages › Réunions › Comptes rendus automatiques (14/11).
    private let isEnabled: @Sendable () -> Bool
    /// A summary was written: the notification « Compte rendu prêt » (14/11).
    private let onFinished: @Sendable (UUID, String) -> Void
    private let now: @Sendable () -> Date
    private var busy = false
    private var current: (meetingID: UUID, task: Task<Void, Never>)?
    /// The model's assets were missing: nothing starts before this (review of 14/11, Important 5).
    private var retryAfter: Date?

    public init(database: AppDatabase, engine: any SummaryEngine, otherWork: @escaping @Sendable () async -> Bool = { false },
                isEnabled: @escaping @Sendable () -> Bool = { true }, now: @escaping @Sendable () -> Date = Date.init,
                onFinished: @escaping @Sendable (UUID, String) -> Void = { _, _ in }) {
        self.onFinished = onFinished
        self.isEnabled = isEnabled
        self.database = database
        self.store = SummaryStore(database)
        self.engine = engine
        self.otherWork = otherWork
        self.now = now
    }

    /// A summary is being written: an update waits for it (review of 14/11).
    public var isRunning: Bool { current != nil }

    /// Why no summary can be made now, if so.
    public var unavailableReason: String? { engine.unavailableReason }

    /// At launch: what was running goes back to the queue.
    public func start() async {
        // Not the one the timer may have started meanwhile (review of 14/11, minor).
        if current == nil { _ = try? store.resetRunning(at: now()) }
        await wake()
    }

    /// `true` from the pop-up to the end of a meeting.
    public func meetingActivity(_ busy: Bool) async {
        self.busy = busy
        if busy {
            current?.task.cancel()
        } else {
            await wake()
        }
    }

    /// Starts the newest waiting summary, if nothing runs and nothing stops it.
    public func wake() async {
        if let retryAfter, now() < retryAfter { return }
        guard isEnabled() else { return }
        guard !busy, current == nil, engine.unavailableReason == nil, await !otherWork(), !busy, current == nil,
              let meetingID = try? store.nextPending() else { return }
        try? store.start(meetingID: meetingID, at: now())
        let task = Task { await self.run(meetingID) }
        current = (meetingID, task)
    }

    /// « Refaire le compte rendu ».
    public func redo(meetingID: UUID) async {
        try? store.redo(meetingID: meetingID, at: now())
        await wake()
    }

    /// Waits for the summary under way, and those it chains to (tests).
    func waitForIdle() async {
        while let task = current?.task { await task.value }
    }

    private func run(_ meetingID: UUID) async {
        let otherWork = otherWork
        do {
            let meetings = MeetingStore(database)
            let lines = try TranscriptStore(database).utterances(meetingID: meetingID)
            let title = try meetings.meeting(id: meetingID)?.title ?? ""
            let participants = try ContactStore(database).participants(meetingID: meetingID).map(\.name)
            // A transcription that starts stops the summary: the Mac computes one thing at a time (review of 14/11).
            let summary = try await Summarizer.make(lines: lines, title: title, participants: participants, engine: engine,
                                                    shouldStop: { await otherWork() })
            try store.finish(meetingID: meetingID, summary: summary.map(SummaryText.markdown),
                             actions: SummaryText.actionRows(summary?.actions ?? [], at: now()), at: now())
            if summary != nil { onFinished(meetingID, title) }
        } catch {
            if Task.isCancelled || error is CancellationError {
                // A meeting or a transcription stopped it, whatever the model called it (review, Important 4).
                try? store.stopped(meetingID: meetingID, at: now())
            } else if case SummaryError.unavailable = error {
                try? store.stopped(meetingID: meetingID, at: now())
                retryAfter = now().addingTimeInterval(60)
            } else {
                try? store.fail(meetingID: meetingID, error: (error as? SummaryError)?.description ?? error.localizedDescription, at: now())
            }
        }
        current = nil
        await wake()
    }
}
