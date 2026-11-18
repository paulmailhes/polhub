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

    @Test func aDismissedLineLeavesAtOnce() async throws {
        let world = try await world { database, _, clock in try marcWaits(database, clock) }
        defer { try? FileManager.default.removeItem(at: world.root) }
        try await waitUntil { world.colin.review.count == 1 }
        let line = try #require(world.colin.review.first)
        #expect(line.id == "reply:\(key("a"))" && line.person == "Marc" && line.days == 4)
        world.colin.dismiss(line, reason: .notNeeded)
        // At once: before the base is read again.
        #expect(world.colin.review.isEmpty)
        try await settled(world.colin)
        #expect(world.colin.review.isEmpty)
        // The base keeps it, with the last message Paul had before him.
        let rows = try ColinStore(world.database).dismissals()
        #expect(rows.map(\.id) == ["reply:\(key("a"))"])
        #expect(rows.first?.reason == .notNeeded && rows.first?.lastMessageAt == world.clock.ago(4) && rows.first?.createdAt == world.clock.now)
        // Marc writes again; three days later the line is back.
        try world.store.apply(account: Self.me, upserts: [received("a3", thread: "a", from: Self.marc, at: world.clock.now.addingTimeInterval(60))])
        try await settled(world.colin)
        #expect(world.colin.review.isEmpty)
        world.clock.advance(days: 3.1)
        world.colin.refresh()
        try await waitUntil { world.colin.review.map(\.id) == ["reply:\(key("a"))"] }
        #expect(world.colin.review.first?.days == 3)
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
        #expect(world.colin.review.map(\.id) == ["reply:\(key("a"))", "silent:\(key("b"))"])
        #expect(world.colin.review.last?.person == "Claire" && world.colin.review.last?.detail == "Cabinet Martin" && world.colin.review.last?.days == 8)
        // Réglages › Colin : five days for an answer.
        world.defaults.set(5, forKey: Preferences.Key.colinReplyDays)
        try await waitUntil { world.colin.review.map(\.id) == ["silent:\(key("b"))"] }
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
        try await waitUntil { world.colin.review.count == 11 }
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

        // Twelve minutes later he looks again: the point stays as it was prepared, whatever came meanwhile.
        world.clock.advance(hours: 0.2)
        var project = try #require(try ProjectStore(world.database).project(id: world.project))
        let original = project
        project.dueDate = world.clock.now.addingTimeInterval(2 * 86_400)
        try ProjectStore(world.database).saveChanges(from: original, to: project, at: world.clock.now)
        world.colin.seen()
        try await settled(world.colin)
        #expect(world.colin.briefingAt == first)
        #expect(world.colin.briefing == ["Cette semaine : aucun rendez-vous.", "À toi de jouer : Cabinet Martin."])

        // Claire writes at 10:30; four hours later Paul is back: prepared again, since the last time he was there.
        try world.store.apply(account: Self.me, upserts: [received("b3", thread: "b", from: Self.claire, name: "Claire Morel", at: world.clock.now.addingTimeInterval(18 * 60))])
        world.clock.advance(hours: 4)
        let back = world.clock.now
        world.colin.seen()
        try await waitUntil { world.colin.briefingAt == back }
        #expect(world.colin.briefing == ["Cette semaine : aucun rendez-vous.", "À livrer : Cabinet Martin vendredi.", "À toi de jouer : Cabinet Martin.",
                                         "Depuis 10:12 : 1 mail de client."])
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

        // Ten minutes later, another library on the same base and the same preferences: the app, opened again.
        clock.advance(hours: 1.0 / 6)
        let again = ColinLibrary(agenda: world.agenda, mails: world.mails, defaults: defaults, now: { clock.now }, calendar: paris, settle: .milliseconds(30),
                                 every: .seconds(3_600))
        try await settled(again)
        #expect(again.briefing.isEmpty)
        again.seen()
        try await waitUntil { again.briefingAt != nil }
        #expect(again.briefingAt == clock.now)
        #expect(again.briefing.last == "Depuis 10:00 : 1 mail de client.")
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
}
