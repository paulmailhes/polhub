import Foundation
import Testing
@testable import Colin

/// Colin's fixed texts (final review of step 3, 18/11): a request on several projects is made one project per
/// question — the lock refuses a change outside the project he read.
@Suite struct ColinTextsTests {
    @Test func severalProjectsAreOnePerQuestion() {
        #expect(ColinTexts.system.contains("un projet par question"))
        #expect(!ColinTexts.system.contains("Paul"))
    }
}
