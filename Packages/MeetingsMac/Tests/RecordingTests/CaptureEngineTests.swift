import AudioCapture
import Foundation
import MeetingDetection
@testable import Observability
import Testing
@testable import Recording

@Suite struct CaptureVariantTests {
    @Test func parsesTheVariantArgument() {
        #expect(CaptureVariant.parse(nil) == CaptureVariant(kind: .a, anchoredOnOutput: false))
        #expect(CaptureVariant.parse("B") == CaptureVariant(kind: .b, anchoredOnOutput: false))
        #expect(CaptureVariant.parse("c") == CaptureVariant(kind: .c, anchoredOnOutput: false))
        #expect(CaptureVariant.parse("D+sortie") == CaptureVariant(kind: .d, anchoredOnOutput: true))
        #expect(CaptureVariant.parse("A+sortie").label == "A+sortie")
        #expect(CaptureVariant.parse("inconnue") == CaptureVariant(kind: .a, anchoredOnOutput: false))
    }

    @Test func eachVariantTargetsWhatThePlanSays() {
        let dia: [UInt32] = [11, 12]
        #expect(CaptureVariant.parse("A").target(diaProcesses: dia, ownProcess: 99) == .processes([11, 12]))
        #expect(CaptureVariant.parse("B").target(diaProcesses: dia, ownProcess: 99) == .bundleIDs(["company.thebrowser.dia"]))
        #expect(CaptureVariant.parse("C").target(diaProcesses: dia, ownProcess: 99)
                == .bundleIDs(["company.thebrowser.dia", "company.thebrowser.browser.helper"]))
        #expect(CaptureVariant.parse("D").target(diaProcesses: dia, ownProcess: 99) == .globalExcluding([99]))
        #expect(CaptureVariant.parse("D").target(diaProcesses: dia, ownProcess: nil) == .globalExcluding([]))
        #expect(CaptureVariant.parse("A").target(diaProcesses: [], ownProcess: 99) == nil)   // rien à écouter
    }
}

@Suite struct RebuildPolicyTests {
    func event(_ source: String, side: String = "both") -> RouteEvent {
        RouteEvent(source: source, side: side, objectID: 1, detail: "")
    }

    @Test func onlyAChangeOfTheEffectiveRouteRebuildsATrack() {
        #expect(RebuildPolicy.tracks(for: event("tapFormat", side: "output")) == [.autres])
        #expect(RebuildPolicy.tracks(for: event("streamFormat", side: "input")) == [.moi])
        #expect(RebuildPolicy.tracks(for: event("serviceRestarted")) == [.moi, .autres])
        // Logged, never a reason to rebuild on their own: a screen that sleeps, an iPhone that comes near.
        for source in ["deviceList", "defaultInput", "defaultOutput", "deviceAlive"] {
            #expect(RebuildPolicy.tracks(for: event(source)).isEmpty)
        }
        #expect(RebuildPolicy.tracks(for: event("streamFormat", side: "output")).isEmpty)
    }

    // The notification our own rebuild provokes must not start another rebuild, and so on for ever.
    @Test func aTapFormatThatDidNotChangeRebuildsNothing() {
        #expect(RebuildPolicy.tracks(for: event("tapFormat", side: "output"), tapFormatUnchanged: true).isEmpty)
        #expect(RebuildPolicy.tracks(for: event("tapFormat", side: "output"), tapFormatUnchanged: false) == [.autres])
    }

    @Test func aHoleBetweenTwoBuildsIsMeasuredFromTheirAnchors() {
        // Build 1 ends with a buffer ingested at t = 10 s. Build 2's first report describes frame 48 000
        // at t = 11.8 s: its first frame was heard at 10.8 s. The hole lasted 0.8 s.
        let hole = RebuildPolicy.holeSeconds(
            lastOfPrevious: TimeAnchor(frameIndex: 480_000, hostTime: 0, continuousNanos: 10_000_000_000),
            firstOfNext: TimeAnchor(frameIndex: 48_000, hostTime: 0, continuousNanos: 11_800_000_000),
            nextSampleRate: 48_000
        )
        #expect(abs(hole - 0.8) < 0.001)
    }
}

