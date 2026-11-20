import Agenda
import Domain
import Foundation
import GoogleKit
import MeetingDetection
import Persistence
import Pipeline
import PolhubDesign
import Summarization
import SwiftUI
import Updates

/// What « Coup d'œil » says (15/11), from what Polhub already holds in memory: the hero, its fixed order and its first
/// line, the two tiles' words, the lines « À régler », the mails to read, the footer's line. Pure: tested on made-up data, without a
/// screen. Nothing here reads the base, the network or the clock: `now` comes from the view's timeline.
enum PanelModel {
    /// Paul's calendar, as Calendrier's: French, weeks from Monday, the Mac's time zone (`Words.calendar`, lot 10, 20/11).
    static var calendar: Calendar { Words.calendar }

    /// How long before an event the hero speaks of it, and how long a summary ready stays in it.
    static let soon: TimeInterval = 15 * 60
    static let readyFor: TimeInterval = 2 * 3_600
    /// The mails the card lists; the others are one click away, in Mails.
    static let mailLimit = 3
    /// « À régler »: a few lines at most, the riskiest first.
    static let issueLimit = 3

    // MARK: - What the hero reads

    /// The meeting as the app knows it (`AppModel`).
    struct Meeting: Equatable {
        var status: RecorderStatus = .idle
        /// Non-nil only while the HUD shows the prompt.
        var prompt: DetectedPrompt?
        var canForgetLink = false
        var meetCode: String?
        var pausedUntil: Date?
    }

    /// The meetings as the library holds them (`MeetingLibrary`).
    struct Meetings: Equatable {
        var rows: [MeetingRow] = []
        var jobs: [UUID: JobRow] = [:]
        var summaryJobs: [UUID: SummaryJobRow] = [:]
        var summaryProgress: [UUID: SummaryProgress] = [:]
        var overviews: [UUID: String] = [:]
        /// Réglages › Réunions › Comptes rendus.
        var summariesOn = true
        /// Why no summary can be made (Apple Intelligence off…).
        var unavailable: String?
        /// The summaries Paul put away (`AppModel.reportsPutAway`): never in the hero again.
        var putAway: Set<UUID> = []
    }

    // MARK: - The hero

    /// The one thing that matters now, the first true in this order.
    enum Hero: Equatable {
        /// The HUD asks; the panel doubles it, same countdown.
        case detected(title: String, deadline: Date, canForget: Bool)
        case recording(title: String, since: Date, detail: String?, meetingID: UUID?)
        /// The meeting seems over: it stops by itself at `stopsAt`, unless someone speaks again.
        case presumedEnded(title: String, stopsAt: Date?, meetingID: UUID?, canForget: Bool)
        /// An event in a quarter of an hour or less, or a Meet started and not recorded.
        case upcoming(Upcoming)
        /// Detection paused; `missed`, a Meet that falls in the pause and will not record.
        case paused(until: Date, missed: CalendarEventRow?)
        case report(Report)
        /// Otherwise the day: its date, then « Libre jusqu'à 16:30 » or « Plus rien aujourd'hui ».
        case day(title: String, line: String?)

        /// The kind, for the fade from one hero to the next.
        var kind: String {
            switch self {
            case .detected: "detected"
            case .recording: "recording"
            case .presumedEnded: "presumedEnded"
            case .upcoming(let upcoming): "upcoming-\(upcoming.event.id)-\(upcoming.started)"
            case .paused: "paused"
            case .report(let report): "report-\(report.meetingID)-\(report.isPreparing)"
            case .day: "day"
            }
        }

        /// The event the hero shows: the Calendrier tile leaves it out.
        var eventID: String? {
            if case .upcoming(let upcoming) = self { return upcoming.event.id }
            return nil
        }
    }

    struct Upcoming: Equatable {
        var event: CalendarEventRow
        /// It started and nothing records.
        var started: Bool
        /// « 15:30 – 16:00 · Refonte du site · 3 invités ».
        var detail: String
        /// Detection is paused past its start: it will not record by itself.
        var pausedThrough: Bool
    }

