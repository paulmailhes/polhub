import Domain
import Foundation
import Pipeline
import GRDB
import Persistence
import Summarization

public struct DaySection: Equatable, Identifiable, Sendable {
    public var id: String { title }
    public let title: String
    public let rows: [MeetingRow]
}

public enum MeetingListModel {
    /// Meetings by day, the latest first: « Aujourd'hui », « Hier », then « Mardi 10 novembre ».
    public static func sections(_ rows: [MeetingRow], now: Date, calendar: Calendar) -> [DaySection] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        let formatter = DateFormatter()
        formatter.locale = calendar.locale ?? Locale(identifier: "fr_FR")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE d MMMM"
        let byDay = Dictionary(grouping: rows) { calendar.startOfDay(for: $0.startedAt) }
        return byDay.keys.sorted(by: >).map { day in
            let title: String
            if day == today {
                title = "Aujourd'hui"
            } else if day == yesterday {
                title = "Hier"
            } else {
                let text = formatter.string(from: day)
                title = text.prefix(1).uppercased() + text.dropFirst()
            }
            return DaySection(title: title, rows: (byDay[day] ?? []).sorted { $0.startedAt > $1.startedAt })
        }
    }

    public static func durationText(_ row: MeetingRow, now: Date) -> String {
        if row.status.isUnfinished { return "en cours" }
        guard let end = row.endedAt else { return "—" }
        return DurationText.short(Int(end.timeIntervalSince(row.startedAt)))
    }
}

/// The meetings and the journal, kept up to date from the base.
@MainActor
public final class MeetingLibrary: ObservableObject {
    @Published public private(set) var rows: [MeetingRow] = []
    @Published public private(set) var journal: [JournalEntry] = []
    /// The newest job of each meeting.
    @Published public private(set) var jobs: [UUID: JobRow] = [:]
    /// From the pop-up to the end of a meeting: transcriptions wait.
    @Published public var meetingActive = false
    public let store: MeetingStore
    public let transcripts: TranscriptStore
    /// Set by the app: « Réessayer » and « Retranscrire » go through it.
    public var queue: TranscriptionQueue?
    /// Set by the app: « Refaire le compte rendu » goes through it (14/11).
    public var summaries: SummaryQueue?
    /// Why no summary can be made (Apple Intelligence off…), said on the meeting's page.
    @Published public var summaryUnavailable: String?
    private var observations: [AnyDatabaseCancellable] = []

    public init(store: MeetingStore) {
        self.store = store
        transcripts = TranscriptStore(store.database)
        observations.append(store.observeRecent(limit: 500) { [weak self] rows in self?.rows = rows })
        observations.append(store.observeJournal(limit: 300) { [weak self] entries in self?.journal = entries })
        observations.append(transcripts.observeLatestJobs { [weak self] jobs in self?.jobs = jobs })
    }
}
