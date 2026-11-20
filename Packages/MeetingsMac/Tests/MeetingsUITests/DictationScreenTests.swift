import AppKit
import Foundation
import Persistence
import SwiftUI
import Testing
@testable import MeetingsUI

/// La fenêtre de la Dictée, en capture (20/11, redessinée après l'essai de Paul).
/// `HUB_LIVE=1 HUB_SNAPSHOTS=<dossier> swift test --filter DictationScreenTests`.
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["HUB_LIVE"] == "1")) struct DictationScreenTests {
    @Test func theWindowWhileTalkingAndWriting() async throws {
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["HUB_SNAPSHOTS"]), isDirectory: true)
        let service = DictationService(library: DictationLibrary(database: try AppDatabase.inMemory()), helper: URL(fileURLWithPath: "/usr/bin/false"))
        for (name, phase, text) in [("dictee-fenetre-ecoute", DictationService.Phase.listening,
                                     "Bonjour Camille, je t'envoie le devis du site ce soir, et on se cale un point demain à dix heures pour en parler avec l'atelier."),
                                    ("dictee-fenetre-ecriture", .writing, "Ouvre le projet hub et lance Vigie.")] {
            service.show(phase, partial: text, level: 0.6)
            try await LiveWindow.capture(DictationPillView(service: service).padding(40).background(Color.gray.opacity(0.35)),
                                         to: folder.appending(path: "\(name).png"), size: NSSize(width: 600, height: 260), wait: .milliseconds(900))
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    }

    /// 20/11 au soir (Paul : « des cartes ») : l'historique par jour, la mémoire, les réglages. Données inventées.
    @Test func thePageInCardsAndItsSettings() async throws {
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["HUB_SNAPSHOTS"]), isDirectory: true)
        let library = DictationLibrary(database: try AppDatabase.inMemory())
        let now = Date()
        library.keep(DictationRow(text: "Ajoute une action : relancer l'atelier pour les photos.", raw: "", app: "Code", seconds: 4.2,
                                  createdAt: now.addingTimeInterval(-120)))
        library.keep(DictationRow(text: "Bonjour Camille,\n\nJe t'envoie le devis du site ce soir. On se cale un point demain à 10 h 30 ?\n\nBonne soirée",
                                  raw: "", app: "Mail", seconds: 14, createdAt: now.addingTimeInterval(-3_600)))
        library.keep(DictationRow(text: "Penser à la nouvelle page d'accueil et au formulaire de contact.", raw: "", app: nil, seconds: 62,
                                  createdAt: now.addingTimeInterval(-90_000), file: "memo-vocal.m4a"))
        library.addWord("Atelier Exemple")
        library.addWord("Camille")
        let service = DictationService(library: library, helper: URL(fileURLWithPath: "/usr/bin/false"))
        try await waitUntil { library.history.count == 3 && library.words.count == 2 }
        try await LiveWindow.capture(DictationHistory(library: library, service: service, query: ""),
                                     to: folder.appending(path: "dictee-page-historique.png"), size: NSSize(width: 900, height: 820), wait: .milliseconds(1_200))
        try await LiveWindow.capture(DictationMemory(library: library),
                                     to: folder.appending(path: "dictee-page-memoire.png"), size: NSSize(width: 900, height: 820), wait: .milliseconds(1_200))
        try await LiveWindow.capture(DictationSettingsPane(service: service),
                                     to: folder.appending(path: "dictee-reglages.png"), size: NSSize(width: 760, height: 1_700), wait: .milliseconds(1_200))
    }
}
