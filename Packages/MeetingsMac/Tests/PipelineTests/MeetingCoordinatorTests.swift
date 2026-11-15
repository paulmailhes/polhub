import Domain
import Foundation
import MeetingDetection
import Persistence
import Recording
import Testing
@testable import Pipeline

@MainActor final class Gate {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var open = false
    func wait() async { if !open { await withCheckedContinuation { waiting.append($0) } } }
    func release() { open = true; waiting.forEach { $0.resume() }; waiting = [] }
}

final class FakeRecorder: MeetingRecording, @unchecked Sendable {
    let events: AsyncStream<RecorderEvent>
    let continuation: AsyncStream<RecorderEvent>.Continuation
    var starts = 0, stops = 0, discards = 0
    var stopGate: Gate?

    init() { (events, continuation) = AsyncStream<RecorderEvent>.makeStream() }
    func start() async { starts += 1 }
    func stop() async {
        if let stopGate { await stopGate.wait() }
        stops += 1
        continuation.finish()
    }
    func discard() async { discards += 1; continuation.finish() }
}

final class FakeFactory: RecorderFactory, @unchecked Sendable {
    var made: [(folder: URL, mode: MeetingSource, recorder: FakeRecorder)] = []
    var stopGate: Gate?
    func make(folder: URL, mode: MeetingSource) throws -> any MeetingRecording {
        let recorder = FakeRecorder()
        recorder.stopGate = stopGate
        made.append((folder, mode, recorder))
        return recorder
    }
}

@MainActor final class FakePresenter: MeetingPresenter {
    var prompts: [String] = [], hides = 0, toasts: [Toast] = [], alerts: [AppAlert] = [], statuses: [RecorderStatus] = [], retitles: [String] = []
    var resolved: [AppAlert.Kind] = [], links: [String?] = []
    func retitle(_ title: String) { retitles.append(title) }
    func resolve(_ alert: AppAlert.Kind) { resolved.append(alert) }
    func meetingLink(_ meetCode: String?) { links.append(meetCode) }
    func showPrompt(title: String, deadline: Date) { prompts.append(title) }
    func hidePrompt() { hides += 1 }
    func show(_ toast: Toast) { toasts.append(toast) }
    func show(_ alert: AppAlert) { alerts.append(alert) }
    func update(_ status: RecorderStatus) { statuses.append(status) }
}

@MainActor final class Clock { var t = 0.0 }

@MainActor @Suite struct MeetingCoordinatorTests {
    let clock = Clock()
    let store: MeetingStore
    let paths: AppPaths
    let factory = FakeFactory()
    let presenter = FakePresenter()
    var freeBytes: Int64? = 200_000_000_000

    init() throws {
        store = MeetingStore(try AppDatabase.inMemory())
        let root = FileManager.default.temporaryDirectory.appending(path: "coordinator-\(UUID().uuidString)", directoryHint: .isDirectory)
        paths = AppPaths(root: root, logs: root.appending(path: "logs"))
    }

    func coordinator(
        freeBytes: Int64? = 200_000_000_000, canResume: @escaping (MeetingRow) -> Bool = { _ in true },
        lastWrite: @escaping (MeetingRow) -> Date? = { _ in nil }, eventTitle: @escaping (String?, Date) -> String? = { _, _ in nil }
    ) -> MeetingCoordinator {
        let clock = clock
        return MeetingCoordinator(
            store: store, paths: paths, recorders: factory, presenter: presenter, detector: MeetingDetector(),
            clock: { clock.t }, now: { Date(timeIntervalSince1970: 1_763_000_000 + clock.t) },
            availableBytes: { freeBytes }, deviceName: { $0 == "casque" ? "Casque" : $0 }, log: nil,
            canResume: canResume, lastWrite: lastWrite, eventTitle: eventTitle
        )
    }

    func tab(_ code: String = "abc-defg-hij", id: String = "A", title: String = "Meet – Point hebdo", focused: Bool = true) -> BrowserTab {
        BrowserTab(windowID: "W", tabID: id, url: "https://meet.google.com/\(code)", title: title,
                   isLoading: false, isFocused: focused, isPinned: false)
    }

    let holding = DetectionInput.audio(DiaAudio(holdsMic: true, playing: true))
    let silent = DetectionInput.audio(DiaAudio(holdsMic: false, playing: false))

    func at(_ t: Double, _ c: MeetingCoordinator, _ input: DetectionInput) async {
        clock.t = t
        await c.handle(input, at: t)
    }

    func tick(_ t: Double, _ c: MeetingCoordinator) async {
        clock.t = t
        await c.tick()
    }

