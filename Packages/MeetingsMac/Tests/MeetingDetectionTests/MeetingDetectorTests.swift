import Domain
import Testing
@testable import MeetingDetection

@Suite struct MeetingDetectorTests {
    func tab(_ id: String = "A", code: String = "abc-defg-hij", loading: Bool = false, focused: Bool = true) -> BrowserTab {
        BrowserTab(windowID: "W", tabID: id, url: "https://meet.google.com/meet/\(code)?authuser=0", title: "Meet – Point",
                   isLoading: loading, isFocused: focused, isPinned: false)
    }

    func candidate(_ id: String = "A", code: String = "abc-defg-hij") -> MeetingCandidate {
        MeetingCandidate(key: "\(id)/\(code)", tabID: id, code: code, authUser: "0", tabTitle: "Meet – Point", source: .tab)
    }

    let mic = MeetingCandidate(key: "mic", tabID: nil, code: nil, authUser: nil, tabTitle: nil, source: .micOnly)
    let manual = MeetingCandidate(key: "manual", tabID: nil, code: nil, authUser: nil, tabTitle: nil, source: .manual)
    let holding = DetectionInput.audio(DiaAudio(holdsMic: true, playing: true))
    let silent = DetectionInput.audio(DiaAudio(holdsMic: false, playing: false))

    /// A detector that recorded since `t = 110`, with Dia holding the microphone.
    func recording() -> MeetingDetector {
        var detector = MeetingDetector()
        _ = detector.handle(holding, at: 99)
        _ = detector.handle(.tabs([tab()], complete: true), at: 100)
        _ = detector.advance(to: 111)
        return detector
    }

    func names(_ effects: [TimedEffect]) -> [String] {
        effects.map {
            switch $0.effect {
            case .prompt: "prompt"
            case .confirm: "confirm"
            case .discard: "discard"
            case .presumedEnd: "presumedEnd"
            case .resume: "resume"
            case .end: "end"
            case .missed: "missed"
            case .alert: "alert"
            case .rememberNever: "rememberNever"
            }
        }
    }

    @Test func promptsWhenAMeetTabAppearsAndConfirmsAfterTenSeconds() {
        var detector = MeetingDetector()
        #expect(detector.handle(.tabs([tab()], complete: true), at: 100) == [TimedEffect(at: 100, effect: .prompt(candidate(), deadline: 110))])
        #expect(detector.advance(to: 111) == [TimedEffect(at: 110, effect: .confirm(candidate()))])
        #expect(detector.phase == .recording(candidate()))
    }

    @Test func aTabWithoutARoomCodeNeverPrompts() {
        var detector = MeetingDetector()
        let landing = BrowserTab(windowID: "W", tabID: "L", url: "https://meet.google.com/landing", title: "Google Meet",
                                 isLoading: false, isFocused: true, isPinned: false)
        let new = BrowserTab(windowID: "W", tabID: "N", url: "https://meet.google.com/meet/new?authuser=0&hs=178", title: "Meet",
                             isLoading: true, isFocused: true, isPinned: false)
        #expect(detector.handle(.tabs([landing, new], complete: true), at: 1).isEmpty)
        #expect(detector.advance(to: 1_000).isEmpty)
    }

    @Test func declineDiscardsAndTheSameTabStaysQuietUntilReloaded() {
        var detector = MeetingDetector()
        _ = detector.handle(.tabs([tab()], complete: true), at: 100)
        #expect(detector.handle(.user(.decline), at: 102) == [TimedEffect(at: 102, effect: .discard(candidate()))])
        for t in stride(from: 110.0, through: 160, by: 10) {
            #expect(detector.handle(.tabs([tab()], complete: true), at: t).isEmpty)
        }
        let reload = detector.handle(.tabs([tab(loading: true)], complete: true), at: 170)
            + detector.handle(.tabs([tab()], complete: true), at: 172)
        #expect(names(reload) == ["prompt"])
    }

    @Test func aTabLeftOpenAfterTheMeetingDoesNotPromptAgain() {
        var detector = MeetingDetector()
        _ = detector.handle(.tabs([tab()], complete: true), at: 100)
        _ = detector.handle(.user(.accept), at: 101)
        #expect(names(detector.handle(.user(.stop), at: 200)) == ["end"])
        for t in stride(from: 210.0, through: 300, by: 10) {
            #expect(detector.handle(.tabs([tab()], complete: true), at: t).isEmpty)
        }
        #expect(detector.handle(.tabs([], complete: true), at: 310).isEmpty)
        #expect(names(detector.handle(.tabs([tab()], complete: true), at: 320)) == ["prompt"])
    }

