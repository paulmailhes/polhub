import Colin
import Foundation
import Persistence
import PolhubDesign
import Testing
@testable import MeetingsUI

/// « Colin à droite » (lot 5, 19/11): the day on the left, 640 points at most; Colin's panel on the right, 420 points, the
/// whole height. In a narrow window, the day alone, Colin's bar floating at its foot.
@Suite struct HomeLayoutTests {
    @Test func colinsPanelStandsBesideTheDay() {
        #expect(HomeLayout.panelWidth == 420 && HomeLayout.dayWidth == 640 && HomeLayout.dayMinimumWidth == 420)
        // Two columns once the day keeps its 420 points beside the panel and its line, with the page's margins.
        #expect(HomeLayout.breakpoint == 420 + 1 + 420 + 2 * PageMetrics.horizontal)
        #expect(HomeLayout.of(width: HomeLayout.breakpoint) == .columns)
        #expect(HomeLayout.of(width: HomeLayout.breakpoint - 1) == .stacked)
        // The window at 1 180 points, its sidebar aside.
        #expect(HomeLayout.of(width: 928) == .columns)
        #expect(HomeLayout.of(width: 1_400) == .columns)
    }

    @Test func theNarrowestWindowStacks() {
        #expect(HomeLayout.of(width: 661) == .stacked)
        #expect(HomeLayout.of(width: 0) == .stacked)
    }
}

/// The words of the Accueil. Every name here is invented.
@Suite struct HomeTextTests {
    func line(_ kind: ReviewRules.Kind, _ person: String, detail: String? = nil, days: Int? = nil) -> ReviewRules.Line {
        ReviewRules.Line(id: "\(kind.rawValue):x", kind: kind, person: person, detail: detail, days: days)
    }

    @Test func eachLineSaysWhatWaits() {
        #expect(ReviewText.title(line(.draft, "Claire")) == "Brouillon prêt pour Claire")
        #expect(ReviewText.title(line(.reply, "Marc")) == "Marc attend ta réponse")
        #expect(ReviewText.title(line(.silent, "Anne")) == "Anne ne répond plus")
        #expect(ReviewText.title(line(.unfiled, "Point Cabinet Martin")) == "Réunion à ranger")
        // Without a name, the sentence still stands.
        #expect(ReviewText.title(line(.draft, "")) == "Brouillon prêt")
        #expect(ReviewText.title(line(.reply, "")) == "Un mail attend ta réponse")
        #expect(ReviewText.title(line(.silent, "")) == "Un client ne répond plus")
    }

    @Test func theSecondLineSaysTheProjectAndTheDays() {
        #expect(ReviewText.detail(line(.reply, "Marc", detail: "Studio Nord", days: 3)) == "Studio Nord · 3 jours")
        #expect(ReviewText.detail(line(.silent, "Anne", detail: "Maison Leroy", days: 9)) == "Maison Leroy · 9 jours")
        #expect(ReviewText.detail(line(.reply, "Marc", days: 1)) == "1 jour")
        #expect(ReviewText.detail(line(.reply, "Marc", days: 0)) == "aujourd'hui")
        #expect(ReviewText.detail(line(.draft, "Claire", detail: "Cabinet Martin")) == "Cabinet Martin")
        #expect(ReviewText.detail(line(.draft, "Claire")) == nil)
        // A meeting to file is named on its second line.
        #expect(ReviewText.detail(line(.unfiled, "Point Cabinet Martin")) == "Point Cabinet Martin")
    }

    /// The Accueil's pass (18/11): a line is late past twice its threshold; its age is then in the accent.
    @Test func lateIsTwiceTheThreshold() {
        let thresholds = ReviewRules.Thresholds(replyDays: 3, silentDays: 7)
        #expect(!ReviewText.late(line(.reply, "Marc", days: 6), thresholds: thresholds))
        #expect(ReviewText.late(line(.reply, "Marc", days: 7), thresholds: thresholds))
        #expect(!ReviewText.late(line(.silent, "Anne", days: 14), thresholds: thresholds))
        #expect(ReviewText.late(line(.silent, "Anne", days: 15), thresholds: thresholds))
        #expect(!ReviewText.late(line(.draft, "Claire", days: 40), thresholds: thresholds))
    }

