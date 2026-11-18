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
        // click, and Polhub only read it after: that message is newer than what Paul saw.
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
        let expected = ReviewRules.Line(id: "draft:d1", kind: .draft, person: "Claire", threadKey: "moi@exemple.fr|t1", draftID: "d1")
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