    /// A meeting's summary on its way, or ready (for two hours), or failed (for two hours).
    struct Report: Equatable {
        enum Stage: Equatable {
            case transcriptionWaiting
            case transcribing(Double)
            case summaryWaiting
            case summarizing(SummaryProgress?)
            case ready(overview: String)
            /// Transcribed, and no summary to come: off, unavailable (`reason`), or too few words.
            case transcriptReady(reason: String?)
            case transcriptionFailed(String)
            case summaryFailed(String)
        }

        var meetingID: UUID
        var title: String
        /// The meeting's length.
        var seconds: Int?
        var stage: Stage
        /// When it became ready, or failed.
        var since: Date?
        /// A summary comes after the transcription.
        var summaryToCome: Bool

        var isPreparing: Bool {
            switch stage {
            case .transcriptionWaiting, .transcribing, .summaryWaiting, .summarizing: true
            default: false
            }
        }

        /// From 0 to 1 while a bar shows: the transcription, then the summary's parts.
        var progress: Double? {
            switch stage {
            case .transcribing(let value): value
            case .summarizing(let progress?): progress.fraction
            default: nil
            }
        }

        /// « Transcription 58 % », « Compte rendu : partie 3 sur 5 », « Compte rendu prêt »… (lot 10, 20/11: « Résumé » is
        /// only the first part of a compte rendu; a failure is a sentence).
        var stageText: String {
            switch stage {
            case .transcriptionWaiting: "Transcription en attente"
            case .transcribing(let value): "Transcription " + Words.percent(value)
            case .summaryWaiting: "Compte rendu en attente"
            case .summarizing(let progress?) where progress.finishing: "Compte rendu : dernière étape"
            case .summarizing(let progress?) where progress.total > 1: "Partie \(min(progress.done + 1, progress.total)) sur \(progress.total)"
            case .summarizing: "Compte rendu en cours d'écriture"
            case .ready: "Compte rendu prêt"
            case .transcriptReady: "Transcription prête"
            case .transcriptionFailed: "La transcription a échoué."
            case .summaryFailed: "Le compte rendu n'a pas pu se faire."
            }
        }
    }

    /// The first true, in the fixed order of the brief: detected, recording, presumed end, an event in 15 min or a Meet
    /// started and not recorded, paused, a summary on its way or ready, the day. `events` is nil without the agenda,
    /// `meetings` nil before the library is ready.
    static func hero(meeting: Meeting, events: [CalendarEventRow]?, projects: [ProjectRow] = [], meetings: Meetings?,
                     now: Date, calendar: Calendar = calendar) -> Hero {
        if let prompt = meeting.prompt {
            return .detected(title: prompt.title, deadline: prompt.deadline, canForget: meeting.canForgetLink)
        }
        let rows = meetings?.rows ?? []
        switch meeting.status {
        case .recording(let title, let since):
            let row = rows.first { $0.status == .recording || $0.status == .pending }
            let found = events.flatMap { event(code: meeting.meetCode, in: $0, now: now) }
            return .recording(title: title, since: since, detail: found.map { recordingDetail($0, row: row, projects: projects) },
                              meetingID: row?.id)
        case .presumedEnded(let title):
            let row = rows.first { $0.status == .presumedEnded }
            return .presumedEnded(title: title, stopsAt: row?.presumedEndAt.map { $0.addingTimeInterval(DetectorConfig().safetySeconds) },
                                  meetingID: row?.id, canForget: meeting.canForgetLink)
        default:
            break
        }
        if let events, let found = upcoming(events, recorded: rows, now: now, calendar: calendar) {
            let paused = meeting.pausedUntil.map { $0 > max(found.event.startAt, now) } ?? false
            return .upcoming(Upcoming(event: found.event, started: found.started,
                                      detail: eventDetail(found.event, projects: projects, calendar: calendar), pausedThrough: paused))
        }
        if let until = meeting.pausedUntil {
            let missed = events.flatMap { events in
                today(events, now: now, calendar: calendar).filter { $0.meetCode != nil && $0.startAt < until }.min { $0.startAt < $1.startAt }
            }
            return .paused(until: until, missed: missed)
        }
        if let meetings, let report = report(meetings, now: now) {
            return .report(report)
        }
        // « Dimanche 15 novembre » (`Words.fullDate`, lot 10, 20/11).
        return .day(title: Words.capitalizedFirst(Words.fullDate(now, now: now, calendar: calendar)),
                    line: events.map { dayLine($0, now: now, calendar: calendar) })
    }

