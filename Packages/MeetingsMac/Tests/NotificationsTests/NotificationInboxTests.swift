import Foundation
import Testing
@testable import Notifications

/// hub's own list of its notifications (Paul, 15/11): kept, capped, collapsed, grouped, and what a click opens.
@MainActor @Suite struct NotificationInboxTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)
    let folder: URL

    init() {
        folder = FileManager.default.temporaryDirectory.appending(path: "notifications \(UUID().uuidString)", directoryHint: .isDirectory)
    }

    var file: URL { folder.appending(path: "Notifications.json") }

    func inbox(file: URL? = nil, at date: Date? = nil) -> NotificationInbox {
        let date = date ?? now
        return NotificationInbox(file: file, now: { date })
    }

    func mail(_ thread: String, sender: String = "Camille Exemple", subject: String = "Maquette") -> PlannedNotice {
        PlannedNotice(id: "mail|\(thread)", fireDate: now, title: sender, body: subject, eventID: nil, meetCode: nil, account: nil,
                      threadKey: thread, kind: .mail)
    }

    func reminder(_ event: String, body: String) -> PlannedNotice {
        PlannedNotice(id: "rappel|\(event)|\(body)", fireDate: now, title: "Point \(event)", body: body, eventID: event, meetCode: "abc-defg-hij",
                      account: "paul@exemple.fr", kind: .reminder)
    }

    @Test func aNotificationIsRecordedWithWhatItsClickNeeds() {
        let inbox = inbox()
        let meeting = UUID()
        inbox.record(NotificationPlan.summaryNotice(meetingID: meeting, title: "Atelier maquette", now: now))
        let kept = try? #require(inbox.notices.first)
        #expect(inbox.notices.count == 1 && inbox.unreadCount == 1)
        #expect(kept?.title == "Compte rendu prêt" && kept?.body == "Atelier maquette" && kept?.meetingID == meeting && kept?.date == now)
        #expect(kept?.action(now: now) == .meeting(meeting))
    }

    @Test func theListKeepsThirtyDaysAndAtMostAHundred() {
        let inbox = inbox()
        for index in 0..<130 {
            inbox.record(mail("compte|fil-\(index)"), at: now.addingTimeInterval(Double(index - 130) * 60))
        }
        #expect(inbox.notices.count == NotificationInbox.limit)
        // The newest stay, newest first.
        #expect(inbox.notices.first?.threadKey == "compte|fil-129" && inbox.notices.last?.threadKey == "compte|fil-30")
        inbox.removeAll()
        inbox.record(mail("compte|vieux"), at: now.addingTimeInterval(-31 * 86_400))
        inbox.record(mail("compte|recent"), at: now.addingTimeInterval(-29 * 86_400))
        #expect(inbox.notices.map(\.threadKey) == ["compte|recent"])
    }

    @Test func repeatsOfOneThreadOrOneEventCollapseIntoOneCard() {
        let inbox = inbox()
        inbox.record(mail("compte|fil", sender: "Camille", subject: "Maquette"), at: now.addingTimeInterval(-600))
        inbox.record(mail("compte|autre"), at: now.addingTimeInterval(-300))
        inbox.markAllSeen()
        inbox.record(mail("compte|fil", sender: "Jules", subject: "Re: Maquette"), at: now)
        #expect(inbox.notices.count == 2)
        let thread = inbox.notices[0]
        #expect(thread.threadKey == "compte|fil" && thread.count == 2 && thread.title == "Jules" && thread.body == "Re: Maquette")
        // A repeat is news again.
        #expect(!thread.seen && inbox.unreadCount == 1)
        // The 10- and 1-minute reminders of one event: one card, the latest text.
        inbox.record(reminder("a", body: "Dans 10 min"), at: now.addingTimeInterval(60))
        inbox.record(reminder("a", body: "Dans 1 min"), at: now.addingTimeInterval(600))
        #expect(inbox.notices.filter { $0.kind == .reminder }.map(\.body) == ["Dans 1 min"])
        // Far apart, two cards.
        inbox.record(mail("compte|fil", sender: "Camille", subject: "Le lendemain"), at: now.addingTimeInterval(86_400))
        #expect(inbox.notices.filter { $0.threadKey == "compte|fil" }.count == 2)
    }

    @Test func aBurstOfOneSectionStacksAndTheDaysAreNamed() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        let inbox = inbox()
        // Three mails within minutes, then a summary, then a mail an hour earlier, and yesterday's reminder.
        inbox.record(mail("compte|1"), at: now.addingTimeInterval(-60))
        inbox.record(mail("compte|2"), at: now.addingTimeInterval(-4 * 60))
        inbox.record(mail("compte|3"), at: now.addingTimeInterval(-12 * 60))
        inbox.record(NotificationPlan.summaryNotice(meetingID: UUID(), title: "Point", now: now), at: now.addingTimeInterval(-20 * 60))
        inbox.record(mail("compte|4"), at: now.addingTimeInterval(-90 * 60))
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        inbox.record(reminder("b", body: "Dans 10 min"), at: yesterday)
        let days = NoticeFeed.days(inbox.notices, now: now, calendar: calendar)
        #expect(days.map(\.title) == ["Aujourd'hui", "Hier"])
        #expect(days[0].groups.map { $0.notices.count } == [3, 1, 1])
        #expect(days[0].groups.map(\.section) == [.mails, .meetings, .mails])
        #expect(days[1].groups.first?.section == .calendar)
        let wednesday = calendar.date(byAdding: .day, value: -3, to: now)!
        let older = calendar.date(byAdding: .day, value: -10, to: now)!
        #expect(NoticeFeed.title(of: wednesday, now: now, calendar: calendar) == wednesday.formatted(
            Date.FormatStyle(locale: Locale(identifier: "fr_FR"), calendar: calendar, timeZone: calendar.timeZone).weekday(.wide)).capitalizedFirst)
        #expect(NoticeFeed.title(of: older, now: now, calendar: calendar).split(separator: " ").count == 3)
        #expect(NoticeFeed.time(of: now.addingTimeInterval(-20), now: now) == "à l'instant")
        #expect(NoticeFeed.time(of: now.addingTimeInterval(-5 * 60), now: now) == "il y a 5 min")
        let time = NoticeFeed.time(of: now.addingTimeInterval(-3 * 3_600), now: now, calendar: calendar)
        // « 7:42 », no zero before the hour (lot 10, 20/11).
        #expect(time == "7:42")
    }

    @Test func theListSurvivesARelaunch() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = inbox(file: file)
        first.record(mail("compte|fil"), at: now.addingTimeInterval(-60))
        first.record(reminder("a", body: "Dans 1 min"), at: now)
        first.markAllSeen()
        first.record(NotificationPlan.summaryNotice(meetingID: UUID(), title: "Atelier", now: now), at: now)
        #expect(FileManager.default.fileExists(atPath: file.path))
        let again = inbox(file: file)
        #expect(again.notices == first.notices)
        #expect(again.unreadCount == 1)
        again.remove([again.notices[0].id])
        #expect(inbox(file: file).notices.count == 2)
        // A file that does not read is an empty list, not a crash.
        try Data("pas du json".utf8).write(to: file)
        #expect(inbox(file: file).notices.isEmpty)
    }

    @Test func openingThePanelMarksEverythingSeen() {
        let inbox = inbox()
        inbox.record(mail("compte|1"))
        inbox.record(mail("compte|2"))
        #expect(inbox.unreadCount == 2)
        inbox.markAllSeen()
        #expect(inbox.unreadCount == 0)
        inbox.record(mail("compte|3"))
        #expect(inbox.unreadCount == 1)
    }

    /// 18/11: « Brouillon prêt » opens the Accueil, where the draft waits at the head of « À valider ».
    @Test func aDraftReadyOpensHome() {
        #expect(PlannedNotice.Kind.draft.section == .home)
        #expect(NoticeAction.of(kind: .draft, eventID: nil, meetCode: nil, account: nil, meetingID: nil, threadKey: "a|t", folder: nil, join: false) == .home)
        let card = InboxNotice(NotificationPlan.draftNotices([(id: "d1", recipient: "Claire", threadKey: "a|t")], now: now)[0], at: now)
        #expect(card.kind == .draft && card.action(now: now) == .home)
    }

    /// The same draft said twice (an agent prepared it again) is one card; another draft is another card.
    @Test func twoNoticesOfOneDraftAreOneCard() {
        let inbox = inbox()
        let claire = NotificationPlan.draftNotices([(id: "d1", recipient: "Claire", threadKey: nil)], now: now)[0]
        inbox.record(claire, at: now.addingTimeInterval(-600))
        inbox.record(claire, at: now)
        inbox.record(NotificationPlan.draftNotices([(id: "d2", recipient: "Marc", threadKey: nil)], now: now)[0], at: now)
        #expect(inbox.notices.count == 2)
        #expect(inbox.notices.first { $0.body.contains("Claire") }?.count == 2)
        #expect(inbox.notices.first { $0.body.contains("Marc") }?.count == 1)
    }

    @Test func aClickOpensWhatTheNotificationIsAbout() {
        // From macOS's center: the same mapping the app used before 15/11.
        #expect(NoticeAction.of(kind: .mail, eventID: nil, meetCode: nil, account: nil, meetingID: nil, threadKey: "a|t", folder: nil, join: false)
            == .mailThread("a|t"))
        #expect(NoticeAction.of(kind: .mail, eventID: nil, meetCode: nil, account: nil, meetingID: nil, threadKey: nil, folder: "programmes", join: false)
            == .mailFolder("programmes"))
        #expect(NoticeAction.of(kind: .reminder, eventID: "a|e", meetCode: "abc", account: "a", meetingID: nil, threadKey: nil, folder: nil, join: true)
            == .join(meetCode: "abc", account: "a"))
        #expect(NoticeAction.of(kind: .newEvent, eventID: "a|e", meetCode: "abc", account: "a", meetingID: nil, threadKey: nil, folder: nil, join: false)
            == .event("a|e"))
        #expect(NoticeAction.of(kind: .newEvent, eventID: nil, meetCode: nil, account: nil, meetingID: nil, threadKey: nil, folder: nil, join: false)
            == .calendar)
        #expect(NoticeAction.of(kind: .test, eventID: nil, meetCode: nil, account: nil, meetingID: nil, threadKey: nil, folder: nil, join: false)
            == .window)
        // From the list: a reminder joins while it is still time, then opens its event.
        let card = InboxNotice(reminder("a", body: "Dans 1 min"), at: now)
        #expect(card.action(now: now.addingTimeInterval(60)) == .join(meetCode: "abc-defg-hij", account: "paul@exemple.fr"))
        #expect(card.action(now: now.addingTimeInterval(2 * 3_600)) == .event("a"))
        let unrecorded = InboxNotice(PlannedNotice(id: "x", fireDate: now, title: "Réunion non enregistrée", body: "", eventID: "a|e",
                                                   meetCode: "abc", account: "a", kind: .unrecorded), at: now)
        #expect(unrecorded.action(now: now) == .join(meetCode: "abc", account: "a"))
        let late = InboxNotice(PlannedNotice(id: "y", fireDate: now, title: "Mail programmé", body: "", eventID: nil, meetCode: nil, account: nil,
                                             folder: "programmes", kind: .mail), at: now)
        #expect(late.action(now: now) == .mailFolder("programmes"))
    }
}

extension String {
    fileprivate var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
