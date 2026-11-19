import Foundation
import MeetingDetection
import Testing
@testable import Pipeline

/// The detection journal (audit of 19/11): what the detector saw and did, without a meeting's code, its title, an
/// address or the rest of a link. A code becomes a short mark, always the same for one code, so that a day's lines
/// still follow one meeting. Every code, title and address here is invented.
@Suite struct DetectionJournalTests {
    @Test func aTabIsJournaledWithoutItsCodeTitleOrAddress() {
        let tab = BrowserTab(windowID: "1", tabID: "2", url: "https://meet.google.com/abc-defg-hij?authuser=moi@exemple.fr&hs=1",
                             title: "Meet - Point \"Atelier Lune\"", isLoading: false, isFocused: true, isPinned: false)
        let text = MeetingCoordinator.journalText("\(DetectionInput.tabs([tab], complete: true))")
        #expect(!text.contains("abc-defg-hij") && !text.contains("moi@exemple.fr") && !text.contains("Atelier") && !text.contains("authuser"))
        #expect(text.contains("meet.google.com/meet-") && text.contains("isFocused: true") && text.contains("complete: true"))
        // The same code, the same mark; another code, another mark.
        let same = MeetingCoordinator.journalText("https://meet.google.com/abc-defg-hij")
        let other = MeetingCoordinator.journalText("https://meet.google.com/xyz-wxyz-xyz")
        #expect(same != other && text.contains(same))
    }

    @Test func aCandidateKeepsNeitherItsTitleNorItsAccount() {
        let candidate = MeetingCandidate(key: "2/abc-defg-hij", tabID: "2", code: "abc-defg-hij", authUser: "moi@exemple.fr",
                                         tabTitle: "Point avec Camille", source: .tab)
        let text = MeetingCoordinator.journalText("\(candidate)")
        #expect(!text.contains("abc-defg-hij") && !text.contains("moi@exemple.fr") && !text.contains("Camille"))
        #expect(text.contains("source: MeetingDetection.MeetingCandidate.Source.tab") || text.contains("source: .tab"))
    }
}
