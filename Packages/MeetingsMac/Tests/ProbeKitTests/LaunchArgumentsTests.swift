import AudioCapture
import Domain
import MeetingDetection
@testable import Observability
import Foundation
import Testing
@testable import ProbeKit

@Suite struct LaunchArgumentsTests {
    @Test func parsesProbeArguments() {
        #expect(LaunchArguments.parse(["Polhub", "--probe", "tabs", "--seconds", "30", "--variant", "whose", "--quit"])
                == ProbeRequest(probe: .tabs, seconds: 30, variant: "whose", quitWhenDone: true))
        #expect(LaunchArguments.parse(["Polhub", "--probe", "mic-holders"])
                == ProbeRequest(probe: .micHolders, seconds: 60, variant: nil, quitWhenDone: false))
        #expect(LaunchArguments.parse(["Polhub", "--probe", "inconnue"]) == nil)
        // The probe of Colin starts from its button only: a command line would skip its guards.
        #expect(LaunchArguments.parse(["Polhub", "--probe", "colin", "--variant", "/tmp/compte"]) == nil)
        #expect(LaunchArguments.parse(["Polhub"]) == nil)
    }

    @Test func everyProbeHasAFrenchTitle() {
        #expect(ProbeID.allCases.count == 11)
        // The probe of Colin has its own button on the Diagnostic page, with its account and its guards: it is not
        // offered in the window of the probes.
        #expect(ProbeID.listed.count == 10)
        #expect(!ProbeID.listed.contains(.colin))
        #expect(ProbeID.tabs.title == "Onglets de Dia")
        #expect(ProbeID.crashWriter.rawValue == "crash-writer")
        #expect(ProbeID.allCases.allSatisfy { !$0.title.isEmpty })
    }
}

@Suite struct TabsProbeTests {
    @Test func samplesCarryTheResultAndTheMeetLink() throws {
        let tab = BrowserTab(windowID: "w", tabID: "t", url: "https://meet.google.com/abc-defg-hij?authuser=1", title: "Meet",
                             isLoading: false, isFocused: true, isPinned: false)
        let ok = TabsProbe.sample(.tabs([tab]), variant: "whose", latency: .milliseconds(12))
        #expect(ok.result == "tabs" && ok.variant == "whose" && ok.errorCode == nil)
        #expect(abs(ok.latencyMs - 12) < 0.001)
        #expect(ok.tabs.first?.link == MeetLink(code: "abc-defg-hij", authUser: "1"))
        #expect(TabsProbe.sample(.browserNotRunning, variant: "loop", latency: .zero).result == "notRunning")
        #expect(TabsProbe.sample(.permissionDenied, variant: "loop", latency: .zero).result == "denied")
        let failed = TabsProbe.sample(.failed(code: -1728, message: "x"), variant: "loop", latency: .zero)
        #expect(failed.result == "failed" && failed.errorCode == -1728 && failed.tabs.isEmpty)
    }
}

@Suite struct MicHoldersProbeTests {
    func proc(_ pid: Int32, app: String?, input: Bool = false, output: Bool = false) -> AudioProcessInfo {
        AudioProcessInfo(objectID: UInt32(pid), pid: pid, bundleID: nil, executablePath: nil, owningAppPath: app,
                         isRunningInput: input, isRunningOutput: output, inputDeviceUIDs: [], outputDeviceUIDs: [])
    }

    @Test func keepsActiveProcessesAndEveryDiaProcess() {
        let kept = MicHoldersProbe.relevant([
            proc(40, app: "/Applications/VoiceInk.app", input: true),
            proc(10, app: "/Applications/Dia.app"),
            proc(30, app: "/Applications/Music.app", output: true),
            proc(20, app: "/Applications/Notes.app"),
            proc(50, app: nil),
        ], diaAppPath: "/Applications/Dia.app")
        #expect(kept.map(\.pid) == [10, 30, 40])
    }
}

@Suite struct CrashWriterProbeTests {
    @Test func lossIsTheGapBetweenLoggedAndReadableFrames() {
        #expect(CrashWriterProbe.lossMilliseconds(framesAppended: 48_000, framesRead: 43_200, sampleRate: 48_000) == 100)
        #expect(CrashWriterProbe.lossMilliseconds(framesAppended: 48_000, framesRead: 48_000, sampleRate: 48_000) == 0)
        #expect(CrashWriterProbe.lossMilliseconds(framesAppended: 48_000, framesRead: 52_800, sampleRate: 48_000) == 0)
    }

    @Test func readsTheLastLoggedCountEvenAfterATruncatedLine() {
        let trace = """
        {"data":{"framesAppended":4800},"kind":"crash-writer","t":"x","up":1}
        {"data":{"error":"x"},"kind":"autre","t":"x","up":2}
        {"data":{"framesAppended":9600},"kind":"crash-writer","t":"x","up":3}
        {"data":{"framesAppe
        """
        #expect(CrashWriterProbe.lastFramesAppended(inTrace: trace) == 9_600)
        #expect(CrashWriterProbe.lastFramesAppended(inTrace: "") == nil)
    }
}

