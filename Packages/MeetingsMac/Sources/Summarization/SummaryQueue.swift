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
    private let now: @Sendable () -> Date
    private var busy = false
    private var current: (meetingID: UUID, task: Task<Void, Never>)?

    public init(database: AppDatabase, engine: any SummaryEngine, otherWork: @escaping @Sendable () async -> Bool = { false },
                now: @escaping @Sendable () -> Date = Date.init) {
        self.database = database
        self.store = SummaryStore(database)
        self.engine = engine
        self.otherWork = otherWork
        self.now = now
    }

    /// Why no summary can be made now, if so.
    public var unavailableReason: String? { engine.unavailableReason }

    /// At launch: what was running goes back to the queue.
    public func start() async {
        _ = try? store.resetRunning(at: now())
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
        do {
            let meetings = MeetingStore(database)
            let lines = try TranscriptStore(database).utterances(meetingID: meetingID)
            let title = try meetings.meeting(id: meetingID)?.title ?? ""
            let participants = try ContactStore(database).participants(meetingID: meetingID).map(\.name)
            let summary = try await Summarizer.make(lines: lines, title: title, participants: participants, engine: engine)
            try store.finish(meetingID: meetingID, summary: summary.map(SummaryText.markdown),
                             actions: SummaryText.actionRows(summary?.actions ?? [], at: now()), at: now())
        } catch is CancellationError {
            try? store.stopped(meetingID: meetingID, at: now())
        } catch let error as SummaryError {
            if case .unavailable = error {
                try? store.stopped(meetingID: meetingID, at: now())
            } else {
                try? store.fail(meetingID: meetingID, error: error.description, at: now())
            }
        } catch {
            if Task.isCancelled {
                try? store.stopped(meetingID: meetingID, at: now())
            } else {
                try? store.fail(meetingID: meetingID, error: error.localizedDescription, at: now())
            }
        }
        current = nil
        await wake()
    }
}
