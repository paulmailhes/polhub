import Foundation
import Persistence
import Testing
@testable import Colin

/// « À valider » (18/11): what waits for Paul's click, said by rules alone. Threads are built from their messages,
/// as the base builds them; every name and address is invented.
@Suite struct ReviewRulesTests {
    static let me = "moi@exemple.fr", other = "moi@atelier.exemple"
    static let mine: Set<String> = [me, other]
    static let marc = "marc@exemple.net", claire = "claire@cabinet.exemple", anne = "anne@maison.exemple"
    static let names = [marc: "Marc Lefèvre", claire: "Claire Morel", anne: "Anne Leroy", me: "Moi", other: "Moi"]
    /// Wednesday 18/11/2026, 10:00 in Paris.
    let now = Date(timeIntervalSince1970: 1_794_992_400)
    let site = UUID(), house = UUID()
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }
    let thresholds = ReviewRules.Thresholds()

    func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    typealias Message = (from: String, daysAgo: Double, labels: [String])
    func received(_ from: String, _ daysAgo: Double) -> Message { (from, daysAgo, ["INBOX", "CATEGORY_PERSONAL"]) }
    func sent(_ daysAgo: Double, from: String = me) -> Message { (from, daysAgo, ["SENT"]) }

    func thread(_ messages: [Message]) -> MailThreadRow { thread("t1", messages) }

    /// A thread as the base keeps it, from its messages.
    func thread(_ id: String, account: String = me, subject: String = "Maquette v2", _ messages: [Message]) -> MailThreadRow {
        let rows = messages.enumerated().map { index, message in
            MailMessageRow(account: account, messageID: "\(id)-\(index)", threadID: id, date: ago(message.daysAgo),
                           sender: MailAddress(name: Self.names[message.from], email: message.from), subject: subject, snippet: "", labels: message.labels)
        }
        return MailThreadRow.aggregate(account: account, threadID: id, messages: rows, mine: Self.mine)!
    }

    /// Paul wrote to Marc (no project) and to Claire and Anne, contacts of one project each.
    var rules: MailFilingRules {
        var rules = MailFilingRules(contactProjects: [Self.claire: [site], Self.anne: [house]], contacts: [Self.claire, Self.anne],
                                    projects: [(site, "Cabinet Martin"), (house, "Maison Leroy")], mine: Self.mine,
                                    correspondents: [Self.marc, Self.claire, Self.anne])
        rules.correspondentStats = [Self.marc: MailCorrespondent(name: "Marc Lefèvre", sent: 3, lastAt: ago(30))]
        return rules
    }

    /// The threads given are copies of one conversation.
    func copies(_ threads: MailThreadRow...) -> [String: String] {
        Dictionary(uniqueKeysWithValues: threads.map { ($0.id, threads[0].id) })
    }

    func replies(_ threads: [MailThreadRow], conversations: [String: String] = [:], dismissed: [ColinDismissalRow] = [], at date: Date? = nil,
                 rules: MailFilingRules? = nil, calendar: Calendar? = nil) -> [ReviewRules.Line] {
        ReviewRules.replies(threads, rules: rules ?? self.rules, conversations: conversations, dismissed: dismissed, now: date ?? now,
                            thresholds: thresholds, calendar: calendar ?? self.calendar)
    }

    /// `recipients`: who Paul wrote to in each thread; without it, the people who wrote in the thread.
    func silent(_ threads: [MailThreadRow], conversations: [String: String] = [:], recipients: [String: [MailAddress]]? = nil,
                events: [CalendarEventRow] = [], dismissed: [ColinDismissalRow] = [], at date: Date? = nil, rules: MailFilingRules? = nil) -> [ReviewRules.Line] {
        let people = recipients ?? Dictionary(uniqueKeysWithValues: threads.map { thread in
            (thread.id, thread.senders.filter { !Self.mine.contains($0.email) })
        })
        return ReviewRules.silent(threads, rules: rules ?? self.rules, conversations: conversations, recipients: people, events: events,
                                  dismissed: dismissed, now: date ?? now, thresholds: thresholds, calendar: calendar)
    }

    func person(_ email: String) -> MailAddress { MailAddress(name: Self.names[email], email: email) }

    func event(_ id: String, project: UUID? = nil, origin: EventProjectOrigin? = nil, meeting: Bool = true, daysAgo: Double, title: String = "Point Cabinet Martin") -> CalendarEventRow {
        CalendarEventRow(account: Self.me, eventID: id, title: title, startAt: ago(daysAgo), endAt: ago(daysAgo).addingTimeInterval(3_600),
                         projectID: project, projectOrigin: origin, meetingID: meeting ? UUID() : nil, updatedAt: now)
    }

    // MARK: - « Attend ta réponse »

    @Test func aThreadWaitsAfterThreeDays() {
        let waiting = thread([sent(10), received(Self.marc, 4)])
        let lines = replies([waiting])
        #expect(lines.count == 1)
        let expected = ReviewRules.Line(id: "reply:\(waiting.id)", kind: .reply, person: "Marc", days: 4, threadKey: waiting.id)
        #expect(lines == [expected])
        #expect(replies([thread([sent(10), received(Self.marc, 2)])]).isEmpty)
        #expect(replies([thread([sent(10), received(Self.marc, 2.99)])]).isEmpty)
        #expect(replies([thread([sent(10), received(Self.marc, 3)])]).first?.days == 3)
    }

    @Test func aThreadPaulAnsweredLastNeverWaits() {
        // The last message Paul did not write is Marc's, and Paul answered after it.
        let answered = thread([received(Self.marc, 5), sent(4)])
        #expect(answered.lastSender == Self.marc)
        #expect(replies([answered]).isEmpty)
    }

    @Test func aStrangerOrANewsletterNeverWaits() throws {
        // Someone Paul never wrote to.
        #expect(replies([thread([received("inconnu@exemple.org", 4)])]).isEmpty)
        // A sender Paul placed among the notifications, even one he wrote to.
        var placed = rules
        // (As the base holds it: this row has no public initializer.)
        let row = #"{"address":"marc@exemple.net","principal":false,"images":false,"createdAt":0,"tab":"notifications"}"#
        placed.senders = [Self.marc: try JSONDecoder().decode(MailSenderRow.self, from: Data(row.utf8))]
        #expect(replies([thread([received(Self.marc, 4)])], rules: placed).isEmpty)
        #expect(replies([thread([received(Self.marc, 4)])]).count == 1)
    }

    @Test func aReplyAwaitedInAProjectNamesIt() {
        let waiting = thread([sent(10), received(Self.claire, 5)])
        let line = replies([waiting]).first
        #expect(line?.person == "Claire" && line?.detail == "Cabinet Martin" && line?.projectID == site && line?.days == 5)
    }

    @Test func aHiddenThreadNeverWaits() {
        // A thread that waits, then hidden with its turn left as it was: it does not show.
        var hidden = thread([sent(10), received(Self.marc, 4)])
        #expect(replies([hidden]).count == 1)
        hidden.hidden = true
        #expect(replies([hidden]).isEmpty)
        var quiet = thread([received(Self.claire, 12), sent(9)])
        quiet.hidden = true
        #expect(silent([quiet]).isEmpty)
    }

    @Test func twoThreadsOfOneSubjectAreTwoConversations() {
        // « Devis » from Marc and « Devis » from Claire: nothing says they are one conversation.
        let first = thread("t1", subject: "Devis", [sent(30), received(Self.marc, 4)])
        let second = thread("t2", subject: "Devis", [sent(30), received(Self.claire, 6)])
        #expect(replies([first, second]).map(\.threadKey) == [second.id, first.id])
        // Even received at the very same instant.
        let twin = thread("t3", subject: "Devis", [sent(30), received(Self.claire, 4)])
        #expect(replies([first, twin]).count == 2)
    }

    // MARK: - « Ne répond plus »

    @Test func aClientIsSilentAfterSevenDaysInAProjectOnly() {
        let waiting = thread([received(Self.claire, 12), sent(9)])
        let lines = silent([waiting])
        let expected = ReviewRules.Line(id: "silent:\(waiting.id)", kind: .silent, person: "Claire", detail: "Cabinet Martin", days: 9,
                                        threadKey: waiting.id, projectID: site)
        #expect(lines == [expected])
        // The same silence outside any project says nothing.
        #expect(silent([thread([received(Self.marc, 12), sent(9)])]).isEmpty)
        #expect(silent([thread([received(Self.claire, 12), sent(6)])]).isEmpty)
        #expect(silent([thread([received(Self.claire, 12), sent(7)])]).first?.days == 7)
        // She answered since: not silent.
        #expect(silent([thread([sent(9), received(Self.claire, 2)])]).isEmpty)
    }

    @Test func aMailPaulStartedThatNobodyAnsweredIsSilent() {
        // No one but Paul wrote in the thread: the project is the one of the person he wrote to.
        let started = thread([sent(9)])
        #expect(started.lastReceivedAt == nil && started.lastSender == nil)
        let line = silent([started], recipients: [started.id: [person(Self.claire)]]).first
        #expect(line?.person == "Claire" && line?.detail == "Cabinet Martin" && line?.projectID == site && line?.days == 9)
        // His own other address in copy is nobody to wait for.
        let copied = silent([started], recipients: [started.id: [MailAddress(email: Self.other), person(Self.claire)]]).first
        #expect(copied?.person == "Claire" && copied?.projectID == site)
        // Written to someone of no project, or to people of two projects: no project, no line.
        #expect(silent([started], recipients: [started.id: [person(Self.marc)]]).isEmpty)
        #expect(silent([started], recipients: [started.id: [person(Self.claire), person(Self.anne)]]).isEmpty)
        #expect(silent([started], recipients: [:]).isEmpty)
        // A thread Paul filed himself outside any project stays there.
        var filed = rules
        filed.choices = [started.id: .perso]
        #expect(silent([started], recipients: [started.id: [person(Self.claire)]], rules: filed).isEmpty)
    }

    @Test func theSilentOneIsWhoPaulAnswered() {
        // Paul wrote first to Anne, long ago, and last to Claire, who had written: Claire is the one who is silent.
        let waiting = thread([received(Self.claire, 12), sent(9)])
        let line = silent([waiting], recipients: [waiting.id: [person(Self.anne), person(Self.claire)]]).first
        #expect(line?.person == "Claire")
    }

    @Test func aComingEventOfTheProjectHidesTheSilence() {
        let waiting = thread([received(Self.claire, 12), sent(9)])
        #expect(silent([waiting], events: [event("e1", project: site, daysAgo: -1)]).isEmpty)
        // A past event of the project, or a coming one of another project, hides nothing.
        #expect(silent([waiting], events: [event("e2", project: site, daysAgo: 3), event("e3", project: house, daysAgo: -1)]).count == 1)
    }

    @Test func nothingOlderThanTheCeiling() {
        #expect(replies([thread([sent(60), received(Self.marc, 46)])]).isEmpty)
        #expect(replies([thread([sent(60), received(Self.marc, 45)])]).count == 1)
        #expect(silent([thread([received(Self.claire, 60), sent(46)])]).isEmpty)
        #expect(silent([thread([received(Self.claire, 60), sent(45)])]).count == 1)
    }

    // MARK: - What Paul sets aside

    @Test func notNeededHidesUntilANewMessage() {
        let waiting = thread([sent(10), received(Self.marc, 4)])
        let aside = ColinDismissalRow(kind: "reply", subject: waiting.id, reason: .notNeeded, createdAt: ago(1))
        #expect(replies([waiting], dismissed: [aside]).isEmpty)
        // Marc writes again after it: three days later, the line is back.
        let again = thread([sent(10), received(Self.marc, 4), received(Self.marc, 0.5)])
        #expect(replies([again], dismissed: [aside]).isEmpty)
        #expect(replies([again], dismissed: [aside], at: now.addingTimeInterval(3 * 86_400)).first?.days == 3)
        // « Elle a répondu ailleurs » hides the same way.
        let elsewhere = ColinDismissalRow(kind: "reply", subject: waiting.id, reason: .answeredElsewhere, createdAt: ago(1))
        #expect(replies([waiting], dismissed: [elsewhere]).isEmpty)
        // What was set aside for another kind of line says nothing here.
        #expect(replies([waiting], dismissed: [ColinDismissalRow(kind: "silent", subject: waiting.id, reason: .notNeeded, createdAt: ago(1))]).count == 1)
    }

    @Test func aMessageThatCameWhilePaulClickedBringsTheLineBack() {
        // Paul sets aside what he sees: Marc's mail of four days ago. Marc had written again an hour before the
        // click, and hub only read it after: that message is newer than what Paul saw.
        let seen = thread([sent(10), received(Self.marc, 4)])
        let aside = ColinDismissalRow(kind: "reply", subject: seen.id, reason: .notNeeded, createdAt: now, lastMessageAt: ago(4))
        #expect(replies([seen], dismissed: [aside]).isEmpty)
        let again = thread([sent(10), received(Self.marc, 4), received(Self.marc, 1.0 / 24)])
        #expect(replies([again], dismissed: [aside], at: now.addingTimeInterval(3 * 86_400)).count == 1)
        // A row of before, which kept no such date, goes by the time of the click.
        let old = ColinDismissalRow(kind: "reply", subject: seen.id, reason: .notNeeded, createdAt: now)
        #expect(replies([again], dismissed: [old], at: now.addingTimeInterval(3 * 86_400)).isEmpty)
        // The same instant as what he saw is what he saw.
        #expect(replies([seen], dismissed: [aside], at: now.addingTimeInterval(86_400)).isEmpty)
    }

    @Test func laterFollowsTheCalendarItIsGiven() {
        // 10:00 in Paris is 22:00 in Auckland: there, the next day begins two hours later.
        let waiting = thread([sent(10), received(Self.marc, 4)])
        let later = ColinDismissalRow(kind: "reply", subject: waiting.id, reason: .later, createdAt: now)
        var auckland = Calendar(identifier: .gregorian)
        auckland.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        #expect(replies([waiting], dismissed: [later], at: now.addingTimeInterval(1.5 * 3_600), calendar: auckland).isEmpty)
        #expect(replies([waiting], dismissed: [later], at: now.addingTimeInterval(2.5 * 3_600), calendar: auckland).count == 1)
        #expect(replies([waiting], dismissed: [later], at: now.addingTimeInterval(2.5 * 3_600)).isEmpty)
    }

    @Test func laterComesBackTheNextDay() {
        let waiting = thread([sent(10), received(Self.marc, 4)])
        let later = ColinDismissalRow(kind: "reply", subject: waiting.id, reason: .later, createdAt: now)
        #expect(replies([waiting], dismissed: [later]).isEmpty)
        // 10:00 on the 18th: still aside at 23:30, back at 00:30 on the 19th.
        #expect(replies([waiting], dismissed: [later], at: now.addingTimeInterval(13.5 * 3_600)).isEmpty)
        #expect(replies([waiting], dismissed: [later], at: now.addingTimeInterval(14.5 * 3_600)).count == 1)
    }

    @Test func twiceAnsweredElsewhereSilencesTheProject() {
        let first = thread("t1", subject: "Devis", [received(Self.claire, 20), sent(15)])
        let second = thread("t2", subject: "Maquette", [received(Self.claire, 20), sent(12)])
        let third = thread("t3", subject: "Logo", [received(Self.claire, 20), sent(9)])
        let elsewhere = { (thread: MailThreadRow, days: Double) in
            ColinDismissalRow(kind: "silent", subject: thread.id, reason: .answeredElsewhere, projectID: self.site, createdAt: self.ago(days))
        }
        #expect(silent([first, second, third]).count == 3)
        // Once: that thread alone.
        #expect(silent([first, second, third], dismissed: [elsewhere(first, 1)]).map(\.threadKey) == [second.id, third.id])
        // Twice on the project: Colin no longer says it of this project. Another project still speaks.
        let anne = thread("t4", subject: "Plans", [received(Self.anne, 20), sent(10)])
        #expect(silent([first, second, third, anne], dismissed: [elsewhere(first, 1), elsewhere(second, 1)]).map(\.threadKey) == [anne.id])
        // « Pas besoin », twice, silences nothing else.
        let notNeeded = { (thread: MailThreadRow) in
            ColinDismissalRow(kind: "silent", subject: thread.id, reason: .notNeeded, projectID: self.site, createdAt: self.ago(1))
        }
        #expect(silent([first, second, third], dismissed: [notNeeded(first), notNeeded(second)]).map(\.threadKey) == [third.id])
        // Said twice of the same thread (she answers on her phone, every time): the project is silenced too.
        let twice = ColinDismissalRow(kind: "silent", subject: first.id, reason: .answeredElsewhere, projectID: site, createdAt: ago(1), times: 2)
        #expect(silent([first, second, third, anne], dismissed: [twice]).map(\.threadKey) == [anne.id])
        // Only what was said of a silence counts, and only with its project.
        let ofAReply = ColinDismissalRow(kind: "reply", subject: first.id, reason: .answeredElsewhere, projectID: site, createdAt: ago(1), times: 2)
        let withoutProject = ColinDismissalRow(kind: "silent", subject: first.id, reason: .answeredElsewhere, createdAt: ago(1), times: 2)
        #expect(silent([first, second, third], dismissed: [ofAReply]).count == 3)
        #expect(silent([first, second, third], dismissed: [withoutProject]).map(\.threadKey) == [second.id, third.id])
    }

    // MARK: - « Brouillon prêt »

    func draft(_ id: String, origin: MailDraftRow.Origin = .agent, to: [MailAddress] = [MailAddress(name: "Claire Morel", email: claire)],
               minutesAgo: Double = 0, thread: String? = nil) -> MailDraftRow {
        MailDraftRow(id: id, account: Self.me, mode: thread == nil ? .new : .reply, threadKey: thread, to: to, subject: "Devis", body: "Bonjour",
                     origin: origin, createdAt: now.addingTimeInterval(-minutesAgo * 60))
    }

    @Test func aProgrammedOrLeavingDraftIsNotReady() {
        let ready = draft("d1", thread: "moi@exemple.fr|t1")
        // Without a project, the line says the subject of the mail.
        let expected = ReviewRules.Line(id: "draft:d1", kind: .draft, person: "Claire", detail: "Devis", threadKey: "moi@exemple.fr|t1", draftID: "d1")
        #expect(ReviewRules.drafts([ready], hidden: []) == [expected])
        // Programmed, or on its way out.
        #expect(ReviewRules.drafts([ready], hidden: ["d1"]).isEmpty)
        // Paul's own draft, or one written in Gmail, is not prepared by an agent.
        #expect(ReviewRules.drafts([draft("d2", origin: .paul), draft("d3", origin: .gmail)], hidden: []).isEmpty)
        // The most recent first; one without a recipient has no name.
        let lines = ReviewRules.drafts([draft("vieux", minutesAgo: 90), draft("neuf", minutesAgo: 5), draft("seul", to: [], minutesAgo: 30)], hidden: [])
        #expect(lines.map(\.draftID) == ["neuf", "seul", "vieux"])
        #expect(lines[1].person.isEmpty)
    }

    /// « Brouillon prêt pour Claire · Cabinet Martin »: the project of the thread it answers; for a new mail, the
    /// one project of the people it is written to; else the subject of the mail.
    @Test func aDraftSaysItsProjectElseItsSubject() {
        // A reply in a thread Paul filed in « Maison Leroy », written to Claire (of « Cabinet Martin »): the thread wins.
        let filed = thread("t1", [received(Self.claire, 2)])
        var chosen = rules
        chosen.choices[filed.id] = .project(house)
        let reply = ReviewRules.drafts([draft("d1", thread: filed.id)], hidden: [], threads: [filed], rules: chosen)
        #expect(reply.first?.detail == "Maison Leroy" && reply.first?.projectID == house)
        // A new mail to Claire: her one project.
        let new = ReviewRules.drafts([draft("d2")], hidden: [], threads: [], rules: rules)
        #expect(new.first?.detail == "Cabinet Martin" && new.first?.projectID == site)
        // To Claire and Anne, of two projects: no project is said, the subject is.
        let both = ReviewRules.drafts([draft("d3", to: [person(Self.claire), person(Self.anne)])], hidden: [], threads: [], rules: rules)
        #expect(both.first?.detail == "Devis" && both.first?.projectID == nil)
        // To Marc, of no project; and a reply whose thread is not among those read.
        #expect(ReviewRules.drafts([draft("d4", to: [person(Self.marc)])], hidden: [], threads: [], rules: rules).first?.detail == "Devis")
        #expect(ReviewRules.drafts([draft("d5", to: [person(Self.marc)], thread: "moi@exemple.fr|ailleurs")], hidden: [], threads: [filed], rules: chosen).first?.detail == "Devis")
    }

    // MARK: - « Réunion à ranger »

    @Test func anEventPaulFiledUnderNoneIsNotToFile() {
        let toFile = event("e1", daysAgo: 2)
        let expected = ReviewRules.Line(id: "unfiled:\(toFile.id)", kind: .unfiled, person: "Point Cabinet Martin", eventID: toFile.id)
        #expect(ReviewRules.unfiled([toFile], now: now) == [expected])
        // Paul said « Aucun »; already in a project; never recorded; too old; not yet held.
        #expect(ReviewRules.unfiled([event("e2", origin: .paul, daysAgo: 2), event("e3", project: site, origin: .titre, daysAgo: 2),
                                     event("e4", meeting: false, daysAgo: 2), event("e5", daysAgo: 15), event("e6", daysAgo: -1)], now: now).isEmpty)
        #expect(ReviewRules.unfiled([event("e7", daysAgo: 14)], now: now).count == 1)
        // The most recent first.
        #expect(ReviewRules.unfiled([event("vieux", daysAgo: 9), event("neuf", daysAgo: 1)], now: now).compactMap(\.eventID).map { $0.hasSuffix("neuf") } == [true, false])
    }

    @Test func oneMeetingInTwoCalendarsIsOneLine() {
        // The same recording linked to the copies of one event in two of Paul's calendars.
        let recording = UUID()
        func copy(_ account: String) -> CalendarEventRow {
            CalendarEventRow(account: account, eventID: "e1", title: "Point Cabinet Martin", startAt: ago(2), endAt: ago(2).addingTimeInterval(3_600),
                             meetingID: recording, updatedAt: now)
        }
        #expect(ReviewRules.unfiled([copy(Self.me), copy(Self.other)], now: now).count == 1)
        #expect(ReviewRules.unfiled([event("e2", daysAgo: 2), event("e3", daysAgo: 3)], now: now).count == 2)
    }

    @Test func aMeetingSetAsideDoesNotComeBack() {
        let toFile = event("e1", daysAgo: 2)
        let notNeeded = ColinDismissalRow(kind: "unfiled", subject: toFile.id, reason: .notNeeded, createdAt: ago(1))
        #expect(ReviewRules.unfiled([toFile], dismissed: [notNeeded], now: now, calendar: calendar).isEmpty)
        let later = ColinDismissalRow(kind: "unfiled", subject: toFile.id, reason: .later, createdAt: now)
        #expect(ReviewRules.unfiled([toFile], dismissed: [later], now: now, calendar: calendar).isEmpty)
        #expect(ReviewRules.unfiled([toFile], dismissed: [later], now: now.addingTimeInterval(86_400), calendar: calendar).count == 1)
    }

    // MARK: - Read by person and by project

    /// The same messages as the exchange reads them: who wrote to whom. Paul's go to `to`; the others come to him.
    func exchanges(_ id: String, account: String = me, to: [String] = [], calendar: Bool = false, automatic: Bool = false, _ messages: [Message]) -> [MailExchange] {
        messages.map { message in
            let isMine = Self.mine.contains(message.from)
            return MailExchange(threadKey: MailThreadRow.key(account: account, threadID: id), date: ago(message.daysAgo), mine: isMine, sender: message.from,
                                recipients: isMine ? to : [account], calendar: !isMine && calendar, automatic: !isMine && automatic)
        }
    }

    func byPerson(_ threads: [MailThreadRow], _ messages: [MailExchange], drafts: [MailDraftRow] = [], events: [CalendarEventRow] = [],
                  dismissed: [ColinDismissalRow] = [], rules: MailFilingRules? = nil) -> [ReviewRules.Line] {
        ReviewRules.repliesByPerson(threads, rules: rules ?? self.rules, exchanges: Exchanges(messages), drafts: drafts, events: events, dismissed: dismissed,
                                    now: now, thresholds: thresholds, calendar: calendar)
    }

    func byProject(_ threads: [MailThreadRow], _ messages: [MailExchange], events: [CalendarEventRow] = [], finished: Set<UUID> = [],
                   dismissed: [ColinDismissalRow] = []) -> [ReviewRules.Line] {
        let people = Dictionary(uniqueKeysWithValues: threads.map { thread in (thread.id, thread.senders.filter { !Self.mine.contains($0.email) }) })
        let projects = ReviewRules.projects(of: threads, rules: rules, recipients: people)
        return ReviewRules.silentByProject(threads, rules: rules, recipients: people, exchanges: Exchanges(messages, projects: projects), events: events,
                                           finished: finished, dismissed: dismissed, now: now, thresholds: thresholds, calendar: calendar)
    }

    func meeting(with address: String, daysAgo: Double, declined: Bool = false, allDay: Bool = false) -> CalendarEventRow {
        CalendarEventRow(account: Self.me, eventID: "rdv-\(daysAgo)-\(declined)-\(allDay)", title: "Point", startAt: ago(daysAgo), endAt: ago(daysAgo).addingTimeInterval(1_800),
                         allDay: allDay, attendees: [Attendee(email: Self.me, response: declined ? "declined" : "accepted", isSelf: true),
                                                    Attendee(email: address, response: "accepted", isSelf: false)], updatedAt: now)
    }

    /// Marc wrote four days ago, in a thread Paul had begun.
    var marcWaits: (threads: [MailThreadRow], messages: [MailExchange]) {
        ([thread("t1", [sent(10), received(Self.marc, 4)])], exchanges("t1", to: [Self.marc], [sent(10), received(Self.marc, 4)]))
    }

    /// The count on Paul's own mails: he answers in a new mail more often than in the thread.
    @Test func aPersonAnsweredInANewThreadNoLongerWaits() {
        let (threads, messages) = marcWaits
        #expect(byPerson(threads, messages).map(\.id) == ["reply:\(Self.marc)"])
        // Two days ago Paul wrote to him, in a new thread: he no longer waits.
        let recap = thread("t2", subject: "Maquette : tes retours sont intégrés", [sent(2)])
        #expect(byPerson(threads + [recap], messages + exchanges("t2", to: [Self.marc], [sent(2)])).isEmpty)
        // In copy of a mail to someone else: he was written to.
        #expect(byPerson(threads + [recap], messages + exchanges("t2", to: [Self.claire, Self.marc], [sent(2)])).isEmpty)
        // A mail to someone else answers nothing; nor what Paul wrote him before his message.
        #expect(byPerson(threads + [recap], messages + exchanges("t2", to: [Self.claire], [sent(2)])).count == 1)
        #expect(byPerson(threads + [recap], messages + exchanges("t2", to: [Self.marc], [sent(5)])).count == 1)
    }

    @Test func oneLineByPersonOnTheirOldestThread() {
        // Marc sent his files in three threads.
        let threads = [thread("t1", [received(Self.marc, 5)]), thread("t2", [received(Self.marc, 9)]), thread("t3", [received(Self.marc, 4)])]
        let messages = exchanges("t1", [received(Self.marc, 5)]) + exchanges("t2", [received(Self.marc, 9)]) + exchanges("t3", [received(Self.marc, 4)])
        let lines = byPerson(threads, messages)
        #expect(lines.count == 1)
        #expect(lines.first?.days == 9 && lines.first?.threadKey == threads[1].id && lines.first?.person == "Marc")
        // Set aside under the person, with the latest message Paul had before him.
        #expect(lines.first?.id == "reply:\(Self.marc)" && lines.first?.lastMessageAt == ago(4))
        #expect(lines.first.map(ReviewRules.subject(of:)) == Self.marc)
        // Two people: two lines, the oldest first.
        let claire = thread("t4", [received(Self.claire, 12)])
        #expect(byPerson(threads + [claire], messages + exchanges("t4", [received(Self.claire, 12)])).map(\.person) == ["Claire", "Marc"])
    }

    @Test func aPersonIsSetAsideUntilTheyWriteAgain() {
        let threads = [thread("t1", [received(Self.marc, 9)]), thread("t2", [received(Self.marc, 4)])]
        let messages = exchanges("t1", [received(Self.marc, 9)]) + exchanges("t2", [received(Self.marc, 4)])
        let aside = ColinDismissalRow(kind: "reply", subject: Self.marc, reason: .notNeeded, createdAt: ago(1), lastMessageAt: ago(4))
        #expect(byPerson(threads, messages, dismissed: [aside]).isEmpty)
        // He writes again, in a third thread: the line is back.
        let again = thread("t3", [received(Self.marc, 3)])
        #expect(byPerson(threads + [again], messages + exchanges("t3", [received(Self.marc, 3)]), dismissed: [aside]).count == 1)
        // Someone else set aside says nothing of him.
        let other = ColinDismissalRow(kind: "reply", subject: Self.claire, reason: .notNeeded, createdAt: ago(1), lastMessageAt: ago(4))
        #expect(byPerson(threads, messages, dismissed: [other]).count == 1)
    }

    /// Set aside, a person comes back by a new message: the line opens the thread of that message, at its age, not
    /// the thread Paul already said needed nothing (audit of 19/11).
    @Test func aPersonBackFromAsideIsSaidOnTheirNewThread() {
        // Marc wrote eight days ago; four days ago Paul said « Pas besoin » with that mail before him.
        let first = thread("t1", [received(Self.marc, 8)])
        let said = exchanges("t1", [received(Self.marc, 8)])
        let aside = ColinDismissalRow(kind: "reply", subject: Self.marc, reason: .notNeeded, createdAt: ago(4), lastMessageAt: ago(8))
        #expect(byPerson([first], said, dismissed: [aside]).isEmpty)
        // Half a day after the click, Marc wrote again in a new thread: three days later, the line is back on it.
        let again = thread("t3", [received(Self.marc, 3.5)])
        let lines = byPerson([first, again], said + exchanges("t3", [received(Self.marc, 3.5)]), dismissed: [aside])
        #expect(lines.map(\.threadKey) == [again.id])
        #expect(lines.first?.days == 3)
        // « Plus tard » hides the person until the next day, whatever the thread, as before.
        let later = ColinDismissalRow(kind: "reply", subject: Self.marc, reason: .later, createdAt: now, lastMessageAt: ago(8))
        #expect(byPerson([first, again], said + exchanges("t3", [received(Self.marc, 3.5)]), dismissed: [later]).isEmpty)
    }

    /// An invitation, an answer to one, a list's mail, an absent mailbox's answer: sent from a person's address,
    /// and nobody expects an answer to them.
    @Test func aCalendarsMailOrAnAutomaticOneNeverWaits() {
        let threads = [thread("t1", subject: "Invitation: Point", [received(Self.marc, 4)])]
        #expect(byPerson(threads, exchanges("t1", calendar: true, [received(Self.marc, 4)])).isEmpty)
        #expect(byPerson(threads, exchanges("t1", automatic: true, [received(Self.marc, 4)])).isEmpty)
        #expect(byPerson(threads, exchanges("t1", [received(Self.marc, 4)])).count == 1)
        // The last message decides: an invitation, then a question about it, waits.
        let asked = [thread("t1", [received(Self.marc, 6), received(Self.marc, 4)])]
        let messages = exchanges("t1", calendar: true, [received(Self.marc, 6)]) + exchanges("t1", [received(Self.marc, 4)])
        #expect(byPerson(asked, messages).count == 1)
    }

    /// Someone of one of Paul's own domains is a colleague: they speak elsewhere.
    @Test func aColleagueNeverWaits() {
        var known = rules
        known.correspondents.formUnion(["lea@exemple.fr", "ami@gmail.com"])
        #expect(byPerson([thread("t1", [received("lea@exemple.fr", 4)])], exchanges("t1", [received("lea@exemple.fr", 4)]), rules: known).isEmpty)
        // One of Paul's mailboxes is at everyone's: a domain of everyone is nobody's.
        known.mine.insert("moi@gmail.com")
        #expect(byPerson([thread("t1", [received("ami@gmail.com", 4)])], exchanges("t1", [received("ami@gmail.com", 4)]), rules: known).count == 1)
    }

    /// A draft to the person, an agent's or Paul's own, in To or in copy: the answer is being written.
    @Test func aDraftToThePersonIsTheirLine() {
        let (threads, messages) = marcWaits
        #expect(byPerson(threads, messages, drafts: [draft("d1", to: [person(Self.marc)])]).isEmpty)
        #expect(byPerson(threads, messages, drafts: [draft("d2", origin: .paul, to: [person(Self.marc)])]).isEmpty)
        var copied = draft("d4", origin: .paul)
        copied.cc = [person(Self.marc)]
        #expect(byPerson(threads, messages, drafts: [copied]).isEmpty)
        #expect(byPerson(threads, messages, drafts: [draft("d3")]).count == 1)
    }

    /// A draft begun before the person's message, and left in Brouillons, answers nothing they wrote after it: else
    /// a reply Paul gave up on would hide everything they write him.
    @Test func aDraftOlderThanTheMessageAnswersNothing() {
        let (threads, messages) = marcWaits
        // Begun twenty days ago, before Marc's message of four days ago.
        #expect(byPerson(threads, messages, drafts: [draft("old", origin: .paul, to: [person(Self.marc)], minutesAgo: 20 * 1_440)]).count == 1)
        // Touched again since his message: it is the answer being written.
        var touched = draft("old", origin: .paul, to: [person(Self.marc)], minutesAgo: 20 * 1_440)
        touched.updatedAt = ago(1)
        #expect(byPerson(threads, messages, drafts: [touched]).isEmpty)
    }

    /// A reply begun after the person's message and then left (a ⌘R, an interruption): untouched for longer than
    /// the threshold, it no longer says that the answer is being written, and the person waits again (audit of
    /// 19/11). Programmed, or on its way out, it answers whatever its age.
    @Test func aDraftLeftAloneStopsHidingTheLine() {
        let threads = [thread("t1", [sent(20), received(Self.marc, 8)])]
        let messages = exchanges("t1", to: [Self.marc], [sent(20), received(Self.marc, 8)])
        // Begun six days ago, two days after Marc's message, and never touched since.
        var left = draft("r1", origin: .paul, to: [person(Self.marc)], minutesAgo: 6 * 1_440, thread: threads[0].id)
        #expect(byPerson(threads, messages, drafts: [left]).map(\.id) == ["reply:\(Self.marc)"])
        // Programmed, or leaving for Gmail: the answer is on its way.
        #expect(ReviewRules.repliesByPerson(threads, rules: rules, exchanges: Exchanges(messages), drafts: [left], outgoing: ["r1"], dismissed: [], now: now,
                                            thresholds: thresholds, calendar: calendar).isEmpty)
        // Touched yesterday: it is the answer being written.
        left.updatedAt = ago(1)
        #expect(byPerson(threads, messages, drafts: [left]).isEmpty)
        // The same for a reply begun in Gmail: what Gmail dated six days ago is left.
        let gmail = MailMessageRow(account: Self.me, messageID: "g1", threadID: "t1", date: ago(6), sender: MailAddress(email: Self.me),
                                   to: [MailAddress(email: Self.marc)], subject: "Re: Maquette v2", snippet: "", labels: ["DRAFT"])
        #expect(ReviewRules.repliesByPerson(threads, rules: rules, exchanges: Exchanges(messages), gmailDrafts: [gmail], dismissed: [], now: now,
                                            thresholds: thresholds, calendar: calendar).count == 1)
    }

    /// A reply begun in Gmail, on the phone or the web, is a draft too: hub knows it as a message of Gmail's.
    @Test func aDraftBegunInGmailIsTheirLineToo() {
        let (threads, messages) = marcWaits
        func gmail(_ to: String, daysAgo: Double) -> MailMessageRow {
            MailMessageRow(account: Self.me, messageID: "g-\(daysAgo)", threadID: "t1", date: ago(daysAgo), sender: MailAddress(email: Self.me),
                           to: [MailAddress(email: to)], subject: "Re: Maquette v2", snippet: "", labels: ["DRAFT"])
        }
        func lines(_ drafts: [MailMessageRow]) -> [ReviewRules.Line] {
            ReviewRules.repliesByPerson(threads, rules: rules, exchanges: Exchanges(messages), gmailDrafts: drafts, dismissed: [], now: now,
                                        thresholds: thresholds, calendar: calendar)
        }
        #expect(lines([gmail(Self.marc, daysAgo: 1)]).isEmpty)
        #expect(lines([gmail(Self.marc, daysAgo: 20)]).count == 1)
        #expect(lines([gmail(Self.claire, daysAgo: 1)]).count == 1)
    }

    /// « Pas besoin » holds until the person writes again after Paul's click: a message of theirs already there,
    /// too young then to be counted, does not bring the line back when it grows old enough.
    @Test func aPersonSetAsideStaysAsideWhenTheirYoungerMailGrowsOld() {
        // Marc wrote nine days ago, and again yesterday in a new thread.
        let threads = [thread("t1", [received(Self.marc, 9)]), thread("t2", [received(Self.marc, 1)])]
        let messages = exchanges("t1", [received(Self.marc, 9)]) + exchanges("t2", [received(Self.marc, 1)])
        let shown = byPerson(threads, messages)
        #expect(shown.count == 1 && shown.first?.days == 9)
        // The last message Paul has before him is yesterday's.
        #expect(shown.first?.lastMessageAt == ago(1))
        let aside = ColinDismissalRow(kind: "reply", subject: Self.marc, reason: .notNeeded, createdAt: now, lastMessageAt: shown.first?.lastMessageAt)
        // Three days later, yesterday's mail is old enough to be counted: the line stays aside.
        let later = now.addingTimeInterval(3 * 86_400)
        #expect(ReviewRules.repliesByPerson(threads, rules: rules, exchanges: Exchanges(messages), dismissed: [aside], now: later, thresholds: thresholds,
                                            calendar: calendar).isEmpty)
    }

    /// An absent mailbox's answer, or a calendar's mail, is nobody's answer: the client is still silent, whether
    /// it came in a thread of its own or in the thread itself.
    @Test func anAutomaticAnswerIsNoAnswerToASilence() {
        let (threads, messages) = claireIsSilent
        // In a thread of its own, filed nowhere: Claire did not « write since ».
        let away = thread("t2", subject: "Réponse automatique : Devis", [received(Self.claire, 9.9)])
        #expect(byProject(threads + [away], messages + exchanges("t2", automatic: true, [received(Self.claire, 9.9)])).count == 1)
        #expect(byProject(threads + [away], messages + exchanges("t2", calendar: true, [received(Self.claire, 9.9)])).count == 1)
        // A real answer of hers there: she wrote.
        #expect(byProject(threads + [away], messages + exchanges("t2", [received(Self.claire, 9.9)])).isEmpty)
        // In the thread itself, after Paul's mail.
        let same = thread("t1", subject: "Devis", [received(Self.claire, 30), sent(10), received(Self.claire, 9.9)])
        let said = exchanges("t1", to: [Self.claire], [received(Self.claire, 30), sent(10)]) + exchanges("t1", automatic: true, [received(Self.claire, 9.9)])
        let lines = byProject([same], said)
        #expect(lines.count == 1 && lines.first?.days == 10)
        // A real answer in the thread: no silence.
        #expect(byProject([same], exchanges("t1", to: [Self.claire], [received(Self.claire, 30), sent(10), received(Self.claire, 9.9)])).isEmpty)
    }

    /// A colleague Paul put in copy writes to him every day about everything: that says nothing of the client.
    @Test func aColleagueInCopyDoesNotBreakASilence() {
        var known = rules
        known.mine.insert("moi@atelier.exemple")
        let quote = thread("t1", subject: "Devis", [received(Self.claire, 30), sent(10)])
        let said = exchanges("t1", to: [Self.claire, "lea@atelier.exemple"], [received(Self.claire, 30), sent(10)])
            + exchanges("t9", [received("lea@atelier.exemple", 2)])
        let people = [quote.id: [MailAddress(email: Self.claire)]]
        let projects = ReviewRules.projects(of: [quote], rules: known, recipients: people)
        let lines = ReviewRules.silentByProject([quote], rules: known, recipients: people, exchanges: Exchanges(said, projects: projects), events: [],
                                                dismissed: [], now: now, thresholds: thresholds, calendar: calendar)
        #expect(lines.count == 1)
    }

    /// Paul answers by a call as often as by a mail: a meeting with the person, held since or to come within a week.
    @Test func aMeetingWithThePersonAnswers() {
        let (threads, messages) = marcWaits
        #expect(byPerson(threads, messages, events: [meeting(with: Self.marc, daysAgo: 2)]).isEmpty)
        #expect(byPerson(threads, messages, events: [meeting(with: Self.marc, daysAgo: -5)]).isEmpty)
        // Before his message, in three weeks, declined, a whole day, or with someone else: he waits.
        for event in [meeting(with: Self.marc, daysAgo: 6), meeting(with: Self.marc, daysAgo: -21), meeting(with: Self.marc, daysAgo: 2, declined: true),
                      meeting(with: Self.marc, daysAgo: 2, allDay: true), meeting(with: Self.claire, daysAgo: 2)] {
            #expect(byPerson(threads, messages, events: [event]).count == 1, "\(event.eventID)")
        }
    }

    @Test func afterTwoWeeksAMessageNoLongerWaits() {
        #expect(byPerson([thread("t1", [received(Self.marc, 14)])], exchanges("t1", [received(Self.marc, 14)])).count == 1)
        #expect(byPerson([thread("t1", [received(Self.marc, 15)])], exchanges("t1", [received(Self.marc, 15)])).isEmpty)
        #expect(ReviewRules.Thresholds().replyMaxDays == 14)
    }

    /// Paul answered Claire ten days ago, in a thread of « Cabinet Martin ».
    var claireIsSilent: (threads: [MailThreadRow], messages: [MailExchange]) {
        ([thread("t1", subject: "Devis", [received(Self.claire, 30), sent(10)])], exchanges("t1", to: [Self.claire], [received(Self.claire, 30), sent(10)]))
    }

    @Test func oneLineByProjectOnItsLastMail() {
        // Two threads of « Cabinet Martin » where Paul wrote last: twenty days ago, and eight days ago.
        let old = thread("t1", subject: "Devis", [received(Self.claire, 30), sent(20)])
        let recent = thread("t2", subject: "Plans", [received(Self.claire, 25), sent(8)])
        let messages = exchanges("t1", to: [Self.claire], [received(Self.claire, 30), sent(20)]) + exchanges("t2", to: [Self.claire], [received(Self.claire, 25), sent(8)])
        let lines = byProject([old, recent], messages)
        #expect(lines.count == 1)
        #expect(lines.first?.id == "silent:\(site.uuidString.lowercased())" && lines.first?.days == 8 && lines.first?.threadKey == recent.id)
        #expect(lines.first?.person == "Claire" && lines.first?.detail == "Cabinet Martin" && lines.first?.lastMessageAt == ago(8))
        // His last mail of the project is three days old: the wait has just started again.
        let fresh = thread("t3", subject: "Textes", [received(Self.claire, 25), sent(3)])
        #expect(byProject([old, recent, fresh], messages + exchanges("t3", to: [Self.claire], [received(Self.claire, 25), sent(3)])).isEmpty)
    }

    /// His clients send their files and their questions in new threads.
    @Test func aProjectThatWroteInAnotherThreadIsNotSilent() {
        let (threads, messages) = claireIsSilent
        #expect(byProject(threads, messages).count == 1)
        // Claire sent her files four days ago, in a new thread.
        let files = thread("t2", subject: "Fichiers", [received(Self.claire, 4)])
        #expect(byProject(threads + [files], messages + exchanges("t2", [received(Self.claire, 4)])).isEmpty)
        // Each check alone: Claire, in a thread of no project; someone else, in a thread of the project.
        #expect(byProject(threads, messages + exchanges("t7", [received(Self.claire, 4)])).isEmpty)
        let colleague = thread("t8", subject: "Plans", [received(Self.claire, 40), received(Self.marc, 4)])
        #expect(ReviewRules.projects(of: [colleague], rules: rules, recipients: [:])[colleague.id] == site)
        #expect(byProject(threads + [colleague], messages + exchanges("t8", [received(Self.claire, 40), received(Self.marc, 4)])).isEmpty)
        // What she wrote before his mail is no answer; nor a word of another project.
        let before = thread("t2", subject: "Fichiers", [received(Self.claire, 12)])
        #expect(byProject(threads + [before], messages + exchanges("t2", [received(Self.claire, 12)])).count == 1)
        let other = thread("t3", [received(Self.anne, 4)])
        #expect(byProject(threads + [other], messages + exchanges("t3", [received(Self.anne, 4)])).count == 1)
    }

    @Test func aFinishedProjectIsNeverSilentNorOneThatMeets() {
        let (threads, messages) = claireIsSilent
        #expect(byProject(threads, messages, finished: [site]).isEmpty)
        #expect(byProject(threads, messages, finished: [house]).count == 1)
        // A meeting of the project, held since his mail or to come: they speak.
        #expect(byProject(threads, messages, events: [event("e1", project: site, daysAgo: 3)]).isEmpty)
        #expect(byProject(threads, messages, events: [event("e2", project: site, daysAgo: -3)]).isEmpty)
        // Before his mail, or of another project: silence.
        #expect(byProject(threads, messages, events: [event("e3", project: site, daysAgo: 15), event("e4", project: house, daysAgo: 3)]).count == 1)
    }

    @Test func aSilenceIsSetAsideByProject() {
        let (threads, messages) = claireIsSilent
        let key = site.uuidString.lowercased()
        let aside = ColinDismissalRow(kind: "silent", subject: key, reason: .notNeeded, projectID: site, createdAt: ago(1), lastMessageAt: ago(10))
        #expect(byProject(threads, messages, dismissed: [aside]).isEmpty)
        // Set aside before his last mail: this is a new silence.
        let earlier = ColinDismissalRow(kind: "silent", subject: key, reason: .answeredElsewhere, projectID: site, createdAt: ago(31), lastMessageAt: ago(30))
        #expect(byProject(threads, messages, dismissed: [earlier]).count == 1)
        // « A répondu ailleurs », said twice of the project: Colin no longer says it.
        let twice = ColinDismissalRow(kind: "silent", subject: key, reason: .answeredElsewhere, projectID: site, createdAt: ago(31), lastMessageAt: ago(30), times: 2)
        #expect(byProject(threads, messages, dismissed: [twice]).isEmpty)
    }

    /// A mailbox Paul hid from his mails is not signaled, but what he wrote from it counts: the line of a person,
    /// or of a project, is said from a box he shows.
    @Test func aHiddenMailboxIsNeverTheOneALineIsSaidFrom() {
        // Marc wrote nine days ago to the box Paul hides, four days ago to the one he shows.
        let shown = thread("t1", [received(Self.marc, 4)]), hidden = thread("t2", account: Self.other, [received(Self.marc, 9)])
        let messages = exchanges("t1", [received(Self.marc, 4)]) + exchanges("t2", account: Self.other, [received(Self.marc, 9)])
        func person(_ threads: [MailThreadRow], _ messages: [MailExchange]) -> [ReviewRules.Line] {
            ReviewRules.repliesByPerson(threads, rules: rules, exchanges: Exchanges(messages), hiddenAccounts: [Self.other], dismissed: [], now: now,
                                        thresholds: thresholds, calendar: calendar)
        }
        let lines = person([shown, hidden], messages)
        #expect(lines.map(\.threadKey) == [shown.id] && lines.first?.days == 4)
        // Only in the box he hides: no line.
        #expect(person([hidden], messages).isEmpty)
        // Answered from the box he hides: he was written to.
        #expect(person([shown, hidden], messages + exchanges("t3", account: Self.other, to: [Self.marc], [sent(2, from: Self.other)])).isEmpty)

        // The same for a silence: Paul's last mail of the project, twelve days ago from the box he shows.
        let quote = thread("t4", subject: "Devis", [received(Self.claire, 30), sent(12)])
        let aside = thread("t5", account: Self.other, subject: "Devis", [received(Self.claire, 30), sent(20, from: Self.other)])
        let people = [quote.id: [MailAddress(email: Self.claire)], aside.id: [MailAddress(email: Self.claire)]]
        func project(_ threads: [MailThreadRow]) -> [ReviewRules.Line] {
            let said = exchanges("t4", to: [Self.claire], [received(Self.claire, 30), sent(12)])
                + exchanges("t5", account: Self.other, to: [Self.claire], [received(Self.claire, 30), sent(20, from: Self.other)])
            let projects = ReviewRules.projects(of: threads, rules: rules, recipients: people)
            return ReviewRules.silentByProject(threads, rules: rules, recipients: people, exchanges: Exchanges(said, projects: projects), events: [],
                                               hiddenAccounts: [Self.other], dismissed: [], now: now, thresholds: thresholds, calendar: calendar)
        }
        #expect(project([quote, aside]).map(\.threadKey) == [quote.id])
        #expect(project([aside]).isEmpty)
    }

    // MARK: - The same mail in two boxes, the order, the names

    @Test func oneLineForAThreadInTwoMailboxes() {
        // Marc wrote to both of Paul's addresses: one mail, two threads, known as copies by the mail's identifier.
        let first = thread("t1", account: Self.me, [received(Self.marc, 4)])
        // The other box took its copy a second later, and its thread begins at « Re: ».
        let second = thread("t9", account: Self.other, subject: "Re: Maquette v2", [received(Self.marc, 4 - 1.0 / 86_400)])
        #expect(replies([first, second], conversations: copies(first, second)).count == 1)
        // Nothing says they are copies: two lines.
        #expect(replies([first, second]).count == 2)
        // Paul answered from one box only: the other box's copy does not wait either, whatever the order.
        let answered = thread("t1", account: Self.me, [received(Self.marc, 4), sent(3)])
        #expect(replies([answered, second], conversations: copies(answered, second)).isEmpty)
        #expect(replies([second, answered], conversations: copies(answered, second)).isEmpty)
        // Set aside in one box, it is set aside.
        let aside = ColinDismissalRow(kind: "reply", subject: second.id, reason: .notNeeded, createdAt: ago(1))
        #expect(replies([first, second], conversations: copies(first, second), dismissed: [aside]).isEmpty)
        // The same for a silence: Paul's mail, seen in his other box too.
        let sentOnce = thread("t2", account: Self.me, subject: "Plans", [received(Self.anne, 20), sent(9)])
        let seenTwice = thread("t8", account: Self.other, subject: "Plans", [received(Self.anne, 20), sent(9, from: Self.me)])
        #expect(silent([sentOnce, seenTwice], conversations: copies(sentOnce, seenTwice)).count == 1)
    }

    /// A conversation is said from the first of its copies that waits, in the order given (the mailboxes Paul shows
    /// come first): not from the box whose copy happens to be dated last.
    @Test func aConversationIsSaidFromTheFirstCopyThatWaits() {
        let first = thread("t1", account: Self.me, [received(Self.marc, 4)])
        let second = thread("t9", account: Self.other, [received(Self.marc, 4 - 1.0 / 86_400)])
        #expect(replies([first, second], conversations: copies(first, second)).map(\.threadKey) == [first.id])
        #expect(replies([second, first], conversations: copies(first, second)).map(\.threadKey) == [second.id])
        // Paul answered what the first box holds; Marc's later mail reached the other box only: that copy waits.
        let answered = thread("t1", account: Self.me, [received(Self.marc, 8), sent(7)])
        let later = thread("t9", account: Self.other, [received(Self.marc, 8), received(Self.marc, 4)])
        let lines = replies([answered, later], conversations: copies(answered, later))
        #expect(lines.map(\.threadKey) == [later.id] && lines.first?.days == 4)
    }

    @Test func aCopyLeftBehindInTheOtherBoxNeverWaits() {
        // Marc wrote to both addresses ten days ago. Paul answered from the first box; Marc wrote again yesterday,
        // to the first box only. The copy left in the second box holds a mail answered nine days ago.
        let alive = thread("t1", account: Self.me, [received(Self.marc, 10), sent(9), received(Self.marc, 1)])
        let left = thread("t9", account: Self.other, [received(Self.marc, 10)])
        let conversation = copies(alive, left)
        #expect(replies([alive, left], conversations: conversation).isEmpty)
        #expect(replies([left, alive], conversations: conversation).isEmpty)
        // Three days later, yesterday's mail waits: in the box where it arrived.
        let later = replies([left, alive], conversations: conversation, at: now.addingTimeInterval(3 * 86_400))
        #expect(later.map(\.threadKey) == [alive.id])
        #expect(later.first?.days == 4)
        // Paul answers it: nothing waits, in either box.
        let done = thread("t1", account: Self.me, [received(Self.marc, 10), sent(9), received(Self.marc, 1), sent(0.5)])
        #expect(replies([left, done], conversations: copies(done, left), at: now.addingTimeInterval(3 * 86_400)).isEmpty)
        // What he set aside in the first box covers the copy of the second.
        let aside = ColinDismissalRow(kind: "reply", subject: alive.id, reason: .notNeeded, createdAt: now.addingTimeInterval(3 * 86_400))
        #expect(replies([left, alive], conversations: conversation, dismissed: [aside], at: now.addingTimeInterval(4 * 86_400)).isEmpty)
    }

    @Test func theOrderIsDraftsRepliesSilentMeetings() {
        let drafts = ReviewRules.drafts([draft("d1")], hidden: [])
        let awaited = replies([thread("t1", subject: "Récent", [received(Self.marc, 3)]), thread("t2", subject: "Ancien", [received(Self.marc, 20)])])
        let quiet = silent([thread("t3", subject: "Plans", [received(Self.anne, 30), sent(8)]), thread("t4", subject: "Devis", [received(Self.claire, 30), sent(25)])])
        let meetings = ReviewRules.unfiled([event("e1", daysAgo: 2)], now: now)
        // Whatever order the lists come in.
        let all = ReviewRules.ordered([meetings, quiet, awaited, drafts])
        #expect(all.map(\.kind) == [.draft, .reply, .reply, .silent, .silent, .unfiled])
        // The oldest wait first.
        #expect(all.compactMap(\.days) == [20, 3, 25, 8])
    }

    @Test func aPersonIsCalledByTheFirstName() {
        #expect(ReviewRules.short("Claire Morel") == "Claire")
        #expect(ReviewRules.short("Jean-Pierre Durand") == "Jean-Pierre")
        #expect(ReviewRules.short("Morel, Claire") == "Claire")
        #expect(ReviewRules.short("Camille") == "Camille")
        #expect(ReviewRules.short("claire@cabinet.exemple") == "claire@cabinet.exemple")
        #expect(ReviewRules.short("  ") == "")
        // Quotes some mailers add around a name.
        #expect(ReviewRules.short("'Claire Morel'") == "Claire")
        #expect(ReviewRules.short("\"Claire Morel\"") == "Claire")
        // A title, a first word that is no word, a name in capitals: the whole name, rather than the wrong word.
        #expect(ReviewRules.short("Dr. Claire Morel") == "Dr. Claire Morel")
        #expect(ReviewRules.short("Mme Leroy") == "Mme Leroy")
        #expect(ReviewRules.short("Me Durand") == "Me Durand")
        #expect(ReviewRules.short("🌿 Atelier Vert") == "🌿 Atelier Vert")
        #expect(ReviewRules.short("MOREL Claire") == "MOREL Claire")
        #expect(ReviewRules.short("EDF Entreprises") == "EDF Entreprises")
        #expect(ReviewRules.short("A B") == "A B")
        // The name a header gave, else the one Paul's own mails gave, else the address.
        var bare = thread([sent(10), received(Self.marc, 4)])
        bare.senders = [MailAddress(email: Self.marc)]
        #expect(replies([bare]).first?.person == "Marc")
        var unknown = rules
        unknown.correspondentStats = [:]
        #expect(replies([bare], rules: unknown).first?.person == Self.marc)
    }
}