    /// Today's events not over yet: neither whole days nor the ones Paul declined (as Accueil and the sidebar).
    static func today(_ events: [CalendarEventRow], now: Date, calendar: Calendar = calendar) -> [CalendarEventRow] {
        events.filter { event in
            !event.allDay && event.endAt > now && calendar.isDate(event.startAt, inSameDayAs: now) && !declined(event)
        }
        .sorted { $0.startAt < $1.startAt }
    }

    static func declined(_ event: CalendarEventRow) -> Bool {
        event.attendees.first(where: \.isSelf)?.response == "declined"
    }

    /// A Meet that started a moment ago (late, or not detected), else an event in a quarter of an hour, else a Meet
    /// started longer ago and still not recorded. A Meet already recorded (`recorded`, the library's meetings) is not
    /// « pas enregistrée », even once its recording ended inside its slot.
    static func upcoming(_ events: [CalendarEventRow], recorded: [MeetingRow] = [], now: Date, calendar: Calendar = calendar) -> (event: CalendarEventRow, started: Bool)? {
        let left = today(events, now: now, calendar: calendar)
        let live = left.filter { $0.startAt <= now && $0.meetCode != nil && !wasRecorded($0, in: recorded, now: now) }
            .max { $0.startAt < $1.startAt }
        let next = left.first { $0.startAt > now && $0.startAt.timeIntervalSince(now) <= soon }
        if let live, now.timeIntervalSince(live.startAt) <= soon { return (live, true) }
        if let next { return (next, false) }
        return live.map { ($0, true) }
    }

    /// How long before its start a recording counts for an event: the notification of a meeting not recorded looks as
    /// far back (`NotificationHub.tick`).
    static let recordedLead: TimeInterval = 30 * 60

    /// A meeting of the library recorded this event, neither thrown away nor deleted: the same Meet code, started from
    /// half an hour before it; or « Enregistrer » (the whole Mac, without a code) during its slot.
    static func wasRecorded(_ event: CalendarEventRow, in rows: [MeetingRow], now: Date) -> Bool {
        rows.contains { row in
            guard row.deletedAt == nil, row.status != .discarded, row.source != .imported, row.startedAt <= now else { return false }
            if let code = row.meetCode {
                return code == event.meetCode && row.startedAt >= event.startAt.addingTimeInterval(-recordedLead)
            }
            return row.source == .wholeMac && row.startedAt < event.endAt && (row.endedAt ?? now) > event.startAt
        }
    }

    /// The event of the meeting being recorded: the same Meet code, the one under way or the nearest.
    static func event(code: String?, in events: [CalendarEventRow], now: Date) -> CalendarEventRow? {
        guard let code else { return nil }
        let same = events.filter { $0.meetCode == code && !$0.allDay }
        return same.first { $0.startAt.addingTimeInterval(-soon) <= now && $0.endAt >= now }
            ?? same.min { abs($0.startAt.timeIntervalSince(now)) < abs($1.startAt.timeIntervalSince(now)) }
    }

    /// « 15:30 – 16:00 · Refonte du site · 3 invités » (`Words.timeRange`, lot 10, 20/11).
    static func eventDetail(_ event: CalendarEventRow, projects: [ProjectRow], calendar: Calendar = calendar) -> String {
        ([Words.timeRange(from: event.startAt, to: event.endAt, calendar: calendar),
          projectName(event.projectID, in: projects), guests(event)].compactMap { $0 }).joined(separator: " · ")
    }

    /// « Refonte du site · Exemple · 3 invités »: the meeting being recorded, from its event.
    static func recordingDetail(_ event: CalendarEventRow, row: MeetingRow?, projects: [ProjectRow]) -> String {
        [projectName(event.projectID ?? row?.projectID, in: projects), AccountStyle.label(for: event.account), guests(event)]
            .compactMap { $0 }.joined(separator: " · ")
    }

    static func projectName(_ id: UUID?, in projects: [ProjectRow]) -> String? {
        id.flatMap { id in projects.first { $0.id == id }?.name }
    }

