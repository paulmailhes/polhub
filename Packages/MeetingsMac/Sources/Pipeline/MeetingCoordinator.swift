import Domain
import Foundation
import MeetingDetection
import Observability
import Persistence
import Recording

/// The short notices shown at the top of the screen.
public enum Toast: Equatable, Sendable {
    case devices(mic: String?, output: String?)
    case ended(title: String, seconds: Int)
    case resumed(title: String)
}

public enum AppAlert: Equatable, Sendable {
    case tabsUnreadable
    case selfTestFailed
    case diskLow(freeGB: Int)
    case trackFailed(String)
}

/// What the menu bar shows.
public enum RecorderStatus: Equatable, Sendable {
    case idle
    case prompting(title: String)
    case recording(title: String, since: Date)
    case presumedEnded(title: String)
    case paused(until: Date)
}

/// Everything Paul sees, behind a protocol: the app draws it, the tests record it.
@MainActor
public protocol MeetingPresenter: AnyObject {
    func showPrompt(title: String, deadline: Date)
    func hidePrompt()
    func show(_ toast: Toast)
    func show(_ alert: AppAlert)
    func update(_ status: RecorderStatus)
    /// The meeting's title changed (the tab's real title arrives after the first reading).
    func retitle(_ title: String)
}

public protocol RecorderFactory: Sendable {
    func make(folder: URL, mode: MeetingSource) throws -> any MeetingRecording
}

/// The real recorders, with the inaudible check measured at the start of step 1.
public struct LiveRecorderFactory: RecorderFactory {
    public let selfTestAmplitude: Float?

    public init(selfTestAmplitude: Float? = SystemAudioSelfTest.inaudibleAmplitude) {
        self.selfTestAmplitude = selfTestAmplitude
    }

    public func make(folder: URL, mode: MeetingSource) throws -> any MeetingRecording {
        try MeetingRecorder(folder: folder, mode: mode, selfTestAmplitude: selfTestAmplitude)
    }
}

/// From detection to a recorded meeting: feeds the detector, carries out its effects (base, recorder,
/// pop-ups, journal), and closes or resumes the meetings a crash left open.
@MainActor
public final class MeetingCoordinator {
    private struct Current {
        var row: MeetingRow
        let recorder: any MeetingRecording
        var listener: Task<Void, Never>?
        var endShown = false
        var diskWarned = false
        var micNames: String?
        var outputName: String?
    }

    private struct LogLine: Encodable, Sendable {
        let at: Double
        let what: String
    }

    private let store: MeetingStore
    private let paths: AppPaths
    private let recorders: any RecorderFactory
    private weak var presenter: (any MeetingPresenter)?
    private var detector: MeetingDetector
    private let clock: () -> Double
    private let now: () -> Date
    private let availableBytes: () -> Int64?
    private let deviceName: (String) -> String
    private let log: TraceWriter?
    private let canResume: (MeetingRow) -> Bool
    private let lastWrite: (MeetingRow) -> Date?

    private var current: Current?
    /// Dia's tabs became unreadable during a meeting: said at its end, if they still are (13/11).
    private var tabsAlertPending = false
    private var recovering: [MeetingRow] = []
    private var recoveryDeadline: Double?
    private var lastDiskCheck: Double?
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    public init(
        store: MeetingStore, paths: AppPaths, recorders: any RecorderFactory, presenter: any MeetingPresenter,
        detector: MeetingDetector, clock: @escaping () -> Double, now: @escaping () -> Date,
        availableBytes: @escaping () -> Int64?, deviceName: @escaping (String) -> String, log: TraceWriter?,
        canResume: @escaping (MeetingRow) -> Bool = { _ in true }, lastWrite: @escaping (MeetingRow) -> Date? = { _ in nil }
    ) {
        self.canResume = canResume
        self.lastWrite = lastWrite
        self.store = store
        self.paths = paths
        self.recorders = recorders
        self.presenter = presenter
        self.detector = detector
        self.clock = clock
        self.now = now
        self.availableBytes = availableBytes
        self.deviceName = deviceName
        self.log = log
    }

    /// Meetings a crash left open: each is resumed if its tab comes back with the microphone within 15 s,
    /// otherwise closed as interrupted.
    public func recoverAfterLaunch() throws {
        let unfinished = try store.unfinished()
        // Only a meeting whose timeline was written moments ago, since this boot, can go on (review,
        // Important 3); any other is closed at once with what it recorded.
        recovering = unfinished.filter(canResume)
        for row in unfinished where !canResume(row) { closeInterrupted(row) }
        recoveryDeadline = recovering.isEmpty ? nil : clock() + 15
    }

