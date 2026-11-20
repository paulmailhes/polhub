import Foundation
import Observation
import Persistence
import Pipeline

/// What the menu bar and « Coup d'œil » show of the recordings, kept up to date by the app: the HUD's presenter
/// passes on what the coordinator decides, the app the rest (« Coup d'œil », 15/11).
///
/// `@Observable`, not `ObservableObject`: a view redraws only for what it reads. `now` changes twice a second; a view
/// that does not read it is never redrawn by it. The menu bar's label reads `shownLabels`, replaced only when what it
/// shows changes (19/11).
@MainActor @Observable
public final class AppModel {
    /// What records, as the coordinator says it. A pause is not in it: see `shownStatus`.
    public var status: RecorderStatus = .idle
    /// The clock, set twice a second by the app (`tick(now:)`). No view reads it in the menu bar: see `shownLabels`.
    public private(set) var now = Date()
    /// The menu bar's label as it shows, with and without « 8 min »: computed at each tick, stored only when it
    /// changes. Measured on 19/11: read from `now`, the label was redrawn twice a second, and macOS redrew the icon on
    /// every screen each time — three quarters of the app's work at rest.
    private var shownLabels = ShownLabels(withMinutes: MenuBarLabel(icon: .columns(.outline, badge: false), text: nil),
                                          plain: MenuBarLabel(icon: .columns(.outline, badge: false), text: nil))

    private struct ShownLabels: Equatable {
        var withMinutes: MenuBarLabel
        var plain: MenuBarLabel
    }
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
    /// The meetings whose summary Paul put away from « Coup d'œil » (its cross, or read once ready): the hero no longer
    /// shows them (Paul, 16/11: « je l'ai déjà traité, j'ai plus besoin qu'il s'affiche »). The latest `reportsKept`,
    /// kept across launches.
    public private(set) var reportsPutAway: Set<UUID> = []
    public static let reportsKept = 50
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var putAwayOrder: [UUID] = []
    private static let putAwayKey = "coupDoeil.comptesRendusRanges"

    public init(isDevelopment: Bool = false, defaults: UserDefaults = .standard) {
        self.isDevelopment = isDevelopment
        self.defaults = defaults
        putAwayOrder = (defaults.stringArray(forKey: Self.putAwayKey) ?? []).compactMap(UUID.init(uuidString:))
        reportsPutAway = Set(putAwayOrder)
    }

    /// A meeting's summary leaves the hero for good.
    public func putAway(report meetingID: UUID) {
        guard !reportsPutAway.contains(meetingID) else { return }
        putAwayOrder.append(meetingID)
        if putAwayOrder.count > Self.reportsKept { putAwayOrder.removeFirst(putAwayOrder.count - Self.reportsKept) }
        reportsPutAway = Set(putAwayOrder)
        defaults.set(putAwayOrder.map(\.uuidString), forKey: Self.putAwayKey)
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

    /// hub watches for meetings: detection on, not paused. The logo is filled then, in outline otherwise (always in
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

    /// Twice a second: the clock; a pause that ran out ends (the coordinator's own pause ends at the same time); the
    /// menu bar's label, when it changed.
    public func tick(now date: Date) {
        now = date
        if let pausedUntil, pausedUntil <= date { self.pausedUntil = nil }
        let labels = ShownLabels(withMinutes: menuBarLabel(meetMinutes: true), plain: menuBarLabel(meetMinutes: false))
        if labels != shownLabels { shownLabels = labels }
    }

    /// The menu bar's label as last shown; `meetMinutes` is Paul's setting (Réglages › Général). At most half a second
    /// behind what the app knows.
    public func shownMenuBarLabel(meetMinutes: Bool) -> MenuBarLabel {
        meetMinutes ? shownLabels.withMinutes : shownLabels.plain
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

    /// An alert, raised again: it replaces the one of its kind (the free space of the last check, `checkDisk`).
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

    /// The free space is worth measuring (a statfs a minute): while a meeting records, or while the disk alert is up.
    public var needsDiskCheck: Bool { isRecording || alerts.contains { $0.kind == .diskLow } }

    /// The free space, measured by the app (`needsDiskCheck`): enough again, the alert goes; still short, it says the
    /// new figure, and comes back if it went during the same meeting. Never its pop-up: the coordinator shows it, once a
    /// meeting.
    public func checkDisk(availableBytes: Int64?) {
        guard let availableBytes else { return }
        guard DiskGuard.isLow(availableBytes: availableBytes) else { return resolve(.diskLow) }
        guard needsDiskCheck else { return }
        let alert = AppAlert.diskLow(freeGB: Int(availableBytes / 1_000_000_000))
        if !alerts.contains(alert) { raise(alert) }
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

    /// The menu bar's label, computed now; the view reads `shownMenuBarLabel`, which changes only when this does.
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