    /// « 3 invités »: the others, neither Paul nor a room (`Words.count`, lot 10, 20/11).
    static func guests(_ event: CalendarEventRow) -> String? {
        let count = event.attendees.filter { !$0.isSelf && !$0.isResource }.count
        return count == 0 ? nil : Words.count(count, "invité")
    }

    /// The newest meeting whose summary is on its way; else one ready, or failed, less than two hours ago.
    static func report(_ meetings: Meetings, now: Date) -> Report? {
        let done = meetings.rows.filter { row in
            row.source != .imported && row.deletedAt == nil && !row.status.isUnfinished && row.status != .discarded
                && !meetings.putAway.contains(row.id)
        }
        .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
        for row in done {
            guard let report = report(for: row, in: meetings, now: now) else { continue }
            if report.isPreparing { return report }
            if let since = report.since, now.timeIntervalSince(since) < readyFor { return report }
        }
        return nil
    }

    /// A meeting opened in Polhub's window once transcribed: its summary is read, it leaves the hero. Opened while it
    /// records or is transcribed, it still announces itself once ready.
    static func isRead(opening id: UUID, in meetings: Meetings) -> Bool {
        guard let row = meetings.rows.first(where: { $0.id == id }) else { return false }
        return row.transcribedAt != nil || meetings.overviews[id] != nil
    }

    private static func report(for row: MeetingRow, in meetings: Meetings, now: Date) -> Report? {
        let job = meetings.jobs[row.id], summary = meetings.summaryJobs[row.id]
        let toCome = meetings.summariesOn && meetings.unavailable == nil
        var report = Report(meetingID: row.id, title: row.title, seconds: row.endedAt.map { Int($0.timeIntervalSince(row.startedAt)) },
                            stage: .transcriptionWaiting, since: nil, summaryToCome: toCome)
        switch job?.state {
        case .queued?: return report
        case .running?:
            report.stage = .transcribing(job?.progress ?? 0)
            return report
        case .failed?:
            report.stage = .transcriptionFailed(job?.error ?? "raison inconnue")
            report.since = job?.updatedAt
            return report
        default: break
        }
        guard let transcribedAt = row.transcribedAt ?? job?.finishedAt else { return nil }
        if let overview = meetings.overviews[row.id], summary?.state != .running {
            report.stage = .ready(overview: overview)
            report.since = summary?.state == .done ? summary?.updatedAt : transcribedAt
            return report
        }
        switch summary?.state {
        case .running?:
            report.stage = .summarizing(meetings.summaryProgress[row.id])
        case .queued? where toCome:
            report.stage = .summaryWaiting
        case .failed?:
            report.stage = .summaryFailed(summary?.error ?? "raison inconnue")
            report.since = summary?.updatedAt
        case nil where toCome && now.timeIntervalSince(transcribedAt) < readyFor:
            // The queue takes it at its next turn, within a minute.
            report.stage = .summaryWaiting
        default:
            report.stage = .transcriptReady(reason: meetings.summariesOn ? meetings.unavailable : nil)
            report.since = transcribedAt
        }
        return report
    }

    // MARK: - The hero's first line

    /// The hero's first line (lot 9, 20/11): its words in their own case, as the Accueil writes « Jeudi 19 novembre »
    /// (« DANS 8 MIN » and « ENREGISTRE » were in capitals), and one thing of it in color, never the whole line.
    struct Eyebrow: Equatable {
        /// What carries the color: the symbol of a state (the recording's dot, a problem's icon), or the words of a delay.
        enum Colored: Equatable { case nothing, symbol, words }

        var text: String
        var systemImage: String?
        var tint: Tint.Role?
        var colored: Colored
    }

