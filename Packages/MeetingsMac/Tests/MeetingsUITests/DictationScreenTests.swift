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
}