@Suite struct CaptureSupervisorTests {
    func anchor(_ frame: Int64, seconds: Double) -> TimeAnchor {
        TimeAnchor(frameIndex: frame, hostTime: 0, continuousNanos: UInt64(seconds * 1e9))
    }

    @Test func reportsGapsPerBuildAndTheHoleBetweenBuilds() {
        let runs = [
            CaptureEngine.AnchorRun(track: .autres, build: 1, device: nil, sampleRate: 48_000,
                                 anchors: [anchor(0, seconds: 0), anchor(48_000, seconds: 1), anchor(96_000, seconds: 4)]),
            CaptureEngine.AnchorRun(track: .moi, build: 1, device: "A", sampleRate: 24_000, anchors: [anchor(0, seconds: 0), anchor(24_000, seconds: 1)]),
            CaptureEngine.AnchorRun(track: .autres, build: 2, device: nil, sampleRate: 44_100, anchors: [anchor(44_100, seconds: 5.5)]),
            CaptureEngine.AnchorRun(track: .autres, build: 3, device: nil, sampleRate: 48_000, anchors: []),
        ]
        let records = CaptureSupervisor.gapRecords(runs)
        #expect(records.map(\.track) == ["autres", "moi", "autres", "autres"])
        #expect(records[0].gaps.count == 1 && records[0].holeBeforeSeconds == nil)
        #expect(records[1].gaps.isEmpty && records[1].holeBeforeSeconds == nil)
        // Build 2's first frame was heard at 5.5 - 1 = 4.5 s; build 1's last buffer came at 4 s.
        #expect(abs((records[2].holeBeforeSeconds ?? 0) - 0.5) < 0.001)
        #expect(records[3].anchors == 0 && records[3].holeBeforeSeconds == nil)
    }

    // Mesure du 13/11 : deux micros enregistrés en même temps ne laissent aucun trou l'un dans l'autre.
    @Test func theHoleIsMeasuredBetweenBuildsOfTheSameMicrophoneOnly() {
        let runs = [
            CaptureEngine.AnchorRun(track: .moi, build: 1, device: "A", sampleRate: 48_000,
                                 anchors: [anchor(48_000, seconds: 1), anchor(96_000, seconds: 2)]),
            CaptureEngine.AnchorRun(track: .moi, build: 2, device: "B", sampleRate: 48_000, anchors: [anchor(48_000, seconds: 1.2)]),
            CaptureEngine.AnchorRun(track: .moi, build: 3, device: "A", sampleRate: 48_000, anchors: [anchor(48_000, seconds: 3.5)]),
        ]
        let records = CaptureSupervisor.gapRecords(runs)
        #expect(records.map(\.device) == ["A", "B", "A"])
        #expect(records[1].holeBeforeSeconds == nil)
        // Build 3's first frame was heard at 3.5 - 1 = 2.5 s; build 1's last buffer came at 2 s.
        #expect(abs((records[2].holeBeforeSeconds ?? 0) - 0.5) < 0.001)
    }
}

@Suite struct MicrophoneTests {
    func proc(_ pid: Int32, input: Bool, devices: [String]) -> AudioProcessInfo {
        AudioProcessInfo(objectID: UInt32(pid), pid: pid, bundleID: nil, executablePath: nil, owningAppPath: "/Applications/Dia.app",
                         isRunningInput: input, isRunningOutput: false, inputDeviceUIDs: devices, outputDeviceUIDs: [])
    }

    // Mesure du 13/11 : l'auxiliaire de Dia tenait le micro intégré et celui du casque, et Meet envoyait le
    // casque. Le premier de la liste n'était pas le bon : chaque micro tenu est enregistré.
    @Test func everyMicrophoneDiaHoldsIsRecorded() {
        let held = CaptureEngine.microphones(heldBy: [
            proc(1, input: false, devices: ["Stale"]),
            proc(2, input: true, devices: ["BuiltInMicrophoneDevice", "00-11-22-33-44-55:input"]),
            proc(3, input: true, devices: ["BuiltInMicrophoneDevice"]),
        ])
        #expect(held == ["00-11-22-33-44-55:input", "BuiltInMicrophoneDevice"])
        #expect(CaptureEngine.microphones(heldBy: [proc(1, input: false, devices: [])]).isEmpty)
    }