    @Test func rejoiningInATabLeftOpenPromptsAgain() {
        var detector = recording()
        _ = detector.handle(silent, at: 200)
        _ = detector.handle(.tabs([], complete: true), at: 201)   // fin immédiate : onglet parti, Dia muet
        _ = detector.handle(.tabs([tab()], complete: true), at: 202)
        _ = detector.handle(.user(.accept), at: 203)
        #expect(names(detector.handle(.user(.stop), at: 300)) == ["end"])
        _ = detector.handle(silent, at: 301)
        #expect(detector.handle(.tabs([tab()], complete: true), at: 310).isEmpty)
        #expect(names(detector.handle(holding, at: 320)) == ["prompt"])
    }

    @Test func releasingTheMicForLessThanFiveSecondsChangesNothing() {
        var detector = recording()
        #expect(detector.handle(silent, at: 200).isEmpty)
        #expect(detector.handle(holding, at: 201.5).isEmpty)
        #expect(detector.advance(to: 400).isEmpty)
    }

    @Test func releasingTheMicEndsPresumptivelyAndRetakingItResumes() {
        var detector = recording()
        _ = detector.handle(silent, at: 200)
        #expect(detector.advance(to: 206) == [TimedEffect(at: 205, effect: .presumedEnd(candidate(), endedAt: 200))])
        #expect(detector.handle(.tabs([tab()], complete: true), at: 250).isEmpty)
        #expect(detector.handle(holding, at: 260) == [TimedEffect(at: 260, effect: .resume(candidate()))])
    }