    /// Lets the coordinator's listener read what a fake recorder sent.
    func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test func aConfirmedMeetingIsStoredRecordedAndFinalized() async throws {
        let c = coordinator()
        await at(100, c, .tabs([tab()], complete: true))
        #expect(presenter.prompts == ["Point hebdo"])
        await tick(111, c)
        #expect(try store.recent(limit: 10).first?.status == .recording)
        await at(200, c, .tabs([], complete: true))
        let row = try #require(try store.recent(limit: 10).first)
        #expect(row.status == .ended && row.endReason == .tabClosed && row.title == "Point hebdo" && row.meetCode == "abc-defg-hij")
        let recorder = try #require(factory.made.first?.recorder)
        #expect(recorder.starts == 1 && recorder.stops == 1 && factory.made.first?.mode == .dia)
        #expect(FileManager.default.fileExists(atPath: paths.meetingFolder(row.id).appending(path: "meeting.json").path))
        #expect(presenter.toasts.contains { if case .ended = $0 { true } else { false } })
    }

    @Test func aDeclinedMeetingLeavesNoAudio() async throws {
        let c = coordinator()
        await at(100, c, .tabs([tab()], complete: true))
        clock.t = 102
        await c.user(.decline)
        let made = try #require(factory.made.first)
        #expect(made.recorder.discards == 1)
        let id = try #require(UUID(uuidString: made.folder.lastPathComponent))
        let row = try #require(try store.meeting(id: id))
        #expect(row.status == .discarded && row.deletedAt != nil)
        #expect(try store.recent(limit: 10).isEmpty)
    }

    // 13/11, réunion client : Dia n'a pas répondu une minute ; le pop-up a fait croire à Paul que
    // l'enregistrement avait un problème. Pendant une réunion, la panne va au journal seulement.
    @Test func unreadableTabsDuringAMeetingDoNotPopUp() async throws {
        let c = coordinator()
        await at(99, c, holding)
        await at(100, c, .tabs([tab()], complete: true))
        await tick(111, c)
        for t in [120.0, 128, 136, 144] { await at(t, c, .tabsUnavailable("-1712 Dia n'a pas répondu en 3.0 s")) }
        #expect(presenter.alerts.isEmpty)
        #expect(try store.journal(limit: 10).contains { $0.kind == .alert })
        await at(160, c, .tabs([tab()], complete: true))
        await at(170, c, .tabs([], complete: true))
        #expect(presenter.alerts.isEmpty)
    }

    @Test func tabsStillUnreadableAtTheEndOfAMeetingAreThenShown() async throws {
        let c = coordinator()
        await at(99, c, holding)
        await at(100, c, .tabs([tab()], complete: true))
        await tick(111, c)
        for t in [120.0, 128, 136] { await at(t, c, .tabsUnavailable("-1712 Dia n'a pas répondu en 3.0 s")) }
        #expect(presenter.alerts.isEmpty)
        clock.t = 150
        await c.user(.stop)
        #expect(presenter.alerts == [.tabsUnreadable])
    }

    @Test func aPresumedEndShowsTheEndAndKeepsRecording() async throws {
        let c = coordinator()
        await at(99, c, holding)
        await at(100, c, .tabs([tab()], complete: true))
        await tick(111, c)
        await at(200, c, silent)
        await tick(206, c)
        let recorder = try #require(factory.made.first?.recorder)
        #expect(recorder.stops == 0)
        #expect(try store.recent(limit: 1).first?.status == .presumedEnded)
        await tick(801, c)
        #expect(recorder.stops == 1)
        #expect(presenter.toasts.filter { if case .ended = $0 { true } else { false } }.count == 1)
        #expect(try store.recent(limit: 1).first?.endReason == .safetyElapsed)
    }

    @Test func aMissedMeetingGoesToTheJournal() async throws {
        let c = coordinator()
        await at(100, c, .tabs([tab()], complete: true))
        clock.t = 101
        await c.user(.decline)
        await at(102, c, holding)
        await at(110, c, .tabs([tab()], complete: true))
        await tick(703, c)
        let missed = try store.journal(limit: 10).filter { $0.kind == .missed }
        #expect(missed.count == 1)
        #expect(missed.first?.message.contains("sans enregistrement") == true)
    }

    // Review Focus 3
    @Test func aRecorderFailureRaisesAnAlertAndAJournalEntry() async throws {
        let c = coordinator()
        await at(100, c, .tabs([tab()], complete: true))
        await tick(111, c)
        let recorder = try #require(factory.made.first?.recorder)
        recorder.continuation.yield(.trackFailed(track: "moi", message: "Le micro a lâché"))
        await settle()
        #expect(presenter.alerts == [.trackFailed("Le micro a lâché")])
        #expect(try store.journal(limit: 10).contains { $0.kind == .alert })
        #expect(recorder.stops == 0)
    }