    // Quand Dia lâche un des deux micros, celui qui reste n'est pas coupé.
    @Test func onlyTheMicrophonesThatChangedAreStoppedOrStarted() {
        #expect(MicPlan.reconcile(recording: ["A", "B"], held: ["B", "C"]) == MicPlan(stop: ["A"], start: ["C"]))
        #expect(MicPlan.reconcile(recording: [], held: ["B", "A"]) == MicPlan(stop: [], start: ["A", "B"]))
        #expect(MicPlan.reconcile(recording: ["A"], held: []) == MicPlan(stop: ["A"], start: []))
        #expect(MicPlan.reconcile(recording: ["A"], held: ["A"]) == MicPlan(stop: [], start: []))
    }

    @Test func eachMicrophoneHasItsOwnFolder() {
        #expect(CaptureEngine.folderName(build: 2, device: "00-11-22-33-44-55:input") == "b02-00-11-22-33-44-55-input")
        #expect(CaptureEngine.folderName(build: 12, device: "AppleUSBAudioEngine:KTMicro:2") == "b12-AppleUSBAudioEngine-KTMicro-2")
        #expect(CaptureEngine.folderName(build: 1, device: nil) == "b01")
    }
}

@Suite struct PermissionCheckTests {
    @Test func namesEveryMicrophoneStatus() {
        #expect(PermissionCheck.name(ofMicrophoneStatus: 0) == "notDetermined")
        #expect(PermissionCheck.name(ofMicrophoneStatus: 1) == "restricted")
        #expect(PermissionCheck.name(ofMicrophoneStatus: 2) == "denied")
        #expect(PermissionCheck.name(ofMicrophoneStatus: 3) == "authorized")
    }

    @Test func namesTheAppleEventsAnswer() {
        #expect(PermissionCheck.name(ofAppleEventsStatus: 0) == "granted")
        #expect(PermissionCheck.name(ofAppleEventsStatus: -1743) == "denied")
        #expect(PermissionCheck.name(ofAppleEventsStatus: -1744) == "wouldPrompt")
        #expect(PermissionCheck.name(ofAppleEventsStatus: -600) == "notRunning")
        #expect(PermissionCheck.name(ofAppleEventsStatus: -50) == "error:-50")
    }
}

@Suite struct RebuildSchedulerTests {
    @Test func anEventWaitsForFourHundredQuietMilliseconds() {
        var s = RebuildScheduler()
        s.note(.autres, reason: "tapFormat", at: 0)
        #expect(s.due(at: 0.3).isEmpty)
        s.note(.autres, reason: "tapFormat", at: 0.3)      // a new event restarts the wait
        #expect(s.due(at: 0.6).isEmpty)
        #expect(s.due(at: 0.71).map(\.track) == [.autres])
        #expect(s.due(at: 0.8).isEmpty)                    // handed out once
    }

    @Test func aPolledReasonDoesNotRestartTheWait() {
        var s = RebuildScheduler()
        s.noteIfIdle(.moi, reason: "micRoute", at: 0)
        s.noteIfIdle(.moi, reason: "stall", at: 0.3)
        let due = s.due(at: 0.41)
        #expect(due.map(\.track) == [.moi])
        #expect(due.first?.reason == "micRoute")
    }

    @Test func twoRebuildsOfATrackAreAtLeastTwoSecondsApart() {
        var s = RebuildScheduler()
        s.note(.autres, reason: "a", at: 0)
        #expect(s.due(at: 0.5).count == 1)
        s.finished(.autres, ok: true, at: 1.0)
        s.note(.autres, reason: "b", at: 1.1)
        #expect(s.due(at: 1.6).isEmpty)
        #expect(s.due(at: 3.01).map(\.reason) == ["b"])
    }

    @Test func afterFiveFailuresATrackIsLeftAloneUntilItsRouteChanges() {
        var s = RebuildScheduler()
        var now = 0.0
        for _ in 0..<5 {
            s.noteIfIdle(.autres, reason: "processSet", at: now)
            now += 3
            #expect(s.due(at: now).count == 1)
            s.finished(.autres, ok: false, at: now)
        }
        #expect(s.hasGivenUp(.autres))
        s.noteIfIdle(.autres, reason: "processSet", at: now)
        now += 3
        #expect(s.due(at: now).isEmpty)

        s.routeChanged(.autres)                            // a new route is a new chance
        #expect(!s.hasGivenUp(.autres))
        s.noteIfIdle(.autres, reason: "processSet", at: now)
        now += 3
        #expect(s.due(at: now).count == 1)
    }

