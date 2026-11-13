import Testing
@testable import Domain

@Suite struct MeetLinkTests {
    @Test func parsesMeetLinks() {
        #expect(MeetLink.parse("https://meet.google.com/abc-defg-hij") == MeetLink(code: "abc-defg-hij", authUser: nil))
        #expect(MeetLink.parse("https://meet.google.com/ABC-DEFG-HIJ?authuser=1&hs=122") == MeetLink(code: "abc-defg-hij", authUser: "1"))
        #expect(MeetLink.parse("https://meet.google.com/abc-defg-hij?authuser=paul%40example.com")?.authUser == "paul@example.com")
        #expect(MeetLink.parse("https://meet.google.com/meet/abc-defg-hij")?.code == "abc-defg-hij")
        #expect(MeetLink.parse("https://meet.google.com/landing") == MeetLink(code: nil, authUser: nil))
        #expect(MeetLink.parse("https://meet.google.com/")?.isRoom == false)
        #expect(MeetLink.parse("https://calendar.google.com/calendar/u/0/r") == nil)
        #expect(MeetLink.parse("https://evil.example/meet.google.com/abc-defg-hij") == nil)
        #expect(MeetLink.parse("pas une url") == nil)
    }
}
