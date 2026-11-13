import Domain
import Foundation
import Persistence
import Testing
@testable import MeetingsUI

@Suite struct SearchModelTests {
    let day = Date(timeIntervalSince1970: 1_794_562_920)

    func hit(_ meeting: UUID, _ title: String, daysAgo: Double, at seconds: Int) -> SearchHit {
        SearchHit(meetingID: meeting, title: title, startedAt: day.addingTimeInterval(-daysAgo * 86_400), startMs: seconds * 1_000,
                  speaker: .autres, excerpt: "… «budget» …")
    }

    @Test func hitsAreGroupedByMeetingNewestFirst() {
        let (old, recent) = (UUID(), UUID())
        let groups = SearchModel.groups([hit(old, "Lundi", daysAgo: 3, at: 10), hit(recent, "Jeudi", daysAgo: 0, at: 5),
                                         hit(old, "Lundi", daysAgo: 3, at: 50)])
        #expect(groups.map(\.title) == ["Jeudi", "Lundi"])
        #expect(groups.last?.excerpts.map(\.startMs) == [10_000, 50_000])
    }

    @Test func atMostFiveExcerptsPerMeeting() {
        let id = UUID()
        let groups = SearchModel.groups((0..<9).map { hit(id, "Lundi", daysAgo: 1, at: $0) })
        #expect(groups.first?.excerpts.count == 5 && groups.first?.more == 4)
    }

    @Test func aQueryOfOneLetterSearchesNothing() {
        #expect(!SearchModel.shouldSearch(" a "))
        #expect(!SearchModel.shouldSearch(""))
        #expect(SearchModel.shouldSearch("ok"))
    }
}
