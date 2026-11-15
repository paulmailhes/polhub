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

    @Test func theDaySaysWhatIsUnderWayOrWhenItIsFree() {
        #expect(PanelModel.dayLine([event("Déjeuner", at(15, 0), minutes: 60, meet: false)], now: now, calendar: calendar) == "Déjeuner, jusqu'à 16:00")
        #expect(PanelModel.dayLine([event("Revue", at(16, 30))], now: now, calendar: calendar) == "Libre jusqu'à 16:30")
        #expect(PanelModel.dayLine([event("Hier", at(16, 30, day: 14)), event("Demain", at(9, 30, day: 16))], now: now, calendar: calendar)
            == "Plus rien aujourd'hui")
    }

    // MARK: - The summary

    @Test func aSummaryShowsWhileItIsWrittenThenTwoHours() {
        let row = meeting("Revue de maquettes", start: at(14, 0), transcribed: at(14, 50))
        var meetings = PanelModel.Meetings(rows: [row])
        // Transcribed a moment ago, no job yet: the queue takes it at its next turn.
        #expect(PanelModel.report(meetings, now: now)?.stage == .summaryWaiting)
        meetings.summaryJobs[row.id] = SummaryJobRow(meetingID: row.id, state: .running, updatedAt: now)
        meetings.summaryProgress[row.id] = SummaryProgress(done: 2, total: 5)
        let writing = PanelModel.report(meetings, now: now)
        #expect(writing?.stageText == "Résumé, partie 3 sur 5" && writing?.tileText == "Résumé 3/5")
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

    @Test func theCalendarTileShowsTheNextTwoWithoutTheHerosOne() {
        let first = event("Revue de maquettes", at(16, 30)), second = event("Appel Hugo", at(17, 30)), third = event("Point", at(18, 0))
        let tile = PanelModel.calendarTile([second, first, third], hiding: nil, now: now, calendar: calendar)
        #expect(tile == PanelModel.Tile(value: "16:30 Revue de maquettes", detail: "17:30 Appel Hugo", count: 3))
        // The hero already shows the first: « Ensuite ».
        #expect(PanelModel.calendarTile([first, second], hiding: first.id, now: now, calendar: calendar)
            == PanelModel.Tile(value: "Appel Hugo", detail: "Ensuite à 17:30", count: 2))
        #expect(PanelModel.calendarTile([second], hiding: nil, now: now, calendar: calendar)
            == PanelModel.Tile(value: "Appel Hugo", detail: "17:30 – 18:00", count: 1))
        // Nothing left today: the next one, tomorrow.
        #expect(PanelModel.calendarTile([event("Atelier", at(9, 30, day: 16))], hiding: nil, now: now, calendar: calendar)
            == PanelModel.Tile(value: "Atelier", detail: "Demain 9:30", count: nil))
        #expect(PanelModel.calendarTile([], hiding: nil, now: now, calendar: calendar) == PanelModel.Tile(value: "Rien de prévu"))
        #expect(PanelModel.calendarTile(nil, hiding: nil, now: now, calendar: calendar).value == "Aucun agenda")
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

    @Test func theMeetingsTileFollowsTheMeeting() {
        let yesterday = meeting("Point équipe", start: at(10, 0, day: 14), transcribed: at(11, 0, day: 14))
        var meetings = PanelModel.Meetings(rows: [yesterday], overviews: [yesterday.id: "Tout va bien."])
        #expect(PanelModel.meetingsTile(status: .recording(title: "Revue", since: now), meetings: meetings, report: nil, now: now, calendar: calendar)
            == PanelModel.Tile(value: "En cours", detail: "Revue", live: true))
        #expect(PanelModel.meetingsTile(status: .idle, meetings: meetings, report: nil, now: now, calendar: calendar)
            == PanelModel.Tile(value: "Point équipe", detail: "Hier · Résumé prêt"))
        meetings.overviews = [:]
        meetings.jobs[yesterday.id] = JobRow(meetingID: yesterday.id, state: .done, language: "fr", doubtful: true, createdAt: now)
        #expect(PanelModel.meetingsTile(status: .idle, meetings: meetings, report: nil, now: now, calendar: calendar).detail == "Hier · À vérifier")
        let report = PanelModel.Report(meetingID: yesterday.id, title: "Revue de maquettes", seconds: nil, stage: .transcribing(0.58), since: nil, summaryToCome: true)
        #expect(PanelModel.meetingsTile(status: .idle, meetings: meetings, report: report, now: now, calendar: calendar)
            == PanelModel.Tile(value: "Transcription 58 %", detail: "Revue de maquettes"))
        #expect(PanelModel.meetingsTile(status: .idle, meetings: PanelModel.Meetings(), report: nil, now: now, calendar: calendar).value == "Aucune réunion")
    }

    @Test func theProjectsTileCountsPrioriteDeuxTheMostUrgent() {
        let projects = [ProjectRow(name: "Refonte site", status: .priorite2, createdAt: now), ProjectRow(name: "Identité", status: .priorite1, createdAt: now),
                        ProjectRow(name: "Studio photo", status: .priorite2, createdAt: now)]
        #expect(PanelModel.projectsTile(projects) == PanelModel.Tile(value: "2 en priorité", detail: "Refonte site, Studio photo"))
        #expect(PanelModel.projectsTile([projects[1]]) == PanelModel.Tile(value: "Rien d'urgent"))
        #expect(PanelModel.projectsTile([]).value == "Aucun projet")
        #expect(PanelModel.projectsTile(nil).value == "Aucun projet")
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

    /// Under the cap of 640 points, only the mails' list gives way; not even one mail left, the card goes.
    @Test func onlyTheMailsListGivesWayUnderTheCap() {
        // Room for all three.
        #expect(PanelModel.mailListHeight(cap: 640, fixed: 400, chrome: 70, gap: 10, rows: 150) == 150)
        // Room for part of them: the list scrolls.
        #expect(PanelModel.mailListHeight(cap: 640, fixed: 480, chrome: 70, gap: 10, rows: 150) == 80)
        // Not one row: the card goes, the Mails tile still counts them.
        #expect(PanelModel.mailListHeight(cap: 640, fixed: 530, chrome: 70, gap: 10, rows: 150) == nil)
        // One short mail still fits where it fits.
        #expect(PanelModel.mailListHeight(cap: 640, fixed: 520, chrome: 70, gap: 10, rows: 40) == 40)
    }

    // MARK: - Buttons and keys

    @Test func theRecordButtonBecomesStopDuringAMeeting() {
        #expect(PanelModel.recordToggle(.idle) == .record(enabled: true))
        #expect(PanelModel.recordToggle(.paused(until: now)) == .record(enabled: true))
        // The hero answers a detected meeting.
        #expect(PanelModel.recordToggle(.prompting(title: "Point")) == .record(enabled: false))
        #expect(PanelModel.recordToggle(.recording(title: "Point", since: now)) == .stop)
        #expect(PanelModel.recordToggle(.presumedEnded(title: "Point")) == .stop)
        #expect(PanelModel.pages == [.home, .projects, .meetings, .calendar, .mails, .contacts])
    }
}
