import Testing
@testable import MeetingDetection

@Suite struct DiaTabParserTests {
    let fs = "\u{1F}", rs = "\u{1E}"

    @Test func parsesTwoTabsAndDeduplicatesByTabID() {
        let raw = ["w1", "t1", "false", "true", "false", "https://meet.google.com/abc-defg-hij", "Point hebdo - Google Meet"].joined(separator: fs) + rs
            + ["w1", "t2", "true", "false", "true", "https://meet.google.com/landing", "Meet"].joined(separator: fs) + rs
            + ["w1", "t1", "false", "true", "false", "https://meet.google.com/abc-defg-hij", "Point hebdo - Google Meet"].joined(separator: fs) + rs
        let tabs = DiaTabParser.parse(raw)
        #expect(tabs.map(\.tabID) == ["t1", "t2"])
        #expect(tabs[0].url == "https://meet.google.com/abc-defg-hij")
        #expect(tabs[0].windowID == "w1" && tabs[0].isFocused && !tabs[0].isLoading)
        #expect(tabs[1].isLoading && tabs[1].isPinned && !tabs[1].isFocused)
    }

    // Review Focus 3 : un titre inattendu ne fait pas perdre l'onglet.
    @Test func parsesAwkwardTitles() {
        let long = String(repeating: "é", count: 5_000)
        for title in ["Point\nhebdo — 🚀", "", long] {
            let raw = ["w", "t", "false", "false", "false", "https://meet.google.com/abc-defg-hij", title].joined(separator: fs) + rs
            #expect(DiaTabParser.parse(raw).first?.title == title)
        }
    }

    @Test func skipsMalformedRecords() {
        #expect(DiaTabParser.parse("w\u{1F}t\u{1E}").isEmpty)
        #expect(DiaTabParser.parse("").isEmpty)
    }
}