    public func handle(_ input: DetectionInput, at time: Double) async {
        await exclusively {
            record("input", "\(input)", at: time)
            if case .tabs(let tabs, _) = input { refreshTitle(from: tabs) }
            await perform(detector.handle(input, at: time))
            await closeUnrecoveredMeetings(at: time)
        }
    }

    /// Called every half second: lets the detector's deadlines fall, checks the disk every 5 min.
    public func tick() async {
        await exclusively {
            let time = clock()
            await perform(detector.advance(to: time))
            await closeUnrecoveredMeetings(at: time)
            if current != nil, time - (lastDiskCheck ?? -.infinity) >= 300 {
                checkDisk(at: time)
            }
        }
    }

    /// Inputs, ticks and clicks are handled one at a time, each to its end: a stop that takes seconds
    /// never lets the next meeting's effects slip in between (review, Important 7).
    private func exclusively(_ body: () async -> Void) async {
        if busy {
            await withCheckedContinuation { waiting.append($0) }
        }
        busy = true
        await body()
        if waiting.isEmpty {
            busy = false
        } else {
            waiting.removeFirst().resume()   // handed over: `busy` stays true
        }
    }

    /// The tab's real title arrives a second after the first reading: the meeting follows it.
    private func refreshTitle(from tabs: [BrowserTab]) {
        guard var meeting = current, meeting.row.source == .dia, let tabID = meeting.row.tabID,
              let tab = tabs.first(where: { $0.tabID == tabID && MeetLink.parse($0.url)?.code == meeting.row.meetCode }),
              tab.title != meeting.row.tabTitle
        else { return }
        meeting.row.tabTitle = tab.title
        let title = MeetingTitle.make(tabTitle: tab.title, code: meeting.row.meetCode, source: .dia, micOnly: false)
        let changed = title != meeting.row.title
        meeting.row.title = title
        save(&meeting)
        guard changed else { return }
        presenter?.retitle(title)
        switch meeting.row.status {
        case .pending: presenter?.update(.prompting(title: title))
        case .recording: presenter?.update(.recording(title: title, since: meeting.row.startedAt))
        case .presumedEnded: presenter?.update(.presumedEnded(title: title))
        default: break
        }
    }

    public func user(_ action: UserAction) async {
        await handle(.user(action), at: clock())
    }

    // MARK: - Effects

    private func perform(_ effects: [TimedEffect]) async {
        for effect in effects {
            record("effect", "\(effect.effect)", at: effect.at)
            await perform(effect)
        }
    }