    static func eyebrow(_ hero: Hero, now: Date) -> Eyebrow {
        switch hero {
        case .detected:
            // Grey, as the logo's outlined circle: nothing records yet (design system v2, 19/11).
            Eyebrow(text: "Réunion détectée", systemImage: "record.circle", tint: nil, colored: .nothing)
        case .recording:
            Eyebrow(text: "Enregistrement", systemImage: "circle.fill", tint: .recording, colored: .symbol)
        case .presumedEnded:
            Eyebrow(text: "Fin de réunion ?", systemImage: "record.circle", tint: .attention, colored: .symbol)
        case .upcoming(let upcoming) where upcoming.started:
            Eyebrow(text: "En cours · pas enregistrée", systemImage: "exclamationmark.circle.fill", tint: .attention, colored: .symbol)
        case .upcoming(let upcoming):
            // « Dans 8 min », its words at attention's color, as « dans 12 min » on the Accueil (`Words.capitalizedFirst`,
            // lot 10, 20/11).
            Eyebrow(text: Words.capitalizedFirst(HomeModel.when(upcoming.event, now: now)), systemImage: "calendar", tint: .attention, colored: .words)
        case .paused:
            Eyebrow(text: "Détection suspendue", systemImage: "pause.circle.fill", tint: nil, colored: .nothing)
        case .report(let report):
            // « Compte rendu », never « Résumé », its first part only; « en échec » for the short form (lot 10, 20/11).
            switch report.stage {
            case .ready: Eyebrow(text: "Compte rendu prêt", systemImage: "checkmark.circle.fill", tint: nil, colored: .nothing)
            case .transcriptReady: Eyebrow(text: "Transcription prête", systemImage: "checkmark.circle.fill", tint: nil, colored: .nothing)
            // A problem colors its icon only: never a colored sentence.
            case .transcriptionFailed: Eyebrow(text: "Transcription en échec", systemImage: "exclamationmark.triangle.fill", tint: .attention, colored: .symbol)
            case .summaryFailed: Eyebrow(text: "Compte rendu impossible", systemImage: "exclamationmark.triangle.fill", tint: .attention, colored: .symbol)
            default: Eyebrow(text: "Compte rendu en cours", systemImage: "sparkles", tint: nil, colored: .nothing)
            }
        case .day(let title, _):
            Eyebrow(text: title, systemImage: nil, tint: nil, colored: .nothing)
        }
    }

    /// « Déjeuner, jusqu'à 13:00 », « Libre jusqu'à 16:30 », « Plus rien aujourd'hui » (`Words.time`, lot 10, 20/11).
    static func dayLine(_ events: [CalendarEventRow], now: Date, calendar: Calendar = calendar) -> String {
        let left = today(events, now: now, calendar: calendar)
        if let current = left.first(where: { $0.startAt <= now }) {
            return "\(current.title), jusqu'à \(Words.time(current.endAt, calendar: calendar))"
        }
        if let next = left.first { return "Libre jusqu'à \(Words.time(next.startAt, calendar: calendar))" }
        return "Plus rien aujourd'hui"
    }

    // MARK: - The tiles

    /// A tile's words: a title and its icon are fixed; the value (15 pt), a detail line (13 pt), a count top right.
    struct Tile: Equatable {
        var value: String
        var detail: String?
        var count: Int?
    }

    /// Calendrier: the next event of today, its title whole, then its time under it (lot 9, 20/11: « 16:30 Revue de… »
    /// was cut on its 161 points); else the next one to come. It never says again what the hero says: the hero's event is
    /// left out (« Ensuite à 17:30 »), and under the day's « Libre jusqu'à 16:30 » the next event's start is not repeated.
    /// The count: the events left today.
    static func calendarTile(_ events: [CalendarEventRow]?, hero: Hero, now: Date, calendar: Calendar = calendar) -> Tile {
        // « Connecter » a Google account, never « Relier » (lot 10, 20/11).
        guard let events else { return Tile(value: "Aucun agenda", detail: "Connecter un compte Google") }
        let leftToday = SidebarCounts.eventsLeftToday(events, now: now, calendar: calendar)
        let count = leftToday > 0 ? leftToday : nil
        let hiding = hero.eventID
        let left = today(events, now: now, calendar: calendar)
        guard let event = left.first(where: { $0.startAt > now && $0.id != hiding }) else {
            let later = events.filter { !$0.allDay && !declined($0) && $0.startAt > now && !calendar.isDate($0.startAt, inSameDayAs: now) }
                .min { $0.startAt < $1.startAt }
            guard let later else { return Tile(value: hiding == nil ? "Rien de prévu" : "Plus rien ensuite", count: count) }
            // A meta at a line's head: « Demain 9:30 », « Lun. 9:30 », « 2 déc. 9:30 » (`Words.shortMoment`, lot 10, 20/11).
            return Tile(value: later.title, detail: Words.capitalizedFirst(Words.shortMoment(later.startAt, now: now, calendar: calendar)),
                        count: count)
        }
        if hiding != nil { return Tile(value: event.title, detail: "Ensuite à \(Words.time(event.startAt, calendar: calendar))", count: count) }
        // The day says « Libre jusqu'à 16:30 » (nothing under way, `dayLine`): that start is the tile's own.
        if case .day = hero, !left.contains(where: { $0.startAt <= now }) { return Tile(value: event.title, count: count) }
        return Tile(value: event.title, detail: Words.timeRange(from: event.startAt, to: event.endAt, calendar: calendar), count: count)
    }