    @Test func aSuccessForgetsEarlierFailures() {
        var s = RebuildScheduler()
        var now = 0.0
        for ok in [false, false, false, false, true, false, false, false, false] {
            s.noteIfIdle(.moi, reason: "micRoute", at: now)
            now += 3
            #expect(s.due(at: now).count == 1)
            s.finished(.moi, ok: ok, at: now)
        }
        #expect(!s.hasGivenUp(.moi))
    }

    @Test func aTrackIsStalledOnlyWhenItShouldBeDelivering() {
        #expect(RebuildScheduler.isStalled(secondsSinceReport: 3.1, shouldDeliver: true, secondsSinceWake: nil))
        #expect(!RebuildScheduler.isStalled(secondsSinceReport: 3.1, shouldDeliver: false, secondsSinceWake: nil))
        #expect(!RebuildScheduler.isStalled(secondsSinceReport: 2.9, shouldDeliver: true, secondsSinceWake: nil))
        #expect(!RebuildScheduler.isStalled(secondsSinceReport: nil, shouldDeliver: true, secondsSinceWake: nil))
        // Just after a wake the audio thread has not resumed yet: five seconds of grace.
        #expect(!RebuildScheduler.isStalled(secondsSinceReport: 4, shouldDeliver: true, secondsSinceWake: 2))
        #expect(RebuildScheduler.isStalled(secondsSinceReport: 4, shouldDeliver: true, secondsSinceWake: 6))
    }
}

@Suite struct SilentTrackTests {
    // Review Focus 1 : une piste qui ne livre rien doit laisser une ligne, pas un blanc.
    @Test func aTrackThatDeliversNothingIsReportedNotIgnored() {
        #expect(CaptureEngine.isSilent(secondsSinceReport: 2.1))
        #expect(!CaptureEngine.isSilent(secondsSinceReport: 1.9))
        #expect(!CaptureEngine.isSilent(secondsSinceReport: nil))

        let record = CaptureEngine.silentRecord(track: .autres, device: nil, build: 2, playing: true, lastAnchor: nil)
        #expect(record.track == "autres" && record.build == 2 && record.device == nil)
        #expect(record.stats == LevelStats(frames: 0, exactZeroFrames: 0, rms: 0, peak: 0))
        #expect(record.health == .silentWhileAudible && record.sourceWasPlaying)
        let mic = CaptureEngine.silentRecord(track: .moi, device: "BuiltInMicrophoneDevice", build: 1, playing: false, lastAnchor: nil)
        #expect(mic.health == .silent && mic.device == "BuiltInMicrophoneDevice")
    }
}

@Suite struct ProductionCaptureTests {
    // Mesure 15 de la phase 0 : réagir à la notification de Core Audio, sans attendre le relevé.
    @Test func aProcessDevicesEventOnlySyncsTheMicrophones() {
        #expect(RebuildPolicy.tracks(for: RouteEvent(source: "processDevices", side: "both", objectID: 1, detail: "")) == [.moi])
        #expect(RebuildPolicy.syncsOnly(reason: "processDevices") && RebuildPolicy.syncsOnly(reason: "micRoute"))
        #expect(!RebuildPolicy.syncsOnly(reason: "streamFormat") && !RebuildPolicy.syncsOnly(reason: "stall"))
    }

    // « Enregistrer maintenant » : le micro par défaut, pas ceux de Dia.
    @Test func wholeMacModeRecordsTheDefaultInput() {
        let dia = AudioProcessInfo(objectID: 2, pid: 2, bundleID: nil, executablePath: nil, owningAppPath: "/Applications/Dia.app",
                                   isRunningInput: true, isRunningOutput: false, inputDeviceUIDs: ["casque"], outputDeviceUIDs: [])
        #expect(CaptureEngine.microphones(source: .systemDefault, held: [dia], defaultInput: "BuiltInMicrophoneDevice") == ["BuiltInMicrophoneDevice"])
        #expect(CaptureEngine.microphones(source: .systemDefault, held: [dia], defaultInput: nil).isEmpty)
        #expect(CaptureEngine.microphones(source: .heldByDia, held: [dia], defaultInput: "BuiltInMicrophoneDevice") == ["casque"])
    }

