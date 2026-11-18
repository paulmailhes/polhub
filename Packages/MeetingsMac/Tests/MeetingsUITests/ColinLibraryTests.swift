import Agenda
import Colin
import Domain
import Foundation
import Mail
import Persistence
import PolhubDesign
import Testing
@testable import MeetingsUI

/// What the Accueil knows, kept up to date out of the display (18/11): « À valider » and « Le point », read in the
/// base. Every name, address and subject here is invented.
@MainActor
@Suite struct ColinLibraryTests {
    static let me = "moi@exemple.fr", other = "moi@perso.exemple", marc = "marc@exemple.net", claire = "claire@cabinet.exemple"

    /// A clock the tests move.
    @MainActor final class Clock {
        /// Wednesday 18/11/2026, 10:00 in Paris.
        var now = Date(timeIntervalSince1970: 1_794_992_400)

        func advance(days: Double = 0, hours: Double = 0) { now.addTimeInterval(days * 86_400 + hours * 3_600) }
        func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
    }

    struct World {
        let database: AppDatabase
        let agenda: AgendaLibrary
        let mails: MailLibrary?
        let store: MailStore
        let colin: ColinLibrary
        let defaults: UserDefaults
        let clock: Clock
        let project: UUID
        let root: URL
    }

    var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.firstWeekday = 2
        return calendar
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
        #expect(condition())
    }

    /// The library has nothing left to compute.
    func settled(_ colin: ColinLibrary) async throws {
        try await Task.sleep(for: .milliseconds(60))
        try await waitUntil { colin.isIdle }
    }

    /// One mailbox, one project « Cabinet Martin » where it is Paul's turn. `seed` fills the base before the
    /// libraries look at it.
    func world(withMails: Bool = true, accounts: [String] = [me], defaults: UserDefaults? = nil, clock: Clock? = nil, every: Duration = .seconds(3_600),
               settle: Duration = .milliseconds(30), seed: (AppDatabase, UUID, Clock) throws -> Void = { _, _, _ in }) async throws -> World {
        let clock = clock ?? Clock()
        let database = try AppDatabase.inMemory()
        let calendar = CalendarStore(database)
        for account in accounts {
            try calendar.addAccount(email: account, at: clock.ago(400))
            try calendar.setGrantedScopes(email: account, scopes: "openid https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/gmail.modify")
        }
        let project = try ProjectStore(database).addProject(name: "Cabinet Martin", status: .priorite2, at: clock.ago(100))
        try seed(database, project.id, clock)
        let root = FileManager.default.temporaryDirectory.appending(path: "colin-\(UUID().uuidString)", directoryHint: .isDirectory)
        let suite = try defaults ?? #require(UserDefaults(suiteName: "colin-\(UUID().uuidString)"))
        let agenda = AgendaLibrary(database: database)
        var mails: MailLibrary?
        if withMails {
            let gmail = SilentGmail()
            let library = MailLibrary(agenda: agenda, root: root, defaults: suite, flavor: .prod, send: { _ in gmail.send }, vault: MemoryScheduleVault())
            try await waitUntil { library.accounts.count == accounts.count }
            mails = library
        }
        let colin = ColinLibrary(agenda: agenda, mails: mails, defaults: suite, now: { clock.now }, calendar: paris, settle: settle, every: every)
        try await settled(colin)
        return World(database: database, agenda: agenda, mails: mails, store: MailStore(database), colin: colin, defaults: suite, clock: clock,
                     project: project.id, root: root)
    }

    // MARK: - Invented mails and events

    func received(_ id: String, thread: String, from: String, name: String = "Marc Dubois", at date: Date, box: String = me, identifier: String? = nil) -> MailMessageRow {
        MailMessageRow(account: box, messageID: id, threadID: thread, date: date, sender: MailAddress(name: name, email: from), to: [MailAddress(email: box)],
                       subject: "Maquette", snippet: "extrait", labels: ["INBOX", "CATEGORY_PERSONAL"], rfcMessageID: identifier)
    }

    func sent(_ id: String, thread: String, to: String, at date: Date, box: String = me) -> MailMessageRow {
        MailMessageRow(account: box, messageID: id, threadID: thread, date: date, sender: MailAddress(name: "Moi", email: box), to: [MailAddress(email: to)],
                       subject: "Maquette", snippet: "extrait", labels: ["SENT"])
    }

    func key(_ thread: String, box: String = me) -> String { MailThreadRow.key(account: box, threadID: thread) }

    /// Paul wrote to Marc two months ago; Marc wrote `daysAgo` days ago: the thread « a » waits for Paul.
    func marcWaits(_ database: AppDatabase, _ clock: Clock, daysAgo: Double = 4) throws {
        try MailStore(database).apply(account: Self.me, upserts: [
            sent("a1", thread: "a", to: Self.marc, at: clock.ago(60)),
            received("a2", thread: "a", from: Self.marc, at: clock.ago(daysAgo)),
        ])
    }

    /// A meeting recorded `daysAgo` days ago, with its event, in no project.
    @discardableResult
    func meeting(_ database: AppDatabase, _ clock: Clock, id: String = "e1", daysAgo: Double = 2, title: String = "Point Cabinet Martin") throws -> CalendarEventRow {
        let start = clock.ago(daysAgo)
        let row = MeetingRow(createdAt: start, status: .ended, source: .dia, candidateKey: "t/\(id)", title: title, startedAt: start,
                             endedAt: start.addingTimeInterval(3_600))
        try MeetingStore(database).save(row)
        let event = CalendarEventRow(account: Self.me, eventID: id, title: title, startAt: start, endAt: start.addingTimeInterval(3_600), updatedAt: start)
        try CalendarStore(database).applyGoogle(account: Self.me, changed: [event], cancelled: [], at: start)
        try CalendarStore(database).setMeeting(eventID: event.id, meetingID: row.id)
        return event
    }

    func agentDraft(to name: String = "Claire Morel", address: String = claire, box: String = me) -> MailDraftRow {
        MailDraftRow(account: box, mode: .new, to: [MailAddress(name: name, email: address)], subject: "Devis d'avril", body: "Bonjour, voici le devis.",
                     signature: false, origin: .agent, createdAt: Date())
    }

    // MARK: - « À valider »

    /// Review Focus 4, in the library: a draft an agent prepared waits for Paul; programmed, it no longer does.
    @Test func anAgentsDraftShowsThenGoesWhenProgrammed() async throws {
        let world = try await world()
        defer { try? FileManager.default.removeItem(at: world.root) }
        let mails = try #require(world.mails)
        #expect(world.colin.review.isEmpty)
        let draft = agentDraft()
        try world.store.saveDraft(draft)
        // One Paul began himself is not Colin's to say.
        try world.store.saveDraft(MailDraftRow(account: Self.me, mode: .new, to: [MailAddress(name: "Marc Dubois", email: Self.marc)], subject: "Autre",
                                               body: "Bonjour Marc.", signature: false, createdAt: Date()))
        try await waitUntil { world.colin.review.count == 1 }
        let line = try #require(world.colin.review.first)
        #expect(line.id == "draft:\(draft.id)" && line.kind == .draft && line.person == "Claire" && line.draftID == draft.id)
        mails.schedule(draft.id, at: Date().addingTimeInterval(3_600))
        try await waitUntil { mails.scheduled[draft.id] != nil }
        try await waitUntil { world.colin.review.isEmpty }
        // « Annuler » : a draft again, waiting again.
        mails.undo()
        try await waitUntil { mails.scheduled.isEmpty }
        try await waitUntil { world.colin.review.map(\.id) == ["draft:\(draft.id)"] }
    }

    /// « Relire » : a reply opens in its thread, wherever the caller shows threads; a new mail, or a reply whose
    /// thread left the copy, opens in the composer.
    @Test func aReplyOpensItsThreadANewMailTheComposer() async throws {
        let world = try await world { database, _, clock in try marcWaits(database, clock) }
        defer { try? FileManager.default.removeItem(at: world.root) }
        let mails = try #require(world.mails)
        func reply(_ thread: String) -> MailDraftRow {
            MailDraftRow(account: Self.me, mode: .reply, threadKey: key(thread), to: [MailAddress(name: "Marc Dubois", email: Self.marc)], subject: "Re: Maquette",
                         body: "Bonjour Marc.", signature: false, origin: .agent, createdAt: Date())
        }
        var shown: [String] = []
        mails.open(reply("a")) { shown.append($0) }
        #expect(shown == [key("a")] && mails.composing == nil)
        let new = agentDraft()
        mails.open(new) { shown.append($0) }
        #expect(shown == [key("a")] && mails.composing == new.id)
        let orphan = reply("parti")
        mails.open(orphan) { shown.append($0) }
        #expect(shown == [key("a")] && mails.composing == orphan.id)
        // From the list of Mails, as before: the thread opens in Mails.
        let router = WindowRouter()
        mails.open(reply("a"), router: router)
        #expect(router.mailSelection == key("a") && router.homeMail == nil)
    }

    /// What an agent drops becomes a draft, told once to the app (for the notification), and a line of « À valider ».
    @Test func aDraftAnAgentDropsIsToldAndShown() async throws {
        let world = try await world()
        defer { try? FileManager.default.removeItem(at: world.root) }
        let mails = try #require(world.mails)
        var told: [MailDraftRow] = []
        mails.onAgentDrafts = { told.append(contentsOf: $0) }
        try world.store.drop(MailAgentDraftRow(mode: .new, account: Self.me, to: [MailAddress(name: "Claire Morel", email: Self.claire)], subject: "Devis d'avril",
                                               body: "Bonjour Claire, voici le devis.", createdAt: Date()))
        try await waitUntil { told.count == 1 }
        #expect(told.first?.origin == .agent && told.first?.subject == "Devis d'avril")
        try await waitUntil { world.colin.review.map(\.kind) == [.draft] }
        #expect(world.colin.review.first?.person == "Claire" && world.colin.review.first?.draftID == told.first?.id)
        // Looked at again and again, nothing new is told.
        for _ in 0..<3 {
            mails.refresh()
            try await Task.sleep(for: .milliseconds(60))
        }
        #expect(told.count == 1)
    }

    @Test func aDismissedLineLeavesAtOnce() async throws {
        let world = try await world { database, _, clock in try marcWaits(database, clock) }
        defer { try? FileManager.default.removeItem(at: world.root) }
        try await waitUntil { world.colin.review.count == 1 }
        let line = try #require(world.colin.review.first)
        #expect(line.id == "reply:\(Self.marc)" && line.threadKey == key("a") && line.person == "Marc" && line.days == 4)
        world.colin.dismiss(line, reason: .notNeeded)
        // At once: before the base is read again.
        #expect(world.colin.review.isEmpty)
        try await settled(world.colin)
        #expect(world.colin.review.isEmpty)
        // The base keeps it, with the last message Paul had before him.
        let rows = try ColinStore(world.database).dismissals()
        #expect(rows.map(\.id) == ["reply:\(Self.marc)"])
        #expect(rows.first?.reason == .notNeeded && rows.first?.lastMessageAt == world.clock.ago(4) && rows.first?.createdAt == world.clock.now)
        // Marc writes again; three days later the line is back.
        try world.store.apply(account: Self.me, upserts: [received("a3", thread: "a", from: Self.marc, at: world.clock.now.addingTimeInterval(60))])
        try await settled(world.colin)
        #expect(world.colin.review.isEmpty)
        world.clock.advance(days: 3.1)
        world.colin.refresh()
        try await waitUntil { world.colin.review.map(\.id) == ["reply:\(Self.marc)"] }
        #expect(world.colin.review.first?.days == 3)
    }

    /// The count on Paul's own mails: he answers in a new mail more often than in the thread, and his clients write
    /// in new threads too.
    @Test func whoWasAnsweredInANewThreadLeavesTheList() async throws {
        let world = try await world { database, project, clock in
            try marcWaits(database, clock)
            // Paul wrote to Claire eight days ago, in a thread of the project: she is silent.
            try MailStore(database).apply(account: Self.me, upserts: [
                received("b1", thread: "b", from: Self.claire, name: "Claire Morel", at: clock.ago(20)),
                sent("b2", thread: "b", to: Self.claire, at: clock.ago(8)),
            ])
            try MailStore(database).file(threadKey: key("b"), as: .project(project), at: clock.ago(20))
            let claire = try ContactStore(database).upsert(email: Self.claire, name: "Claire Morel", company: nil, at: clock.ago(100))
            try ContactStore(database).link(contactID: claire.id, projectID: project, origin: .paul, at: clock.ago(100))
        }
        defer { try? FileManager.default.removeItem(at: world.root) }
        try await waitUntil { world.colin.review.map(\.kind) == [.reply, .silent] }
        // Paul answers Marc in a new mail, not in the thread: Marc no longer waits.
        try world.store.apply(account: Self.me, upserts: [sent("n1", thread: "n", to: Self.marc, at: world.clock.now.addingTimeInterval(-600))])
        try await waitUntil { world.colin.review.map(\.kind) == [.silent] }
        // Claire sends her files in a new thread: she is not silent.
        try world.store.apply(account: Self.me, upserts: [received("f1", thread: "f", from: Self.claire, name: "Claire Morel", at: world.clock.now.addingTimeInterval(-300))])
        try await waitUntil { world.colin.review.isEmpty }
    }

    /// Paul answers Marc from the Accueil and sends: the draft goes at once, the copy of what he sent only comes with
    /// the next reading of the mailbox. In between, Marc does not « wait » again.
    @Test func aSentAnswerKeepsTheLineAwayUntilItsCopyComes() async throws {
        let world = try await world { database, _, clock in try marcWaits(database, clock) }
        defer { try? FileManager.default.removeItem(at: world.root) }
        try await waitUntil { world.colin.review.map(\.kind) == [.reply] }
        let answer = MailDraftRow(account: Self.me, mode: .reply, threadKey: key("a"), to: [MailAddress(name: "Marc Dubois", email: Self.marc)],
                                  subject: "Re: Maquette", body: "Bonjour Marc.", signature: false, createdAt: world.clock.now)
        try world.store.saveDraft(answer)
        try await waitUntil { world.colin.review.isEmpty }
        // It leaves for Gmail, then the engine takes it out of the drafts.
        world.colin.departs(answer)
        try world.store.deleteDraft(answer.id)
        try await waitUntil { world.mails?.drafts.isEmpty == true }
        try await settled(world.colin)
        #expect(world.colin.review.isEmpty)
        // The copy of the mailbox brings what he sent: the line stays away for good.
        try world.store.apply(account: Self.me, upserts: [sent("a3", thread: "a", to: Self.marc, at: world.clock.now)])
        try await settled(world.colin)
        world.clock.advance(hours: 1)
        world.colin.refresh()
        try await settled(world.colin)
        #expect(world.colin.review.isEmpty)
    }

    /// A send that never reached the copy (Gmail refused it, the mailbox was not read again): after ten minutes the
    /// line says Marc waits again.
    @Test func aSentAnswerThatNeverComesLetsTheLineBack() async throws {
        let world = try await world { database, _, clock in try marcWaits(database, clock) }
        defer { try? FileManager.default.removeItem(at: world.root) }
        try await waitUntil { world.colin.review.map(\.kind) == [.reply] }
        let answer = MailDraftRow(account: Self.me, mode: .reply, threadKey: key("a"), to: [MailAddress(name: "Marc Dubois", email: Self.marc)],
                                  subject: "Re: Maquette", body: "Bonjour Marc.", signature: false, createdAt: world.clock.now)
        try world.store.saveDraft(answer)
        try await waitUntil { world.colin.review.isEmpty }
        world.colin.departs(answer)
        try world.store.deleteDraft(answer.id)
        try await settled(world.colin)
        #expect(world.colin.review.isEmpty)
        world.clock.advance(hours: 0.2)
        world.colin.refresh()
        try await waitUntil { world.colin.review.map(\.kind) == [.reply] }
    }

    /// A reply begun in Gmail, on the phone: Marc's answer is being written.
    @Test func aDraftBegunInGmailTakesTheLineAway() async throws {
        let world = try await world { database, _, clock in try marcWaits(database, clock) }
        defer { try? FileManager.default.removeItem(at: world.root) }
        try await waitUntil { world.colin.review.map(\.kind) == [.reply] }
        try world.store.apply(account: Self.me, upserts: [
            MailMessageRow(account: Self.me, messageID: "g1", threadID: "a", date: world.clock.now.addingTimeInterval(-600),
                           sender: MailAddress(name: "Moi", email: Self.me), to: [MailAddress(email: Self.marc)], subject: "Re: Maquette", snippet: "",
                           labels: ["DRAFT"]),
        ])
        try await waitUntil { world.colin.review.isEmpty }
    }

    /// What Paul sent from a mailbox he hides counts: Marc, answered from it, no longer waits.
    @Test func anAnswerFromAHiddenMailboxCounts() async throws {
        let world = try await world(accounts: [Self.me, Self.other]) { database, _, clock in try marcWaits(database, clock) }
        defer { try? FileManager.default.removeItem(at: world.root) }
        let mails = try #require(world.mails)
        mails.hidden = [Self.other]
        try await waitUntil { world.colin.review.map(\.kind) == [.reply] }
        try world.store.apply(account: Self.other, upserts: [sent("h1", thread: "h", to: Self.marc, at: world.clock.now.addingTimeInterval(-600), box: Self.other)])
        try await waitUntil { world.colin.review.isEmpty }
    }

    @Test func aLineSetAsideForLaterComesBackTheNextDay() async throws {
        let world = try await world { database, _, clock in try marcWaits(database, clock) }
        defer { try? FileManager.default.removeItem(at: world.root) }
        try await waitUntil { world.colin.review.count == 1 }
        world.colin.dismiss(try #require(world.colin.review.first), reason: .later)
        #expect(world.colin.review.isEmpty)
        try await settled(world.colin)
        // The same day, even hours later, it stays aside.
        world.clock.advance(hours: 10)
        world.colin.refresh()
        try await settled(world.colin)
        #expect(world.colin.review.isEmpty)
        world.clock.advance(hours: 5)
        world.colin.refresh()
        try await waitUntil { world.colin.review.count == 1 }
    }

    /// A draft is not set aside: it leaves when it is sent, deleted or programmed.
    @Test func aDraftIsNeverSetAside() async throws {
        let world = try await world()
        defer { try? FileManager.default.removeItem(at: world.root) }
        try world.store.saveDraft(agentDraft())
        try await waitUntil { world.colin.review.count == 1 }
        world.colin.dismiss(try #require(world.colin.review.first), reason: .notNeeded)
        try await settled(world.colin)
        #expect(world.colin.review.count == 1)
        #expect(try ColinStore(world.database).dismissals().isEmpty)
    }

    @Test func filingAMeetingRemovesItsLine() async throws {
        let world = try await world { database, _, clock in
            try meeting(database, clock, id: "e1", daysAgo: 2, title: "Point Cabinet Martin")
            try meeting(database, clock, id: "e2", daysAgo: 1, title: "Appel découverte")
        }
        defer { try? FileManager.default.removeItem(at: world.root) }
        try await waitUntil { world.colin.review.count == 2 }
        // The most recent first.
        #expect(world.colin.review.map(\.person) == ["Appel découverte", "Point Cabinet Martin"])
        #expect(world.colin.review.allSatisfy { $0.kind == .unfiled })
        let first = try #require(world.colin.review.last)
        await world.colin.file(first, projectID: world.project)
        #expect(world.colin.review.map(\.person) == ["Appel découverte"])
        try await settled(world.colin)
        #expect(world.colin.review.map(\.person) == ["Appel découverte"])
        let eventID = try #require(first.eventID)
        let filed = try #require(try CalendarStore(world.database).event(id: eventID))
        #expect(filed.projectID == world.project && filed.projectOrigin == .paul)
        // « Aucun » : filed under no project, it is not offered again either.
        await world.colin.file(try #require(world.colin.review.first), projectID: nil)
        #expect(world.colin.review.isEmpty)
        try await settled(world.colin)
        #expect(world.colin.review.isEmpty)
    }

    @Test func aChangedThresholdChangesTheList() async throws {
        let world = try await world { database, project, clock in
            try marcWaits(database, clock)
            // Paul wrote to Claire eight days ago, in a thread of the project: she is silent.
            try MailStore(database).apply(account: Self.me, upserts: [
                received("b1", thread: "b", from: Self.claire, name: "Claire Morel", at: clock.ago(20)),
                sent("b2", thread: "b", to: Self.claire, at: clock.ago(8)),
            ])
            try MailStore(database).file(threadKey: key("b"), as: .project(project), at: clock.ago(20))
        }
        defer { try? FileManager.default.removeItem(at: world.root) }
        try await waitUntil { world.colin.review.count == 2 }
        #expect(world.colin.review.map(\.id) == ["reply:\(Self.marc)", "silent:\(world.project.uuidString.lowercased())"])
        #expect(world.colin.review.last?.person == "Claire" && world.colin.review.last?.detail == "Cabinet Martin" && world.colin.review.last?.days == 8)
        // Réglages › Colin : five days for an answer.
        world.defaults.set(5, forKey: Preferences.Key.colinReplyDays)
        try await waitUntil { world.colin.review.map(\.kind) == [.silent] }
        world.defaults.set(10, forKey: Preferences.Key.colinSilentDays)
        try await waitUntil { world.colin.review.isEmpty }
        world.defaults.set(2, forKey: Preferences.Key.colinReplyDays)
        world.defaults.set(5, forKey: Preferences.Key.colinSilentDays)
        try await waitUntil { world.colin.review.count == 2 }
    }

    /// The thresholds pass with the minutes, without anything written in the base: the base is not read again.
    @Test func aLineAppearsWhenItsThresholdPasses() async throws {
        let world = try await world(every: .milliseconds(40)) { database, _, clock in try marcWaits(database, clock, daysAgo: 2.9) }
        defer { try? FileManager.default.removeItem(at: world.root) }
        try await settled(world.colin)
        #expect(world.colin.review.isEmpty)
        let readings = world.colin.readings
        world.clock.advance(days: 0.2)
        try await waitUntil { world.colin.review.count == 1 }
        #expect(world.colin.readings == readings)
    }

    /// Review Focus 3, in the library: a mail delivered to two of Paul's mailboxes, answered from one, waits in
    /// neither.
    @Test func aConversationAnsweredFromAnotherMailboxDoesNotWait() async throws {
        let world = try await world(accounts: [Self.me, Self.other]) { database, _, clock in
            let store = MailStore(database)
            try store.apply(account: Self.me, upserts: [
                sent("a1", thread: "a", to: Self.marc, at: clock.ago(60)),
                received("a2", thread: "a", from: Self.marc, at: clock.ago(4), identifier: "<m1@exemple.net>"),
                sent("a3", thread: "a", to: Self.marc, at: clock.ago(3.5)),
            ])
            try store.apply(account: Self.other, upserts: [
                received("x1", thread: "x", from: Self.marc, at: clock.ago(4), box: Self.other, identifier: "<m1@exemple.net>"),
            ])
        }
        defer { try? FileManager.default.removeItem(at: world.root) }
        try await settled(world.colin)
        #expect(world.colin.review.isEmpty)
        // Without the answer, the conversation is one line, not two.
        try world.store.apply(account: Self.me, removed: ["a3"])
        try await waitUntil { world.colin.review.count == 1 }
        try await settled(world.colin)
        #expect(world.colin.review.count == 1)
    }

    /// A thread only Paul wrote in: the project is the one of the person he wrote to.
    @Test func aThreadPaulBeganIsSilentInTheProjectOfItsRecipient() async throws {
        let world = try await world { database, project, clock in
            let claire = try ContactStore(database).upsert(email: Self.claire, name: "Claire Morel", company: nil, at: clock.ago(100))
            try ContactStore(database).link(contactID: claire.id, projectID: project, origin: .paul, at: clock.ago(100))
            try MailStore(database).apply(account: Self.me, upserts: [sent("c1", thread: "c", to: Self.claire, at: clock.ago(9))])
        }
        defer { try? FileManager.default.removeItem(at: world.root) }
        try await waitUntil { world.colin.review.count == 1 }
        let line = try #require(world.colin.review.first)
        #expect(line.kind == .silent && line.projectID == world.project && line.detail == "Cabinet Martin" && line.days == 9)
        // « Elle a répondu ailleurs » keeps the project: said twice, Colin no longer says it of this project.
        world.colin.dismiss(line, reason: .answeredElsewhere)
        #expect(world.colin.review.isEmpty)
        let row = try #require(try ColinStore(world.database).dismissals().first)
        #expect(row.reason == .answeredElsewhere && row.projectID == world.project && row.lastMessageAt == world.clock.ago(9))
    }

    /// The mailboxes Paul hid from his mails are not signaled either; an agent's draft still waits for him.
    @Test func aHiddenMailboxIsNotSignaled() async throws {
        let world = try await world(accounts: [Self.me, Self.other]) { database, _, clock in
            try MailStore(database).apply(account: Self.other, upserts: [
                sent("a1", thread: "a", to: Self.marc, at: clock.ago(60), box: Self.other),
                received("a2", thread: "a", from: Self.marc, at: clock.ago(4), box: Self.other),
            ])
        }
        defer { try? FileManager.default.removeItem(at: world.root) }
        let mails = try #require(world.mails)
        try world.store.saveDraft(agentDraft(box: Self.other))
        try await waitUntil { world.colin.review.count == 2 }
        mails.hidden = [Self.other]
        try await waitUntil { world.colin.review.map(\.kind) == [.draft] }
        mails.hidden = []
        try await waitUntil { world.colin.review.map(\.kind) == [.draft, .reply] }
    }

    /// Marc wrote to both of Paul's addresses; the copy of the mailbox Paul hid is dated a second later. The
    /// conversation is still said, from the mailbox he shows.
    @Test func aConversationWithACopyInAHiddenMailboxIsSaidFromTheOther() async throws {
        let world = try await world(accounts: [Self.me, Self.other]) { database, _, clock in
            let store = MailStore(database)
            try store.apply(account: Self.me, upserts: [
                sent("a1", thread: "a", to: Self.marc, at: clock.ago(60)),
                received("a2", thread: "a", from: Self.marc, at: clock.ago(4), identifier: "<m1@exemple.net>"),
            ])
            try store.apply(account: Self.other, upserts: [
                received("x1", thread: "x", from: Self.marc, at: clock.ago(4).addingTimeInterval(1), box: Self.other, identifier: "<m1@exemple.net>"),
            ])
        }
        defer { try? FileManager.default.removeItem(at: world.root) }
        let mails = try #require(world.mails)
        try await waitUntil { world.colin.review.count == 1 }
        mails.hidden = [Self.other]
        try await settled(world.colin)
        #expect(world.colin.review.map(\.threadKey) == [key("a")])
        // Hidden the other way round: said from the other mailbox.
        mails.hidden = [Self.me]
        try await waitUntil { world.colin.review.map(\.threadKey) == [key("x", box: Self.other)] }
    }

    /// Without the mails (no mailbox yet), the Accueil still says the meetings to file and the day.
    @Test func withoutMailsOnlyTheMeetingsAndTheDayShow() async throws {
        let world = try await world(withMails: false) { database, _, clock in
            try marcWaits(database, clock)
            try meeting(database, clock)
        }
        defer { try? FileManager.default.removeItem(at: world.root) }
        try await waitUntil { world.colin.review.count == 1 }
        try await settled(world.colin)
        #expect(world.colin.review.map(\.kind) == [.unfiled])
        world.colin.seen()
        try await waitUntil { world.colin.briefingAt != nil }
        #expect(world.colin.briefing == ["Cette semaine : aucun rendez-vous.", "À toi de jouer : Cabinet Martin."])
    }

    // MARK: - The refreshes

    /// Review Focus 5: ten requests in a row are one computation, and a burst of writings is not ten.
    @Test func aBurstOfChangesIsOneRefresh() async throws {
        let world = try await world(settle: .milliseconds(150)) { database, _, clock in try marcWaits(database, clock) }
        defer { try? FileManager.default.removeItem(at: world.root) }
        try await waitUntil { world.colin.review.count == 1 }
        try await settled(world.colin)
        var before = world.colin.computations
        for _ in 0..<10 { world.colin.refresh() }
        try await settled(world.colin)
        #expect(world.colin.computations == before + 1)
        // Ten mails arrive one after the other, as a synchronization writes them.
        before = world.colin.computations
        let readings = world.colin.readings
        for index in 0..<10 {
            try world.store.apply(account: Self.me, upserts: [received("n\(index)", thread: "n\(index)", from: Self.marc, at: world.clock.ago(Double(index) + 3.5))])
        }
        // One person, one line: on his oldest thread that waits.
        try await waitUntil { world.colin.review.count == 1 && world.colin.review.first?.days == 12 }
        try await settled(world.colin)
        #expect(world.colin.computations - before <= 2)
        #expect(world.colin.readings - readings <= 2)
        // Nothing changes: nothing is computed, however long one waits.
        before = world.colin.computations
        try await Task.sleep(for: .milliseconds(400))
        #expect(world.colin.computations == before)
    }

    /// Paul types in a draft: its text is saved again and again, and nothing a line says has changed.
    @Test func typingInADraftComputesNothing() async throws {
        let world = try await world()
        defer { try? FileManager.default.removeItem(at: world.root) }
        let mails = try #require(world.mails)
        let draft = agentDraft()
        try world.store.saveDraft(draft)
        try await waitUntil { world.colin.review.count == 1 }
        try await settled(world.colin)
        let before = world.colin.computations
        for index in 0..<5 {
            mails.edit(draft.id) { $0.body = "Bonjour Claire, voici le devis corrigé \(index)." }
            try await Task.sleep(for: .milliseconds(30))
        }
        try await waitUntil { mails.drafts.first?.body == "Bonjour Claire, voici le devis corrigé 4." }
        try await settled(world.colin)
        #expect(world.colin.computations == before)
        // Another recipient is something a line says: « Brouillon prêt pour Marc ».
        mails.edit(draft.id) { $0.to = [MailAddress(name: "Marc Dubois", email: Self.marc)] }
        try await waitUntil { world.colin.review.first?.person == "Marc" }
    }

    /// A reading that took long (a Mac that slept in the middle of it) never holds the next computations for long.
    @Test func aLongReadingNeverHoldsTheNextOnesForLong() {
        #expect(ColinLibrary.pause(settle: .milliseconds(300), reading: .zero) == .milliseconds(300))
        #expect(ColinLibrary.pause(settle: .milliseconds(300), reading: .milliseconds(20)) == .milliseconds(300))
        // Never more than a sixth of the time in readings…
        #expect(ColinLibrary.pause(settle: .milliseconds(300), reading: .milliseconds(200)) == .seconds(1))
        // … and never more than five seconds, whatever the reading took.
        #expect(ColinLibrary.pause(settle: .milliseconds(300), reading: .seconds(8 * 3_600)) == .seconds(5))
    }

    /// What is written and that no line says is not read again: Paul's notes in the page of a project, a mail read
    /// or archived, a calendar that writes the same events again.
    @Test func writingsTheAccueilDoesNotReadAreNotReadAgain() async throws {
        let world = try await world { database, _, clock in
            try marcWaits(database, clock)
            try meeting(database, clock)
        }
        defer { try? FileManager.default.removeItem(at: world.root) }
        try await waitUntil { world.colin.review.count == 2 }
        try await settled(world.colin)
        let readings = world.colin.readings, lines = world.colin.review
        let projects = ProjectStore(world.database)
        var project = try #require(try projects.project(id: world.project))
        for index in 0..<5 {
            let before = project
            project.notes = "Appel du matin, ligne \(index)."
            try projects.saveChanges(from: before, to: project, at: world.clock.now)
            try await Task.sleep(for: .milliseconds(40))
        }
        try world.store.apply(account: Self.me, labels: ["a2": ["INBOX", "CATEGORY_PERSONAL", "UNREAD"]])
        try await Task.sleep(for: .milliseconds(60))
        try world.store.apply(account: Self.me, labels: ["a2": ["CATEGORY_PERSONAL"]])
        let event = try #require(try CalendarStore(world.database).allEvents().first)
        try CalendarStore(world.database).applyGoogle(account: Self.me, changed: [event], cancelled: [], at: world.clock.now.addingTimeInterval(600))
        try await Task.sleep(for: .milliseconds(150))
        try await settled(world.colin)
        #expect(world.colin.readings == readings)
        #expect(world.colin.review == lines)
        // What a line or the point does say is read: the project is due in two days.
        let before = project
        project.dueDate = world.clock.now.addingTimeInterval(2 * 86_400)
        try projects.saveChanges(from: before, to: project, at: world.clock.now)
        try await waitUntil { world.colin.readings == readings + 1 }
    }

    /// What is published changes only when the lines do: a view that reads them is not redrawn for nothing.
    @Test func theListIsPublishedOnlyWhenItChanges() async throws {
        let world = try await world { database, _, clock in try marcWaits(database, clock) }
        defer { try? FileManager.default.removeItem(at: world.root) }
        try await waitUntil { world.colin.review.count == 1 }
        try await settled(world.colin)
        var published = 0
        let watch = world.colin.objectWillChange.sink { published += 1 }
        defer { watch.cancel() }
        for _ in 0..<3 {
            world.colin.refresh()
            try await settled(world.colin)
        }
        #expect(published == 0)
    }

    // MARK: - « Le point »

    @Test func theBriefingIsPreparedOnAReturnOnly() async throws {
        let world = try await world { database, project, clock in
            // Claire wrote in a thread of the project, long ago, and Paul answered.
            try MailStore(database).apply(account: Self.me, upserts: [
                received("b1", thread: "b", from: Self.claire, name: "Claire Morel", at: clock.ago(20)),
                sent("b2", thread: "b", to: Self.claire, at: clock.ago(19)),
            ])
            try MailStore(database).file(threadKey: key("b"), as: .project(project), at: clock.ago(20))
        }
        defer { try? FileManager.default.removeItem(at: world.root) }
        // Nothing is prepared before Paul is there.
        try await settled(world.colin)
        #expect(world.colin.briefing.isEmpty && world.colin.briefingAt == nil)
        let first = world.clock.now
        world.colin.seen()
        try await waitUntil { world.colin.briefingAt != nil }
        #expect(world.colin.briefingAt == first)
        // The very first time: nothing « since ».
        #expect(world.colin.briefing == ["Cette semaine : aucun rendez-vous.", "À toi de jouer : Cabinet Martin."])

        // Twenty minutes later he looks again: the point is closed, and stays as it was prepared whatever came meanwhile.
        world.clock.advance(hours: 1.0 / 3)
        var project = try #require(try ProjectStore(world.database).project(id: world.project))
        let original = project
        project.dueDate = world.clock.now.addingTimeInterval(2 * 86_400)
        try ProjectStore(world.database).saveChanges(from: original, to: project, at: world.clock.now)
        world.colin.seen()
        try await settled(world.colin)
        #expect(world.colin.briefingAt == first)
        #expect(world.colin.briefing == ["Cette semaine : aucun rendez-vous.", "À toi de jouer : Cabinet Martin."])

        // Claire writes at 10:38; four hours later Paul is back: prepared again, since the last time he was there.
        try world.store.apply(account: Self.me, upserts: [received("b3", thread: "b", from: Self.claire, name: "Claire Morel", at: world.clock.now.addingTimeInterval(18 * 60))])
        world.clock.advance(hours: 4)
        let back = world.clock.now
        world.colin.seen()
        try await waitUntil { world.colin.briefingAt == back }
        #expect(world.colin.briefing == ["Cette semaine : aucun rendez-vous.", "À livrer : Cabinet Martin vendredi.", "À toi de jouer : Cabinet Martin.",
                                         "Depuis 10:20 : 1 mail de client."])
    }

    /// Paul is back before the mailboxes were read again (the Mac just woke, Polhub just opened): what they bring a
    /// few seconds later was there while he was away, and enters the point. Once they and the calendars were read
    /// again, the point no longer moves.
    @Test func whatTheMailboxesBringAfterAReturnEntersThePoint() async throws {
        let world = try await world { database, project, clock in
            try MailStore(database).apply(account: Self.me, upserts: [
                received("b1", thread: "b", from: Self.claire, name: "Claire Morel", at: clock.ago(20)),
                sent("b2", thread: "b", to: Self.claire, at: clock.ago(19)),
            ])
            try MailStore(database).file(threadKey: key("b"), as: .project(project), at: clock.ago(20))
        }
        defer { try? FileManager.default.removeItem(at: world.root) }
        world.colin.seen()
        try await waitUntil { world.colin.briefingAt != nil }
        // Thirteen hours later the Mac wakes: the point is prepared on the copy of before the sleep.
        world.clock.advance(hours: 13)
        let back = world.clock.now
        world.colin.seen()
        try await waitUntil { world.colin.briefingAt == back }
        try await settled(world.colin)
        #expect(world.colin.briefing == ["Cette semaine : aucun rendez-vous.", "À toi de jouer : Cabinet Martin."])
        // Gmail answers: Claire wrote three hours ago.
        try world.store.apply(account: Self.me, upserts: [received("b3", thread: "b", from: Self.claire, name: "Claire Morel", at: back.addingTimeInterval(-3 * 3_600))])
        try await waitUntil { world.colin.briefing.last == "Depuis 10:00 : 1 mail de client." }
        #expect(world.colin.briefingAt == back)
        // The mailbox and the calendar were read again since his return: the point is closed.
        try world.store.save(MailCursorRow(account: Self.me, lastSyncAt: back.addingTimeInterval(20)))
        try CalendarStore(world.database).recordSync(email: Self.me, syncToken: nil, error: nil, at: back.addingTimeInterval(20))
        try await waitUntil { world.mails?.cursors[Self.me]?.lastSyncAt != nil && world.agenda.accounts.first?.lastSyncAt != nil }
        world.clock.advance(hours: 1.0 / 60)
        world.colin.refresh()
        try await settled(world.colin)
        try world.store.apply(account: Self.me, upserts: [received("c1", thread: "c", from: Self.claire, name: "Claire Morel", at: back.addingTimeInterval(-2 * 3_600))])
        try world.store.file(threadKey: key("c"), as: .project(world.project), at: world.clock.now)
        try await Task.sleep(for: .milliseconds(150))
        try await settled(world.colin)
        #expect(world.colin.briefing.last == "Depuis 10:00 : 1 mail de client." && world.colin.briefingAt == back)
    }

    /// A copy read again writes what it found, then notes that it was read, in one pass: what the last one brings
    /// enters the point too, before it is closed. For a mailbox as for a calendar.
    @Test func whatTheLastCopyReadAgainBringsEntersThePointToo() async throws {
        let world = try await world { database, project, clock in
            try MailStore(database).apply(account: Self.me, upserts: [
                received("b1", thread: "b", from: Self.claire, name: "Claire Morel", at: clock.ago(20)),
                sent("b2", thread: "b", to: Self.claire, at: clock.ago(19)),
            ])
            try MailStore(database).file(threadKey: key("b"), as: .project(project), at: clock.ago(20))
        }
        defer { try? FileManager.default.removeItem(at: world.root) }
        world.colin.seen()
        try await waitUntil { world.colin.briefingAt != nil }
        world.clock.advance(hours: 13)
        let back = world.clock.now
        world.colin.seen()
        try await waitUntil { world.colin.briefingAt == back }
        try await settled(world.colin)
        // The calendar is read first: nothing new there.
        try CalendarStore(world.database).recordSync(email: Self.me, syncToken: nil, error: nil, at: back.addingTimeInterval(5))
        try await waitUntil { world.agenda.accounts.first?.lastSyncAt != nil }
        // Then the mailbox, in one pass: Claire's mail of the evening, and the note that the mailbox was read.
        try world.store.apply(account: Self.me, upserts: [received("b3", thread: "b", from: Self.claire, name: "Claire Morel", at: back.addingTimeInterval(-3 * 3_600))])
        try world.store.save(MailCursorRow(account: Self.me, lastSyncAt: back.addingTimeInterval(6)))
        try await waitUntil { world.colin.briefing.last == "Depuis 10:00 : 1 mail de client." }
        try await settled(world.colin)
        // Everything was read again: the point is closed, what comes later is for the next one.
        try world.store.apply(account: Self.me, upserts: [received("c1", thread: "c", from: Self.claire, name: "Claire Morel", at: back.addingTimeInterval(-2 * 3_600))])
        try world.store.file(threadKey: key("c"), as: .project(world.project), at: world.clock.now)
        try await Task.sleep(for: .milliseconds(150))
        try await settled(world.colin)
        #expect(world.colin.briefing.last == "Depuis 10:00 : 1 mail de client." && world.colin.briefingAt == back)
    }

    /// The same for the calendar read last: an event taken while Paul was away is in « Cette semaine ».
    @Test func anEventTheCalendarBringsAfterAReturnEntersThePoint() async throws {
        let world = try await world()
        defer { try? FileManager.default.removeItem(at: world.root) }
        world.colin.seen()
        try await waitUntil { world.colin.briefingAt != nil }
        world.clock.advance(hours: 4)
        let back = world.clock.now
        world.colin.seen()
        try await waitUntil { world.colin.briefingAt == back }
        try await settled(world.colin)
        #expect(world.colin.briefing.first == "Cette semaine : aucun rendez-vous.")
        try world.store.save(MailCursorRow(account: Self.me, lastSyncAt: back.addingTimeInterval(5)))
        try await waitUntil { world.mails?.cursors[Self.me]?.lastSyncAt != nil }
        // A client took a slot tomorrow at ten; the calendar writes it, then notes that it was read.
        let start = paris.date(bySettingHour: 10, minute: 0, second: 0, of: back.addingTimeInterval(86_400))!
        let event = CalendarEventRow(account: Self.me, eventID: "e9", title: "Point Cabinet Martin", startAt: start, endAt: start.addingTimeInterval(3_600), updatedAt: back)
        try CalendarStore(world.database).applyGoogle(account: Self.me, changed: [event], cancelled: [], at: back.addingTimeInterval(6))
        try CalendarStore(world.database).recordSync(email: Self.me, syncToken: nil, error: nil, at: back.addingTimeInterval(6))
        try await waitUntil { world.colin.briefing.first == "Cette semaine : 1 rendez-vous, demain 10:00." }
        #expect(world.colin.briefingAt == back)
    }

    /// Polhub is quit and opened again (an update): the point is prepared again at once, with the same « since ».
    @Test func aRelaunchPreparesThePointAgain() async throws {
        let clock = Clock()
        let defaults = try #require(UserDefaults(suiteName: "colin-\(UUID().uuidString)"))
        let world = try await world(defaults: defaults, clock: clock) { database, project, clock in
            try MailStore(database).apply(account: Self.me, upserts: [
                sent("b1", thread: "b", to: Self.claire, at: clock.ago(30)),
                received("b2", thread: "b", from: Self.claire, name: "Claire Morel", at: clock.now.addingTimeInterval(3_600)),
            ])
            try MailStore(database).file(threadKey: key("b"), as: .project(project), at: clock.ago(30))
        }
        defer { try? FileManager.default.removeItem(at: world.root) }
        world.colin.seen()
        try await waitUntil { world.colin.briefingAt != nil }
        clock.advance(hours: 4)
        world.colin.seen()
        try await waitUntil { world.colin.briefingAt == clock.now }
        #expect(world.colin.briefing.last == "Depuis 10:00 : 1 mail de client.")

        // Ten minutes later, another library on the same base and the same preferences: the app, opened again. Paul
        // was there all along: the mail of the morning is no news, the point says so no more.
        clock.advance(hours: 1.0 / 6)
        let again = ColinLibrary(agenda: world.agenda, mails: world.mails, defaults: defaults, now: { clock.now }, calendar: paris, settle: .milliseconds(30),
                                 every: .seconds(3_600))
        try await settled(again)
        #expect(again.briefing.isEmpty)
        again.seen()
        try await waitUntil { again.briefingAt != nil }
        #expect(again.briefingAt == clock.now)
        #expect(again.briefing == ["Cette semaine : aucun rendez-vous.", "À toi de jouer : Cabinet Martin."])

        // What came since his last passage is news: Claire writes at 14:15, the app opens again at 14:20.
        try world.store.apply(account: Self.me, upserts: [received("b3", thread: "b", from: Self.claire, name: "Claire Morel", at: clock.now.addingTimeInterval(5 * 60))])
        clock.advance(hours: 1.0 / 6)
        let third = ColinLibrary(agenda: world.agenda, mails: world.mails, defaults: defaults, now: { clock.now }, calendar: paris, settle: .milliseconds(30),
                                 every: .seconds(3_600))
        third.seen()
        try await waitUntil { third.briefingAt != nil }
        #expect(third.briefing.last == "Depuis 14:10 : 1 mail de client.")
    }

    /// Paul leaves the Accueil (another app, another page): his absence starts then, not at his last arrival.
    @Test func leavingTheAccueilStartsTheAbsence() async throws {
        let world = try await world()
        defer { try? FileManager.default.removeItem(at: world.root) }
        world.colin.seen()
        // An hour and a half on the Accueil, then an hour and a half elsewhere: ninety minutes away, not three hours.
        world.clock.advance(hours: 1.5)
        world.colin.left()
        world.clock.advance(hours: 1.5)
        let first = world.colin.briefingAt
        world.colin.seen()
        #expect(world.defaults.array(forKey: Preferences.Key.colinAbsences) as? [Int] == [90])
        try await settled(world.colin)
        // Not a return: the point stays the one of this morning.
        #expect(world.colin.briefingAt == first || first == nil)
        // Without the departure noted, the same hours would have been a return.
        world.clock.advance(hours: 3.5)
        world.colin.seen()
        #expect(world.defaults.array(forKey: Preferences.Key.colinAbsences) as? [Int] == [90, 210])
        try await waitUntil { world.colin.briefingAt == world.clock.now }
    }

    /// The bar at the bottom of the mails also shows over the Accueil. What it says of a draft an agent prepared is
    /// already said there by the line « Brouillon prêt »: over the Accueil it is not said again.
    @Test func theNewsOfADraftIsNotSaidTwiceOnTheAccueil() async throws {
        let world = try await world()
        defer { try? FileManager.default.removeItem(at: world.root) }
        let mails = try #require(world.mails)
        try world.store.drop(MailAgentDraftRow(mode: .new, account: Self.me, to: [MailAddress(name: "Claire Morel", email: Self.claire)], subject: "Devis d'avril",
                                               body: "Bonjour Claire, voici le devis.", createdAt: Date()))
        try await waitUntil { mails.message != nil }
        #expect(mails.message == "Un agent a préparé « Devis d'avril » : il t'attend dans Brouillons.")
        #expect(mails.barMessage(draftNews: true) == mails.message)
        #expect(mails.barMessage(draftNews: false) == nil)
        // Anything else is said everywhere: what a gesture answered, a mail that could not leave.
        mails.message = "Envoi annulé : le mail t'attend dans Brouillons."
        #expect(mails.barMessage(draftNews: false) == "Envoi annulé : le mail t'attend dans Brouillons.")
        #expect(mails.barMessage(draftNews: true) == "Envoi annulé : le mail t'attend dans Brouillons.")
    }

    /// The absences are kept in minutes, the last hundred, from half an hour up: numbers only, to set the threshold
    /// of a return. Those shorter than the threshold are kept too: without them, nothing says whether it is right.
    @Test func theAbsencesAreKeptInMinutes() async throws {
        let world = try await world()
        defer { try? FileManager.default.removeItem(at: world.root) }
        world.colin.seen()
        #expect(world.defaults.array(forKey: Preferences.Key.colinAbsences) == nil)
        // Twenty minutes: Paul only went to another window.
        world.clock.advance(hours: 1.0 / 3)
        world.colin.seen()
        #expect(world.defaults.array(forKey: Preferences.Key.colinAbsences) == nil)
        // An hour: not a return, but an absence all the same.
        world.clock.advance(hours: 1)
        world.colin.seen()
        #expect(world.defaults.array(forKey: Preferences.Key.colinAbsences) as? [Int] == [60])
        world.clock.advance(hours: 4)
        world.colin.seen()
        #expect(world.defaults.array(forKey: Preferences.Key.colinAbsences) as? [Int] == [60, 240])
        for _ in 0..<110 {
            world.clock.advance(hours: 5)
            world.colin.seen()
        }
        let kept = try #require(world.defaults.array(forKey: Preferences.Key.colinAbsences) as? [Int])
        #expect(kept.count == 100 && kept.allSatisfy { $0 == 300 })
        // What is kept of the presence: three dates, nothing else.
        let data = try #require(world.defaults.data(forKey: Preferences.Key.colinPresence))
        let state = try JSONDecoder().decode(Presence.State.self, from: data)
        #expect(state.lastSeen == world.clock.now)
        try await settled(world.colin)
    }

    // MARK: - « Colin tient le kanban seul » (step 3, 18/11)

    /// Claire, of « Cabinet Martin », wrote in thread « b », filed in the project.
    func claireWrote(_ database: AppDatabase, _ project: UUID, _ clock: Clock) throws {
        try MailStore(database).apply(account: Self.me, upserts: [received("b1", thread: "b", from: Self.claire, name: "Claire Morel", at: clock.ago(3))])
        try MailStore(database).file(threadKey: key("b"), as: .project(project), at: clock.ago(3))
    }

    func kanbanDefaults(on: Bool = true, colin: Bool = true, since: Date?) throws -> UserDefaults {
        let suite = try #require(UserDefaults(suiteName: "colin-\(UUID().uuidString)"))
        suite.set(colin, forKey: Preferences.Key.colinOn)
        suite.set(on, forKey: Preferences.Key.colinKanban)
        if let since { suite.set(since, forKey: Preferences.Key.colinKanbanSince) }
        return suite
    }

    func paulAnswersClaire(_ world: World, id: String = "b2", minutesAgo: Double = 10) throws {
        var mail = sent(id, thread: "b", to: Self.claire, at: world.clock.now.addingTimeInterval(-minutesAgo * 60))
        mail.to = [MailAddress(name: "Claire Morel", email: Self.claire)]
        try world.store.apply(account: Self.me, upserts: [mail])
    }

    @Test func theRulesWriteWhenColinAndTheSwitchAreOn() async throws {
        let clock = Clock()
        let world = try await world(defaults: try kanbanDefaults(since: clock.ago(1)), clock: clock) { database, project, clock in
            try claireWrote(database, project, clock)
        }
        defer { try? FileManager.default.removeItem(at: world.root) }
        try paulAnswersClaire(world)
        let projects = ProjectStore(world.database)
        try await waitUntil { (try? projects.project(id: world.project))?.todo == "En attente retour de Claire" }
        #expect(try projects.project(id: world.project)?.status == .priorite1)
        let lines = try ProjectChanges(world.database).lines(since: .distantPast, authors: [.colin])
        #expect(lines.count == 1 && lines.first?.reason == "Après ton mail à Claire, 9:50")
        // A meeting booked tomorrow in the project: its deadline.
        let start = world.clock.now.addingTimeInterval(86_400)
        let event = CalendarEventRow(account: Self.me, eventID: "e9", title: "Point devis", startAt: start, endAt: start.addingTimeInterval(1_800),
                                     updatedAt: world.clock.now)
        try CalendarStore(world.database).applyGoogle(account: Self.me, changed: [event], cancelled: [], at: world.clock.now)
        try CalendarStore(world.database).setProject(eventID: event.id, projectID: world.project, origin: .paul)
        try await waitUntil { (try? projects.project(id: world.project))?.dueDate == paris.startOfDay(for: start) }
        try await settled(world.colin)
    }

    @Test func nothingIsWrittenWhenColinIsOff() async throws {
        let clock = Clock()
        let world = try await world(defaults: try kanbanDefaults(colin: false, since: clock.ago(1)), clock: clock) { database, project, clock in
            try claireWrote(database, project, clock)
        }
        defer { try? FileManager.default.removeItem(at: world.root) }
        try paulAnswersClaire(world)
        try await settled(world.colin)
        world.colin.refresh()
        try await settled(world.colin)
        #expect(try ProjectStore(world.database).project(id: world.project)?.todo == nil)
        #expect(try ProjectChanges(world.database).lines(since: .distantPast, authors: [.colin]).isEmpty)
    }

    /// Computed again and again (the minutes pass, the base is read from memory): the mail is answered once.
    @Test func aRuleIsWrittenOnceEvenOnCachedInputs() async throws {
        let clock = Clock()
        let world = try await world(defaults: try kanbanDefaults(since: clock.ago(1)), clock: clock) { database, project, clock in
            try claireWrote(database, project, clock)
        }
        defer { try? FileManager.default.removeItem(at: world.root) }
        try paulAnswersClaire(world)
        let projects = ProjectStore(world.database)
        try await waitUntil { (try? projects.project(id: world.project))?.todo == "En attente retour de Claire" }
        for _ in 0..<3 {
            world.clock.advance(hours: 0.02)
            world.colin.refresh()
            try await settled(world.colin)
        }
        #expect(try projects.journal(projectID: world.project).map(\.title) == ["Mail envoyé à Claire le 18/11"])
        #expect(try ProjectChanges(world.database).lines(since: .distantPast, authors: [.colin]).count == 1)
    }

    /// Turned on now, the switch leaves what was sent before: Colin keeps the cards from now on.
    @Test func turningTheSwitchOnLeavesTheMailsOfBefore() async throws {
        let clock = Clock()
        let defaults = try kanbanDefaults(on: false, since: nil)
        let world = try await world(defaults: defaults, clock: clock) { database, project, clock in try claireWrote(database, project, clock) }
        defer { try? FileManager.default.removeItem(at: world.root) }
        try paulAnswersClaire(world, minutesAgo: 10)
        try await settled(world.colin)
        defaults.set(true, forKey: Preferences.Key.colinKanban)
        try await settled(world.colin)
        world.colin.refresh()
        try await settled(world.colin)
        let projects = ProjectStore(world.database)
        #expect(try projects.project(id: world.project)?.todo == nil)
        world.clock.advance(hours: 0.1)
        try paulAnswersClaire(world, id: "b3", minutesAgo: 1)
        try await waitUntil { (try? projects.project(id: world.project))?.todo == "En attente retour de Claire" }
        try await settled(world.colin)
    }
}