    /// What the Mails tile and card read of the mails.
    struct Mails: Equatable {
        /// The unread threads of the people's inbox (never Notifications), the newest first.
        var unread: [MailThreadRow] = []
        /// At least one mailbox granted the mails.
        var hasMailboxes = false
        /// A mailbox that cannot be read, and why.
        var failure: Failure?

        struct Failure: Equatable {
            var account: String
            var text: String
        }
    }

    /// The people's unread threads of the inbox, the newest first: the mailboxes shown, never Notifications.
    static func unread(_ inbox: [MailThreadRow], hidden: Set<String>, tab: (MailThreadRow) -> MailTab) -> [MailThreadRow] {
        inbox.filter { $0.unread && $0.inInbox && !$0.hidden && !hidden.contains($0.account) && tab($0) == .personnes }
            .sorted { $0.lastMessageAt > $1.lastMessageAt }
    }

    /// Mails: « 5 nouveaux » and the first names of the latest senders, or « Rien de neuf »; a mailbox to reconnect;
    /// « Autoriser les mails » without one. Nothing said twice (lot 9, 20/11): while the card under the tiles lists the mails
    /// (`listed`), their senders are its own; a mailbox to reconnect that « À régler » names (`issues`) is its own too.
    static func mailsTile(_ mails: Mails?, listed: Bool = false, issues: [Issue] = []) -> Tile {
        // The words of Réglages › Comptes Google, never « Relier Gmail » (lot 10, 20/11).
        guard let mails, mails.hasMailboxes else { return Tile(value: "Autoriser les mails", detail: "Réglages › Comptes Google") }
        if let failure = mails.failure, needsReconnecting(failure.text), !issues.contains(where: { $0.id == Issue.account(failure.account) }) {
            return Tile(value: "\(AccountStyle.label(for: failure.account)) déconnecté", detail: "À reconnecter")
        }
        let count = mails.unread.count
        guard count > 0 else { return Tile(value: "Rien de neuf") }
        // « 1 nouveau », « 5 nouveaux » (`Words.count`, lot 10, 20/11).
        let value = Words.count(count, "nouveau", "nouveaux")
        if listed { return Tile(value: value) }
        var names: [String] = []
        for thread in mails.unread {
            let name = firstName(sender(of: thread))
            if !names.contains(name) { names.append(name) }
            if names.count == 2 { break }
        }
        return Tile(value: value, detail: names.joined(separator: ", "))
    }

    // MARK: - « À régler »

    /// A cause that keeps Polhub from working well, and what a click does.
    struct Issue: Equatable, Identifiable {
        enum Action: Equatable {
            /// Réglages › Diagnostic: it shows what is known, never runs a test by itself.
            case diagnostic
            case accounts
            /// `UpdateService.installNow()`, which waits for a quiet moment.
            case installUpdate
        }

        var id: String
        var title: String
        var detail: String?
        var action: Action
        /// What the click does, in the tooltip.
        var help: String

        /// The line of a Google account to reconnect: one per account, for its agenda and its mails.
        static func account(_ email: String) -> String { "account-\(email)" }
    }

    /// What the updates say (`UpdateService`).
    struct Updates: Equatable {
        var state: UpdateService.State = .idle
        /// The newest version published, if newer than this one.
        var latest: String?
        var autoInstall = true
    }

