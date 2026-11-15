import Agenda
import Foundation
import GoogleKit
import Mail
import MailFormat
import Notifications
import Persistence
import PolhubDesign
import Testing
@testable import MeetingsUI

/// A Gmail that answers nothing and remembers every request: no test here reaches Google, and none may send.
final class SilentGmail: @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    var calls: [String] { lock.withLock { log } }

    var send: MailProbe.Send {
        { [self] build in
            let request = build("jeton")
            lock.withLock { log.append("\(request.httpMethod ?? "GET") \(request.url?.path() ?? "")") }
            throw GoogleError.http(599)
        }
    }
}

/// Wave B, 15/11 (« Programmer l'envoi »): Gmail's choices, the words of the hours, the library's lock and folder.
@Suite struct SchedulePresetsTests {
    var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "fr_FR")
        return calendar
    }

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        paris.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// A Friday afternoon: tomorrow morning, tomorrow afternoon, Monday morning.
    @Test func gmailsChoicesOnAFriday() {
        let options = SchedulePresets.options(now: date(2026, 11, 20, 15), calendar: paris)
        #expect(options.map(\.title) == ["Demain matin", "Demain après-midi", "Lundi matin"])
        #expect(options.map(\.date) == [date(2026, 11, 21, 8), date(2026, 11, 21, 13), date(2026, 11, 23, 8)])
    }

    /// On a Sunday, « Lundi matin » would be tomorrow morning; on a Monday, Gmail does not offer it.
    @Test func noMondayTwiceNorOnMonday() {
        #expect(SchedulePresets.options(now: date(2026, 11, 22, 10), calendar: paris).map(\.title) == ["Demain matin", "Demain après-midi"])
        #expect(SchedulePresets.options(now: date(2026, 11, 23, 6), calendar: paris).map(\.title) == ["Demain matin", "Demain après-midi"])
        #expect(SchedulePresets.options(now: date(2026, 11, 24, 23, 50), calendar: paris).last?.date == date(2026, 11, 30, 8))
    }

    /// The change of hour (28/03/2027 in Paris): 8:00 stays 8:00 on the clock.
    @Test func theChangeOfHourKeepsTheHour() {
        let options = SchedulePresets.options(now: date(2027, 3, 27, 22), calendar: paris)
        #expect(options.map { paris.component(.hour, from: $0.date) } == [8, 13, 8])
        #expect(options.map { paris.component(.day, from: $0.date) } == [28, 28, 29])
        #expect(options[1].date.timeIntervalSince(options[0].date) == 5 * 3_600)
    }

    @Test func theHoursInWords() {
        let now = date(2026, 11, 18, 10)
        #expect(MailText.clock(date(2026, 11, 18, 8), calendar: paris) == "8:00")
        #expect(MailText.clock(date(2026, 11, 18, 13, 5), calendar: paris) == "13:05")
        #expect(MailText.scheduled(date(2026, 11, 18, 18, 30), now: now, calendar: paris) == "aujourd'hui 18:30")
        #expect(MailText.scheduled(date(2026, 11, 19, 8), now: now, calendar: paris) == "demain 8:00")
        #expect(MailText.scheduled(date(2026, 11, 17, 8), now: now, calendar: paris) == "hier 8:00")
        #expect(MailText.scheduled(date(2026, 11, 23, 8), now: now, calendar: paris) == "lundi 8:00")
        #expect(MailText.scheduled(date(2026, 12, 1, 8), now: now, calendar: paris) == "mardi 1 décembre 8:00")
        #expect(MailText.scheduled(date(2027, 1, 4, 8), now: now, calendar: paris) == "lundi 4 janvier 2027 8:00")
        #expect(MailText.scheduledShort(date(2026, 11, 18, 18, 30), now: now, calendar: paris) == "18:30")
        #expect(MailText.scheduledShort(date(2026, 11, 23, 8), now: now, calendar: paris) == "lun. 8:00")
        #expect(MailText.scheduledShort(date(2026, 12, 1, 8), now: now, calendar: paris) == "1 déc. 8:00")
        #expect(MailText.presetDate(date(2026, 11, 21, 8), calendar: paris) == "sam. 21 nov. 8:00")
    }

    /// What Paul reads when it is over (Paul, 15/11).
    @Test func whatPaulIsTold() {
        let planned = date(2026, 11, 23, 8)
        let entry = ScheduledSend(draftID: "d", account: "moi@exemple.fr", sendAt: planned, fingerprint: "", subject: "Devis", threadKey: nil,
                                  createdAt: planned)
        let late = MailLibrary.texts(for: .sent(entry, at: date(2026, 11, 23, 9, 12)), calendar: paris)
        #expect(late.notice?.body == "Parti à 9:12 au lieu de 8:00 : ton Mac était en veille ou Polhub fermé." && late.notice?.title == "« Devis »")
        #expect(MailLibrary.texts(for: .sent(entry, at: planned.addingTimeInterval(2)), calendar: paris).notice == nil)
        let changed = MailLibrary.texts(for: .stopped(entry, .changed), calendar: paris)
        #expect(changed.notice?.body.hasPrefix("« Devis » n'est pas parti : le brouillon a changé depuis que tu l'as programmé.") == true)
        #expect(changed.notice?.folder == .drafts)
        let held = MailLibrary.texts(for: .held(entry), now: date(2026, 11, 23, 21), calendar: paris)
        #expect(held.notice?.title == "Pas encore parti" && held.notice?.folder == .scheduled)
        #expect(held.notice?.body.contains("programmé pour aujourd'hui 8:00") == true)
        #expect(MailLibrary.texts(for: .maybeSent(entry)).notice?.body.contains("peut-être parti") == true)
    }

    /// Updates wait from three minutes before the time until the mail left; never for one that waits for Paul.
    @Test func updatesWaitAroundAProgrammedSend() {
        let now = date(2026, 11, 23, 7, 58)
        func entry(_ at: Date, _ state: ScheduledSend.State = .waiting) -> ScheduledSend {
            ScheduledSend(draftID: UUID().uuidString, account: "moi@exemple.fr", sendAt: at, fingerprint: "", subject: "x", threadKey: nil, state: state, createdAt: now)
        }
        #expect(MailLibrary.holdsUpdates([entry(now.addingTimeInterval(120))], now: now))
        #expect(!MailLibrary.holdsUpdates([entry(now.addingTimeInterval(600))], now: now))
        #expect(MailLibrary.holdsUpdates([entry(now.addingTimeInterval(-3_600))], now: now))
        #expect(!MailLibrary.holdsUpdates([entry(now.addingTimeInterval(-13 * 3_600))], now: now))
        #expect(MailLibrary.holdsUpdates([entry(now.addingTimeInterval(86_400), .leaving)], now: now))
        #expect(!MailLibrary.holdsUpdates([entry(now.addingTimeInterval(-3_600), .held)], now: now))
    }
}

