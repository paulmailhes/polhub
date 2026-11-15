import Foundation
import Observation
import Persistence
import Pipeline

/// What the menu bar and « Coup d'œil » show of the recordings, kept up to date by the app: the HUD's presenter
/// passes on what the coordinator decides, the app the rest (« Coup d'œil », 15/11).
///
/// `@Observable`, not `ObservableObject`: a view redraws only for what it reads. `now` changes twice a second for the
/// menu bar's clock; a view that does not read it is never redrawn by it.
@MainActor @Observable
public final class AppModel {
    /// What records, as the coordinator says it. A pause is not in it: see `shownStatus`.
    public var status: RecorderStatus = .idle
    /// The clock of the menu bar, set twice a second by the app (`tick(now:)`). Only the menu bar's label reads it.
    public private(set) var now = Date()
    /// When the meeting just detected records by itself, while the HUD shows its prompt: the one source of the
    /// countdown, for the HUD's pop-up, the menu bar and « Coup d'œil ». Set and cleared by the HUD's presenter.
    public private(set) var promptDeadline: Date?
    /// What puts the recordings at risk, one of each kind, the riskiest first. Each goes by itself once its cause is
    /// gone (`resolve`), not when Paul closes its pop-up.
    public private(set) var alerts: [AppAlert] = []
    /// Until when Paul paused detection; nil once the pause is over (cleared by `tick(now:)`).
    public var pausedUntil: Date?
    /// Dia's tabs are read and fed to the coordinator. Off before launch ends, and in the development build until
    /// switched on.
    public var detectionOn = false
    /// The Meet code of the meeting under way, told by the coordinator; nil without one or without a meeting.
    public private(set) var meetCode: String?
    /// The start of the next event with a Meet link, not started yet (`updateNextMeet`).
    public private(set) var nextMeetAt: Date?
    /// The development build: it never detects on its own, never updates itself, and notifies nothing.
    public let isDevelopment: Bool

    public init(isDevelopment: Bool = false) {
        self.isDevelopment = isDevelopment
    }

    // MARK: - What records

    /// The status as the menu bar shows it: a pause only shows while nothing records.
    public var shownStatus: RecorderStatus {
        if case .idle = status, let pausedUntil { return .paused(until: pausedUntil) }
        return status
    }

    /// From the confirmation to the end: a stop is possible.
    public var isRecording: Bool {
        switch status {
        case .recording, .presumedEnded: true
        default: false
        }
    }

    /// From the prompt to the end of a meeting.
    public var meetingUnderWay: Bool {
        switch status {
        case .prompting, .recording, .presumedEnded: true
        case .idle, .paused: false
        }
    }

    /// Detection is paused (whatever records meanwhile).
    public var isPaused: Bool { pausedUntil != nil }

    /// Polhub watches for meetings: detection on, not paused. The logo is filled then, in outline otherwise (always in
    /// outline in the development build).
    public var isWatching: Bool { detectionOn && !isPaused }

    /// The meeting just detected, while its prompt is on screen: its title and when it records by itself. Nil as
    /// soon as the HUD's prompt closes, so the HUD and « Coup d'œil » show it and hide it together.
    public var prompt: DetectedPrompt? {
        guard case .prompting(let title) = status, let promptDeadline else { return nil }
        return DetectedPrompt(title: title, deadline: promptDeadline)
    }

    /// « Jamais pour ce lien »: only for a meeting with a Meet code, from the prompt to a presumed end.
    public var canForgetLink: Bool { meetCode != nil && meetingUnderWay }

    // MARK: - Set by the app

    /// Twice a second: the clock; a pause that ran out ends (the coordinator's own pause ends at the same time).
    public func tick(now date: Date) {
        now = date
        if let pausedUntil, pausedUntil <= date { self.pausedUntil = nil }
    }

    /// The HUD shows the prompt (or another pop-up replaced it: nil).
    public func setPromptDeadline(_ deadline: Date?) {
        if promptDeadline != deadline { promptDeadline = deadline }
    }

    public func setMeetCode(_ code: String?) {
        if meetCode != code { meetCode = code }
    }

    // MARK: - Alerts

    /// The riskiest alert, the one « Coup d'œil » puts first.
    public var alert: AppAlert? { alerts.first }

    /// A recording is at risk: the logo's badge.
    public var recordingsAtRisk: Bool { !alerts.isEmpty }

    /// An alert, raised again: it replaces the one of its kind (the free space of the last check).
    public func raise(_ alert: AppAlert) {
        var next = alerts.filter { $0.kind != alert.kind }
        next.append(alert)
        alerts = next.sorted { $0.kind < $1.kind }
    }

    /// Its cause is gone.
    public func resolve(_ kind: AppAlert.Kind) {
        guard alerts.contains(where: { $0.kind == kind }) else { return }
        alerts.removeAll { $0.kind == kind }
    }

    /// The free space, measured by the app while the disk alert is up: enough again, it goes.
    public func checkDisk(availableBytes: Int64?) {
        guard let availableBytes, !DiskGuard.isLow(availableBytes: availableBytes) else { return }
        resolve(.diskLow)
    }

    // MARK: - The next Meet

    /// From the calendar's events: the next one with a Meet link that has not started; neither whole days nor the
    /// ones Paul declined. The app calls it when the events change and when that start passes.
    public func updateNextMeet(_ events: [CalendarEventRow], now date: Date) {
        let next = Self.nextMeet(events, now: date)?.startAt
        if nextMeetAt != next { nextMeetAt = next }
    }

    static func nextMeet(_ events: [CalendarEventRow], now: Date) -> CalendarEventRow? {
        events.filter { event in
            event.meetCode != nil && !event.allDay && event.startAt > now
                && event.attendees.first(where: \.isSelf)?.response != "declined"
        }
        .min { $0.startAt < $1.startAt }
    }

    /// The start of the next Meet passed: the following one is to look for.
    public var nextMeetPassed: Bool { nextMeetAt.map { $0 <= now } ?? false }

    /// « 8 min »: the minutes before the next Meet, in the quarter of an hour before it.
    public var minutesToMeet: Int? { MenuBarLabel.minutes(before: nextMeetAt, now: now) }

    /// The menu bar's label; `meetMinutes` is Paul's setting (Réglages › Général).
    public func menuBarLabel(meetMinutes: Bool) -> MenuBarLabel {
        MenuBarLabel.make(status: shownStatus, now: now, promptDeadline: promptDeadline,
                          minutesToMeet: meetMinutes ? minutesToMeet : nil, danger: recordingsAtRisk,
                          watching: detectionOn, isDevelopment: isDevelopment)
    }
}

/// The meeting the HUD asks about: it records by itself at `deadline` unless Paul says no.
public struct DetectedPrompt: Equatable, Sendable {
    public let title: String
    public let deadline: Date

    public init(title: String, deadline: Date) {
        self.title = title
        self.deadline = deadline
    }
}