    private func perform(_ timed: TimedEffect) async {
        let at = timed.at
        switch timed.effect {
        case .prompt(let candidate, let deadline):
            if let index = recovering.firstIndex(where: { $0.candidateKey == candidate.key }) {
                await resume(recovering.remove(at: index), at: at)
                await perform(detector.handle(.user(.accept), at: at))
            } else {
                await start(candidate, status: .pending, source: .dia, at: at)
                presenter?.showPrompt(title: current?.row.title ?? "", deadline: date(deadline))
                presenter?.update(.prompting(title: current?.row.title ?? ""))
            }

        case .confirm(let candidate):
            if current == nil {
                await start(candidate, status: .recording, source: candidate.source == .manual ? .wholeMac : .dia, at: at)
            }
            guard var meeting = current else { return }
            meeting.row.status = .recording
            save(&meeting)
            presenter?.hidePrompt()
            presenter?.update(.recording(title: meeting.row.title, since: meeting.row.startedAt))

        case .discard:
            guard var meeting = current else { return }
            current = nil
            meeting.listener?.cancel()
            await meeting.recorder.discard()
            meeting.row.status = .discarded
            meeting.row.deletedAt = now()
            save(&meeting)
            presenter?.hidePrompt()
            presenter?.update(.idle)

        case .presumedEnd(_, let endedAt):
            guard var meeting = current else { return }
            meeting.row.status = .presumedEnded
            meeting.row.presumedEndAt = date(endedAt)
            meeting.endShown = true
            save(&meeting)
            presenter?.show(.ended(title: meeting.row.title, seconds: seconds(of: meeting.row, until: date(endedAt))))
            presenter?.update(.presumedEnded(title: meeting.row.title))

        case .resume:
            guard var meeting = current else { return }
            meeting.row.status = .recording
            meeting.row.presumedEndAt = nil
            meeting.endShown = false
            save(&meeting)
            presenter?.show(.resumed(title: meeting.row.title))
            presenter?.update(.recording(title: meeting.row.title, since: meeting.row.startedAt))

        case .end(_, let endedAt, let reason):
            guard let meeting = current else { return }
            current = nil
            await finish(meeting, endedAt: date(endedAt), endNanos: UInt64(max(0, endedAt) * 1e9), reason: reason)
            presenter?.update(.idle)

        case .missed(let candidate, let reason):
            let title = MeetingTitle.make(tabTitle: candidate.tabTitle, code: candidate.code, source: .dia, micOnly: candidate.source == .micOnly)
            journal(.missed, "Dia a tenu le micro 10 min avec l'onglet « \(title) », sans enregistrement (\(Self.words(reason))).")

        case .alert(.tabsUnreadable):
            // During a meeting the recording does not need the tabs: a pop-up would only alarm.
            if current != nil {
                tabsAlertPending = true
                journal(.alert, "Polhub ne lit plus les onglets de Dia (la réunion en cours s'enregistre normalement).")
            } else {
                presenter?.show(.tabsUnreadable)
                journal(.alert, "Polhub ne lit plus les onglets de Dia : les réunions sont détectées par le micro seul.")
            }

        case .alert(.tabsReadableAgain):
            tabsAlertPending = false
            journal(.info, "Les onglets de Dia se lisent de nouveau.")

        case .rememberNever(let code):
            try? store.addNeverCode(code, at: now())
        }
    }

    // MARK: - A meeting

    private func start(_ candidate: MeetingCandidate, status: MeetingStatus, source: MeetingSource, at time: Double) async {
        let startedAt = date(time)
        let row = MeetingRow(
            createdAt: now(), status: status, source: source, candidateKey: candidate.key, tabID: candidate.tabID,
            meetCode: candidate.code, authUser: candidate.authUser, tabTitle: candidate.tabTitle,
            title: MeetingTitle.make(tabTitle: candidate.tabTitle, code: candidate.code, source: source, micOnly: candidate.source == .micOnly),
            startedAt: startedAt
        )
        await record(row, recording: source, at: time)
    }

    /// The meeting a crash interrupted goes on in its folder, under its row.
    private func resume(_ row: MeetingRow, at time: Double) async {
        var row = row
        row.status = .recording
        row.presumedEndAt = nil
        await record(row, recording: row.source, at: time)
        journal(.info, "Réunion « \(row.title) » reprise après un arrêt de l'app.")
    }

    private func record(_ row: MeetingRow, recording source: MeetingSource, at time: Double) async {
        let folder = paths.meetingFolder(row.id)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let recorder: any MeetingRecording
        do {
            recorder = try recorders.make(folder: folder, mode: source)
        } catch {
            presenter?.show(.trackFailed("L'enregistrement ne démarre pas : \(error.localizedDescription)"))
            journal(.alert, "L'enregistrement de « \(row.title) » n'a pas démarré : \(error.localizedDescription)")
            return
        }
        var meeting = Current(row: row, recorder: recorder)
        save(&meeting)
        meeting.listener = Task { [weak self] in
            for await event in recorder.events {
                self?.handle(event)
            }
        }
        current = meeting
        await recorder.start()
        checkDisk(at: time)
    }

    private func finish(_ meeting: Current, endedAt: Date, endNanos: UInt64?, reason: EndReason) async {
        var meeting = meeting
        await meeting.recorder.stop()
        meeting.listener?.cancel()
        let header = MeetingFile(
            id: meeting.row.id, title: meeting.row.title, meetCode: meeting.row.meetCode, mode: meeting.row.source,
            startedAt: meeting.row.startedAt, endedAt: endedAt, endReason: reason.rawValue
        )
        var withEnd = header
        withEnd.endNanos = endNanos
        let file = try? MeetingFinalizer.finalize(folder: paths.meetingFolder(meeting.row.id), header: withEnd)
        meeting.row.status = reason == .interrupted ? .interrupted : .ended
        meeting.row.endedAt = endedAt
        meeting.row.endReason = reason
        meeting.row.healthJSON = file.flatMap { try? String(decoding: JSONEncoder().encode($0.health), as: UTF8.self) }
        save(&meeting)
        if !meeting.endShown, reason != .interrupted {
            presenter?.show(.ended(title: meeting.row.title, seconds: seconds(of: meeting.row, until: endedAt)))
        }
        if tabsAlertPending {
            tabsAlertPending = false
            presenter?.show(.tabsUnreadable)
        }
    }