    /// Final review (18/11): the next meeting says its hour once.
    @Test func theNextMeetingSaysItsHourOnce() {
        #expect(TodayText.next(when: "dans 40 min", hour: "14:00", project: "Studio Nord") == "dans 40 min · 14:00 · Studio Nord")
        #expect(TodayText.next(when: "à 15:30", hour: "15:30", project: "Studio Nord") == "à 15:30 · Studio Nord")
        #expect(TodayText.next(when: "en cours", hour: "14:00", project: nil) == "en cours · 14:00")
    }

    @Test func eachLineHasItsButton() {
        #expect(ReviewText.action(.draft) == "Relire")
        #expect(ReviewText.action(.reply) == "Ouvrir")
        #expect(ReviewText.action(.silent) == "Ouvrir")
        #expect(ReviewText.action(.unfiled) == "Ranger")
    }

    /// « Pas besoin », « Plus tard », and for a silent client « Anne a répondu ailleurs »: said with the name, never
    /// with « elle » or « il ».
    @Test func theWaysToSetALineAside() {
        #expect(ReviewText.dismissals(line(.reply, "Marc")).map(\.title) == ["Pas besoin", "Plus tard"])
        #expect(ReviewText.dismissals(line(.reply, "Marc")).map(\.reason) == [.notNeeded, .later])
        #expect(ReviewText.dismissals(line(.silent, "Anne")).map(\.title) == ["Anne a répondu ailleurs", "Pas besoin", "Plus tard"])
        #expect(ReviewText.dismissals(line(.silent, "Anne")).map(\.reason) == [.answeredElsewhere, .notNeeded, .later])
        #expect(ReviewText.dismissals(line(.silent, "")).first?.title == "Réponse reçue ailleurs")
        // A draft leaves when it is sent or deleted; a meeting when it is filed, under « Aucun » too.
        #expect(ReviewText.dismissals(line(.draft, "Claire")).isEmpty)
        #expect(ReviewText.dismissals(line(.unfiled, "Point Cabinet Martin")).isEmpty)
    }