    @Test func theSafetyDelayEndsAPresumedMeetingAtItsPresumedTime() {
        var detector = recording()
        _ = detector.handle(silent, at: 200)
        #expect(detector.advance(to: 801) == [
            TimedEffect(at: 205, effect: .presumedEnd(candidate(), endedAt: 200)),
            TimedEffect(at: 800, effect: .end(candidate(), endedAt: 200, reason: .safetyElapsed)),
        ])
    }

    @Test func closingTheTabWithDiaSilentEndsAtOnce() {
        var detector = recording()
        _ = detector.handle(silent, at: 300)
        #expect(detector.handle(.tabs([], complete: true), at: 302) == [TimedEffect(at: 302, effect: .end(candidate(), endedAt: 300, reason: .tabClosed))])
    }

    @Test func aPartialReadingNeverConcludesTheTabIsGone() {
        var detector = recording()
        _ = detector.handle(silent, at: 300)
        #expect(detector.handle(.tabs([], complete: false), at: 302).isEmpty)
    }

    @Test func diaQuittingEndsTheMeeting() {
        var detector = recording()
        #expect(detector.handle(.diaQuit, at: 300) == [TimedEffect(at: 300, effect: .end(candidate(), endedAt: 300, reason: .diaQuit))])
    }

    @Test func neverCodesDoNotPromptAndNeverForThisLinkRemembers() {
        var never = MeetingDetector(neverCodes: ["abc-defg-hij"])
        #expect(never.handle(.tabs([tab()], complete: true), at: 1).isEmpty)

        var detector = MeetingDetector()
        _ = detector.handle(.tabs([tab()], complete: true), at: 1)
        #expect(detector.handle(.user(.neverForThisLink), at: 2) == [
            TimedEffect(at: 2, effect: .rememberNever(code: "abc-defg-hij")),
            TimedEffect(at: 2, effect: .discard(candidate())),
        ])
        _ = detector.handle(.tabs([], complete: true), at: 3)
        #expect(detector.handle(.tabs([tab("B")], complete: true), at: 4).isEmpty)
    }

    @Test func threeUnreadableReadingsRaiseOneAlertAndTheMicAloneThenPrompts() {
        var detector = MeetingDetector()
        #expect(detector.handle(.tabsUnavailable("x"), at: 1).isEmpty)
        #expect(detector.handle(.tabsUnavailable("x"), at: 2).isEmpty)
        #expect(detector.handle(.tabsUnavailable("x"), at: 3) == [TimedEffect(at: 3, effect: .alert(.tabsUnreadable))])
        #expect(detector.handle(.tabsUnavailable("x"), at: 4).isEmpty)
        #expect(detector.handle(holding, at: 5).isEmpty)
        #expect(detector.advance(to: 11) == [TimedEffect(at: 10, effect: .prompt(mic, deadline: 20))])
        #expect(detector.handle(.tabs([], complete: true), at: 12) == [TimedEffect(at: 12, effect: .alert(.tabsReadableAgain))])
    }

    @Test func recordNowIsManualAndEndsOnlyOnStop() {
        var detector = MeetingDetector()
        #expect(detector.handle(.user(.recordNow), at: 10) == [TimedEffect(at: 10, effect: .confirm(manual))])
        #expect(detector.handle(silent, at: 20).isEmpty)
        #expect(detector.handle(.diaQuit, at: 50).isEmpty)
        #expect(detector.advance(to: 1_000).isEmpty)
        #expect(detector.handle(.user(.stop), at: 1_100) == [TimedEffect(at: 1_100, effect: .end(manual, endedAt: 1_100, reason: .userStopped))])

        var busy = recording()
        #expect(busy.handle(.user(.recordNow), at: 200).isEmpty)
    }

    // Review Focus 2
    @Test func aSecondMeetTabIsIgnoredDuringAMeeting() {
        var detector = recording()
        let second = tab("B", code: "xyz-abcd-efg", focused: false)
        #expect(detector.handle(.tabs([tab(), second], complete: true), at: 120).isEmpty)
        _ = detector.handle(silent, at: 200)
        let effects = detector.handle(.tabs([second], complete: true), at: 201) + detector.handle(.tabs([second], complete: true), at: 203)
        #expect(names(effects) == ["end", "prompt"])
        if case .prompt(let next, _) = effects.last?.effect { #expect(next.key == "B/xyz-abcd-efg") }
    }

    // Revue finale, Important 3 : sans micro, la réunion vit tant que Dia joue, puis finit 10 min après.
    @Test func aMeetingWhereDiaNeverTookTheMicDoesNotEndOnTheMicRule() {
        var detector = MeetingDetector()
        _ = detector.handle(.audio(DiaAudio(holdsMic: false, playing: true)), at: 99)
        _ = detector.handle(.tabs([tab()], complete: true), at: 100)
        _ = detector.advance(to: 111)
        #expect(detector.advance(to: 1_000).isEmpty)
        _ = detector.handle(silent, at: 1_000)
        #expect(detector.advance(to: 1_601) == [TimedEffect(at: 1_600, effect: .end(candidate(), endedAt: 1_000, reason: .safetyElapsed))])
    }

    // Revue finale, Important 3 : un onglet ouvert sans réunion ne s'enregistre pas pendant des heures.
    @Test func aTabMeetingWhereNothingEverHappensIsDiscarded() {
        var detector = MeetingDetector()
        _ = detector.handle(.tabs([tab()], complete: true), at: 100)
        let effects = detector.advance(to: 400)
        #expect(names(effects) == ["confirm", "discard"])
        #expect(effects.last?.at == 220)
    }

    // Revue finale, Important 3 : au lancement, un onglet déjà ouvert sans le micro est une réunion passée.
    @Test func tabsAlreadyOpenAtLaunchWithoutTheMicDoNotPrompt() {
        var config = DetectorConfig()
        config.ignoreTabsOpenAtLaunch = true
        var quiet = MeetingDetector(config: config)
        #expect(quiet.handle(.tabs([tab()], complete: true), at: 1).isEmpty)
        #expect(names(quiet.handle(holding, at: 5)) == ["prompt"])

        var inCall = MeetingDetector(config: config)
        _ = inCall.handle(holding, at: 1)
        #expect(names(inCall.handle(.tabs([tab()], complete: true), at: 2)) == ["prompt"])
    }

    // Revue finale, Important 5 : deux réunions enchaînées dans deux onglets restent deux réunions.
    @Test func aSecondMeetingInAnotherTabIsItsOwnMeeting() {
        var detector = recording()
        _ = detector.handle(silent, at: 200)
        _ = detector.advance(to: 206)
        let next = tab("B", code: "xyz-abcd-efg", focused: true)
        _ = detector.handle(.tabs([tab(focused: false), next], complete: true), at: 250)
        #expect(detector.handle(holding, at: 260) == [
            TimedEffect(at: 260, effect: .end(candidate(), endedAt: 200, reason: .nextMeeting)),
            TimedEffect(at: 260, effect: .prompt(candidate("B", code: "xyz-abcd-efg"), deadline: 270)),
        ])

        // Within the grace too: A hung up, B's waiting room takes the microphone two seconds later.
        var quick = recording()
        _ = quick.handle(silent, at: 200)
        _ = quick.handle(.tabs([tab(focused: false), next], complete: true), at: 201)
        #expect(names(quick.handle(holding, at: 202)) == ["end", "prompt"])
    }

    @Test func diaQuittingAfterThePresumedEndKeepsThePresumedTime() {
        var detector = recording()
        _ = detector.handle(silent, at: 200)
        _ = detector.advance(to: 206)
        #expect(detector.handle(.diaQuit, at: 300) == [TimedEffect(at: 300, effect: .end(candidate(), endedAt: 200, reason: .diaQuit))])
    }

    // Revue finale, Critique 1 : un seul échec de lecture ne déclenche rien.
    @Test func oneUnreadableReadingDoesNotStartTheFallback() {
        var detector = MeetingDetector()
        _ = detector.handle(.tabs([tab()], complete: true), at: 100)
        _ = detector.handle(.user(.decline), at: 101)
        _ = detector.handle(holding, at: 102)
        let effects = detector.handle(.tabsUnavailable("x"), at: 400) + detector.advance(to: 1_000)
        #expect(!names(effects).contains("prompt") && !names(effects).contains("confirm"))
    }

    // Revue finale, Critique 1 : le pop-up du repli n'est jamais daté du passé.
    @Test func theFallbackNeverPromptsInThePast() {
        var detector = MeetingDetector()
        _ = detector.handle(holding, at: 5)
        _ = detector.handle(.tabsUnavailable("x"), at: 100)
        _ = detector.handle(.tabsUnavailable("x"), at: 101)
        #expect(names(detector.handle(.tabsUnavailable("x"), at: 102)) == ["alert"])
        #expect(detector.advance(to: 108) == [TimedEffect(at: 107, effect: .prompt(mic, deadline: 117))])
    }

    // Revue finale, Critique 1 : un appel refusé reste refusé quand les onglets deviennent illisibles.
    @Test func aRefusedCallStaysRefusedWhenTabsBecomeUnreadable() {
        var detector = MeetingDetector()
        _ = detector.handle(.tabs([tab()], complete: true), at: 100)
        _ = detector.handle(.user(.decline), at: 101)
        _ = detector.handle(holding, at: 102)
        var effects: [TimedEffect] = []
        for t in [200.0, 201, 202, 203] { effects += detector.handle(.tabsUnavailable("x"), at: t) }
        effects += detector.advance(to: 1_000)
        #expect(!names(effects).contains("prompt"))
    }

    // Revue finale, Critique 1 : « Arrêter » sur une réunion au micro seul ne la relance pas.
    @Test func stoppingAMicOnlyMeetingDoesNotRestartIt() {
        var detector = MeetingDetector()
        _ = detector.handle(holding, at: 5)
        for t in [10.0, 11, 12] { _ = detector.handle(.tabsUnavailable("x"), at: t) }
        _ = detector.advance(to: 18)
        _ = detector.handle(.user(.accept), at: 18)
        #expect(names(detector.handle(.user(.stop), at: 50)) == ["end"])
        #expect(!names(detector.advance(to: 200)).contains("prompt"))
        _ = detector.handle(silent, at: 210)
        _ = detector.handle(holding, at: 220)
        #expect(names(detector.advance(to: 226)) == ["prompt"])
    }

    @Test func tenMinutesOfMicWithAMeetTabAndNoRecordingIsAMissedMeeting() {
        var detector = MeetingDetector()
        _ = detector.handle(.tabs([tab()], complete: true), at: 100)
        _ = detector.handle(.user(.decline), at: 101)
        _ = detector.handle(holding, at: 102)
        _ = detector.handle(.tabs([tab()], complete: true), at: 110)
        #expect(detector.advance(to: 702) == [TimedEffect(at: 702, effect: .missed(candidate(), reason: .declined))])
        #expect(detector.advance(to: 2_000).isEmpty)
    }

    @Test func pauseSuppressesPromptsUntilItsTime() {
        var detector = MeetingDetector()
        #expect(detector.handle(.user(.pause(until: 500)), at: 0).isEmpty)
        #expect(detector.handle(.tabs([tab()], complete: true), at: 100).isEmpty)
        #expect(names(detector.handle(.tabs([tab()], complete: true), at: 501)) == ["prompt"])
    }
}
