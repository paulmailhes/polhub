import Domain
import Foundation
import Persistence
import Testing
@testable import MeetingsUI

@MainActor @Suite struct MeetingListTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "fr_FR")
        return calendar
    }

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func row(_ title: String, _ start: Date, status: MeetingStatus = .ended, minutes: Double? = 42) -> MeetingRow {
        MeetingRow(createdAt: start, status: status, source: .dia, candidateKey: "k", title: title, startedAt: start,
                   endedAt: minutes.map { start.addingTimeInterval($0 * 60) })
    }

    @Test func meetingsAreGroupedByDay() {
        let rows = [row("A", date(13, 9)), row("B", date(13, 10, 2)), row("C", date(12, 15)), row("D", date(10, 11))]
        let sections = MeetingListModel.sections(rows, now: date(13, 12), calendar: calendar)
        #expect(sections.map(\.title) == ["Aujourd'hui", "Hier", "Mardi 10 novembre"])
        #expect(sections.first?.rows.map(\.title) == ["B", "A"])
    }

    @Test func durationsOfOngoingAndEndedMeetings() {
        #expect(MeetingListModel.durationText(row("A", date(13, 9)), now: date(13, 12)) == "42 min")
        #expect(MeetingListModel.durationText(row("A", date(13, 9), status: .recording, minutes: nil), now: date(13, 12)) == "en cours")
    }

    @Test func theLibraryPublishesNewMeetings() async throws {
        let store = MeetingStore(try AppDatabase.inMemory())
        let library = MeetingLibrary(store: store)
        try store.save(row("Point hebdo", date(13, 9)))
        for _ in 0..<50 where library.rows.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(library.rows.map(\.title) == ["Point hebdo"])
    }
}