    /// Lot 5 (19/11): under the date, one line says what came since Paul last came, then « Voir › ».
    @Test func theLineUnderTheDateSaysWhatCameSince() {
        let week = Briefing.Line(.week, label: "Cette semaine", text: "3 rendez-vous, le prochain demain 10:00.")
        #expect(BriefingText.since([week, Briefing.Line(.since, label: "Depuis hier 19:40", text: "1 mail de client, 2 projets ont bougé.")])
                == "Depuis hier 19:40 · 1 mail de client, 2 projets ont bougé")
        #expect(BriefingText.since([Briefing.Line(.since, label: "Depuis 8:05", text: "3 mails de clients.")]) == "Depuis 8:05 · 3 mails de clients")
        #expect(BriefingText.since([week, Briefing.Line(.yours, label: "À toi de jouer", text: "Studio Nord.")]) == nil)
        #expect(BriefingText.since([]) == nil)
        // Lot 10 (20/11): found by its kind, whatever its first word says.
        #expect(BriefingText.since([Briefing.Line(.since, label: "Ce matin", text: "rien de neuf.")]) == "Ce matin · rien de neuf")
        #expect(BriefingText.since([Briefing.Line(.week, label: "Depuis lundi", text: "rien.")]) == nil)
    }

    /// Lot 5 (19/11): when « Le point » was prepared is said under the pointer, as the day is said elsewhere.
    @Test func whenThePointWasPreparedIsSaidUnderThePointer() {
        var paris = Calendar(identifier: .gregorian)
        paris.timeZone = TimeZone(identifier: "Europe/Paris")!
        let now = Date(timeIntervalSince1970: 1_795_096_800)   // Thursday 19/11/2026, 15:00 in Paris
        #expect(BriefingText.prepared(now.addingTimeInterval(-3_600), now: now, calendar: paris) == "Le point · aujourd'hui 14:00")
        #expect(BriefingText.prepared(now.addingTimeInterval(-86_400 - 3 * 3_600), now: now, calendar: paris) == "Le point · hier 12:00")
    }

    /// Lot 5 (19/11): « Rejoindre » outlined, then the Accueil's one full button ten minutes before; far off (tomorrow's
    /// first, in the evening), none before its last ten minutes.
    @Test func joinIsTheOneFullButtonTenMinutesBefore() {
        #expect(TodayText.join(minutesLeft: 40, sameDay: true) == .secondary)
        #expect(TodayText.join(minutesLeft: 10, sameDay: true) == .primary)
        #expect(TodayText.join(minutesLeft: 8, sameDay: true) == .primary)
        #expect(TodayText.join(minutesLeft: -5, sameDay: true) == .primary)
        #expect(TodayText.join(minutesLeft: 8, sameDay: false) == .primary)
        #expect(TodayText.join(minutesLeft: 600, sameDay: false) == nil)
    }

    /// Lot 5 (19/11): a line's gestures, the same under the pointer and at the right click — its action, « Ranger » for a
    /// meeting, the ways to set it aside.
    @Test func eachLineHasItsGesturesUnderThePointerAndTheRightClick() {
        #expect(ReviewText.gestures(line(.draft, "Claire")) == ReviewText.Gestures(open: "Relire", file: false, dismissals: []))
        #expect(ReviewText.gestures(line(.reply, "Marc")) == ReviewText.Gestures(open: "Ouvrir", file: false, dismissals: ReviewText.dismissals(line(.reply, "Marc"))))
        #expect(ReviewText.gestures(line(.silent, "Anne")).dismissals.map(\.title) == ["Anne a répondu ailleurs", "Pas besoin", "Plus tard"])
        // A meeting opens with a click; « Ranger » is its action.
        #expect(ReviewText.gestures(line(.unfiled, "Point Cabinet Martin")) == ReviewText.Gestures(open: "Ouvrir", file: true, dismissals: []))
    }

    /// Lot 5 (19/11): « Reporter » and « Livré » come under the pointer on every dated line, the late ones too, in the place
    /// of its « quand »; an unfolded line shows them under its actions; the right click has them, after « Ouvrir le projet ».
    @Test func aDatedLineShowsItsActionsUnderThePointer() {
        #expect(TodoText.hoverActions(dated: true, unfolded: false))
        #expect(!TodoText.hoverActions(dated: true, unfolded: true))
        #expect(!TodoText.hoverActions(dated: false, unfolded: false))
        #expect(TodoText.menu(dated: true) == ["Ouvrir le projet", "Reporter", "Livré"])
        #expect(TodoText.menu(dated: false) == ["Ouvrir le projet"])
    }

    /// Lot 10 (20/11): a sentence of the point is its label and its text, kept apart: never cut at its « : », which the
    /// hour of « depuis » has too.
    @Test func aSentenceOfThePointIsItsLabelAndItsText() {
        let since = Briefing.Line(.since, label: "Depuis hier 19:40", text: "4 mails de clients.")
        #expect(since.sentence == "Depuis hier 19:40 : 4 mails de clients.")
        #expect(Briefing.Line(.week, label: "Cette semaine", text: "aucun rendez-vous.").sentence == "Cette semaine : aucun rendez-vous.")
    }
}