    /// One line per cause, three at most, the riskiest for the recordings first: the alerts (the only ones that put the
    /// badge on the logo), then a Google account to reconnect, then an update that failed or waits for Paul.
    static func issues(alerts: [AppAlert], accounts: [GoogleAccountRow] = [], mailFailure: Mails.Failure? = nil,
                       updates: Updates? = nil) -> [Issue] {
        var issues = alerts.map { alert in
            let words = HUDText.alert(alert)
            return Issue(id: "alert-\(alert.kind.rawValue)", title: words.title, detail: words.message, action: .diagnostic, help: "Ouvrir le Diagnostic")
        }
        let calendarBroken = accounts.filter { $0.lastError.map(needsReconnecting) ?? false }.map(\.email)
        var mailBroken: [String] = []
        if let mailFailure, needsReconnecting(mailFailure.text) { mailBroken.append(mailFailure.account) }
        for email in calendarBroken + mailBroken where !issues.contains(where: { $0.id == Issue.account(email) }) {
            let both = calendarBroken.contains(email) && mailBroken.contains(email)
            // A sentence, its period, as the alerts' lines above it (lot 10, 20/11).
            let detail = both ? "Son agenda et ses mails ne se mettent plus à jour." : calendarBroken.contains(email)
                ? "Son agenda ne se met plus à jour." : "Ses mails ne se mettent plus à jour."
            issues.append(Issue(id: Issue.account(email), title: "Compte \(AccountStyle.label(for: email)) à reconnecter", detail: detail,
                                action: .accounts, help: "Ouvrir Réglages › Comptes Google"))
        }
        if let updates, let version = updates.latest {
            let underWay: [UpdateService.State] = [.waitingForIdle, .downloading, .installing]
            if case .failed = updates.state {
                issues.append(Issue(id: "update", title: "La mise à jour \(version) a échoué", detail: "Nouvel essai dans une heure",
                                    action: .installUpdate, help: "Réessayer au prochain moment calme"))
            } else if !updates.autoInstall, !underWay.contains(updates.state) {
                // A sentence, its period; « désactivée », as the switch of Réglages (lot 10, 20/11: « coupée »).
                issues.append(Issue(id: "update", title: "Polhub \(version) est disponible", detail: "L'installation automatique est désactivée.",
                                    action: .installUpdate, help: "Installer au prochain moment calme"))
            }
        }
        return Array(issues.prefix(issueLimit))
    }

    /// An account's error that Paul must act on: a connection expired, refused or too narrow. A network error passes
    /// by itself and is never « à régler ». The kept text says which error it is, read by `GoogleError` itself, never by
    /// its first words here (lot 10, 20/11).
    static func needsReconnecting(_ error: String) -> Bool {
        GoogleError(stored: error)?.needsReconnecting ?? false
    }

    /// The footer's grey line: a version that waits for a quiet moment is not « à régler ».
    static func updateLine(_ updates: Updates?) -> String? {
        guard let updates, let version = updates.latest else { return nil }
        switch updates.state {
        case .waitingForIdle: return "Polhub \(version) s'installera au calme"
        case .downloading: return "Polhub \(version) se télécharge…"
        case .installing: return "Polhub va se relancer en \(version)"
        default: return nil
        }
    }

    // MARK: - The mails card

    /// A mail of the card: who, what, when, and the color of its project.
    struct MailLine: Equatable, Identifiable {
        var thread: MailThreadRow
        var sender: String
        var subject: String
        var time: String
        /// `#RRGGBB` of the project it is filed in.
        var projectTint: String?

        var id: String { thread.id }
    }