    // Review Focus 1 : après un plantage, une reprise n'écrase aucun segment.
    @Test func buildNumbersContinueAfterExistingFolders() {
        #expect(BuildNumbering.next(existingFolders: ["b01", "b02-casque-input", "b10-micMac"]) == 11)
        #expect(BuildNumbering.next(existingFolders: [".DS_Store"]) == 1)
        #expect(BuildNumbering.next(existingFolders: []) == 1)
    }

    @Test func deviceChangesBecomeEvents() {
        #expect(CaptureSupervisor.changes(previousMics: ["A"], currentMics: ["A", "B"], previousOutput: "X", currentOutput: "X") == [.micsChanged(["A", "B"])])
        #expect(CaptureSupervisor.changes(previousMics: ["A"], currentMics: ["A"], previousOutput: "X", currentOutput: "Y") == [.outputChanged("Y")])
        #expect(CaptureSupervisor.changes(previousMics: [], currentMics: [], previousOutput: nil, currentOutput: nil).isEmpty)
    }
}

@Suite struct QuietSyncTests {
    // Vu sur la sonde de la chaîne complète : une notification sans changement comptait comme une reconstruction.
    @Test func anUnchangedMicrophoneSetIsNotARebuild() {
        #expect(MicPlan.reconcile(recording: ["A"], held: ["A"]).isEmpty)
        #expect(!MicPlan.reconcile(recording: ["A"], held: ["B"]).isEmpty)
        #expect(!MicPlan.reconcile(recording: [], held: ["A"]).isEmpty)
    }
}

@Suite struct ProductionFailureTests {
    // Revue finale, Important 6 : « rien à écouter » et un arrêt lent restent dans la trace.
    @Test func onlyRealFailuresReachThePerson() {
        #expect(!CaptureEngine.isWorthTelling(step: "stop-timeout", message: "x"))
        #expect(!CaptureEngine.isWorthTelling(step: "target", message: "noDiaAudioProcess"))
        #expect(CaptureEngine.isWorthTelling(step: "start", message: "HALError(status: 560227702)"))
        #expect(CaptureEngine.frenchMessage(track: "moi", step: "start", status: 560227702)
            == "La piste « moi » s'est interrompue (démarrage, erreur 560227702).")
    }

    // Revue finale, mineur relevé : pas de notice « Périphériques changés » au début ni à la fin d'une réunion.
    @Test func startingOrLosingTheLastDeviceIsNotAChange() {
        #expect(CaptureSupervisor.changes(previousMics: [], currentMics: ["A"], previousOutput: nil, currentOutput: "X").isEmpty)
        #expect(CaptureSupervisor.changes(previousMics: ["A"], currentMics: [], previousOutput: "X", currentOutput: nil).isEmpty)
        #expect(CaptureSupervisor.changes(previousMics: ["A"], currentMics: ["B"], previousOutput: "X", currentOutput: "X") == [.micsChanged(["B"])])
    }

    // Revue finale, Important 2 : une timeline en panne n'arrête pas l'enregistrement d'une réunion.
    @Test func aMeetingKeepsRecordingWhenItsTimelineFails() async throws {
        struct Down: Error {}
        let trace = TraceWriter(path: "/tmp/x", sink: { _ in throw Down() })
        _ = try? await trace.write(kind: "x", ["a": 1])
        #expect(await trace.failure != nil)
        #expect(await CaptureSupervisor.keepGoing(trace, after: 0, stopOnTraceFailure: false))
        #expect(!(await CaptureSupervisor.keepGoing(trace, after: 0, stopOnTraceFailure: true)))
    }

    @Test func onlySilenceBlamesThePermission() {
        #expect(MeetingRecorder.selfTestFailed(result: "allZero"))
        #expect(!MeetingRecorder.selfTestFailed(result: "nonZero"))
        #expect(!MeetingRecorder.selfTestFailed(result: "startFailed:560227702"))
    }
}