    // « Coup d'œil » (15/11): « Jamais pour ce lien » needs the meeting's code, told as the meeting starts and ends.
    @Test func theMeetingsLinkIsToldThenForgotten() async throws {
        let c = coordinator()
        await at(100, c, .tabs([tab()], complete: true))
        #expect(presenter.links == ["abc-defg-hij"])
        clock.t = 102
        await c.user(.decline)
        #expect(presenter.links == ["abc-defg-hij", nil])
        // A meeting started by hand has no code.
        clock.t = 110
        await c.user(.recordNow)
        #expect(presenter.links.count == 2)
    }

    // « Coup d'œil » (15/11): the badge of the menu bar goes once the cause of the alert is gone.
    @Test func theCausesOfTheAlertsAreToldWhenTheyAreGone() async throws {
        let c = coordinator()
        for t in [100.0, 108, 116] { await at(t, c, .tabsUnavailable("-1712 Dia n'a pas répondu en 3.0 s")) }
        #expect(presenter.alerts == [.tabsUnreadable])
        #expect(presenter.resolved.isEmpty)
        await at(120, c, .tabs([], complete: true))
        #expect(presenter.resolved == [.tabsUnreadable])

        await at(130, c, holding)
        await at(131, c, .tabs([tab()], complete: true))
        // A new recorder: a track failure of before no longer threatens.
        #expect(presenter.resolved == [.tabsUnreadable, .trackFailed])
        let recorder = try #require(factory.made.first?.recorder)
        recorder.continuation.yield(.selfTest(passed: true))
        await settle()
        #expect(presenter.resolved == [.tabsUnreadable, .trackFailed, .selfTestFailed])
        recorder.continuation.yield(.selfTest(passed: false))
        await settle()
        #expect(presenter.alerts == [.tabsUnreadable, .selfTestFailed])
    }

    // Review Focus 3
    @Test func lowDiskSpaceWarnsOnce() async throws {
        let c = coordinator(freeBytes: 15_000_000_000)
        await at(100, c, .tabs([tab()], complete: true))
        await tick(111, c)
        await tick(500, c)
        await tick(900, c)
        #expect(presenter.alerts == [.diskLow(freeGB: 15)])
    }

    // Review Focus 1
    @Test func aMeetingInterruptedByACrashResumesInItsFolder() async throws {
        let start = Date(timeIntervalSince1970: 1_763_000_000 - 600)
        let row = MeetingRow(createdAt: start, status: .recording, source: .dia, candidateKey: "A/abc-defg-hij",
                             tabID: "A", meetCode: "abc-defg-hij", title: "Point hebdo", startedAt: start)
        try store.save(row)
        try FileManager.default.createDirectory(at: paths.meetingFolder(row.id), withIntermediateDirectories: true)
        let c = coordinator()
        try c.recoverAfterLaunch()
        await at(1, c, holding)
        await at(2, c, .tabs([tab()], complete: true))
        #expect(factory.made.map(\.folder) == [paths.meetingFolder(row.id)])
        #expect(presenter.prompts.isEmpty)
        #expect(try store.recent(limit: 10).map(\.id) == [row.id])
        #expect(try store.meeting(id: row.id)?.status == .recording)
    }

    @Test func anUnmatchedUnfinishedMeetingIsClosedAsInterrupted() async throws {
        let start = Date(timeIntervalSince1970: 1_763_000_000 - 600)
        let row = MeetingRow(createdAt: start, status: .recording, source: .dia, candidateKey: "A/abc-defg-hij",
                             title: "Point hebdo", startedAt: start)
        try store.save(row)
        let c = coordinator()
        try c.recoverAfterLaunch()
        await tick(16, c)
        let closed = try #require(try store.meeting(id: row.id))
        #expect(closed.status == .interrupted && closed.endReason == .interrupted)
    }

    @Test func devicesChangesBecomeAToastWithNames() async throws {
        let c = coordinator()
        await at(100, c, .tabs([tab()], complete: true))
        await tick(111, c)
        let recorder = try #require(factory.made.first?.recorder)
        recorder.continuation.yield(.micsChanged(["casque"]))
        await settle()
        #expect(presenter.toasts.contains(.devices(mic: "Casque", output: nil)))
    }

    // Revue finale, Important 4 : le vrai titre de l'onglet arrive une seconde après le pop-up.
    @Test func theTitleFollowsTheTab() async throws {
        let c = coordinator()
        await at(100, c, .tabs([tab(title: "Meet")], complete: true))
        #expect(presenter.prompts == ["Google Meet"])
        await at(101, c, .tabs([tab(title: "Meet – Point hebdo")], complete: true))
        #expect(try store.recent(limit: 1).first?.title == "Point hebdo")
        #expect(presenter.retitles == ["Point hebdo"])
    }

