import Testing
@testable import Domain

@Suite struct MeetingTitleTests {
    @Test func titlesComeFromTheTab() {
        #expect(MeetingTitle.make(tabTitle: "Meet – Point hebdo Studio", code: "abc-defg-hij", source: .dia, micOnly: false) == "Point hebdo Studio")
        #expect(MeetingTitle.make(tabTitle: "Meet - Point hebdo", code: "abc-defg-hij", source: .dia, micOnly: false) == "Point hebdo")
        #expect(MeetingTitle.make(tabTitle: "Meet – abc-defg-hij", code: "abc-defg-hij", source: .dia, micOnly: false) == "Google Meet")
        #expect(MeetingTitle.make(tabTitle: nil, code: nil, source: .dia, micOnly: true) == "Réunion dans Dia")
        #expect(MeetingTitle.make(tabTitle: nil, code: nil, source: .wholeMac, micOnly: false) == "Enregistrement manuel")
    }

    /// A title the calendar may replace (13/11).
    @Test func genericTitlesAreRecognised() {
        for title in ["Google Meet", "Réunion dans Dia", "Enregistrement manuel", "abc-defg-hij", "  "] {
            #expect(MeetingTitle.isGeneric(title), "« \(title) »")
        }
        #expect(!MeetingTitle.isGeneric("RDV de cadrage"))
    }
}
