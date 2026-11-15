import Combine
import Domain
import Foundation
import Persistence
import Summarization
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

    /// 15/11: the second line says when, how long, and the project.
    @Test func theSecondLineSaysWhenHowLongAndTheProject() {
        let meeting = row("A", date(13, 9))
        let time = meeting.startedAt.formatted(date: .omitted, time: .shortened)
        #expect(MeetingListModel.metaText(meeting, project: "Refonte du site", now: date(13, 12)) == "\(time) · 42 min · Refonte du site")
        #expect(MeetingListModel.metaText(meeting, project: nil, now: date(13, 12)) == "\(time) · 42 min")
    }

    /// Paul, 15/11: the newest meeting opens by itself when none is chosen, or when the one chosen is gone.
    @Test func theNewestMeetingOpensWhenNoneIsChosen() {
        let rows = [row("B", date(13, 10)), row("A", date(13, 9))]
        #expect(MeetingListModel.meetingToOpen(selection: nil, rows: rows) == rows[0].id)
        #expect(MeetingListModel.meetingToOpen(selection: rows[1].id, rows: rows) == rows[1].id)
        #expect(MeetingListModel.meetingToOpen(selection: UUID(), rows: rows) == rows[0].id)
        let asked = UUID()
        #expect(MeetingListModel.meetingToOpen(selection: asked, rows: []) == asked)
        #expect(MeetingListModel.meetingToOpen(selection: nil, rows: []) == nil)
    }

    @Test func aMeetingSentToTheTrashLeavesTheNextOneOpen() {
        let rows = [row("C", date(13, 11)), row("B", date(13, 10)), row("A", date(13, 9))]
        #expect(MeetingListModel.neighbor(of: rows[1].id, in: rows) == rows[2].id)
        #expect(MeetingListModel.neighbor(of: rows[2].id, in: rows) == rows[1].id)
        #expect(MeetingListModel.neighbor(of: rows[0].id, in: [rows[0]]) == nil)
    }

    /// 15/11: under a meeting, its summary's first lines, or where it is.
    @Test func theSummaryLineSaysTheSummaryOrWhereItIs() {
        let id = UUID(), now = date(13, 12)
        func job(_ state: SummaryState) -> SummaryJobRow { SummaryJobRow(meetingID: id, state: state, updatedAt: now) }
        #expect(MeetingListModel.summaryLine(overview: "Le client valide.", job: job(.done)) == .init(text: "Le client valide.", kind: .ready))
        #expect(MeetingListModel.summaryLine(overview: "Venu du coffre.", job: nil) == .init(text: "Venu du coffre.", kind: .ready))
        #expect(MeetingListModel.summaryLine(overview: "Ancien.", job: job(.running)) == .init(text: "Ancien.", kind: .writing))
        #expect(MeetingListModel.summaryLine(overview: nil, job: job(.running))?.kind == .writing)
        #expect(MeetingListModel.summaryLine(overview: nil, job: job(.queued))?.kind == .waiting)
        #expect(MeetingListModel.summaryLine(overview: nil, job: job(.failed))?.kind == .failed)
        #expect(MeetingListModel.summaryLine(overview: nil, job: job(.done)) == nil)
        #expect(MeetingListModel.summaryLine(overview: nil, job: nil) == nil)
    }

    /// 15/11: the list shows each meeting's summary first line and its state, read apart from `MeetingRow`.
    @Test func theLibraryPublishesTheSummariesFirstLinesAndTheirState() async throws {
        let database = try AppDatabase.inMemory()
        let store = MeetingStore(database)
        let library = MeetingLibrary(store: store)
        let meeting = row("Point hebdo", date(13, 9))
        try store.save(meeting)
        try SummaryStore(database).start(meetingID: meeting.id, at: date(13, 10))
        try SummaryStore(database).finish(meetingID: meeting.id, summary: "## Résumé\n\nLe client valide la refonte.\n\n## Décisions\n\n- Garder WordPress.",
                                          actions: [], at: date(13, 10))
        for _ in 0..<50 where library.overviews.isEmpty || library.summaryJobs.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(library.overviews[meeting.id] == "Le client valide la refonte.")
        #expect(library.summaryJobs[meeting.id]?.state == .done)
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

/// A stand-in for Apple's model: a short pause for each part, so that the progress can be followed.
struct PacedEngine: SummaryEngine {
    var unavailableReason: String? { nil }

    func notes(for chunk: String, part: Int, of count: Int) async throws -> String {
        try await Task.sleep(for: .milliseconds(20))
        return "notes \(part)/\(count)"
    }

    func summary(of notes: [String], title: String) async throws -> MeetingSummary {
        MeetingSummary(overview: "\(title) : \(notes.count) parties.", decisions: [], actions: [])
    }
}

@MainActor @Suite struct SummaryProgressTests {
    /// 15/11: the page follows the summary part by part, and forgets it once it is written.
    @Test func theLibraryFollowsTheSummaryPartByPart() async throws {
        let database = try AppDatabase.inMemory()
        let store = MeetingStore(database)
        let start = Date(timeIntervalSince1970: 1_794_562_920)
        let meeting = MeetingRow(createdAt: start, status: .ended, source: .dia, candidateKey: "k", title: "Atelier", startedAt: start,
                                 endedAt: start.addingTimeInterval(3_600), transcribedAt: start.addingTimeInterval(3_700))
        try store.save(meeting)
        try TranscriptStore(database).replaceUtterances(meetingID: meeting.id, (0..<60).map { index in
            UtteranceRow(meetingID: meeting.id, speaker: index % 2 == 0 ? .moi : .autres, startMs: index * 30_000, endMs: index * 30_000 + 25_000,
                         text: String(repeating: "On reprend la maquette de l'accueil et le devis. ", count: 10), doubtful: false)
        })
        let library = MeetingLibrary(store: store)
        let queue = SummaryQueue(database: database, engine: PacedEngine(), now: { start })
        library.summaries = queue
        var seen: [SummaryProgress] = []
        let watch = library.$summaryProgress.sink { progress in
            if let step = progress[meeting.id], seen.last != step { seen.append(step) }
        }
        defer { watch.cancel() }
        await queue.wake()
        for _ in 0..<200 where try SummaryStore(database).job(meetingID: meeting.id)?.state != .done {
            try await Task.sleep(for: .milliseconds(20))
        }
        for _ in 0..<100 where library.summaryProgress[meeting.id] != nil || seen.last?.finishing != true {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(seen.count >= 3 && seen.first?.done == 0 && seen.last?.finishing == true)
        #expect(seen.map(\.done) == seen.map(\.done).sorted())
        #expect(library.summaryProgress[meeting.id] == nil)
    }
}