    /// The card's order, since Gmail gives no « important »: the threads filed in a project first, then those of a
    /// known contact, then the others; the newest first in each group.
    static func mailLines(_ unread: [MailThreadRow], projectTint: (MailThreadRow) -> String?, isKnown: (String) -> Bool,
                          now: Date, calendar: Calendar = calendar) -> [MailLine] {
        let ranked = unread.map { thread -> (rank: Int, line: MailLine) in
            let tint = projectTint(thread)
            let rank = tint != nil ? 0 : thread.lastSender.map(isKnown) == true ? 1 : 2
            // « 10:42 » today, else « hier », « lun. », « 12 nov. » (`Words`, lot 10, 20/11).
            let date = thread.lastMessageAt
            let time = calendar.isDate(date, inSameDayAs: now) ? Words.time(date, calendar: calendar) : Words.shortDay(date, now: now, calendar: calendar)
            return (rank, MailLine(thread: thread, sender: sender(of: thread), subject: thread.subject.isEmpty ? Words.noSubject : thread.subject,
                                   time: time, projectTint: tint))
        }
        return ranked.sorted { ($0.rank, $1.line.thread.lastMessageAt) < ($1.rank, $0.line.thread.lastMessageAt) }.map(\.line)
    }

    /// The last person who wrote, by name when the mail gives one.
    static func sender(of thread: MailThreadRow) -> String {
        if let last = thread.lastSender {
            return thread.senders.first { $0.email == last }?.display ?? last
        }
        return thread.senders.last?.display ?? "?"
    }

    /// « Camille » for « Camille Martin » as for « Martin, Camille », « camille.martin » for an address alone.
    static func firstName(_ display: String) -> String {
        let name = display.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        if name.contains("@") { return String(name.split(separator: "@").first ?? Substring(name)) }
        let parts = name.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        // « Martin, Camille »: one word before the comma, the first name after it.
        let given = parts.count == 2 && !parts[0].contains(" ") && !parts[1].isEmpty ? parts[1] : parts.first ?? name
        return String(given.split(separator: " ").first ?? Substring(given))
    }

    // MARK: - Words of time

    /// « à l'instant », « il y a 4 min », « il y a 1 h 10 » (`Words.ago`, lot 10, 20/11: the hours, the days and the
    /// clock of the panel come from `Words` too).
    static func ago(_ date: Date, now: Date) -> String {
        Words.ago(date, now: now)
    }

    // MARK: - The clock

    /// The panel's clock: every 30 s, on the whole half-minutes (from a whole minute, the first of 2001). An event
    /// starts on a whole minute, so « dans 8 min » and the hero's quarter of an hour turn at the very tick the menu
    /// bar's « 8 min » turns (`AppModel.minutesToMeet`, every 0.5 s), not up to 30 s later.
    static let clock = PeriodicTimelineSchedule(from: Date(timeIntervalSinceReferenceDate: 0), by: 30)

    // MARK: - The height

    /// How many of the card's mails show under the panel's cap: all of them when they fit, else as many whole rows as
    /// fit (never a row cut through its subject); nil when not one does: the card has no header left to keep (lot 9,
    /// 20/11), it goes and the Mails tile names the senders. `fixed` is the height of everything but the card, `chrome`
    /// the card without its rows; `rowHeight` 0 before they were measured.
    static func mailRowsShown(cap: CGFloat, fixed: CGFloat, chrome: CGFloat, gap: CGFloat, rowHeight: CGFloat, count: Int) -> Int? {
        guard rowHeight > 0 else { return count }
        // Half a point of slack: the measures come rounded.
        let room = cap - fixed - gap - chrome + 0.5
        let rows = min(count, Int((room / rowHeight).rounded(.down)))
        return rows > 0 ? rows : nil
    }

    /// The card's link: every mail it does not show, « Voir les 2 autres »; nil when it shows them all (`Words.count`,
    /// lot 10, 20/11).
    static func moreMails(total: Int, shown: Int) -> String? {
        let hidden = total - shown
        guard hidden > 0 else { return nil }
        return hidden == 1 ? "Voir l'autre" : "Voir les \(Words.count(hidden, "autre"))"
    }

    // MARK: - Buttons and keys

    /// The round Enregistrer button (« Tuiles allégées », Paul, 16/11): it only starts a recording, from rest; a meeting
    /// detected or recorded is answered and stopped in the hero, so Arrêter is never there twice.
    static func canRecord(_ status: RecorderStatus) -> Bool {
        switch status {
        case .idle, .paused: true
        case .prompting, .recording, .presumedEnded: false
        }
    }

    /// ⌘1 to ⌘7: the pages, in the sidebar's order, the same as in the window (lot 4, 19/11): computed from its list.
    static let pages: [SidebarItem] = SidebarItem.allNumbered
}