    // Revue finale, Important 7 : une fin lente ne laisse pas la réunion suivante s'intercaler.
    /// 14/11: the calendar knows the meeting's name before the tab does, and better.
    @Test func theCalendarsTitleComesFirstAndTheTabDoesNotReplaceIt() async throws {
        var asked: [String?] = []
        let c = coordinator(eventTitle: { code, _ in
            asked.append(code)
            return code == "abc-defg-hij" ? "Atelier maquette Alpha" : nil
        })
        await at(100, c, .tabs([tab(title: "Meet")], complete: true))
        #expect(presenter.prompts == ["Atelier maquette Alpha"])
        await at(101, c, .tabs([tab(title: "Meet – Point hebdo")], complete: true))
        let row = try #require(try store.recent(limit: 1).first)
        #expect(row.title == "Atelier maquette Alpha" && row.tabTitle == "Meet – Point hebdo")
        #expect(presenter.retitles.isEmpty)
        #expect(asked.first == "abc-defg-hij")
    }

    @Test func aSlowStopDoesNotLetTheNextMeetingInterleave() async throws {
        let gate = Gate()
        factory.stopGate = gate
        let c = coordinator()
        await at(100, c, .tabs([tab()], complete: true))
        await tick(111, c)
        clock.t = 200
        let ending = Task { await c.handle(.tabs([], complete: true), at: 200) }
        await settle()
        let next = Task { await c.handle(.tabs([tab("xyz-abcd-efg", id: "B")], complete: true), at: 201) }
        await settle()
        #expect(presenter.prompts.count == 1)
        gate.release()
        await ending.value
        await next.value
        #expect(presenter.prompts.count == 2)
        #expect(Array(presenter.statuses.suffix(2)) == [.idle, .prompting(title: "Point hebdo")])
    }

    // Revue finale, Important 3 : une réunion restée ouverte depuis longtemps n'est pas « reprise ».
    @Test func aStaleUnfinishedMeetingIsClosedAtOnce() async throws {
        let start = Date(timeIntervalSince1970: 1_763_000_000 - 7_200)
        let row = MeetingRow(createdAt: start, status: .presumedEnded, source: .dia, candidateKey: "A/abc-defg-hij",
                             title: "Vieille réunion", startedAt: start)
        try store.save(row)
        let c = coordinator(canResume: { _ in false })
        try c.recoverAfterLaunch()
        #expect(try store.meeting(id: row.id)?.status == .interrupted)
        await at(1, c, holding)
        await at(2, c, .tabs([tab()], complete: true))
        #expect(factory.made.allSatisfy { $0.folder != paths.meetingFolder(row.id) })
    }

    // Revue finale, mineur relevé : une réunion interrompue finit quand sa timeline s'est arrêtée.
    @Test func anInterruptedMeetingEndsWhenItsTimelineStopped() async throws {
        let start = Date(timeIntervalSince1970: 1_763_000_000 - 3_600)
        let row = MeetingRow(createdAt: start, status: .recording, source: .dia, candidateKey: "A/abc-defg-hij",
                             title: "Point hebdo", startedAt: start)
        try store.save(row)
        let stoppedAt = start.addingTimeInterval(3_000)
        let c = coordinator(canResume: { _ in false }, lastWrite: { _ in stoppedAt })
        try c.recoverAfterLaunch()
        let closed = try #require(try store.meeting(id: row.id))
        #expect(closed.endedAt.map { abs($0.timeIntervalSince(stoppedAt)) < 0.01 } == true)
    }

    // Revue finale, mineur relevé : la lecture s'arrête à la fin de la réunion, pas 10 min après.
    @Test func theEndOfTheMeetingIsKeptForPlayback() async throws {
        let c = coordinator()
        await at(99, c, holding)
        await at(100, c, .tabs([tab()], complete: true))
        await tick(111, c)
        await at(200, c, silent)
        await tick(801, c)
        let row = try #require(try store.recent(limit: 1).first)
        let file = try MeetingFile.decoder.decode(MeetingFile.self, from: Data(contentsOf: paths.meetingFolder(row.id).appending(path: "meeting.json")))
        #expect(file.endNanos == 200_000_000_000)
    }

    @Test func recoveryNeedsARecentTimelineFromThisBoot() {
        let boot = Date(timeIntervalSince1970: 1_000_000)
        let now = boot.addingTimeInterval(86_400)
        #expect(RecoveryPolicy.canResume(lastWrite: now.addingTimeInterval(-60), bootTime: boot, now: now))
        #expect(!RecoveryPolicy.canResume(lastWrite: now.addingTimeInterval(-3_600), bootTime: boot, now: now))
        #expect(!RecoveryPolicy.canResume(lastWrite: boot.addingTimeInterval(-10), bootTime: boot, now: boot.addingTimeInterval(60)))
        #expect(!RecoveryPolicy.canResume(lastWrite: nil, bootTime: boot, now: now))
    }
}