    /// 15 s after launch, a meeting nobody came back to is closed with what it recorded.
    private func closeUnrecoveredMeetings(at time: Double) async {
        guard let deadline = recoveryDeadline, time >= deadline else { return }
        recoveryDeadline = nil
        let rows = recovering
        recovering = []
        for row in rows { closeInterrupted(row) }
    }

    /// A meeting the app stopped recording without ending it: it ends when its timeline stopped.
    private func closeInterrupted(_ row: MeetingRow) {
        let endedAt = row.presumedEndAt ?? lastWrite(row) ?? row.updatedAt
        let header = MeetingFile(
            id: row.id, title: row.title, meetCode: row.meetCode, mode: row.source,
            startedAt: row.startedAt, endedAt: endedAt, endReason: EndReason.interrupted.rawValue
        )
        let file = try? MeetingFinalizer.finalize(folder: paths.meetingFolder(row.id), header: header)
        var closed = row
        closed.status = .interrupted
        closed.endedAt = endedAt
        closed.endReason = .interrupted
        closed.healthJSON = file.flatMap { try? String(decoding: JSONEncoder().encode($0.health), as: UTF8.self) }
        closed.updatedAt = now()
        try? store.save(closed)
        journal(.info, "Réunion « \(row.title) » interrompue : l'app s'était arrêtée pendant l'enregistrement.")
    }

    // MARK: - What the recorder says

    private func handle(_ event: RecorderEvent) {
        guard var meeting = current else { return }
        switch event {
        case .selfTest(let passed):
            if !passed {
                presenter?.show(.selfTestFailed)
                journal(.alert, "Le son des autres n'est pas capté au début de « \(meeting.row.title) » : vérifie l'autorisation d'enregistrement de l'audio du système.")
            }
        case .micsChanged(let mics):
            meeting.micNames = mics.isEmpty ? nil : mics.map(deviceName).joined(separator: ", ")
            current = meeting
            presenter?.show(.devices(mic: meeting.micNames, output: meeting.outputName))
        case .outputChanged(let output):
            meeting.outputName = output.map(deviceName)
            current = meeting
            presenter?.show(.devices(mic: meeting.micNames, output: meeting.outputName))
        case .trackFailed(_, let message), .traceFailed(let message):
            presenter?.show(.trackFailed(message))
            journal(.alert, "Pendant « \(meeting.row.title) » : \(message)")
        }
    }

    // MARK: - Small things

    private func checkDisk(at time: Double) {
        lastDiskCheck = time
        guard var meeting = current, !meeting.diskWarned, let free = availableBytes(), DiskGuard.isLow(availableBytes: free) else { return }
        meeting.diskWarned = true
        current = meeting
        let freeGB = Int(free / 1_000_000_000)
        presenter?.show(.diskLow(freeGB: freeGB))
        journal(.alert, "Disque presque plein : il reste \(freeGB) Go.")
    }

    private func save(_ meeting: inout Current) {
        meeting.row.updatedAt = now()
        try? store.save(meeting.row)
        if current?.row.id == meeting.row.id { current = meeting }
    }

    private func journal(_ kind: JournalKind, _ message: String) {
        try? store.addJournal(JournalEntry(createdAt: now(), kind: kind, message: message, meetingID: current?.row.id))
    }

    private func record(_ kind: String, _ what: String, at time: Double) {
        guard let log else { return }
        Task { try? await log.write(kind: kind, LogLine(at: time, what: what)) }
    }

    /// A detector time (continuous seconds) as a date.
    private func date(_ time: Double) -> Date {
        now().addingTimeInterval(time - clock())
    }

    private func seconds(of row: MeetingRow, until end: Date) -> Int {
        max(0, Int(end.timeIntervalSince(row.startedAt).rounded()))
    }

    static func words(_ reason: MissReason) -> String {
        switch reason {
        case .declined: "refusée ou arrêtée"
        case .paused: "détection suspendue"
        case .tabsUnreadable: "onglets illisibles"
        case .notDetected: "non détectée"
        }
    }
}