@Suite struct LaunchContextTests {
    @Test func detectsALaunchByTheAgent() {
        #expect(LaunchContext.origin(environment: ["XPC_SERVICE_NAME": "fr.paulmailhes.polhub.relance"]) == .launchd)
        #expect(LaunchContext.origin(environment: ["XPC_SERVICE_NAME": "application.fr.paulmailhes.polhub.123.456"]) == .user)
        #expect(LaunchContext.origin(environment: [:]) == .user)
        #expect(LaunchContext.agentLabel == "fr.paulmailhes.polhub.relance")
    }
}

@Suite struct TestProtocolTests {
    @Test func protocolStepsAreWellFormed() {
        let ids = TestProtocol.call.map(\.id)
        #expect(ids == (1...17).map { String(format: "S%02d", $0) })
        #expect(TestProtocol.call.allSatisfy { !$0.instruction.isEmpty && $0.minSeconds >= 0 })
        #expect(TestProtocol.call.map(\.minSeconds).reduce(0, +) == 795)
    }

    @Test func theCallCoversEveryMeasurementOfTheReport() {
        let text = TestProtocol.call.map(\.instruction).joined(separator: "\n")
        for needle in ["salle d'attente", "Coupe ton micro", "Silence complet", "VoiceInk", "plein écran", "Recharge",
                       "haut-parleurs", "AirPods", "Raccroche", "vidéo", "micro coupé"] {
            #expect(text.contains(needle), "le protocole ne couvre plus : \(needle)")
        }
    }
}

@Suite struct TabsProbeFallbackTests {
    @Test func threeFailuresInARowSwitchFromWhoseToLoop() {
        #expect(TabsProbe.variant(after: 2, current: .whose) == .whose)
        #expect(TabsProbe.variant(after: 3, current: .whose) == .loop)
        #expect(TabsProbe.variant(after: 9, current: .loop) == .loop)
    }

    @Test func aPartialReadingKeepsItsTabsAndSaysWhatFailed() {
        let tab = BrowserTab(windowID: "w", tabID: "t", url: "https://meet.google.com/abc-defg-hij", title: "Meet",
                             isLoading: false, isFocused: true, isPinned: false)
        let sample = TabsProbe.sample(.partial(tabs: [tab], failures: [ScriptFailure(code: -1728, message: "x")]),
                                      variant: "whose", latency: .zero)
        #expect(sample.result == "partial" && sample.errorCode == -1728 && sample.tabs.count == 1)
    }
}

@Suite struct ProbeTraceFailureTests {
    struct DiskFull: Error {}

    // Review Focus 5 : une sonde ne continue pas à mesurer dans le vide.
    @Test func aProbeStopsWhenItsTraceCanNoLongerBeWritten() async {
        let healthy = TraceWriter(path: "/essai", sink: { _ in })
        #expect(await TabsProbe.keepGoing(healthy, after: 0.01))
        let broken = TraceWriter(path: "/essai", sink: { _ in throw DiskFull() })
        try? await broken.write(kind: "a", ["n": 1])
        #expect(await TabsProbe.keepGoing(broken, after: 0.01) == false)
    }
}

@Suite struct LaunchDecisionTests {
    let request = ProbeRequest(probe: .tabs, seconds: 10, variant: nil, quitWhenDone: true)

    @Test func decidesWhatACopyDoesWhenItStarts() {
        // A probe asked on the command line always runs, whatever else is running.
        #expect(LaunchDecision.decide(request: request, origin: .user, anotherCopyIsRunning: true) == .runProbe(request))
        // The agent's copy never yields: it is the only one launchd restarts.
        // Remarque différée de la phase 0 : deux copies à l'ouverture de session ; seule celle de launchd reste.
        #expect(LaunchDecision.decide(request: nil, origin: .launchd, anotherCopyIsRunning: true) == .askOtherCopyToQuit)
        #expect(LaunchDecision.decide(request: nil, origin: .launchd, anotherCopyIsRunning: false) == .stayInMenuBar)
        #expect(LaunchDecision.decide(request: nil, origin: .user, anotherCopyIsRunning: true) == .yieldToRunningCopy)
        #expect(LaunchDecision.decide(request: nil, origin: .user, anotherCopyIsRunning: false) == .showWindow)
    }
}

@MainActor @Suite struct ProtocolBoardTests {
    final class Clock { var now = Date(timeIntervalSince1970: 1_000) }

    @Test func aDoubleClickDoesNotSkipAStep() {
        let clock = Clock()
        let board = ProtocolBoard(now: { clock.now })
        _ = board.begin()
        clock.now += 5
        board.next()
        board.next()                                       // the second click of a double-click
        #expect(board.stepIndex == 1)
        clock.now += 1.5
        board.next()
        #expect(board.stepIndex == 2)
    }

    @Test func previousGoesBackOneStepAndNeverBelowTheFirst() {
        let clock = Clock()
        let board = ProtocolBoard(now: { clock.now })
        _ = board.begin()
        board.previous()
        #expect(board.stepIndex == 0)
        clock.now += 5
        board.next()
        clock.now += 5
        board.previous()
        #expect(board.stepIndex == 0)
        #expect(board.stepStartedAt == clock.now)
    }

    @Test func theStreamTellsTheProbeEveryStepReached() async {
        let clock = Clock()
        let board = ProtocolBoard(now: { clock.now })
        let advances = board.begin()
        clock.now += 5
        board.next()
        clock.now += 5
        board.previous()
        board.end()
        var seen: [Int] = []
        for await index in advances { seen.append(index) }
        #expect(seen == [1, 0])
    }
}
