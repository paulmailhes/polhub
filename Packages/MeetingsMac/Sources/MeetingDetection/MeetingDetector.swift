import Domain
import Foundation

/// Decides when a meeting starts and ends, from readings of Dia. Pure: no clock, no input or output. The
/// caller stamps each input with a time in continuous seconds and carries out the effects. The rules are
/// those of the step 1 plan (R1 to R16), measured on the phase 0 guided call.
public struct MeetingDetector: Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case prompting(MeetingCandidate)
        case recording(MeetingCandidate)
        case presumedEnded(MeetingCandidate, endedAt: Double)
    }

    public private(set) var phase: Phase = .idle
    let config: DetectorConfig
    private var neverCodes: Set<String>

    // What Dia does.
    private var audio = DiaAudio(holdsMic: false, playing: false)
    private var micHeldSince: Double?
    private var micReleasedAt: Double?
    private var lastTabs: [BrowserTab] = []
    private var lastReadingComplete = false
    private var tabsUnreadable = false
    private var failuresInARow = 0
    private var alerted = false

    private var unreadableSince: Double?
    private var quietSince: Double?
    private var micRetakenAt: Double?
    private var releaseBeforeRetake: Double?
    private var sawFirstReading = false

    // The current meeting.
    private var promptDeadline: Double?
    private var promptedAt: Double?
    private var micHeldDuringMeeting = false
    private var everActiveInMeeting = false

    // Memory of keys.
    private var declined: Set<String> = []
    private var consumed: Set<String> = []
    private var stopped: Set<String> = []
    private var missedReported: Set<String> = []
    private var missedWatch: (candidate: MeetingCandidate, since: Double)?
    private var pausedUntil: Double?

    public init(config: DetectorConfig = .init(), neverCodes: Set<String> = []) {
        self.config = config
        self.neverCodes = neverCodes
    }

    /// Lets the deadlines due before `time` fall in order, then handles the input.
    public mutating func handle(_ input: DetectionInput, at time: Double) -> [TimedEffect] {
        var effects = advance(to: time)
        effects += apply(input, at: time)
        effects += evaluate(at: time)
        watchForMissedMeeting(at: time)
        return effects
    }

    /// Lets every deadline due up to `time` fall, each at its own time.
    public mutating func advance(to time: Double) -> [TimedEffect] {
        var effects: [TimedEffect] = []
        var fired = 0
        while let (due, deadline) = nextDeadline(), due <= time {
            effects += fire(deadline, at: due)
            effects += evaluate(at: due)
            watchForMissedMeeting(at: due)
            // Each deadline changes the state it comes from; this bound only guards against a future rule
            // that would not.
            fired += 1
            if fired > 100 { break }
        }
        return effects
    }

    // MARK: - Deadlines

    private enum Deadline {
        case countdown, weakEnd, safety, fallback, missed, pauseEnd, noSound, silence
    }

    private func nextDeadline() -> (Double, Deadline)? {
        var due: [(Double, Deadline)] = []
        switch phase {
        case .prompting:
            if let promptDeadline { due.append((promptDeadline, .countdown)) }
        case .recording(let candidate):
            if candidate.source != .manual, micHeldDuringMeeting, !audio.holdsMic, let micReleasedAt {
                due.append((micReleasedAt + config.micReleaseGraceSeconds, .weakEnd))
            }
            // A tab meeting without the microphone: nothing at all for two minutes is no meeting; a meeting
            // only heard (Dia playing) ends ten minutes after Dia fell silent.
            if candidate.source == .tab, !micHeldDuringMeeting {
                if !everActiveInMeeting, let promptedAt {
                    due.append((promptedAt + config.noSoundSeconds, .noSound))
                } else if everActiveInMeeting, !audio.playing, !audio.holdsMic, let quietSince {
                    due.append((quietSince + config.safetySeconds, .silence))
                }
            }
        case .presumedEnded(_, let endedAt):
            due.append((endedAt + config.safetySeconds, .safety))
        case .idle:
            // The countdown of the fallback starts when both are true, never earlier (review, Critical 1).
            if let unreadableSince, audio.holdsMic, !declined.contains("mic"), let micHeldSince, pausedUntil == nil {
                due.append((max(micHeldSince, unreadableSince) + config.fallbackMicSeconds, .fallback))
            }
        }
        if let missedWatch, !missedReported.contains(missedWatch.candidate.key) {
            due.append((missedWatch.since + config.missedAfterSeconds, .missed))
        }
        if let pausedUntil { due.append((pausedUntil, .pauseEnd)) }
        return due.min { $0.0 < $1.0 }
    }

    private mutating func fire(_ deadline: Deadline, at time: Double) -> [TimedEffect] {
        switch (deadline, phase) {
        case (.countdown, .prompting(let candidate)):
            return confirm(candidate, at: time)
        case (.weakEnd, .recording(let candidate)):
            let endedAt = micReleasedAt ?? time
            phase = .presumedEnded(candidate, endedAt: endedAt)
            return [TimedEffect(at: time, effect: .presumedEnd(candidate, endedAt: endedAt))]
        case (.safety, .presumedEnded(let candidate, let endedAt)):
            return finish(candidate, endedAt: endedAt, reason: .safetyElapsed, at: time)
        case (.fallback, .idle):
            return prompt(.micOnly, at: time)
        case (.noSound, .recording(let candidate)):
            let stale = tabIsPresent(candidate)
            let effects = discard(candidate, at: time)
            if stale { consumed.insert(candidate.key) }
            return effects
        case (.silence, .recording(let candidate)):
            return finish(candidate, endedAt: quietSince ?? time, reason: .safetyElapsed, at: time)
        case (.missed, _):
            guard let watch = missedWatch else { return [] }
            missedReported.insert(watch.candidate.key)
            return [TimedEffect(at: time, effect: .missed(watch.candidate, reason: missReason(for: watch.candidate, at: time)))]
        case (.pauseEnd, _):
            pausedUntil = nil
            return []
        default:
            return []
        }
    }

    // MARK: - Inputs

    private mutating func apply(_ input: DetectionInput, at time: Double) -> [TimedEffect] {
        switch input {
        case .audio(let new):
            let wasActive = audio.holdsMic || audio.playing
            let isActive = new.holdsMic || new.playing
            if isActive, !wasActive { quietSince = nil } else if !isActive, wasActive { quietSince = time }
            if isActive, isInAMeeting { everActiveInMeeting = true }
            if new.holdsMic, !audio.holdsMic {
                micHeldSince = time
                releaseBeforeRetake = micReleasedAt
                micRetakenAt = time
                micReleasedAt = nil
                // Dia takes the microphone again in a tab left open after a meeting: Paul rejoined (R5).
                for key in lastTabs.compactMap({ MeetingCandidate.of($0)?.key }) {
                    consumed.remove(key)
                    stopped.remove(key)
                }
            } else if !new.holdsMic, audio.holdsMic {
                micReleasedAt = time
                micHeldSince = nil
                declined.remove("mic")
            }
            audio = new
            if new.holdsMic, isInAMeeting { micHeldDuringMeeting = true }
            return []

        case .tabs(let tabs, let complete):
            var effects: [TimedEffect] = []
            failuresInARow = 0
            tabsUnreadable = false
            unreadableSince = nil
            if alerted {
                alerted = false
                effects.append(TimedEffect(at: time, effect: .alert(.tabsReadableAgain)))
            }
            lastTabs = tabs
            lastReadingComplete = complete
            if complete {
                // A key is forgotten once its tab is gone (R5).
                let present = Set(tabs.compactMap { MeetingCandidate.of($0)?.key })
                // At launch, a room tab already open while Dia holds no microphone is a past meeting.
                if config.ignoreTabsOpenAtLaunch, !sawFirstReading, !audio.holdsMic {
                    consumed.formUnion(present)
                }
                sawFirstReading = true
                declined = declined.filter { present.contains($0) || $0 == "mic" }
                consumed = consumed.intersection(present)
                stopped = stopped.intersection(present)
            }
            // A reload is a fresh start for its tab (R5).
            for key in tabs.filter(\.isLoading).compactMap({ MeetingCandidate.of($0)?.key }) {
                declined.remove(key)
                consumed.remove(key)
                stopped.remove(key)
            }
            return effects

        case .tabsUnavailable:
            // One failed reading (an osascript timeout) proves nothing: only three in a row do.
            failuresInARow += 1
            guard failuresInARow >= config.failuresBeforeAlert else { return [] }
            tabsUnreadable = true
            if unreadableSince == nil {
                unreadableSince = time
                // A call Paul refused, stopped or already recorded stays so when the tabs go blind.
                let lastKnown = lastTabs.compactMap(MeetingCandidate.of)
                if lastKnown.contains(where: {
                    declined.contains($0.key) || stopped.contains($0.key) || consumed.contains($0.key) || neverCodes.contains($0.code ?? "")
                }) {
                    declined.insert("mic")
                }
            }
            guard !alerted else { return [] }
            alerted = true
            return [TimedEffect(at: time, effect: .alert(.tabsUnreadable))]

        case .diaQuit:
            var effects: [TimedEffect] = []
            switch phase {
            case .prompting(let candidate):
                effects = discard(candidate, at: time)
            case .recording(let candidate):
                if candidate.source != .manual {
                    effects = finish(candidate, endedAt: time, reason: .diaQuit, at: time, tabStillOpen: false)
                }
            case .presumedEnded(let candidate, let endedAt):
                effects = finish(candidate, endedAt: endedAt, reason: .diaQuit, at: time, tabStillOpen: false)
            case .idle:
                break
            }
            if audio.holdsMic { micReleasedAt = time }
            audio = DiaAudio(holdsMic: false, playing: false)
            micHeldSince = nil
            lastTabs = []
            lastReadingComplete = false
            return effects

        case .user(let action):
            return apply(action, at: time)
        }
    }

    private mutating func apply(_ action: UserAction, at time: Double) -> [TimedEffect] {
        switch (action, phase) {
        case (.accept, .prompting(let candidate)):
            return confirm(candidate, at: time)
        case (.decline, .prompting(let candidate)), (.stop, .prompting(let candidate)):
            declined.insert(candidate.key)
            return discard(candidate, at: time)
        case (.stop, .recording(let candidate)), (.stop, .presumedEnded(let candidate, _)):
            return finish(candidate, endedAt: time, reason: .userStopped, at: time)
        case (.recordNow, .idle):
            return confirm(.manual, at: time)
        case (.neverForThisLink, .prompting(let candidate)):
            guard let code = candidate.code else { return [] }
            neverCodes.insert(code)
            return [TimedEffect(at: time, effect: .rememberNever(code: code))] + discard(candidate, at: time)
        case (.neverForThisLink, .recording(let candidate)), (.neverForThisLink, .presumedEnded(let candidate, _)):
            guard let code = candidate.code else { return [] }
            neverCodes.insert(code)
            return [TimedEffect(at: time, effect: .rememberNever(code: code))]
                + finish(candidate, endedAt: time, reason: .userStopped, at: time)
        case (.pause(let until), _):
            pausedUntil = until
            return []
        case (.resume, _):
            pausedUntil = nil
            return []
        default:
            return []
        }
    }

    // MARK: - Rules that read the state

    private mutating func evaluate(at time: Double) -> [TimedEffect] {
        var effects: [TimedEffect] = []
        switch phase {
        case .prompting(let candidate):
            if candidate.source == .tab, tabIsGone(candidate) {   // R4
                effects += discard(candidate, at: time)
            }
        case .recording(let candidate), .presumedEnded(let candidate, _):
            if candidate.source == .tab, micRetakenAt == time, let next = otherTabCandidate(than: candidate),
               next.tab.isFocused, !tabIsFocused(candidate) {
                // Dia took the microphone again for a meeting in another tab, in front: that is a new
                // meeting, not the previous one going on (review, Important 5).
                var endedAt = releaseBeforeRetake ?? time
                if case .presumedEnded(_, let presumed) = phase { endedAt = presumed }
                effects += finish(candidate, endedAt: endedAt, reason: .nextMeeting, at: time)
            } else if candidate.source == .tab, tabIsGone(candidate), !audio.holdsMic, !audio.playing {   // R8
                let endedAt = micHeldDuringMeeting ? (micReleasedAt ?? time) : time
                effects += finish(candidate, endedAt: endedAt, reason: .tabClosed, at: time, tabStillOpen: false)
            } else if case .presumedEnded = phase, audio.holdsMic,
                      candidate.source != .tab || tabIsPresent(candidate) {   // R7
                phase = .recording(candidate)
                effects.append(TimedEffect(at: time, effect: .resume(candidate)))
            }
        case .idle:
            break
        }
        if case .idle = phase, !isPaused(at: time), !tabsUnreadable, let candidate = nextTabCandidate() {   // R1
            effects += prompt(candidate, at: time)
        }
        return effects
    }

    /// The Meet tab to prompt for: a room, neither « jamais », nor declined, nor already recorded; the
    /// tab in front first.
    private func nextTabCandidate() -> MeetingCandidate? {
        let candidates = lastTabs.compactMap { tab in MeetingCandidate.of(tab).map { (tab, $0) } }
            .filter { _, candidate in
                !neverCodes.contains(candidate.code ?? "") && !declined.contains(candidate.key) && !consumed.contains(candidate.key)
            }
        return (candidates.first { $0.0.isFocused } ?? candidates.first)?.1
    }

    /// Another room tab that could prompt, the one in front first.
    private func otherTabCandidate(than current: MeetingCandidate) -> (tab: BrowserTab, candidate: MeetingCandidate)? {
        let others = lastTabs.compactMap { tab in MeetingCandidate.of(tab).map { (tab: tab, candidate: $0) } }
            .filter { $0.candidate.key != current.key }
            .filter { !neverCodes.contains($0.candidate.code ?? "") && !declined.contains($0.candidate.key) && !consumed.contains($0.candidate.key) }
        return others.first { $0.tab.isFocused } ?? others.first
    }

    private func tabIsFocused(_ candidate: MeetingCandidate) -> Bool {
        lastTabs.contains { $0.isFocused && MeetingCandidate.of($0)?.key == candidate.key }
    }

    private func tabIsPresent(_ candidate: MeetingCandidate) -> Bool {
        lastTabs.contains { MeetingCandidate.of($0)?.key == candidate.key }
    }

    /// Only a complete reading proves a tab is gone.
    private func tabIsGone(_ candidate: MeetingCandidate) -> Bool {
        lastReadingComplete && !tabIsPresent(candidate)
    }

    private var isInAMeeting: Bool {
        if case .idle = phase { return false }
        return true
    }

    private func isPaused(at time: Double) -> Bool {
        pausedUntil.map { time < $0 } ?? false
    }

    // MARK: - Transitions

    private mutating func prompt(_ candidate: MeetingCandidate, at time: Double) -> [TimedEffect] {
        let deadline = time + config.countdownSeconds
        phase = .prompting(candidate)
        promptDeadline = deadline
        promptedAt = time
        micHeldDuringMeeting = audio.holdsMic
        everActiveInMeeting = audio.holdsMic || audio.playing
        return [TimedEffect(at: time, effect: .prompt(candidate, deadline: deadline))]
    }

    private mutating func confirm(_ candidate: MeetingCandidate, at time: Double) -> [TimedEffect] {
        phase = .recording(candidate)
        promptDeadline = nil
        micHeldDuringMeeting = micHeldDuringMeeting || audio.holdsMic
        return [TimedEffect(at: time, effect: .confirm(candidate))]
    }

    private mutating func discard(_ candidate: MeetingCandidate, at time: Double) -> [TimedEffect] {
        phase = .idle
        promptDeadline = nil
        micHeldDuringMeeting = false
        return [TimedEffect(at: time, effect: .discard(candidate))]
    }

    /// A tab left open after its meeting does not prompt again (R5); one that is gone needs no such memory.
    private mutating func finish(
        _ candidate: MeetingCandidate, endedAt: Double, reason: EndReason, at time: Double, tabStillOpen: Bool? = nil
    ) -> [TimedEffect] {
        phase = .idle
        promptDeadline = nil
        micHeldDuringMeeting = false
        if candidate.source == .tab, tabStillOpen ?? tabIsPresent(candidate) {
            consumed.insert(candidate.key)
            if reason == .userStopped { stopped.insert(candidate.key) }
        }
        // « Arrêter » on a meeting found by the microphone alone holds until Dia lets go of it.
        if candidate.source == .micOnly, reason == .userStopped { declined.insert("mic") }
        return [TimedEffect(at: time, effect: .end(candidate, endedAt: endedAt, reason: reason))]
    }

    // MARK: - Missed meetings (R14)

    /// Dia holds the microphone with a Meet tab open (or tabs unreadable) and nothing records.
    private mutating func watchForMissedMeeting(at time: Double) {
        guard case .idle = phase, audio.holdsMic else {
            missedWatch = nil
            return
        }
        let candidate: MeetingCandidate? = tabsUnreadable
            ? .micOnly
            : lastTabs.compactMap(MeetingCandidate.of).first { !neverCodes.contains($0.code ?? "") }
        guard let candidate else {
            missedWatch = nil
            return
        }
        if missedWatch?.candidate.key != candidate.key {
            missedWatch = (candidate, time)
        }
    }

    private func missReason(for candidate: MeetingCandidate, at time: Double) -> MissReason {
        if declined.contains(candidate.key) || stopped.contains(candidate.key) { return .declined }
        if isPaused(at: time) { return .paused }
        if tabsUnreadable { return .tabsUnreadable }
        return .notDetected
    }
}
