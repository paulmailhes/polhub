import Domain
import Foundation
import Testing
@testable import Persistence

@Suite struct MeetingStoreTests {
    let base = Date(timeIntervalSince1970: 1_763_026_920)   // 13/11/2025 10:42 (Paris), un instant quelconque

    func meeting(_ title: String, status: MeetingStatus = .ended, startedAt: Date? = nil, deleted: Bool = false) -> MeetingRow {
        let start = startedAt ?? base
        return MeetingRow(
            createdAt: start, status: status, source: .dia, candidateKey: "t/abc-defg-hij",
            title: title, startedAt: start, deletedAt: deleted ? start : nil
        )
    }

    func sameInstant(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): abs(a.timeIntervalSince(b)) < 0.001
        default: false
        }
    }

    @Test func storesAndReadsBackAMeeting() throws {
        let store = MeetingStore(try AppDatabase.inMemory())
        var row = meeting("Point hebdo Studio")
        row.meetCode = "abc-defg-hij"
        row.endedAt = base.addingTimeInterval(2_520.25)
        row.endReason = .tabClosed
        try store.save(row)
        let back = try #require(try store.meeting(id: row.id))
        #expect(back.id == row.id && back.title == "Point hebdo Studio" && back.meetCode == "abc-defg-hij")
        #expect(back.status == .ended && back.endReason == .tabClosed && back.source == .dia)
        #expect(sameInstant(back.startedAt, row.startedAt) && sameInstant(back.endedAt, row.endedAt))
    }

    @Test func recentSkipsSoftDeletedMeetingsNewestFirst() throws {
        let store = MeetingStore(try AppDatabase.inMemory())
        try store.save(meeting("A", startedAt: base))
        try store.save(meeting("B", startedAt: base.addingTimeInterval(60), deleted: true))
        try store.save(meeting("C", startedAt: base.addingTimeInterval(120)))
        #expect(try store.recent(limit: 10).map(\.title) == ["C", "A"])
    }

    @Test func softDeleteHidesAMeeting() throws {
        let store = MeetingStore(try AppDatabase.inMemory())
        let row = meeting("A")
        try store.save(row)
        try store.softDelete(id: row.id, at: base.addingTimeInterval(10))
        #expect(try store.recent(limit: 10).isEmpty)
        #expect(sameInstant(try store.meeting(id: row.id)?.deletedAt, base.addingTimeInterval(10)))
    }

    @Test func unfinishedListsPendingRecordingAndPresumedEnded() throws {
        let store = MeetingStore(try AppDatabase.inMemory())
        for (index, status) in MeetingStatus.allCases.enumerated() {
            try store.save(meeting(status.rawValue, status: status, startedAt: base.addingTimeInterval(Double(index))))
        }
        #expect(Set(try store.unfinished().map(\.status)) == [.pending, .recording, .presumedEnded])
    }

    @Test func journalComesNewestFirst() throws {
        let store = MeetingStore(try AppDatabase.inMemory())
        try store.addJournal(JournalEntry(createdAt: base, kind: .info, message: "un"))
        try store.addJournal(JournalEntry(createdAt: base.addingTimeInterval(5), kind: .missed, message: "deux"))
        #expect(try store.journal(limit: 10).map(\.message) == ["deux", "un"])
    }

    @Test func neverCodesRoundTrip() throws {
        let store = MeetingStore(try AppDatabase.inMemory())
        try store.addNeverCode("abc-defg-hij", at: base)
        try store.addNeverCode("abc-defg-hij", at: base)
        #expect(try store.neverCodes() == ["abc-defg-hij"])
    }

    @Test func memorySamplesAreKept() throws {
        let store = MeetingStore(try AppDatabase.inMemory())
        try store.addMemorySample(MemorySample(at: base, pressure: "normal", freeBytes: 1, activeBytes: 2, inactiveBytes: 3,
                                               wiredBytes: 4, compressedBytes: 5, swapUsedBytes: 6))
        #expect(try store.memorySampleCount() == 1)
    }

    @Test func theDevFlavorNeverTouchesTheRealData() {
        #expect(AppPaths.standard(.dev).database.path.contains("/Application Support/Polhub-dev/"))
        #expect(AppPaths.standard(.prod).meetings.path.hasSuffix("/Application Support/Polhub/Reunions"))
        #expect(AppPaths.standard(.dev).database != AppPaths.standard(.prod).database)
        #expect(AppPaths.standard(.prod).logs.path.hasSuffix("/Library/Logs/Polhub"))
    }
}
