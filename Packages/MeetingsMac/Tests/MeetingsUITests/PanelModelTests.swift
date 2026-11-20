import Domain
import Foundation
import GoogleKit
import MeetingDetection
import Persistence
import Pipeline
import Summarization
import Testing
import Updates
@testable import MeetingsUI

/// What « Coup d'œil » says (15/11), on made-up events, meetings and mails: no screen, no clock but `now`.
@Suite struct PanelModelTests {
    let calendar: Calendar = {
        var calendar = PanelModel.calendar
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()
    /// Sunday 15 November 2026, 15:22 in Paris.
    var now: Date { at(15, 22) }

    func at(_ hour: Int, _ minute: Int, day: Int = 15) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func event(_ title: String, _ start: Date, minutes: Double = 30, meet: Bool = true, allDay: Bool = false, declined: Bool = false,
               guests: Int = 0, project: UUID? = nil, account: String = "paul@atelier-nord.fr") -> CalendarEventRow {
        var attendees = (0..<guests).map { Attendee(email: "invite\($0)@exemple.fr") }
        attendees.append(Attendee(email: account, response: declined ? "declined" : "accepted", isSelf: true))
        attendees.append(Attendee(email: "salle@exemple.fr", isResource: true))
        return CalendarEventRow(account: account, eventID: title, title: title, startAt: start, endAt: start.addingTimeInterval(minutes * 60),
                                allDay: allDay, meetCode: meet ? "abc-\(title.count)-xyz" : nil, attendees: attendees, projectID: project, updatedAt: now)
    }

    func meeting(_ title: String, start: Date, minutes: Double = 38, status: MeetingStatus = .ended, transcribed: Date? = nil,
                 source: MeetingSource = .dia) -> MeetingRow {
        MeetingRow(createdAt: start, status: status, source: source, candidateKey: "t/\(title)", title: title, startedAt: start,
                   endedAt: status.isUnfinished ? nil : start.addingTimeInterval(minutes * 60), transcribedAt: transcribed)
    }

    // MARK: - The hero's order

    @Test func theHeroTakesTheFirstTrueInItsFixedOrder() {
        let project = ProjectRow(name: "Refonte du site", status: .priorite2, createdAt: now)
        let soon = event("Revue de maquettes", at(15, 30), guests: 3, project: project.id)
        let lunch = event("Déjeuner", at(12, 0), minutes: 60, meet: false)
        let past = meeting("Point équipe", start: at(13, 0), transcribed: at(14, 0))
        var meetings = PanelModel.Meetings(rows: [past], jobs: [past.id: JobRow(meetingID: past.id, state: .running, language: "fr", progress: 0.58, createdAt: now)])
        var state = PanelModel.Meeting(status: .prompting(title: "Revue de maquettes"), prompt: DetectedPrompt(title: "Revue de maquettes", deadline: now.addingTimeInterval(7)),
                                       canForgetLink: true, meetCode: soon.meetCode, pausedUntil: now.addingTimeInterval(1_800))
        func hero() -> PanelModel.Hero {
            PanelModel.hero(meeting: state, events: [lunch, soon], projects: [project], meetings: meetings, now: now, calendar: calendar)
        }
        // 1. The HUD asks: the panel doubles it.
        #expect(hero() == .detected(title: "Revue de maquettes", deadline: now.addingTimeInterval(7), canForget: true))
        // A prompt the HUD does not show is not a hero.
        state.prompt = nil
        #expect(hero() != .detected(title: "Revue de maquettes", deadline: now.addingTimeInterval(7), canForget: true))
        // 2. Recording: the event of the same Meet code gives its project, its account and its guests.
        let recorded = meeting("Revue de maquettes", start: now.addingTimeInterval(-60), status: .recording)
        meetings.rows.insert(recorded, at: 0)
        state.status = .recording(title: "Revue de maquettes", since: now.addingTimeInterval(-60))
        #expect(hero() == .recording(title: "Revue de maquettes", since: now.addingTimeInterval(-60),
                                     detail: "Refonte du site · Atelier Nord · 3 invités", meetingID: recorded.id))
        // 3. Presumed end: it stops by itself ten minutes after.
        var ending = recorded
        ending.status = .presumedEnded
        ending.presumedEndAt = now.addingTimeInterval(-120)
        meetings.rows[0] = ending
        state.status = .presumedEnded(title: "Revue de maquettes")
        #expect(hero() == .presumedEnded(title: "Revue de maquettes", stopsAt: now.addingTimeInterval(-120 + 600), meetingID: recorded.id, canForget: true))
        // 4. An event in 8 min, with the pause that will keep it from recording.
        meetings.rows.removeFirst()
        state.status = .idle
        guard case .upcoming(let upcoming) = hero() else { Issue.record("expected the next event"); return }
        #expect(upcoming.event.id == soon.id && !upcoming.started && upcoming.pausedThrough)
        #expect(upcoming.detail == "15:30 – 16:00 · Refonte du site · 3 invités")
        // 5. Paused, nothing within the quarter of an hour: the Meet that falls in the pause is told.
        let later = event("Appel Hugo", at(15, 45))
        state.pausedUntil = at(16, 22)
        #expect(PanelModel.hero(meeting: state, events: [lunch, later], meetings: meetings, now: now, calendar: calendar)
            == .paused(until: at(16, 22), missed: later))
        // 6. The summary on its way.
        state.pausedUntil = nil
        let report = PanelModel.hero(meeting: state, events: [lunch, later], meetings: meetings, now: now, calendar: calendar)
        guard case .report(let preparing) = report else { Issue.record("expected the report"); return }
        #expect(preparing.stage == .transcribing(0.58) && preparing.isPreparing && preparing.stageText == "Transcription 58 %")
        // 7. Nothing else: the day.
        meetings.jobs = [:]
        meetings.rows = []
        #expect(PanelModel.hero(meeting: state, events: [lunch, later], meetings: meetings, now: now, calendar: calendar)
            == .day(title: "Dimanche 15 novembre", line: "Libre jusqu'à 15:45"))
        // Before the libraries: the day, without a line.
        #expect(PanelModel.hero(meeting: state, events: nil, meetings: nil, now: now, calendar: calendar) == .day(title: "Dimanche 15 novembre", line: nil))
    }

    @Test func aMeetStartedAMomentAgoComesBeforeTheNextOne() {
        let late = event("Point client", at(15, 15))
        let next = event("Revue", at(15, 30), meet: false)
        let long = event("Atelier", at(14, 0), minutes: 120)
        #expect(PanelModel.upcoming([next, late], now: now, calendar: calendar)?.event == late)
        #expect(PanelModel.upcoming([next, late], now: now, calendar: calendar)?.started == true)
        // A Meet under way for an hour leaves the next event first, then comes back.
        #expect(PanelModel.upcoming([long, next], now: now, calendar: calendar)?.event == next)
        #expect(PanelModel.upcoming([long], now: now, calendar: calendar)?.event == long)
        // Neither a whole day, nor one declined, nor an event without a Meet under way.
        #expect(PanelModel.upcoming([event("Journée", at(15, 30), allDay: true), event("Refusé", at(15, 25), declined: true),
                                     event("Déjeuner", at(15, 0), meet: false)], now: now, calendar: calendar) == nil)
        // Past the quarter of an hour: the day.
        #expect(PanelModel.upcoming([event("Plus tard", at(15, 40))], now: now, calendar: calendar) == nil)
    }

    /// A Meet recorded, then ended inside its slot (the tab closed, the presumed end ran out), is not « pas
    /// enregistrée »: its summary on its way shows instead (finding of 16/11, as the notification of a meeting not
    /// recorded).
    @Test func aMeetRecordedThenEndedInItsSlotIsNotUnrecorded() {
        let long = event("Atelier", at(14, 0), minutes: 120)
        var recorded = meeting("Atelier", start: at(14, 2), minutes: 38)
        recorded.meetCode = long.meetCode
        #expect(PanelModel.upcoming([long], recorded: [recorded], now: now, calendar: calendar) == nil)
        // A short one, a moment ago.
        let late = event("Point client", at(15, 15))
        var short = meeting("Point client", start: at(15, 16), minutes: 4)
        short.meetCode = late.meetCode
        #expect(PanelModel.upcoming([late], recorded: [short], now: now, calendar: calendar) == nil)
        // Recorded with « Enregistrer » (the whole Mac, no Meet code) during its slot: recorded too.
        let whole = meeting("Enregistrement", start: at(14, 5), minutes: 30, source: .wholeMac)
        #expect(PanelModel.upcoming([long], recorded: [whole], now: now, calendar: calendar) == nil)
        // Another Meet recorded, or this one long before, or a recording thrown away: still not recorded.
        var other = recorded
        other.meetCode = "zzz-zzzz-zzz"
        #expect(PanelModel.upcoming([long], recorded: [other], now: now, calendar: calendar)?.started == true)
        var before = recorded
        before.startedAt = at(13, 0)
        #expect(PanelModel.upcoming([long], recorded: [before], now: now, calendar: calendar)?.event == long)
        var thrown = recorded
        thrown.status = .discarded
        #expect(PanelModel.upcoming([long], recorded: [thrown], now: now, calendar: calendar)?.event == long)
        // The next event still comes.
        let next = event("Revue", at(15, 30), meet: false)
        #expect(PanelModel.upcoming([long, next], recorded: [recorded], now: now, calendar: calendar)?.event == next)
        // The hero: the summary on its way, never « Enregistrer » after Paul left.
        let meetings = PanelModel.Meetings(rows: [recorded], jobs: [recorded.id: JobRow(meetingID: recorded.id, state: .running, language: "fr",
                                                                                         progress: 0.3, createdAt: now)])
        let hero = PanelModel.hero(meeting: PanelModel.Meeting(), events: [long], meetings: meetings, now: now, calendar: calendar)
        guard case .report(let report) = hero else { Issue.record("expected the report, got \(hero)"); return }
        #expect(report.meetingID == recorded.id)
    }

    /// « dans 8 min » turns with the menu bar's « 8 min » (finding of 16/11): the panel's clock ticks on the whole
    /// half-minutes, and an event starts on a whole minute, so both read the same number between two ticks.
    @Test func theHerosMinutesTurnWithTheLogos() {
        let start = at(16, 30)
        let opened = at(16, 14).addingTimeInterval(17.3)
        let ticks = Array(PanelModel.clock.entries(from: opened, mode: .normal).prefix(40))
        #expect(ticks.count == 40)
        for (tick, next) in zip(ticks, ticks.dropFirst()) {
            let shown = MenuBarLabel.minutes(before: start, now: tick.addingTimeInterval(0.001))
            for offset in [0.5, 10, 20, next.timeIntervalSince(tick) - 0.01] {
                #expect(MenuBarLabel.minutes(before: start, now: tick.addingTimeInterval(offset)) == shown, "à \(tick) + \(offset) s")
            }
        }
    }

    @Test func theDaySaysWhatIsUnderWayOrWhenItIsFree() {
        #expect(PanelModel.dayLine([event("Déjeuner", at(15, 0), minutes: 60, meet: false)], now: now, calendar: calendar) == "Déjeuner, jusqu'à 16:00")
        #expect(PanelModel.dayLine([event("Revue", at(16, 30))], now: now, calendar: calendar) == "Libre jusqu'à 16:30")
        #expect(PanelModel.dayLine([event("Hier", at(16, 30, day: 14)), event("Demain", at(9, 30, day: 16))], now: now, calendar: calendar)
            == "Plus rien aujourd'hui")
    }

    // MARK: - The summary

    /// Paul, 16/11: « le résumé d'ADG est prêt, je l'ai déjà traité, j'ai plus besoin qu'il s'affiche ». Put away (the
    /// cross, or read once ready), a meeting's summary leaves the hero for good, the day comes back.
    @Test func aSummaryPutAwayLeavesTheHero() {
        let row = meeting("Revue de maquettes", start: at(14, 0), transcribed: at(14, 50))
        var meetings = PanelModel.Meetings(rows: [row], summaryJobs: [row.id: SummaryJobRow(meetingID: row.id, state: .done, updatedAt: at(15, 18))],
                                           overviews: [row.id: "Maquettes validées."])
        #expect(PanelModel.report(meetings, now: now) != nil)
        meetings.putAway = [row.id]
        #expect(PanelModel.report(meetings, now: now) == nil)
        #expect(PanelModel.hero(meeting: PanelModel.Meeting(), events: [], meetings: meetings, now: now, calendar: calendar).kind == "day")
        // An older one still within its two hours does not take the place of the one put away.
        let older = meeting("Point client", start: at(13, 0), transcribed: at(13, 45))
        meetings.rows.append(older)
        meetings.overviews[older.id] = "Tout va bien."
        meetings.summaryJobs[older.id] = SummaryJobRow(meetingID: older.id, state: .done, updatedAt: at(14, 0))
        #expect(PanelModel.report(meetings, now: now)?.meetingID == older.id)
    }

    /// Opened in Polhub's window once transcribed, a meeting's summary counts as read; opened while it records or is
    /// transcribed, it still announces itself when it is ready.
    @Test func aMeetingOpenedOnceTranscribedIsRead() {
        let done = meeting("Revue de maquettes", start: at(14, 0), transcribed: at(14, 50))
        let running = meeting("Point client", start: at(15, 0))
        let meetings = PanelModel.Meetings(rows: [done, running])
        #expect(PanelModel.isRead(opening: done.id, in: meetings))
        #expect(!PanelModel.isRead(opening: running.id, in: meetings))
        #expect(!PanelModel.isRead(opening: UUID(), in: meetings))
    }

    @Test func aSummaryShowsWhileItIsWrittenThenTwoHours() {
        let row = meeting("Revue de maquettes", start: at(14, 0), transcribed: at(14, 50))
        var meetings = PanelModel.Meetings(rows: [row])
        // Transcribed a moment ago, no job yet: the queue takes it at its next turn.
        #expect(PanelModel.report(meetings, now: now)?.stage == .summaryWaiting)
        meetings.summaryJobs[row.id] = SummaryJobRow(meetingID: row.id, state: .running, updatedAt: now)
        meetings.summaryProgress[row.id] = SummaryProgress(done: 2, total: 5)
        let writing = PanelModel.report(meetings, now: now)
        #expect(writing?.stageText == "Résumé, partie 3 sur 5")
        meetings.summaryJobs[row.id] = SummaryJobRow(meetingID: row.id, state: .done, updatedAt: at(15, 18))
        meetings.overviews[row.id] = "Maquettes validées ; reste la page tarifs."
        let ready = PanelModel.report(meetings, now: now)
        #expect(ready?.stage == .ready(overview: "Maquettes validées ; reste la page tarifs.") && ready?.since == at(15, 18))
        #expect(ready?.seconds == 38 * 60)
        #expect(PanelModel.ago(at(15, 18), now: now) == "il y a 4 min")
        // Two hours later, the day comes back.
        #expect(PanelModel.report(meetings, now: at(17, 19)) == nil)
        // Summaries off: « Transcription prête », from the transcription.
        meetings = PanelModel.Meetings(rows: [row], summariesOn: false)
        #expect(PanelModel.report(meetings, now: now)?.stage == .transcriptReady(reason: nil))
        meetings = PanelModel.Meetings(rows: [row], unavailable: "Apple Intelligence est désactivé.")
        #expect(PanelModel.report(meetings, now: now)?.stage == .transcriptReady(reason: "Apple Intelligence est désactivé."))
        // A failed transcription offers to try again, for two hours.
        let failed = meeting("Point client", start: at(13, 0))
        meetings = PanelModel.Meetings(rows: [failed], jobs: [failed.id: JobRow(meetingID: failed.id, state: .failed, language: nil, error: "moteur absent",
                                                                               createdAt: at(14, 0), updatedAt: at(14, 0))])
        #expect(PanelModel.report(meetings, now: now)?.stage == .transcriptionFailed("moteur absent"))
        #expect(PanelModel.report(meetings, now: at(16, 30)) == nil)
        // Neither an imported meeting nor one still recorded.
        meetings = PanelModel.Meetings(rows: [meeting("Ancienne", start: at(14, 0), transcribed: at(14, 50), source: .imported),
                                              meeting("En cours", start: at(15, 0), status: .recording)])
        #expect(PanelModel.report(meetings, now: now) == nil)
    }

    // MARK: - The tiles

    /// The Calendrier tile (lot 9, 20/11): the next event's title, whole, then its time under it; « 16:30 Revue de… » was
    /// cut on its 161 points (audit of 19/11). The hero's event is left out: « Ensuite à ».
    @Test func theCalendarTileSaysTheNextEventTitleFirst() {
        let first = event("Revue de maquettes", at(16, 30)), second = event("Appel Hugo", at(17, 30)), third = event("Point", at(18, 0))
        // A hero that says nothing of the calendar.
        let elsewhere = PanelModel.Hero.paused(until: at(16, 0), missed: nil)
        #expect(PanelModel.calendarTile([second, first, third], hero: elsewhere, now: now, calendar: calendar)
            == PanelModel.Tile(value: "Revue de maquettes", detail: "16:30 – 17:00", count: 3))
        // The hero already shows the first: « Ensuite ».
        let upcoming = PanelModel.Hero.upcoming(PanelModel.Upcoming(event: first, started: false, detail: "16:30 – 17:00", pausedThrough: false))
        #expect(PanelModel.calendarTile([first, second], hero: upcoming, now: now, calendar: calendar)
            == PanelModel.Tile(value: "Appel Hugo", detail: "Ensuite à 17:30", count: 2))
        // Nothing left today: the next one, tomorrow.
        #expect(PanelModel.calendarTile([event("Atelier", at(9, 30, day: 16))], hero: elsewhere, now: now, calendar: calendar)
            == PanelModel.Tile(value: "Atelier", detail: "Demain 9:30", count: nil))
        #expect(PanelModel.calendarTile([], hero: elsewhere, now: now, calendar: calendar) == PanelModel.Tile(value: "Rien de prévu"))
        #expect(PanelModel.calendarTile(nil, hero: elsewhere, now: now, calendar: calendar).value == "Aucun agenda")
    }

    /// « Libre jusqu'à 16:30 », then « 16:30 Revue de… » just under it: the same hour twice (audit of 19/11). The day
    /// gives the next event's start, the tile its title (lot 9, 20/11).
    @Test func theHourIsSaidOnce() {
        let first = event("Revue de maquettes", at(16, 30)), second = event("Appel Hugo", at(18, 30))
        let hero = PanelModel.hero(meeting: PanelModel.Meeting(), events: [first, second], meetings: PanelModel.Meetings(), now: now, calendar: calendar)
        #expect(hero == .day(title: "Dimanche 15 novembre", line: "Libre jusqu'à 16:30"))
        let tile = PanelModel.calendarTile([first, second], hero: hero, now: now, calendar: calendar)
        #expect(tile == PanelModel.Tile(value: "Revue de maquettes", detail: nil, count: 2))
        #expect(![tile.value, tile.detail ?? ""].joined().contains("16:30"))
        // During an event, the day says when it ends: the tile keeps the next one's time.
        let lunch = event("Déjeuner", at(15, 0), minutes: 60, meet: false)
        let busy = PanelModel.hero(meeting: PanelModel.Meeting(), events: [lunch, first], meetings: PanelModel.Meetings(), now: now, calendar: calendar)
        #expect(busy == .day(title: "Dimanche 15 novembre", line: "Déjeuner, jusqu'à 16:00"))
        #expect(PanelModel.calendarTile([lunch, first], hero: busy, now: now, calendar: calendar)
            == PanelModel.Tile(value: "Revue de maquettes", detail: "16:30 – 17:00", count: 2))
    }

    func thread(_ id: String, from name: String?, _ email: String, subject: String, at date: Date, unread: Bool = true,
                labels: [String] = ["INBOX", "CATEGORY_PERSONAL"]) -> MailThreadRow {
        let message = MailMessageRow(account: "paul@atelier-nord.fr", messageID: id, threadID: id, date: date, sender: MailAddress(name: name, email: email),
                                     subject: subject, snippet: "…", labels: labels + (unread ? ["UNREAD"] : []))
        return MailThreadRow.aggregate(account: "paul@atelier-nord.fr", threadID: id, messages: [message], mine: ["paul@atelier-nord.fr"])!
    }

    @Test func theMailsTileCountsPeoplesUnreadMails() {
        let camille = thread("a", from: "Camille Martin", "camille@exemple-studio.fr", subject: "Devis révisé", at: at(10, 42))
        let camilleAgain = thread("b", from: "Camille Martin", "camille@exemple-studio.fr", subject: "Photos", at: at(11, 0))
        let julien = thread("c", from: nil, "julien.dupont@exemple.fr", subject: "Accès", at: at(9, 15))
        let unread = PanelModel.unread([camille, julien, camilleAgain], hidden: [], tab: { _ in .personnes })
        #expect(unread.map(\.threadID) == ["b", "a", "c"])
        #expect(PanelModel.mailsTile(PanelModel.Mails(unread: unread, hasMailboxes: true))
            == PanelModel.Tile(value: "3 nouveaux", detail: "Camille, julien.dupont"))
        // Never the Notifications tab, nor a mailbox hidden, nor a thread read.
        #expect(PanelModel.unread([camille], hidden: [], tab: { _ in .notifications }).isEmpty)
        #expect(PanelModel.unread([camille], hidden: ["paul@atelier-nord.fr"], tab: { _ in .personnes }).isEmpty)
        #expect(PanelModel.unread([thread("d", from: "Léa", "lea@exemple.fr", subject: "Lu", at: now, unread: false)], hidden: [], tab: { _ in .personnes }).isEmpty)
        #expect(PanelModel.mailsTile(PanelModel.Mails(unread: [], hasMailboxes: true)).value == "Rien de neuf")
        #expect(PanelModel.mailsTile(nil).value == "Relier Gmail")
        #expect(PanelModel.mailsTile(PanelModel.Mails(hasMailboxes: false)).value == "Relier Gmail")
        // A mailbox to reconnect; a network error passes by itself.
        let expired = PanelModel.Mails.Failure(account: "paul@atelier-nord.fr", text: GoogleError.expired.description)
        #expect(PanelModel.mailsTile(PanelModel.Mails(unread: unread, hasMailboxes: true, failure: expired)).value == "Atelier Nord déconnecté")
        let offline = PanelModel.Mails.Failure(account: "paul@atelier-nord.fr", text: "The Internet connection appears to be offline.")
        #expect(PanelModel.mailsTile(PanelModel.Mails(unread: unread, hasMailboxes: true, failure: offline)).value == "3 nouveaux")
    }

    /// « Mails » said once (lot 9, 20/11): the tile « 5 nouveaux · Camille, Julien », then the card « Nouveaux mails 5 »
    /// and Camille's mail under it (audit of 19/11). While the card lists the mails, the tile keeps their number and the
    /// card has no header; without the card (a meeting under way, no room), the tile names the latest senders.
    @Test func theMailsAreSaidOnce() {
        let camille = thread("a", from: "Camille Martin", "camille@exemple-studio.fr", subject: "Devis révisé", at: at(10, 42))
        let julien = thread("c", from: nil, "julien.dupont@exemple.fr", subject: "Accès", at: at(9, 15))
        let mails = PanelModel.Mails(unread: [camille, julien], hasMailboxes: true)
        #expect(PanelModel.mailsTile(mails, listed: true) == PanelModel.Tile(value: "2 nouveaux"))
        #expect(PanelModel.mailsTile(mails, listed: false) == PanelModel.Tile(value: "2 nouveaux", detail: "Camille, julien.dupont"))
        // A mailbox to reconnect is said by « À régler »: the tile does not say it again.
        let expired = PanelModel.Mails.Failure(account: "paul@atelier-nord.fr", text: GoogleError.expired.description)
        let broken = PanelModel.Mails(unread: [camille, julien], hasMailboxes: true, failure: expired)
        let issues = PanelModel.issues(alerts: [], mailFailure: expired)
        #expect(issues.map(\.title) == ["Compte Atelier Nord à reconnecter"])
        #expect(PanelModel.mailsTile(broken, listed: true, issues: issues) == PanelModel.Tile(value: "2 nouveaux"))
        // Pushed out of « À régler » by three alerts, it stays on the tile.
        let crowded = PanelModel.issues(alerts: [.tabsUnreadable, .selfTestFailed, .diskLow(freeGB: 9)], mailFailure: expired)
        #expect(PanelModel.mailsTile(broken, listed: true, issues: crowded).value == "Atelier Nord déconnecté")
    }

    // MARK: - « À régler »

    @Test func onlyRealProblemsAreToSettleThreeAtMost() {
        let expired = GoogleAccountRow(email: "paul@atelier-nord.fr", addedAt: now, lastError: GoogleError.expired.description)
        let offline = GoogleAccountRow(email: "perso@gmail.com", addedAt: now, lastError: "The Internet connection appears to be offline.")
        let mailFailure = PanelModel.Mails.Failure(account: "paul@atelier-nord.fr", text: GoogleError.expired.description)
        let failed = PanelModel.Updates(state: .failed("refusée"), latest: "0.18.0", autoInstall: true)
        let issues = PanelModel.issues(alerts: [.tabsUnreadable], accounts: [expired, offline], mailFailure: mailFailure, updates: failed)
        #expect(issues.map(\.title) == ["Polhub ne lit plus les onglets de Dia", "Compte Atelier Nord à reconnecter", "La mise à jour 0.18.0 a échoué"])
        #expect(issues.map(\.action) == [.diagnostic, .accounts, .installUpdate])
        #expect(issues[1].detail == "Son agenda et ses mails ne se mettent plus à jour")
        // Three at most, the riskiest first.
        let many = PanelModel.issues(alerts: [.tabsUnreadable, .selfTestFailed, .diskLow(freeGB: 9)], accounts: [expired], updates: failed)
        #expect(many.count == 3 && many.allSatisfy { $0.action == .diagnostic })
        // Nothing to settle: a version that waits for a quiet moment is a grey line of the footer.
        let waiting = PanelModel.Updates(state: .waitingForIdle, latest: "0.18.0", autoInstall: true)
        #expect(PanelModel.issues(alerts: [], accounts: [offline], updates: waiting).isEmpty)
        #expect(PanelModel.updateLine(waiting) == "Polhub 0.18.0 s'installera au calme")
        #expect(PanelModel.updateLine(PanelModel.Updates()) == nil)
        // A version that waits for Paul, the automatic installation off.
        let manual = PanelModel.Updates(state: .idle, latest: "0.18.0", autoInstall: false)
        #expect(PanelModel.issues(alerts: [], updates: manual).map(\.title) == ["Polhub 0.18.0 est disponible"])
        #expect(PanelModel.needsReconnecting(GoogleError.needsWrite.description) && PanelModel.needsReconnecting(GoogleError.refused("admin_policy_enforced").description))
        #expect(!PanelModel.needsReconnecting(GoogleError.timeout.description) && !PanelModel.needsReconnecting(GoogleError.http(503).description))
    }

    // MARK: - The mails card

    @Test func theMailsOfAProjectComeFirstThenKnownPeople() {
        let stranger = thread("a", from: "Inconnu", "inconnu@exemple.fr", subject: "Bonjour", at: at(15, 0))
        let known = thread("b", from: "Julien Dupont", "julien@exemple.fr", subject: "Re: Accès au serveur de test", at: at(9, 15))
        let filed = thread("c", from: "Camille Martin", "camille@exemple-studio.fr", subject: "", at: at(18, 0, day: 14))
        let filedNewer = thread("d", from: "Léa Bernard", "lea@exemple-studio.fr", subject: "Photos du tournage", at: at(8, 0, day: 10))
        let lines = PanelModel.mailLines([stranger, known, filed, filedNewer], projectTint: { $0.threadID == "c" || $0.threadID == "d" ? "#3B82F6" : nil },
                                         isKnown: { $0 == "julien@exemple.fr" }, now: now, calendar: calendar)
        #expect(lines.map(\.thread.threadID) == ["c", "d", "b", "a"])
        #expect(lines.map(\.time) == ["hier", "mar.", "9:15", "15:00"])
        #expect(lines[0].sender == "Camille Martin" && lines[0].subject == "(sans objet)" && lines[0].projectTint == "#3B82F6")
        #expect(PanelModel.firstName("Camille Martin") == "Camille" && PanelModel.firstName("\"Léa\"") == "Léa")
    }

    /// A name written « Nom, Prénom » gave « Müller, » in the Mails tile, with its comma (Paul's capture, 16/11).
    @Test func aNameWrittenLastNameFirstGivesTheFirstName() {
        #expect(PanelModel.firstName("Bernard, Léa") == "Léa")
        #expect(PanelModel.firstName("\"Roche, Nina\"") == "Nina")
        #expect(PanelModel.firstName("Hugo Petit, Atelier Nord") == "Hugo")
        #expect(PanelModel.firstName("Bernard,") == "Bernard")
    }

    /// Under the cap of 640 points, only the mails' card gives way, by whole rows (finding of 16/11: a row cut through
    /// its subject): the rows that fit; with not one, the card goes, as it has no header left to keep (lot 9, 20/11), and
    /// the Mails tile names the senders.
    @Test func onlyTheMailsCardGivesWayUnderTheCapByWholeRows() {
        // Room for all three.
        #expect(PanelModel.mailRowsShown(cap: 640, fixed: 400, chrome: 66, gap: 10, rowHeight: 45, count: 3) == 3)
        // Room for 1.6 rows: one, whole, never half of the next.
        #expect(PanelModel.mailRowsShown(cap: 640, fixed: 490, chrome: 66, gap: 10, rowHeight: 45, count: 3) == 1)
        // Room for exactly two.
        #expect(PanelModel.mailRowsShown(cap: 640, fixed: 474, chrome: 66, gap: 10, rowHeight: 45, count: 3) == 2)
        // A row of 45 points fits in 45, whatever the rounding of the measures.
        #expect(PanelModel.mailRowsShown(cap: 640, fixed: 518.6, chrome: 66.2, gap: 10, rowHeight: 45.3, count: 3) == 1)
        // Not one row: the card goes; the Mails tile still counts them and names their senders.
        #expect(PanelModel.mailRowsShown(cap: 640, fixed: 541, chrome: 66, gap: 10, rowHeight: 45, count: 3) == nil)
        #expect(PanelModel.mailRowsShown(cap: 640, fixed: 580, chrome: 66, gap: 10, rowHeight: 45, count: 3) == nil)
        // Before the rows were measured: all of them, the panel measures them next.
        #expect(PanelModel.mailRowsShown(cap: 640, fixed: 580, chrome: 66, gap: 10, rowHeight: 0, count: 2) == 2)
    }

    /// « Voir les N autres » counts every mail the card does not show (finding of 16/11).
    @Test func theLinkCountsEveryMailNotShown() {
        #expect(PanelModel.moreMails(total: 5, shown: 3) == "Voir les 2 autres")
        #expect(PanelModel.moreMails(total: 5, shown: 1) == "Voir les 4 autres")
        #expect(PanelModel.moreMails(total: 4, shown: 3) == "Voir l'autre")
        #expect(PanelModel.moreMails(total: 3, shown: 3) == nil)
    }

    // MARK: - The hero's first line

    /// The hero's first line in its own case, as the Accueil writes « Jeudi 19 novembre » (lot 9, 20/11: « DANS 8 MIN »,
    /// « ENREGISTRE » in capitals before), and one thing of it in color, never the whole line: the symbol of a state (the
    /// recording's dot, a problem's icon), or the words of a delay (« Dans 8 min »).
    @Test func theEyebrowIsInItsOwnCaseAndColorsOneThing() {
        let soon = event("Revue de maquettes", at(15, 30))
        func report(_ stage: PanelModel.Report.Stage) -> PanelModel.Hero {
            .report(PanelModel.Report(meetingID: UUID(), title: "Point", stage: stage, summaryToCome: true))
        }
        let heroes: [(PanelModel.Hero, PanelModel.Eyebrow)] = [
            (.detected(title: "Point", deadline: now, canForget: false),
             PanelModel.Eyebrow(text: "Réunion détectée", systemImage: "record.circle", tint: nil, colored: .nothing)),
            (.recording(title: "Point", since: now, detail: nil, meetingID: nil),
             PanelModel.Eyebrow(text: "Enregistrement", systemImage: "circle.fill", tint: .recording, colored: .symbol)),
            (.presumedEnded(title: "Point", stopsAt: nil, meetingID: nil, canForget: false),
             PanelModel.Eyebrow(text: "Fin de réunion ?", systemImage: "record.circle", tint: .attention, colored: .symbol)),
            (.upcoming(PanelModel.Upcoming(event: soon, started: false, detail: "", pausedThrough: false)),
             PanelModel.Eyebrow(text: "Dans 8 min", systemImage: "calendar", tint: .attention, colored: .words)),
            (.upcoming(PanelModel.Upcoming(event: soon, started: true, detail: "", pausedThrough: false)),
             PanelModel.Eyebrow(text: "En cours · pas enregistrée", systemImage: "exclamationmark.circle.fill", tint: .attention, colored: .symbol)),
            (.paused(until: at(16, 0), missed: nil),
             PanelModel.Eyebrow(text: "Détection suspendue", systemImage: "pause.circle.fill", tint: nil, colored: .nothing)),
            (report(.transcribing(0.4)), PanelModel.Eyebrow(text: "Compte rendu en cours", systemImage: "sparkles", tint: nil, colored: .nothing)),
            (report(.ready(overview: "Tout est validé.")),
             PanelModel.Eyebrow(text: "Résumé prêt", systemImage: "checkmark.circle.fill", tint: nil, colored: .nothing)),
            (report(.transcriptReady(reason: nil)),
             PanelModel.Eyebrow(text: "Transcription prête", systemImage: "checkmark.circle.fill", tint: nil, colored: .nothing)),
            (report(.transcriptionFailed("moteur absent")),
             PanelModel.Eyebrow(text: "Transcription échouée", systemImage: "exclamationmark.triangle.fill", tint: .attention, colored: .symbol)),
            (report(.summaryFailed("trop court")),
             PanelModel.Eyebrow(text: "Résumé impossible", systemImage: "exclamationmark.triangle.fill", tint: .attention, colored: .symbol)),
            (.day(title: "Dimanche 15 novembre", line: nil),
             PanelModel.Eyebrow(text: "Dimanche 15 novembre", systemImage: nil, tint: nil, colored: .nothing)),
        ]
        for (hero, expected) in heroes {
            let eyebrow = PanelModel.eyebrow(hero, now: now)
            #expect(eyebrow == expected, "\(hero.kind)")
            #expect(eyebrow.text != eyebrow.text.uppercased(), "\(hero.kind) : en capitales")
        }
    }

    // MARK: - Buttons and keys

    /// « Tuiles allégées » (Paul, 16/11): Arrêter is only in the hero; the round button stays Enregistrer, at rest
    /// while a meeting is detected or recorded.
    @Test func theRoundButtonOnlyRecords() {
        #expect(PanelModel.canRecord(.idle) && PanelModel.canRecord(.paused(until: now)))
        #expect(!PanelModel.canRecord(.prompting(title: "Point")))
        #expect(!PanelModel.canRecord(.recording(title: "Point", since: now)))
        #expect(!PanelModel.canRecord(.presumedEnded(title: "Point")))
        // ⌘1 to ⌘7, in the sidebar's order (lot 4, 19/11).
        #expect(PanelModel.pages == [.home, .projects, .meetings, .calendar, .mails, .inspiration, .contacts])
    }
}