/// Colin's thread and bar on the Accueil (18/11): the days of the thread, what the bar says, how wide it is.
@MainActor
@Suite struct ColinThreadTextTests {
    /// Wednesday 18/11/2026, 10:00 in Paris.
    let now = Date(timeIntervalSince1970: 1_794_992_400)
    var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "fr_FR")
        return calendar
    }

    /// The Accueil's pass (18/11): the thread follows its end only when Paul is there, 32 pt or less from it.
    @Test func theThreadFollowsOnlyAtTheBottom() {
        #expect(ThreadScroll.follows(contentHeight: 2_000, offset: 1_400, visibleHeight: 600))
        #expect(ThreadScroll.follows(contentHeight: 2_000, offset: 1_370, visibleHeight: 600))
        #expect(!ThreadScroll.follows(contentHeight: 2_000, offset: 1_300, visibleHeight: 600))
        // A thread shorter than the window: at its end.
        #expect(ThreadScroll.follows(contentHeight: 300, offset: 0, visibleHeight: 600))
    }

    /// Colin's actions take their place in his text: where the text stood when each began; one not reached yet by the
    /// words shown waits at the end.
    @Test func stepsTakeTheirPlaceInTheText() {
        let first = ColinStep(id: "t1", tool: "mails", state: .done, position: 11)
        let second = ColinStep(id: "t2", tool: "projet", state: .running, position: 40)
        let pieces = ColinThreadText.pieces("Je regarde. Trois projets.", groups: ColinStepText.groups([first, second]))
        #expect(pieces == [.text("Je regarde."), .steps(StepGroup(steps: [first])), .text("Trois projets."), .steps(StepGroup(steps: [second]))])
        #expect(ColinThreadText.pieces("", groups: []) == [])
    }

    /// Final review (18/11): Paul's hand on the thread stops the following at once, even a slow scroll inside the end's
    /// margin; let go at the end, it follows again. Content that grows while he follows is followed; his question
    /// always brings him back.
    @Test func theThreadFollowsPaulsHand() {
        var follow = ThreadFollow()
        #expect(follow.scrollsOnTick)
        follow.userScroll(began: true)
        #expect(!follow.following && !follow.scrollsOnTick)
        let duringHand = follow.geometry(atEnd: true)
        #expect(!duringHand)
        follow.userScroll(began: false)
        #expect(follow.following)
        // Content that grows under the end while he follows: scrolled to.
        let grown = follow.geometry(atEnd: false)
        #expect(grown)
        // Gone up to read: not pulled back; his question brings him back.
        follow.userScroll(began: true)
        _ = follow.geometry(atEnd: false)
        follow.userScroll(began: false)
        let pulled = follow.geometry(atEnd: false)
        #expect(!follow.following && !pulled)
        follow.asked()
        #expect(follow.following && follow.scrollsOnTick)
    }

    /// The words of each tick fade in over 0.2 s from their own arrival; older ones are settled.
    @Test func freshWordsFadeFromTheirArrival() {
        let start = Date(timeIntervalSince1970: 1_000)
        let arrivals = [FreshText.Arrival(offset: 5, at: start), FreshText.Arrival(offset: 9, at: start.addingTimeInterval(0.1))]
        let early = FreshText.segments(count: 14, arrivals: arrivals, now: start.addingTimeInterval(0.15))
        #expect(early.map(\.range) == [0..<5, 5..<9, 9..<14])
        #expect(early.map(\.opacity) == [1, 0.75, 0.25])
        let late = FreshText.segments(count: 14, arrivals: arrivals, now: start.addingTimeInterval(0.5))
        #expect(late.map(\.range) == [0..<14] && late.first?.opacity == 1)
    }

    /// 19/11: once the last words have faded in, nothing is left to animate. The list of arrivals was emptied only when
    /// the text changed: after the last word, the timeline ran on at the screen's rate for as long as the answer showed.
    @Test func theFadeEndsAfterTheLastWords() {
        let start = Date(timeIntervalSince1970: 1_000)
        let arrivals = [FreshText.Arrival(offset: 5, at: start), FreshText.Arrival(offset: 9, at: start.addingTimeInterval(0.1))]
        #expect(FreshText.fading(arrivals, now: start.addingTimeInterval(0.15)) == arrivals)
        #expect(FreshText.fading(arrivals, now: start.addingTimeInterval(0.25)) == [arrivals[1]])
        #expect(FreshText.fading(arrivals, now: start.addingTimeInterval(0.31)).isEmpty)
        // The view waits this long after the last arrival before it empties its list.
        #expect(FreshText.settles > FreshText.fade)
    }

    /// « Copier » under an answer copies what Paul reads: no fences, no stars, no line to keep.
    @Test func copyTakesTheTextAsRead() {
        let answer = "Voilà, **court** et à ton ton.\n```message\nSalut Marc !\n```\n```retenir\nMarc préfère WhatsApp.\n```"
        #expect(ColinThreadText.plain(answer) == "Voilà, court et à ton ton.\n\nSalut Marc !")
    }

    /// What Colin changed in an answer goes with it; his rules' changes, and an agent's, stay lines at their time.
    @Test func changesMadeInAnAnswerGoWithIt() {
        let question = ColinMessageRow(author: .paul, text: "Passe Studio Nord en priorité 1", createdAt: now.addingTimeInterval(-300))
        let answer = ColinMessageRow(author: .colin, text: "C'est fait.", createdAt: now.addingTimeInterval(-299.999))
        let next = ColinMessageRow(author: .paul, text: "Merci", createdAt: now.addingTimeInterval(-60))
        func line(_ id: String, _ who: ChangeAuthor, at seconds: Double, reason: String? = nil) -> ProjectChangeLine {
            ProjectChangeLine(id: id, projectID: UUID(), projectName: "Studio Nord", who: who, at: now.addingTimeInterval(seconds), reason: reason, rows: [],
                              undoneAt: nil)
        }
        let made = line("c1", .colin, at: -280)
        let rule = line("c2", .colin, at: -270, reason: "Après ton mail à Marc, 9:50")
        let agent = line("c3", .agent, at: -265)
        let later = line("c4", .colin, at: -30)
        let split = ColinThreadText.attach([made, rule, agent, later], to: [question, answer, next])
        #expect(split.inAnswers == [answer.id: [made]])
        #expect(split.loose.map(\.id) == ["c2", "c3", "c4"])
    }

    @Test func theDaySeparatorsSayTodayYesterdayThenTheDate() {
        #expect(ColinThreadText.day(now.addingTimeInterval(-3_600), now: now, calendar: paris) == "Aujourd'hui")
        #expect(ColinThreadText.day(now.addingTimeInterval(-86_400), now: now, calendar: paris) == "Hier")
        #expect(ColinThreadText.day(now.addingTimeInterval(-2 * 86_400), now: now, calendar: paris) == "lundi 16 novembre")
        let messages = [-2.0, -1.9, -1.0, 0].map { days in
            ColinMessageRow(author: .paul, text: "\(days)", createdAt: now.addingTimeInterval(days * 86_400 - 60))
        }
        #expect(ColinThreadText.sections(messages, now: now, calendar: paris).map(\.day) == ["lundi 16 novembre", "Hier", "Aujourd'hui"])
        #expect(ColinThreadText.sections(messages, now: now, calendar: paris).map { $0.items.count } == [2, 1, 1])
    }

    /// Step 3 (18/11): Colin's changes take their place in the thread by their time, under their day.
    @Test func changesTakeTheirPlaceByTime() {
        let question = ColinMessageRow(author: .paul, text: "Passe Cabinet Martin en priorité 1", createdAt: now.addingTimeInterval(-120))
        let answer = ColinMessageRow(author: .colin, text: "C'est fait.", createdAt: now.addingTimeInterval(-119.999))
        let row = ProjectChangeRow(id: 7, projectID: UUID(), field: .status, subject: nil, before: "priorité 2", after: "priorité 1", detail: nil, who: .colin,
                                   batch: "b", reason: nil, source: nil, at: now.addingTimeInterval(-100), undoneAt: nil)
        let change = ProjectChangeLine(id: "c7", projectID: row.projectID, projectName: "Cabinet Martin", who: .colin, at: row.at, reason: nil, rows: [row],
                                       undoneAt: nil)
        let earlier = ProjectChangeLine(id: "c3", projectID: row.projectID, projectName: "Cabinet Martin", who: .colin, at: now.addingTimeInterval(-86_400),
                                        reason: "Rendez-vous du jeudi 19/11", rows: [row], undoneAt: nil)
        let sections = ColinThreadText.sections([question, answer], changes: [change, earlier], now: now, calendar: paris)
        #expect(sections.map(\.day) == ["Hier", "Aujourd'hui"])
        #expect(sections.last?.items.map(\.id) == [question.id, answer.id, "change-c7"])
        #expect(ColinThreadText.lastID([question, answer], changes: [change, earlier]) == "change-c7")
    }

    @Test func theBarSaysWhatColinCanDo() {
        let ask = "Écris ou dicte à Colin…"
        #expect(ColinThreadText.bar(.off) == .turnOn)
        // The Accueil's pass (18/11): why it waits is said above the field, not only in its empty text.
        #expect(ColinThreadText.bar(.waitingCall) == .field(placeholder: ask, enabled: false, note: "Colin attend la fin de ton call."))
        #expect(ColinThreadText.bar(.idle) == .field(placeholder: ask, enabled: true, note: nil))
        #expect(ColinThreadText.bar(.working("Colin lit tes mails…")) == .field(placeholder: ask, enabled: true, note: nil))
        #expect(ColinThreadText.bar(.settling) == .field(placeholder: ask, enabled: true, note: "Le Mac vient de se réveiller : Colin répond dans un instant."))
        #expect(ColinThreadText.bar(.broken("Limite atteinte.")) == .field(placeholder: ask, enabled: true, note: "Limite atteinte."))
    }

    @Test func theEndOfAnAnswerIsSaidApart() {
        func answer(_ text: String, _ state: ColinMessageRow.State) -> ColinMessageRow { ColinMessageRow(author: .colin, text: text, state: state, createdAt: now) }
        #expect(ColinThreadText.note(of: answer("Marc t'a écrit\n\nArrêté : ton call commence.", .interrupted)) == ("Marc t'a écrit", "Arrêté : ton call commence."))
        #expect(ColinThreadText.note(of: answer("Arrêté : le Mac s'endort.", .interrupted)) == ("", "Arrêté : le Mac s'endort."))
        #expect(ColinThreadText.note(of: answer("Marc t'a", .interrupted)) == ("Marc t'a", "Arrêté."))
        #expect(ColinThreadText.note(of: answer("Mar", .failed)) == ("Mar", "Colin n'a pas pu finir."))
        // Lot 10 (20/11): the stop is found by the words the base keeps, never reworded, whatever the thread says of it.
        #expect(ColinStop.ending("Marc t'a écrit\n\nArrêté : ton call commence.").map { [$0.said] } == ["Marc t'a écrit"])
        #expect(ColinStop.ending("Arrêté : Colin est à l'arrêt.")?.stop == .off && ColinStop.ending("Arrêté : le Mac s'endort.")?.stop == .sleep)
        #expect(ColinStop.ending("Marc t'a") == nil && ColinStop.ending("Arrêté : autre chose.") == nil)
        #expect(ColinStop.call.stored == "Arrêté : ton call commence." && ColinStop.sleep.stored == "Arrêté : le Mac s'endort."
                && ColinStop.off.stored == "Arrêté : Colin est à l'arrêt.")
        #expect(ColinThreadText.note(of: answer("Trois projets.", .done)) == ("Trois projets.", nil))
    }

    /// Lot 5 (19/11): in a panel of 420 points, Paul's bubble leaves 64 points beside it, no longer 140.
    @Test func paulsBubbleLeavesSixtyFourPoints() {
        #expect(ThreadMetrics.bubbleGap == 64)
    }

    /// Lot 5 (19/11): the head of Colin's panel says his real state — never « en marche » during a call or a breakdown,
    /// as the switch alone said before.
    @Test func theHeaderSaysColinsRealState() {
        #expect(ColinState(.idle) == .ready && ColinState.ready.label == "prêt")
        #expect(ColinState(.working("Colin lit tes mails…")) == .answering && ColinState.answering.label == "répond…")
        #expect(ColinState(.starting) == .answering)
        // A question on its way, before its first word.
        #expect(ColinState(.idle, answering: true) == .answering)
        #expect(ColinState(.broken("Limite atteinte."), answering: true) == .answering)
        #expect(ColinState(.waitingCall) == .waitingCall && ColinState.waitingCall.label == "attend ton call")
        #expect(ColinState(.settling) == .waking && ColinState.waking.label == "se réveille")
        #expect(ColinState(.broken("Limite atteinte.")) == .broken && ColinState.broken.label == "en panne")
        #expect(ColinState(.off) == .off && ColinState(.off, answering: true) == .off && ColinState.off.label == "à l'arrêt")
        for status in [ColinThread.Status.off, .waitingCall, .settling, .idle, .starting, .working("…"), .broken("…")] {
            #expect(ColinState(status).label != "en marche")
        }
        // Its dot: green while he works, the color of attention out of order, grey otherwise; it beats while he answers.
        #expect(ColinState.ready.dot == .done && ColinState.answering.dot == .done && ColinState.broken.dot == .attention)
        #expect(ColinState.off.dot == .quiet && ColinState.waitingCall.dot == .quiet && ColinState.waking.dot == .quiet)
        #expect(ColinState.answering.beats && !ColinState.ready.beats)
    }

    /// Lot 5 (19/11): in a narrow window, the head of Colin's bar says his state, or, ready, the start of his last answer.
    @Test func theNarrowBarSaysTheStateOrTheLastAnswer() {
        #expect(ColinState.barLine(.ready, lastAnswer: "Marc t'a écrit lundi.") == "Marc t'a écrit lundi.")
        #expect(ColinState.barLine(.ready, lastAnswer: nil) == "prêt")
        #expect(ColinState.barLine(.answering, lastAnswer: "Marc t'a écrit lundi.") == "répond…")
        #expect(ColinState.barLine(.waitingCall, lastAnswer: "Marc t'a écrit lundi.") == "attend ton call")
        #expect(ColinState.barLine(.off, lastAnswer: "Marc t'a écrit lundi.") == "à l'arrêt")
    }

    /// The start of an answer is its first line as Paul reads it: no stars, no fences, never the note of its end.
    @Test func theStartOfAnAnswerIsItsFirstLine() {
        func answer(_ text: String, _ state: ColinMessageRow.State = .done) -> ColinMessageRow {
            ColinMessageRow(author: .colin, text: text, state: state, createdAt: now)
        }
        #expect(ColinThreadText.opening(answer("Voilà, **court** et à ton ton.\n```message\nSalut Marc !\n```")) == "Voilà, court et à ton ton.")
        #expect(ColinThreadText.opening(answer("```message\nSalut Marc !\n```")) == "Salut Marc !")
        #expect(ColinThreadText.opening(answer("Marc t'a écrit\n\nArrêté : ton call commence.", .interrupted)) == "Marc t'a écrit")
        #expect(ColinThreadText.opening(answer("Arrêté : le Mac s'endort.", .interrupted)) == nil)
    }

    /// Lot 5 (19/11): « Copier » once — an answer with a message to copy has it in its card, not in its foot; an empty foot
    /// takes no room.
    @Test func theFootOffersCopyOnceAndTakesNoRoomEmpty() {
        func answer(_ text: String, _ state: ColinMessageRow.State = .done) -> ColinMessageRow {
            ColinMessageRow(author: .colin, text: text, state: state, createdAt: now)
        }
        #expect(ColinThreadText.copiesInItsCard("Voilà.\n```message\nSalut Marc !\n```"))
        #expect(!ColinThreadText.copiesInItsCard("Trois projets."))
        #expect(ColinThreadText.foot(of: answer("Trois projets."), colinOn: true) == ColinThreadText.Foot(note: nil, copy: true, retry: false))
        let card = ColinThreadText.foot(of: answer("Voilà, court.\n```message\nSalut Marc !\n```\n```retenir\nMarc préfère WhatsApp.\n```"), colinOn: true)
        #expect(card == ColinThreadText.Foot(note: nil, copy: false, retry: false) && card.isEmpty)
        #expect(ColinThreadText.foot(of: answer("Marc t'a\n\nArrêté : ton call commence.", .interrupted), colinOn: true)
                == ColinThreadText.Foot(note: "Arrêté : ton call commence.", copy: true, retry: true))
        #expect(ColinThreadText.foot(of: answer("Arrêté : le Mac s'endort.", .interrupted), colinOn: false)
                == ColinThreadText.Foot(note: "Arrêté : le Mac s'endort.", copy: false, retry: false))
        #expect(ColinThreadText.foot(of: answer("", .failed), colinOn: true) == ColinThreadText.Foot(note: "Colin n'a pas pu finir.", copy: false, retry: true))
        #expect(!ColinThreadText.Foot(note: "Arrêté.", copy: false, retry: false).isEmpty)
    }

    /// Lot 5 (19/11): each card of the thread says at its head what it is.
    @Test func eachCardSaysWhatItIs() {
        #expect(ResultCard.message.label == "Message à copier")
        #expect(ResultCard.draft.label == "Brouillon")
        #expect(ResultCard.change.label == "Projet modifié")
        #expect(ResultCard.creation.label == "Nouveau projet")
        func row(_ field: ProjectChangeField) -> ProjectChangeRow {
            ProjectChangeRow(id: 1, projectID: UUID(), field: field, subject: nil, before: nil, after: "priorité 1", detail: "priorité 1", who: .colin,
                             batch: "b", reason: nil, source: nil, at: now, undoneAt: nil)
        }
        func line(_ fields: [ProjectChangeField]) -> ProjectChangeLine {
            ProjectChangeLine(id: "c1", projectID: UUID(), projectName: "Vlog 2", who: .colin, at: now, reason: nil, rows: fields.map(row), undoneAt: nil)
        }
        #expect(ResultCard.of(line([.created, .client])) == .creation)
        #expect(ResultCard.of(line([.status, .todo])) == .change)
        // A draft says whom it is for.
        #expect(ResultCard.draftFor([MailAddress(name: "Claire Morel", email: "claire@cabinet-martin.exemple")]) == "Pour Claire")
        #expect(ResultCard.draftFor([]) == "Pour toi")
    }
}

