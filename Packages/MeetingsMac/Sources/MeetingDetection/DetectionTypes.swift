import Domain
import Foundation

/// What Dia does with sound right now: holds a microphone, plays something.
public struct DiaAudio: Equatable, Sendable {
    public var holdsMic: Bool
    public var playing: Bool

    public init(holdsMic: Bool, playing: Bool) {
        self.holdsMic = holdsMic
        self.playing = playing
    }
}

public enum UserAction: Equatable, Sendable {
    case accept, decline, stop, recordNow, neverForThisLink
    case pause(until: Double)
    case resume
}

/// One input of the detector, stamped by the caller with a time in continuous seconds.
public enum DetectionInput: Equatable, Sendable {
    /// A reading of Dia's Meet tabs. `complete: false` when some windows could not be read: an absent tab
    /// then proves nothing.
    case tabs([BrowserTab], complete: Bool)
    case tabsUnavailable(String)
    case audio(DiaAudio)
    case diaQuit
    case user(UserAction)
}

/// What a meeting is attached to: a Meet tab, Dia's microphone alone (tabs unreadable), or a manual start.
public struct MeetingCandidate: Equatable, Sendable {
    public enum Source: String, Sendable {
        case tab, micOnly, manual
    }

    /// `<tabID>/<code>`, `mic` or `manual`.
    public let key: String
    public let tabID: String?
    public let code: String?
    public let authUser: String?
    public let tabTitle: String?
    public let source: Source

    public init(key: String, tabID: String?, code: String?, authUser: String?, tabTitle: String?, source: Source) {
        self.key = key
        self.tabID = tabID
        self.code = code
        self.authUser = authUser
        self.tabTitle = tabTitle
        self.source = source
    }

    public static let micOnly = MeetingCandidate(key: "mic", tabID: nil, code: nil, authUser: nil, tabTitle: nil, source: .micOnly)
    public static let manual = MeetingCandidate(key: "manual", tabID: nil, code: nil, authUser: nil, tabTitle: nil, source: .manual)

    /// The candidate of a Meet tab that opens a room, nil for any other Meet page.
    public static func of(_ tab: BrowserTab) -> MeetingCandidate? {
        guard let link = MeetLink.parse(tab.url), link.isRoom, let code = link.code else { return nil }
        return MeetingCandidate(
            key: "\(tab.tabID)/\(code)", tabID: tab.tabID, code: code, authUser: link.authUser, tabTitle: tab.title, source: .tab
        )
    }
}

public enum MissReason: String, Sendable {
    case declined, paused, tabsUnreadable, notDetected
}

public enum DetectionAlert: Equatable, Sendable {
    case tabsUnreadable, tabsReadableAgain
}

public enum DetectionEffect: Equatable, Sendable {
    /// Show the start pop-up and start the pre-recording.
    case prompt(MeetingCandidate, deadline: Double)
    /// Accepted, or the countdown ran out: the recording is real.
    case confirm(MeetingCandidate)
    /// « Pas cette fois », or the tab closed during the countdown: destroy the pre-recording.
    case discard(MeetingCandidate)
    case presumedEnd(MeetingCandidate, endedAt: Double)
    case resume(MeetingCandidate)
    case end(MeetingCandidate, endedAt: Double, reason: EndReason)
    case missed(MeetingCandidate, reason: MissReason)
    case alert(DetectionAlert)
    case rememberNever(code: String)
}

public struct TimedEffect: Equatable, Sendable {
    public let at: Double
    public let effect: DetectionEffect

    public init(at: Double, effect: DetectionEffect) {
        self.at = at
        self.effect = effect
    }
}

public struct DetectorConfig: Sendable {
    public var countdownSeconds = 10.0
    /// A reload of the tab lets go of the microphone for about one second (phase 0, S09).
    public var micReleaseGraceSeconds = 5.0
    public var safetySeconds = 600.0
    public var fallbackMicSeconds = 5.0
    public var failuresBeforeAlert = 3
    public var missedAfterSeconds = 600.0
    /// A tab meeting in which Dia never held the microphone nor played is discarded after this.
    public var noSoundSeconds = 120.0
    /// At launch, room tabs already open while Dia does not hold the microphone are past meetings.
    public var ignoreTabsOpenAtLaunch = false

    public init() {}
}
