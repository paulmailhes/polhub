import AppKit
import Agenda
import Domain
import Foundation
import Persistence
import PolhubDesign
import ProjectsUI
import SwiftUI
import Testing
import Updates
@testable import MeetingsUI

/// Réglages, every family and every page, in light and dark (lot 7, 19/11), with an invented world: made-up accounts,
/// senders, journal and studios. Not part of `make check`:
/// `POLHUB_LIVE=1 POLHUB_SNAPSHOTS=<dossier> swift test --filter SettingsScreenTests` (live: glass and toolbar).
/// Nothing is ever checked for real: the Diagnostic's states are set by hand, so that it never tests the micro or the
/// sound.
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"] != nil), .serialized)
struct SettingsScreenTests {
    static let size = NSSize(width: 1_000, height: 860)

    private func output() throws -> URL {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"]), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        return output
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func everyPage() async throws {
        let output = try output()
        let world = try InspirationTestWorld(name: "captures-reglages-lot7")
        defer { world.clean() }
        try world.fill()
        let lastRun = InspirationTestWorld.day(11, 19).addingTimeInterval(2 * 3_600)
        let inspiration = world.library(services: InspirationServices(status: {
            [InspirationStatusLine(id: "awwwards", name: "Awwwards", lastRun: lastRun, added: 1)]
        }))
        try await waitUntil { inspiration.loaded.count == 3 && inspiration.sources.count == 3 }

        let database = world.database
        let calendar = CalendarStore(database)
        try calendar.addAccount(email: "paul@atelier-exemple.fr", at: Date())
        try calendar.setGrantedScopes(email: "paul@atelier-exemple.fr",
                                      scopes: "openid https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/gmail.modify")
        try calendar.recordSync(email: "paul@atelier-exemple.fr", syncToken: "jeton", error: nil, at: Date().addingTimeInterval(-600))
        try calendar.addAccount(email: "perso.exemple@gmail.com", at: Date().addingTimeInterval(1))
        try calendar.recordSync(email: "perso.exemple@gmail.com", syncToken: "jeton", error: nil, at: Date().addingTimeInterval(-900))
        let mailStore = MailStore(database)
        try mailStore.remember(address: "lettre@lettre-exemple.fr", tab: .some("notifications"), at: Date())
        try mailStore.remember(address: "camille@studio-exemple.fr", tab: .some("personnes"), images: true, at: Date())

        let meetings = MeetingStore(database)
        try meetings.addJournal(JournalEntry(createdAt: Date().addingTimeInterval(-7_200), kind: .info, message: "Polhub est passé de 0.41.0 à 0.42.0."))
        try meetings.addJournal(JournalEntry(createdAt: Date().addingTimeInterval(-3_600), kind: .missed,
                                             message: "Réunion « Point hebdo » manquée : Polhub n'était pas ouvert."))
        try meetings.addJournal(JournalEntry(createdAt: Date().addingTimeInterval(-600), kind: .alert,
                                             message: "Une autorisation manque depuis la mise à jour de macOS ou de Dia : ouvre le Diagnostic."))
        let library = MeetingLibrary(store: meetings)
        let projects = ProjectLibrary(store: ProjectStore(database), meetings: meetings)
        let agenda = AgendaLibrary(database: database)
        let root = world.root.appending(path: "mails", directoryHint: .isDirectory)
        let mails = MailLibrary(agenda: agenda, root: root, defaults: try #require(UserDefaults(suiteName: "reglages-lot7-\(UUID().uuidString)")), flavor: .dev)
        let colinDefaults = try #require(UserDefaults(suiteName: "reglages-lot7-colin-\(UUID().uuidString)"))
        colinDefaults.set(true, forKey: Preferences.Key.colinOn)
        let thread = ColinThread(database: database, runner: nil, defaults: colinDefaults)
        try thread.saveKnowledge("Écrire court, à mon ton.\nMon lien de rendez-vous : https://exemple.fr/rdv")
        let probe = ColinProbeControl(defaults: colinDefaults, isQuiet: { true }, start: { _, _ in nil }, stop: {}, report: { nil })
        let updates = UpdateService(current: SemanticVersion("0.42.0")!, fetch: { Data("[]".utf8) }, isIdle: { true },
                                    defaults: try #require(UserDefaults(suiteName: "reglages-lot7-maj-\(UUID().uuidString)")))
        let startup = StartupControl(read: { true }, write: { _ in nil })
        let model = DiagnosticModel(amplitude: 0.0000316, showsRelaunch: true, relaunchEnabled: { true }, setRelaunch: { _ in nil },
                                    missingModels: { [] })
        // Set by hand: the page never runs a check of its own (no micro, no sound).
        for item in [ChecklistItem.microphone, .systemAudio, .models, .relaunch] { model.set(item, .ok) }
        model.set(.diaAutomation, .notRunning)
        let logosFolder = world.root.appending(path: "logos", directoryHint: .isDirectory)
        let quiet = try #require(UserDefaults(suiteName: "reglages-lot7-logos-\(UUID().uuidString)"))
        quiet.set(false, forKey: Preferences.Key.projectLogos)
        let logos = ProjectLogos(folder: logosFolder, database: nil, defaults: quiet)
        let router = WindowRouter()
        try await waitUntil { agenda.accounts.count == 2 && mails.senders.count == 2 }
        // Réglages › iPhone (20/11): switched on, an iPhone paired, a QR code waiting; nothing listens (never started).
        let phoneDefaults = try #require(UserDefaults(suiteName: "reglages-iphone-\(UUID().uuidString)"))
        phoneDefaults.set(true, forKey: PhoneAccess.enabledKey)
        phoneDefaults.set("https://mac.exemple.ts.net:8443", forKey: PhoneAccess.addressKey)
        let phone = PhoneAccess(database: agenda.database, agenda: agenda, mails: mails, appVersion: "0.51.0", defaults: phoneDefaults, port: 0)
        let (_, seen) = phone.store.pair(name: "iPhone")
        _ = phone.store.device(for: seen)
        phone.pair()

        func window(_ startup: StartupControl) -> some View {
            MainWindowView(library: library, projects: projects, agenda: agenda, mails: mails, thread: thread, colinProbe: probe,
                           inspiration: inspiration, updates: updates, startup: startup, phone: phone, router: router, paths: world.paths) {
                DiagnosticView(model: model, colin: probe) {}
            }
            .environment(\.projectLogos, logos)
        }
        let panes: [SettingsPane?] = [nil] + SettingsPane.allCases.map(Optional.some)
        for dark in [false, true] {
            for pane in panes {
                router.openSettings(pane)
                try await LiveWindow.capture(window(startup), to: output.appending(path: "reglages-\(pane?.rawValue ?? "familles")\(dark ? "-sombre" : "").png"),
                                             size: Self.size, dark: dark, wait: .milliseconds(1_800))
            }
        }
        // The narrowest window, on the pages with the most helps: two lines at most, beside a list too.
        for pane in [SettingsPane.general, .notifications, .mails, .colin, .meetings, .inspiration] {
            router.openSettings(pane)
            try await LiveWindow.capture(window(startup), to: output.appending(path: "reglages-\(pane.rawValue)-etroit.png"),
                                         size: NSSize(width: MainWindowView<EmptyView>.minimumWidth, height: 860))
        }
        // During a meeting, the relaunch waits, in Général and in the Diagnostic alike (lot 7, 19/11).
        let busy = StartupControl(read: { true }, write: { _ in nil }, busy: { true })
        _ = busy.ask(false)
        for pane in [SettingsPane.general, .diagnostic] {
            router.openSettings(pane)
            try await LiveWindow.capture(window(busy), to: output.appending(path: "reglages-\(pane.rawValue)-reunion.png"), size: Self.size)
        }
        // The summaries cannot be written: the problem in place of the help.
        library.summaryUnavailable = "Apple Intelligence est coupée dans Réglages Système."
        router.openSettings(.meetings)
        try await LiveWindow.capture(window(startup), to: output.appending(path: "reglages-meetings-indisponible.png"), size: Self.size)
    }
}