/// « Aujourd'hui », then « Demain » (0.36.0, 18/11): from the hour Paul set (19:00) and once the day's last meeting is
/// over, the Accueil shows tomorrow. Every name here is invented.
@Suite struct HomeDayTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.firstWeekday = 2
        return calendar
    }

    func at(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func event(_ id: String, day: Int, hour: Int, minute: Int = 0, hours: Double = 1, allDay: Bool = false, declined: Bool = false) -> CalendarEventRow {
        CalendarEventRow(account: "moi@exemple.fr", eventID: id, title: id, startAt: at(day, hour, minute), endAt: at(day, hour, minute).addingTimeInterval(hours * 3_600),
                         allDay: allDay, attendees: [Attendee(email: "moi@exemple.fr", response: declined ? "declined" : "accepted", isSelf: true)],
                         updatedAt: at(1))
    }

    func shown(_ events: [CalendarEventRow], at date: Date) -> DayShown {
        HomeModel.dayShown(events, now: date, tomorrowFrom: 19 * 60, calendar: calendar)
    }

    /// Review Focus 2: a meeting under way keeps today; midnight brings the new today, never the day after.
    @Test func theSwitchWaitsForTheLastMeetingAndMidnight() {
        let events = [event("soiree", day: 18, hour: 18, minute: 15, hours: 1.5), event("martin", day: 19, hour: 10),
                      event("nord", day: 19, hour: 15), event("vendredi", day: 20, hour: 11)]
        let early = shown(events, at: at(18, 19, 10))
        #expect(!early.tomorrow && early.title == "Aujourd'hui" && early.events.map(\.eventID) == ["soiree"])
        let evening = shown(events, at: at(18, 20, 1))
        #expect(evening.tomorrow && evening.title == "Demain · jeudi 19 novembre")
        #expect(evening.events.map(\.eventID) == ["martin", "nord"])
        #expect(shown(events, at: at(18, 23, 59)).events.map(\.eventID) == ["martin", "nord"])
        let midnight = shown(events, at: at(19, 0, 1))
        #expect(!midnight.tomorrow && midnight.title == "Aujourd'hui" && midnight.events.map(\.eventID) == ["martin", "nord"])
        // Before the hour, a day already over stays today's.
        #expect(!shown([event("matin", day: 18, hour: 9)], at: at(18, 17)).tomorrow)
    }

    @Test func tomorrowListsWholeDaysFirstAndSkipsDeclined() {
        let events = [event("martin", day: 19, hour: 10), event("refuse", day: 19, hour: 11, declined: true),
                      event("salon", day: 19, hour: 0, hours: 24, allDay: true)]
        #expect(shown(events, at: at(18, 21)).events.map(\.eventID) == ["salon", "martin"])
    }

    @Test func upcomingAfterTomorrow() {
        let events = [event("lundi", day: 23, hour: 9, minute: 30), event("journee", day: 21, hour: 0, hours: 24, allDay: true)]
        #expect(shown(events, at: at(18, 21)).events.isEmpty)
        #expect(HomeModel.upcoming(events, after: at(19), calendar: calendar)?.eventID == "lundi")
    }

    @Test func theSwitchHourIsASetting() {
        #expect(Preferences.Key.homeTomorrowFrom == "accueil.demainAPartirDe")
        #expect(Preferences.Default.homeTomorrowFrom == 1_140)
    }
}
