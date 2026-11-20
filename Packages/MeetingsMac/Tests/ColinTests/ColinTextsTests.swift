import Foundation
import Testing
@testable import Colin

/// Colin's fixed texts: several projects change in one question (Paul, 20/11; before, one project per question).
@Suite struct ColinTextsTests {
    @Test func severalProjectsChangeInOneQuestion() {
        #expect(ColinTexts.system.contains("plusieurs projets d'un coup"))
        #expect(!ColinTexts.system.contains("un projet par question"))
        #expect(!ColinTexts.system.contains("Paul"))
    }
}
