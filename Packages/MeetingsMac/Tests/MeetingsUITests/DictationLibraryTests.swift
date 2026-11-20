import AudioCapture
import Domain
import HubDesign
import Foundation
import Persistence
import Testing
@testable import MeetingsUI

/// 20/11 : la Dictée dans hub. Sa mémoire nourrit Whisper ; son modèle est celui de Réunions ; sa section vient en
/// dernier, sans raccourci.
@MainActor @Suite struct DictationLibraryTests {
    @Test func thePromptHasPaulsWordsThenHubsThenTheNamesItKnows() async throws {
        let database = try AppDatabase.inMemory()
        _ = try ProjectStore(database).addProject(name: "Site vitrine", status: .priorite2, at: Date())
        let library = DictationLibrary(database: database)
        library.addWord("Atelier Exemple")
        try await waitUntil { library.words.count == 1 }
        library.refreshKnown()
        #expect(library.prompt.hasPrefix("Atelier Exemple, hub, Vigie"))
        #expect(library.prompt.contains("Site vitrine"))
        // The first corrections, once.
        #expect(library.corrections.contains { $0.heard == "mythe" && $0.written == "Meet" })
    }

    /// 20/11 au soir : le premier micro branché dans l'ordre de Paul ; sans ordre, celui du système.
    @Test func theFirstConnectedMicrophoneOfPaulsOrderRecords() throws {
        let defaults = try #require(UserDefaults(suiteName: "dictee-micros-\(UUID().uuidString)"))
        let settings = DictationSettings(defaults: defaults)
        let connected = [Microphone(uid: "interne", name: "Micro du Mac"), Microphone(uid: "casque", name: "Casque")]
        #expect(settings.microphone(connected: connected) == nil)
        defaults.set("absent\ncasque\ninterne", forKey: Preferences.Key.dictationMicrophones)
        #expect(settings.microphone(connected: connected) == "casque")
        #expect(DictationSettings.ordered(settings.microphones, connected: connected, known: ["absent": "Ancien micro"]).map(\.name)
            == ["Ancien micro", "Casque", "Micro du Mac"])
        #expect(settings.autoStop == 10 && settings.paragraphPause == 3 && settings.rules == .standard)
        defaults.set(0.0, forKey: Preferences.Key.dictationAutoStop)
        #expect(settings.autoStop == nil)
    }

    /// 20/11 au soir : « Garder l'historique 30 jours » emporte les dictées et leur son ; un son sans dictée part aussi.
    @Test func oldDictationsGoWithTheirSounds() async throws {
        let sounds = FileManager.default.temporaryDirectory.appending(path: "dictee-sons-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sounds, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sounds) }
        let library = DictationLibrary(database: try AppDatabase.inMemory(), sounds: sounds)
        let now = Date()
        let old = DictationRow(text: "Ancienne.", raw: "", app: nil, seconds: 1, createdAt: now.addingTimeInterval(-40 * 86_400))
        let recent = DictationRow(text: "Récente.", raw: "", app: nil, seconds: 1, createdAt: now.addingTimeInterval(-3_600))
        let orphan = UUID()
        for row in [old, recent] { library.keep(row) }
        for id in [old.id, recent.id, orphan] {
            FileManager.default.createFile(atPath: library.soundURL(id).path(percentEncoded: false), contents: Data([1]),
                                           attributes: [.creationDate: now.addingTimeInterval(-600)])
        }
        try await waitUntil { library.history.count == 2 }
        library.purge(keepDays: 30, now: now)
        try await waitUntil { library.history.count == 1 }
        #expect(library.history.map(\.text) == ["Récente."])
        #expect(library.hasSound(recent) && !library.hasSound(old))
        #expect(!FileManager.default.fileExists(atPath: library.soundURL(orphan).path(percentEncoded: false)))
        library.delete(recent)
        #expect(!library.hasSound(recent))
    }

    @Test func theLastDictationIsCopied() async throws {
        let library = DictationLibrary(database: try AppDatabase.inMemory())
        #expect(!library.copyLast())
        library.keep(DictationRow(text: "Bonjour.", raw: "bonjour", app: "Mail", seconds: 1, createdAt: Date()))
        try await waitUntil { library.history.count == 1 }
        #expect(library.copyLast())
    }

    @Test func theModelGoesWithTheLastOfReunionsAndDictee() {
        #expect(AddOnTexts.takingModel(.meetings, installed: [.meetings]) != nil)
        #expect(AddOnTexts.takingModel(.meetings, installed: [.meetings, .dictation]) == nil)
        #expect(AddOnTexts.takingModel(.dictation, installed: [.dictation])?.contains("Dictée") == true)
        #expect(AddOnTexts.takingModel(.projects, installed: [.projects]) == nil)
    }

    @Test func theDictationComesLastWithoutAKey() {
        let items = SidebarItem.visible(hasProjects: true, hasAgenda: true, hasMails: true, hasInspiration: true, hasDictation: true)
        #expect(items.last == .dictation)
        #expect(SidebarItem.dictation.shortcut == nil)
        #expect(SidebarItem.calendar.shortcut == 4)
        #expect(SettingsPane.families(hasAgenda: true, hasProjects: true, hasDictation: true)[1].last == .dictation)
    }

    @Test func theHelpersLinesArriveWhole() {
        let splitter = LineSplitter()
        #expect(splitter.add(Data(#"{"ready":{}}"#.utf8) + Data("\n{\"lev".utf8)) == [#"{"ready":{}}"#])
        #expect(splitter.add(Data("el\":0.5}\n".utf8)) == [#"{"level":0.5}"#])
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }
}
