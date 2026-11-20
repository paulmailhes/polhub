import Domain
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