@MainActor
@Suite struct MailScheduleLibraryTests {
    let account = "moi@exemple.fr"

    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<150 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
        #expect(condition())
    }

    func library(defaults: UserDefaults? = nil, gmail: SilentGmail = SilentGmail(), vault: MemoryScheduleVault = MemoryScheduleVault())
        async throws -> (MailLibrary, MailStore, URL) {
        let database = try AppDatabase.inMemory()
        let calendar = CalendarStore(database)
        try calendar.addAccount(email: account, at: Date())
        try calendar.setGrantedScopes(email: account, scopes: "openid https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/gmail.modify")
        let root = FileManager.default.temporaryDirectory.appending(path: "programme-\(UUID().uuidString)", directoryHint: .isDirectory)
        let suite = try defaults ?? #require(UserDefaults(suiteName: "programme-\(UUID().uuidString)"))
        let mails = MailLibrary(agenda: AgendaLibrary(database: database), root: root, defaults: suite, flavor: .prod, send: { _ in gmail.send }, vault: vault)
        try await waitUntil { mails.accounts.count == 1 }
        return (mails, MailStore(database), root)
    }

    func draft(_ store: MailStore, subject: String = "Devis d'avril") throws -> MailDraftRow {
        let draft = MailDraftRow(account: account, mode: .new, to: [MailAddress(name: "Jules Durand", email: "jules@exemple.fr")], subject: subject,
                                 body: "Bonjour Jules, voici le devis.", signature: false, createdAt: Date())
        try store.saveDraft(draft)
        return draft
    }

    /// Programmed, the mail leaves Brouillons for « Programmés », is locked, and « Annuler » takes it back.
    @Test func programmingLocksTheDraftAndMovesIt() async throws {
        let vault = MemoryScheduleVault()
        let (mails, store, root) = try await library(vault: vault)
        defer { try? FileManager.default.removeItem(at: root) }
        let row = try draft(store)
        try await waitUntil { mails.drafts.count == 1 }
        #expect(mails.draftCount == 1 && !mails.showsScheduled)
        mails.composing = row.id
        let at = Date().addingTimeInterval(3_600)
        mails.schedule(row.id, at: at)
        try await waitUntil { mails.scheduled[row.id] != nil }
        #expect(vault.all.map(\.draftID) == [row.id] && vault.all.first?.sendAt == at)
        #expect(mails.draftCount == 0 && mails.scheduledDrafts.map(\.draft.id) == [row.id] && mails.showsScheduled)
        #expect(mails.composing == nil)
        #expect(mails.undoable?.text == "« Devis d'avril » programmé pour \(MailText.scheduled(at))")
        // Locked: nothing Paul could still type changes what leaves.
        mails.edit(row.id) { $0.body = "Autre chose" }
        mails.attach([URL(fileURLWithPath: "/etc/hosts")], to: row.id)
        #expect(try store.draft(row.id)?.body == "Bonjour Jules, voici le devis." && store.draft(row.id)?.files.isEmpty == true)
        mails.send(row.id)
        #expect(mails.sending == nil)
        // « Annuler », in the bar: a draft again, open again.
        mails.undo()
        try await waitUntil { mails.scheduled.isEmpty }
        #expect(vault.all.isEmpty && mails.draftCount == 1 && mails.composing == row.id)
        mails.edit(row.id) { $0.body = "Bonjour Jules, voici le devis corrigé." }
        #expect(try store.draft(row.id)?.body == "Bonjour Jules, voici le devis corrigé.")
    }

    /// « Programmés » sits between Brouillons and Tous les messages, as Gmail's, with its clock.
    @Test func programmesHasItsPlaceUnderMails() {
        #expect(MailFolder.allCases == [.inbox, .sent, .drafts, .scheduled, .all, .subscriptions, .spam, .trash])
        #expect(MailFolder.scheduled.title == "Programmés" && MailFolder.scheduled.icon == "clock" && MailFolder.scheduled.aside == nil)
    }

    /// The updates of the app wait for a programmed mail about to leave.
    @Test func updatesWaitForAMailAboutToLeave() async throws {
        let (mails, store, root) = try await library()
        defer { try? FileManager.default.removeItem(at: root) }
        let row = try draft(store)
        #expect(!mails.isSending)
        mails.schedule(row.id, at: Date().addingTimeInterval(120))
        try await waitUntil { mails.scheduled[row.id] != nil }
        #expect(mails.isSending)
    }

    /// The guarantee of 14/11 with the programmed sends: no setting (whatever its key) and no row makes a mail
    /// leave; only Paul's choice, kept in the Keychain, does.
    @Test func noSettingNorRowEverSends() async throws {
        let defaults = try #require(UserDefaults(suiteName: "programme-reglages-\(UUID().uuidString)"))
        let past = Date().addingTimeInterval(-60)
        defaults.set(0, forKey: Preferences.Key.mailUndoSeconds)
        defaults.set(["envoi-1"], forKey: Preferences.Key.mailUnconfirmed)
        defaults.set(#"[{"draftID":"envoi-1","account":"moi@exemple.fr","sendAt":0,"fingerprint":"","subject":"x","state":"waiting","createdAt":0}]"#,
                     forKey: "mails.envoisProgrammes")
        defaults.set(["envoi-1": past], forKey: "mails.programmes")
        let gmail = SilentGmail(), vault = MemoryScheduleVault()
        let (mails, store, root) = try await library(defaults: defaults, gmail: gmail, vault: vault)
        defer { try? FileManager.default.removeItem(at: root) }
        let row = MailDraftRow(id: "envoi-1", account: account, mode: .new, to: [MailAddress(email: "jules@exemple.fr")], subject: "x", body: "Pars",
                               gmailDraftID: "r1", gmailMessageID: "m1", origin: .agent, pushedAt: past, createdAt: past)
        try store.saveDraft(row)
        try store.drop(MailAgentDraftRow(mode: .new, account: account, to: [MailAddress(email: "jules@exemple.fr")], subject: "Devis", body: "Envoie à 8:00",
                                         createdAt: past))
        mails.start()
        for _ in 0..<3 {
            mails.refresh()
            try await Task.sleep(for: .milliseconds(150))
        }
        #expect(!gmail.calls.contains { $0.hasSuffix("/drafts/send") })
        #expect(gmail.calls.contains { $0.hasSuffix("/history") || $0.hasSuffix("/profile") || $0.hasSuffix("/sendAs") })
        #expect(mails.scheduled.isEmpty && vault.saves == 0 && mails.sending == nil)
        await mails.engine.follow(accounts: [])
    }

    /// A programmed reply waits for its time under its thread; its line in the list says « Programmé ».
    @Test func aMailWaitingForPaulShowsInProgrammes() async throws {
        let vault = MemoryScheduleVault()
        let (mails, store, root) = try await library(vault: vault)
        defer { try? FileManager.default.removeItem(at: root) }
        let row = try draft(store)
        try vault.save([ScheduledSend(draftID: row.id, account: account, sendAt: Date().addingTimeInterval(-13 * 3_600), fingerprint: "", subject: row.subject,
                                      threadKey: nil, state: .held, createdAt: Date())])
        // A launch later: the vault is read.
        let again = MailLibrary(agenda: mails.agenda, root: root, defaults: try #require(UserDefaults(suiteName: "programme-\(UUID().uuidString)")),
                                flavor: .prod, send: { [silent = SilentGmail()] _ in silent.send }, vault: vault)
        try await waitUntil { again.scheduledDrafts.count == 1 }
        #expect(again.scheduledDrafts.first?.entry.state == .held && again.showsScheduled && again.draftCount == 0)
        #expect(!again.isSending)
        again.show(folderNamed: "scheduled")
        #expect(again.folder == .scheduled && again.shown.isEmpty)
    }
}

/// The notification of a programmed mail opens its folder when it has no thread.
@MainActor @Suite struct ScheduleNoticeTests {
    @Test func aNoticeNamesItsFolder() async throws {
        let center = NotificationHubTests.Center()
        let hub = NotificationHub(agenda: AgendaLibrary(database: try AppDatabase.inMemory()), client: center,
                                  settings: { Preferences(defaults: UserDefaults(suiteName: "avis-\(UUID().uuidString)")!) })
        await hub.mailScheduleNotice(MailScheduleNotice(title: "Pas encore parti", body: "« Devis »…", threadKey: nil, folder: .scheduled))
        await hub.mailScheduleNotice(MailScheduleNotice(title: "Mail non envoyé", body: "…", threadKey: "moi@exemple.fr|t1", folder: .drafts))
        #expect(center.delivered.map(\.kind) == [.mail, .mail])
        #expect(center.delivered.map(\.folder) == ["scheduled", nil] && center.delivered.map(\.threadKey) == [nil, "moi@exemple.fr|t1"])
    }
}
