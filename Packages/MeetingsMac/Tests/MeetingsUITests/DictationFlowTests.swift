import Dictation
import Foundation
import HubDesign
import Persistence
import Testing
@testable import MeetingsUI

/// 21/11 : la Dictée de bout en bout, de la touche au texte, avec la vraie aide `hub-dictee` et un son joué comme un
/// micro — sans micro, sans son, sans fenêtre, sans presse-papiers. Deux versions du 20/11 ont cassé la Dictée sans
/// qu'un test le voie : celui-ci se lance avant chaque publication.
/// `HUB_DICTEE_HELPER=<hub-dictee> HUB_DICTEE_CLIP=<son.wav, « … l'atelier pour les photos. »> swift test --filter DictationFlowTests`
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["HUB_DICTEE_HELPER"] != nil)) struct DictationFlowTests {
    private func waitUntil(_ seconds: Double, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while !condition(), Date() < end { try await Task.sleep(for: .milliseconds(20)) }
        #expect(condition())
    }

    private func press(_ service: DictationService) {
        service.key(down: true)
        service.key(down: false)
    }

    @Test func theKeyStartsAtOnceAndTheTextComes() async throws {
        let environment = ProcessInfo.processInfo.environment
        let helper = URL(fileURLWithPath: try #require(environment["HUB_DICTEE_HELPER"]))
        let clip = try #require(environment["HUB_DICTEE_CLIP"])
        let defaults = try #require(UserDefaults(suiteName: "dictee-flux-\(UUID().uuidString)"))
        // Nothing heard, nothing touched on Paul's Mac.
        for key in [Preferences.Key.dictationSounds, Preferences.Key.dictationMuteMac, Preferences.Key.dictationPauseMedia,
                    Preferences.Key.dictationKeepSound] {
            defaults.set(false, forKey: key)
        }
        let library = DictationLibrary(database: try AppDatabase.inMemory())
        let service = DictationService(library: library, helper: helper, defaults: defaults)
        service.showsWindow = false
        service.testSource = clip
        var delivered: [String] = []
        service.testDelivery = { delivered.append($0) }
        service.start()
        defer { service.stop() }

        // The key answers within a second of the launch, long before Whisper is loaded.
        try await waitUntil(2) { service.phase == .ready }
        press(service)
        #expect(service.phase == .listening)
        try await waitUntil(2) { service.micOpen }
        #expect(DictationWindowContent(service.windowState).title == "Je t'écoute")
        try await Task.sleep(for: .seconds(4))
        press(service)
        #expect(service.phase == .writing)
        // Said while Whisper was loading, written as soon as it is there.
        try await waitUntil(90) { service.phase == .ready }
        #expect(delivered.count == 1 && delivered.first?.lowercased().contains("atelier") == true)
        #expect(service.whisperLoaded)

        // A second one, Whisper loaded: the words come while the sound plays, and the text follows the key closely.
        press(service)
        try await waitUntil(2) { service.micOpen }
        try await waitUntil(3) { !service.partial.isEmpty }
        try await Task.sleep(for: .seconds(3))
        let pressed = Date()
        press(service)
        try await waitUntil(5) { service.phase == .ready }
        #expect(Date().timeIntervalSince(pressed) < 2)
        #expect(delivered.count == 2 && delivered.last?.lowercased().contains("photos") == true)
        try await waitUntil(2) { library.history.count == 2 }

        // Given up with Échap: nothing is written, and the next press starts again.
        press(service)
        try await waitUntil(2) { service.micOpen }
        service.escape()
        #expect(service.phase == .ready)
        press(service)
        #expect(service.phase == .listening)
        service.escape()
        try await Task.sleep(for: .milliseconds(300))
        #expect(delivered.count == 2)
    }
}
