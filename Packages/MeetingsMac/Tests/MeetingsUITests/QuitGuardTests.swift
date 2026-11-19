import Foundation
import Pipeline
import Testing
@testable import MeetingsUI

/// ⌘Q while something would be lost (audit of 19/11): a meeting being recorded, a mail about to leave. Quitting then
/// asks first; the rest of the time it quits.
@Suite struct QuitGuardTests {
    @Test func quittingDuringARecordingOrASendAsksFirst() throws {
        let recording = try #require(QuitGuard.question(status: .recording(title: "Point d'équipe", since: Date()), sending: false))
        #expect(recording.title == "Polhub enregistre une réunion" && recording.stay == "Continuer l'enregistrement" && recording.quit == "Quitter quand même")
        #expect(QuitGuard.question(status: .presumedEnded(title: "Point d'équipe"), sending: false) == recording)
        // The recording is said first: it is what would be lost for good.
        #expect(QuitGuard.question(status: .recording(title: "Point", since: Date()), sending: true) == recording)
        let sending = try #require(QuitGuard.question(status: .idle, sending: true))
        #expect(sending.title == "Un mail part dans un instant" && sending.stay == "Attendre l'envoi")
    }

    @Test func otherwiseQuittingQuits() {
        #expect(QuitGuard.question(status: .idle, sending: false) == nil)
        #expect(QuitGuard.question(status: .prompting(title: "Point"), sending: false) == nil)
        #expect(QuitGuard.question(status: .paused(until: Date()), sending: false) == nil)
    }
}
